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

## Still open

| Priority | Finding | Proposed change and constraints |
|---|---|---|
| 1 | Page painting scans every block against the viewport, and engine painting scans all layout lines even with a retained layout. At 2,000 blocks the scan is cheap (1.75 ms) but it grows with the document, not the window. | Index conservative paint bounds and locate the visible interval. Include quote bars that extend into the margin, folded blocks, and spanning cells. Table and nested-table line records are **not** sorted by Y: do not binary-search the line array or stop at the first offscreen row. |
| 2 | The page compares blocks against the whole viewport, although a WebP timer can invalidate one image rectangle. Text is laid out before the engine applies its canvas clip. | Intersect the invalid region with the viewport before dispatching block painting, preserving decorations and selection. |
| 3 | Initial layout of many small blocks (285 ms for 2,000 paragraphs) is the largest remaining cost. Each block is tokenized, styled and measured through the shared engine, and the result is thrown away before paint builds it again. | Let the layout pass fill the same cache the paint pass reads, so a block is built once. Needs a cache big enough for the document, or a two-tier scheme, or the thrash will cost more than the sharing saves — a 128-entry cache over 2,000 blocks evicts everything before paint runs. |
| 4 | The word-width cache is unbounded and shared by every block through the engine. | Bound it with explicit font/device identity. Benchmark repetitive prose *and* mostly-unique identifiers or log data; the two behave very differently. |
| 5 | `InkCSS.Value` still visits every rule on a miss, and `TStringList.Values[Prop]` is itself a linear scan of the rule. | Parse selectors when rules are added and index declarations by property, so a lookup visits only the rules that can answer it. The memo already hides most of this; it would show on a first paint of a very large stylesheet. |
| 6 | Tokens, styled runs, lines and cells grow their arrays one element at a time. | Reserve capacity or grow geometrically where profiling shows it matters. Do not assume a cached box is only its height: some measurement callbacks also emit runs into the layout. |

The largest remaining win is eliminating the duplicated build between layout
and paint (3 above), not threads. **Do not move LCL canvas or font operations
to worker threads.** And a same-source early return in `Tokenize` is not a
substitute for the cache: the shared engine alternates between blocks, and
the option and metric keys do not fully describe device and image state.

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
`tools/renderer_dryrun.pas` benchmarks the direct engine API, which does not
exercise the page wrapper's repeated `Tokenize` calls.
