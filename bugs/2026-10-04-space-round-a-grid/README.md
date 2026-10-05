# Too much space above and below a grid

Found 4 October 2026, after `bugs/2026-10-04-grid-card-text-unstyled` was
fixed.  The headings in the cards are right now, but a `display: grid` row
of cards still has more space above it and much more below it than a
browser gives it.  It is not the source's whitespace: the same page built
with no line breaks anywhere spaces out the same.

## The numbers

`send-window.html` is Heckers Sketch's send window page exactly as the
program builds it (made-up machine facts).  `send-window-browser.png` is
Brave at 846 px; `send-window-lazink.png` is the page in a `TInkPage` of
about the same width, in the program's window.  Measured from the bottom
edge of one table to the middle of the next heading's text:

| | browser | LazInk |
|---|---|---|
| banner to "Files" (no grid - the control) | 26 px | 27 px |
| files table to the cards' headings | 26 px | 43 px |
| the cards' tables to "The report" | 26 px | 62 px |

So spacing between ordinary blocks matches a browser to the pixel, and only
the edges of the grid are off: about 17 px too much above it and about
36 px too much below.

## A smaller page

`page.html` has the same shape with nothing else in it: a heading and a
table, another, a two-card grid of heading-and-table cards, then a heading
and a table after it.  In a browser the three gaps before the headings are
equal.

## Guesses, not findings

* The grid's `gap` (16 px here) added above the first row of cards and
  below the last, as well as between items.  That alone would be 16 px at
  each edge - close to the gap above, but less than the one below.
* A card's height counted with its heading's `margin-top` and the
  heading's or table's `margin-bottom`, with the larger of the two cards
  carried below the grid as well.

In the browser a card's heading sits 26 px under the table above the grid -
exactly where a heading outside a grid sits - so nothing extra belongs
there at all.

## What Heckers Sketch does meanwhile

Uses the cards anyway; the send window reads a little airier than it
should.  Nothing is worked round.

## Fixed - 4 October 2026

The first guess was right, and it was the whole of the gap above: the page
wrote the grid's `gap` as the generated table's `cellspacing`, and
cellspacing frames a real table on every side, where a grid's gap goes only
between its items.  The table markup a grid builds now says `gaponly="1"`,
and the renderer leaves the edges alone for such a table - rows and columns
keep the gap between them only.  Below the grid the same 16 px was joined
by the edge spacing counted into the block's height a second way through
the trailing row spacing, which is also gone.  The left and right edges
stopped needing the negative-margin trick that lined cards up with the
text, so that is gone too.

Measured on `page.html` after the fix: the three gaps before the headings
are equal, as the browser draws them; on `send-window.html` the banner,
the files table, the cards and "The report" all sit 26 px apart, the
browser's own rhythm.  `CardTextChecks` holds a one-row gaponly grid to
exactly the height of the same row without it, and the page to no band
above or below.

## Still about 18 px below the grid, in a real window - 4 October 2026, later

Checked again in Heckers Sketch's send window after the fix
(`send-window-in-program.png`; the page it drew is
`send-window-in-program.html`, byte for byte the same as `send-window.html`).
The space above the grid is right now.  The space below it is not.

Measured on the pictures by machine, not by eye: from the last full-width
table border row to the first row of the next heading's gray text.  The
browser figures are from `send-window-browser.png` (Brave, 846 px); the
LazInk ones from the `TInkPage` in the window, about 848 px wide.

| | browser | LazInk |
|---|---|---|
| files table to the cards' headings | 23 px | 24 px |
| the cards' tables to "The report" | 23 px | 42 px |

So about 18 px too much is left below a grid, close to the grid's 16 px
`gap` plus a pixel or two - as if one trailing gap, or the last card row's
spacing, is still counted into the block's height there.

**Not a stale layout:** after the window had shown it, the page was given
an empty `Source` and then the same source again, and the fresh layout
measures the same 42 px.  The send window does set `Source` several times
while files go out and resizes the page once at the end, so that was worth
ruling out.

**Why the tests may not see it:** `CardTextChecks` holds a one-row grid to
the height of the same row without the gap.  Here each card is a heading
over a seven-row table, and the two cards are the same height.  A check on
the block after a grid of taller cards - a heading and a multi-row table
in each - is where the extra would show.

## And fixed - 5 October 2026

The guess was close: not the grid's own spacing but a phantom line inside
each card.  A cell that ended with a nested table still finished with an
empty line box a text line tall, so every card - and with it the grid row -
was about 20 px taller than its content.  A trailing empty line in a cell
now collapses, as it does in a browser (a wholly empty cell keeps its one
line box).  The send window's gap below the cards measures 24 px against
the browser's 23, the same pixel the other gaps sit at, and the tests hold
a cell ending with a nested table to exactly its content's height.
