# GitHub-flavored sample

A document that uses what a README on GitHub uses: the GitHub extensions
to CommonMark, raw HTML where Markdown has no syntax, and HTML inside code
blocks that must stay text.  Open it in LazMD and in the demo's page
viewer; both should show it the way GitHub does.  Edit a paragraph, save,
and the rest of the file must keep its bytes.

<p align="center">
  <img src="../images/TInkRichEdit.png" width="360" alt="The rich editor">
  <img src="../images/TInkEdit.png" width="200" alt="The single-line edit">
</p>

<p align="center"><i>Two pictures centered the GitHub way: a <code>&lt;p align="center"&gt;</code> holding <code>&lt;img width=...&gt;</code> tags.</i></p>

## Text

**Bold**, *italic*, ~~struck~~, `code`, and a **[bold link](https://github.com)**
written with the stars outside the brackets, as most people write it.  A
[**bold link**](https://github.com) written the other way round.  Autolinks:
https://www.freepascal.org and www.lazarus-ide.org.  Entities: &copy; &amp;
&lt;tag&gt; &mdash; and a literal \*star\*.  A footnote-style reference
link: [the LazInk README][readme].

[readme]: ../README.md "LazInk"

A line with two trailing spaces  
breaks here.  A backslash at the end\
breaks here too.

## Headings

### Third level

#### Fourth level

Setext heading
--------------

## Lists

- A bullet
- Another, with a nested list:
  - Nested with a dash
  * Nested with a star
    1. Numbered inside
    2. Second
- [x] A finished task
- [ ] An open task

1. First
2. Second
   - A bullet under a number

   A second paragraph in the item.
3. Third

## Quotes and rules

> A quotation, with **bold** and a [link](https://example.com).
>
> > A quote inside a quote.

---

***

___

## Code

Inline `code` and a fenced block with a language:

```pascal
program Hello;
begin
  WriteLn('<b>not bold</b>');  // HTML in code is text
end.
```

HTML in a fenced block stays text, tags and all:

```html
<p align="center">
  <img src="picture.png" width="480" alt="not rendered">
</p>
<details><summary>Not folded</summary>Not hidden.</details>
```

A fence written with tildes, no language:

~~~
<b>still text</b> and a | pipe | that is not a table
~~~

    An indented code block, with <i>tags</i> that stay text.

## Tables

| Left | Center | Right | Default |
| :--- | :----: | ----: | ------- |
| `code` | **bold** | 12 | a \| pipe |
| [link](https://example.com) | ![tiny](../images/TInkEdit.png) | 3.5 | text |

## Raw HTML

An image on a line of its own, no paragraph around it:

<img src="../images/TInkLabel.png" width="300" alt="A label">

A link around a picture, the GitHub badge pattern:

<a href="https://github.com/TonyStone31/LazInk"><img src="../images/TInkMemo.png" width="240" alt="Badge"></a>

A folding section:

<details>
<summary>Click to open</summary>

Hidden until opened on GitHub.  Shown as text in the editor.

</details>

An HTML table, which Markdown tables cannot express (a cell spanning two columns):

<table>
  <tr><th>Name</th><th colspan="2">Size</th></tr>
  <tr><td>Robot</td><td>900</td><td>653</td></tr>
</table>

Inline HTML in a paragraph: <kbd>Ctrl</kbd>+<kbd>S</kbd> saves, H<sub>2</sub>O,
x<sup>2</sup>, <mark>marked</mark>, <b>bold</b> and <i>italic</i> with the
old tags, a <br> break in the middle.

<!-- An HTML comment: kept in the file, never shown. -->

## Pictures

A Markdown image with a title: ![The list box](../images/TInkListBox.png "TInkListBox").

A WebP picture: ![WebP drawing](../tests/fixtures/webp/drawing-lossy.webp)
and an animated one: ![Animated WebP](../tests/fixtures/webp/animation.webp).

An image with a reference destination: ![The page viewer][page]

[page]: ../images/TInkPage.png

## Escapes and edge cases

\# not a heading.  1\. not a list.  \- not a bullet.  A line that is only
dashes but belongs to the paragraph above
---
is a setext heading of that paragraph on GitHub.

Text right after a fence:
```
code
```
More text.

The end.
