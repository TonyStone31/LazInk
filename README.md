# LazInk

**Formatted text for Lazarus, drawn entirely on a `TCanvas`.** Labels,
memos, list boxes, a document viewer and a WYSIWYG Markdown editor that
read **HTML or Markdown** and look the same on every widgetset - no
RichMemo, no browser engine, no dependencies beyond the LCL, and **0BSD
licensed**, so you can use it anywhere with no strings at all.

![A help site rendered by TInkPage](images/demo-documents.png)

## Why

* **A real page viewer in one line.** `InkPage1.LoadFromFile('help/index.html')`
  renders a whole help site: headings, lists, tables, highlighted code,
  PNG, animated GIF and **WebP** (decoded in Pascal - nothing to install),
  links with Back and Forward, find-in-page, selection and copy, touch
  scrolling, and a CSS reader with light and dark `prefers-color-scheme`.
* **Markdown is native.** Every display control takes
  `TextFormat := itfMarkdown`; the page loads whole `.md` documents,
  read the way GitHub reads them.
* **A WYSIWYG Markdown editor.** `TInkRichEdit` edits headings, nested
  lists, quotes, tables and fenced code as the thing itself, and reads
  and writes Markdown whole. Nothing else for Lazarus does this.
* **Selection like a browser, everywhere.** Drag, double-click a word,
  Shift+arrows, a right-click copy menu, Ctrl+C as text and HTML - in the
  page, the memo, the list box, even the label.
* **Chat-ready.** `TInkMemo.AppendBlock` appends a whole message - lists,
  tables, highlighted code - as one entry with its own band color, and
  `ReplaceLast` grows the answer in place as it streams in.
* **Held against a real browser.** A side-by-side harness renders every
  construct next to Chromium; line heights match it exactly, and the
  comparison page is part of the repository.

## Sixty seconds

```pascal
uses InkLabel, InkMemo, InkPage, InkMarkdown;

InkLabel1.Caption := 'Status: <b><font color="#00AA00">connected</font></b>';

InkMemo1.TextFormat := itfMarkdown;
InkMemo1.Append('**12:04** build finished, `0 errors`');

InkPage1.StyleSheet.Text :=
  'body { background: #23262c; color: #b8bcc4 } h2 { color: #4ab3e8 }';
InkPage1.LoadMarkdown(ReleaseNotes);
```

![The WYSIWYG Markdown editor](images/demo-editor.png)

## The controls

| Control | One line |
|---|---|
| `TInkPage` | scrolling viewer for complete HTML/Markdown documents |
| `TInkMemo` | a growing stream of formatted lines - a log, a chat |
| `TInkLabel` | a caption that understands inline markup |
| `TInkListBox` | formatted items with an in-place editor |
| `TInkRichEdit` | the WYSIWYG editor, Markdown in and out |
| `TInkEdit` | a one-line edit, every character colored by your event |
| `TInkCodeMemo` | a plain multi-line editor that can grow with its text |

## Install

Open `lazink.lpk` with **Package → Open Package File**, then
**Compile → Use → Install**. The controls land on the **LazInk** palette
tab. The demo is `demo/lazinkdemo.lpi` - a tab for every control, built
in the form designer.

> **Status: 1.0.0.0.** Usable, and the API may still change. Built and
> tested with FPC 3.3.1 and Lazarus trunk on GTK3/Linux; nothing in it is
> widgetset-specific, but the other widgetsets have not been run yet -
> reports welcome.

## Learn more

* **[The guide](docs/GUIDE.md)** - every control, feature and limit, in detail.
* **[Writing pages](docs/HTML_SUPPORT.md)** - every tag and CSS property it reads, with examples.
* **[The roadmap](ROADMAP.md)** - what is open; **[the history](docs/HISTORY.md)** - how it was built, and why.

## License

**0BSD** - the BSD Zero Clause License. See [LICENSE](LICENSE).
