# Wanted: code blocks a reader can handle - a height of their own, folding, a header with actions

Written 9 October 2026, from Heckers Sketch
(https://github.com/TonyStone31/heckers-sketch), whose assistant window
shows a model's answers in a `TInkMemo` with `AppendBlock(..., itfMarkdown)`.
Answers carry fenced code - often the whole drawing, hundreds of lines -
and today a fence is laid out in full, in the middle of the conversation.
A 300-line answer pushes everything else out of sight, and the only way
past it is to scroll the whole memo.  Each item is a general feature for
any chat, log or document viewer; nothing here should know about Heckers
Sketch.  Not asked for: language highlighting - LazInk's small highlighter
stays as it is, and `OnHighlightCode` is there for a host that wants more.

---

## 1. A code block with a height of its own

### The need

A long fence should take a fixed share of the view and scroll inside
itself, as code blocks do in every chat and forum.  Today its full length
is laid out, so a reply of 400 lines is 400 lines tall.

### How it could work

* `CodeMaxLines: Integer` on `TInkMemo` and `TInkPage` (0 = no limit, as
  now).  A fence taller than that is drawn that many lines high with its
  own vertical scrollbar; the wheel scrolls the block while the pointer is
  over it and the block can still move, then the page.
* Long lines do not wrap inside a code block (code is read by columns);
  the block gets a horizontal scrollbar instead, or `CodeWrap: Boolean`
  chooses.
* Selecting and copying inside a scrolled block works as it does now on a
  page; the block scrolls to follow a drag selection.

## 2. Folding a code block

### The need

Once read, a long block is in the way of everything after it.

### How it could work

* A small fold arrow in the block's header (item 3): folded, the block shows
  its header and its first line, dimmed, with "... 312 lines".
* `CodeFoldOver: Integer` - fences longer than this start folded (0 =
  never).  `FoldCode(Entry, Block, Folded)` and `OnCodeFold` for a host
  that wants to remember.
* Folding never changes `GetEntryText` or what is copied.

## 3. A header on each code block, with the host's own actions

### The need

The "copy this code" button is a start; a host needs its own buttons on a
block - "Use this", "Open in the editor", "Run" - and the reader wants to
see what language a block is before reading it.

### How it could work

* A thin header row on each fence: the fence's language on the left
  (`heck`, `pascal`), the line count, then buttons on the right.
* `CodeActions: TStrings` - captions of buttons every block gets beside
  Copy (empty by default).  `OnCodeAction(Sender, Entry, Block: Integer;
  const Action, Code, Language: string)` fires on a click, with the block's
  plain code.  A host that wants a button only on some languages filters
  in `OnCodeHeader(Sender, const Language: string; Actions: TStrings)`.
* The header is drawn in the theme of the block; buttons follow the hover
  rules of the existing copy button.

## 4. Smaller things

* **Line numbers in a code block** - `CodeLineNumbers: Boolean`, drawn in a
  gutter that is never selected or copied.  A model saying "change line 40"
  of its own answer needs them.
* **Which code block is under the mouse** - `CodeBlockAt(X, Y, out Entry,
  Block)`, for a right-click menu.
* **A block still arriving** - while `ReplaceLast` keeps growing an entry
  that ends inside an unclosed fence, the fence is drawn as code already
  (today the half-written fence shows as text until its closing ``` comes).
  Worth checking - it may already work.

---

## Done - 9 October 2026

Items 2 and 3, on `TInkCustomPage`, so `TInkPage` and `TInkMemo` both
have them (published on both):

* `CodeHeader` (default True): every code block gets a header row, a shade
  apart from the code - the fence's language (or "code") and the line
  count on the left; on the right, right to left: **Copy**, the host's
  `CodeActions`, and for a long block the fold.  The code starts under the
  header; selection and copying of the text never include it.
* **Copy** puts `Block.Code` - the whole code as plain text, folded or not
  - on the clipboard and reads "Copied" for 1.5 s (same width, so nothing
  jumps).
* `CodeFoldLines` (default 0, never): a block with more lines starts
  folded to its first N, a dimmed "..." under them, and its header offers
  **Show all N lines** / **Show less**.  Decided once per block, then the
  reader's; `FoldCode(Block, Folded)` from code; setting `CodeFoldLines`
  again decides every block afresh.
* `CodeActions: TStrings` and `OnCodeAction(Sender, ABlock, AAction,
  ACode, ALanguage)`: the host's buttons; a memo's entry is
  `Block(ABlock).Entry`.  `CodeButtons(ABlock)` gives the buttons and their
  rects for a host that wants its own menu.
* A press on a header button is not a selection; the button under the
  pointer lights, and the pointer is a hand.  A finger's tap reaches the
  buttons through the same path as a link tap.

Not done yet: item 1 (a block scrolling inside a height of its own -
folding covers the chat's need for now), line numbers, `CodeBlockAt`, and
checking a fence still arriving under `ReplaceLast`.  Checks:
`CodeHeaderChecks` in tests/render_tests.pas.
