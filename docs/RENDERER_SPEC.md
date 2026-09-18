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
| Document | `inkpage.pas`, `inkmarkdown.pas`, `inkcss.pas`, `inkcode.pas` | MIT, ours | **All the parsing**: HTML tags and attributes, Markdown, entities, stylesheets, media queries, code coloring - into **blocks**: a paragraph, a heading, a list item, a code block, a picture, a table, a card grid.  Each block is a short string of **LazInk markup**. |
| Controls | `inklabel.pas`, `inkmemo.pas`, `inklistbox.pas`, `inkpage.pas`, `inkrichedit.pas` | MIT, ours | Where blocks go on screen, scrolling, selection, find, history, clipboard, touch. |
| **Renderer** | `inkhtml.pas`, `inktables.inc` | **MPL 1.1** | Given a canvas, a rectangle and one string of LazInk markup: **measure it, wrap it, paint it, and say what is under a point.** |

So the new renderer does **not** read HTML, does not read CSS, and does not
know about documents, scrolling or selection.  It is a canvas text engine
for one small markup language.  Everything else already belongs to us.

**"Don't we have to write the HTML and Markdown parsing as well?"**  No -
that is already done and it is already ours.  `inkpage.pas` reads HTML,
`inkmarkdown.pas` reads Markdown and converts it, `inkcss.pas` reads the
CSS, `inkcode.pas` colors code, and all four are MIT.  Every feature since
September 2026 - style attributes, folding `<details>`, tables built from
CSS, flex and grid, media queries, code coloring - went in there, not in
the MPL code.

The JVCL-derived code does parse *something*, which is where the confusion
comes from: it scans the **markup string we hand it** for `<b>`, `<font>`,
`<a>` and the table tags.  It has never seen a document.  It does not know
what `<h1>`, `<ul>`, `<blockquote>`, a class, a stylesheet or a fence is;
by the time a string reaches it, entities are already characters, headings
are already font sizes, and CSS is already colors and attributes.

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

**Audited on 17 September 2026** - this is every routine and type our code
actually uses from the MPL unit, with how many call sites each has:

| Used | What |
|---|---|
| `HTMLPlainText` (17) | markup to copyable text |
| `HTMLEscape` (13), `HTMLUnescape` (4) | text to markup and back |
| `HTMLDrawOpt` (9) | draw |
| `HTMLTextExtentOpt` (6) | measure |
| `HTMLStringToColor` (6) | a color name or hex to a `TColor` |
| `InkOptions` (4), `DefaultHTMLOptions` (2) | build an options record |
| `HTMLHitTest` (4) | what is under a point |
| `HTMLShadeColor` (3), `HTMLContrastColor` (2) | theme-aware colors |
| `HTMLWordWrap` (2) | re-flow markup to a width |
| `HTMLIsCJK` (1) | may a line break here |
| `HTMLDrawTextEx3` (1) | `inkpage.pas` line 2839, hit testing that also wants the text's width and height back.  The new engine should answer this with a proper call of its own, and `TJvHTMLCalcType` - a JVCL name - should not survive into it. |

`HTMLTextHeightOpt`, `HTMLPrepareText`, `HTMLDrawText`, `HTMLDrawTextHL`,
`HTMLTextExtent`, `HTMLTextWidth`, `HTMLTextHeight`, `HTMLDrawTextEx` and
`HTMLDrawTextEx2` are **not called by LazInk at all** - they are JVCL's old
entry points, and the new engine need not have them.

**Types that come with it.**  These live in the MPL unit today and are
**published properties on our MIT controls**: `TInkBorders` and
`TInkLinkStyle` (both `TPersistent`, on `TInkLabel`, `TInkMemo`,
`TInkListBox`), `TInkVertAlign`, `TInkHorzAlign`, `THTMLOptions`,
`THTMLHitInfo` and `THTMLRunEvent`.  They are LazInk's own additions, not
JVCL's - the `Ink` prefix is the clue - so **moving them into a small MIT
unit of their own is worth doing before the engine is written**: it is a
mechanical change, it can be done any day, and it means the switch-over does
not have to move published properties at the same time as everything else.
Check each one's history before relicensing it, as with every other file.

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
* **The ampersand marker.**  Between preparing text and drawing it, the old
  engine parks a literal ampersand as `#1` so that `&amp;lt;` comes back as
  the text `&lt;` rather than being unescaped twice, and turns it back into
  `&` at draw time.  It leaks: a href reported by `HTMLHitTest` can still
  carry the marker, and `inkpage.pas`'s `LinkHref` (line 509) strips it.  A
  new engine may keep the convention or drop it, but **whichever it does,
  `LinkHref` changes with it** - and the hrefs the controls see must end up
  with a real ampersand either way.
* **`TOwnerDrawState`** is not decoration: `TInkListBox` passes the real
  owner-draw state (every other control passes `[]`).  `odSelected` or
  `odDisabled` means draw the text in the selection colors rather than the
  markup's own; `odDisabled` also draws `<hr>` in the font color; and
  `odReserved1` means an `<ind=N>` indent is scaled by `Scale` like
  everything else.  Keep those three, or change the list box with the
  engine.

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

**Settled on 17 September 2026:** LazInk colors code itself, a little.
`inkcode.pas` (ours, MIT) marks comments, strings, numbers and keywords, by
the language a fence or a class named, and by rules most languages share
when it named none - so every block gets something, at the price of being
wrong here and there.  `HighlightCode` turns it off; `OnHighlightCode` hands
the block to a host highlighter instead.  The highlighter emits nothing the
drawing engine does not already understand: escaped text and
`<font color="...">`.  **A new engine therefore needs no highlighting code
of its own** - it only has to keep `<font color>` working.

**Today:** a `<pre>` block is drawn in the monospace face, on a shaded
background, with its whitespace kept, **not wrapped**, and long lines are
**clipped** at the block's right edge.

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
   argued for here first.  What covers what, in `tests/render_tests.pas`:

   | Test | What it pins down |
   |---|---|
   | `MarkdownChecks`, `MarkdownPageChecks` | the markup the document layer emits - in other words, everything the engine must accept |
   | `SelectionChecks` | `OnRun` reporting, run rectangles, hit testing, what a selection copies |
   | `NavigationChecks`, `FindChecks` | link ordinals, hrefs, `HTMLPlainText` |
   | `CardTableChecks`, `NarrowChecks` | table attributes, column widths, cells as blocks, wrapping at a width |
   | `PictureChecks` | pictures and their links, extents |
   | `TagChecks`, `CodeChecks` | `<font>`, `<b>`, `<i>`, `<u>`, `<s>`, `<center>`, `<right>`, and that markup round-trips back to text |
   | `ListEditChecks`, `ListCopyChecks` | the owner-draw path and `TOwnerDrawState` |
   | `TouchChecks`, `IconChecks` | nothing to do with the engine; they must keep passing anyway |
   | the help-page run (`tests/run.sh pages.txt results/`) | 38 real pages: every visible text fragment must survive, at three widths |
4. Then delete `inkhtml.pas` and `inktables.inc`, check the provenance of
   every remaining file (ROADMAP section 4, step 3), and change the license.
5. Keep `docs/RENDERER_CHANGES.md` as the record of the old engine, and keep
   crediting JVCL, wp and the forum thread as where LazInk started.

---

## 10. The prototype, and what it still has to do

`inkrendernext.pas` (0BSD, not in `lazink.lpk`, no dependency on `InkHtml`)
is a from-scratch prototype of the engine this document describes.  It is
built the way section 2 asks: tokenize, style, lay out into kept line boxes,
paint from them.

**Dry runs.**  `tools/renderer_dryrun.pas` draws the same markup with both
engines side by side into one PNG, prints their extents and hit tests, and
times both on 67 KB of markup.  It has been run twice: once when the
prototype first appeared, and again after its next round of work the same
day.

| | Old | Prototype, first run | Prototype, second run |
|---|---|---|---|
| inline markup and wrapping | 428 x 56 | 430 x 55 | 432 x 55 |
| `<center>` / `<right>` / `<left>` | 430 x 69 | 430 x 68 | 430 x 68 |
| entities | 334 x 18 | 430 x 17 | **334 x 17** |
| a long unbreakable word | 428 x 35 | 430 x 34 | 432 x 34 |
| CJK text | 354 x 18 | 430 x 17 | **354 x 17** |
| a plain table | 138 x 61 | 430 x 58 | **138 x 58** |
| a table of cards | 430 x 64 | 430 x 29 | 422 x 45 |
| first layout, 67 KB | 74 ms | 68 ms | **38 ms** |
| 30 paints from the kept layout | 872 ms | 73 ms | **75 ms** |
| re-layout at a new width | 76 ms | 62 ms | **34 ms** |

So the engine lays a long document out in **half** the old engine's time and
paints a screenful in about a tenth of it, because painting reads a layout
instead of parsing and measuring again.  That is the design working, and it
is the reason to finish it.

Matching the old engine already: bold, italic, underline, strike, `<font>`
color and size, links and their underline, where lines break, long words,
CJK, alignment, superscript and subscript, `<hr>`, entity handling
(including `&amp;lt;` staying literal text, so the `#1` marker convention is
not needed), content widths, hit testing with the right href and ordinal,
and `odSelected` / `odDisabled` colors.

One difference is an **improvement, not a regression**: the hit result's
`LinkText` comes back `a link` where the old engine says `alink`.  The old
one drops the space between runs.  The prototype is right; do not "fix" it
backwards, and change the test that pins the old spelling when the switch
happens.

### The checklist

Done since the prototype first ran (all 18 September 2026):

- [x] Superscript and subscript are painted, not just measured.
- [x] `<hr>` is drawn.
- [x] Extents report the **content** width, so a label sizes to its text.
- [x] `LinkText` is filled in.
- [x] Images take the image list's size instead of a hard-coded 16 x 16.
- [x] `TOwnerDrawState`: `odSelected` and `odDisabled` pick the selection
      and disabled colors.
- [x] `<ind>`'s indent is applied at layout time.
- [x] Half the utility API: `InkNextEscape`, `InkNextUnescape`,
      `InkNextPlainText`, `InkNextContrastColor`, `InkNextShadeColor`,
      `InkNextIsCJK`.

Still to do, heaviest first:

- [ ] **Tables.**  Still the largest item, and Heckers Sketch's index rides
      on it.  Cell backgrounds, borders and padding now draw, but:
      - **`<br>` inside a cell does not start a new line.**  Measured on
        `<td><b>Title</b><br>body words</td>`: both runs come back at the
        same place (`@6,6`), so the second line is painted over the first.
        This is why a card shows only its body text.
      - A plain table draws **no grid**; the old engine borders every cell.
      - Column widths are not the algorithm in section 3.3 (longest word
        first, then share what is left), and `width="100%"` /
        `layout="fixed"` are not read.
      - The card sample is 45 pixels tall against the old engine's 64, so
        padding and spacing do not add up to the same box yet.
- [ ] **`InkNextPlainText` puts a spurious line break and tab before a
      table's first cell** - `[\n\tTitle...]` where the old engine gives
      `[Title...]`.  `tests/check_help_text.pas` compares this text across
      38 pages, so it has to match exactly.
- [ ] **`<p>` is one break; it must be two** - a blank line - and dropped
      when it is the first thing in the string.
- [ ] **A paint origin.**  Still the signature decision: `Paint` draws at
      layout coordinates, so moving text means moving `Borders`, which is in
      the cache key - 30 scrolled paints cost 1,063 ms against 75 ms for the
      same paints at rest.  An origin argument at paint time, `Borders` out
      of the key.
- [ ] **A line may end a couple of pixels past the width** (432 against a
      430 column) when it finishes with a superscript or a larger font.
- [ ] **`<ind=N>`.**  The tokenizer reads `<ind n="20">`; the markup the
      document layer emits is `<ind=20>`.  And the indent is always scaled
      by `Scale`, where the old engine scales it only when `odReserved1` is
      in the draw state.
- [ ] **`InkNextColor` is implementation-only** - it is the
      `HTMLStringToColor` replacement and has to be public.
- [ ] **Selection.**  No `OnRun` / `RunPart` equivalent yet.  `RunAt` /
      `LineAt` on the layout is the better shape; `TInkCustomPage.PrepareRuns`
      gets rewritten onto whichever it becomes.
- [ ] **The rest of the API** (section 4): the options builders, and a
      decision on `HTMLWordWrap` - the prototype wraps inside layout, so
      `inkpage.pas` stops pre-wrapping rather than the engine growing a
      wrapper.
- [ ] **Move `TInkBorders` and `TInkLinkStyle`** out of the MPL unit, as
      section 4 says.  Unchanged and still worth doing on its own.

Nothing in either dry run says the design is wrong.  The opposite: the parts
that are hardest to get right generically already agree with the old engine,
the gap list is shrinking in the order a person would pick, and the speed is
going the right way.

---

## 11. Room to leave for what comes later

Not work for the first version.  They are here because each one is cheap to
allow for now and expensive to retrofit.

* **Pictures are boxes with a source of frames.**  Today an image run is an
  image-list index of a fixed size.  A page's pictures are files - PNG, GIF
  and, if ROADMAP item 17 happens, **animated WebP** - with a real size, a
  current frame, and a clock.  Give an image run a size the caller sets and
  a frame the caller can change between paints, and animation stays entirely
  outside the engine, where `TInkGIF` already is.  The format question (a
  Pascal decoder against binding libwebp, and the rule that GIF stays
  whichever way it goes) is settled in ROADMAP section 4, item 17 - the
  engine only has to not care which decoder filled the bitmap.
* **A picture that is not inline.**  Blocks place their own pictures today
  (`TInkCustomPage` does the layout), but `float: left` with text wrapping
  round it is the one layout feature documents really ask for.  The line
  box list makes it possible - a line needs to know its available width
  varies down the page - so do not assume one width per layout.
* **`colspan` and `rowspan`**, column widths from `width`, `<thead>` and
  zebra striping (ROADMAP section 4, item 8).  The old engine cannot do
  them; a table design that starts from a grid of cells rather than a list
  of rows can.
* **Code blocks that scroll sideways** rather than clipping, and real tab
  stops - the open questions in section 8.  Both want a block that can be
  wider than the column and clipped to it, which is a property of the line
  box, not of the text.
* **Selection painting.**  The controls draw the selection themselves from
  run rectangles today.  If the engine ever paints it, it needs the
  selection range as an input, not a second pass over the canvas.
* **Hi-DPI.**  `Scale` is in the options and in the cache key already; keep
  every measurement going through it rather than reading `Font.Size`
  directly, and this stays a one-line concern.
* **Not wanted, still:** JavaScript, forms, video, web fonts, positioning,
  animations beyond a picture's own frames, and printing.  A document
  renderer with a media framework behind it is a different program.
