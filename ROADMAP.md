# LazInk - what is left to do

Rewritten 4 October 2026.  Everything that was finished, and the story of
how, moved to `docs/HISTORY.md`; this file holds only what is open, so it
can be read in one sitting.  When an item here is done, write how under it,
and when the note has gone cold, move it to the history file.

---

## 1. What LazInk is

A general-purpose Lazarus package of **formatted-text controls drawn
entirely on a `TCanvas`** - labels, memos, list boxes, a page viewer and a
rich editor - that read **HTML or Markdown**.  It should be the package a
Lazarus developer reaches for when they want decorated text, release notes,
a help viewer or a Markdown document, without a browser engine.

Heckers Sketch (https://github.com/TonyStone31/heckers-sketch) is its
first real user.  Its needs come first, but every one of them is solved in
a way any other program can use.  Nothing in LazInk may know about Heckers
Sketch.

### Principles

* **Canvas-drawn, no widgetset-specific rendering.**  Where the platform
  has to be touched, keep it small, behind `{$IFDEF}`, and do nothing on
  platforms that don't need it.
* **No external dependencies** beyond Lazarus/LCL and FPC - in particular
  not SynEdit and not any GPL code.
* **A small code highlighter, not a real one**: comments, strings, numbers
  and keywords, nothing else.  `OnHighlightCode` is where a host plugs in a
  real one.
* **One renderer, two input formats.**  Markdown is converted and drawn by
  the same renderer; every display control has `TextFormat`, and new
  Markdown features go in the converter, once.
* **A subset, on purpose.**  Not a browser.  Add what real documents need,
  and say plainly what is not supported (`docs/HELP_COMPATIBILITY.md`,
  README "Limits").
* **US English** everywhere: color, center, license, gray.
* **Tested.**  `tests/run.sh` stays green, new behavior comes with checks,
  and a new check must be able to fail.
* **0BSD throughout**, no third-party code in the package.

## 2. Where it stands

| Control | What it does now | Missing |
|---|---|---|
| `TInkLabel` | inline markup, HTML or Markdown, copy menu | character selection; links out of a finger's reach on GTK3 |
| `TInkMemo` | page-engine lines, selection, copy menu, find, touch, `ScrollBars` | wrap measures a line without its images |
| `TInkListBox` | markup items, in-place editor, copy menu | character selection |
| `TInkPage` | whole HTML/Markdown documents: headings, lists, tables, code, PNG/GIF/WebP, links, history, CSS reader, flex/grid cards, media queries, selection, find, touch and flick, `ScrollBars` | hardware check of touch |
| `TInkEdit` | single-line edit, per-character colors | - |
| `TInkRichEdit` | WYSIWYG inline editor, selection, clipboard, undo, `ReadOnly` | headings, lists, tables; Markdown in and out |
| `TInkScrollBar` | canvas scrollbar, colored from CSS | - |

Checked against the Heckers Sketch manual (38 pages).  Only **GTK3 on
Linux** has been run.

## 3. Open - in rough order of value

### A. The renderer wishlist from real use

**All done, 4 October 2026.**  The six items from building Heckers
Sketch's send window (`bugs/2026-09-20-summary-page-wants/README.md`, which
says how each landed): cell text styling (`font-size`, `font-weight`,
`font-family`, `line-height` on `td`/`th`), `white-space: nowrap` columns,
block children of a cell, tables nested in cells and in grid/flex cards,
inline pills on `<span>`, and `SetInnerHTML` by id.  A page like that send
window can now be written the way a browser page would be.

**Opened and closed again the same day, 4 October 2026** - from moving
that send window onto them, all done (the notes say how):
`@media (prefers-color-scheme)` with the `ColorScheme` property
(`bugs/2026-10-04-light-dark-and-more`); text in a grid card styled, the
band gone and block margins read in cells
(`bugs/2026-10-04-grid-card-text-unstyled`); `imoInlineHTML` for Markdown,
and the `NoWrap` ellipsis with `TInkLabel.Ellipsis`.

**Open, 4 October 2026:** a grid of cards has about 17 px too much space
above it and 36 px too much below, where ordinary blocks match a browser
to the pixel (`bugs/2026-10-04-space-round-a-grid`).

### B. Selection, finished

* **Character selection in `TInkLabel` and `TInkListBox`** (they have the
  copy menu and line-level copying today).  `TInkPage` and `TInkMemo` have
  the real thing; the hit-test machinery exists.
* **Keyboard selection** (Shift+arrows) on the page-based controls.

### C. The demo

* ~~A proper redesign~~ - done; the owner calls it "way better these days"
  (4 October 2026).
* **Color the Markdown source** in the editor tab with LazInk's own
  machinery (the `TInkCodeMemo` idea - a multi-line plain-text editor with
  per-character coloring).  If it turns out to be worth having, it belongs
  in the package.  Markdown is the only language it colors.
* **Source and preview scrolled together** - nice, not essential.
* **A build on the current stable Lazarus** - only trunk has been run.

### D. Hardware and platforms

* **Touch on a real Linux touchscreen** (the Linux Mint machine), and a
  Windows run.  The code is built and unit-tested; the hardware check is
  written down with the machine and distro when done.
* **Other widgetsets actually run** - win32, qt5/qt6, cocoa, gtk2 - with
  the results written into the README.  Don't claim what hasn't been run.

### E. The big one - a WYSIWYG Markdown editor

`TInkRichEdit` reading and writing Markdown: headings, lists, links, code,
then tables.  Nothing in the Online Package Manager renders Markdown
natively or edits it WYSIWYG (checked 16 September 2026), so this is where
LazInk could be unique.

**The first piece is in (4 October 2026).**  The editor has paragraph
kinds - `ipkH1`-`ipkH6`, `ipkBullet`, `ipkNumber`, `ipkQuote`, `ipkCode` -
held per character the way `Align` is, so the flat document stays flat.
They render (heading sizes and weight, list markers with hanging indents,
a quote's bar, a shaded monospace code band), they edit (`ApplyParaKind`,
`SelParaKind`; Enter at a heading's end starts plain text, Enter on an
empty item ends its list), they survive the `Markup` round trip as
`<h1>`-`<h6>`, `<li>`, `<oli>`, `<blockquote>` and `<pre>` wrappers, and
`LoadMarkdown`/`AsMarkdown` carry a document in and out - the round trip is
a fixed point, which the tests hold it to.

**Tables are in too (4 October 2026), which completes E as it was asked.**
A table row is a paragraph kind whose cells are the text between literal
'|' characters - the pipes draw as the grid, not as glyphs, so the flat
document and its one-dimensional caret survive untouched.  Consecutive
rows share their column widths, the head row is bold on a band, Tab hops
cells (a new row past the last), Enter adds a row and ends the table on an
empty one, InsertTable starts one from nothing, and pipe tables round-trip
through LoadMarkdown/AsMarkdown with their delimiter row - still a fixed
point, still held there by the tests.

Polish still open here: nested lists (they flatten to one level); the
language tag on fenced code; images; cells cannot hold a pipe; and a demo
tab that edits Markdown through this instead of a TMemo - which is also
C's coloring item made moot.

### F. An Online Package Manager listing

The license is already 0BSD, so this is now just the work of listing it -
best after the widgetset runs in D, so the listing's claims are true.

### G. Small gaps, when they get in the way

* `<abbr title>`: a title on anything that is not a link is dropped.
* Flex/grid: `justify`/`align`, `order`, grow/shrink ratios are not read.
* Markdown: emphasis does not follow full CommonMark delimiter rules, link
  definitions must fit on one line, no footnotes, an image in a table cell
  shows its alt text.
* `TInkMemo` word-wrap measures a line without its `<img>` images, so a
  line of images can run a little past the edge.
* On Qt and GTK2 a finger cannot be told from the mouse, so a memo selects
  unless `MouseDrag := imdScroll`.

## 4. What not to do

* **Don't build a browser** or chase CSS conformance.
* **Don't use or depend on `TSynMarkdownSyn`** - not in the package, not in
  the demo.
* **Don't grow the highlighter into a real one** - four token kinds, word
  lists, nothing else; `OnHighlightCode` is the extension point, and no
  SynEdit glue goes in the package.
* **Don't make the package depend on SynEdit** or on any GPL code.
* **Don't make separate "Markdown" versions of each control** - use
  `TextFormat`.
* **Don't put Heckers Sketch specifics in LazInk** - build the general
  version.
* **Don't claim support that hasn't been run** (widgetsets, touch
  hardware).

## 5. Working on it

* Build: open `lazink.lpk` in Lazarus, or `lazbuild lazink.lpk`.  The demo
  is `demo/lazinkdemo.lpi`.
* Test:

  ```sh
  LAZARUS_DIR=/path/to/lazarus FPC=/path/to/fpc tests/run.sh
  ```

  and, to check that a folder of HTML pages renders completely:

  ```sh
  ls /path/to/help/*.html > pages.txt
  LAZARUS_DIR=... FPC=... tests/run.sh pages.txt results/
  ```

  Heckers Sketch's manual (`docs/help` in its repository) is a good folder
  for this.
* Heckers Sketch builds against LazInk from `../LazInk/lazink.lpk`, so a
  change here reaches it on its next build.  Keep `tests/run.sh` green
  before pushing.
* **A stale demo build**: `lazbuild` can miss an edit to `demo/main.lfm`
  made in the same second as the build.  `rm -rf demo/lib` and build again.
* Update `README.md`, `docs/HELP_COMPATIBILITY.md` and this file as items
  land.  Commit finished work; don't leave it uncommitted.
* `bugs/` holds one dated folder per bug or wishlist, each with a repro;
  a fixed one gets a "Fixed" section saying how, and stays as the record.
* How everything so far was built, and why: `docs/HISTORY.md`.
