# An inline-block is a pill, not a box

Found 11 October 2026, the day the showcase grew its CSS sections -
the first catch of the demo's own side-by-side tab, with `tools/drift.sh
demo/showcase.html` pointing at it: section 12 lands 120 pixels short
of the browser.

## What shows

Section 12 of `demo/showcase.html` ("Borders of every stripe"), against
the browser's picture beside it:

* `width: 110px` on an inline-block chip is ignored - the chip hugs its
  word, so eight chips fit two rows where the browser needs three.
  `text-align: center` inside the forced width has nothing to center in.
* `border: 2px dashed` (and dotted, double, inset, outset, groove,
  ridge) draw as a thin solid line.  Block boxes get all these styles
  from `TreePaintBox`; inline boxes do not.
* `<span class="dot">` - an empty inline-block with `width`, `height`,
  a background and `border-radius: 50%` - disappears entirely.

## Why

The tree serializer (`inkpagetree.inc`, `Element()`) turns any inline
element with a background or border into a *pill*: `pad`, `radius` and
`pillborder` attributes on a `<font>` run.  The pill is measured from
its words, its border is one solid rounded stroke, and with no words
there is no run at all.  A browser makes an inline-block an atomic
inline-level *box*: sized by `width`/`height` when given, bordered like
any block, present even when empty.

## The fix, when taken

Either teach the pill run an explicit size (`minw`/`minh` attributes,
centered words, the full `Side()` border styles), or - truer - let an
inline-block become a real `TInkBox` laid into the line like an image
run.  The second follows the engine's direction (boxes from computed
styles everywhere); the first is the smaller patch.

Repro: load `demo/showcase.html`, section 12, beside
`demo/showcase-browser.png` - the demo's Side by side tab does exactly
this.

## Fixed, 11 October 2026

The smaller patch, done whole: the pill run learned to be an atomic box.
The serializer marks any inline-block (`pillbox`), carries its border
box (`minw`/`minh`, CSS width plus the padding and border), its centered
words (`pillc`), its border's width and style (`pillbw`, `pillline`),
turns a percentage radius into one the engine clamps to a circle, and
puts a zero-width space in an empty sized element so a run exists to
size.  The engine honors the forced width in all three measuring paths
(lines, cells, narrowest-word), centers by growing the side padding the
words are drawn behind, stands an empty box whole above the baseline,
lets an atomic box grow its line the way a picture does, and draws
dashed, dotted, double and the two-tone bevel borders side by side
(`PillSides`).  Checks: the width is law (126 wanted), the empty dot
stands 46 by 46, a dashed border has dashes - each proven able to fail
by putting the mutation back.  Sections 11 and 12 of the showcase were
one bug; both came right together.

Still approximate: an inline-block's vertical margins do not reach its
line box, so stacked chips sit a little tighter than a browser's.
