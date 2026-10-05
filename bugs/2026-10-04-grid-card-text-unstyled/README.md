# Text in a grid card ignores the stylesheet

Found 4 October 2026, moving Heckers Sketch's send window
(`src/app/hsSendReport.pas` there) onto the summary-page features that landed
the same day (`bugs/2026-09-20-summary-page-wants`).  The pills, `nowrap`
cells, cell font sizes and a `div` title in a cell all worked.  These did not.
`page.html` beside this shows all three; open it in a browser and in
`TInkPage` side by side.

## 1. Text in a grid card is not styled

Two `display: grid` cards, each a heading over a key/value table.  The tables
are laid out and dressed properly.  The heading above each is not: an `<h3>`
comes out as bold body text, not the `h3` rule's 12px gray uppercase, and a
`<div class="cap">` comes out as plain body text.  A `.cards h3` rule does
nothing either.

The summary-page note says this case is "written exactly as a browser page
would write it"; the tables are, the text beside them is not.

## 2. A blank band after the grid

The block after the grid starts well below where its margin puts it: in the
send window, a band of empty space roughly three lines tall.

## 3. Spacing between blocks in a cell

In a cell, `div.title` and `div.sub` are separate lines in their own sizes,
as promised, but `margin-top` on the second and `line-height` on the first
are not read, so the two lines touch.

## What Heckers Sketch does meanwhile

Keeps its old five-column table (key, value, gap, key, value) for the two
fact sections, with the captions as `td.cap` cells.  Item 3 it lives with.

## Fixed - 4 October 2026, all three

1. A heading or a div in a grid/flex card now takes its stylesheet rule -
   size, weight, color and text-transform - through the same path a block
   child of a table cell does, in the card's own CSS context.
2. The band was the page manufacturing blank lines out of the source's own
   indentation: whitespace between block tags inside a cell or a card is
   now dropped at every block edge, the way a browser drops it.  What
   remains above a card's heading is the heading's own margin-top, which a
   browser shows too.
3. A block's `margin-top` and `margin-bottom` inside a cell or a card -
   shorthand, longhand or style attribute - become a `<vgap=N>` in the
   markup, and the renderer opens exactly that gap.  `line-height` on a
   block inside a cell is still not read.

Tests: `CardTextChecks` in `tests/render_tests.pas` holds this page's
banner and cards to the markup they should make, and the engine to the
exact gap.
