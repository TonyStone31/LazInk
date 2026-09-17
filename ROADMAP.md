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
  the package must **not** depend on SynEdit or any GPL code - see 6.
* **No syntax highlighting of code, by decision.**  LazInk shows code
  blocks clearly and leaves colouring to SynEdit - see "Code blocks and
  syntax highlighting" below.
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
  for the JVCL-derived renderer (`inkhtml.pas`, `inktables.inc`), until
  the renderer is replaced and the whole package moves to a no-conditions
  licence - see 4.

---

## 2. Where it stands

| Control | What it does now | Missing |
|---|---|---|
| `TInkLabel` | inline markup, HTML or Markdown, copy menu | character selection |
| `TInkMemo` | lines of markup, whole-document Markdown, copy menu, Ctrl+A/Ctrl+C by line | character selection |
| `TInkListBox` | markup items, in-place editor, copy menu, Ctrl+A/Ctrl+C by item | character selection |
| `TInkPage` | whole HTML or Markdown documents: headings, lists, tables, code/kbd, PNG and animated GIF, links, anchors, Back/Forward, small CSS reader, themed scrollbar, drag-to-scroll, GitHub-flavoured Markdown, code blocks, quotes, hanging list markers, a host stylesheet, GTK3 touch and flick, mouse selection and copy menu | hardware check of touch; find in page |
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

**Built (16 September 2026); the hardware check is still to do.**
`inktouch.pas`: `InkHookTouch(Control, Handler)` connects to `touch-event`
on the control's own GDK window (`GetContainerWidget`) from `CreateWnd`, one
hook per window, freed with it, first finger only, coordinates converted to
the control's client area.  `InkHookTouchAsMouse` sends touches on as LCL
mouse messages, used by `TInkEdit`, `TInkRichEdit` and `TInkScrollBar`.
`InkMouseIsTouch` reads Windows' pen/touch signature from the current
message, for P4.  Everything is `{$IFDEF LCLGTK3}` / `{$IFDEF WINDOWS}`; qt5
and qt6 need nothing, since no LCL widget there accepts raw touch and Qt
turns fingers into mouse events.  The package's output folder now includes
`$(LCLWidgetType)`, because this unit is widgetset-specific.

`TInkPage` feeds touches and mouse into the same grab (`GrabBegin` /
`GrabMove` / `GrabEnd`, same slop and link rules) and remembers whether a
finger made it (`FGrabFinger`); mouse events within half a second of a
touch are ignored, in case a platform sends both.  A quick finger drag
flicks (`FlickScroll`); a mouse drag does not.  `TInkPage.Touch` is public.

Tested: finger drag, tap, cancel, drag ending on a link, flick both ways,
stopping a flick, and the real GTK path - `gtk_widget_event` with GDK touch
events made in the test, including a second finger that must be ignored,
and a tap on the scrollbar.  Not yet done: the check on Tony's wife's Linux
Mint machine, and a Windows run.  `TInkLabel` is a graphic control with no
window, so on GTK3 a finger does not reach its links.

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

**Done (16 September 2026), together with P4.**  `inkcopymenu.pas` holds
the menu the display controls share: Copy (the selection), Copy this
paragraph / line / item (under the pointer), Copy link address (over a
link), Copy all, Select all, with `CopyMenu` to turn it off, a program's
own `PopupMenu` taking precedence, and `OnCopyMenu` to add items (the menu
is rebuilt each time).  `TInkMemo` and `TInkListBox` copy their selected
lines with Ctrl+C and everything after Ctrl+A; `TInkLabel`, which has no
keyboard, gets the menu.  Tests click the menu items and read the
clipboard.  Captions are resourcestrings.

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

**Done (16 September 2026).**  `inkmarkdown.pas` now parses blocks and
writes real HTML (`MarkdownToHTML`); `MarkdownToInk` flattens that for the
inline controls.  Everything listed above is in, plus setext headings with
GitHub's anchors, reference links, bare URLs, indented code, `> [!NOTE]`
alerts and entities.  `TInkPage` learned `<pre>`, `<blockquote>`, `<hr>`,
hanging markers, `list-style-type`, task boxes, cell alignment,
`LoadMarkdown`, `.md` files by name, a first-heading title, and a
`StyleSheet` property for the host's CSS.  Both documents render; tests
cover each construct.  Found on the way and fixed in the renderer: table
columns were squeezed in proportion (now longest word first), and wrapping
was slow - the whole `WHATS_NEW.md` (118 KB) lays out in 0.19 s instead of
0.9 s.

For Heckers Sketch: `uWhatsNew.ReleaseNotesHTML` can become
`FPage.StyleSheet.Text := <its CSS>` and `FPage.LoadMarkdown(<the sections
to show>)`; picking the sections stays in the program.

Still simplified: emphasis does not follow the full CommonMark delimiter
rules, link definitions must fit on one line, no footnotes, and an image
inside a table cell shows its alt text.

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

**Done for `TInkPage` (16 September 2026).**  The renderer reports each
run of text it lays out (`THTMLOptions.OnRun`: text, position, line, part,
font) - a few lines in the MPL renderer, and the one thing the new renderer
must provide too.  `TInkPage` lays a block out once more with that hook
(`htmlHyperLink` mode, so nothing is painted) and keeps the runs; a block's
**words** are the runs joined by whatever lay between them in the source's
plain text - a space where a line wrapped, a line break, a tab between
cells.  `TInkRichEdit` was read first: it keeps its own per-character
layout and never uses the HTML renderer, so the page could not borrow it.

`PositionAt(X, Y)` finds the nearest line and run and the nearest gap
between characters; `PositionPoint` goes back.  Positions are (block, byte
offset) and survive a new layout.  Mouse: drag, double-click (words),
triple-click (blocks), Shift+click, auto-scroll past the edges; Ctrl+A,
Ctrl+C and Ctrl+Insert.  The selection goes to X11's primary selection on
release.  Copy is plain text (list markers kept, tables as tab-separated
rows) plus HTML through `Clipboard.SetAsHtml`.  `SelectionColor`, else
`::selection`, else the system highlight blended into the page.
`MouseDrag` (`imdSelect`, `imdScroll`): the mouse selects by default, a
finger always scrolls - GTK3 touches through P1, Windows' marked mouse
messages through `InkMouseIsTouch`.  Tests cover the hit test both ways,
every selection gesture, the painted highlight, the copied text and HTML,
the menu, and a finger that must still scroll.

Not done: character selection in `TInkLabel`, `TInkMemo` and `TInkListBox`
(they have the copy menu and line-level copying instead); inline code keeps
its own background over the highlight; keyboard selection (Shift+arrows).
On Qt and GTK2 a finger cannot be told from the mouse, so there it selects
unless `MouseDrag := imdScroll`.

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

## 4. A renderer of our own, and a licence with no strings

**Tony:** "eventually we want our own complete replacement... I want a
license that is almost zero restrictions... do whatever you want with this
code.  I still want to have jedi jcvhtml credited of course, maybe at least
as inspiration and getting it off the ground for us."

### Why

LazInk's renderer, `inkhtml.pas` (with `inktables.inc`), is derived from
Project JEDI's JVCL and stays under **MPL 1.1** - it still contains JVCL
routines line for line (see `THIRD_PARTY_NOTICES.md`).  MPL is a fair
licence, but it has conditions: the covered files keep their licence, and
anyone shipping a program built with them owes recipients that source.  So
LazInk cannot be "do anything you like" while those two files are in it,
and relabelling them is not an option - **only code we wrote ourselves can
be relicensed.**

Replacing the renderer is also the natural moment to get HTML right: the
JVCL code was an inline-markup drawer that has been stretched to tables and
pages.  A renderer designed for documents from the start can be both leaner
and more capable.

### The licence to move to

For "do whatever you want", in order of preference:

1. **0BSD** (Zero-Clause BSD) - one paragraph, no conditions at all, not
   even keeping the notice; OSI-approved, so companies' lawyers recognise
   it.  **Recommended.**
2. **MIT-0** - the MIT licence with the attribution condition removed; also
   OSI-approved.
3. **The Unlicense** - a public-domain dedication with a fallback licence
   for countries without public domain.  Fine, but less widely accepted by
   corporate policies than 0BSD.

Avoid **WTFPL**: it says the right thing, but several large companies ban it
because it is not a real legal instrument, which defeats the purpose.

This is not legal advice - read the one you pick before switching.

### How to do it without carrying JVCL code across

The new renderer has to be **genuinely new code**, not `inkhtml.pas`
rewritten line by line, or it is still derived.

* Write it from a **behaviour specification**, not from the old source:
  `docs/HELP_COMPATIBILITY.md`, the test suite, and a list of what each tag
  and CSS property does (write that list first, in `docs/RENDERER_SPEC.md`).
* Use a **different design**, which is the honest evidence that it is new:
  parse the document into a small tree of elements -> resolve styles ->
  lay out boxes (block, inline, table, list item) -> paint.  The JVCL code
  draws while it parses; the new one should not.
* New files and unit names (for example `inkdom.pas`, `inklayout.pas`,
  `inkpaint.pas`).  Don't open `inkhtml.pas` while writing them; if you
  have read it, work from the specification rather than from memory of the
  code.
* Keep the **public API** the controls use today (`HTMLDrawOpt`,
  `HTMLTextExtentOpt`, `HTMLHitTest`, `HTMLPlainText`, `HTMLStringToColor`
  and friends) as thin wrappers over the new engine, so `TInkLabel`,
  `TInkMemo`, `TInkListBox`, `TInkPage` and `TInkRichEdit` switch over
  without rewrites.  `HTMLStringToColor` is one of the routines still
  matching JVCL exactly - write a new one.
* Run **both renderers side by side** behind a switch while it is being
  built, and compare their output on the test pages.

### Then

1. The new renderer passes every existing test, renders all of Heckers
   Sketch's `docs/help` pages completely (`tests/run.sh pages.txt ...` and
   `check_help_text.py`), and is at least as fast.
2. Delete `inkhtml.pas` and `inktables.inc`.
3. **Check provenance of every remaining file before relicensing.**  All of
   them say MIT today, but `inklistbox.pas` grew out of wp's forum list box
   example (via Tony's demo built on it) - confirm what, if anything, of
   that example is still in it, and rewrite whatever is.  The goal is that
   **no code from JVCL or from the forum example remains** - the forum
   thread is credited as where LazInk came from, not as a source of code.
   Relicense only files whose authors agree; anything uncertain gets
   rewritten too.
4. Switch `LICENSE` to the chosen licence, drop `LICENSES/MPL-1.1.txt`,
   update the SPDX lines and `lazink.lpk`'s licence field.
5. **Keep the credit.**  The story, as Tony tells it: he started the forum
   thread in 2021 wanting simple HTML to decorate list box text; wp
   suggested taking what was needed from JVCL and helped make it happen;
   Tony's demo on that example is where the idea for LazInk was born; and
   the components have been LazInk's own since.  `THIRD_PARTY_NOTICES.md`,
   the README and the demo's Credits tab keep saying so - JVCL, wp and the
   other forum helpers as where it started, `TDzHTMLText` as a source of
   ideas (no code) - with no borrowed code left in the package.  This is
   not about discrediting anyone; Tony sees how code should be shared
   differently, and that is only possible with code written for LazInk.
   Keep `docs/RENDERER_CHANGES.md` as a record of the old renderer.

### What the new renderer should learn

Kept lean and fast - no scripting, no full CSS - but enough for people to
write good-looking documents.  Most of these are things Heckers Sketch's
help pages already use and LazInk currently drops (see
`HELP_COMPATIBILITY.md`):

1. **The `style` attribute** - `<span style="color:#c00">`.  The most common
   way people colour one thing.
2. **`<span>` and `<div>` with classes**, styled from the stylesheet.
3. **Simple descendant selectors** - `.sheet td`, `nav a` - and child
   selectors.  Real stylesheets are written this way.
4. **Proper whitespace rules** - collapsing in normal text, kept in `<pre>`,
   `&nbsp;` respected.
5. **Box model basics** - margin and padding shorthand (1 to 4 values),
   `border` with width/style/colour, `border-radius`, `background-color`
   on any block.
6. **Text styling** - `line-height`, `text-align`, `font-weight`,
   `font-style`, `text-decoration`, `text-transform`, `letter-spacing`,
   `font-family` stacks with a monospace fallback, `em`/`rem`/`%` sizes.
7. **Lists done properly** - hanging markers, nested lists, `decimal`,
   `lower-alpha`, `upper-roman`, `none`, `<ol start>`.
8. **Tables done properly** - `colspan`/`rowspan`, `<thead>`/`<tbody>`,
   column widths from `width`, cell padding, `border-collapse`, header
   backgrounds, zebra striping by class.
9. **Images** - `width`/`height` attributes, `max-width: 100%`, alt text
   when missing, float left/right with text wrapping round them.
10. **More elements** - `<dl>`/`<dt>`/`<dd>`, `<blockquote>`, `<pre>`,
    `<small>`, `<mark>`, `<del>`/`<ins>`, `<abbr title>` (tooltip),
    `<details>`/`<summary>` (click to open), `<figure>`/`<figcaption>`.
11. **Code blocks** - monospace, a background, whitespace kept, no wrapping,
    long lines clipped or scrolled.  See below.
12. **The full named-entity table** and correct UTF-8 everywhere, emoji
    included.
13. **Link titles as tooltips**, and anchors on any element with an `id`.
14. **A simple flex row** (`display: flex` with wrapping) - enough for card
    grids like the Heckers Sketch help index, instead of stacking them.
15. **Hi-DPI** - everything scales with the control's font and the screen.
16. **Speed** - lay a page out once per width and cache it; paint only
    what is on screen; re-lay out only what changed.  Use the 38-page
    Heckers Sketch manual as the benchmark and keep a timing for it.

Not wanted: JavaScript, forms, video, web fonts, positioning, animations,
media queries beyond maybe one width breakpoint.

---

## 5. After that - general purpose

In rough order of value to other Lazarus developers:

1. **A WYSIWYG Markdown editor** - `TInkRichEdit` reading and writing
   Markdown: headings, lists, links, code, then tables.  A search of the
   Online Package Manager's catalogue (16 September 2026) found nothing for
   Lazarus that **renders** Markdown natively, and nothing that **edits** it
   WYSIWYG.  HtmlViewer, LazRichView and RichMemo are the nearest, and none
   of them does Markdown.  This is where LazInk could be unique.
2. **Other widgetsets actually run** - win32, qt5/qt6, cocoa, gtk2 - with
   the results written into the README.
3. **An Online Package Manager listing** - after the licence change, so it
   goes out under the licence it will keep.

### Code blocks and syntax highlighting

GitHub colours a fenced code block by the language named after the opening
fence (` ```pascal `).  **LazInk will not colour code** - that is what
SynEdit is for, and anyone whose program is mainly about showing or
editing code should use SynEdit.  LazInk is for documents that sometimes
contain code: READMEs, release notes, help pages.

* **Code blocks look like code**: fixed-width font, a shaded background
  from CSS (`pre`, `code`), whitespace kept, no word wrapping, long lines
  clipped or scrolled rather than wrapped.  This is the feature.
* **The language name is kept** (`class="language-pascal"`), as GitHub
  does.  It costs nothing.
* **The README says it once**, under Limits: "LazInk shows code blocks but
  does not colour them - for that, use SynEdit."
* A hook for a host to colour code itself is a **maybe, later, only if
  somebody asks**.  No SynEdit glue, no add-on package.

The one thing LazInk colours as source is Markdown itself, in the demo's
editor tab (P5), because Markdown is LazInk's own business.

---

## 6. What not to do

* **Don't build a browser** or chase CSS conformance.
* **Don't use or depend on `TSynMarkdownSyn`** - not in the package, not
  in the demo.
* **Don't colour code** or build SynEdit glue - see "Code blocks and syntax
  highlighting".
* **Don't make the package depend on SynEdit** or on any GPL code.
* **Don't make separate "Markdown" versions of each control** - use
  `TextFormat`.
* **Don't put Heckers Sketch specifics in LazInk.**  If Heckers Sketch
  needs something, build the general version.
* **Don't claim support that hasn't been run** (widgetsets, touch hardware).
* **Don't port `inkhtml.pas` line by line** into the new renderer, and don't
  relicense a file until its provenance is checked - see 4.

---

## 7. Working on it

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
* **A stale demo build**: `lazbuild` can miss an edit to `demo/main.lfm`
  made in the same second as the build, and the demo then shows the old
  form.  `rm -rf demo/lib` and build again.  (`lazbuild -B` rebuilds
  Lazarus itself and fails without `--lazarusdir`.)
* Update `README.md`, `docs/HELP_COMPATIBILITY.md` and this file as items
  land.  Commit finished work; don't leave it uncommitted.

---

## 8. History

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
