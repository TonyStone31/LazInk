{ A dry run of LazInk's renderer.

  Draws a page of sample markup with InkRender - the engine itself, not the
  controls - into a PNG, prints each sample's extent, line and run counts,
  checks that the plain text reads back the way it went in, answers a hit
  test on a link, and then times the engine on a long document.

  It is a tool, not a test: nothing here is asserted, and tests/run.sh does
  not build it.  The numbers in docs/RENDERER_SPEC.md section 10 came from
  here; run it after changing layout and compare.

    fpc -Fu. -Fu$LAZARUS/lcl/units/x86_64-linux \
        -Fu$LAZARUS/lcl/units/x86_64-linux/gtk3 \
        -Fu$LAZARUS/components/lazutils/lib/x86_64-linux \
        -Fu$LAZARUS/components/freetype/lib/x86_64-linux \
        tools/renderer_dryrun.pas
    ./renderer_dryrun page.png

  For "does this look the way a page should look", the reference is a
  browser, not this: see tools/browser_shot.sh.

  SPDX-License-Identifier: 0BSD }
program renderer_dryrun;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Classes, SysUtils, Graphics, Types, Math, DateUtils,
  InkRender;

const
  W = 430;

var
  Sheet: TBitmap; PNG: TPortableNetworkGraphic;
  N: TInkRenderOptions; R: TInkRenderer; L: TInkRenderLayout;
  Samples, Names: array of string;
  I, Y, K, LinkX, LinkY: Integer;
  Tile: TBitmap; Run: TInkRenderRun; NHit: TInkRenderHit;

  procedure Sample(const AName, AMarkup: string);
  begin
    SetLength(Samples, Length(Samples)+1); Samples[High(Samples)] := AMarkup;
    SetLength(Names, Length(Names)+1); Names[High(Names)] := AName;
  end;

  procedure SetFont(C: TCanvas);
  begin
    C.Font.Name := 'DejaVu Sans'; C.Font.Size := 10;
    C.Font.Style := []; C.Font.Color := clBlack;
  end;

  { how long the engine takes on a document of some size }
  procedure Bench;
  const BWidth = 700;
  var Doc: string; J, Reps: Integer; T: TDateTime; BW: TBitmap;
    BN: TInkRenderOptions; BR: TInkRenderer; BL: TInkRenderLayout;
  begin
    Doc := '';
    for J := 1 to 400 do
      Doc := Doc + '<b>Heading ' + IntToStr(J) + '</b> some ordinary words in a paragraph, ' +
        'with <i>emphasis</i>, a <a href="p' + IntToStr(J) + '.html">link</a> and ' +
        '<font color="#336699">color</font> before the next break.<br>';
    WriteLn('document: ', Length(Doc) div 1024, ' KB of markup');
    BW := TBitmap.Create; BW.SetSize(BWidth, 400);
    BW.Canvas.Font.Name := 'DejaVu Sans'; BW.Canvas.Font.Size := 10;
    BR := TInkRenderer.Create;
    FillChar(BN, SizeOf(BN), 0);
    BN.BaseFont := BW.Canvas.Font; BN.Width := BWidth; BN.Scale := 100;
    BN.HoverIndex := -1; BN.LinkColor := clBlue; BN.LinkBackColor := clNone;
    BN.HoverColor := clRed; BN.HoverBackColor := clNone; BN.Borders := Rect(0,0,0,0);
    T := Now;
    BR.Tokenize(Doc); BL := BR.Layout(BW.Canvas, BN);
    WriteLn(Format('tokenize + layout         %5.0f ms  (height %d, %d runs)',
      [MilliSecondsBetween(Now, T) * 1.0, BL.Size.cy, BL.RunCount]));
    Reps := 30;
    T := Now;
    for J := 1 to Reps do BR.Paint(BW.Canvas, Rect(0, 0, BWidth, 400), BN);
    WriteLn(Format('%d paints, kept layout    %5.0f ms',
      [Reps, MilliSecondsBetween(Now, T) * 1.0]));
    T := Now;
    for J := 1 to Reps do BR.Paint(BW.Canvas, Rect(0, 0, BWidth, 400), BN, 0, -J*20);
    WriteLn(Format('%d paints, scrolling      %5.0f ms  (an offset, one layout)',
      [Reps, MilliSecondsBetween(Now, T) * 1.0]));
    BN.Width := BWidth - 120;
    T := Now;
    BL := BR.Layout(BW.Canvas, BN);
    WriteLn(Format('re-layout at a new width  %5.0f ms', [MilliSecondsBetween(Now, T) * 1.0]));
    BR.Free; BW.Free;
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
  Sample('table with headings',
    '<table><tr><th>Control</th><th>What it is</th></tr>' +
    '<tr><td>TInkPage</td><td>a viewer</td></tr></table>');
  Sample('nested inline', 'a <b>bold <i>and italic <u>and underlined</u></i></b> run');
  Sample('paragraphs only', 'one<p>two<p>three');
  Sample('a cell that wraps',
    '<table width="100%"><tr><td>a cell with enough words in it that the text has to ' +
    'wrap inside the cell rather than run past its edge</td><td>short</td></tr></table>');
  Sample('cells with their own style',
    '<table cellpadding="4" bordercolor="#8899aa"><tr>' +
    '<td bgcolor="#eef2ff" cellpadding="10" radius="8">roomy</td>' +
    '<td bgcolor="#fff7ed" valign="bottom">low</td>' +
    '<td border="none" color="#227744">no border<br>two lines</td></tr></table>');
  Sample('a table in a cell',
    '<table cellpadding="6" bordercolor="#8899aa"><tr><td>outer left</td>' +
    '<td><table cellpadding="4" bordercolor="#cc8844"><tr><td>inner one</td>' +
    '<td>inner two</td></tr></table></td></tr></table>');
  Sample('styled table (cards)',
    '<table width="100%" layout="fixed" cellspacing="8" cellpadding="6 8 6 8" ' +
    'cellbg="#eef2ff" bordercolor="#c7d2fe" radius="8">' +
    '<tr><td><b>Card one</b><br>some words</td><td bgcolor="#fff7ed"><b>Card two</b><br>more</td></tr></table>');

  Sheet := TBitmap.Create;
  Sheet.SetSize(W+40, 1500);
  Sheet.Canvas.Brush.Color := clWhite; Sheet.Canvas.Brush.Style := bsSolid;
  Sheet.Canvas.FillRect(0, 0, Sheet.Width, Sheet.Height);
  SetFont(Sheet.Canvas);

  R := TInkRenderer.Create;
  FillChar(N, SizeOf(N), 0);
  N.BaseFont := Sheet.Canvas.Font; N.Width := W; N.Scale := 100;
  N.Borders := Rect(0, 0, 0, 0);
  N.LinkColor := clBlue; N.LinkUnderline := True; N.HoverIndex := -1;
  N.LinkBackColor := clNone; N.HoverColor := clRed; N.HoverBackColor := clNone;

  Y := 10;
  for I := 0 to High(Samples) do
  begin
    Sheet.Canvas.Font.Style := [fsBold]; Sheet.Canvas.Font.Color := clGray;
    Sheet.Canvas.TextOut(10, Y, Names[I]);
    SetFont(Sheet.Canvas);
    Inc(Y, 18);

    R.Tokenize(Samples[I]);
    Tile := TBitmap.Create;
    try
      Tile.SetSize(W, 400);
      Tile.Canvas.Brush.Color := clWhite; Tile.Canvas.FillRect(0, 0, W, 400);
      SetFont(Tile.Canvas);
      L := R.Layout(Tile.Canvas, N);
      R.Paint(Tile.Canvas, Rect(0, 0, W, Max(1, Min(L.Size.cy, 400))), N);
      Sheet.Canvas.CopyRect(Rect(10, Y, 10+W, Y+Max(1, Min(L.Size.cy, 400))),
        Tile.Canvas, Rect(0, 0, W, Max(1, Min(L.Size.cy, 400))));
    finally Tile.Free end;

    WriteLn(Format('%-28s %4d x %3d   lines %2d runs %3d   text %s',
      [Names[I], L.Size.cx, L.Size.cy, L.LineCount, L.RunCount,
       BoolToStr(InkRenderPlainText(Samples[I]) <> '', 'ok', 'EMPTY')]));
    Inc(Y, Min(L.Size.cy, 400) + 24);
  end;

  { the link, and what a hit on it answers }
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
  if LinkX >= 0 then
  begin
    NHit := R.HitTest(Sheet.Canvas, LinkX, LinkY);
    WriteLn;
    WriteLn(Format('a hit at %d,%d: onlink=%s name="%s" text="%s" index=%d',
      [LinkX, LinkY, BoolToStr(NHit.OnLink, True), NHit.LinkName, NHit.LinkText,
       NHit.LinkIndex]));
  end;

  PNG := TPortableNetworkGraphic.Create;
  PNG.Assign(Sheet); PNG.SaveToFile(ParamStr(1));
  WriteLn('wrote ', ParamStr(1));
  WriteLn;
  WriteLn('--- speed ---');
  Bench;
  R.Free; PNG.Free; Sheet.Free;
end.
