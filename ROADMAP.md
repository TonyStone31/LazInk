# LazInk roadmap

Notes for future work on LazInk, written 16 September 2026 while looking at
what Heckers Sketch would need from it.  LazInk stays its own project;
Heckers Sketch would just be one of its users.

## Where it stands (updated the same evening)

Most of the list below was built the same day, in a session of its own:

* **Done:** `TInkPage` (a full-page viewer), tables, headings, lists,
  `<code>` and `<kbd>`, images by file name including animated GIFs, a small
  CSS reader, `MarkdownToInk` and a `TextFormat` switch on the viewers, a
  test suite, and the license files (`LICENSE`, `LICENSES/`,
  `THIRD_PARTY_NOTICES.md`, `docs/RENDERER_CHANGES.md`).
* **Checked against Heckers Sketch's own help folder:** all 38 pages load
  and render at 360, 700 and 1100 pixels wide, all 12 images decode, and all
  2,205 visible text fragments survive.  The test used to expect exactly nine
  images - true of the site on the day it was written - and now counts the
  `<img>` tags in the pages it is given.
* **Published** on GitHub as `TonyStone31/LazInk`.
* **First real use:** Heckers Sketch's release-notes window is a `TInkPage`
  now.  Before the swap, `TInkPage` learned to scroll when the page is
  dragged, which that window needed for Windows touch screens.
* **Still open:**
  * ~~A themed scrollbar~~ - **done** 16 September: `TInkScrollBar`,
    coloured from the page's CSS `scrollbar-color` / `scrollbar-width`, with
    tests for the CSS, the colours it is painted in, and the bar's clicks,
    drag, keys and wheel.  Heckers Sketch's release notes use it.
  * Trying the other widgetsets - only GTK3 has been run.
  * Heckers Sketch's help pages inside the program, which will be the second
    real use.

The rest of this file is the original list, kept for the reasoning.

## Next: two gaps found in real use (16 September, notes only - no code yet)

### 1. Touch does not scroll a page on Linux

Tony: on his wife's Linux Mint machine, dragging a finger on Heckers Sketch's
What's New window does nothing.  It works on Windows.

**Why - read from the code, not yet run on a touchscreen here:**
`TInkPage`'s drag-scroll (`MouseDown`/`MouseMove`/`MouseUp`, added this week)
only ever sees the mouse.  On Windows a finger arrives as mouse messages, so
it works.  On GTK3 it does not: the Lazarus GTK3 backend asks GDK for raw
touch events on every window it creates and then ignores them - and once a
window has asked for touch, **GDK stops turning fingers into mouse events for
it**.  So a finger on a `TInkPage` on Linux produces nothing at all.

Heckers Sketch already hit this for its drawing area and worked round it in
its own `uTouch.pas`: it connects to the form's GTK `touch-event` signal
(`g_signal_connect_data(..., 'touch-event', ...)`) and turns
`GDK_TOUCH_BEGIN / UPDATE / END / CANCEL` into its own events.  Two limits of
that as it stands: it is hooked on the **main window only** (What's New is a
separate form, so it gets nothing), and it keeps **one global handler**, so a
second hook would replace the first.

**What LazInk needs:**

* Its own touch hook, in LazInk, so every LazInk control scrolls by finger
  without the host doing anything.  On GTK3: connect to `touch-event` on the
  control's own widget (or its form's, and route by position), and feed
  begin/update/end into the same grab-and-drag code the mouse uses.
  `{$IFDEF LCLGTK3}` like `uTouch`; nothing needed on Windows.  Per-control,
  not one global handler.
* A decision on **mouse drag vs touch drag**.  Once touch is its own path, a
  mouse drag could be freed up for selecting text (below) - which is what a
  browser does: finger drags scroll, mouse drags select.
* Momentum ("flick") scrolling would be nice, not essential.
* Test on real hardware - nothing in the nested X server here has fingers.
  Worth checking qt5/qt6 too, which may deliver touch differently again.
* Once LazInk has it, Heckers Sketch's `uTouch` could perhaps use the same
  code rather than keeping its own.

### 2. Text cannot be selected or copied

Tony: "you cannot select text to copy and paste it elsewhere.  That's sort
of a shitty aspect of lazink for sure."

**Where things are:** `TInkEdit` and `TInkRichEdit` have a caret, selection
and clipboard.  The viewers - `TInkLabel`, `TInkMemo`, `TInkListBox`,
`TInkPage` - have none.  `TInkMemo`/`TInkListBox` can highlight whole
*lines* (`ShowSelection`) but not text inside them.  The renderer's hit test
(`HTMLHitTest` / `THTMLHitInfo` in `inkhtml.pas`) only answers "is this over
a link"; it cannot say **which character** is under the pointer, and that is
the piece everything else needs.  `PlainText` already exists on `TInkPage`.

**Options, cheapest first:**

1. **Copy without selecting** - a right-click menu on the viewers with *Copy
   all* (from `PlainText`) and *Copy this paragraph* (the block under the
   pointer, via `HTMLPlainText` of its source); Ctrl+A then Ctrl+C for the
   whole page.  A day's work, no renderer changes, and it covers "get the
   text out" for help pages and release notes.
2. **Real selection** - press, drag, highlight, Ctrl+C, like a browser:
   * the renderer needs a character-level hit test: given X,Y in a drawn
     block, return the character offset (and the reverse, offset to
     position, to paint the highlight).  `TInkRichEdit` already lays out
     text per character for its caret - read how it does that before
     writing a second way;
   * selection has to run **across blocks** on `TInkPage` (paragraph to
     table cell to list item), in document order;
   * painting the highlight behind the text, in a colour from CSS
     (`::selection` is the browser's way; a `SelectionColor` property is
     enough);
   * copy as plain text, and ideally as HTML too for pasting into a word
     processor;
   * double-click selects a word, triple-click a paragraph;
   * **conflicts with drag-to-scroll** - see the touch note above: on a
     mouse, drag should select; on a finger, drag should scroll.  That is
     only possible once touch arrives separately from the mouse, so the two
     gaps want solving together.
3. **Use `TInkRichEdit` read-only as the viewer** - selection for free, but
   it is an inline editor without tables, images or the page layout, so it
   would not render the manual.  Not a real answer for `TInkPage`.

**Suggested order:** option 1 now for the viewers (quick win); then the
touch hook; then real selection on top of the character hit test, with mouse
drag = select and touch drag = scroll.

## What Heckers Sketch needs from it

Heckers Sketch has two places that could use LazInk.  Today it has its own
hand-written code for both.

### 1. The "What's New" window - the small job

`uWhatsNew.pas` in Heckers Sketch is about 600 lines of its own parser and
painter for the release notes.  It handles headings, bullets and bold, and
not much else.  A bug on 16 September showed raw `<kbd>` tags in the window,
because that code doesn't understand them.  A LazInk control would have
rendered them properly.

The notes come from `WHATS_NEW.md`, which is Markdown.  Right now it has 145
release headings, 195 section headings, 342 bullets, bold on 295 lines,
backticks on 71 lines, and some indented sub-bullets.

**What LazInk needs to add for this:**

* **Headings.**  `<h1>`, `<h2>`, `<h3>` - or at least a documented way to do
  them with `<font size>` and `<b>` that looks right.  There are no heading
  tags yet.
* **Bullet lists.**  `<ul>` and `<li>`, with the text wrapping under the
  first word rather than under the bullet, and one level of nesting.  There
  are no list tags yet; `<ind>` gets close but doesn't draw the bullet or
  hang the wrapped lines.
* **Code and keys.**  `<code>` (monospace, faint background) and `<kbd>`
  (monospace, a small box around it).  Neither exists yet.
* **Theme colors.**  Heckers Sketch has light and dark themes, so the
  control's text, link, rule and background colors must be settable from code
  and must not assume a white background.  Check that `TInkMemo` does this
  cleanly.
* **A Markdown-to-markup helper.**  Something like
  `function MarkdownToInk(const S: string): string` that handles headings,
  bullets, `**bold**`, `*italic*` and `` `code` ``.  This could live in
  LazInk as an optional unit, or in Heckers Sketch.  In LazInk it would be
  useful to other people too.

Once those exist, Heckers Sketch swaps its window's painting for a
`TInkMemo` (or a scrolling `TInkLabel`) and deletes most of `uWhatsNew.pas`.
It keeps the part that decides *which* releases to show.

### 2. The help manual inside the program - the big job

The manual is web pages in `docs/help/` (38 pages).  Today `/manual` opens
them in the web browser.  Showing them inside the program would be nice, but
the pages use a lot more HTML than LazInk handles.  Counted across all 38
pages:

| Used in the manual | Count | LazInk today |
| --- | --- | --- |
| `<table>`, `<tr>`, `<td>`, `<th>` | 19 tables, 469 cells | no |
| `<code>` | 271 | no |
| `<kbd>` | 248 | no |
| `<ul>`, `<ol>`, `<li>` | 84 lists, 239 items | no |
| `<h1>`, `<h2>` | 227 | no |
| `<p>`, `<b>`, `<i>`, `<br>`, `<a>` | many | yes |
| `<img src="file.png">` with `<figure>` / `<figcaption>` | 27 figures | images only by list index, not by file name |
| `<div class="card">`, `.grid` layout on the index page | 37 cards | no |
| A shared stylesheet (`style.css`) | every page | no CSS |
| Links between pages, and to `#anchors` | 191 links | links fire an event; loading the next page and jumping to an anchor would be up to the program |

**What LazInk would need for this, roughly in order of value:**

1. Everything from the What's New list above (headings, lists, code, kbd).
2. **Tables** - simple ones: rows, cells, a header row, column widths worked
   out from the content.  This is the biggest single piece of work.
3. **Images by file name**, relative to the page, so `<img src="shots/x.png">`
   works.
4. **A page viewer control** - something like `TInkPage`: load a file, scroll
   the whole document as one piece (not line by line like `TInkMemo`),
   follow links to other files, jump to `#anchors`, and go back.
5. **A tiny bit of style** - not real CSS, but a way to set heading sizes,
   code background, table borders and link colors once for the whole
   control, so pages don't need `<font>` everywhere.
6. Simply ignoring the tags it doesn't know (`<nav>`, `<header>`, `<footer>`,
   `<meta>`, `<div>`) instead of showing them as text.  Check what the
   parser does with unknown tags now.

The card grid on the manual's index page is probably not worth supporting.
It's easier to give the in-program viewer a plain contents list.

**The honest alternative:** keep opening the manual in the browser.  It works
today, it looks right, and there is only one copy to maintain.  Writing a
second, simpler copy of the manual just for LazInk would be a mistake - two
copies of a manual means one of them goes stale.  So the in-program manual
only makes sense once LazInk can render the real pages.

## The order that makes sense

1. Publish LazInk (commit, GitHub, `LICENSE`).
2. Add headings, lists, `<code>` and `<kbd>`.  These help everyone, and they
   are all that the What's New window needs.
3. Swap Heckers Sketch's What's New window over to LazInk and delete its
   hand-written painter.  This is the first real-world use, and it will show
   what else is missing.
4. Tables, file images, and a page viewer - then decide whether the manual
   moves into the program.

## README ideas

The README is already in good shape: it has screenshots, the markup list,
examples and proper credits.  A few things worth adding when it goes public:

* **A "Limits" section** saying plainly that the markup is a small subset of
  HTML - no tables, lists, headings or CSS yet - so nobody expects a web
  browser.  Update it as those land.
* **Requirements**: which Lazarus and FPC versions it has been tested with,
  and which widgetsets have actually been tried (the README claims all of
  them, including cocoa - say which ones were really run).
* **Status**: "0.9, usable, API may still change".
* **A link to the forum thread** is already there; add the GitHub URL once
  the repository exists.
* **A `LICENSE` file**, as above, and a line in the README pointing to it.

## Implementation update: tables and Markdown

The display controls now have an HTML/Markdown `TextFormat` property, a small
Markdown converter, and shared rendering of basic HTML tables. The demo includes
a source/preview tab and `tests/run.sh` exercises conversion, wrapping, cell
links, malformed input, and control integration. These changes supersede the
"no tables" and "Markdown helper needed" descriptions above for display controls.

`TInkPage` now provides native whole-document scrolling, local-file loading,
relative images and stylesheets, page navigation, anchors, and history. It has
minimal CSS palette/typography support and animated GIF playback. The published
38-page help site has been audited and tested; see `docs/HELP_COMPATIBILITY.md`
for the precise boundary between readable native rendering and browser styling.
Remote resource retrieval has an event hook but no built-in HTTP client.

Still needed: editable tables and Markdown serialization in the rich editor;
nested/merged cells; hanging list markers; more CSS only where a demonstrated
help-page requirement justifies it. The lightweight inline controls remain
separate from the page viewer's HTML normalization.

## Licensing update: September 16, 2026

The missing-license-file items above are now resolved: LICENSE defines the
MIT/MPL boundary, LICENSES contains both full texts, THIRD_PARTY_NOTICES.md
records upstream attribution and the original-attachment comparison, and
docs/RENDERER_CHANGES.md records renderer modifications. Public-facing credits
now emphasize JVCL, Lazarus/Free Pascal, and AI-assisted learning rather than
retelling the forum discussion. Separate binary releases still need their
actual corresponding-source distribution or download location.
