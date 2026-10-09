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
| `TInkLabel` | inline markup, HTML or Markdown, copy menu, character selection | links out of a finger's reach on GTK3 |
| `TInkMemo` | page-engine lines, selection, copy menu, find, touch, `ScrollBars` | wrap measures a line without its images |
| `TInkListBox` | markup items, in-place editor, copy menu, character selection in an item | - |
| `TInkPage` | whole HTML/Markdown documents: headings, lists, tables, code, PNG/GIF/WebP, links, history, CSS reader, flex/grid cards, media queries, mouse and keyboard selection, find, touch and flick, `ScrollBars` | hardware check of touch |
| `TInkEdit` | single-line edit, per-character colors, `TextHint`, undo/redo, context menu | - |
| `TInkRichEdit` | WYSIWYG editor: inline styles, headings, nested lists, quotes, code with fence languages, tables, Markdown in and out, undo, context menu | images |
| `TInkCodeMemo` | plain multi-line editor: `Text`/`Lines`, `TextHint`, `MaxLength`, `WantReturns`/`WantTabs`, per-character colors, undo, context menu | a `TInkScrollBar` of its own |
| `TInkScrollBar` | canvas scrollbar, colored from CSS | - |

Checked against the Heckers Sketch manual (38 pages).  Only **GTK3 on
Linux** has been run.

## 3. Open - in rough order of value

### A. What real programs asked for

Everything asked so far is done - the send-window wishlist, light and
dark, the grid bugs, the dialog round (`TextHint`, undo and the
context menu on `TInkEdit`, `TInkCodeMemo`, `itfPlain`), and the chat
window (8 October 2026: `TInkEdit.PasswordChar`; whole-message entries in
`TInkMemo` with `AppendBlock`/`AppendPlain`/`ReplaceLast`/`EntryAt`;
`TInkCodeMemo.AutoHeight`) - and the story moved to `docs/HISTORY.md`;
each bug folder keeps its own "how".  Open here: whatever Heckers
Sketch's next window finds.
* ~~Code blocks a reader can handle~~ - done 9 October 2026
  (bugs/2026-10-09-code-blocks-in-a-chat): a header on every code block
  with the language, the line count and Copy; `CodeFoldLines` folds a long
  block to its first lines; `CodeActions` / `OnCodeAction` give the host
  its own buttons.  Still open from that note: a block scrolling inside a
  height of its own (folding covers the need for now), line numbers, and
  `CodeBlockAt`.
* `TInkCodeMemo` still scrolls with the stock scrollbar, not a
  `TInkScrollBar`, and has no `ScrollBars` property yet.

### B. Selection, finished

Done, 8 October 2026.  A `TInkLabel` selects like a page: a drag takes
characters, a double click a word, a triple click everything, and the copy
menu grew Copy and Select all; a click still follows a link.  A
`TInkListBox` selects characters with a drag that stays inside the pressed
item's row - the moment it leaves the row it is an ordinary item drag
again, so the held-button highlight and `emOnSelect` behave as they always
have - and `SelectedText`/Ctrl+C prefer the characters when some are
selected.  Both are built on `TInkRunText` in `InkDraw`, the single-rect
version of the page's run map, and both hand a mouse selection to X11's
primary clipboard.  The page controls take Shift with the arrows, Home,
End, PgUp and PgDn to extend the selection from its caret end.

### C. The demo

* ~~The showcase~~ - done, 5 October 2026.  The Markdown tab's source pane
  is a `TInkCodeMemo` colored by the demo through `OnGetCharAttrs`
  (Markdown is the only language it colors, and no SynEdit anywhere); the
  WYSIWYG tab opens on a document loaded from Markdown with paragraph-kind
  and Table buttons, and its source pane speaks markup or Markdown both
  ways; the Documents tab grew a `ColorScheme` box.  The README's pictures
  are regenerated.
* **Show somewhere still**: pills and `itfPlain` have no demo spot yet.
* **Source and preview scrolled together** - nice, not essential.
* **A build on the current stable Lazarus** - only trunk has been run.

### D. Hardware and platforms

* **Touch on a real Linux touchscreen** (the Linux Mint machine), and a
  Windows run.  The code is built and unit-tested; the hardware check is
  written down with the machine and distro when done.
* **Other widgetsets actually run** - win32, qt5/qt6, cocoa, gtk2 - with
  the results written into the README.  Don't claim what hasn't been run.

### E. The WYSIWYG Markdown editor - polish

The editor itself is **done as asked** (4 October 2026; the story is in
`docs/HISTORY.md`): headings, lists, quotes, code, tables, Markdown in and
out as a fixed point.  Nothing else for Lazarus does this.

**Nested lists and fence languages landed 5 October 2026**: a list item
carries its depth (Tab nests it, Shift+Tab brings it back, Enter on an
empty nested item steps out a level before it leaves the list; a sublist
does not break its parent's numbering), and a code line carries its
fence's language - both per character like the kind, both through the
`Markup` and Markdown round trips, which stay fixed points.  Found on the
way and fixed: right after a paragraph break at the document's end, the
caret inherited default attributes instead of its paragraph's, so Enter at
a list's end lost the list for the next typed character.

Open polish:

* **Images** in the editor.
* **A pipe inside a table cell** - the separator wins today.

### F. An Online Package Manager listing

The license is already 0BSD, so this is now just the work of listing it -
best after the widgetset runs in D, so the listing's claims are true.

### G. Small gaps, when they get in the way

* **Nested block boxes flatten**: a `<div>` with a background holding
  another block element loses the nesting - each piece becomes its own
  block, and the outer box's background only wraps the first words.  The
  block model is flat; found by the side-by-side page, 8 October 2026.
* `<abbr title>`: a title on anything that is not a link is dropped.
* Flex/grid: `justify`/`align`, `order`, grow/shrink ratios are not read.
* Markdown: emphasis does not follow full CommonMark delimiter rules, link
  definitions must fit on one line, no footnotes, an image in a table cell
  shows its alt text.
* `TInkMemo` word-wrap measures a line without its `<img>` images, so a
  line of images can run a little past the edge.
* On Qt and GTK2 a finger cannot be told from the mouse, so a memo selects
  unless `MouseDrag := imdScroll`.

### H. Scrolling speed on very long pages - wanted in the near future

The 76-section comparison page (~1800 blocks, ~29000px) scrolls, but a
fast wheel can feel it.  Tony wants this improved in the near future.
Measured nothing yet; in the order worth trying:

* ~~Find the first visible block by binary search~~ - done 9 October
  2026: a paint starts at the first block that can show (and the one before
  it, whose band or bar may reach down into view) and stops at the first
  that starts below the window.  Not yet measured on the 76-section page.
* **Blit on scroll.**  A scroll of 40px repaints the whole viewport; the
  still-visible region could be copied down and only the exposed strip
  painted.  Classic, biggest win, but the selection overlay, the find
  bar and the band fills must be invalidated honestly.
* **Check the layout cache fits the page.**  THTMLLayoutCache holds 128
  entries / 16MB; an 1800-block page may thrash it, re-laying-out blocks
  every time they scroll back in.  Count hits and misses (the fields are
  there) before assuming.
* **A retained strip.**  Render viewport+margin to one bitmap, blit from
  it while scrolling inside the strip, re-render when leaving it.  Only
  if the first three are not enough.

### I. HTML and CSS to add - agreed 8 October 2026

Checked against what generators and documentation pages actually write.
Already in: thead/tbody/tfoot, the HTML5 containers (section, article,
nav, figure, header, footer, main, aside - all blocks), svg skipped
cleanly, iframe showing its fallback content, task-list checkboxes,
details/summary, dl, em and px units.

To do, smallest first (Tony: "go ahead and mark those... those will be
good, and floated images should be important too"):

* **`<wbr>`** - a break opportunity in a long identifier.  The tag is
  already parsed as void; the engine just never learns the spot.
* **`tr:nth-child(even)` / `(odd)` backgrounds** - zebra striping, the
  single most common table CSS there is.  One selector special-case.
* **`text-overflow: ellipsis`** - the engine already ellipsizes
  (NoWrap+Ellipsis); the CSS reader just never says so.
* **`vertical-align` / `valign` in table cells** - top-aligning a tall
  row's neighbors; docs tables use it.  Verify what the engine has.
* **`em` relative to the current font** - CSSPixels multiplies em by a
  fixed 16; a page at font-size 14px gets slightly wrong em margins.
* **`#id` selectors** in the CSS reader - occasional, cheap.
* **Images floated beside text** (`float: left/right`, `<img align=>`) -
  the one large layout feature real pages miss here.  "Nothing flows
  around a picture" is a stated limit; lifting it is engine work in the
  line layout, not a patch.  Agreed as important - the big item of this
  section.

Done already from this list: the task-list checkbox now draws the way
Chromium draws one (its blue behind a white check, gray-bordered white
when empty - a pill, so every control gets the same box), replacing the
Unicode ballot glyphs, 8 October 2026.

Not worth it, deliberately: `<iframe>` as a real embedded page (offline
help has no third-party embeds; the fallback text is the right render),
`<video>`/`<audio>`, web fonts, floats beyond images, `position:`,
JavaScript - the "what not to do" list below still holds.

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
