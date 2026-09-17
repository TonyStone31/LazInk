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
  monospace face and their stylesheet background colour.
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
  `<del>`/`<ins>`/`<mark>`, task-list checkboxes.
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
supports simple element, class, and element-with-class selectors, comma-separated
selectors, source order and simple selector specificity. `:root` custom properties
and `var(--name)` allow the site's existing palette to work.

The native layout uses `color`, `background`, pixel `font-size`, single-value
pixel `padding`, pixel `margin-top`/`margin-bottom`, the colour from a simple
`border` declaration, and `.wrap`'s pixel `max-width`. Code/key font selection is
semantic. The control's Font supplies the base font.

The scrollbar is LazInk's own and takes `scrollbar-color` (thumb and track:
hex, colour names, `rgb()`/`rgba()`, `currentcolor`, `var()`) and
`scrollbar-width` (`auto`, `thin`, `none`) from `html`/`:root`, falling back
to `body`.  `var()` takes a fallback - `var(--x, #fff)` - and nests; a value
whose variable cannot be resolved is dropped rather than overriding an
earlier valid one, and a variable that refers to itself resolves to nothing.
The bar keeps its width whether or not the page overflows, like
`scrollbar-gutter: stable`.

This is **not CSS conformance**. In particular:

- Cards stack vertically. CSS grid, flexbox, positioning and media queries are
  ignored. Content still wraps and images shrink with the control.
- Descendant selectors, pseudo-classes, inline `style` attributes, and general
  CSS inheritance are not implemented. Alias-cell colours therefore fall back
  to the normal text colour.
- Shorthand font/margin declarations, multi-value padding, line-height, rounded
  corners, letter spacing, uppercase transforms, border-collapse, and individual
  border styles are not reproduced.
- Tables use a simple grid and content-derived column widths. No row/column
  spans, nested tables, or explicit column widths; long unbroken words can
  overflow a cell. The audited site has no spans or nested tables.
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
- All nine image references decode; the animated GIF contains 90 frames.
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
python3 tools/audit_help.py https://tonystone31.github.io/noella-etch-a-sketch/ \
  --download /tmp/lazink-help --output /tmp/help-audit.json
python3 - <<'PY'
from pathlib import Path
Path('/tmp/help-pages.txt').write_text('\n'.join(
    str(p) for p in sorted(Path('/tmp/lazink-help').rglob('*.html'))))
Path('/tmp/help-results').mkdir(exist_ok=True)
PY
LAZARUS_DIR=/path/to/lazarus FPC=/path/to/fpc \
  tests/run.sh /tmp/help-pages.txt /tmp/help-results
python3 tests/check_help_text.py /tmp/help-pages.txt /tmp/help-results
```

The optional site tests assert the audited snapshot's image/frame counts. If the
site adds images or replaces its animation, review and update those expectations.
