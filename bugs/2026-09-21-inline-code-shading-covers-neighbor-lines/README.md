# The shading behind inline code cuts into the lines of text above and below it

Seen 21 September 2026 on **Windows**, in Heckers Sketch's "What's new"
window (`TInkPage`, `TextFormat := itfMarkdown`), release v2026.09.21.
Reported by the person using it; **not yet reproduced by whoever wrote this
note**, who was on Linux - so the first job is to look at `repro.md` on
Windows and confirm it, and then on Linux to see whether it is there too
and merely less visible.

## What you see

A wrapped list item with a piece of inline code in the middle of it:

```markdown
  Colored red, green and blue like the axes.  A line is two points,
  `line = a to b`, and that is all it is; a solid's edges are lines you
  can pick like any other.
```

The shaded box behind `line = a to b` is **taller than the line it sits
in**.  It covers the bottoms of the letters on the line above and the tops
of the letters on the line below, so both neighbors look sliced off where
they pass the code.

`repro.md` beside this is that list item exactly as shipped, and a plain
paragraph built to show it: a line of descenders (g j p q y) above a
shaded piece and a line of ascenders (b d f h k l) below it.

## The stylesheet it was shown with

From `uWhatsNew.pas` in Heckers Sketch, nothing exotic:

```css
body { font-size: 14px; padding: 6px }
li   { margin-bottom: 6px }
code { background: #xxxxxx }        /* panel mixed 12% toward the text color */
```

No `line-height`, no padding on `code`.  So the line box is as tall as the
body font, and the `code` run is in the fixed face.

## Where it probably is

`inkrender.pas`, the run-painting loop, at about line 1980:

```pascal
if BG<>clNone then
begin
  Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=BG;
  Canvas.FillRect(DrawRect);
end
else Canvas.Brush.Style:=bsClear;
...
else if not R.IsImage then Canvas.TextOut(DrawRect.Left,DrawRect.Top,R.Text);
```

Two things there can each do it, and on Windows probably both do:

1. **`DrawRect` for a run is as tall as that run's own font, not as tall
   as the line.**  The fixed face Windows picks (Consolas, Courier New) has
   a taller cell than the body face at the same pixel size, so the code
   run's rectangle stands proud of the line box top and bottom.  The fill
   is painted *after* the line above has been drawn, so it covers that
   line's descenders.
2. **The brush is still solid when `TextOut` runs**, and - as the comment
   just above that code says - `TextOut` paints its own background when the
   brush is solid.  That background is the font's full cell, which is what
   overhangs.  On GTK the cell and the line box happen to agree more
   closely, which would be why nobody saw it on Linux.

Either way backgrounds and text are painted **in one pass, run by run**,
so a background that overhangs always lands on top of text that was
painted before it.

## What would fix it

* **Clip a run's background to its line box** - top and bottom of the line
  it is on, not of its own font.  That is what a browser does: an inline
  background never reaches outside the line unless padding asks it to.
* **Paint in two passes**: every background on the page (or at least in
  the block) first, then every piece of text.  Then an overhang cannot
  cover a neighbor's letters even when there is one.
* **Set the brush to `bsClear` before `TextOut`** once the fill has been
  done, so the text never brings a second, taller background of its own.
* Worth checking at the same time: `<mark>`, link hover backgrounds
  (`HoverBackColor`) and `<span style="background:...">` go through the
  same code and will have the same fault.

## How to check it

`repro.md` in a `TInkPage` with the stylesheet above, at 14px, on Windows,
at 100% and at 150% scaling.  Right is: every letter on the lines above
and below the shaded piece whole, and the shading the height of its own
line and no more.  The side-by-side tool (`tools/sidebyside.pas`) against
a browser will show the difference in one picture.

## Fixed - 21 September 2026

Reproduced on Linux as well, once the geometry was made the same as the
Windows one: a `line-height` tighter than the fixed face's own cell, which
is what Consolas beside Segoe UI amounts to.  With `repro.md`, 14px text and
`line-height: 1`, the old renderer painted **32 rows of shading against a
14-pixel line**.  `before.png` and `after.png` are that case (with a pink
`code` background so the overlap can be seen); the fault is the shading
behind `line = a to b` and `true`/`false` slicing into the lines either side.

All three things this note suspected were real, plus one it did not name.
Each is fixed in `TInkRenderer.PaintLayout`:

1. **Two passes.**  Every background on the page is painted first, then
   every piece of text, so an overhang can no longer land on letters that
   were already drawn.
2. **A run's background is clipped to its line box**, top and bottom, as a
   browser clips an inline background to the line it is on.
3. **The brush is clear whenever text is drawn**, so `TextOut` never brings
   a second background of its own - the font's whole cell - with it.
4. **Text is placed on its baseline, not by the top of its cell.**  The
   ascent a run is laid out with leaves out the font's *internal leading*;
   `TextOut` counts it.  On GTK every font reports an internal leading of
   nought, so the two agreed and nobody noticed.  On Windows, Segoe UI and
   Consolas both have some - different amounts - so every run was drawn
   that many pixels low, and a code run by a different amount from the text
   beside it.  Paint now asks the painted font for its real ascent and puts
   the text so its baseline lands where layout put it.  Table cells, which
   had no baseline at all, now have one too.

`<mark>`, link hover backgrounds and `<span style="background:...">` go
through the same code and are fixed by the same change.

**Tested:** `InlineShadeChecks` in `tests/render_tests.pas` renders this
case and checks the shading is never taller than its line; it fails on the
old renderer (32 rows) and passes on the new one.  **Not tested:** point 4
on Windows itself - GTK cannot report an internal leading, so it can only
be seen there.  Worth one look at `repro.md` on Windows at 100% and 150%.
