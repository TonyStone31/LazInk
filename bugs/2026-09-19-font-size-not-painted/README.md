# Every size of text is drawn at the base size, though it is laid out at its own

Seen 19 September 2026, at `0121d7e` ("Sizes in pixels, rowspan, line-height,
and a page that matches a browser"), against Heckers Sketch's manual: every
heading came out the same size as the body text.  `headings.png` and
`sizes.png` beside this are what it looks like.

It is not only headings, and that is the useful part of it.

## What you see

`sizes.html` is five paragraphs, each asking for a size:

```html
<p class="big">40px</p>     .big   { font-size: 40px }
<p class="mid">22px</p>     .mid   { font-size: 22px }
<p class="base">15px base</p>
<p class="small">11px</p>
<p>no size given</p>
```

Every one of them is **drawn in the same glyphs** - the body's 15 pixels -
but each one **takes up the room its own size asks for**: the 40px paragraph
sits in a 40-pixel line box with small text stranded in the middle of it, the
22px one in a 22-pixel box, and so on.  So the layout knows the size and the
painting does not.

`headings.html` is the same thing as a page would write it: `h1` at 30px,
`h2` at 19px, and one `h2` with `style="font-size: 26px"`.  All three draw at
the body size.  A `style` attribute makes no difference, which rules out the
stylesheet reader.

Smaller sizes are wrong the same way: the 11px paragraph is drawn at 15.

## Reproducing it

`probe.pas` is the whole harness - a form, a `TInkPage`, `LoadFromFile`:

```
fpc -dLCL -dLCLgtk3 -Fu<LazInk> -Fu<lcl units> ... probe.pas
DISPLAY=:78 ./probe sizes.html      # then photograph the window
```

## Where it probably is

Not diagnosed to a line - the symptom was clear enough to hand over as it
is - but the shape of it says the base font, not the CSS:

* `TInkCustomPage.BlockFont` sets the block's size with `HTMLFontSize`, which
  is `InkRenderApplySize`: **a negative value goes to `Font.Height`** (that
  is the pixel spelling), a positive one to `Font.Size`.
* `EngineOptions` then takes `Result.BaseFont := Canvas.Font`.
* Anything downstream that reads a size back off that font as `.Size` rather
  than `.Height` gets points where pixels were meant, or the control's own
  size where the block's was meant - and every run is painted at the base.

Measurement clearly reads the right number, which is why the line boxes are
right; so the two paths have got out of step, and the painting one is the
one that lost it.

`TInkRenderer.Paint` itself applies `InkRenderApplySize(Canvas, R.Style.Size)`
correctly, so the value in `R.Style.Size` at paint time is the thing to look
at first.

## What it costs, meanwhile

Heckers Sketch's manual in the program has no heading hierarchy - a page is
one flat wall of 15-pixel text, headings only marked by color and weight.
The same pages in a browser are fine, so this is the in-program reader only.
The release going out today ships with it; the pages are written the way a
browser reads them and will simply get better when this is fixed - nothing
in the manual needs changing for it.
