{ A dry run of the renderer prototype against the one it would replace.

  Draws the same markup with InkHtml (the MPL engine the package uses) and
  with InkRenderNext (the 0BSD prototype), side by side into one PNG, and
  prints their extents, line counts and hit test answers.  Then times both
  on a long document: first layout, thirty paints, and a re-layout at a new
  width.

  It is a tool, not a test: nothing here is asserted, and tests/run.sh does
  not build it.  What it found is written up in docs/RENDERER_SPEC.md
  section 10.  Build it against the working tree:

    fpc -Fu. -Fu$LAZARUS/lcl/units/x86_64-linux \
        -Fu$LAZARUS/lcl/units/x86_64-linux/gtk3 \
        -Fu$LAZARUS/components/lazutils/lib/x86_64-linux \
        -Fu$LAZARUS/components/freetype/lib/x86_64-linux \
        tools/renderer_dryrun.pas
    ./renderer_dryrun compare.png

  SPDX-License-Identifier: MIT }
program renderer_dryrun;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Graphics, Types, Math, DateUtils,
  InkHtml, InkRenderNext;
const
  W = 430;
var
  Sheet: TBitmap; PNG: TPortableNetworkGraphic;
  O: THTMLOptions; N: TInkNextOptions; R: TInkNextRenderer; L: TInkNextLayout;
  Samples, Names: array of string;
  I, Y, K: Integer; Wrapped: string; Sz, NSz: TSize;
  Hit: THTMLHitInfo; NHit: TInkNextHit; Tile: TBitmap; Run: TInkNextRun;
  LinkX, LinkY: Integer;

  procedure Sample(const AName, AMarkup: string);
  begin
    SetLength(Samples, Length(Samples)+1); Samples[High(Samples)] := AMarkup;
    SetLength(Names, Length(Names)+1); Names[High(Names)] := AName;
  end;

  { how long each engine takes on a document of some size }
  procedure Bench;
  const BWidth = 700;
  var Doc, BWrapped: string; I, Reps: Integer; T: TDateTime; BW: TBitmap;
    BO: THTMLOptions; BN: TInkNextOptions; BR: TInkNextRenderer; BL: TInkNextLayout;
    BSz: TSize;
  begin
    Doc := '';
    for I := 1 to 400 do
      Doc := Doc + '<b>Heading ' + IntToStr(I) + '</b> some ordinary words in a paragraph, ' +
        'with <i>emphasis</i>, a <a href="p' + IntToStr(I) + '.html">link</a> and ' +
        '<font color="#336699">color</font> before the next break.<br>';
    WriteLn('document: ', Length(Doc) div 1024, ' KB of markup');
    BW := TBitmap.Create; BW.SetSize(BWidth, 400);
    BW.Canvas.Font.Name := 'DejaVu Sans'; BW.Canvas.Font.Size := 10;
    BO := DefaultHTMLOptions;
    BR := TInkNextRenderer.Create;
    FillChar(BN, SizeOf(BN), 0);
    BN.BaseFont := BW.Canvas.Font; BN.Width := BWidth; BN.Scale := 100; BN.HoverIndex := -1;
    BN.LinkColor := clBlue; BN.LinkBackColor := clNone; BN.HoverColor := clRed;
    BN.HoverBackColor := clNone; BN.Borders := Rect(0, 0, 0, 0);
    T := Now;
    BWrapped := HTMLWordWrap(BW.Canvas, Doc, BWidth, BO.SuperSubScriptRatio, BO.Scale);
    BSz := HTMLTextExtentOpt(BW.Canvas, Rect(0, 0, BWidth, 0), [], BWrapped, BO);
    WriteLn(Format('old: wrap + measure            %5.0f ms  (height %d)',
      [MilliSecondsBetween(Now, T) * 1.0, BSz.cy]));
    T := Now;
    BR.Tokenize(Doc); BL := BR.Layout(BW.Canvas, BN);
    WriteLn(Format('new: tokenize + layout         %5.0f ms  (height %d, %d runs)',
      [MilliSecondsBetween(Now, T) * 1.0, BL.Size.cy, BL.RunCount]));
    Reps := 30;
    T := Now;
    for I := 1 to Reps do
      HTMLDrawOpt(BW.Canvas, Rect(0, -I*20, BWidth, 400 - I*20), [], BWrapped, BO);
    WriteLn(Format('old: %d paints                 %5.0f ms',
      [Reps, MilliSecondsBetween(Now, T) * 1.0]));
    T := Now;
    for I := 1 to Reps do BR.Paint(BW.Canvas, Rect(0, 0, BWidth, 400), BN);
    WriteLn(Format('new: %d paints, kept layout    %5.0f ms',
      [Reps, MilliSecondsBetween(Now, T) * 1.0]));
    T := Now;
    for I := 1 to Reps do
    begin
      { moving the text by its Borders re-lays it out, which is finding 6 }
      BN.Borders := Rect(0, -I*20, 0, 0);
      BR.Paint(BW.Canvas, Rect(0, 0, BWidth, 400), BN);
    end;
    WriteLn(Format('new: %d paints, moving Borders %5.0f ms  (each one re-lays out)',
      [Reps, MilliSecondsBetween(Now, T) * 1.0]));
    BN.Borders := Rect(0, 0, 0, 0);
    T := Now;
    BWrapped := HTMLWordWrap(BW.Canvas, Doc, BWidth - 120, BO.SuperSubScriptRatio, BO.Scale);
    BSz := HTMLTextExtentOpt(BW.Canvas, Rect(0, 0, BWidth - 120, 0), [], BWrapped, BO);
    WriteLn(Format('old: re-wrap at a new width    %5.0f ms', [MilliSecondsBetween(Now, T) * 1.0]));
    BN.Width := BWidth - 120;
    T := Now;
    BL := BR.Layout(BW.Canvas, BN);
    WriteLn(Format('new: re-layout at a new width  %5.0f ms', [MilliSecondsBetween(Now, T) * 1.0]));
    BR.Free; BW.Free;
  end;

  procedure SetFont(C: TCanvas);
  begin
    C.Font.Name := 'DejaVu Sans'; C.Font.Size := 10;
    C.Font.Style := []; C.Font.Color := clBlack;
  end;
begin
  Application.Initialize;
  Sample('inline + wrap',
    '<b>Bold</b>, <i>italic</i>, <u>under</u>, <s>struck</s>, ' +
    '<font color="#d73a49" size="13">colored and bigger</font>, ' +
    'H<sub>2</sub>O and x<sup>2</sup>, <a href="one.html">a link</a>, then a long ' +
    'sentence that has to wrap onto another line or two so the widths can be compared.');
  Sample('alignment', 'left as usual<br><center>centered here<br><right>and right<br><left>back');
  Sample('paragraph + rule', 'first paragraph<p>second one<br><hr>after the rule');
  Sample('entities', 'a &amp; b, 5 &lt; 6, x &gt; y, caf&eacute;, and &amp;lt; stays text');
  Sample('long word', 'a supercalifragilisticexpialidociousandthensome word in a narrow column');
  Sample('CJK', 'CJK wrapping: ' + #$E4#$B8#$AD#$E6#$96#$87#$E6#$B8#$AC#$E8#$A9#$A6 +
    #$E4#$B8#$AD#$E6#$96#$87#$E6#$B8#$AC#$E8#$A9#$A6 + #$E4#$B8#$AD#$E6#$96#$87#$E6#$B8#$AC#$E8#$A9#$A6 +
    #$E4#$B8#$AD#$E6#$96#$87#$E6#$B8#$AC#$E8#$A9#$A6 + #$E4#$B8#$AD#$E6#$96#$87#$E6#$B8#$AC#$E8#$A9#$A6);
  Sample('plain table',
    '<table><tr><td>one</td><td>two</td></tr><tr><td>three</td><td>a longer cell</td></tr></table>');
  Sample('styled table (cards)',
    '<table width="100%" layout="fixed" cellspacing="8" cellpadding="6 8 6 8" ' +
    'cellbg="#eef2ff" bordercolor="#c7d2fe" radius="8">' +
    '<tr><td><b>Card one</b><br>some words</td><td bgcolor="#fff7ed"><b>Card two</b><br>more</td></tr></table>');

  Sheet := TBitmap.Create;
  Sheet.SetSize(2*W+40, 1500);
  Sheet.Canvas.Brush.Color := clWhite; Sheet.Canvas.Brush.Style := bsSolid;
  Sheet.Canvas.FillRect(0, 0, Sheet.Width, Sheet.Height);
  SetFont(Sheet.Canvas);

  O := DefaultHTMLOptions; O.LinkColor := clBlue; O.LinkUnderline := True;
  R := TInkNextRenderer.Create;
  FillChar(N, SizeOf(N), 0);
  N.BaseFont := Sheet.Canvas.Font; N.Width := W; N.Scale := 100;
  N.Borders := Rect(0, 0, 0, 0);
  N.LinkColor := clBlue; N.LinkUnderline := True; N.HoverIndex := -1;
  N.LinkBackColor := clNone; N.HoverColor := clRed; N.HoverBackColor := clNone;

  Y := 10;
  for I := 0 to High(Samples) do
  begin
    Sheet.Canvas.Font.Style := [fsBold]; Sheet.Canvas.Font.Color := clGray;
    Sheet.Canvas.TextOut(10, Y, Names[I] + '    old | new');
    SetFont(Sheet.Canvas);
    Inc(Y, 18);

    SetFont(Sheet.Canvas);
    Wrapped := HTMLWordWrap(Sheet.Canvas, Samples[I], W, O.SuperSubScriptRatio, O.Scale);
    Sz := HTMLTextExtentOpt(Sheet.Canvas, Rect(0, 0, W, 0), [], Wrapped, O);
    HTMLDrawOpt(Sheet.Canvas, Rect(10, Y, 10+W, Y+Sz.cy), [], Wrapped, O);

    R.Tokenize(Samples[I]);
    Tile := TBitmap.Create;
    try
      Tile.SetSize(W, 2000);
      Tile.Canvas.Brush.Color := clWhite; Tile.Canvas.FillRect(0, 0, W, 2000);
      SetFont(Tile.Canvas);
      L := R.Layout(Tile.Canvas, N);
      NSz := L.Size;
      R.Paint(Tile.Canvas, Rect(0, 0, W, Max(1, NSz.cy)), N);
      Sheet.Canvas.CopyRect(Rect(W+30, Y, 2*W+30, Y+Max(1, Min(NSz.cy, 2000))),
        Tile.Canvas, Rect(0, 0, W, Max(1, Min(NSz.cy, 2000))));
    finally Tile.Free end;

    WriteLn(Format('%-24s old %4d x %3d | new %4d x %3d   lines %2d runs %3d',
      [Names[I], Sz.cx, Sz.cy, NSz.cx, NSz.cy, L.LineCount, L.RunCount]));
    Inc(Y, Max(Sz.cy, Min(NSz.cy, 400)) + 26);
  end;

  { hit testing on the link in sample 0 }
  SetFont(Sheet.Canvas);
  R.Tokenize(Samples[0]);
  L := R.Layout(Sheet.Canvas, N);
  LinkX := -1; LinkY := -1;
  for K := 0 to L.RunCount-1 do
  begin
    Run := L.RunAt(K);
    if Run.Style.LinkIndex > 0 then
    begin
      LinkX := (Run.Bounds.Left + Run.Bounds.Right) div 2;
      LinkY := (Run.Bounds.Top + Run.Bounds.Bottom) div 2;
      Break;
    end;
  end;
  WriteLn('link run found at ', LinkX, ',', LinkY);
  if LinkX >= 0 then
  begin
    NHit := R.HitTest(Sheet.Canvas, LinkX, LinkY);
    WriteLn('new hit on the link: onlink=', NHit.OnLink, ' name="', NHit.LinkName,
      '" index=', NHit.LinkIndex, ' text="', NHit.LinkText, '"');
    Wrapped := HTMLWordWrap(Sheet.Canvas, Samples[0], W, O.SuperSubScriptRatio, O.Scale);
    Hit := HTMLHitTest(Sheet.Canvas, Rect(0, 0, W, 400), Wrapped, O, LinkX, LinkY);
    WriteLn('old hit at the same point: onlink=', Hit.OnLink, ' name="', Hit.LinkName,
      '" index=', Hit.LinkIndex, ' text="', Hit.LinkText, '"');
  end;

  PNG := TPortableNetworkGraphic.Create;
  PNG.Assign(Sheet); PNG.SaveToFile(ParamStr(1));
  WriteLn('wrote ', ParamStr(1));
  WriteLn;
  WriteLn('--- speed ---');
  Bench;
  R.Free; PNG.Free; Sheet.Free;
end.
