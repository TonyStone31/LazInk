# Wanted: light and dark, inline HTML in Markdown, and an ellipsis

Written 4 October 2026, from Heckers Sketch
(https://github.com/TonyStone31/heckers-sketch), after its send window moved
onto the summary-page features.  Each item is something it works round
today, but each is written as a general feature: nothing here should know
about Heckers Sketch, and each should be useful to anyone putting formatted
text in a Lazarus program.  None is a bug.

For each: what is wanted, how it could work inside LazInk, and what it must
not do.

---

## 1. Light and dark - `prefers-color-scheme` (the big one)

### The need

Help sites, release notes and README-style pages written for a browser do
their themes like this:

```css
:root { --bg: #23262c; --text: #e6e6e6 }            /* dark by default */
@media (prefers-color-scheme: light) {
  :root { --bg: #f4f5f6; --text: #1d2027 }
}
body { background: var(--bg); color: var(--text) }
```

LazInk reads the custom properties and `var()`, but `ReadMedia` in
`inkcss.pas` marks any feature other than `min-width`/`max-width` as
`FNever`, so the light block never applies and the page is always dark.  Any
program that shows such a page, or wants one stylesheet that suits both a
light and a dark window, has to edit the HTML or keep two stylesheets.

### How it could work

**In the stylesheet (`TInkStyleSheet`).**  A new property,
`ColorScheme: TInkColorScheme`, holding the scheme the sheet answers to:
light or dark, never "auto".  `ReadMedia` learns one more feature:

* `prefers-color-scheme: light` and `prefers-color-scheme: dark` are judged
  against `ColorScheme` when the block is read.  A block for the other scheme
  is `FNever`, exactly as a print block is today.
* They combine with the width features the way CSS does:
  `(prefers-color-scheme: dark) and (max-width: 600px)` holds only when both
  do.  The existing loop already ANDs features; this is one more branch in
  it.
* `not`, and features LazInk still cannot judge (`prefers-contrast`,
  `prefers-reduced-motion`), stay `FNever` as now.

Judging at read time keeps the lookup path and its memo untouched.  A change
of scheme means reading the sheet again, which is what a width crossing an
`@media` boundary already does (`TInkCustomPage.Layout`, `FMediaState`).

**On the controls.**  Every control that reads a stylesheet (`TInkPage`,
`TInkMemo`, and any other page-based one) gets a published property:

```pascal
type
  TInkColorScheme = (icsAuto, icsLight, icsDark);

property ColorScheme: TInkColorScheme read FColorScheme write SetColorScheme
  default icsAuto;
{ read-only: what icsAuto came to, for a host that wants to match it }
property ActiveColorScheme: TInkColorScheme read GetActiveColorScheme;
```

* `icsLight` and `icsDark` force the answer.
* `icsAuto` is worked out without any platform code, in this order:
  1. **The application's say, if it has one.**  A unit-level setting in
     `inkcss.pas`, say `InkAppColorScheme: TInkColorScheme = icsAuto`, that
     a program with its own light/dark themes sets once.  Every LazInk
     control on `icsAuto` then follows the program's theme, not the
     desktop's.
  2. **Otherwise, the control's own background.**  `ColorToRGB(Color)`,
     with `clDefault` read as `clWindow`, and light when its luminance is
     at least half.  This needs no widgetset code and already follows a
     dark desktop theme on GTK3, Qt and Windows wherever the widgetset
     reports a dark `clWindow`.  It also does the right thing when a host
     simply sets `Color` to suit its own theme.
* `SetColorScheme` reads the styles again and keeps the scroll position,
  the same way `ScrollBars` re-applies (`SetScrollBars`).  On `icsAuto`, a
  change of `Color` (`CMColorChanged`) does the same when it flips the
  answer.
* One call to tell every control at once, for a program that changes theme
  while windows are open: `InkColorSchemeChanged`, which walks
  `Screen.Forms` and asks each LazInk control to re-check.  Nothing needs
  to keep a list of instances.

**The host's `StyleSheet` reads the same queries**, so a program can hand in
one stylesheet holding both palettes and let LazInk choose.  That is as
useful as the page support itself: a release-notes window or a styled memo
written once for both themes.

**Optional, later: root attributes.**  Many sites let the reader override
the scheme with `:root[data-theme="light"] { ... }`, set by a script.  A
`RootAttributes: TStrings` on the page control (`data-theme=light`),
applied to `<html>` before matching, plus selector support for exactly
`:root[attr="value"]` and `html[attr="value"]`, would let those rules work
too.  It is not needed for the main case: with `ColorScheme` forced, the
media query alone already gives the reader's choice.

### What it must not do

* No widgetset-specific "is the desktop dark?" call in the first version.
  If one is ever added, it goes behind `{$IFDEF}`, falls back to the
  background rule everywhere else, and is documented per widgetset only
  once it has actually been run there.
* No built-in dark palette that LazInk applies on its own: the scheme only
  chooses between the rules the page and the host wrote.  A page with no
  `prefers-color-scheme` rules looks exactly as it does today.
* `print` stays never-applies.

### Tests and docs

* A rule inside `(prefers-color-scheme: light)` applies with `icsLight`,
  not with `icsDark`; and the reverse.
* Combined with a width query, both have to hold.
* `icsAuto` with a white `Color` answers light, with a near-black one dark;
  `InkAppColorScheme` beats the background.
* Changing `ColorScheme` keeps the scroll position.
* `HTML_SUPPORT.md` (the `@media` line) and the README's "Limits" say what
  is read.

**What Heckers Sketch does meanwhile:** its help window keeps a second
stylesheet holding only the light palette, and when the page should be light
it edits the page's HTML to link that sheet in after the main one.  With
this, the extra sheet and the HTML editing go, and the window sets
`ColorScheme` from the reader's Auto/Light/Dark choice.

---

## 2. Inline HTML in Markdown, leaving anything unknown as text

### The need

`MarkdownToHTML(S, [imoRawHTML])` passes all raw HTML through; without it,
all of it shows as text.  Real Markdown - release notes, READMEs - uses a few
inline tags (`<kbd>Ctrl</kbd>`, `<sub>`, `<sup>`, `<br>`) and also writes
placeholders in angle brackets the way command help does: `/tiles <folder>`,
`move <part> to <corner>`.  With raw HTML on, the placeholders vanish as
unknown tags.  With it off, `<kbd>` shows its brackets.  Neither is right.

### How it could work

A third choice in the converter (`inkmarkdown.pas`), `imoInlineHTML`, with a
matching `TInkPage.MarkdownInlineHTML` property:

* A tag is passed through only if it is **well formed** (`<name>`,
  `</name>`, `<name attr="...">`) and its **name is on an inline list**.
  The default list is the inline tags LazInk draws: `b i em strong u s del
  ins code kbd samp sub sup br span small mark abbr`.
* On a passed tag, only harmless attributes are kept (`class`, `title`).
  `style`, event attributes and anything else are dropped, so the option is
  safe for text that is not fully trusted.
* **Everything else is text**: `<folder>`, block tags (`<div>`, `<table>`),
  `<script>`, `<img>`, and anything malformed are escaped to `&lt;...&gt;`
  and shown as written.
* Code spans and fenced code are untouched, as now.  HTML comments are
  still dropped.
* The list is a public, editable `TStrings` (say `InkMarkdownInlineTags`),
  so a program can add a tag it trusts without patching LazInk.

`imoRawHTML` stays as it is, for trusted documents that really carry
blocks.  If both options are given, `imoRawHTML` wins.

### Tests

`<kbd>G</kbd>` draws as a key; `/tiles <folder>` shows `<folder>`;
`<div>x</div>` shows its tags; `<span onclick="..." class="k">` keeps the
class and loses the handler; nothing inside backticks changes.

**What Heckers Sketch does meanwhile:** before handing over its release
notes, it strips a fixed list of tags by name, so `<kbd>G</kbd>` reads as a
plain `G`.

---

## 3. An ellipsis for one line that does not fit

### The need

`HTMLDrawOpt` with `NoWrap` holds a line to one line and clips it at the
rectangle's edge, so the last word can stop halfway through a letter.  A
status bar, a list row, a command bar or a file name in a narrow column
wants the line to end in "…" instead.

### How it could work

Two fields on `THTMLOptions`, both default off, so nothing changes for
existing callers:

```pascal
Ellipsis: Boolean;        { with NoWrap: end a line that does not fit in EllipsisText }
EllipsisText: string;     { '…' (U+2026) unless set }
```

* Only with `NoWrap`.  The runs are measured as now.  The run that crosses
  the right edge is cut back a whole code point at a time (never inside a
  UTF-8 sequence), until it plus `EllipsisText` fits.  The ellipsis is
  drawn in that run's font and color.
* **A pill is one thing**, as it is for wrapping: if a pill does not fit
  whole, it goes, and the ellipsis follows the run before it.  An image
  likewise.
* If not even the ellipsis fits, nothing is drawn, rather than drawing past
  the rectangle.
* `HTMLTextExtentOpt` with the same options gives the cut width, so layout
  and painting agree.
* A way to know a line was cut, for a host that wants a tooltip with the
  whole text: `HTMLDrawOpt` returning `True` when it cut, or an out
  parameter on an overload.
* `TInkLabel` could then offer the same as a property for a single-line
  label (`Ellipsis`), using the same code.

**What Heckers Sketch does meanwhile:** the first row of its command bar
(colored words and key caps on one line) is drawn by hand, run by run,
trimming the last one a letter at a time.  The key caps could already be
`<font bgcolor pad radius>` pills; the ellipsis is the missing piece.

---

## Also open from the same work

`bugs/2026-10-04-grid-card-text-unstyled`: text in a grid card ignores the
stylesheet, a blank band follows a grid, and margins between blocks in a
cell are not read.
