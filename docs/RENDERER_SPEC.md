# LazInk renderer specification

Written 17 September 2026.  This is the **behavior** the drawing engine has
to produce, written down so a new one can be built **from this document and
the test suite**, without reading the JVCL-derived code it replaces.  See
ROADMAP.md section 4 for why: `inkhtml.pas` and `inktables.inc` are MPL 1.1,
and they are the only thing keeping the package off a no-conditions license.

**How to use it.**  Build to this document.  Do not open `inkhtml.pas` or
`inktables.inc` while writing the new engine; if you have read them, work
from here instead of from memory of the code.  Where this document and the
old code disagree, `tests/run.sh` decides - the tests are the spec in
executable form.

---

## 1. What the renderer is, and is not

LazInk reads a document in three layers.  Only the third is being replaced.

| Layer | Where | License | Job |
|---|---|---|---|
| Document | `inkpage.pas`, `inkmarkdown.pas`, `inkcss.pas` | MIT, ours | HTML or Markdown, plus CSS, into **blocks**: a paragraph, a heading, a list item, a code block, a picture, a table, a card grid.  Each block is a short string of **LazInk markup**. |
| Controls | `inklabel.pas`, `inkmemo.pas`, `inklistbox.pas`, `inkpage.pas`, `inkrichedit.pas` | MIT, ours | Where blocks go on screen, scrolling, selection, find, history, clipboard, touch. |
| **Renderer** | `inkhtml.pas`, `inktables.inc` | **MPL 1.1** | Given a canvas, a rectangle and one string of LazInk markup: **measure it, wrap it, paint it, and say what is under a point.** |

So the new renderer does **not** read HTML, does not read CSS, and does not
know about documents, scrolling or selection.  It is a canvas text engine
for one small markup language.  Everything else already belongs to us.

That markup language is section 3, and it is the whole contract.

---

## 2. The design to write it to

The old engine draws while it parses, in one pass over the string.  The new
one must not - both because a different design is the honest evidence that
it is new code, and because it is the only way to get tables, hanging
markers and selection right without special cases.

Four stages, each testable on its own:

1. **Tokenize** the markup into text runs and tags.  No canvas needed.
2. **Style**: fold the tags into a stack, so every text run carries the font
   name, size, style set, color, background color, link ordinal and
   alignment that apply to it.  No canvas needed - this stage is pure, and
   is where most of the tests can live.
3. **Lay out**: measure the styled runs on the canvas, break them into lines
   that fit a width, and place each run's rectangle.  This is where wrapping,
   line height, super/subscript, alignment, indents and tables happen.  The
   result is a **line box list**, which the caller may keep.
4. **Paint** the laid-out lines onto the canvas, and nothing else: no
   measuring, no wrapping decisions.

Measuring, hit testing and painting then all read the same layout, which is
what makes "what is under the pointer" agree with what was drawn.

**Caching.**  Layout must be reusable: the same markup at the same width,
font and scale must not be laid out twice.  A page of 500 blocks is laid out
once per width and painted on every scroll, so paint must be cheap and must
be able to skip lines that are off screen.

---

## 3. The markup language

This is what the document layer emits and the renderer must accept.  It is
deliberately tiny and it is *not* HTML: no nesting rules are enforced, no
unknown tag is an error (an unknown tag is dropped), and attributes are
simple.  Tag names and attribute names are **case-insensitive**.

### 3.1 Inline text

| Markup | Meaning |
|---|---|
| `<b>` `</b>` | bold on/off |
| `<i>` `</i>` | italic on/off |
| `<u>` `</u>` | underline on/off |
| `<s>` `</s>` | struck through on/off |
| `<sup>` `</sup>` | superscript: smaller, raised |
| `<sub>` `</sub>` | subscript: smaller, lowered |
| `<font ...>` `</font>` | see below |
| `<a href="...">` `</a>` | a link: link color, underline by default, and a hit-testable region |
| `<br>`, `<br/>` | line break |
| `<hr>` | a horizontal rule across the drawing width |
| `<p>`, `<p/>` | a paragraph break: the same as two `<br>`, except at the very start of the text, where it is dropped |
| `</p>` | nothing |
| `<center>` | from here on, lines are centered in the width |
| `<right>` | from here on, lines are right-aligned |
| `<left>` | from here on, lines are left-aligned (the default) |
| `<ind=N>` | from here on, lines start N pixels in from the left |
| `<img src="N">` | draws image N from the options' `TCustomImageList`, in the line, as tall as the line |

`<font>` takes any of, in any order and unquoted or quoted:

* `color="#rrggbb"` or a color name - the text color.
* `bgcolor="#rrggbb"`, a name, or `none` - the text background.
* `size="N"` - the font size in **points**.
* `face="Name"` - the font family, for example the monospace face.

Every one of these is a **stack**: `</font>` restores what was in force
before the matching `<font>`, and the same for `<b>`, `<i>` and the rest.
Tags left open at the end of the string are closed at the end.  A closing
tag with nothing open is ignored.

Nothing else is markup.  `<` that does not begin a known tag is literal
text, and this happens - documents show markup examples.

### 3.2 Text, entities and whitespace

* The text arriving at the renderer is **UTF-8, already decoded**: the
  document layer turns `&amp;`, `&#8212;` and the named entities into
  characters before it builds markup.  The renderer still has to accept
  `&lt;`, `&gt;` and `&amp;` (it emits them itself through the escape
  routine), and must render a literal ampersand that came from `&amp;`
  without re-reading it as the start of another entity.
* CR and LF in the text are **not** line breaks - only `<br>` is.  They are
  dropped.
* Spaces are drawn as they arrive.  Collapsing runs of whitespace is the
  document layer's job, and it has already done it, except inside code,
  where the spaces are meant.
* Line breaking happens at spaces, and additionally **between any two CJK
  characters** (Chinese, Japanese and Korean do not space their words; a
  line of them must still wrap).

### 3.3 Tables

A table is one block's markup and is laid out as a unit inside the block's
width.

```
<table [attributes]>
  <tr>
    <td [attributes]>cell markup</td>
    <th [attributes]>heading cell</th>
  </tr>
</table>
```

Cells hold ordinary inline markup, including `<br>`, and may begin with
`<center>` or `<right>` for that cell's alignment.  `<th>` is a `<td>` whose
text is bold.  Tables do not nest inside each other in practice, but nested
markup must not crash - draw the inner table's text if nothing else.

Table attributes:

| Attribute | Meaning |
|---|---|
| `width="100%"` | the table fills the block's width; without it, it is as wide as its content needs, up to the block's width |
| `layout="fixed"` | every column the same width |
| `cellspacing="N"` | N pixels between cells, and around the outside |
| `cellpadding="T R B L"` or `"N"` | padding inside every cell |
| `cellbg="#rrggbb"` \| `none` | the default cell background |
| `bordercolor="#rrggbb"` | the default border color |
| `border="none"` | no borders at all |
| `sides="trbl"` | which borders to draw, by letter |
| `radius="N"` | rounded corners, N pixels |

Cell attributes, each overriding the table's: `bgcolor`, `bordercolor`,
`sides`, `border="none"`, `color` (the text color), `radius`.

**Column widths**, when the layout is not fixed: give every column at least
its longest single word, then share what is left over between the columns in
proportion to how much wider each one would like to be.  (Sharing in
proportion to their wanted widths instead makes a column of one-word cells
as wide as a column of sentences; that was a real bug.)  Cells are aligned
to the **top** of their row.

Not supported, on purpose, and to be written down as such:
`colspan`/`rowspan`, per-column widths, nested tables.  These are the first
things to add once the new engine exists - the design must leave room for
them, which the old one does not.

### 3.4 What the plain-text form is

`HTMLPlainText` turns markup into the text a person would copy:

* tags are dropped, entities are resolved;
* `</td>` and `</th>` become a **tab**;
* `</tr>`, `<br>` and `</p>` become a **line ending**.

---

## 4. The API the controls use

The new engine keeps these as its own public routines - same names, same
meanings - so `TInkLabel`, `TInkMemo`, `TInkListBox`, `TInkPage` and
`TInkRichEdit` switch over without being rewritten.  Everything the controls
actually call today is listed here; anything in the old unit that is not in
this list can go.

```pascal
{ options: fonts, scaling, alignment, link and hover looks, image list,
  line spacing, borders, and the run callback used for selection }
function DefaultHTMLOptions(ASuperSubScriptRatio: Double = 0.7;
  AScale: Integer = 100): THTMLOptions;
function InkOptions(...): THTMLOptions;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions);
function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions): TSize;
function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  X, Y: Integer; const Options: THTMLOptions): THTMLHitInfo;
function HTMLWordWrap(Canvas: TCanvas; const Text: string; MaxWidth: Integer;
  SuperSubScriptRatio: Double; Scale: Integer = 100): string;
function HTMLPlainText(const Text: string): string;
function HTMLEscape(const Text: string): string;
function HTMLUnescape(const Text: string): string;
function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;
function HTMLContrastColor(ABackground: TColor): TColor;
function HTMLShadeColor(AColor: TColor; APercent: Integer): TColor;
function HTMLIsCJK(const AChar: string): Boolean;
```

Notes that are part of the contract:

* **`THTMLOptions`** carries: `SuperSubScriptRatio` (how much smaller a
  superscript is), `Scale` (percent, for Hi-DPI), `LineSpacing`, `Borders`
  (padding inside the rectangle), `VertAlign`, `HorzAlign`, `Images`,
  `LinkColor`, `LinkBackColor`, `LinkUnderline`, the four `Hover*` fields
  (`HoverIndex` is which link ordinal is under the pointer), and `OnRun` /
  `RunPart`.
* **`THTMLHitInfo`** answers: `OnLink`, `LinkName` (the href), `LinkText`
  (the words between `<a>` and `</a>`), `LinkIndex` - **the ordinal of the
  link in this string, counting from 1**.  Ordinals are how a control maps a
  click back to the target it stored, so they must count every `<a href>` in
  document order, including ones inside table cells.
* **`OnRun`** is how selection works: while laying out for painting, the
  engine reports every run of text it places - the text, its rectangle, its
  line number, its part number, and its font - so the control can find the
  character under the pointer and paint a selection over the same pixels.
  It must **not** report while measuring, only while drawing, or the runs
  arrive twice.  `RunPart` numbers the parts of a table (each cell is its
  own part) so runs from different cells do not look like one line.
* **`HTMLWordWrap`** re-flows markup by inserting `<br>` at word
  boundaries, and **tags open across an inserted break stay in effect**.
  It must not break before the first word of a line that so far holds only
  tags (a cell starting with `<b>` used to wrap onto a blank line).  The
  canvas must already carry the base font.
* **`HTMLStringToColor`** must be written fresh - the old one is JVCL's line
  for line.  It takes `#rgb`, `#rrggbb`, `clXxx` names, and plain color
  names, and returns `ADefColor` for anything else.

---

## 5. Layout rules

* **Line height** is the tallest thing on the line: the tallest font used,
  plus `LineSpacing`.  A line with only small text is short; one with a
  24-point word is tall.
* **Super/subscript** are drawn at `SuperSubScriptRatio` of the current
  size, raised or lowered by about a quarter of the line, and they do not
  make the line taller than the base font would.
* **Alignment** applies from the tag onward, per line, inside the drawing
  width: `<center>`, `<right>`, `<left>`.  Alignment inside a table cell
  applies to that cell.
* **`Borders`** insets the drawing rectangle on all four sides before
  anything is laid out.
* **`VertAlign`** places the whole block of lines in the rectangle when the
  rectangle is taller than the text (a list box item, a label).
* **`Scale`** multiplies every font size by a percentage, for Hi-DPI.  Sizes
  arrive in points; the control has already scaled its own font.
* Measuring and drawing must agree exactly: `HTMLTextExtentOpt` returns the
  size `HTMLDrawOpt` would paint into, with the same options and canvas
  font.  A page's scrollbar is built from those numbers.

---

## 6. Performance

The benchmark is Heckers Sketch's manual: 38 pages, and a 118 KB Markdown
document laid out in **0.19 s** today (it was 0.9 s before the old engine
was made to measure each word once and remember font metrics).  The new
engine must be at least as fast, and should be faster because layout is kept
rather than redone.

Requirements, not suggestions:

* Measure each word once per layout, not the whole line again per word.
* Remember text metrics per font, not per call.
* Paint must skip lines outside the clip rectangle.
* Layout must be reusable across paints, and across scrolls especially.
* A timing for the 38-page manual goes in the test output, so a regression
  shows up as a number.

---

## 7. What it must not do

No JavaScript, forms, video, web fonts, positioning, animations, floats, or
arbitrary websites.  No syntax coloring (see below).  No knowledge of HTML
tags, CSS or Markdown - those are the document layer's, and mixing them back
in is how the old engine ended up hard to replace.

---

## 8. Code blocks - open questions

Code blocks are the one place where the current behavior is a decision
rather than a limitation, and Tony wants to settle it before the new engine
is built, because it changes what the renderer has to support.

**Today:** a `<pre>` block is drawn in the monospace face, on a shaded
background, with its whitespace kept, **not wrapped**, and long lines are
**clipped** at the block's right edge.  The language from
`class="language-pascal"` is kept but does nothing.  LazInk does not color
code, by decision - that is SynEdit's job.

What is still open, with what each would cost:

1. **Long lines: clip, wrap, or scroll?**  Clipping is what happens now and
   costs nothing, but the end of a line is simply gone.  Soft-wrapping with
   a marker (as GitHub's mobile view does) costs a wrap mode in the engine.
   A horizontal scrollbar per code block is the browser behavior and costs
   the most: the block becomes a small scrolling surface of its own, with
   its own hit testing.
2. **Tab width.**  Tabs in code are currently spaces-as-they-arrive; a real
   tab stop every N characters is a layout rule the engine would own.
3. **Line numbers**, off by default.  Cheap if the document layer draws them
   as a hanging marker, like a list item's bullet.
4. **Copying.**  Selecting a code block should copy the code and nothing
   else - no markers, no numbers.  This is a selection rule, not a drawing
   one, and is worth deciding now because it constrains how the marker is
   stored.
5. **A coloring hook.**  The roadmap says no SynEdit glue and no coloring in
   LazInk.  A host-supplied callback ("here is a line and its language, give
   me back marked-up text") would let someone else do it without LazInk
   growing a highlighter.  Maybe, later, only if somebody asks - but if it
   is ever wanted, the engine must accept markup produced per line, which it
   already would.
6. **A copy button** on a code block, as documentation sites have.  That is
   a control feature, not a renderer one, but it needs the block to know its
   own rectangle, which it does.

---

## 9. Getting there without breaking anything

1. Write the new engine in new units (`inkdom.pas`, `inklayout.pas`,
   `inkpaint.pas` or similar), behind the same routine names in a wrapper
   unit.
2. Run **both** engines behind a switch and compare, on the 38 help pages
   and every test document: plain text must match exactly, extents within a
   pixel or two, link ordinals and hit tests exactly.
3. `tests/run.sh` must pass against the new engine with no test rewritten to
   suit it.  A test that has to change is a behavior change, and needs to be
   argued for here first.
4. Then delete `inkhtml.pas` and `inktables.inc`, check the provenance of
   every remaining file (ROADMAP section 4, step 3), and change the license.
5. Keep `docs/RENDERER_CHANGES.md` as the record of the old engine, and keep
   crediting JVCL, wp and the forum thread as where LazInk started.
