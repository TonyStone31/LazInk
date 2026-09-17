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
* **Still open:** trying the other widgetsets (only GTK3 has been run), and
  the first real use inside Heckers Sketch - which will show what is missing.

The rest of this file is the original list, kept for the reasoning.

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
