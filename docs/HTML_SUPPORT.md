# What you can write in a LazInk page

This is the reference for anyone **writing** help pages that a program will
show in `TInkPage` (or `TInkMemo`, `TInkLabel`, `TInkListBox`). It says what
LazInk reads and what it ignores, so a page can be written once and look the
same in a browser and in the program.

LazInk is not a browser and does not try to be one. What it does do, it tries
to do the way a browser does: the same font sizes, the same line heights, the
same margins. The comparison page in `tests/compare/page.html` is drawn side
by side with a real browser by `tools/sidebyside.pas`; at the time of writing
the two agree on the height of a 3,200-pixel page to within five pixels.

Write the page as ordinary HTML. It will open in a browser too, and that is
the point - author it in a browser, ship it to `TInkPage`.

---

## Two inputs

| | |
|---|---|
| **HTML** | `LoadFromFile('help/index.html')`, `LoadHTML(S)`. A `<link rel="stylesheet">` and any `<style>` block are read. |
| **Markdown** | a `.md` file name, or `LoadMarkdown(S)`. GitHub-flavored: tables, fenced code with a language, task lists, autolinks. A Markdown document carries no stylesheet, so the program dresses it with `InkPage1.StyleSheet`. |

A page's own rules beat the program's stylesheet.

---

## Text

| Written | Drawn |
|---|---|
| `<b> <strong>` | bold |
| `<i> <em> <cite> <dfn> <var>` | italic |
| `<u>` | underlined |
| `<s> <strike> <del>` | struck through |
| `<ins>` | underlined |
| `<mark>` | on a highlight (yellow unless CSS says otherwise) |
| `<code> <kbd> <tt> <samp>` | the fixed face, on its stylesheet's background |
| `<sup> <sub>` | raised and lowered, smaller |
| `<small>` | smaller |
| `<q>` | wrapped in quotation marks |
| `<br>` | a line break |
| `<wbr>` | a break opportunity inside a long word |
| `<span style="...">` | whatever the style attribute says |
| `<abbr title="...">` | its text (the title is not shown) |

**Entities:** `&amp; &lt; &gt; &quot; &nbsp; &copy; &reg; &trade; &euro;
&mdash; &ndash; &hellip; &rarr; &larr; &times; &deg;` and about fifty more,
plus numeric ones written either way - `&#233;` and `&#xE9;`.

**Wrapping:** lines break on spaces, after slashes in long paths, and between
CJK characters, keeping closing punctuation off the start of a line.  Words
joined by `&nbsp;` (or a raw U+00A0) do not break.

---

## Blocks

`<p>` `<div>` `<h1>`-`<h6>` `<blockquote>` `<pre>` `<hr>` `<address>`
`<figure>` `<figcaption>`, and the HTML5 sectioning elements `<section>`
`<article>` `<aside>` `<main>` `<header>` `<footer>` `<nav>`.

Headings are sized the way a browser sizes them - h1 twice the body text, h2
one and a half times, h3 a sixth larger, h4 the same, h5 and h6 smaller -
until the stylesheet says otherwise. Margins between blocks collapse the way
they do in a browser: two blocks with a margin between them are one margin
apart, not two.

`<blockquote>` gets a bar down its left side, and a quote inside a quote gets
two.

`<details>` and `<summary>` fold: what the `<details>` holds is hidden behind
its summary until the summary is clicked, and `<details open>` starts open. A
triangle marks which way it goes.

---

## Lists

`<ul>` `<ol>` `<li>` `<dl>` `<dt>` `<dd>`, nested as deep as you like.
Bullets and numbers hang to the left of the text, so a wrapped line lines up
under the first word rather than under the bullet.

* `<ol start="8">` starts at eight.
* `<ol type="a">`, or `list-style-type` in CSS - `disc`, `circle`, `square`,
  `decimal`, `lower-alpha`, `upper-alpha`, `lower-roman`, `upper-roman`,
  `none`.
* A task list (`<input type="checkbox">` anywhere in a line, or Markdown's
  `- [x]`) draws the checkbox the way Chromium draws one: a 13px rounded
  square, blue behind a white check when checked, gray-bordered when not.

---

## Tables

`<table> <tr> <th> <td> <caption>`, and `<thead>` `<tbody>` `<tfoot>` pass
through without disturbing the rows.

* **`colspan` and `rowspan`** both work, and so does a `<table>` inside a
  cell.
* `<th>` is bold and centered unless the stylesheet says otherwise.
* Column widths are worked out from the content: a table that fits keeps its
  columns at their natural width, and one that does not shares the room out,
  every column keeping at least its longest word.
* `width="60%"` or `width="400"` on the table; `cellpadding` and
  `cellspacing`; `border-collapse: separate` with `border-spacing` for cards
  with gaps between them.
* **Every cell carries its own look**: `background`, `color`, `border`,
  `border-color`, `border-radius`, `padding`, `text-align`, `valign`, set on
  the cell, on `td`/`th`, or through a class. A borderless table of bordered
  cells is a grid of cards.
* **And its own text**: `font-size`, `font-weight`, `font-family` and
  `line-height` on `td`/`th` by tag or class reach the words in the cell -
  a smaller face for one column is how a long file name fits.  Inline
  markup inside the cell still wins.
* **`white-space: nowrap` on a cell** keeps its column at least as wide as
  the whole text, so `85 KB` never folds to give a long neighbor room.
  `&nbsp;` is a real no-break space too, in every control.
* **Block children of a cell** - `div`, `p`, `h1`-`h6` - are lines of
  their own, each in its own size and weight: a title over a dimmer line
  is a card.
* **A table nests**: inside a cell, or inside a `display: grid` /
  `display: flex` card, keeping its stylesheet's padding, backgrounds and
  colors.  Two cards side by side, each holding a small key/value table,
  is written exactly as a browser page would write it.
* **Pills**: `padding`, `border-radius` and `border` on a `<span>` - by
  class or style attribute - make an inline box behind the words, so a
  status can be a rounded badge in a sentence or a cell.  A pill's words
  stay on one line.  `span.x { color; background; font-size; font-weight }`
  also style a span's words with no pill involved.
* **Any HTML a browser would accept**: a page is parsed into a document
  tree by the HTML standard's rules before anything is drawn, so tag soup
  comes out as a browser builds it - `<p>` and `<li>` closed by what
  follows, `<b>one<i>two</b>three</i>` mended, `<tbody>` implied, stray
  text in a table moved before it, every named character, and old pages in
  Windows-1252 or another code page their `<meta charset>` names.
* **One element at a time**: `SetInnerHTML('status', '<b>sent</b>')`
  replaces what is inside the element with that `id` and reads the page
  again, keeping the scroll where it was - a live status page changes one
  line without rebuilding its source.

```html
<table class="cards">
  <tr>
    <td><b>One</b><br><small>a card</small></td>
    <td><b>Two</b><br><small>another</small></td>
  </tr>
</table>
```

```css
table.cards { width: 100%; border-collapse: separate; border-spacing: 10px }
table.cards td { background: #f4f7ff; border: 1px solid #c7d2fe;
                 border-radius: 8px; padding: 10px 12px }
```

A `display: flex` or `display: grid` container is laid out as rows of cards
in the same way, wrapping to fewer columns when the window is narrow.

---

## Pictures

```html
<img src="shots/window.png" alt="the main window">
<img src="shots/window.png" alt="..." width="520">
<img src="shots/window.png" alt="..." width="50%">
<img src="shots/window.png" alt="..." style="max-width: 400px">
```

* **Formats:** PNG, JPEG, BMP and the rest of what FPC decodes; **animated
  GIF**; and **WebP** - still or animated, lossy or lossless, with alpha -
  decoded in Pascal, with nothing to install. WebP is usually a fraction of
  the size of the same GIF.
* **Size:** `width` and `height` as attributes or in a `style`, in pixels or
  as a percentage of the column. A width on its own keeps the picture's
  shape; a `max-width` is a ceiling rather than a size. Whatever is asked
  for, a picture is never drawn wider than its column.
* `<picture>` and `<source>` are stepped over, so the `<img>` inside a
  `<picture>` is what gets drawn - write the fallback and it will be right in
  both a browser and LazInk.
* `alt` text is shown when the file will not load, so it is worth writing.
* A picture inside a table cell is drawn as its `alt` text, not as a picture.

---

## Code

````markdown
```pascal
procedure Hello;
begin
  WriteLn('hi');    { a comment }
end;
```
````

or `<pre><code class="language-pascal">`.

Code keeps its spacing in the fixed face on a shaded background, and a long
line is cut off at the block's edge rather than wrapped. LazInk colors it a
little - comments, strings, numbers and keywords. It knows the comment and
quote rules for about sixty language names and keyword lists for the dozen or
so that turn up in documents; a block that names no language is colored by
the rules most languages share. It is not a real highlighter and will not
always be right. A page that colored its own code with `<span>`s keeps its
own colors, and the program can switch LazInk's coloring off or do its own.

---

## Links, anchors and pictures that link

```html
<a href="tables.html#wide">a page and a place in it</a>
<a href="#top">a place in this page</a>
<a href="https://example.com">out to a browser</a>
<a href="shots/window.png"><img src="shots/thumb.png" alt="a picture"></a>
```

Relative links and images resolve against the document. An `id` anywhere is
an anchor. The viewer keeps a Back and Forward history, and returns to where
the page was scrolled.

---

## The CSS it reads

The cascade a browser runs - `<style>`, `<link rel="stylesheet">`,
`@import`, `@layer`, `@property`, custom properties and `var()`, every
selector (pseudo-classes, `:is()`/`:where()`/`:has()`, attribute selectors,
`::before`/`::after`/`::marker`), `!important`, inheritance - and boxes laid
out from it:

| | |
|---|---|
| **Box** | `display`, `margin`, `padding`, `border` (each side, `border-radius`), `width`/`height` and their `min-`/`max-`, `box-sizing`, `overflow` (as a clip) |
| **Layout** | normal flow with margin collapsing, `float`/`clear`, `position` (`relative`, `absolute`, `fixed`), `z-index`, flex (wrap, grow, shrink, basis, alignment, `order`, `gap`), grid (`grid-template-*`, named areas, `repeat()`, `minmax()`, `auto-fill`, spans), tables (`border-collapse`, `border-spacing`, `table-layout`, spans, captions) |
| **Text** | `color`, `background-color`, `font-*`, `text-align`, `text-decoration`, `text-transform`, `white-space`, `line-height`, `vertical-align`, `text-overflow: ellipsis` (with `nowrap` and a clipping `overflow`), `visibility`, `opacity: 0` |
| **Lists** | `list-style-type`, `list-style-position`, counters in markers |
| **Scrollbar** | `scrollbar-color`, `scrollbar-width` (see the README) |

Still approximate: words do not flow line by line round a float,
`position: fixed` scrolls with the page, background pictures, masks and
`box-shadow` are not drawn, and a gradient is its first color.

`@media` is judged at the control's width, for `min-width`/`max-width`
(and the range syntax), `prefers-color-scheme` and the rest, which is enough
for a page that narrows to one column and carries a light and a dark
palette:

```css
:root { --bg: #23262c; --text: #e6e6e6 }            /* dark by default */
@media (prefers-color-scheme: light) {
  :root { --bg: #f4f5f6; --text: #1d2027 }
}
body { background: var(--bg); color: var(--text) }
@media (max-width: 420px) {
  .grid { grid-template-columns: 1fr }
  body { font-size: 13px }
}
```

Which scheme answers is the control's `ColorScheme` (`icsAuto`, `icsLight`,
`icsDark`).  On `icsAuto` it follows `InkAppColorScheme` when the program
set one, else the control's own background: light when its luminance is at
least half, so a dark desktop theme reaches the page with no platform code
at all.  `ActiveColorScheme` reads what auto came to, and
`InkColorSchemeChanged` tells every open page when the program's theme
flips.  The host's `StyleSheet` reads the same queries, so one sheet can
dress a release-notes window for both themes.  The features combine the way
CSS combines them - `(prefers-color-scheme: dark) and (max-width: 600px)`
holds only when both do - and LazInk applies no palette of its own: a page
with no scheme rules looks exactly as it always did.

A `style` attribute is read as a browser reads it, on any element.

### Sizes are pixels

`font-size: 15px` is fifteen pixels of text, as it is in a browser - not
eleven points rounded off. Inside the controls this is the LCL's own
convention: a positive size is points, a negative one is pixels, exactly as
`TFont.Size` and `TFont.Height` spell it.

`line-height` is read as a bare multiplier (`1.5`), a length (`22px`, `1.6em`)
or a percentage. Without it, a line is as tall as the font in it - which is
what a browser does too.

### What the body says, everything inherits

`font-size`, `font-family` and `line-height` set on `body` reach every block
that does not name its own, which is how pages are actually written:

```css
body { font-size: 15px; font-family: sans-serif; line-height: 1.5 }
h1   { font-size: 28px }          /* its own size, the body's family */
```

The body's `font-size` is also what every heading, margin and indent is a
multiple of, so it is the one declaration worth getting right. Other
properties are not inherited - a `color` on `body` colors the page's text,
but a `color` on a `div` does not reach the paragraphs inside it.

### Font families

A stack is tried in order and the first face this machine actually has is
used: `font-family: "Helvetica Neue", Arial, sans-serif`. The generic names
work too - `serif` and `monospace` pick a face, and `sans-serif`,
`system-ui` and `ui-sans-serif` keep the control's own font, which is the
one the platform already resolves a generic sans to. Naming a real family
is worth it when a page must look the same everywhere; leaving it generic is
worth it when it should look native.

---

## What it does not do

* No JavaScript, no forms or form controls, no video or audio, no web fonts.
* Words do not flow line by line round a float: the float takes its side
  and the text sits beside it.
* `position: fixed` scrolls with the page.
* No `letter-spacing`, `word-spacing`, `box-shadow`, `background-image`,
  masks or `text-shadow`; `opacity` is read only as 0, and a gradient is
  its first color.
* `<table>` has no `<col>`/`<colgroup>` widths.
* Colors come from the page, but the control's own theme supplies the
  defaults - a page that relies on the browser's light/dark scheme will take
  the control's instead.
* No HTTP: a program supplies remote content through `OnResource`.

---

## A page that uses most of it

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Pushing a tool</title>
<style>
  body { background: #fff; color: #22262c; font-size: 15px; padding: 12px;
         font-family: sans-serif; line-height: 1.5 }
  h1 { color: #14315c; font-size: 26px }
  h2 { color: #176bbd; font-size: 20px }
  code, kbd { background: #eef0f3 }
  pre { background: #f4f6f8; padding: 10px }
  table { border-collapse: collapse }
  th, td { border: 1px solid #c8ccd2; padding: 6px 10px }
  th { background: #eef2f7; text-transform: uppercase }
  .note { background: #f4f6f8; border-left: 4px solid #176bbd; padding: 8px 10px }
</style>
</head>
<body>

<h1 id="top">Pushing a tool</h1>

<p>Press <kbd>Ctrl</kbd>+<kbd>P</kbd>, or use the <b>Tools</b> menu.</p>

<div class="note"><b>Note.</b> A pushed tool stays pushed until it is
pushed again.</div>

<h2>Keys</h2>

<table>
  <tr><th>Key</th><th>What it does</th></tr>
  <tr><td rowspan="2"><kbd>Ctrl</kbd></td><td>with <kbd>P</kbd>, pushes</td></tr>
  <tr><td>with <kbd>Z</kbd>, undoes</td></tr>
</table>

<p><img src="shots/tool-push.webp" alt="the tool being pushed" width="520"></p>

<details>
  <summary>The long way round</summary>
  <p>There is a menu item for it as well.</p>
</details>

</body>
</html>
```

Open that in a browser and in `TInkPage`, and the two should be hard to tell
apart.
