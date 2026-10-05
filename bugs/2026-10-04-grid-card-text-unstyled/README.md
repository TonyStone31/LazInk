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
