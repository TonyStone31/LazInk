# Wanted: what a chat window needs - a hidden entry, whole messages in a memo, and a growing last one

Written 8 October 2026, from Heckers Sketch
(https://github.com/TonyStone31/heckers-sketch), which has started an
assistant window: a conversation about the drawing, whose answers are text
and code (the drawing's own language, Heck), and a settings box with a
provider, a model and an API key.  It is built from LazInk and BGRA
controls only, like every other dialog there.  Nothing is connected yet,
so none of this is urgent; it is what the window will want when it is.
Each item is a general feature for any chat or log viewer; nothing here
should know about Heckers Sketch.

What is already there and is used as it is: `TInkMemo` with `Append`
(following the end while the view is there), `OnLinkClick`, copying a
block, `TextFormat`; `TInkCodeMemo` for the question, with `TextHint`.

---

## 1. A hidden entry in TInkEdit - `PasswordChar`

### The need

An API key or a password typed or pasted into a form must not show.  The
stock `TEdit.PasswordChar` does it; `TInkEdit` has nothing, so the
settings box shows no field at all - only "Paste a key" and "a key ending
...7f3a".  That works, but a form that needs a typed secret has no way.

### How it could work

* `property PasswordChar: Char`, default `#0` (shown as typed).  When set,
  every character is drawn as that one - or a bullet when it is `'*'`, the
  way most toolkits draw it now.
* While hidden: Copy and Cut do nothing (and are gray in the menu), the
  text is never put on the clipboard or in the selection, and a word jump
  (Ctrl+arrow) goes to the start or end, since the words are not shown.
* Undo still works.  `Text` is the real text.

## 2. A whole message as one entry in TInkMemo

### The need

A chat answer is several paragraphs, a list, and a fenced code block -
Markdown, as every assistant writes it.  `TInkMemo`'s entries are a line
each, of inline markup; an answer split over many entries loses its lists
and code blocks, and cannot be picked or copied as one thing.  `TInkPage`
lays all that out but is one document, not a stream that grows.

### How it could work

* `AppendBlock(const Text: string; Format: TInkTextFormat)`: one entry laid
  out like a fragment of a page - paragraphs, lists, block quotes, fenced
  code with `OnHighlightCode`, tables if cheap - and still one entry: one
  `Count`, one copy, one `GetPlainText`.
* Its own background and margin, so the program can set a question apart
  from an answer: `BlockColor` and an indent per entry, or a class name
  the small stylesheet can style.
* A fenced code block gets the same "copy this" the page viewer's code
  blocks would get, copying the code alone, with no line numbers or
  markup.

## 3. A last entry that grows - for an answer that arrives a word at a time

### The need

Answers come in pieces over seconds.  Shown as they come, the last entry is
replaced again and again; re-laying out the whole memo each time would make
a long conversation crawl.

### How it could work

* `ReplaceLast(const Text: string)` (or `AppendToLast`), which lays out
  only that entry and keeps the rest.
* Follow the end only when the reader is already there, as `Append` does
  now: someone scrolled up to read an older answer must not be pulled down
  by the one arriving.
* While an entry is growing, a selection elsewhere in the memo stays put.

## 4. Smaller things

* **Which entry is under the mouse** - `EntryAt(X, Y): Integer`, -1 for
  none - so a program can offer "Copy this answer" or "Use this code" on a
  right click.
* **A plain-text-only entry**, for text a stranger or a model wrote that must
  never be read as markup: `AppendPlain(const Text: string)`, drawn as is,
  `<b>` and all.  (The program escapes today; one call is harder to get
  wrong.)
* **TInkCodeMemo that grows with its text** - `AutoHeight` between
  `MinLines` and `MaxLines`, then a scrollbar - so a question box starts as
  one line and opens up as it is written.

---

## Done - 8 October 2026

All of it, as `TInkEdit.PasswordChar`, `TInkMemo.AppendBlock` /
`AppendPlain` / `ReplaceLast` / `EntryAt` / `GetEntryText`, and
`TInkCodeMemo.AutoHeight` with `MinLines` / `MaxLines`.

1. **PasswordChar** - default `#0`; when set, every character draws as
   that one, with `'*'` drawn as a bullet.  Copy and Cut do nothing while
   hidden (gray in the menu), `OnGetCharAttrs` is not asked (a colorizer
   must not read the secret), undo works, `Text` is the real text.  On the
   word-jump point: `TInkEdit` has no word navigation at all - Ctrl+arrow
   is a plain arrow and a double click selects everything - so no word
   boundary shows through.

2. **AppendBlock(Text, Format, Color, Indent)** - one entry, laid out by
   the same page engine `TInkPage` uses: paragraphs, lists, quotes,
   tables, fenced code through `OnHighlightCode` with the viewer's "copy
   this code" button.  One `Count`, one `GetPlainText` (paragraphs joined
   by line breaks), one entry in the copy menu - "Copy this message".
   `Color` draws a continuous band behind the whole entry (the gaps
   between its paragraphs are filled), `Indent` sets it in from the left.

3. **ReplaceLast(Text)** - replaces only the last entry's blocks and lays
   out from there; everything above is untouched, so a selection above
   stays put.  The view follows only when it was already at the end.
   Replacing with the same text is a no-op.

4. **Smaller things** - `EntryAt(X, Y)` (-1 for none); `AppendPlain`
   (shown exactly as written, `<b>` and all); `AutoHeight` on
   `TInkCodeMemo`, growing between `MinLines` (default 1) and `MaxLines`
   (default 8) of the control's font as text is typed, set, re-wrapped by
   a resize, or re-sized by a font change - then the scrollbar takes over.

Entries written through `Lines` from outside stay ordinary lines; the
entry extras ride on the `Append*` calls.  Regression tests cover the
masking, the clipboard refusal, entries, bands, menu, `ReplaceLast`
selection stability, `EntryAt`, and the growing box.
