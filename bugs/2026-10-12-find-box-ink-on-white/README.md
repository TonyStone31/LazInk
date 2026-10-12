# The find box writes white on white under a dark page

Found 12 October 2026 in Heckers Sketch's help viewer on Windows 11.
Tony: "I am unable to type into the find box.  I think the main form is
capturing the keys or something."  The keys arrived fine all along -
driving the window showed the match counter ticking to 1/1 and the page
scrolling to the hit - but nothing the typing drew could be seen.

## Why

`ShowFindBar` dresses the box with `FFindEdit.Font.Assign(Font)`, taking
the page's whole font - including its color, which is mixed for the
page's background.  A dark page uses near-white ink.  The box itself
stays `clWindow`, which is white on stock Windows and most Linux themes,
so the typed text lands near-white on white.  `TInkEdit` draws its caret
with `Font.Color` too, so the caret is just as invisible and the box
looks dead rather than miscolored.  A light page never shows it, which
is why the find bar survived every light-theme look at it.

## The fix

The box keeps the page's font face and size so the bar matches the
document, but its ink is pinned back to `clWindowText` right after the
assign.  That is the system pairing for a `clWindow` box, so it stays
readable whatever the page's palette - and on a dark system theme, where
`clWindow` itself goes dark, the pairing still holds.
