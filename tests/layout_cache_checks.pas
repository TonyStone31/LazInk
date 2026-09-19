{ Retained-layout equivalence and invalidation through the public drawing API. }
unit Layout_Cache_Checks;
{$mode objfpc}{$H+}
interface
procedure LayoutCacheChecks;
implementation
uses Classes, SysUtils, Graphics, Controls, StdCtrls, LCLType, Types, ImgList, InkDraw;

type
  TRunProbe = class
    Trace: string;
    Cache: THTMLLayoutCache;
    Canvas: TCanvas;
    Reenter: Boolean;
    procedure Run(const Text: string; X,Y,W,H,Line,Part: Integer; Font: TFont);
  end;

procedure Require(OK: Boolean; const Msg: string);
begin
  if not OK then raise Exception.Create('Layout cache: '+Msg);
end;

procedure TRunProbe.Run(const Text: string; X,Y,W,H,Line,Part: Integer; Font: TFont);
var O: THTMLOptions; Hit: THTMLHitInfo; MW,MH: Integer; Nested: TRunProbe;
begin
  Trace := Trace+Format('%s[%d,%d,%d,%d,%d,%d,%s,%d,%d]',
    [Text,X,Y,W,H,Line,Part,Font.Name,Font.Height,Font.Color]);
  if Reenter then
  begin
    Reenter := False;
    { Invalidate the very entry being reported, then recursively measure a
      different entry. The outer layout and callback must remain alive. }
    Cache.Clear;
    Nested := TRunProbe.Create;
    try
      O := DefaultHTMLOptions; O.OnRun := @Nested.Run; O.RunPart := 99;
      HTMLMeasureAndHit(Canvas,Rect(0,0,180,100),'nested callback',O,-1,-1,
        MW,MH,Hit,Cache);
      Require(Nested.Trace<>'','nested callback was delivered');
    finally Nested.Free end;
  end;
end;

procedure LayoutCacheChecks;
var Bitmap,Other,Tile: TBitmap; Font: TFont; Cache,Small: THTMLLayoutCache;
  Probe: TRunProbe; Plain,Cached: TMemoryStream; Images: TImageList;
  O: THTMLOptions; R: TRect; Text,Expected: string; State: TOwnerDrawState;
  Hit: THTMLHitInfo; Before: QWord; W,H,X,Y,Pass: Integer; Found: Boolean;
  Initial,Changed: TSize;

  procedure ResetCanvas;
  begin
    Bitmap.Canvas.Font.PixelsPerInch := Font.PixelsPerInch;
    Bitmap.Canvas.Font.Assign(Font);
    Bitmap.Canvas.Brush.Style := bsSolid; Bitmap.Canvas.Brush.Color := clWhite;
    Bitmap.Canvas.FillRect(Rect(0,0,Bitmap.Width,Bitmap.Height));
    Bitmap.Canvas.Brush.Style := bsClear;
    Probe.Trace := '';
  end;

  procedure Equivalent(const LabelText: string);
  var SavedTrace: string; J: Integer;
  begin
    ResetCanvas;
    HTMLDrawOpt(Bitmap.Canvas,R,State,Text,O);
    SavedTrace := Probe.Trace;
    Plain.Clear; Bitmap.SaveToStream(Plain);
    for J := 1 to 2 do
    begin
      ResetCanvas;
      HTMLDrawOpt(Bitmap.Canvas,R,State,Text,O,Cache);
      Cached.Clear; Bitmap.SaveToStream(Cached);
      Require((Plain.Size=Cached.Size) and CompareMem(Plain.Memory,Cached.Memory,Plain.Size),
        LabelText+' pixels, pass '+IntToStr(J));
      Require(Probe.Trace=SavedTrace,LabelText+' callbacks, pass '+IntToStr(J));
    end;
  end;

  procedure ExpectMiss(const LabelText: string);
  begin
    Before := Cache.Misses;
    ResetCanvas; HTMLDrawOpt(Bitmap.Canvas,R,State,Text,O,Cache);
    Require(Cache.Misses=Before+1,LabelText+' invalidates geometry');
  end;

begin
  Bitmap := TBitmap.Create; Other := TBitmap.Create; Tile := TBitmap.Create;
  Font := TFont.Create; Cache := THTMLLayoutCache.Create;
  Small := nil; Images := TImageList.Create(nil); Probe := TRunProbe.Create;
  Plain := TMemoryStream.Create; Cached := TMemoryStream.Create;
  try
    Bitmap.SetSize(320,260); Other.SetSize(320,260);
    Font.Name := 'DejaVu Sans'; Font.Height := -16; Font.Color := clBlack;
    Probe.Cache := Cache; Probe.Canvas := Bitmap.Canvas;
    O := DefaultHTMLOptions; O.OnRun := @Probe.Run; O.RunPart := 7;
    R := Rect(0,0,300,250); State := [];
    Text := '<a href="before">before</a><table><tr><td rowspan="2" valign="bottom">'+
      '<a href="span">spanning cell</a></td><td><table><tr><td>nested café</td>'+ 
      '<td><b>right</b></td></tr></table></td></tr><tr><td>wrapping words wrapping words'+
      '</td></tr></table><a href="after">after</a>';
    Equivalent('nested table and rowspan');
    Require((Cache.Misses=1) and (Cache.Hits=1),'second paint reuses layout');
    Before := Cache.Misses;
    OffsetRect(R,9,-12); Equivalent('scroll offset');
    Require(Cache.Misses=Before,'scroll does not remeasure');
    O.HoverIndex := 1; O.HoverColor := clRed; O.HoverBackColor := clYellow;
    O.HoverUnderline := True; Equivalent('hover');
    O.LinkColor := clBlue; O.LinkUnderline := True; Equivalent('link style');
    State := [odSelected]; Equivalent('selected');
    State := [odDisabled]; Equivalent('disabled');
    Require(Cache.Misses=Before,'paint state does not remeasure');
    State := []; O.HoverIndex := 0;
    R := Rect(0,0,300,250);
    ResetCanvas; HTMLMeasureAndHit(Bitmap.Canvas,R,Text,O,-1,-1,W,H,Hit);
    Expected := Probe.Trace; Probe.Trace := ''; Bitmap.Canvas.Font.Assign(Font);
    HTMLMeasureAndHit(Bitmap.Canvas,R,Text,O,-1,-1,W,H,Hit,Cache);
    Require(Probe.Trace=Expected,'measurement reports all retained runs');
    Require(Cache.Misses=Before,'measure shares paint geometry');
    Found := False;
    for Y := 0 to 50 do
      for X := 0 to 75 do
      begin
        Bitmap.Canvas.Font.Assign(Font);
        Hit := HTMLHitTest(Bitmap.Canvas,R,Text,O,X*4,Y*4,Cache);
        if Hit.OnLink and (Hit.LinkName='span') then Found := True;
      end;
    Require(Found,'hit test finds link in spanning cell');
    Require(Cache.Misses=Before,'hit tests reuse paint geometry');
    Probe.Trace := ''; Probe.Reenter := True; Bitmap.Canvas.Font.Assign(Font);
    HTMLMeasureAndHit(Bitmap.Canvas,R,Text,O,-1,-1,W,H,Hit,Cache);
    Require(Probe.Trace=Expected,'cache clearing and nested callback preserve outer runs');

    Cache.Clear;
    Text := 'many wrapping words <b>bold</b> and a <a href="a">link</a>';
    Equivalent('plain text');
    R.Right := 110; ExpectMiss('width'); Equivalent('narrow text');
    O.LineHeight := 31; ExpectMiss('line height'); Equivalent('line height');
    O.LineSpacing := 4; ExpectMiss('line spacing'); Equivalent('line spacing');
    O.NoWrap := True; ExpectMiss('no wrap'); Equivalent('no wrap');
    O.Scale := 125; ExpectMiss('scale'); Equivalent('scale');
    O.Borders := Rect(3,4,5,6); ExpectMiss('borders'); Equivalent('borders');
    O.HorzAlign := ihaRight; ExpectMiss('horizontal alignment'); Equivalent('horizontal alignment');
    O.VertAlign := ivaBottom; ExpectMiss('vertical alignment'); Equivalent('vertical alignment');
    R.Bottom := 200; ExpectMiss('aligned height'); Equivalent('aligned height');
    Font.Height := -20; ExpectMiss('font height'); Equivalent('font height');
    Font.Style := [fsItalic]; ExpectMiss('font style'); Equivalent('font style');
    Font.Name := 'DejaVu Sans Mono'; ExpectMiss('font face'); Equivalent('font face');
    Font.Color := clGreen; ExpectMiss('font color'); Equivalent('font color');
    Text := 'replacement source'; ExpectMiss('source'); Equivalent('source');
    State := [odReserved1]; ExpectMiss('scaled indentation state');
    Font.PixelsPerInch := Font.PixelsPerInch+24; ExpectMiss('font DPI');
    Font.Quality := fqAntialiased; ExpectMiss('font quality');
    Font.Orientation := 100; ExpectMiss('font orientation');
    Before := Cache.Misses; Other.Canvas.Font.Assign(Font);
    HTMLDrawOpt(Other.Canvas,R,State,Text,O,Cache);
    Require(Cache.Misses=Before+1,'another canvas has separate geometry');

    Cache.Clear; Font.Orientation := 0; Font.Height := -16; Font.Style := [];
    O := DefaultHTMLOptions; O.Images := Images; State := [];
    R := Rect(0,0,300,250); Text := '<img src="0"> image';
    Images.Width := 16; Images.Height := 16; Tile.SetSize(16,16);
    Tile.Canvas.Brush.Color := clRed; Tile.Canvas.FillRect(Rect(0,0,16,16));
    Images.Add(Tile,nil);
    Equivalent('inline image');
    Before := Cache.Misses;
    Tile.Canvas.Brush.Color := clBlue; Tile.Canvas.FillRect(Rect(0,0,16,16));
    Images.Replace(0,Tile,nil); Equivalent('updated image pixels');
    Require(Cache.Misses=Before,'image pixels update without remeasuring');
    Bitmap.Canvas.Font.Assign(Font);
    Initial := HTMLTextExtentOpt(Bitmap.Canvas,R,[],Text,O,Cache);
    { A TImageList empties itself when it is resized, so the picture has to
      be put back at the new size - otherwise the run falls back to the
      placeholder and the geometry would not move for the reason meant. }
    Images.Width := 32; Images.Height := 32;
    Tile.SetSize(32,32);
    Tile.Canvas.Brush.Color := clRed; Tile.Canvas.FillRect(Rect(0,0,32,32));
    Images.Add(Tile,nil);
    Require(Images.Count=1,'the resized list holds its picture again');
    ExpectMiss('image dimensions');
    Bitmap.Canvas.Font.Assign(Font);
    Changed := HTMLTextExtentOpt(Bitmap.Canvas,R,[],Text,O,Cache);
    Require(Changed.cx>Initial.cx,'resized inline image changes geometry');
    Images.Clear; ExpectMiss('image count');

    Small := THTMLLayoutCache.Create(2);
    O := DefaultHTMLOptions;
    for Pass := 1 to 4 do
    begin
      Bitmap.Canvas.Font.Assign(Font);
      HTMLDrawOpt(Bitmap.Canvas,R,[],'entry '+IntToStr(Pass),O,Small);
    end;
    Require((Small.Count=2) and (Small.Misses=4),'entry budget evicts');
    Before := Small.Misses; Bitmap.Canvas.Font.Assign(Font);
    HTMLDrawOpt(Bitmap.Canvas,R,[],'entry 3',O,Small);
    Require(Small.Misses=Before,'recent entry survives');
    Bitmap.Canvas.Font.Assign(Font);
    HTMLDrawOpt(Bitmap.Canvas,R,[],'entry 1',O,Small);
    Require(Small.Misses=Before+1,'evicted entry is rebuilt');
    FreeAndNil(Small); Small := THTMLLayoutCache.Create(128,1);
    for Pass := 1 to 3 do
    begin
      Bitmap.Canvas.Font.Assign(Font);
      HTMLDrawOpt(Bitmap.Canvas,R,[],'oversized '+IntToStr(Pass),O,Small);
      Require((Small.Count=1) and (Small.Bytes>1),'one oversized entry, no accumulation');
    end;
    Small.Clear; Require((Small.Count=0) and (Small.Bytes=0),'clear releases entries');
    WriteLn('Retained-layout pixels, callbacks, hit tests, invalidation and eviction checks passed.');
  finally
    Cached.Free; Plain.Free; Probe.Free; Images.Free; Small.Free; Cache.Free;
    Font.Free; Tile.Free; Other.Free; Bitmap.Free;
  end;
end;
end.
