# A list after a rule gets the rule's color painted behind its text

Found 19 September 2026 while looking at Heckers Sketch's "What's new"
window, which is a `TInkPage` in Markdown mode.  Every bullet was a solid
block of color with the text invisible inside it - see `before.png`.  It is
not that program's CSS: the same thing happens in the twenty-line repro
beside this, and it happens in both a light and a dark palette.

`after.png` is the same page with the one-line fix at the bottom of this
file applied.

## What you see

Markdown (`repro.md`):

```markdown
Paragraph before the rule, plain text.

---

Paragraph after the rule, plain text that should be readable.

### A heading after the rule

- a bullet after the rule
- another bullet

Another paragraph at the end.
```

with a stylesheet that gives the rule a color of its own (`repro.css`; the
color is red here only so it can be told apart from the text color):

```css
body { background: #eceef1; color: #5e6670; font-size: 14px; padding: 6px }
hr { color: #ff0000 }
```

Every **list item after the `hr`** is drawn with a solid red background
behind its text, wrapped lines and all.  Paragraphs and headings after the
same `hr` are fine.  A list *before* any `hr` is fine.  The color is always
the `hr`'s color.

The repro is `repro.pas` - a form, a `TInkPage`, `TextFormat := itfMarkdown`,
the stylesheet and the Markdown, and nothing else.

## Why

Three things in a row, and it takes all three:

**1. `TInkCustomPage.Paint` leaves the brush color behind after an `hr`.**
In `inkpage.pas` the `hr` branch fills the rule and leaves the loop:

```pascal
if B.Tag='hr' then
begin
  ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := B.BarColor;
  TR := B.TextBounds; OffsetRect(TR,0,-FScroll.Position);
  ACanvas.FillRect(TR);
  Continue;
end;
```

The next block sets `Brush.Style := bsClear` again, so the *style* is put
back - but the *color* stays the rule's from here to the end of the paint.
On its own that is harmless.

**2. `TInkRenderer.Paint` puts the brush back in the wrong order.**
In `inkrender.pas`, at the end of `Paint`:

```pascal
finally Canvas.Font.Assign(OldFont); Canvas.Brush.Style:=OldBrushStyle; Canvas.Brush.Color:=OldBrushColor; ... end;
```

`TBrush.SetColor` in the LCL sets `Style := bsSolid` as a side effect - the
same behavior the VCL has, on the reasoning that if you are choosing a
color you must want to paint with it.  So restoring the style first and the
color second undoes the restore: every call to `Paint` returns with the
canvas brush **solid**, whatever it was on the way in.

Measured, with the restore as it is:

```
DBG rp entry style=1        (bsClear)
DBG rp exit  old=1 now=0    (asked for bsClear, got bsSolid)
```

**3. A list item draws its text after its marker, with no `bsClear` in
between.**  In `TInkCustomPage.Paint` the brush is set to `bsClear` once,
before the marker is drawn:

```pascal
ACanvas.Brush.Style := bsClear;
...
if B.Marker<>'' then
  HTMLDrawOpt(ACanvas, <marker rect>, [], HTMLEscape(B.Marker), O);   { leaves the brush solid, see 2 }
O := BlockOptions(I);
...
HTMLDrawOpt(ACanvas,TR,[],B.Wrapped,O);                                { draws the text with a solid brush }
```

So the marker's own `HTMLDrawOpt` hands the canvas back with a solid brush,
and the text draw that follows it paints `Canvas.TextOut` over an opaque
background in the leftover color.  A paragraph has no marker, so its one
`HTMLDrawOpt` is entered while the brush is still clear and the damage only
shows up after the text is already on the canvas - which is why only lists
show it.

That is also why it needs an `hr`: without one, the leftover color happens
to be the page background and nobody notices.

## The fix

One line, in `inkrender.pas`, `TInkRenderer.Paint` - restore the color
first, then the style, so the style's restore is the last word:

```pascal
finally Canvas.Font.Assign(OldFont); Canvas.Brush.Color:=OldBrushColor; Canvas.Brush.Style:=OldBrushStyle; OldFont.Free; BoxAttrs.Free end;
```

Verified: with that swap the run is drawn with `brushstyle=1` (`bsClear`)
and the page looks like `after.png`.

Worth doing as well, and cheap:

* **`inkpage.pas`, `TInkCustomPage.Paint`** - set `Brush.Style := bsClear`
  again after the marker is drawn, or once more just before the text
  `HTMLDrawOpt`.  Nothing that draws text should depend on what the last
  thing to draw left behind.
* **the `hr` branch** - put the brush color back, or set both color and
  style at the top of every block rather than only the style.
* **the same restore-order trap elsewhere** - anywhere that saves and
  restores a brush, the color must go back before the style.  Worth a grep
  for `Brush.Style:=` near `Brush.Color:=`.
* **a regression test** - `tests/render_tests.pas` could render
  `repro.md` with `repro.css` and assert that a pixel in the middle of the
  bullet's line box is the page background, not the rule's color.  That is
  the whole fault in one pixel.

## Where it was seen

Heckers Sketch, "What's new" (`uWhatsNew.pas`): the release notes are
Markdown, each version heading is followed by `---`, and the notes
underneath it are bullets - so every bullet in that window was unreadable.
The stylesheet there is built from the program's theme, so it looked like a
light-mode bug at first; it is not, it happens in every palette, and the
block is simply more obvious against a pale page.
