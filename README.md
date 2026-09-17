# LazInk

Lightweight HTML-formatted text controls for Lazarus, drawn entirely with
`TCanvas`. Because no native text widget is involved, the controls are
designed to render the same on every LCL widgetset. No RichMemo, no
widgetset-specific backends, no browser engine.

> **Status: 0.9.** Usable, and the API may still change. Built and tested with
> FPC 3.3.1 and Lazarus trunk on **GTK3 / Linux x86-64**. Other widgetsets
> (win32, gtk2, qt5/6, cocoa) should work because nothing here is
> widgetset-specific, but they have not been run yet - reports welcome.

![The LazInk palette](images/palette.png)

## The controls

| | Control | What it is |
|---|---|---|
| ![](images/TInkLabel.png) | `TInkLabel` | A label whose Caption understands inline markup. AutoSize aware, optional `WordWrap` and `MaxWidth`, `VertAlign`/`HorzAlign` for placing the text block in a bigger box, transparent by default. |
| ![](images/TInkEdit.png) | `TInkEdit` | A single-line edit box where **every character can have its own colour and style**, supplied by the `OnGetCharAttrs` event. The text stays plain — great for password-strength colouring, highlighting digits/symbols, or syntax-colouring markup as it is typed. Full editing: caret, selection, clipboard, MaxLength, ReadOnly, alignment. |
| ![](images/TInkRichEdit.png) | `TInkRichEdit` | A **multi-line WYSIWYG editor**. The caret and the selection sit inside the rendered text: select a word, call `ToggleStyle(fsBold)`, and that run stops being plain. Per-character colour, background, size, face, style, super/subscript and links; word wrap; paragraph alignment; undo/redo; a `Markup` property that round-trips to the markup below. |
| ![](images/TInkMemo.png) | `TInkMemo` | A scrollable multi-line **viewer** — a log, a transcript, formatted help. Each line of `Lines` is one paragraph of markup, lines can differ in height, optional `WordWrap`. |
| | `TInkPage` | A scrolling **document viewer** for complete HTML or Markdown pages: headings, lists, tables, code and key labels, PNG and animated GIF images, relative links, anchors, Back and Forward, and a small stylesheet reader. See [Complete help pages](#complete-help-pages). |
| ![](images/TInkListBox.png) | `TInkListBox` | An HTML-rendering listbox with an in-place editor that floats over the clicked item, holding either its plain text or (with `EditRawHTML`) its markup. Optional `AlternateColor` striping. |

`TInkLabel`, `TInkMemo` and `TInkListBox` also share: an `Images` list for
`<img src="n">`, `Borders` and `LineSpacing`, a `LinkStyle` / `LinkHoverStyle`
pair so links light up under the mouse, `AutoOpenLink`, and the full set of link
events — `OnLinkClick`, `OnLinkEnter`, `OnLinkLeave`, `OnLinkRightClick`.

## Supported markup

```
<b> <i> <u> <s>                        bold / italic / underline / strikeout
<font color= bgcolor= size= face=>     #RRGGBB, clRed-style and named colours
<sup> <sub>                            superscript / subscript
<br> <hr>                              line break / horizontal rule
<p>...</p>                             paragraph: a break plus a blank line
<center> <right> <left>                whole-line alignment
<ind="20">                             indent
<a href="...">text</a>                 links (OnLinkClick, hover styling)
<img src="n">                          entry n of the control's Images list
&amp; &lt; &gt; &quot; &nbsp; &copy; &reg; &trade; &euro;
```

Wherever text wraps — `TInkLabel.WordWrap`, `TInkMemo.WordWrap`,
`TInkRichEdit` — lines break on spaces, after slashes in long paths, and,
because CJK does not separate words with spaces, after any Chinese, Japanese or
Korean character, keeping closing punctuation off the start of a line.

Example:

```pascal
InkLabel1.Caption := 'Status: <b><font color="#00AA00">connected</font></b> to <a href="cfg">server</a>';
InkMemo1.Append('<font color="clGray">12:04</font> <b>tony</b> joined');
```

`TInkEdit` doesn't parse markup — it asks you per character instead:

```pascal
procedure TForm1.InkEdit1GetCharAttrs(Sender: TObject; AIndex: Integer;
  const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
begin
  case AChar[1] of
    '0'..'9': AColor := clGreen;
    'A'..'Z', 'a'..'z': ; // leave default
  else
    AColor := clBlue;   // symbols
  end;
end;
```

`TInkRichEdit` is the other way round again — it owns a document, and markup is
only what it reads from and writes back to:

```pascal
InkRichEdit1.Markup.Text := 'A <b>bold</b> start.';   // one paragraph per line
InkRichEdit1.ToggleStyle(fsBold);                     // acts on the selection
InkRichEdit1.ApplyColor(clRed);
InkRichEdit1.ApplySize(18);
ShowMessage(InkRichEdit1.AsHTML('<br>'));             // feed a TInkLabel or TInkMemo
```

With nothing selected, the `Apply*` calls set what the next typed character will
wear, the way every editor behaves. `SelStyle`, `SelColor`, `SelSize`,
`SelFace`, `SelScript` and `SelAlignment` report what the selection currently
carries, so a toolbar can show the right buttons pressed.

## Complete help pages

`TInkPage` is the native scrolling page viewer for complete HTML help files.
It renders the original Heckers Sketch manual with headings, lists, tables,
code/key labels, screenshots, animated GIFs, relative links, and Back/Forward.
Its small stylesheet reader picks up the site's palette and basic typography;
CSS grid cards become a vertical list. No browser engine is added.

```pascal
InkPage1.LoadFromFile('/path/to/help/index.html');
```

**Its scrollbar** is drawn by LazInk (`TInkScrollBar`), so it can wear the
page's colours instead of the platform's grey.  It reads the same CSS a
browser does:

```css
html { scrollbar-color: #4ab3e8 #1b1e24; scrollbar-width: thin; }
```

`scrollbar-color` is the thumb, then the track - `#rgb`, `#rrggbb`, a colour
name, `rgb()`/`rgba()`, `currentcolor`, or a `var()` holding any of those.
`scrollbar-width` is `auto`, `thin` or `none` (none hides the bar; the page
still scrolls).  Both are read from `html` or `:root`, then `body`.  Without
them, the track is the page background and the thumb sits halfway between
that and the text colour, so a dark page gets a dark bar with no CSS at all.
`InkPage1.ScrollBar` reaches it from code.

**Touch screens:** drag the page with a finger (or the left mouse button) to
scroll it - on Windows a finger arrives as a mouse press, moves and a release,
and a touch screen has no wheel.  A tap that wobbles a few pixels is still a
click, and a drag that ends on a link does not follow it.  `DragScroll := False`
turns it off.  `ScrollY` reads where the page is.

Try the demo's **HTML help pages** tab, or pass an HTML filename on its command
line. Keep the help folder's relative image and stylesheet paths intact.
Remote content can be supplied through `OnResource`; HTTP transport is not
built in. See [the compatibility report](docs/HELP_COMPATIBILITY.md) for the
exact CSS subset, tested site coverage, and remaining limitations.

## Tables and Markdown

`TInkLabel`, `TInkMemo`, `TInkListBox`, and `TInkPage` expose `TextFormat`:
`itfHTML` (the default) or `itfMarkdown`, declared in `InkMarkdown`.
Changing it reinterprets the existing source; it does not translate the source.
`TInkEdit` remains plain text and `TInkRichEdit` remains an HTML-backed inline
WYSIWYG editor. Rich-editor table editing is not implemented.

The shared renderer supports simple `<table>`, `<tr>`, `<th>` and `<td>`
blocks, including multiple tables mixed with text. Columns are sized from their
content and narrowed to the available width, cell text wraps, headers are bold,
and borders use the current font colour. Links inside cells retain click and
hover support. List boxes now measure variable-height rows, with `ItemHeight`
as their minimum height.

Markdown supports ATX headings, `**bold**`, `*italic*`, `~~strikeout~~`, inline
backticks, triple-backtick code fences, links, simple bullets, and pipe tables.
Raw HTML is escaped. This is a deliberately small subset, not a CommonMark or
GitHub Markdown implementation: nested lists, reference links, images,
underscore emphasis, and table alignment markers are not implemented (alignment
markers are accepted but cells remain left aligned). Code blocks use monospace;
whitespace still follows the existing renderer's handling.

```pascal
uses InkMarkdown;

InkMemo1.TextFormat := itfMarkdown;
InkMemo1.WordWrap := True;
InkMemo1.LoadDocument(
  '# Status' + LineEnding +
  '| Name | State |' + LineEnding +
  '| --- | --- |' + LineEnding +
  '| **Server** | Ready |');
```

Memo `Lines` and list-box `Items` remain independent entries. Use
`TInkMemo.LoadDocument` to replace its contents with one complete multiline
HTML or Markdown entry; splitting a table across entries cannot work. For labels,
assign the complete source to `Caption`. `MarkdownToInk(Source)` is also usable
on its own. `SaveAsHTML` on the viewers converts Markdown entries to HTML;
plain-text export removes formatting and separates table cells and rows.

Limits: no CSS, nested tables, merged cells (`rowspan` / `colspan`), specified
column widths, or table editing tools. Very long unbroken words can overflow a
cell, and very narrow controls may not fit the minimum cell padding. Table blocks
currently use top-left placement. Large documents remain subject to the native
list-box row-height limits; use `TInkPage` for a full document.

The demo's **Tables / Markdown** tab offers sample selection and a live source
preview. Renderer tests run on Linux x86-64 with a display available:

```sh
LAZARUS_DIR=/path/to/lazarus FPC=/path/to/fpc tests/run.sh
```

The test script defaults to GTK3; set `LCL_WIDGETSET` for another built widgetset.
This change has been built and tested with FPC 3.3.1 and Lazarus trunk on GTK3.

## The demo

`demo/lazinkdemo.lpi` — a WYSIWYG editor side by side with the markup it
produces, plus a tab for each control. Everything is built at design time, so
you can open `demo/main.lfm` in the form designer and push it around; nothing is
conjured up at run time. There are deliberately no File/Open/Save actions.

![The WYSIWYG editor tab](images/demo-editor.png)

The **List box** tab is the demo this whole package grew out of — a simulated
log arriving into an owner-drawn listbox, with an editor that floats into place
over the item you click:

![The list box tab](images/demo-listbox.png)

## Installing

Open `lazink.lpk` in Lazarus → Install. The components appear on the
**LazInk** palette tab. For lazbuild-only workflows:

```
lazbuild --add-package-link /path/to/lazink.lpk
```

then add `LazInk` to your project's required packages.

## Limits

LazInk renders a **subset** of HTML, on purpose. It is not a web browser:

* No JavaScript, forms, video or web fonts.
* CSS is a small reader, not CSS conformance - no grid, flexbox, positioning,
  media queries, descendant selectors or inline `style` attributes.
* Tables are simple grids: no row or column spans, no nested tables.
* The Markdown is a small subset, not CommonMark.
* No built-in HTTP downloads - a host supplies remote content through
  `OnResource`.

[docs/HELP_COMPATIBILITY.md](docs/HELP_COMPATIBILITY.md) has the exact list.

## Tests

```sh
LAZARUS_DIR=/path/to/lazarus FPC=/path/to/fpc tests/run.sh
```

runs the renderer and Markdown checks.  Given a file listing HTML pages and an
output folder, it also loads and renders every page at several widths and
checks every image decodes:

```sh
LAZARUS_DIR=... FPC=... tests/run.sh pages.txt results/
python3 tests/check_help_text.py pages.txt results/
```

The second command checks that every visible piece of text in the source pages
survived into the rendered page.

## Where it is going

[ROADMAP.md](ROADMAP.md) is the plan: touch scrolling on Linux, copying and
selecting text, fuller Markdown, a Markdown editor in the demo; then a
renderer of LazInk's own, replacing the JVCL-derived one so the whole
package can move to a no-conditions licence; and a WYSIWYG Markdown editor
after that - with what "done" means for each.

## Credits and origins

### How LazInk started

In August 2021 Tony Stone started a thread on the Lazarus forum,
[Memo Component that supports HTML markup](https://forum.lazarus.freepascal.org/index.php/topic,55971.0.html),
asking for a simple way to decorate text in list boxes and memos with a
little HTML - mostly colour and bold - for showing log files, without
pulling in a heavyweight HTML component.

**wp** suggested taking what was needed from the HTML drawing code in
Project JEDI's JVCL, and helped make it happen: he pulled those routines
out into a standalone unit and wrote an owner-drawn list box example around
it.  Tony built a demo on top of that example - the floating in-place
editor over a list item, saving the list as text or as markup - and that
demo is where the idea for LazInk was born.

Since then LazInk has grown into its own set of Lazarus components: labels,
memos, list boxes, a page viewer, a rich editor, a scrollbar, Markdown and
tables.  AI assistants helped teach the component-writing process and
worked on the design, the code and the debugging.

### Where the code comes from today

The HTML renderer (`inkhtml.pas`, with `inktables.inc`) still contains code
adapted from JVCL, and is under JVCL's licence (MPL 1.1) - see
[License](#license) and [the notices](THIRD_PARTY_NOTICES.md).  Everything
else was written for LazInk.

The plan ([ROADMAP.md](ROADMAP.md), section 4) is to replace that renderer
with one written for LazInk, so the whole package can be released with
essentially no conditions.  That is not a judgement on JVCL or on anyone
who helped - it is a different view of how this particular code should be
shared, and it can only be done with code written for it.  The credit below
stays either way: JVCL and wp's example are what got LazInk off the ground.

### Thanks

* **Project JEDI's JVCL** - the HTML drawing code LazInk grew from
  (`JvHTControls`, `JvJVCLUtils`).  Andrei Prygounkov, Fedor Koshevnikov,
  Igor Pavluk, Serge Korolev, SGB Software, Maciej Kaczkowski, Timo
  Tegtmeier, Andreas Hausladen and the JEDI contributors.
* **wp** - suggested the JVCL route, extracted the routines into a
  standalone unit, and wrote the list box example LazInk started from.
* **jamie** - suggested `TIpHtmlPanel` on the IPro tab, the first thing that
  actually rendered.
* **skalogryz** - pointed out that a Qt5 memo could do it with low-level
  widget access.
* **avra** - the RichMemo wiki examples for mixed-colour text, and the IDE
  shortcuts for finding lost forms.
* **Jurassic Pork** - reported that the original demo opened off-screen on a
  single-monitor machine; the demo centres itself because of that.
* **tetrastes** and **denis.totoliciu** - the *Window / Center lost window*
  discussion that came out of it.
* **Digão Dalpiaz**, whose `TDzHTMLText` label was a source of **ideas** -
  inline images, link hover styling, borders, line spacing and CJK line
  breaking.  No code was taken from it.
* **Lazarus and Free Pascal** - the component framework, the compiler, the
  runtime and the image decoders.

## License

LazInk uses **MIT for its independent component code** and **MPL 1.1 for the
JVCL-derived renderer** (`inkhtml.pas`, with `inktables.inc`). These licenses
apply to different files; the complete package is not MIT-only.

See [LICENSE](LICENSE), the [MIT text](LICENSES/MIT.txt), the
[MPL 1.1 text](LICENSES/MPL-1.1.txt), and the
[renderer modification record](docs/RENDERER_CHANGES.md).

No JVCL package needs installing, but the adapted source still carries its
license. Both licenses permit commercial use. Applications may use LazInk
without putting their independent source under MPL; distribution must still
meet the covered renderer's source-availability and notice requirements.
For this source distribution, the corresponding renderer source accompanies
the license files. Binary distributors must provide their corresponding
covered source or an actual compliant source-download location.
