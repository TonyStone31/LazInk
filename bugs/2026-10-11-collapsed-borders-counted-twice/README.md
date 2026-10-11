# A collapsed table charged every shared border twice

Found 11 October 2026 on the demo's side-by-side tab - Tony: "in
section 4 and 5 we still have a height difference."  Measured: the
browser's table rows ran 35 pixels of pitch, LazInk's 36, one pixel a
row across every `border-collapse: collapse` table.

## Why

Collapse only zeroed `border-spacing`.  Each cell still carried its
own top and bottom border in layout, so an interior edge cost two
pixels where a browser charges the shared edge once.

## Fixed, the same day

`LayTable` now gives one pixel back at every interior row boundary -
the shared edge is the narrower of the meeting borders, so a uniform
grid shares its whole border and a borderless table shares nothing -
and a cell above a shared edge reaches into it, so its bottom border
and the next row's top border paint the same pixels: one line, as a
browser draws it.  Row pitches after: 59, 35, 35, 35 against the
browser's 59, 35, 35, 35, rowspan tables included.  Column edges still
charge both sides - a table runs a pixel or two wide per interior
column, left for the day it gets in the way.
