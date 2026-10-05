# Wanted: TInkEdit with a hint and undo, a plain multi-line editor, and plain text

Written 5 October 2026, from Heckers Sketch
(https://github.com/TonyStone31/heckers-sketch), which is moving every
dialog off the stock LCL controls: on Windows the stock ones draw in the
system's colors whatever the dialog's theme, so a dark dialog gets dark
words on dark, or white boxes.  Its 42 one-line text boxes are to become
`TInkEdit`, and its two multi-line notes want a LazInk editor too.  Each
item is a general feature; nothing here should know about Heckers Sketch.

---

## 1. A hint in an empty TInkEdit - `TextHint`

### The need

`TEdit.TextHint` - the gray "the name on the ticket - T-3, kitchen supply"
shown in an empty box - is how a form says what goes in a field without a
second label.  `TInkEdit` has no equivalent, so a form moving to it either
loses the hint or grows labels.

### How it could work

* `property TextHint: string`, published, default `''`.
* Drawn when `Text = ''`, in the edit's own font, in a dimmed text color:
  `TextHintColor: TColor = clDefault`, where `clDefault` means the font
  color blended halfway into `Color`, so it suits a light and a dark box
  without being set.
* It stays while the box has focus and is empty, with the caret drawn at
  its start - the way most current toolkits do it - and goes with the first
  character typed.  (LCL's own `TEdit` differs by widgetset here; one rule
  everywhere is the point.)
* Cut to the box with the same ellipsis `HTMLDrawOpt` now has, never
  wrapped; aligned by `Alignment` like the text.
* Never part of `Text`, never copied, never selected.

## 2. Undo and redo in TInkEdit

### The need

Every stock edit has Ctrl+Z.  A user who deletes a figure by mistake
expects it back, and moving a form to `TInkEdit` should not take that away.

### How it could work

* Ctrl+Z undoes, Ctrl+Shift+Z and Ctrl+Y redo; `Undo`, `Redo`, `CanUndo`,
  `CanRedo` and `ClearUndo` public.
* A step is one typed run, so "1-2-6" typed is one undo, not three: a run
  ends at a pause of about a second, a caret move by mouse or arrow, a
  change from typing to deleting, a paste, a cut, or a word boundary (a
  space after a non-space).  Each step keeps the text and the selection
  before and after, so undo also restores where the caret was.
* Setting `Text` from code clears the history: a form filling its fields
  is not something to undo.  `OnChange` fires on undo and redo as on any
  edit.
* A modest cap on the history (a hundred steps) so a long session in one
  box cannot grow without end.
* Undo and Redo appear in the context menu (item 3) when there is
  something to undo or redo.

## 3. A context menu in TInkEdit

`TInkEdit` publishes `PopupMenu` but brings no menu of its own; a stock
edit has Cut, Copy, Paste, Delete and Select All on a right-click.  The
same `CopyMenu`-style switch the display controls have - on by default -
with Undo, Redo, Cut, Copy, Paste, Delete and Select All, each enabled only
when it can do something, and `ReadOnly` hiding the ones that change the
text.  A host's own `PopupMenu` still wins when set.

## 4. A plain multi-line editor

### The need

A form's notes field - "What were you doing, and what happened?" - is a
plain, editable, multi-line box: wrapped text, a scroll bar, Enter for a
new line.  `TInkMemo` shows text and selects it but is not edited;
`TInkRichEdit` edits, but it is WYSIWYG, which is more than a note needs:
pasted formatting rides in, and a note should be plain text.

The roadmap already has the `TInkCodeMemo` idea in section C - "a
multi-line plain-text editor with per-character coloring" - for coloring
the demo's Markdown source.  The same control would serve here; coloring is
just a handler a note does not set.

### How it could work

A `TInkCodeMemo` (or `TInkPlainEdit` - the name is the maintainer's), the
multi-line sibling of `TInkEdit`:

* `Text` and `Lines: TStrings`; `ReadOnly`; `MaxLength`; `WordWrap`
  (default on), wrapping at spaces; `ScrollBars` as on `TInkMemo`, drawn
  with `TInkScrollBar` so it takes the page colors.
* Editing as `TInkEdit` already does it, across lines: caret, selection by
  mouse and Shift+arrows, Home/End, PgUp/PgDn, Ctrl+Home/End, clipboard,
  and the undo and context menu of items 2 and 3.
* `WantReturns` (default on) and `WantTabs` (default off, so Tab leaves the
  box, as a form expects); `OnChange` on every edit.
* `TextHint`, as item 1, for the empty box.
* `OnGetCharAttrs`, the same event `TInkEdit` has, for a host that wants
  coloring - Markdown in the demo, or anything else.
* Pasting puts in plain text only.
* Touch: a finger drag scrolls, as in `TInkMemo`.

## 5. Plain text in the display controls - `itfPlain`

### The need

`TInkMemo` reads HTML or Markdown.  A read-only box that shows text as it
is - a cut list, a ticket, a log, a machine's details - has to escape every
`&`, `<` and `>` before setting it, at every place that sets it, or a line
like `width < 24" & square` comes out mangled.  The stock `TMemo` such a
box replaces never needed that.

### How it could work

* A third `TInkTextFormat`, `itfPlain`: the text is shown exactly as
  written, one line per line, with no tags, entities or Markdown read.
  Inside, it is the same as escaping each line and reading it as HTML in a
  `<pre>`-like block that still wraps when `WordWrap` is on - so the
  renderer needs nothing new.
* On `TInkMemo` first, where it matters most; on `TInkLabel`, `TInkListBox`
  and `TInkPage` too, so every display control can say "this is not
  markup".
* `Lines`, `Append`, selection, find and the copy menu work as now; copying
  gives back the text as written.
* The control's font is used as it is, so a host that sets a fixed face
  gets a fixed-width plain box - which is what tickets and logs want.

**What Heckers Sketch does meanwhile:** keeps its six read-only text boxes
(tickets, the postcard's text, the long-text viewer) as stock `TMemo` until
this exists.

**What Heckers Sketch does meanwhile:** keeps its two notes (the bug
report's and the postcard's) as stock `TMemo` until this exists, and holds
its 42 text boxes as `TEdit` until items 1 and 2 land - two of them have
hints, and all of them would lose Ctrl+Z.
