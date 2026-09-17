<!--
  The page the demo opens on.  It is Markdown, shown by a TInkPage, and it
  is written to use most of what the page can draw - edit it and see.
-->

# Welcome to LazInk

LazInk is a set of Lazarus components that draw **HTML** and **Markdown**
on a plain `TCanvas`: no browser engine, no RichMemo, nothing that differs
from one widgetset to the next. This page is one of them - a `TInkPage` -
reading a Markdown file that sits beside the demo.

![The LazInk palette](../images/palette.png)

> [!TIP]
> Everything on this page can be **selected** with the mouse and copied.
> Right-click for the copy menu, press **Ctrl+F** to find a word, and use
> your mouse's back and forward buttons after following a link.

## What to try

1. **Select** some text - drag, double-click a word, triple-click a
   paragraph, Shift+click to stretch the selection. Ctrl+C copies it, as
   plain text and as HTML.
2. **Right-click** anywhere: *Copy*, *Copy this paragraph*, *Copy link
   address* over a link, *Copy all*, *Select all*.
3. **Find**: Ctrl+F, or the Find button. Enter goes to the next match,
   Shift+Enter to the one before.
4. **Follow a link** - [LazInk's own README](../README.md) is a long
   Markdown document - and come back with the **Back** button, the mouse's
   back button or Alt+Left.
5. **Change the look** with the list above the page. That is
   `StyleSheet`: a program dressing a document that has no CSS of its own.
6. On a **touch screen**, drag the page with a finger and flick it.

## What a page can hold

### Lists

- Bullets, with long items that wrap onto more lines and keep lining up
  under their first word rather than under the bullet
- Nested lists
  - a second level
    - and a third
- [x] Task lists, with their boxes
- [ ] ...including the ones not done yet

### Tables

| Control | What it is | Reads |
|:--------|:-----------|:-----:|
| `TInkPage` | a scrolling document viewer | HTML, Markdown |
| `TInkLabel` | a label | HTML, Markdown |
| `TInkMemo` | a multi-line viewer | HTML, Markdown |
| `TInkListBox` | a list with an in-place editor | HTML, Markdown |
| `TInkEdit` | an edit box colored per character | plain text |
| `TInkRichEdit` | a WYSIWYG editor | its own document |

### Code

Code keeps its spacing, sits on its own background, and a long line is cut
off at the edge rather than wrapped:

```pascal
procedure TForm1.FormCreate(Sender: TObject);
begin
  InkPage1.StyleSheet.Text := 'body { background: #1e2127; color: #c8ccd4 }';
  InkPage1.LoadFromFile('help/index.html');   // HTML or Markdown, by its name
end;
```

LazInk shows code but does not color it - for that, use SynEdit.

### Quotes, rules and the rest

> A quote has a bar down its side.
>
> > And a quote inside a quote has two.

---

*Emphasis*, **strong**, ***both***, ~~struck through~~, `code`, a bare
address such as https://www.lazarus-ide.org, entities like &copy; and
&rarr;, and headings you can link to - [back to the top](#welcome-to-lazink).

## Which control?

| Show... | Written by | Use |
|---|---|---|
| a caption or a status | the program | `TInkLabel` |
| one line being typed, colored | the user | `TInkEdit` |
| lines arriving - a log, a chat | the program, a line at a time | `TInkMemo` |
| a whole document, like this one | an author, ahead of time | `TInkPage` |
| items to pick and rename | the program; the user edits items | `TInkListBox` |
| formatted text with a caret | the user | `TInkRichEdit` |

If you would call `Append`, it is a memo; if you would call `LoadFromFile`,
it is a page.

## The other tabs

- **Markdown editor** - this kind of page, with its source beside it.
- **WYSIWYG editor** - a rich text editor whose document is LazInk markup.
- **Label + Edit**, **Memo** and **List box** - the smaller controls, each
  reading the same markup.
- **Credits** - where LazInk came from.

LazInk lives at <https://github.com/TonyStone31/LazInk>.
