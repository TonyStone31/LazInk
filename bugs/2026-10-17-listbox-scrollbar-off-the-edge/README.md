# The listbox never shows its scrollbar

Found 17 October 2026 on GTK3, first in ShellDesk's history list (18
rows, six in view).  A `TInkListBox` with more items than fit scrolls
with the wheel and the keyboard, but no scrollbar ever appears - not the
overlay bar GTK shows when the pointer moves over a list, not the
classic one with `GTK_OVERLAY_SCROLLING=0`.

A first note from that day guessed the bar was hidden for good by the
`set_no_show_all` and `hide` calls in `LCLGtkScrolledWindowNew`.  It is
not: asked directly, the bar reports `get_visible = True` (the LCL's own
`size_allocate` shows it whenever the policy allows one).  It is simply
laid out where it cannot be seen.

`before-after.png`: the same 40-item list, 300 by 200, with the pointer
over it.  Left as it was, right with the fix; the overlay bar is the thin
line at the right edge.

## Why

It is the LCL's GTK3 widgetset, not LazInk.  A plain `TListBox` does the
same as soon as one item is wider than the box, in every style
(`lbStandard`, `lbOwnerDrawFixed`, `lbOwnerDrawVariable`).  The listbox
is a `GtkScrolledWindow` round a `GtkTreeView`, with the horizontal
policy `GTK_POLICY_NEVER`.  GTK then counts the widest item's text toward
the scrolled window's preferred width.  The LCL's own `size_allocate`
(`gtk3lclscrolledwindow.inc`) sees the allocation fall short of that
width, calls GTK's layout with the width widened to the widest item,
then re-allocates the child to the real width - and leaves the vertical
scrollbar where the widened layout put it.  Measured: the bar was
allocated at x=418 (classic) and its overlay window at x=412 for a box
spanning x=10 to x=310.

A markup item is wider than its box nearly always: GTK measures the raw
item text, tags and all, and the items wrap only when LazInk draws them.
That is why every `TInkListBox` with a long item is hit while a short
plain list is not.

The report for Lazarus, with a standalone program and screenshots, is
`GIT/bug-reports/lazarus/gtk3-listbox-scrollbar`.

## The fix

On GTK3, `TInkListBox.CreateWnd` sets the scrolled window's horizontal
policy to `GTK_POLICY_EXTERNAL` after the handle is made.  Neither policy
shows a horizontal bar, but `EXTERNAL` keeps the child's width out of
the preferred width, so the widening never happens and the bar lands at
x=284 (classic) or x=293 (overlay window): the right edge of the box.
Verified with screenshots on a nested X server, overlay and classic,
with the pointer over the list; `tests/run.sh` passes.

Two things stay as they were, both LCL GTK3 behavior shared with a plain
`TListBox`:

- `ClientWidth` stays the full width with a classic scrollbar showing,
  so wrapped items run under the bar by its width (about 15 px).  With
  the overlay bar GTK uses by default, nothing is covered until the bar
  shows itself, as in every GTK program.
- The overlay bar is hidden until the pointer moves over the list.  That
  is GTK's design, not a fault.

## Should the listbox be custom drawn?

The README says LazInk draws everything on a `TCanvas`.  `TInkListBox`
is the one control for which that is only half true: its items are
drawn by LazInk, but the box, the selection model, the scrolling and the
scrollbar are the widgetset's `TCustomListBox`.  That split is where
this bug came from, and the earlier work-arounds in the same unit
(`DrawItem` clamping its rectangle to `ClientWidth`, the Cocoa
`SetItemIndex` lock, the GTK3 click counting) are the same shape.

What a canvas-drawn list would give:

- One behavior on every widgetset: the scrollbar is `TInkScrollBar`,
  colored from CSS like the page's, no overlay-or-classic question, no
  `ClientWidth` doubt.  The GTK3 report above stops mattering.
- Row height, wrapping and the selection are LazInk's, so items can be
  measured once at the real width and a selection can span items the
  way `TInkMemo` already does.
- Room to grow: columns, a header row, a grid of cells - the string
  grid Tony has in mind.  Those are far easier on a control that owns
  its layout than on `TCustomListBox`, whose `Columns` means something
  else on every platform.

What it costs:

- The native pieces come for free today: keyboard navigation, type-to-
  find, `MultiSelect` and `ExtendedSelect`, `Sorted`, `TopIndex`,
  `IntegralHeight`, the `Items` object with its `Objects`, focus and
  accessibility.  All of it would be written again, and the form
  designer's `Items` editor and every published property that programs
  already set must keep working, which means keeping the
  `TCustomListBox`-shaped API on a control that is not one.
- `TInkMemo` is already most of this: page-engine lines, a scrollbar,
  selection, find, touch.  A list is a memo whose lines are rows that
  can be selected whole and edited in place.  Building the list on the
  memo's engine, rather than from nothing, is the shorter road and keeps
  one layout engine under every control.

Suggestion, not a decision: keep today's `TInkListBox` as it is, with
this fix, and when the time comes for columns or a grid, grow that from
`TInkMemo` (rows that select, a header, cells) as a new control rather
than rewriting the listbox.  The old one stays for the programs that use
it; the README wording about the canvas can say the listbox items are
drawn on it, which is what is true.
