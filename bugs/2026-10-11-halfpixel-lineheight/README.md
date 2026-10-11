# Half a pixel a line: whole-pixel line heights against a browser's 22.5

Found 11 October 2026 on the demo's side-by-side tab.  Tony: "there is
still quite a height difference even by the time section 1 is in the
view."  Measured band by band at the top of the showcase: LazInk's
paragraph lines advance at exactly 22 pixels where the browser's
advance at 22.5 - its band starts run 212, 234, 257 (22, 23,
alternating) against LazInk's 210, 232, 254.

## Why

`font: 15px/1.5` computes a line-height of 22.5px.  A browser carries
the fraction (Chromium's LayoutUnit is 1/64px), so n lines stand
n x 22.5 tall.  LazInk's `LinePixels` rounds to whole pixels once -
22 - and every ruled line loses half a pixel.  The showcase had about
250 such lines; 0.5 x 250 = 125 of the 134 pixels the whole page came
up short.  Everything else on the page agreed to a few pixels.

## The fix, when taken

Fractional line advance through the engine: line-height carried in
quarter pixels (or 1/64ths) from the tree serializer's `lineheight`
attribute through `Metrics` and both layout paths, with each line's
top rounded only at paint.  Contained but real - the field's meaning
changes everywhere it is read.

Meanwhile the showcase pins integral pitches (15px x 1.6 = 24,
pre 13px/20px) so the comparison tests everything else pixel-true;
any page whose computed line-height lands on a half pixel will drift
half a pixel a line until this is taken.
