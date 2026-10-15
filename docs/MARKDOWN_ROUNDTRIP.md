# Markdown editing and round trips

LazMD edits the rendered page with `TInkRichEdit` and the source with
`TInkCodeMemo`. The Rendered and Raw tabs switch between them; Side by side
shows both, and an edit in one updates the other.

Turning the whole edited page back into Markdown is not good enough: the
renderer cannot know whether the author wrote `*` or `_`, a setext or an ATX
heading, or a reference link. So the editor keeps the source and writes back
only what was edited.

## The rules

- Opening a document, switching tabs and saving without edits keeps its
  bytes.
- An edit leaves the rest of the source alone.
- Undoing every edit gives back the original source, after a save too.
- UTF-8, a UTF-8 BOM, CRLF, LF, mixed line endings and a missing final
  newline all survive.

Markdown parsing stays in `InkMarkdown`; painting and the caret stay in the
rich editor.

## A small document to edit

Select a word in this paragraph and try **bold**, *italic*, ~~strikethrough~~,
`inline code`, and a [link](https://example.com). Check the toolbar state,
undo, redo, save, and then look at Raw. Change one word and check that the
blocks after it keep their spelling.

A setext heading
---------------

This paragraph uses __alternate bold markers__ and &amp; an entity.

* A bullet written with an asterisk
* Another item
  * A nested item

1. First step
2. Second step

> A quotation should stay a quotation when its words change.

| Feature | Center | Right |
| :--- | :---: | ---: |
| **Tables** | short | 12 |
| Literal pipe: a\|b | wider content | 345 |

~~~pascal
begin
  WriteLn('Keep the fence style when editing elsewhere.');
end.
~~~

<!-- This comment must survive edits to the surrounding paragraphs. -->

A [reference link][example] keeps its definition when other text changes.

[example]: https://example.com "Reference title"

- [x] A completed task
- [ ] A remaining task

![Image alternative text](../images/TInkRichEdit.png "Rich editor")

## How it works

`MarkdownBlocks` returns the top-level HTML blocks with their byte ranges in
the source. The rich editor tags every character with the block it came
from, and undo snapshots keep those tags. `AsMarkdown` copies unchanged
blocks and the gaps between them byte for byte. For a changed block it first
tries to splice the edit into the original text, and keeps that if it parses
to the same HTML; otherwise it writes the block out fresh.

Written-out Markdown escapes only what would otherwise read as markup: `*`,
`` ` ``, brackets and backslashes always; `_` and `~` only where they could
pair up; `<` and `&` only before a tag or an entity; a leading `-`, `+`,
`#`, `>` or `1.` only at the start of a line. Link and image destinations
get angle brackets only when they hold a space or unbalanced parentheses.

Tables keep column alignment apart from paragraph alignment. A literal pipe
in a cell is a different character from a column divider, so it can be
selected, typed and saved without adding a column. GFM resolves `\|` before
inline parsing, code spans included, so code in a cell gets its pipes
escaped again on the way out.

Images are one character each, carrying source, alternative text and title.
`LoadMarkdown` takes a base URI for relative files, and `OnImageNeeded` lets
the host supply pictures itself. Local pictures load by default and shrink
to the editor width; a missing one shows its alternative text and keeps its
Markdown. Animation is not done here.

Task checkboxes use the existing checkbox painter, toggle on a click and
save as `[ ]` or `[x]`. Link titles and hard line breaks survive too. Code
spans and fences pick a delimiter longer than any backtick run inside them,
and emphasis leaves out leading and trailing spaces.

## Go to source

The Rendered context menu has Go to source, for a selection or the caret.
A right-click outside the selection moves the caret there; a right-click on
an image selects the image. Raw opens, or takes the focus in Side by side,
with the matching source selected. An image selects its whole Markdown
expression, reference images included. A table cell maps to its text, empty
cells too.

`TInkRichEdit.OnGoToSource` lets the host offer the menu item;
`MarkdownSourceRange` returns byte offsets into the current `AsMarkdown`.
It finds the range by trying candidates and checking each one renders the
same, so a word repeated in a link destination is not taken for its label.
The search gives up after a fixed number of tries, and LazMD then says it
could not find the spot instead of selecting the wrong text. A source map
from the parser would be faster and exact; it is not written yet.

## Inserting pictures

The Image button and Edit > Image open a dialog with a file picker, a
preview, alternative text and an optional title. Selected text becomes the
alternative text. The dialog shows the path exactly as it will be written.
`TInkRichEdit.InsertImage` inserts it as one undo step; it does nothing
inside code or source blocks.

A local picture can stay where it is or be copied into a folder. Relative
paths start from the saved document's folder; an absolute file URI is the
other choice. The copy is made only on Insert, leaves the original, and
picks a new name if the file exists. A relative folder such as `assets` or
`../images` is taken beside the document; absolute folders work too. The
choices are remembered while the window is open.

An unsaved document gets absolute file URIs; relative paths and copying
work once it is saved. Spaces and other special characters are encoded in
local URLs. Undo does not delete a copied picture. Web addresses can be
inserted but are not downloaded.

## What is not done

- A block the editor cannot show as rich text appears in Rendered as
  editable Markdown source, so nothing is lost. Nested quotes and
  containers, ordered lists that start at another number and some inline
  HTML still need proper rich forms. Keep each block's original source
  when adding them.
- A changed block can still come out normalized when the edit cannot be
  spliced into the original.
- The parser is not CommonMark-complete: emphasis, raw HTML, reference
  definitions and nested blocks need work against the specification.
  GitHub also renders and filters beyond the GFM specification.
- Tables: no row and column commands or alignment buttons yet; the drag
  grid only makes new tables.
- Images: no properties dialog, no pasting a picture from the clipboard,
  no size. Markdown image syntax has no width or height, and GitHub's HTML
  attributes are not portable, so size needs a decision first.

## Checks when changing the editor

1. Run the LazInk tests (`tests/run.sh`) and LazMD's (`tests/run.sh`).
2. Open this file in LazMD and compare Rendered and Raw.
3. Edit text and formatting, the first character of a paragraph included.
4. Edit table cells, a literal pipe included; use Tab, Shift+Tab and Enter.
5. Save, switch tabs, undo, save again, and diff the source.
6. Repeat with CRLF, a BOM, no final newline, comments and references.
7. Try deleting across blocks, joining paragraphs, paste, and Clear
   formatting.

## Specification checks

`tests/markdown_roundtrip_tests.pas` checks rendered objects, edits, undo,
tables, tasks, images, hard breaks and unchanged source; `tests/run.sh` runs
it after the renderer tests. Set `MARKDOWN_SPEC` to a CommonMark
`spec.json` and every example in it is loaded and saved again too; all 652
from CommonMark 0.31.2 come back byte for byte.

`tests/check_markdown_spec.py SPEC_FILE --report REPORT_FILE` compares the
converter's HTML with the specification's, for `spec.json` or `spec.txt`.
Set `FPC` to the compiler. Python is needed for this check only; the
components stay plain Pascal. The specification files are not kept here;
download them from their publishers.

On 15 October 2026 the converter matched 511 of 652 CommonMark 0.31.2
examples and 525 of 672 cmark-gfm examples. The comparison ignores heading
IDs, void-tag spelling, attribute order, entity spelling and whitespace
between tags. The most differences are in emphasis, links, autolinks, raw
HTML and reference definitions; for GFM also task-list HTML, table ends and
disallowed HTML.

Parser conformance, how the page looks and source preservation are three
separate checks; passing one says nothing about the other two. References:
[CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) and the
[GFM specification](https://github.github.com/gfm/).
