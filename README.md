# LazInk

Lightweight HTML-formatted text controls for Lazarus, drawn entirely with
`TCanvas`. Because no native text widget is involved, every control renders
identically on **every LCL widgetset** — win32, gtk2, **gtk3**, qt5/6, cocoa.
No RichMemo, no widgetset-specific backends, no surprises.

## The controls

| Control | What it is |
|---|---|
| `TInkLabel` | A label whose Caption understands inline markup. AutoSize aware, transparent by default, clickable `<a href=...>` links via `OnLinkClick`. |
| `TInkEdit` | A single-line edit box where **every character can have its own color and style**, supplied by the `OnGetCharAttrs` event. The text stays plain — great for password-strength coloring, highlighting digits/symbols, flagging duplicates. Full editing: caret, selection, clipboard, MaxLength, ReadOnly, alignment. |
| `TInkMemo` | A scrollable multi-line viewer; each line is a paragraph of markup, lines can differ in height. For logs, transcripts, formatted help. Links fire `OnLinkClick`. |
| `TInkListBox` | An HTML-rendering listbox with an optional in-place edit popup for copying/editing an item's plain text. |

## Supported markup

The renderer (derived from JVCL's HTML drawing utilities) understands:

```
<b> <i> <u> <s>                     bold / italic / underline / strikeout
<font color="#RRGGBB" bgcolor= size=>   also clRed-style and named colors
<sup> <sub>                         superscript / subscript
<br> <hr>                           line break / rule
<center> <right> <ind="20">         alignment and indent
<a href="...">text</a>              links (OnLinkClick)
&amp; &lt; &gt; &quot; &reg; &copy; &trade;
```

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

## Installing

Open `lazink.lpk` in Lazarus → Install. The components appear on the
**LazInk** palette tab. For lazbuild-only workflows:

```
lazbuild --add-package-link /path/to/lazink.lpk
```

then add `LazInk` to your project's required packages.

## Roadmap

- `TInkHyperlinkLabel` — a dedicated one-liner link label (TInkLabel already
  fires `OnLinkClick` for `<a href=...>` spans; this would be the convenience
  wrapper).
- A simple WYSIWYG editor control that toggles between raw markup and the
  rendered text.
- Word wrap in `TInkMemo`/`TInkLabel` (the renderer currently breaks lines
  only on `<br>`).

## License

Component code: MIT. The renderer unit `inkhtml.pas` derives from the
JVCL project's `JvHtControls` (MPL 1.1) — see that unit's header.
