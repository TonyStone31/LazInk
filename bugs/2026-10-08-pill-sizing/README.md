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

## Done, 10 October 2026

The tree rework had already brought pills most of the way; what was
left sat in layout, not paint.  A pill run's box took its height from
`MeasureRun`, whose height is the run's line metrics - and under
`line-height: 1.45` those carry the half-leading, so every pill stood a
leading taller than its words.  Now a pill is measured with the
line-height switched off (its box is the font's height plus the
padding, placed from the baseline), and the line takes what a plain run
of that style would give it, since an inline box in CSS may stand
taller than its line without growing it - which is also what keeps the
`line-height: 1` inline-shading check honest.  Against Chromium the
test pill lands on the same pixel rows (box 20..42 both sides, 23px).
The suite check renders one pill at line-height 1 and again at 2.2 and
wants the same box both times; the old code gave 19 and 37.  Section 32
re-verified against the browser side by side; sections 13 and 32 share
one builder, so the chips are the same check.
