# LazInk - direction

Written 16 September 2026, for whoever works on LazInk next.  It says what
LazInk is for, what is done, what Heckers Sketch needs **now** (in order,
each with what "done" means), where the package goes after that, and what
not to do.

---

## 1. What LazInk is

A general-purpose Lazarus package of **formatted-text controls drawn
entirely on a `TCanvas`** - labels, memos, list boxes, a page viewer and a
rich editor - that read **HTML or Markdown**.  It should be the package a
Lazarus developer reaches for when they want decorated text, release notes,
a help viewer or a Markdown document, without a browser engine.

Heckers Sketch (https://github.com/TonyStone31/noella-etch-a-sketch) is its
first real user and is driving the next round of work.  Its needs come
first, but every one of them should be solved in a way any other program
can use.  Nothing in LazInk may know about Heckers Sketch.

### Principles

* **Canvas-drawn, no widgetset-specific rendering.**  Where the platform has
  to be touched (touch input on GTK3, below), keep it small, behind
  `{$IFDEF}`, and do nothing on platforms that don't need it.
* **No external dependencies** beyond Lazarus/LCL and FPC.  In particular
  the package must **not** depend on SynEdit or any GPL code - see 5.
* **No syntax highlighting of code, by decision.**  LazInk shows code
  blocks well and hands them to the host to colour if it wants to - see
  "Code blocks and syntax highlighting" below.  It does not ship
  highlighters for programming languages.
* **One renderer, two input formats.**  Markdown is converted to LazInk's
  markup and drawn by the same renderer.  Every display control has a
  `TextFormat` property (`itfHTML` / `itfMarkdown`) rather than a separate
  "Markdown" twin of each control.  New Markdown features go in the
  converter, once.
* **A subset, on purpose.**  Not a browser, not CSS conformance, not
  CommonMark-complete.  Add what real documents need, and say plainly what
  is not supported (`docs/HELP_COMPATIBILITY.md`, README "Limits").
* **Tested.**  `tests/run.sh` must stay green, and new behaviour comes with
  checks.  Make sure a new check can actually fail.
* **The licence boundary stays clean**: MIT for LazInk's own code, MPL 1.1
  for the JVCL-derived renderer (`inkhtml.pas`, `inktables.inc`).  See
  `LICENSE`.

---

## 2. Where it stands

| Control | What it does now | Missing |
|---|---|---|
| `TInkLabel` | inline markup, HTML or Markdown | text selection / copy |
| `TInkMemo` | lines of markup, whole-document Markdown | text selection / copy |
| `TInkListBox` | markup items, in-place editor | text selection / copy |
| `TInkPage` | whole HTML or Markdown documents: headings, lists, tables, code/kbd, PNG and animated GIF, links, anchors, Back/Forward, small CSS reader, themed scrollbar, drag-to-scroll | **touch on Linux**, **text selection / copy**, fuller Markdown |
| `TInkEdit` | single-line edit, per-character colours | - |
| `TInkRichEdit` | WYSIWYG inline editor, selection, clipboard, undo, `ReadOnly` | headings, lists, tables; Markdown in and out |
| `TInkScrollBar` | canvas scrollbar, coloured from CSS `scrollbar-color` / `scrollbar-width` | - |

Checked against the Heckers Sketch manual (38 pages, 14 images, 2,209 text
fragments all render).  Only **GTK3 on Linux** has been run.

Heckers Sketch already uses `TInkPage` for its "What's new" window.

---

## 3. What Heckers Sketch needs now - in this order

Each item: the problem, exactly what to build, and what "done" means.

### P1. Touch scrolls a page on Linux (GTK3)

**Problem.**  On Tony's wife's Linux Mint machine, a finger dragged on
Heckers Sketch's What's New window does nothing.  It works on Windows.

**Why** (read from the code; not yet reproduced on a touchscreen): the
Lazarus GTK3 backend asks GDK for raw touch events on every window and then
ignores them, and once a window has asked for touch, **GDK stops turning
fingers into mouse events for it**.  `TInkPage`'s drag-to-scroll only
listens to the mouse, so on GTK3 a finger never reaches it.  On Windows a
finger arrives as mouse messages, which is why it works there.

Heckers Sketch hit the same thing for its drawing area and worked round it
in its own `uTouch.pas`: `g_signal_connect_data(widget, 'touch-event', ...)`
on the form, turning `GDK_TOUCH_BEGIN / UPDATE / END / CANCEL` into its own
begin/move/end calls.  That version is hooked on the main window only and
keeps one global handler - neither is good enough for a package.

**Build:**
* A touch hook **inside LazInk**, used by `TInkPage` (and by `TInkMemo`,
  `TInkListBox` if they scroll), so a host does nothing.
* Per control, not one global handler: several LazInk controls, on several
  forms (What's New is a separate modal form), must all work.
* `{$IFDEF LCLGTK3}` for the GDK code; nothing on Windows, where the
  existing mouse path already works.  Look at qt5/qt6 as well.
* Touch begin/update/end feed the **same** grab-and-drag logic the mouse
  uses now (`FGrab`, `FGrabY`, `FGrabAt`, the 8-pixel slop, "a drag that
  ends on a link is not a click", a tap follows a link).
* Keep touch and mouse **distinguishable** inside the control - P4 needs a
  finger drag to scroll and a mouse drag to select.
* Optional: momentum ("flick") scrolling.

**Done when:** on a real Linux touchscreen, a finger scrolls a `TInkPage`
on a secondary modal form, taps follow links, and Windows still works.
The non-hardware logic has tests; the hardware check is written down with
the machine and distro it was done on.

### P2. Copy text out - the quick version

**Problem.**  Tony: "you cannot select text to copy and paste it elsewhere.
That's sort of a shitty aspect of lazink."

**Build (before real selection):**
* A right-click menu on the display controls with **Copy all** (from
  `PlainText`) and **Copy this paragraph** (the block under the pointer, via
  `HTMLPlainText` of its source).  On `TInkPage`, the block is the one in
  `FBlocks` whose `Bounds` contain the point.
* **Ctrl+A** then **Ctrl+C** copies everything.
* A property to turn the menu off (`CopyMenu: Boolean`), and an event so a
  host can add its own items.

**Done when:** Heckers Sketch's What's New and a help page can have their
text copied into a text editor, and tests cover what lands on the
clipboard.

### P3. Fuller Markdown

**Problem.**  The Markdown converter is a basic subset.  Programmers write
GitHub-flavoured Markdown, and Heckers Sketch wants to hand its
`WHATS_NEW.md` straight to LazInk instead of converting it to HTML itself
(which it does today, in `uWhatsNew.pas`, `ReleaseNotesHTML`).

**Build, in `inkmarkdown.pas`:**
* Headings `#` to `######` (and the `===` / `---` underline form).
* Paragraphs joined across wrapped lines; a blank line ends one.
* **Bullet lists with wrapped continuation lines** - `WHATS_NEW.md` wraps
  every bullet onto indented lines - and **nested lists** by indentation,
  `-`, `*`, `+`, and numbered `1.` lists.
* `**bold**`, `*italic*`, `_italic_`, `__bold__`, `~~strike~~`,
  `` `code` ``.
* Fenced code blocks, with the **language tag kept** - ` ```pascal `
  becomes `<pre><code class="language-pascal">`, which is what GitHub and
  every Markdown tool produce.  See "Code blocks and syntax highlighting"
  below for what LazInk does with it.
* Links `[text](url)`, autolinks `<https://...>`, images `![alt](path)`
  (relative to the document, the way `TInkPage` already handles HTML).
* Blockquotes `>`.
* Horizontal rules `---` / `***`.
* Pipe tables (already there) with alignment markers honoured.
* Task lists `- [ ]` / `- [x]`.
* HTML comments `<!-- -->` dropped (Heckers Sketch's `WHATS_NEW.md` starts
  with one).
* Raw HTML stays escaped by default, as now; an option to pass it through
  for trusted documents.
* Hanging list markers in the renderer - wrapped lines line up under the
  first word, not the bullet (listed as missing in
  `HELP_COMPATIBILITY.md`).

**Done when:** LazInk's own `README.md` and Heckers Sketch's
`WHATS_NEW.md` render correctly in `TInkPage` with
`TextFormat := itfMarkdown`, with a test for each construct above.

### P4. Real text selection

**Build:**
* A **character-level hit test** in the renderer: given X,Y inside a drawn
  block, the character offset; and the reverse, offset to position, to
  paint the highlight.  Today `HTMLHitTest` / `THTMLHitInfo` only answers
  "is this over a link".  `TInkRichEdit` already lays text out per
  character for its caret - read how before writing a second way.
* Press, drag, highlight, **Ctrl+C**, as in a browser.  Double-click
  selects a word, triple-click a paragraph, Shift+click extends.
* Selection runs **across blocks** on `TInkPage` - paragraph, list item,
  table cell - in document order.
* The highlight colour from CSS (`::selection`) or a `SelectionColor`
  property.
* Copy as plain text; also as HTML where the platform clipboard takes it.
* **Mouse drag selects, finger drag scrolls** - which needs P1.  Until then,
  keep drag-to-scroll for the mouse and select with Shift+drag, or add a
  `DragMode` property.
* Then the same for `TInkLabel`, `TInkMemo`, `TInkListBox`.

**Done when:** text on a Heckers Sketch help page can be selected with the
mouse and pasted elsewhere, a finger still scrolls, and tests cover the hit
test and the copied text.

**Why not just use `TInkRichEdit` read-only for What's New?**  It was
considered: it has `ReadOnly`, selection and clipboard already.  But it has
no headings, lists, tables or images, and cannot show the help pages, so
selection has to exist in the viewers anyway.  Once P4 is done, What's New
gets it for free.

### P5. A Markdown editor in the demo

**Tony:** "I also want a mark down editor in the demo application... to
demonstrate and maybe it opens the readme for the demo app."

**Build, in `demo/`:**
* A new tab, **Markdown editor**: source on the left, a live `TInkPage`
  preview on the right (`TextFormat := itfMarkdown`), updating as you type
  (debounced, about 300 ms).
* It **opens LazInk's own `README.md`** when the demo starts, so the first
  thing a visitor sees is the package describing itself, rendered by
  itself.  Look for it next to the demo's executable, then one folder up.
* **Open** and **Save** on this tab.  The README currently says the demo has
  "deliberately no File/Open/Save actions" - update it to say this tab is
  the exception.
* Source pane: **do not use SynEdit's `TSynMarkdownSyn`.**  Tony's call:
  build as much of this as possible out of LazInk itself.  (The highlighter
  exists in Lazarus trunk, but its header says GPL only, and it may not be
  in the stable release - reasons enough on their own.)
  * Start with a plain multi-line source box (`TMemo`) so the tab works.
  * Then colour the Markdown source with LazInk's own machinery: the
    per-character colour/style callback `TInkEdit` already has
    (`OnGetCharAttrs`), in a **multi-line** plain-text editor - a
    `TInkCodeMemo`, or a plain-text mode of `TInkRichEdit`.  Headings,
    `**bold**` markers, `` `code` ``, links, list markers and quotes in
    their own colours.  Markdown is the only language it colours - see
    "Code blocks and syntax highlighting".
  * If that editor turns out to be worth having on its own, it belongs in
    the package: a canvas-drawn multi-line editor with per-character
    colouring is useful well beyond this demo.
* Keeping the source and the preview scrolled together is nice, not
  essential.

**Done when:** the demo builds on Lazarus trunk and on the current stable
release, starts with `README.md` rendered, can edit and save a file, and
the README has a screenshot of the tab.

### P6. Heckers Sketch's help pages inside the program

Mostly ready on LazInk's side (`TInkPage` renders the whole manual).  What
Heckers Sketch will need when it gets there:

* P1 and P4, so the pages can be scrolled by finger and copied from.
* **Loading a folder of pages beside the executable** - already works with
  `LoadFromFile` and relative paths.  Remote fetching stays the host's job
  (`OnResource`).
* A **contents list** in place of the site's CSS card grid (the grid is
  deliberately not supported).
* **Back/Forward buttons** a host can wire to `Back`/`Forward`, with
  `CanGoBack`/`CanGoForward` so they can be enabled and disabled.
* **Find in page** (Ctrl+F) - nice to have, after P4, since it reuses the
  highlight.

---

## 4. After that - general purpose

In rough order of value to other Lazarus developers:

1. **A WYSIWYG Markdown editor** - `TInkRichEdit` reading and writing
   Markdown: headings, lists, links, code, then tables.  A search of the
   Online Package Manager's catalogue (16 September 2026) found nothing for
   Lazarus that **renders** Markdown natively, and nothing that **edits** it
   WYSIWYG.  HtmlViewer, LazRichView and RichMemo are the nearest, and none
   of them does Markdown.  This is where LazInk could be unique.
2. **An editor-plus-preview component** (SynEdit + `TInkPage`) as a
   **separate, optional package** (`lazink_synedit.lpk`), so the core
   package stays free of SynEdit and GPL code.
3. **Other widgetsets actually run** - win32, qt5/qt6, cocoa, gtk2 - with
   the results written into the README.
4. **An Online Package Manager listing.**
5. Nested and merged table cells, and more CSS only where a real document
   needs it.
6. The **code-highlighting hook** described below, and a demo of it
   wired to SynEdit's highlighters in a **separate, optional** package, so
   nobody has to write the glue themselves.

### Code blocks and syntax highlighting

GitHub colours a fenced code block by the language named after the opening
fence (` ```pascal `, ` ```python `), and people coming from GitHub will
expect a Markdown component to do the same.  **LazInk will not do that
itself** - a highlighter per language is a large, never-finished job, and
SynEdit already does it well.  But it must not look like an oversight, so:

* **Code blocks are shown well without colour**: monospace, a background
  from CSS (`pre`, `code`), whitespace kept, no word wrapping, and a
  horizontal scroll or clipping for long lines rather than a wrapped mess.
* **The language is kept** (`class="language-pascal"`), so a host can see
  it.
* **A hook**: an event such as

  ```pascal
  TInkCodeBlockEvent = procedure(Sender: TObject; const Language,
    Code: string; var Markup: string; var Handled: Boolean) of object;
  ```

  on `TInkPage` (and the other viewers): LazInk passes the language and the
  plain code, and a host that wants colour returns LazInk markup with
  `<font color=...>` spans.  Unhandled blocks are drawn plain.  A host can
  drive SynEdit's highlighters from this, or its own tokenizer.
* **Said plainly in the README**, under Limits: "LazInk does not colour
  code.  Use `OnCodeBlock` to plug in a highlighter - SynEdit's work
  well."
* A small example of the hook in the demo - a handful of Pascal keywords
  in bold is enough to show how it works, without becoming a highlighter.

The one language LazInk *does* colour is Markdown itself, in the demo's
source pane (P5), because that is LazInk's own business.

---

## 5. What not to do

* **Don't build a browser** or chase CSS conformance.
* **Don't use or depend on `TSynMarkdownSyn`** - not in the package, not
  in the demo.
* **Don't ship syntax highlighters for programming languages.**  Provide the
  hook; let hosts bring their own.
* **Don't make the package depend on SynEdit** or on any GPL code.
* **Don't make separate "Markdown" versions of each control** - use
  `TextFormat`.
* **Don't put Heckers Sketch specifics in LazInk.**  If Heckers Sketch
  needs something, build the general version.
* **Don't claim support that hasn't been run** (widgetsets, touch hardware).

---

## 6. Working on it

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
  python3 tests/check_help_text.py pages.txt results/
  ```

  Heckers Sketch's manual is a good folder for this: `docs/help` in its
  repository.
* Heckers Sketch builds against LazInk from `../LazInk/lazink.lpk`, so a
  change here reaches it on its next build.  Keep `tests/run.sh` green
  before pushing.
* Update `README.md`, `docs/HELP_COMPATIBILITY.md` and this file as items
  land.  Commit finished work; don't leave it uncommitted.

---

## 7. History

* **August 2021** - started as an HTML-formatted list box from a Lazarus
  forum thread (see the README credits); the renderer comes from JVCL.
* **1 September 2026** - LazInk 0.9: `TInkLabel`, `TInkEdit`, `TInkMemo`,
  `TInkListBox`; the renderer renamed `InkHtml`.
* **16 September 2026**
  * `TInkRichEdit`, `TInkPage`, tables, Markdown input, the CSS reader,
    animated GIFs, the test suite, and the MIT/MPL licence files.
  * Published at https://github.com/TonyStone31/LazInk.
  * First real use: Heckers Sketch's What's New window.  `TInkPage` learned
    drag-to-scroll for Windows touch screens first.
  * `TInkScrollBar`, coloured from CSS `scrollbar-color` /
    `scrollbar-width`; `var()` fallbacks and nesting.
  * Found in real use: touch does not scroll on Linux (P1), and text cannot
    be copied (P2, P4).
