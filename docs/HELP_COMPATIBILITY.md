# Heckers Sketch help compatibility

Target: https://tonystone31.github.io/noella-etch-a-sketch/

Audited from the published site on 16 September 2026. `tools/audit_help.py`
downloaded every linked local page, image, and stylesheet. The inventory in
`help-site-audit.json` records 38 HTML pages, 19 tables, 182 table rows, 54 header
cells, 469 data cells, 191 links, 248 keyboard labels, 271 code spans, and nine
image references. The downloaded snapshot had no broken internal references.

## Native page viewer

`TInkPage` loads the original files. It uses LazInk's canvas renderer, a native
scrollbar, and FPC's image decoders. No browser engine or new external rendering
library is required. The older label/memo/list-box renderer remains a smaller
inline-markup renderer; use `TInkPage` for complete HTML documents.

Supported content in this site:

- Document titles; headings; paragraphs; navigation and footer text.
- Ordered and unordered lists, including indentation for nested lists.
- Bold, italic/emphasis, code and keyboard labels. Code/key labels use a
  monospace face and their stylesheet background color.
- Table rows, headers, cells, wrapping, and cell links.
- PNG screenshots and animated GIFs, constrained to the available width.
- Figures/captions and visible text in screenshot placeholders.
- Numeric HTML entities and every named entity used in the audited site.
- Relative local page, stylesheet, and image references; anchor navigation;
  Back and Forward. Browser history scroll restoration is not implemented.
- HTML or Markdown as input (see the README for the Markdown read).
- Code blocks (`<pre>`): whitespace kept, fixed face, shaded background, long
  lines cut off at the block's edge.
- Blockquotes with a bar, horizontal rules, `<dl>`/`<dt>`/`<dd>`,
  `<del>`/`<ins>`/`<mark>`, task-list checkboxes, `<q>` (quotation marks).
- `<details>`/`<summary>`: what a `<details>` holds is folded away behind its
  summary, which wears a triangle and opens or shuts on a click, as in a
  browser. `open` starts it open, and a `<details>` with no summary stays
  open because nothing could open it. `TInkPage.FoldOpen`, `ToggleFold` and
  `BlockVisible` let a program do the same.
- A table's `<caption>`: a line of its own above the table.
- `title` on a link: its tooltip while the pointer is over it.
- What is inside `<svg>` or `<template>` is not drawn or read out.
- Lists with hanging markers: bullets and numbers sit to the left of the
  text, and wrapped lines line up under the first word. `<ol start>`, `<ol
  type>` and `list-style-type` (`decimal`, `lower-alpha`, `upper-alpha`,
  `lower-roman`, `upper-roman`, `disc`, `circle`, `square`, `none`).
- Table cell alignment from `align` or `style="text-align: ..."`.
- `id` on any element, and `<a name>`, as anchors.
- A program's own CSS (`TInkPage.StyleSheet`) beneath the page's.

`OnLinkClick`, when assigned, replaces built-in navigation. Hosts can use it to
route external links, report errors, or call `LoadFromURL` themselves. Local
resource failures raise an exception for a page, fall back to the control theme
for a missing stylesheet, and display alternate text for a missing image.

## Deliberately limited CSS

The reader accepts external stylesheets and embedded `<style>` blocks. It
supports element, class, and element-with-class selectors, descendant and child
selectors (`table.cards td`, `nav > a`) where the page knows the ancestors - table
cells, and what is inside them - comma-separated selectors, source order and
simple specificity. `:root` custom properties and `var(--name)` allow the site's
existing palette to work. Colors may be `#rgb`, `#rrggbb`, `rgb()`/`rgba()`,
names, or `none`/`transparent`.

The native layout uses `color`, `background`, pixel `font-size`, single-value
pixel `padding`, pixel `margin-top`/`margin-bottom`, the color from a simple
`border` declaration, and `.wrap`'s pixel `max-width`.

Tables read more (this is what makes Heckers Sketch's `table.cards` index look
as it does in a browser): on the table, `width: 100%`, `table-layout: fixed`
(or a `%` width on its cells) for equal columns, `border-collapse` and
`border-spacing`, and `margin` including negative left/right; on its cells
(`td`, `th`, with classes), `padding` in one to four values, `background`,
`border` / `border-color` / `border-top` ... `border-left` (including `none`),
`border-radius`, `color` and `text-align`. `<small>` is smaller, colored by
`small` rules in context, and `a { text-decoration: none; color }` applies
inside a table. Code/key font selection is
semantic. The control's Font supplies the base font.

The scrollbar is LazInk's own and takes `scrollbar-color` (thumb and track:
hex, color names, `rgb()`/`rgba()`, `currentcolor`, `var()`) and
`scrollbar-width` (`auto`, `thin`, `none`) from `html`/`:root`, falling back
to `body`.  `var()` takes a fallback - `var(--x, #fff)` - and nests; a value
whose variable cannot be resolved is dropped rather than overriding an
earlier valid one, and a variable that refers to itself resolves to nothing.
The bar keeps its width whether or not the page overflows, like
`scrollbar-gutter: stable`.

This is **not CSS conformance**. In particular:

- `display: flex` and `display: grid` containers lay their children out as
  cards in rows: `flex-wrap: wrap` and `grid-template-columns` with
  `auto-fill`/`auto-fit` and `minmax(Npx, ...)` fit as many to a row as the
  width allows (the item width from `flex-basis`, `flex`, `min-width`,
  `width` or `minmax`, the gap from `gap`/`column-gap`); `repeat(N, ...)` or
  a list of tracks gives N columns; a row that does not wrap sizes its items
  to their content. Items keep their background, border, radius and padding;
  inside an item, headings are bold lines and blocks are line breaks.
  Justification, alignment, ordering, growing and shrinking are not read.
- `@media` blocks with `min-width` / `max-width` apply against the page's own
  width, and the page is read again when a resize crosses one; other media
  (print, color schemes, orientation) never apply. `display: none` hides any
  element, and `display: block` on table cells stacks them one to a row -
  Heckers Sketch's index does both below 600 pixels, as in a browser.
  Positioning is ignored.
- A `style` attribute is read: `color`, `background`/`background-color`,
  `font-size`, `font-weight`, `font-style` and `text-decoration` on a word or
  a span, and those plus `text-align`, `margin-top`, `margin-bottom` and
  `padding` on a block, where it beats what the stylesheet said. An element's
  `align`, a `<center>`, and `text-align` from the stylesheet center or
  right-align a block's lines.
- Descendant selectors only match inside tables and flex containers (the
  places the page keeps its ancestors); pseudo-classes (`:first-child`,
  `:hover`) and general CSS inheritance are not implemented.
- Shorthand font declarations, shorthand margins outside tables, line-height,
  letter spacing, uppercase transforms, individual column widths, and dashed or
  dotted border styles are not reproduced.
- No row/column spans or nested tables; cells align to the top; long unbroken
  words can overflow a cell.
- GIFs loop continuously; finite loop counts and transparent-page compositing
  are not supported. The site's GIF is opaque and loops continuously.
- No JavaScript, forms, video, general web fonts, or arbitrary website support.

The aim is to preserve the help content and navigation in a native layout,
without maintaining a second version of the manual or building a browser.

## Local and remote resources

For a bundled copy, preserve the site's directory structure and call:

```pascal
InkPage1.LoadFromFile('/path/to/help/index.html');
```

For generated HTML, use `LoadHTML(HTML, BaseURL)` so relative references have a
base. `Source` and `TextFormat` can also be assigned directly.

Remote transport is intentionally a host responsibility at this stage.
`LoadFromURL` resolves a URL; `OnResource(Sender, URL, Destination, Handled)`
lets the host fill a stream from its HTTP client or cache. Return `Handled=True`
and leave the stream open. The event is synchronous; a host should prefetch/cache
network resources to avoid blocking its UI. There is no built-in HTTP downloader,
and entering an HTTPS URL alone will not fetch the website.

## Validation

Built with FPC 3.3.1 and Lazarus trunk on GTK3/Linux x86-64. Tests covered:

- HTML/Markdown conversion and tables, malformed input, escaping, table link
  ordinals and hit testing, and changes of control input format.
- All 38 published pages at 360, 700, and 1100 pixel control widths.
- Every image reference decodes; the animated GIF's frame count matches a
  count taken by walking the file's own blocks.
- Every one of 2,134 visible HTML text fragments survives page parsing.
- Initial GIF frames match Pillow's independent compositing result pixel for
  pixel. This is not an exhaustive comparison of all animation frames.
- Native previews of the contents, commands, keyboard table, and line-tool page.
- Demo build and startup with a local help page.

These checks establish content coverage of this snapshot, not pixel identity
with a browser or validation of every widgetset. The GTK3 runtime emits its
existing `DefaultWndHandler` warning during the control tests.

Reproduce the audit and content checks:

```sh
tools/audit_help.pas https://tonystone31.github.io/noella-etch-a-sketch/ \
  --download /tmp/lazink-help --output /tmp/help-audit.json
find /tmp/lazink-help -name '*.html' | sort > /tmp/help-pages.txt
mkdir -p /tmp/help-results
LAZARUS_DIR=/path/to/lazarus FPC=/path/to/fpc \
  tests/run.sh /tmp/help-pages.txt /tmp/help-results
```

`tools/audit_help.pas` is a Pascal script for `instantfpc`, which comes with
Free Pascal - run it directly, or as `instantfpc tools/audit_help.pas ...`
when instantfpc is not on your PATH.  `tests/run.sh` checks the visible text as well when it is given a page list
and a results folder.  Both tools read the pages with the FCL's own HTML
reader, so they check LazInk against an independent reading of the same
files.

The optional site tests assert the audited snapshot's image/frame counts. If the
site adds images or replaces its animation, review and update those expectations.
