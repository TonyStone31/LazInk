# TInkMemo draws its text a third bigger than its font says

Found 5 October 2026, moving Heckers Sketch's read-only boxes to `TInkMemo`
with `itfPlain`.  A memo with `Font.Height = -13` draws 17 px text - 13
points, not 13 pixels.

## Why

`TInkMemo.StyleBlock` (`inkmemo.pas:374`) sets

    B.PointSize := Max(1, Round(FLayoutBase * FHTMLScale / 100));

`FLayoutBase` is in pixels (`BaseFontPixels`), and everywhere else a block's
size is stored negative to mean pixels - `TInkCustomPage` does
`B.PointSize := -Max(1, ...)` (`inkpage.pas:2954`) and `-K` (`:3057`).  The
memo's positive value reaches `HTMLFontSize`, which reads a positive size as
points, so the text comes out 4/3 of the size asked for.

## The fix

    B.PointSize := -Max(1, Round(FLayoutBase * FHTMLScale / 100));

and a check that a memo with `Font.Height = -13` lays its lines out 13 px
high (or its text 13 px tall), so the sign cannot slip again.  Anything else
reading a memo block's `PointSize` should take `Abs` of it, as the page's
code already does.

## What Heckers Sketch does meanwhile

Nothing - its tickets and the postcard's text read a little large until
this is in.

## Fixed - 5 October 2026

The one-character fix from the note: `TInkMemo.StyleBlock` writes its
block size negative - pixels, as every other block spells it - so a memo
with `Font.Height = -13` draws 13-pixel text.  The one other reader that
assumed a positive size (`ScrollIntoView`'s caret-height guess) now takes
`Abs`.  The test holds a memo block to exactly `PointSize = -13`.
