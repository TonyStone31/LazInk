# Navigating straight to a .webp shows the file as text

`TInkCustomPage.Navigate` makes a one-picture page when the URL it is given
is a picture, which is what a browser does:

```pascal
Ext := LowerCase(ExtractFileExt(PageURL));
if (Ext='.png') or (Ext='.gif') or (Ext='.jpg') or (Ext='.jpeg') or
  (Ext='.bmp') or (Ext='.ico') then
  { a picture on its own is a page with just the picture, as in a browser }
  NewSource := '<html>...<img src="..."></html>'
else
  NewSource := ReadText(PageURL);
```

`.webp` is not in the list, so `LoadFromURL('shots/tool-push.webp')` falls to
`ReadText` and the window fills with the file read as text - a screen of
binary gibberish.  LazInk decodes WebP perfectly well as an `<img>`; it is
only this list that has not heard about it.

Found in Heckers Sketch: every animation in its manual is a link to itself,
so clicking any one of them did this once the manual went from GIF to WebP.

**The fix** is the extension list - add `.webp`, and `.avif`/`.tiff`/`.webp`
are worth a thought at the same time if FPC decodes them for you.  A list of
formats the reader supports, written out by hand in one place, is the kind of
thing that goes stale the day a new decoder lands: better still would be
asking whatever decodes pictures whether it knows this extension.

Heckers Sketch no longer depends on it - its picture window builds the
one-picture page itself now, which is the honest way round: the window knows
it was asked for a picture, so it says so rather than leaving the renderer to
guess from the name.  Worth fixing here anyway for the next caller.
