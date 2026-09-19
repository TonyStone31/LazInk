# Rendering performance audit — 19 September 2026

This concerns HTML/Markdown document rendering, not image decoding.

**Measured workloads and method.** `tools/render_bench.pas` exercises the
actual `TInkPage` path rather than calling `TInkRenderer` directly. Each
workload starts in a fresh process, with a 900×640 page and DejaVu Sans at
16 pixels, then resizes to 650 pixels wide. Parsing and initial layout are
timed separately. Repaint and scroll times are means of eight draws;
scrolling visits positions throughout the document. PNG writing is outside
the timed sections.

The paragraphs contain bold/italic text, links, inline code, and Unicode.
The tables have four columns, wrapping text, and middle/bottom alignment.
The nested workload puts another table inside each outer row. The styled
workload has 500 paragraphs and 360 CSS rules, including descendant
selectors. The spans workload adds rowspans and colspans.

Environment: Linux x86-64, GTK3, FPC 3.3.1, Lazarus trunk, `-O2`. These are
synthetic workloads and bitmap-canvas draws; they do not measure compositor
presentation, resource downloads, image scaling, or animation decoding.
Absolute timings vary by machine and widgetset — **before and after must be
measured on the same machine**, which is why the figures below were taken by
stashing the changes and rebuilding rather than compared against an earlier
run elsewhere.

Before is commit `0121d7e`. Milliseconds:

| Workload | Parse | Initial layout | Repaint | Scroll/draw | Resize/layout |
|---|---:|---:|---:|---:|---:|
| 2,000 paragraphs | 36 → 38 | 299 → **285** | 3.750 → **1.750** | 3.750 → **3.375** | 284 → **268** |
| 250-row table | 14 → **10** | 73 → **50** | 63.500 → **2.125** | 63.875 → **2.125** | 61 → **43** |
| 60-row nested table | 7 → **4** | 53 → **37** | 46.500 → **2.000** | 45.375 → **2.125** | 43 → **28** |
| 60-row spans table | 7 → **4** | 55 → **37** | 46.750 → **2.500** | 45.125 → **1.625** | 43 → **29** |
| 500 paragraphs / 360 CSS rules | 531 → **33** | 861 → **129** | 8.625 → **1.750** | 7.750 → **3.375** | 838 → **65** |

The headline numbers: **a table repaints and scrolls about 25 to 30 times
faster**, and **a stylesheet-heavy page parses 16 times faster and relays out
13 times faster**. Rendering is unchanged: the comparison page is still 3,194
pixels against the browser's 3,199, and the retained-layout checks compare
painted pixels and callback traces rather than only asserting a render
succeeded.

### A later pass

Two more, once the renderer was drawing at the right sizes and layout was
the remaining cost:

* **The cache key a run makes from its style is kept between runs.** It was
  four `IntToStr` calls and a handful of concatenations *per word*; a
  paragraph's words nearly all share one style, so it is now built when the
  style changes and reused otherwise.
* **`Metrics` answers from the run before it.** Its result depends only on
  the style and the line height, and consecutive runs almost always share
  both, so a few comparisons replace a key and a binary search.

Layout and re-layout, before and after that pass:

| Workload | Initial layout | Resize/layout |
|---|---:|---:|
| 2,000 paragraphs | 293 → **231** | 278 → **211** |
| 250-row table | 50 → **40** | 43 → **34** |
| 60-row nested table | 36 → **29** | 29 → **19** |
| 60-row spans table | 37 → **30** | 29 → **19** |
| 500 paragraphs / 360 CSS rules | 143 → **126** | 70 → **52** |

## What was changed

**Retained layout (the big one for tables).** `InkDraw.HTMLDrawOpt` always
called `Tokenize`, and `Tokenize` clears the layout, so `TInkCustomPage`
re-laid out every visible block on every repaint. A large table is one block,
so all of its cells were measured again even when a few rows were showing.

`THTMLLayoutCache` is a bounded, owner-scoped LRU of immutable layouts, and
`TInkPage` owns one. Painting, measuring and hit testing now consume the same
geometry. The renderer grew `DetachLayout`, `PaintLayout`, `HitTestLayout`
and `ReportLayoutRuns` so a finished layout can be used without keeping the
tokens, box tree and working caches that built it, and `TInkRenderLayout`
grew `Retain`/`Release` so a callback may clear the cache while its own
layout is still being painted.

The identity is exact rather than hashed — a collision must never display
other text — and covers source, canvas, device, DPI, every font field, width,
scale, borders, line spacing, line height, wrap, alignment, the aligned
height, and the image list's identity, size and count. Hover, selection,
link colors and run callbacks are deliberately *not* part of it: they are
paint-time state applied to retained geometry, which is why hovering and
selecting no longer remeasure anything.

Two things made the difference between a cache that helped and one that hurt:

* **The lookup is keyed on a 64-bit FNV-1a hash**, with the identity kept as
  a record and compared with `CompareMem` only after the hash matches. The
  first version compared a ~100-byte key string and the whole block source
  against every entry, which cost more than it saved on a page of many small
  blocks: scrolling 2,000 paragraphs went from 3.75 ms to 5.125 ms. With the
  hash it is 3.375 ms.
* **One builder renderer is kept per cache** rather than created per miss.
  Word widths and font metrics are the expensive part of measuring and a
  page's blocks share most of their words; a fresh renderer per block threw
  that away. It is discarded when the device or font DPI changes, which is
  what those caches are keyed on but cannot see. `Tokenize` resets the style
  key, so reuse cannot carry stale styles across sources.

**CSS lookups are remembered.** `InkCSS.Value` scanned every rule for every
property of every block, reparsing selectors and allocating two string lists
per call. It now (a) skips rules that do not declare the property before
parsing their selectors or matching ancestors, (b) reuses the two scratch
lists instead of making and freeing them per call, and (c) remembers what it
worked out, keyed on tag, classes, property and ancestor context, so 500
paragraphs wearing 40 classes ask the rules 40 times. The remembered value is
stored *apart from the caller's fallback*: the fallback belongs to the call,
the value to the sheet. Adding a rule or a variable, clearing the sheet, or
changing the media width forgets everything.

The memo keys are compared **case-sensitively**. That is not a detail: a
`TStringList` compares with `AnsiCompareText` by default, and a binary search
paying for a locale-aware comparison at every step made the plain-paragraph
workload *slower* — parse 36 → 59 ms — even though the memo held only 1,059
entries. Byte comparison put it back to 38 ms and took the styled workload's
parse from 439 ms to 33.

**Cached numbers are numbers.** The renderer's width and metric caches stored
their values as strings in a parallel `TStringList`, so every hit ran
`StrToInt` and every miss inserted into a second sorted list. Both now live
in the key list's own `Objects` pointer — the width directly, the metric
height and ascent packed into sixteen bits each.

**Metrics on a cache hit no longer call the widgetset.** `StrToIntDef(value,
Canvas.TextHeight('Tg'))` evaluates its default argument eagerly, so a
successful lookup still asked GTK for a height.

**Table layout.** Each cell's measured content height is retained once its
column width is final; rowspan adjustment and vertical alignment reuse it
instead of calling `LayCell` again, which also avoids re-measuring nested
tables twice. Row and column offsets are computed once as prefix sums rather
than re-summing every preceding row and column for every cell. That removes
one quadratic component of table layout; it does not make the whole algorithm
linear.

**Box tree construction.** `TInkBox.AddChild` invalidated every existing
child on every append, so building a row of cells cost the square of their
number. A new child says nothing about the children already there, so it now
marks only the box itself.

**The animation tick.** A 20 ms timer walked every block of every document,
including documents with nothing moving in them. The page now keeps a short
list of the blocks that can animate and **switches the timer off when that
list is empty**. `TInkPage.Animating` reports it, and the suite checks that a
page of still pictures stops the tick, an animated one runs it, and replacing
the document stops it again.

**Two leaks and a bug fixed on the way.** `TInkRenderer.Destroy` did not free
its box tree (rebuilding freed the preceding one, so only the last leaked).
`InkDraw`'s run relay was a global font and handler pair, which cannot
survive a callback that measures something else; it is now an object created
per call. And the retained-layout tests caught a real rendering fault:
**an inline `<img>` from an image list was laid out at the width of its
placeholder character**, because `MeasureInline` computed the picture's size
and then overwrote it with `MeasureRun` of the `#1` it stands for. A picture
now takes its own size and sits on the baseline.

## Correctness

The retained-layout suite (`tests/layout_cache_checks.pas`) renders the same
markup with and without the cache and compares **painted pixels and the full
run-callback trace**, not just that a render happened. It covers nested
tables, rowspans, vertical alignment, scroll offsets, hover, link styling,
selected and disabled states, measurement, hit testing inside a spanning
cell, a callback that clears the cache and recursively measures something
else while its own layout is being painted, every invalidation key above,
another canvas, and entry-budget eviction.

One pre-existing test had to change. The Markdown anchor check asserted a
positive scroll position, but its 497-pixel document now fits inside the
500-pixel viewport, so there was nothing to scroll. It uses a 200-pixel
viewport, asserts the document overflows it, then restores the height. No
anchor behavior changed.

One of the new tests was wrong and is now right: it resized a `TImageList`
and expected it to keep its images. A `TImageList` empties itself when it is
resized, so the picture has to be added again at the new size — otherwise the
run falls back to the placeholder and the geometry does not move for the
reason the test meant.

## Follow-up review at `f7ad2c4`

These findings come from a read-only source review after the retained-layout,
CSS memoization, metric, animation-list, and subsequent rendering fixes.
They are proposals for a later implementation pass: **no new timings were
collected, no GUI tests were launched, and no rendering code was changed
for this review**. The measurements above describe earlier passes, not the
cost of each finding below. Priority reflects the expected benefit and
implementation risk; it is not a measured speedup ranking.

### 1. Reject vertically offscreen runs inside tall cells

In `InkRender.TInkRenderer.PaintLayout`, vertical rejection happens at the
line level, while individual runs are rejected only horizontally. A table
cell's line record can cover its full height. If a small part of a tall cell
is visible, its offscreen text can still be submitted to the canvas; clipping
limits the pixels drawn but does not eliminate the submission work.

Add conservative vertical rejection for individual paint operations. Keep
`OnRun` callback behavior intact rather than silently dropping callbacks
when adding the paint rejection. Include superscripts, subscripts, spanning
cell backgrounds, and borders in the bounds checks. This is the first
candidate for a relatively small improvement. Validate with a cell much
taller than the viewport, at its top, middle, and bottom, and count drawing
calls as well as comparing pixels.

### 2. Remove repeated work in nested tables

`InkRender.TInkRenderer.LayoutTable` adds an enclosing cell line whose run
range includes the runs emitted by nested tables. Those runs also belong to
the nested tables' own line records. `PaintLayout` visits both ranges, so
nested content can be submitted more than once. More nesting adds more
visits; clipping alone does not remove that duplication.

Establish one paint traversal for each operation. This needs careful testing:
the current traversal also determines when enclosing backgrounds and borders
are painted. Merely skipping a repeated run could leave it covered by a
later background. Preserve callback behavior, link hits, and selection.

There is a separate layout cost: `MeasureNested` builds a complete temporary
layout to obtain a height, frees it, and placement later builds the nested
table again. This repeats recursively with nesting depth. Retain child
geometry at its final width and translate it during placement, preserving
rowspan sizing, alignment, padding, and paint order. Benchmark nesting depth
separately from row count to expose the repeated work.

### 3. Move decoration parsing out of repaint; dispatch only dirty blocks

`PaintLayout` rebuilds a `TStringList` from each cell decoration's `R.Meta`
and resolves colors, border flags, sides, and radius on each repaint. Store
resolved decoration fields in the immutable layout instead. Preserve current
scaling and color semantics; compare rounded corners, partial borders,
inherited cell colors, and transparent backgrounds.

`InkPage.TInkCustomPage.RenderTo` filters blocks against the full viewport,
even when a WebP update invalidates only one image rectangle. Intersect the
canvas's dirty clip with the viewport before dispatching block painting.
Use conservative bounds that include quote bars extending into gaps, block
decorations, and selection. These are smaller changes to try before the
larger indexing work below.

### 4. Avoid hashing the entire source on every cache hit

`InkDraw.IdentityHash` walks every source byte each time
`THTMLLayoutCache.Acquire` is called, including successful paint and hit-test
lookups. An enormous table is one block, so scrolling or moving the pointer
over it repeatedly reads the whole table's markup.

Compute a source fingerprint when markup changes, or use a stable block
identity plus a source revision for page-owned entries. Preserve collision-safe
matching and the complete geometry identity. Revisions must change for
resolved markup changes, including CSS-driven markup and rebuilt flex tables;
a raw string pointer is not a safe replacement. Keep the general drawing API
correct for callers without page-owned identities. Measure warm cache lookup
cost as source size increases while the viewport stays fixed.

### 5. Share spatial lookup between painting and interaction

`RenderTo` visits every page block, and `PaintLayout` visits every retained
line. `MouseMove` can cause separate scans through `HitTestLink`, `BlockAt`,
and the text-cursor check. Thus both scrolling and pointer movement retain
costs that grow with the document rather than only its visible content.

Index conservative block and run bounds and share lookup results where
possible. Include folded blocks, quote-bar extensions, rowspans, and nested
cells. Existing table line records are **not sorted by Y**: do not simply
binary-search that array or stop at the first offscreen line. Preserve paint
order among the operations found by the index. Benchmark pointer movement
near the end of a large document as well as repainting it.

### 6. Share initial measurement with first paint without cache thrashing

`InkPage.TInkCustomPage.Layout` calls `HTMLTextExtentOpt` without the page's
retained cache. The first paint then builds geometry again for visible blocks.
Retain measured layouts for the viewport and a modest surrounding region, or
use a two-tier strategy that keeps useful geometry within a memory budget.

Simply passing the existing 128-entry cache through the entire layout loop
would mostly retain the tail of a 2,000-block document and evict the top before
painting it. Preserve canvas/device compatibility when sharing measurement
results; rendering to a bitmap is not automatically the same as rendering to
the control. Measure load-to-first-paint, cold scrolling, warm repaint, resize,
and retained memory separately.

### 7. Bound the builder's measurement caches separately

The layout cache's byte budget does not include the retained builder's
word-width and metric caches. `THTMLLayoutCache.Clear` releases layout entries
but leaves `FBuilder` alive. Unique widths continue accumulating through
`TInkRenderer.MeasureRun`, including across document replacements, and sorted
list insertion becomes more expensive as those caches grow.

Give measurement caches their own limits and explicit font/device identity;
retain the benefit of sharing common words between blocks. Consider releasing
obsolete builder working data on document replacement. Test repetitive prose,
mostly-unique identifiers, and repeated navigation through unrelated documents.
Measure total retained memory, not only `THTMLLayoutCache.Bytes`. The existing
exception that permits one oversized retained layout also means the layout
budget itself is a soft limit.

### Additional profiling candidates

- `InkCSS.Value` still visits every rule on a memo miss and reparses matching
  candidates' selectors; each rule's `Values[Prop]` lookup is also linear.
  Precompile selectors and index declarations by property if first-load
  profiling of large stylesheets justifies it. Memoization already handles
  repeated contexts, so this is no longer the first general optimization.
- Tokens, styled runs, lines, cells, and box-child arrays grow one element at
  a time. Consider reserved capacity or geometric growth where allocation
  profiling shows a benefit. Avoid assuming every resize copies the entire
  array, and account for memory retained by spare capacity.

**Suggested implementation order:** individual-run clipping and resolved
decorations first; nested-table duplication next; then source revisions and
spatial indexing. Initial-layout sharing deserves a separate first-paint
benchmark, and builder memory limits deserve a long-session benchmark.

Keep LCL canvas and font operations on the UI thread. Validate optimizations
against the recently corrected table sizing, wrapping, and heading margins,
using pixel comparisons and callback/interaction checks rather than timings
alone. No speedup is promised until measured on representative documents.

## How to reproduce

```sh
export LAZARUS_DIR=/path/to/lazarus
export FPC=/path/to/fpc
tools/run_render_bench.sh paragraphs 2000 /tmp/render-shots
tools/run_render_bench.sh table 250 /tmp/render-shots
tools/run_render_bench.sh nested 60 /tmp/render-shots
tools/run_render_bench.sh styled 500 /tmp/render-shots
tools/run_render_bench.sh spans 60 /tmp/render-shots
tests/run.sh
```

Set `LCL_WIDGETSET` to another built widgetset to audit it separately. Use
fresh processes and compare both timing and geometry; the tool prints block
count and document height before and after resizing. Compare PNG pixels
between revisions rather than just checking that a render succeeded.
`tools/renderer_dryrun.pas` benchmarks the direct engine API. It does not
exercise page-level cache lookup, block dispatch, or the separate initial
measurement and paint paths; use `render_bench` for those costs.
