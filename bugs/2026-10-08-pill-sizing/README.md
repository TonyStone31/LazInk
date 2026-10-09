# A pill fills its line, a browser's inline box hugs its words

Seen 8 October 2026 in the side-by-side (section 32, `section32.png` -
browser left, LazInk right).  Tony: "the pills fills in the side by side
dont look quite as nicely sized as the real browser either."

## What shows

Under the long page's `line-height: 1.45`, LazInk's pills and badges come
out taller and chunkier than the browser's: the pill's box is drawn over
the run's whole line box, and a roomy line-height makes the line box
taller than the text.  A browser sizes an inline box to its content - the
font's own height plus the padding - and centers it on the line, whatever
the line-height around it.

## The fix (diagnosed, not yet done)

In the pill paint (inkrender.pas, PaintLayout pass 1), size the box from
the run's own text height plus `PillPadV`, placed from the run's baseline
(`DrawRect.Top + R.Ascent - CanvasAscent(R) - PillPadV`), instead of from
`DrawRect.Top..Bottom`.  The same was already done for the checkbox by
making it an element with its own fixed size; pills keep their text, so
they get the content-box treatment instead.  Check the run-background fill
beside it (clamped to the line today) while in there, and re-verify
section 32 and the chips in section 13 against the browser afterwards.
