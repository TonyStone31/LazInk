# What a summary page wanted and could not have

Written 20 September 2026, from Heckers Sketch's send window
(`uSendForm.pas` there).  It shows what went when a bug report is sent: a
banner, a table of files whose rows change color as each is encrypted and
sent, and cards of facts about the machine and the program.  It is built as
HTML and redrawn a handful of times while the report goes.

It came out well.  These are the places where the page had to be written
round LazInk rather than the way a browser page would be, in the order they
cost the most.  None of them is a crash; each is a request.  `page.html`
beside this is the page as it would be written for a browser, with one
numbered rule in its stylesheet for each item below - open it in a browser
and in `TInkPage` side by side and the differences are the list.

## 1. `font-size` on a table cell is not read

`td.file { font-size: 12px }` does nothing, and neither does
`td.big { font-size: 22px }`.  HTML_SUPPORT.md says as much - a cell carries
`background`, `color`, `border`, `padding`, `text-align`, `valign` - so this
is a gap, not a bug.  But a smaller face for one column is the ordinary way
to make a long file name fit, and it was the first thing asked for.

**Worked round with** `<b style="font-size: 22px">` and
`<code>` (whose 12px comes from the `code` rule) inside the cell.

**Wanted:** `font-size`, `font-weight`, `font-family` and `line-height` on
`td`/`th`, by tag or class, reaching the text in the cell.

## 2. No way to keep a cell on one line

`white-space: nowrap` is listed as read, but on a `td` it does not stop the
table folding `85 KB` or `did not go` onto two lines to give a long
neighbor more room.  And `&nbsp;` does not help: **an `&nbsp;` entity is a
place a line may break**, where a raw U+00A0 character in the source is
not.  The last paragraph of `page.html` shows it - the entities wrap, and
the same text with real U+00A0 characters does not.

**Worked round with** raw `#$C2#$A0` bytes in place of spaces.

**Wanted:** `&nbsp;` to be non-breaking like the character it stands for;
and `white-space: nowrap` on a cell to set that column's minimum width to
the whole text.

## 3. A `<div>` inside a cell is flattened into the line

Two `<div>`s in a `<td>` - a title and a line under it - came out as one
run of text on one line, the second straight after the first.  A `<br>`
between two sizes of text then overlapped them, because the line took the
smaller size's height.

**Worked round with** two rows of one cell each, the same background on
both, which costs the rounded corners.

**Wanted:** block children of a cell (`div`, `p`, `h3`) laid out as blocks,
each with its own size and line height.

## 4. A table inside a card, or inside a cell, loses its dress

This is the one that shaped the page.

* A `<table>` inside a `display: grid` (or flex) card is drawn as **plain
  running text** - the keys and values of the table run together as
  sentences.  Cards are laid out, but only of text.
* A `<table>` inside a `<td>` is drawn as a table, but its cells **do not
  take their classes or the `td` rule**: no padding, no background on the
  key column, and an `<h3>` above it in the same cell is drawn as body
  text.

Two cards side by side, each holding a small key/value table, is what a
summary like this is, and neither way of writing it worked.

**Worked round with** one table of five columns - key, value, a gap cell
with no border, key, value - and a row for each *pair* of facts, so the two
"cards" share their row heights and are not really cards.

**Wanted:** a table as a child of a grid/flex item, laid out in the item's
width; and the full cell styling for a table nested in a cell.  With those,
`border-radius` and a border on the card would make real cards.

## 5. Inline boxes: a pill

`<span style="background: ...">` colors the words, but there is no
`padding` or `border-radius` on an inline span, so a status cannot be a
rounded pill sitting in a cell.

**Worked round with** coloring the whole cell.

**Wanted:** `padding`, `border-radius` and `border` on a `<span>`.  Low on
the list; the colored cell reads well enough.

## 6. Smaller things

* `font-weight: bold` on a `td` by class is not applied (`<b>` inside is).
* A way to change one element without reloading the page - `SetInnerHTML`
  by `id`, say - would make a live status page cheap.  Reloading a page
  this small a handful of times is fine; it would not be for a log.

## What worked, for the record

Cell backgrounds and colors by class, `colspan`, `border-collapse`,
`text-align` in cells, `<small>`, `<code>`, `<ul>`, a full document with
its own `<style>` through `TextFormat := itfHTML` and `Source`, and redrawing
the whole page five or six times in a few seconds with no flicker worth
mentioning.
