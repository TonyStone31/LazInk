# TInkEdit fires OnChange while its form is still loading

Found 5 October 2026, moving Heckers Sketch's 42 text boxes from `TEdit` to
`TInkEdit`.

## What happens

A form's `.lfm` that sets a `TInkEdit`'s `OnChange` before its `Text` -
which is how the stock `TEdit` entries came out of the IDE - crashes the
form as it loads:

    EReadError: Error reading edAngle.Text: Access violation

`SetTextValue` ends in `Changed`, which calls `OnChange`; the handler runs
while the form is half read and touches a control that does not exist yet.

## What the stock controls do

`TEdit`, `TMemo` and the other LCL edits do not fire `OnChange` while the
component is loading (`csLoading in ComponentState`): reading a stored
`Text` is not a change.  They do fire it when code sets `Text` later.

## The fix that would match

In `TInkEdit.Changed` (and `TInkCodeMemo`/`TInkRichEdit`, if they share the
path): skip `OnChange` while `csLoading in ComponentState`, and skip
`ClearUndo`'s work too while loading if it matters.  Nothing else changes:
code that sets `Text` after the form is up still gets its `OnChange`, as
with `TEdit`.

A test: stream a form (or `ReadComponentRes` a small `.lfm`) with
`OnChange` before `Text`, and check the handler did not run.

## What Heckers Sketch does meanwhile

Its `.lfm` files list `OnChange` after `Text` in every `TInkEdit`, which is
also the order the IDE writes for the class (`Text` is published first).  A
form saved from the IDE keeps that order; an older form converted by hand
might not.

## Fixed - 5 October 2026

As the note prescribed: `TInkEdit.Changed` and `TInkRichEdit.Changed` (and
so `TInkCodeMemo`, which rides the latter) skip `OnChange` while
`csLoading` is in `ComponentState` - reading a stored `Text` is not a
change.  Code setting `Text` after the form is up fires it as before,
which the test holds: `EditAndPlainChecks` streams a form with `OnChange`
written before `Text` through `TReader` and checks the handler stayed
silent during the load and fired on the first real change after it.
