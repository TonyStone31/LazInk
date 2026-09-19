{ InkRender - LazInk's own renderer.

  This unit is an isolated, from-scratch experiment for the renderer described
  in docs/RENDERER_SPEC.md.  It intentionally has no dependency on InkHtml,
  inktables.inc, or any LazInk control and is not part of lazink.lpk.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors

  The design is deliberately data-first:
    source -> lexical tokens -> styled runs -> cached line boxes -> paint.
  A layout is immutable while it is painted, so scrolling never reparses or
  remeasures the source.  This is prototype plumbing, not a compatibility
  wrapper for the existing renderer.
}
unit InkRender;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList, LCLType, LCLIntf, Types, Math, InkBox;

function InkRenderEscape(const Text: string): string;
function InkRenderUnescape(const Text: string): string;
function InkRenderPlainText(const Markup: string): string;
function InkRenderColor(const S: string; Default: TColor = clBlack): TColor;
function InkRenderContrastColor(Background: TColor): TColor;
function InkRenderShadeColor(Color: TColor; Percent: Integer): TColor;
function InkRenderIsCJK(const Text: string): Boolean;
procedure InkRenderApplySize(const Canvas: TCanvas; ASize: Integer); overload;
procedure InkRenderApplySize(const AFont: TFont; ASize: Integer); overload;
function InkRenderTimes(ASize, AFactor: Integer): Integer;
function InkRenderSmaller(ASize: Integer; AFactor: Double): Integer;
function InkRenderScalePx(Value, Scale: Integer): Integer;

type
  TInkRenderTokenKind = (ntText, ntOpen, ntClose, ntBreak, ntRule);
  TInkRenderAlign = (naLeft, naCenter, naRight);
  TInkRenderVertAlign = (nvaTop, nvaCenter, nvaBottom);
  TInkRenderScript = (nsNormal, nsSuper, nsSub);

  TInkRenderToken = record
    Kind: TInkRenderTokenKind;
    Name: string;
    Value: string;
    Attributes: TStringList;
    SelfClosing: Boolean;
  end;

  TInkRenderStyle = record
    Face: string;
    Size: Integer;
    Color, BackColor: TColor;
    Styles: TFontStyles;
    Script: TInkRenderScript;
    LinkIndex: Integer;
    LinkName: string;
    Align: TInkRenderAlign;
    Indent: Integer;
  end;

  TInkRenderRun = record
    Text: string;
    Style: TInkRenderStyle;
    Bounds: TRect;
    { spec 2.2: a run hangs from a baseline rather than sitting on a top
      edge.  Ascent is how far it reaches above that line, Descent below. }
    Ascent, Descent, Baseline: Integer;
    Line: Integer;
    Part: Integer;
    IsImage: Boolean;
    ImageIndex: Integer;
    Control: Byte; { 0=text, 1=table, 2=row, 3=cell, 4/5/6=closes, 7=rule, 8=cell box }
    Meta: string; { serialized attributes on structural runs }
  end;

  TInkRenderLine = record
    Bounds: TRect;
    Baseline: Integer;
    FirstRun, RunCount: Integer;
    Align: TInkRenderAlign;
    Part: Integer;
  end;

  TInkRenderHit = record
    OnLink: Boolean;
    LinkIndex: Integer;
    LinkName, LinkText: string;
    RunIndex: Integer;
    CharacterOffset: Integer;
  end;

  TInkRenderRunEvent = procedure(const Run: TInkRenderRun) of object;

  TInkRenderOptions = record
    BaseFont: TFont;
    Images: TCustomImageList;
    Width: Integer;
    Height: Integer;
    VertAlign: TInkRenderVertAlign;
    Scale: Integer;
    LineSpacing: Integer;
    { a line's height in pixels, as CSS line-height asks for it: the extra
      room is split evenly above and below the font's own ascent and
      descent, which is what a browser calls half-leading.  Zero leaves
      every line the height of the font in it. }
    LineHeight: Integer;
    Borders: TRect;
    LinkColor, LinkBackColor: TColor;
    LinkUnderline: Boolean;
    HoverIndex: Integer;
    HoverColor, HoverBackColor: TColor;
    HoverUnderline: Boolean;
    OwnerState: TOwnerDrawState;
    { code: the text is laid out as it was written and cut off at the edge
      rather than wrapped }
    NoWrap: Boolean;
    OnRun: TInkRenderRunEvent;
    RunPart: Integer;
  end;

  TInkRenderLayout = class
  private
    FReferences: Integer;
    FRuns: array of TInkRenderRun;
    FLines: array of TInkRenderLine;
    FSize: TSize;
    FSourceHash: Cardinal;
    FWidth, FScale: Integer;
  public
    procedure Clear;
    { Conservative payload size, including managed strings (which may be shared). }
    function StorageBytes: SizeUInt;
    { Pins for cache clients: a callback may clear/evict its own cache. }
    procedure Retain;
    procedure Release;
    function RunCount: Integer;
    function LineCount: Integer;
    function RunAt(Index: Integer): TInkRenderRun;
    function LineAt(Index: Integer): TInkRenderLine;
    property Size: TSize read FSize;
    property SourceHash: Cardinal read FSourceHash;
    property Width: Integer read FWidth;
  end;

  TInkRenderer = class
  private
    FTokens: array of TInkRenderToken;
    FStyled: array of TInkRenderRun;
    FLayout: TInkRenderLayout;
    FSourceHash: Cardinal;
    FLayoutKey: Cardinal;
    FStyleKey: Cardinal;
    FMetricKeys, FMetricHeights: TStringList;
    { the box tree the document is laid out through, and the options in use }
    FRoot: TInkBox;
    FOpt: TInkRenderOptions;
    FWidthKeys, FWidthValues: TStringList;
    { the style the last cache key was built from, and the key it made }
    FKeyFace, FKeyText: string;
    FKeySize, FKeyBits, FKeyScript: Integer;
    { and what the last call to Metrics worked out, for the run after it }
    FMetFace: string;
    FMetSize, FMetBits, FMetScript, FMetLine, FMetHeight, FMetAscent: Integer;
    FNextLink: Integer;
    function HashSource(const S: string): Cardinal;
    function HashOptions(const Options: TInkRenderOptions): Cardinal;
    function IsKnownTag(const N: string): Boolean;
    function IsStyleTag(const N: string): Boolean;
    function BaseStyle(const Options: TInkRenderOptions): TInkRenderStyle;
    function StyleFor(const Stack: array of TInkRenderStyle): TInkRenderStyle;
    procedure AddToken(AKind: TInkRenderTokenKind; const Name, Value: string;
      ASelfClosing: Boolean; const Attrs: TStringList);
    procedure BuildStyles(const Options: TInkRenderOptions);
    procedure AddStyledText(const Text: string; const Style: TInkRenderStyle;
      APart: Integer);
    { the part of a cache key that a run's style makes, kept between runs:
      a paragraph's words nearly all share one style, and building it again
      for every word was four IntToStr and a handful of concatenations }
    function StyleKey(const AStyle: TInkRenderStyle): string;
    function MeasureRun(const Canvas: TCanvas; const Run: TInkRenderRun): TSize;
    { the height of a run's line, and how it sits on its baseline }
    function Metrics(const Canvas: TCanvas; const Run: TInkRenderRun;
      out AAscent, ADescent: Integer): Integer;
    function MetricHeight(const Canvas: TCanvas; const Run: TInkRenderRun): Integer;
    function IsCJK(C: Cardinal): Boolean;
    function CodepointAt(const S: string; P: Integer; out Bytes: Integer): Cardinal;
    { ALeft and AWidth say where the table goes and how much room it has;
      left alone they are the page's column, and a table inside a cell
      passes the cell's }
    procedure LayoutTable(const Canvas: TCanvas; const Options: TInkRenderOptions;
      AStart, AEnd: Integer; var X, Y, Line: Integer;
      ALeft: Integer = -1; AWidth: Integer = -1; ABox: TInkBox = nil);
    { spec 2.1: the tree the document is laid out through, and the three
      ways a box of ours measures itself }
    procedure BuildBoxTree;
    function MeasureInline(ABox: TInkBox; const Canvas: TCanvas;
      AWidth, AY: Integer): Integer;
    function MeasureRule(ABox: TInkBox; const Canvas: TCanvas;
      AWidth, AY: Integer): Integer;
    function MeasureTableBox(ABox: TInkBox; const Canvas: TCanvas;
      AWidth, AY: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Tokenize(const Source: string);
    function Layout(const Canvas: TCanvas; const Options: TInkRenderOptions): TInkRenderLayout;
    { Paints the kept layout into Bounds.  AOffsetX and AOffsetY move the
      text inside it without laying anything out again - which is what
      scrolling is: one layout, a hundred offsets. }
    procedure Paint(Canvas: TCanvas; const Bounds: TRect; const Options: TInkRenderOptions;
      AOffsetX: Integer = 0; AOffsetY: Integer = 0);
    { Tells Options.OnRun about every run of text in the kept layout, in the
      coordinates a paint at these offsets would have used.  This is how a
      control learns where the words are without drawing them - measuring
      must not depend on there being a clip, or a canvas at all. }
    procedure ReportRuns(const Options: TInkRenderOptions;
      AOffsetX: Integer = 0; AOffsetY: Integer = 0);
    { X and Y in the coordinates Paint was given, offsets included }
    function HitTest(const Canvas: TCanvas; X, Y: Integer;
      AOffsetX: Integer = 0; AOffsetY: Integer = 0): TInkRenderHit;
    { Transfer the finished geometry without retaining tokens, box trees or
      measurement caches. The caller owns the result. }
    function DetachLayout: TInkRenderLayout;
    procedure PaintLayout(Canvas: TCanvas; const Bounds: TRect;
      const Options: TInkRenderOptions; ALayout: TInkRenderLayout;
      AOffsetX: Integer = 0; AOffsetY: Integer = 0);
    procedure ReportLayoutRuns(const Options: TInkRenderOptions;
      ALayout: TInkRenderLayout; AOffsetX: Integer = 0; AOffsetY: Integer = 0);
    function HitTestLayout(const Canvas: TCanvas; X, Y: Integer;
      ALayout: TInkRenderLayout; AOffsetX: Integer = 0;
      AOffsetY: Integer = 0): TInkRenderHit;
    property CachedLayout: TInkRenderLayout read FLayout;
  end;

implementation

function Lower(const S: string): string;
begin Result := LowerCase(Trim(S)) end;

function InkRenderColor(const S: string; Default: TColor): TColor;
var V, Hex: string; N: LongInt;
begin
  V := Lower(S);
  if (V = '') or (V = 'none') or (V = 'transparent') then Exit(Default);
  if V[1] = '#' then
  begin
    Hex := Copy(V, 2, MaxInt);
    if Length(Hex) = 3 then Hex := Hex[1]+Hex[1]+Hex[2]+Hex[2]+Hex[3]+Hex[3];
    if TryStrToInt('$'+Hex, N) then Exit(RGBToColor((N shr 16) and $ff,
      (N shr 8) and $ff, N and $ff));
  end;
  { the names a page writes, which are not the LCL's clXxx spellings }
  if V='white' then Exit(clWhite);
  if (V='black') then Exit(clBlack);
  if (V='gray') or (V='gray') then Exit(clGray);
  if V='silver' then Exit(RGBToColor($C0,$C0,$C0));
  if V='red' then Exit(clRed);
  if V='maroon' then Exit(clMaroon);
  if V='lime' then Exit(clLime);
  if V='green' then Exit(clGreen);
  if V='blue' then Exit(clBlue);
  if V='navy' then Exit(clNavy);
  if V='yellow' then Exit(clYellow);
  if V='olive' then Exit(clOlive);
  if (V='aqua') or (V='cyan') then Exit(clAqua);
  if V='teal' then Exit(clTeal);
  if (V='fuchsia') or (V='magenta') then Exit(clFuchsia);
  if V='purple' then Exit(clPurple);
  if V='orange' then Exit(RGBToColor($FF,$A5,$00));
  if V='gold' then Exit(RGBToColor($FF,$D7,$00));
  if V='pink' then Exit(RGBToColor($FF,$C0,$CB));
  if V='brown' then Exit(RGBToColor($A5,$2A,$2A));
  { and the LCL's own, so clWindowText and friends still work }
  Result := StringToColorDef(S, StringToColorDef('cl'+S, Default));
end;

function InkRenderEscape(const Text: string): string;
var P, Start: Integer;
begin
  { one pass: copy the runs between the three characters that are markup,
    and write their names where they were }
  Result := ''; P := 1; Start := 1;
  while P <= Length(Text) do
  begin
    if Text[P] in ['&','<','>'] then
    begin
      if P > Start then Result := Result + Copy(Text,Start,P-Start);
      case Text[P] of
        '&': Result := Result + '&amp;';
        '<': Result := Result + '&lt;';
        '>': Result := Result + '&gt;';
      end;
      Start := P+1;
    end;
    Inc(P);
  end;
  if P > Start then Result := Result + Copy(Text,Start,P-Start);
end;

{ &#233; and &#xE9; }
function InkRenderNumbered(const Name: string): string;
var N: LongInt;
begin
  Result := '';
  if (Length(Name)>2) and ((Name[2]='x') or (Name[2]='X')) then
  begin
    if not TryStrToInt('$'+Copy(Name,3,MaxInt),N) then Exit;
  end
  else if not TryStrToInt(Copy(Name,2,MaxInt),N) then Exit;
  if (N<=0) or (N>$10FFFF) or ((N>=$D800) and (N<=$DFFF)) then Exit;
  Result := UTF8Encode(WideString(WideChar(N)));
end;

{ The named entities documents actually use - the ones a page writes when it
  means a symbol it cannot type.  Not the whole HTML table. }
function InkRenderNamed(const Name: string): string;
begin
  Result := '';
  case Name of
    'nbsp': Result := ' ';
    'ensp', 'emsp', 'thinsp': Result := ' ';
    'shy', 'zwj', 'zwnj': Result := '';
    'copy': Result := #$C2#$A9;
    'reg': Result := #$C2#$AE;
    'trade': Result := #$E2#$84#$A2;
    'deg': Result := #$C2#$B0;
    'plusmn': Result := #$C2#$B1;
    'times': Result := #$C3#$97;
    'divide': Result := #$C3#$B7;
    'middot': Result := #$C2#$B7;
    'bull': Result := #$E2#$80#$A2;
    'hellip': Result := #$E2#$80#$A6;
    'ndash': Result := #$E2#$80#$93;
    'mdash': Result := #$E2#$80#$94;
    'lsquo': Result := #$E2#$80#$98;
    'rsquo': Result := #$E2#$80#$99;
    'ldquo': Result := #$E2#$80#$9C;
    'rdquo': Result := #$E2#$80#$9D;
    'laquo': Result := #$C2#$AB;
    'raquo': Result := #$C2#$BB;
    'lsaquo': Result := #$E2#$80#$B9;
    'rsaquo': Result := #$E2#$80#$BA;
    'larr': Result := #$E2#$86#$90;
    'uarr': Result := #$E2#$86#$91;
    'rarr': Result := #$E2#$86#$92;
    'darr': Result := #$E2#$86#$93;
    'harr': Result := #$E2#$86#$94;
    'euro': Result := #$E2#$82#$AC;
    'pound': Result := #$C2#$A3;
    'yen': Result := #$C2#$A5;
    'cent': Result := #$C2#$A2;
    'sect': Result := #$C2#$A7;
    'para': Result := #$C2#$B6;
    'dagger': Result := #$E2#$80#$A0;
    'permil': Result := #$E2#$80#$B0;
    'frac12': Result := #$C2#$BD;
    'frac14': Result := #$C2#$BC;
    'frac34': Result := #$C2#$BE;
    'sup2': Result := #$C2#$B2;
    'sup3': Result := #$C2#$B3;
    'micro': Result := #$C2#$B5;
    'infin': Result := #$E2#$88#$9E;
    'ne': Result := #$E2#$89#$A0;
    'le': Result := #$E2#$89#$A4;
    'ge': Result := #$E2#$89#$A5;
    'check': Result := #$E2#$9C#$93;
    'star': Result := #$E2#$98#$85;
  end;
end;

function InkRenderUnescape(const Text: string): string;
var P, Q: Integer; Name: string;
begin
  { one pass, reading each &name; where it stands: an ampersand that came
    from &amp; is therefore never read a second time }
  Result := ''; P := 1;
  while P <= Length(Text) do
  begin
    if Text[P] <> '&' then begin Result := Result+Text[P]; Inc(P); Continue end;
    Q := P+1;
    while (Q <= Length(Text)) and (Q-P <= 8) and (Text[Q] <> ';') do Inc(Q);
    if (Q > Length(Text)) or (Text[Q] <> ';') then
    begin
      Result := Result+Text[P]; Inc(P); Continue;
    end;
    Name := LowerCase(Copy(Text,P+1,Q-P-1));
    if Name = 'lt' then Result := Result+'<'
    else if Name = 'gt' then Result := Result+'>'
    else if Name = 'amp' then Result := Result+'&'
    else if Name = 'quot' then Result := Result+'"'
    else if Name = 'apos' then Result := Result+''''
    else if (Name<>'') and (Name[1]='#') then Result := Result+InkRenderNumbered(Name)
    else if InkRenderNamed(Name)<>'' then Result := Result+InkRenderNamed(Name)
    else Result := Result+Copy(Text,P,Q-P+1);
    P := Q+1;
  end;
end;

function InkRenderPlainText(const Markup: string): string;
var P,Q,S: Integer; Raw,Name: string; Closing: Boolean;
begin
  Result:=''; P:=1;
  while P<=Length(Markup) do
  begin
    if Markup[P]<>'<' then begin Result:=Result+Markup[P]; Inc(P); Continue end;
    Q:=P+1; while (Q<=Length(Markup)) and (Markup[Q]<>'>') do Inc(Q);
    if Q>Length(Markup) then begin Result:=Result+Copy(Markup,P,MaxInt); Break end;
    Raw:=LowerCase(Trim(Copy(Markup,P+1,Q-P-1)));
    Closing:=(Raw<>'') and (Raw[1]='/');
    if Closing then Delete(Raw,1,1);
    Name:=Raw; S:=Pos(' ',Name); if S>0 then Name:=Copy(Name,1,S-1);
    { section 3.4.  An opening <p> is a blank line - two endings - because
      that is what it draws; a closing one, a rule and a break are one each;
      a cell ends with a tab. }
    if Closing and ((Name='td') or (Name='th')) then Result:=Result+#9
    else if (not Closing) and (Name='p') then
    begin
      if Trim(Result)<>'' then Result:=Result+LineEnding+LineEnding;
    end
    else if (Name='br') or (Name='hr') or
      (Closing and ((Name='tr') or (Name='p'))) then Result:=Result+LineEnding;
    P:=Q+1;
  end;
  Result:=InkRenderUnescape(Result);
end;

function InkRenderContrastColor(Background: TColor): TColor;
var R,G,B: Byte; L: Integer;
begin
  R:=Red(ColorToRGB(Background)); G:=Green(ColorToRGB(Background)); B:=Blue(ColorToRGB(Background));
  L:=(299*R+587*G+114*B) div 1000;
  if L<128 then Result:=clWhite else Result:=clBlack;
end;

function InkRenderShadeColor(Color: TColor; Percent: Integer): TColor;
var R,G,B: Integer;
begin
  R:=Red(ColorToRGB(Color)); G:=Green(ColorToRGB(Color)); B:=Blue(ColorToRGB(Color));
  R:=EnsureRange(R+(255-R)*Percent div 100,0,255);
  G:=EnsureRange(G+(255-G)*Percent div 100,0,255);
  B:=EnsureRange(B+(255-B)*Percent div 100,0,255);
  Result:=RGBToColor(R,G,B);
end;

function InkRenderIsCJK(const Text: string): Boolean;
var U: Cardinal;
begin
  if Text='' then Exit(False);
  U:=Ord(Text[1]);
  Result:=((U>=$2E80) and (U<=$A4CF)) or ((U>=$AC00) and (U<=$D7A3)) or
    ((U>=$F900) and (U<=$FAFF)) or ((U>=$20000) and (U<=$2FA1F));
end;

{ "6", "6 10" or "6 10 6 10", the way CSS writes padding: one value for
  every side, two for vertical and horizontal, four for top, right, bottom,
  left.  A page writes all four, and reading only the first was why a table
  whose stylesheet asked for room came out tight. }
function PadOf(const S: string; ADefault, AScale: Integer): TRect;
var Parts: TStringList; N: array[0..3] of Integer; I: Integer;
begin
  for I := 0 to 3 do N[I] := ADefault;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
    Parts.DelimitedText := Trim(S);
    case Parts.Count of
      1: for I := 0 to 3 do N[I] := StrToIntDef(Parts[0],ADefault);
      2: begin
           N[0] := StrToIntDef(Parts[0],ADefault); N[2] := N[0];
           N[1] := StrToIntDef(Parts[1],ADefault); N[3] := N[1];
         end;
      3: begin
           N[0] := StrToIntDef(Parts[0],ADefault);
           N[1] := StrToIntDef(Parts[1],ADefault); N[3] := N[1];
           N[2] := StrToIntDef(Parts[2],ADefault);
         end;
      4: for I := 0 to 3 do N[I] := StrToIntDef(Parts[I],ADefault);
    end;
  finally Parts.Free end;
  { top, right, bottom, left - into a TRect's Top, Right, Bottom, Left }
  Result := Rect(Max(0,InkRenderScalePx(N[3],AScale)),Max(0,InkRenderScalePx(N[0],AScale)),
    Max(0,InkRenderScalePx(N[1],AScale)),Max(0,InkRenderScalePx(N[2],AScale)));
end;

{ A size the LCL's way: points when positive, pixels when negative, exactly
  as TFont.Size and TFont.Height spell it.  A page whose CSS says 14px then
  gets fourteen pixels of text rather than the ten and a half points it
  would otherwise round to. }
procedure InkRenderApplySize(const Canvas: TCanvas; ASize: Integer);
begin
  if ASize < 0 then Canvas.Font.Height := ASize
  else Canvas.Font.Size := ASize;
end;

{ the same, on a font of its own: a run reported to a host carries its size
  the way the rest of the engine spells one, and assigning a pixel size to
  TFont.Size would be a size in points with the sign still on it }
procedure InkRenderApplySize(const AFont: TFont; ASize: Integer);
begin
  if ASize < 0 then AFont.Height := ASize
  else AFont.Size := ASize;
end;

{ the same size, several times over, for measuring a font more finely than
  the platform will report it }
function InkRenderTimes(ASize, AFactor: Integer): Integer;
begin
  if ASize < 0 then Result := ASize*AFactor else Result := ASize*AFactor;
end;

{ the same size, smaller, for a superscript or a subscript }
function InkRenderSmaller(ASize: Integer; AFactor: Double): Integer;
begin
  if ASize < 0 then Result := Min(-1,Round(ASize*AFactor))
  else Result := Max(1,Round(ASize*AFactor));
end;

function InkRenderScalePx(Value, Scale: Integer): Integer;
begin
  if Scale<=0 then Scale:=100;
  Result:=Max(0,Round(Value*Scale/100));
end;

function InkRenderAttr(const Attrs: TStringList; const Name: string): string;
begin Result := Attrs.Values[Lower(Name)] end;

function InkRenderStyleBits(const Styles: TFontStyles): Integer;
begin
  Result := 0;
  if fsBold in Styles then Inc(Result, 1);
  if fsItalic in Styles then Inc(Result, 2);
  if fsUnderline in Styles then Inc(Result, 4);
  if fsStrikeOut in Styles then Inc(Result, 8);
end;

function InkRenderDecodeText(const S: string): string;
var I: Integer; T: string;
begin
  { The document layer owns full entity handling. These three escapes are
    sufficient for the renderer's deliberately small markup contract. }
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      T := LowerCase(Copy(S, I, 4));
      if T = '&lt;' then begin Result := Result + '<'; Inc(I, 4); Continue end;
      if T = '&gt;' then begin Result := Result + '>'; Inc(I, 4); Continue end;
      T := LowerCase(Copy(S, I, 5));
      if T = '&amp;' then begin Result := Result + '&'; Inc(I, 5); Continue end;
    end;
    Result := Result + S[I]; Inc(I);
  end;
end;

function InkRenderText(const S: string): string;
var I: Integer;
begin
  Result := InkRenderDecodeText(S);
  I := 1;
  while I <= Length(Result) do
    if Result[I] in [#10, #13] then Delete(Result, I, 1) else Inc(I);
end;

procedure TInkRenderLayout.Clear;
begin
  SetLength(FRuns, 0); SetLength(FLines, 0); FSize := Types.Size(0, 0);
  FSourceHash := 0; FWidth := -1; FScale := 100;
end;

procedure TInkRenderLayout.Retain;
begin
  Inc(FReferences);
end;

procedure TInkRenderLayout.Release;
begin
  Dec(FReferences);
  if FReferences=0 then Free;
end;

function TInkRenderLayout.StorageBytes: SizeUInt;
var I: Integer;
begin
  Result := InstanceSize + SizeUInt(Length(FRuns))*SizeOf(TInkRenderRun) +
    SizeUInt(Length(FLines))*SizeOf(TInkRenderLine);
  for I := 0 to High(FRuns) do
    with FRuns[I] do
      Inc(Result, Length(Text)+Length(Meta)+Length(Style.Face)+
        Length(Style.LinkName)+4*32);
end;

function TInkRenderer.DetachLayout: TInkRenderLayout;
begin
  Result := FLayout;
  FLayout := TInkRenderLayout.Create;
  FLayout.Clear;
end;

function TInkRenderLayout.RunCount: Integer;
begin Result := Length(FRuns) end;

function TInkRenderLayout.LineCount: Integer;
begin Result := Length(FLines) end;

function TInkRenderLayout.RunAt(Index: Integer): TInkRenderRun;
begin
  if (Index < 0) or (Index >= Length(FRuns)) then
    raise ERangeError.CreateFmt('Run index %d is outside the layout', [Index]);
  Result := FRuns[Index];
end;

function TInkRenderLayout.LineAt(Index: Integer): TInkRenderLine;
begin
  if (Index < 0) or (Index >= Length(FLines)) then
    raise ERangeError.CreateFmt('Line index %d is outside the layout', [Index]);
  Result := FLines[Index];
end;

constructor TInkRenderer.Create;
begin
  inherited Create;
  FLayout := TInkRenderLayout.Create;
  FMetricKeys := TStringList.Create;
  FMetricHeights := TStringList.Create;
  FWidthKeys := TStringList.Create;
  FWidthValues := TStringList.Create;
  FMetricKeys.Sorted:=True; FMetricKeys.CaseSensitive:=True;
  FMetricHeights.CaseSensitive:=True;
  FWidthKeys.Sorted:=True; FWidthKeys.CaseSensitive:=True;
  FWidthValues.CaseSensitive:=True;
end;

destructor TInkRenderer.Destroy;
var I: Integer;
begin
  for I := 0 to High(FTokens) do FTokens[I].Attributes.Free;
  FRoot.Free;
  FLayout.Free;
  FMetricKeys.Free; FMetricHeights.Free;
  FWidthKeys.Free; FWidthValues.Free;
  inherited Destroy;
end;

function TInkRenderer.HashSource(const S: string): Cardinal;
var I: Integer;
begin
  Result := 2166136261;
  for I := 1 to Length(S) do Result := (Result xor Ord(S[I])) * 16777619;
end;

function TInkRenderer.IsKnownTag(const N: string): Boolean;
begin
  Result := (N = 'b') or (N = 'i') or (N = 'u') or (N = 's') or
    (N = 'sup') or (N = 'sub') or (N = 'font') or (N = 'a') or
    (N = 'br') or (N = 'hr') or (N = 'p') or (N = 'center') or
    (N = 'right') or (N = 'left') or (N = 'ind') or (N = 'img') or
    (N = 'table') or (N = 'tr') or (N = 'td') or (N = 'th');
end;

function TInkRenderer.IsStyleTag(const N: string): Boolean;
begin
  Result := (N = 'b') or (N = 'i') or (N = 'u') or (N = 's') or
    (N = 'sup') or (N = 'sub') or (N = 'font') or (N = 'a') or
    (N = 'center') or (N = 'right') or (N = 'left') or (N = 'ind') or
    (N = 'td') or (N = 'th');
end;

procedure TInkRenderer.AddToken(AKind: TInkRenderTokenKind;
  const Name, Value: string; ASelfClosing: Boolean; const Attrs: TStringList);
var N: Integer;
begin
  N := Length(FTokens); SetLength(FTokens, N+1);
  FTokens[N].Kind := AKind; FTokens[N].Name := Name;
  FTokens[N].Value := Value; FTokens[N].SelfClosing := ASelfClosing;
  FTokens[N].Attributes := TStringList.Create;
  FTokens[N].Attributes.CaseSensitive := False;
  FTokens[N].Attributes.Assign(Attrs);
end;

procedure TInkRenderer.Tokenize(const Source: string);
var P, Q, Start, N: Integer; Raw, Name, Key, Val: string;
  Closing, SelfClosing, InlineAttr: Boolean; Attrs: TStringList; Quote: Char;
begin
  FSourceHash := HashSource(Source);
  FLayout.Clear; FStyleKey := 0; FLayoutKey := 0;
  for N := 0 to High(FTokens) do FTokens[N].Attributes.Free;
  SetLength(FTokens, 0); P := 1; Attrs := TStringList.Create;
  try
    while P <= Length(Source) do
    begin
      if Source[P] <> '<' then
      begin
        Start := P; while (P <= Length(Source)) and (Source[P] <> '<') do Inc(P);
        AddToken(ntText, '', InkRenderText(Copy(Source, Start, P-Start)), False, Attrs); Continue;
      end;
      Q := P+1; while (Q <= Length(Source)) and (Source[Q] <> '>') do Inc(Q);
      if Q > Length(Source) then
      begin
        AddToken(ntText, '', InkRenderText(Copy(Source, P, MaxInt)), False, Attrs); Break;
      end;
      Raw := Copy(Source, P+1, Q-P-1); P := Q+1;
      Closing := False; SelfClosing := False; Raw := Trim(Raw);
      if (Raw <> '') and (Raw[1] = '/') then begin Closing := True; Delete(Raw,1,1); Raw := Trim(Raw) end;
      if (Raw <> '') and (Raw[Length(Raw)] = '/') then begin SelfClosing := True; Delete(Raw,Length(Raw),1); Raw := Trim(Raw) end;
      InlineAttr := False;
      Q := 1; while (Q <= Length(Raw)) and not (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
      Name := Lower(Copy(Raw,1,Q-1));
      if Pos('=',Name)>0 then
      begin
        Key:=Copy(Name,1,Pos('=',Name)-1); Val:=Copy(Name,Pos('=',Name)+1,MaxInt);
        Name:=Lower(Key); Attrs.Clear; Attrs.Values['n']:=Val; InlineAttr:=True;
      end;
      if not IsKnownTag(Name) then Continue;
      if not InlineAttr then Attrs.Clear;
      while Q <= Length(Raw) do
      begin
        while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
        Start := Q; while (Q <= Length(Raw)) and not (Raw[Q] in ['=',' ',#9,#10,#13]) do Inc(Q);
        Key := Lower(Copy(Raw,Start,Q-Start)); if Key='' then Break;
        while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
        Val := '';
        if (Q <= Length(Raw)) and (Raw[Q] = '=') then
        begin
          Inc(Q); while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
          Quote := #0; if (Q <= Length(Raw)) and (Raw[Q] in ['"', '''']) then begin Quote := Raw[Q]; Inc(Q) end;
          Start := Q;
          if Quote <> #0 then while (Q <= Length(Raw)) and (Raw[Q] <> Quote) do Inc(Q)
          else while (Q <= Length(Raw)) and not (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
          Val := Copy(Raw,Start,Q-Start); if Quote <> #0 then Inc(Q);
        end;
        Attrs.Values[Key] := Val;
      end;
      if Name = 'br' then AddToken(ntBreak,Name,'',SelfClosing,Attrs)
      else if Name = 'hr' then AddToken(ntRule,Name,'',SelfClosing,Attrs)
      else if Closing then AddToken(ntClose,Name,'',SelfClosing,Attrs)
      else AddToken(ntOpen,Name,'',SelfClosing,Attrs);
    end;
  finally Attrs.Free end;
end;

function TInkRenderer.HashOptions(const Options: TInkRenderOptions): Cardinal;
var S: string; StyleBits: Integer;
begin
  StyleBits := 0;
  if fsBold in Options.BaseFont.Style then Inc(StyleBits, 1);
  if fsItalic in Options.BaseFont.Style then Inc(StyleBits, 2);
  if fsUnderline in Options.BaseFont.Style then Inc(StyleBits, 4);
  if fsStrikeOut in Options.BaseFont.Style then Inc(StyleBits, 8);
  S := Options.BaseFont.Name + '|' + IntToStr(Options.BaseFont.Height) + '|' +
    IntToStr(Options.BaseFont.Color) + '|' + IntToStr(StyleBits) +
    '|' + IntToStr(Options.Scale) + '|' + IntToStr(Options.LineSpacing) +
    '|' + IntToStr(Options.LineHeight) +
    '|' + IntToStr(Ord(Options.NoWrap)) +
    '|' + IntToStr(Options.Height) + '|' + IntToStr(Integer(Options.VertAlign)) +
    '|' + IntToStr(Options.Borders.Left) + '|' + IntToStr(Options.Borders.Top) +
    '|' + IntToStr(Options.Borders.Right) + '|' + IntToStr(Options.Borders.Bottom);
  Result := HashSource(S);
end;

function TInkRenderer.BaseStyle(const Options: TInkRenderOptions): TInkRenderStyle;
begin
  Result.Face := Options.BaseFont.Name;
  { the control's own font, in pixels: TFont keeps Height and Size in step,
    and pixels are what a page's CSS talks in }
  if Options.BaseFont.Height <> 0 then Result.Size := -Abs(Options.BaseFont.Height)
  else if Options.BaseFont.Size > 0 then Result.Size := -Round(Options.BaseFont.Size*4/3)
  else Result.Size := -13;
  { scaling keeps the sign: a pixel size stays a pixel size }
  if Options.Scale > 0 then Result.Size := InkRenderSmaller(Result.Size, Options.Scale / 100);
  Result.Color := Options.BaseFont.Color; Result.BackColor := clNone;
  Result.Styles := Options.BaseFont.Style; Result.Script := nsNormal;
  Result.LinkIndex := 0; Result.LinkName := '';
  Result.Align := naLeft; Result.Indent := 0;
end;

function TInkRenderer.StyleFor(const Stack: array of TInkRenderStyle): TInkRenderStyle;
var I: Integer;
begin
  { the same convention as everywhere else: points when positive, pixels
    when negative, and nought meaning the level said nothing about size.
    This read "Size > 0" until sizes could be negative, which quietly threw
    away every size on the stack and drew the whole document at ten points
    - headings included. }
  Result.Face := ''; Result.Size := -13;
  Result.Color := clWindowText; Result.BackColor := clNone; Result.Align := naLeft;
  Result.Styles := []; Result.Script := nsNormal; Result.LinkIndex := 0;
  Result.LinkName := ''; Result.Indent := 0;
  for I := 0 to High(Stack) do
  begin
    if Stack[I].Face <> '' then Result.Face := Stack[I].Face;
    if Stack[I].Size <> 0 then Result.Size := Stack[I].Size;
    if Stack[I].Color <> clDefault then Result.Color := Stack[I].Color;
    if Stack[I].BackColor <> clNone then Result.BackColor := Stack[I].BackColor;
    Result.Styles := Result.Styles + Stack[I].Styles;
    if Stack[I].Script <> nsNormal then Result.Script := Stack[I].Script;
    if Stack[I].LinkIndex > 0 then begin Result.LinkIndex := Stack[I].LinkIndex; Result.LinkName := Stack[I].LinkName end;
    if Stack[I].Align <> naLeft then Result.Align := Stack[I].Align;
    if Stack[I].Indent <> 0 then Result.Indent := Stack[I].Indent;
  end;
end;

procedure TInkRenderer.AddStyledText(const Text: string;
  const Style: TInkRenderStyle; APart: Integer);
var N: Integer;
begin
  if Text = '' then Exit; N := Length(FStyled); SetLength(FStyled,N+1);
  FStyled[N].Text := Text; FStyled[N].Style := Style; FStyled[N].Part := APart;
  FStyled[N].Line := -1; FStyled[N].IsImage := False; FStyled[N].ImageIndex := -1;
  FStyled[N].Control := 0; FStyled[N].Meta := '';
end;

procedure TInkRenderer.BuildStyles(const Options: TInkRenderOptions);
var Stack: array of TInkRenderStyle; StackNames: array of string;
  Base, S: TInkRenderStyle; I,N,Part,K: Integer; T: TInkRenderToken;
  procedure Push(const V: TInkRenderStyle; const TagName: string);
  begin
    K := Length(Stack); SetLength(Stack,K+1); SetLength(StackNames,K+1);
    Stack[K] := V; StackNames[K] := TagName;
  end;
  procedure PopMatching(const TagName: string);
  var M: Integer;
  begin
    for M := High(StackNames) downto 1 do
      if StackNames[M] = TagName then
      begin
        SetLength(Stack,M); SetLength(StackNames,M); Exit;
      end;
  end;
  procedure AddControl(Kind: Byte; const Meta: string);
  var Z: Integer;
  begin
    Z := Length(FStyled); SetLength(FStyled, Z+1);
    FStyled[Z].Text := ''; FStyled[Z].Style := StyleFor(Stack);
    FStyled[Z].Part := Part; FStyled[Z].Line := -1;
    FStyled[Z].IsImage := False; FStyled[Z].ImageIndex := -1;
    FStyled[Z].Control := Kind; FStyled[Z].Meta := Meta;
  end;
begin
  SetLength(FStyled,0); FNextLink := 0; Part := 0; Base := BaseStyle(Options);
  SetLength(Stack, 1); SetLength(StackNames, 1); Stack[0] := Base; StackNames[0] := '';
  for I := 0 to High(FTokens) do
  begin
    T := FTokens[I]; S := StyleFor(Stack);
    case T.Kind of
      ntText: AddStyledText(T.Value,S,Part);
      ntBreak: begin AddStyledText(#10,S,Part); Inc(Part) end;
      ntRule: begin AddControl(7,''); Inc(Part) end;
      ntOpen:
        begin
          S := StyleFor(Stack); N := 0;
          if T.Name='b' then S.Styles := S.Styles+[fsBold]
          else if T.Name='i' then S.Styles := S.Styles+[fsItalic]
          else if T.Name='u' then S.Styles := S.Styles+[fsUnderline]
          else if T.Name='s' then S.Styles := S.Styles+[fsStrikeOut]
          else if T.Name='sup' then S.Script := nsSuper
          else if T.Name='sub' then S.Script := nsSub
          else if T.Name='center' then S.Align := naCenter
          else if T.Name='right' then S.Align := naRight
          else if T.Name='left' then S.Align := naLeft
          else if T.Name='ind' then S.Indent := StrToIntDef(InkRenderAttr(T.Attributes,'n'),0)
          else if T.Name='font' then
          begin
            S.Face := InkRenderAttr(T.Attributes,'face');
            { a size the LCL's way: points when positive, pixels when
              negative, and zero meaning the tag said nothing }
            N := StrToIntDef(InkRenderAttr(T.Attributes,'size'),0); if N<>0 then S.Size := N;
            S.Color := InkRenderColor(InkRenderAttr(T.Attributes,'color'),S.Color);
            S.BackColor := InkRenderColor(InkRenderAttr(T.Attributes,'bgcolor'),S.BackColor);
          end
          else if T.Name='a' then begin Inc(FNextLink); S.LinkIndex := FNextLink; S.LinkName := InkRenderAttr(T.Attributes,'href') end
          else if T.Name='img' then begin AddStyledText(#1,S,Part); N := Length(FStyled)-1; FStyled[N].IsImage := True; FStyled[N].ImageIndex := StrToIntDef(InkRenderAttr(T.Attributes,'src'),-1) end
          else if T.Name='table' then AddControl(1,T.Attributes.Text)
          else if T.Name='tr' then AddControl(2,T.Attributes.Text)
          else if (T.Name='td') or (T.Name='th') then
          begin
            if T.Name='th' then S.Styles := S.Styles+[fsBold];
            AddControl(3,T.Attributes.Text);
          end;
          if IsStyleTag(T.Name) and not T.SelfClosing then Push(S,T.Name)
          else if T.Name='p' then
          begin
            if Length(FStyled)>0 then begin AddStyledText(#10,S,Part); AddStyledText(#10,S,Part); Inc(Part) end;
          end;
        end;
      ntClose:
        begin
          PopMatching(T.Name);
          if (T.Name='table') then AddControl(6,'')
          else if T.Name='tr' then AddControl(5,'')
          else if (T.Name='td') or (T.Name='th') then AddControl(4,'');
          { </p> is intentionally inert; the opening paragraph tag owns the break. }
        end;
    end;
  end;
end;

function TInkRenderer.CodepointAt(const S: string; P: Integer; out Bytes: Integer): Cardinal;
var B: Byte; K, Follow: Integer;
begin
  { the lead byte says how many follow it and carries the first few bits;
    each following byte adds six more.  A byte that does not follow the
    rules is passed through as itself rather than guessed at. }
  Bytes := 1; Result := 0;
  if (P<1) or (P>Length(S)) then Exit;
  B := Ord(S[P]);
  if B < $80 then Exit(B);
  if (B and $E0) = $C0 then begin Follow := 1; Result := B and $1F end
  else if (B and $F0) = $E0 then begin Follow := 2; Result := B and $0F end
  else if (B and $F8) = $F0 then begin Follow := 3; Result := B and $07 end
  else Exit(B);
  if P+Follow > Length(S) then Exit(B);
  for K := 1 to Follow do
  begin
    if (Ord(S[P+K]) and $C0) <> $80 then Exit(B);
    Result := (Result shl 6) or Cardinal(Ord(S[P+K]) and $3F);
  end;
  Bytes := Follow+1;
end;

function TInkRenderer.IsCJK(C: Cardinal): Boolean;
begin Result := ((C>=$2E80) and (C<=$A4CF)) or ((C>=$AC00) and (C<=$D7A3)) or ((C>=$F900) and (C<=$FAFF)) or ((C>=$20000) and (C<=$2FA1F)) end;

function TInkRenderer.StyleKey(const AStyle: TInkRenderStyle): string;
var Bits: Integer;
begin
  Bits := InkRenderStyleBits(AStyle.Styles);
  if (AStyle.Size=FKeySize) and (Bits=FKeyBits) and
    (Integer(AStyle.Script)=FKeyScript) and (AStyle.Face=FKeyFace) then
    Exit(FKeyText);
  FKeySize := AStyle.Size; FKeyBits := Bits;
  FKeyScript := Integer(AStyle.Script); FKeyFace := AStyle.Face;
  FKeyText := AStyle.Face+#1+IntToStr(AStyle.Size)+#1+IntToStr(Bits)+#1+
    IntToStr(Integer(AStyle.Script))+#1;
  Result := FKeyText;
end;

function TInkRenderer.MeasureRun(const Canvas: TCanvas; const Run: TInkRenderRun): TSize;
var Old: TFont; S,Key: string; N: Integer;
begin
  S := Run.Text;
  Key := StyleKey(Run.Style)+S;
  { the width itself, beside its key: turning every hit back from a string
    cost more than measuring some of the words did }
  if FWidthKeys.Find(Key,N) then
  begin
    Result:=Types.Size(PtrInt(FWidthKeys.Objects[N]),MetricHeight(Canvas,Run));
    Exit;
  end;
  Old := TFont.Create; Old.PixelsPerInch := Canvas.Font.PixelsPerInch; Old.Assign(Canvas.Font); Canvas.Font.Name := Run.Style.Face;
  InkRenderApplySize(Canvas,Run.Style.Size); Canvas.Font.Style := Run.Style.Styles;
  if Run.Style.Script<>nsNormal then
    InkRenderApplySize(Canvas,InkRenderSmaller(Run.Style.Size,0.7));
  N:=Canvas.TextWidth(S);
  FWidthKeys.AddObject(Key,TObject(PtrInt(N)));
  Result := Types.Size(N,MetricHeight(Canvas,Run));
  Canvas.Font.Assign(Old); Old.Free;
end;

function TInkRenderer.MetricHeight(const Canvas: TCanvas;
  const Run: TInkRenderRun): Integer;
var A,D: Integer;
begin
  Result := Metrics(Canvas,Run,A,D);
end;

function TInkRenderer.Metrics(const Canvas: TCanvas; const Run: TInkRenderRun;
  out AAscent, ADescent: Integer): Integer;
var Key: string; N, Big, Asc10, Desc10: Integer; Old: TFont; TM: TTextMetric;
  { what this call worked out, for the next run to answer from }
  procedure Remember;
  begin
    FMetFace := Run.Style.Face; FMetSize := Run.Style.Size;
    FMetBits := InkRenderStyleBits(Run.Style.Styles);
    FMetScript := Integer(Run.Style.Script); FMetLine := FOpt.LineHeight;
    FMetHeight := Result; FMetAscent := AAscent;
  end;
begin
  { the run before this one nearly always wore the same style: answering
    from that costs a few comparisons instead of a key and a search }
  if (Run.Style.Size=FMetSize) and (Run.Style.Face=FMetFace) and
    (InkRenderStyleBits(Run.Style.Styles)=FMetBits) and
    (Integer(Run.Style.Script)=FMetScript) and (FOpt.LineHeight=FMetLine) and
    (FMetHeight>0) then
  begin
    Result := FMetHeight; AAscent := FMetAscent;
    ADescent := Max(0,Result-AAscent);
    Exit;
  end;
  Key := StyleKey(Run.Style)+IntToStr(FOpt.LineHeight);
  { the height and the ascent packed into the key's own pointer: both fit
    in sixteen bits many times over, and a hit then costs no parsing }
  if FMetricKeys.Find(Key,N) then
  begin
    Big := PtrInt(FMetricKeys.Objects[N]);
    Result := Big and $FFFF;
    AAscent := (Big shr 16) and $FFFF;
    if Result<1 then Result := Canvas.TextHeight('Tg');
    if AAscent<1 then AAscent := Max(1,Round(Result*0.78));
    ADescent := Max(0,Result-AAscent);
    Remember;
    Exit;
  end;
  Old := TFont.Create; Old.PixelsPerInch := Canvas.Font.PixelsPerInch; Old.Assign(Canvas.Font);
  Canvas.Font.Name := Run.Style.Face;
  InkRenderApplySize(Canvas,Run.Style.Size);
  Canvas.Font.Style := Run.Style.Styles;
  if Run.Style.Script<>nsNormal then
    InkRenderApplySize(Canvas,InkRenderSmaller(Run.Style.Size,0.7));
  { the font's own metrics, not a guess: a browser's "normal" line is the
    font's ascent plus its descent, without the internal leading the
    platform adds on top - which is why a page used to come out with every
    line a couple of pixels taller than the same page in a browser.

    Measured at ten times the size and scaled back down.  The platform
    hands back whole pixels, so asking at the size the text is drawn rounds
    the ascent up and the descent up again, and a line ends up most of a
    pixel taller than the font really is.  Over a page of a hundred and
    fifty lines that is a hundred pixels - which is exactly the amount
    LazInk used to run longer than the same page in a browser. }
  Big := InkRenderTimes(Run.Style.Size,10);
  if Run.Style.Script<>nsNormal then Big := InkRenderTimes(InkRenderSmaller(Run.Style.Size,0.7),10);
  InkRenderApplySize(Canvas,Big);
  if GetTextMetrics(Canvas.Handle,TM) then
  begin
    Asc10 := Max(1,TM.tmAscent-TM.tmInternalLeading);
    Desc10 := Max(0,TM.tmDescent);
    Result := Max(1,Round((Asc10+Desc10)/10));
    AAscent := Max(1,Round(Asc10/10));
    ADescent := Max(0,Result-AAscent);
  end
  else
  begin
    InkRenderApplySize(Canvas,Run.Style.Size);
    Result := Canvas.TextHeight('Tg');
    AAscent := Max(1,Round(Result*0.78)); ADescent := Max(0,Result-AAscent);
  end;
  { line-height: the page asked for a line of its own height, so the room
    it added goes half above the text and half below it }
  if FOpt.LineHeight>0 then
  begin
    AAscent := Max(1,AAscent+(FOpt.LineHeight-Result) div 2);
    Result := Max(1,FOpt.LineHeight);
    ADescent := Max(0,Result-AAscent);
  end;
  FMetricKeys.AddObject(Key,
    TObject(PtrInt((Min($FFFF,AAscent) shl 16) or Min($FFFF,Result))));
  Remember;
  Canvas.Font.Assign(Old); Old.Free;
end;

procedure TInkRenderer.LayoutTable(const Canvas: TCanvas;
  const Options: TInkRenderOptions; AStart, AEnd: Integer; var X, Y, Line: Integer;
  ALeft: Integer = -1; AWidth: Integer = -1; ABox: TInkBox = nil);
type
  TCell = record StartRun, EndRun, Row, Col, Span, Down: Integer;
    MeasuredHeight: Integer; Pad: TRect; AttrText: string end;
var
  Cells: array of TCell;
  { how many more rows each column is still covered for by a cell above it }
  Busy: array of Integer;
  I, J, Row, Col, Rows, Cols, CellIndex, TableWidth, Spacing,
    SX, SY, W, H, Want, Extra, Total, CellX, CellY: Integer;
  RowHeights, ColWidths, ColMin, ColMax, RowOffsets, ColOffsets: array of Integer;
  DefaultPad: TRect;
  R: TInkRenderRun; L: TInkRenderLine; Box: TInkBox; St: TInkBoxStyle;
  Drop, MI, CellW, Share, Over, ShareMin, OverMin: Integer; VA: string;
  InCell, FixedLayout, FillWidth: Boolean;
  TableAttrs, CellAttrs, Merge: TStringList;
  WidthText: string; WidthPercent: Integer;

  procedure AddLine(First, Count, Top, Height, Part: Integer);
  begin
    if Count <= 0 then Exit;
    L.Bounds := Rect(0, Top, Options.Width, Top+Height); L.FirstRun := First;
    L.RunCount := Count; L.Align := FLayout.FRuns[First].Style.Align; L.Part := Part;
    SetLength(FLayout.FLines, Length(FLayout.FLines)+1);
    FLayout.FLines[High(FLayout.FLines)] := L;
  end;

  { how tall a table inside a cell comes out: laid out into a layout that
    is then thrown away, so measuring costs nothing on screen }
  function MeasureNested(const Canvas: TCanvas; AStart, AEnd, AWidth: Integer): Integer;
  var Keep: TInkRenderLayout; X2,Y2,L2: Integer;
  begin
    Keep := FLayout; FLayout := TInkRenderLayout.Create;
    try
      X2 := 0; Y2 := 0; L2 := 0;
      LayoutTable(Canvas,FOpt,AStart,AEnd,X2,Y2,L2,0,AWidth);
      Result := Y2;
    finally FLayout.Free; FLayout := Keep end;
  end;

  { Lays one cell's runs out inside AWidth, wrapping the way body text does.
    With Emit off it only measures, which is how a row learns its height
    before anything is placed.  Returns the height the cell needs. }
  { a cell's line has ended: if its words asked to be centered or pushed
    right, move them now that their width is known }
  procedure AlignCellLine(AFirst, AX, AWidth, ACX: Integer; Emit: Boolean);
  var K, Shift: Integer;
  begin
    if not Emit or (AFirst>High(FLayout.FRuns)) then Exit;
    case FLayout.FRuns[AFirst].Style.Align of
      naCenter: Shift := (AWidth-(ACX-AX)) div 2;
      naRight: Shift := AWidth-(ACX-AX);
    else Exit;
    end;
    if Shift<=0 then Exit;
    for K := AFirst to High(FLayout.FRuns) do
    begin
      Inc(FLayout.FRuns[K].Bounds.Left,Shift);
      Inc(FLayout.FRuns[K].Bounds.Right,Shift);
    end;
  end;

  function LayCell(Index, AX, AY, AWidth: Integer; Emit: Boolean): Integer;
  var RunIndex, CX, CY, LineH, RW, P, Start, Bytes,
    Inner, Depth, InnerX, InnerLine, LineFirst, K, Shift: Integer; Pad: TRect;
    Run: TInkRenderRun; Sz: TSize; Text, Atom: string; C: Cardinal;
    Attrs: TStringList; BG, FG: TColor;
  begin
    Pad := Cells[Index].Pad;
    Attrs := TStringList.Create;
    try
      Attrs.Text := Cells[Index].AttrText;
      BG := InkRenderColor(Attrs.Values['bgcolor'], clNone);
      FG := InkRenderColor(Attrs.Values['color'], clNone);
    finally Attrs.Free end;
    CX := AX+Pad.Left; CY := AY+Pad.Top; LineH := 0;
    LineFirst := Length(FLayout.FRuns);
    RunIndex := Cells[Index].StartRun;
    while RunIndex<=Cells[Index].EndRun do
    begin
      if (RunIndex<0) or (RunIndex>=Length(FStyled)) then begin Inc(RunIndex); Continue end;
      { a table inside a cell is this same operation again, in the width the
        cell has - which is the whole point of laying out through a tree }
      if FStyled[RunIndex].Control=1 then
      begin
        Inner := RunIndex+1; Depth := 1;
        while (Inner<=Cells[Index].EndRun) and (Depth>0) do
        begin
          if FStyled[Inner].Control=1 then Inc(Depth)
          else if FStyled[Inner].Control=6 then Dec(Depth);
          if Depth>0 then Inc(Inner);
        end;
        if Inner<=Cells[Index].EndRun then
        begin
          if CX>AX+Pad.Left then
          begin
            if LineH=0 then LineH := Canvas.TextHeight('Tg');
            Inc(CY,LineH); CX := AX+Pad.Left; LineH := 0;
          end;
          InnerX := AX+Pad.Left; InnerLine := Length(FLayout.FLines);
          if Emit then
            LayoutTable(Canvas,FOpt,RunIndex,Inner,InnerX,CY,InnerLine,AX+Pad.Left,AWidth)
          else Inc(CY,MeasureNested(Canvas,RunIndex,Inner,AWidth));
          LineH := 0;
        end;
        RunIndex := Inner+1; Continue;
      end;
      if FStyled[RunIndex].Control<>0 then begin Inc(RunIndex); Continue end;
      Run := FStyled[RunIndex];
      if BG<>clNone then Run.Style.BackColor := BG;
      if FG<>clNone then Run.Style.Color := FG;
      Text := Run.Text;
      P := 1;
      while P<=Length(Text) do
      begin
        if Text[P]=#10 then
        begin
          { a break inside a cell starts another line in the same cell }
          Inc(P);
          if LineH=0 then LineH := Canvas.TextHeight('Tg');
          AlignCellLine(LineFirst,AX+Pad.Left,AWidth,CX,Emit);
          Inc(CY,LineH); CX := AX+Pad.Left; LineH := 0;
          LineFirst := Length(FLayout.FRuns);
          Continue;
        end;
        Start := P;
        if Text[P] in [' ',#9] then
          while (P<=Length(Text)) and (Text[P] in [' ',#9]) do Inc(P)
        else
          while (P<=Length(Text)) and not (Text[P] in [' ',#9,#10]) do
          begin C:=CodepointAt(Text,P,Bytes); Inc(P,Bytes); if IsCJK(C) then Break end;
        Atom := Copy(Text,Start,P-Start);
        Run.Text := Atom; Sz := MeasureRun(Canvas,Run); RW := Sz.cx;
        if (CX>AX+Pad.Left) and (CX+RW>AX+Pad.Left+AWidth) and
          (Atom[1]<>' ') and (Atom[1]<>#9) then
        begin
          if LineH=0 then LineH := Sz.cy;
          AlignCellLine(LineFirst,AX+Pad.Left,AWidth,CX,Emit);
          Inc(CY,LineH); CX := AX+Pad.Left; LineH := 0;
          LineFirst := Length(FLayout.FRuns);
        end;
        if Emit then
        begin
          if Run.Style.Script=nsSuper then
            Run.Bounds := Rect(CX,CY-Sz.cy div 4,CX+RW,CY-Sz.cy div 4+Sz.cy)
          else if Run.Style.Script=nsSub then
            Run.Bounds := Rect(CX,CY+Sz.cy div 4,CX+RW,CY+Sz.cy div 4+Sz.cy)
          else Run.Bounds := Rect(CX,CY,CX+RW,CY+Sz.cy);
          Run.Line := Length(FLayout.FLines);
          Run.Part := Cells[Index].Row*1000+Cells[Index].Col;
          SetLength(FLayout.FRuns,Length(FLayout.FRuns)+1);
          FLayout.FRuns[High(FLayout.FRuns)] := Run;
        end;
        Inc(CX,RW); LineH := Max(LineH,MetricHeight(Canvas,Run));
      end;
      Inc(RunIndex);
    end;
    AlignCellLine(LineFirst,AX+Pad.Left,AWidth,CX,Emit);
    if LineH=0 then LineH := Canvas.TextHeight('Tg');
    Result := (CY+LineH) - AY + Pad.Bottom;
  end;

  { the width a cell would like, and the width it cannot go below (its
    longest single word), both without the padding }
  { the text of one run, added to a line being measured }
  procedure WidthOfRun(const ARun: TInkRenderRun; var ALineW, AWant, ALeast: Integer);
  var P, Start, Bytes: Integer; Run: TInkRenderRun; Text, Atom: string;
    C: Cardinal; Sz: TSize;
  begin
    Run := ARun; Text := Run.Text; P := 1;
    while P<=Length(Text) do
    begin
      if Text[P]=#10 then begin Inc(P); ALineW := 0; Continue end;
      Start := P;
      if Text[P] in [' ',#9] then
        while (P<=Length(Text)) and (Text[P] in [' ',#9]) do Inc(P)
      else
        while (P<=Length(Text)) and not (Text[P] in [' ',#9,#10]) do
        begin C:=CodepointAt(Text,P,Bytes); Inc(P,Bytes); if IsCJK(C) then Break end;
      Atom := Copy(Text,Start,P-Start);
      Run.Text := Atom; Sz := MeasureRun(Canvas,Run);
      Inc(ALineW,Sz.cx); AWant := Max(AWant,ALineW);
      if not (Atom[1] in [' ',#9]) then ALeast := Max(ALeast,Sz.cx);
    end;
  end;

  { where a table that starts at AFrom ends }
  function TableEnd(AFrom, ALimit: Integer): Integer;
  var J, Depth: Integer;
  begin
    J := AFrom+1; Depth := 1;
    while (J<=ALimit) and (Depth>0) do
    begin
      if FStyled[J].Control=1 then Inc(Depth)
      else if FStyled[J].Control=6 then Dec(Depth);
      if Depth>0 then Inc(J);
    end;
    Result := J;
  end;

  { How wide a table nested inside a cell wants to be: the widest its rows
    want, and the least they can be squeezed to.  This used to be skipped
    over - the control runs were ignored and the text inside them measured
    as if it were one long line - so a cell holding a small table asked for
    the width of every one of its cells laid end to end. }
  procedure NestedWidths(AFrom, ATo: Integer; out AWant, ALeast: Integer);
  var I, J, RowWant, RowLeast, CellWant, CellLeast, W2, L2, LineW: Integer;
    InCell: Boolean; Pad, TablePad: TRect; Attrs: TStringList;
  begin
    AWant := 0; ALeast := 0;
    RowWant := 0; RowLeast := 0; CellWant := 0; CellLeast := 0;
    InCell := False; LineW := 0;
    Attrs := TStringList.Create;
    try
      { this table's own default padding, then each cell's over it - a cell
        measured with the outer table's padding comes out narrower than it
        is drawn, and the column it is in is squeezed by the difference }
      Attrs.Text := FStyled[AFrom].Meta;
      TablePad := PadOf(Attrs.Values['cellpadding'],2,FOpt.Scale);
      Pad := TablePad;
      I := AFrom+1;
      while (I<=ATo-1) and (I<Length(FStyled)) do
      begin
        case FStyled[I].Control of
          1: begin
               J := TableEnd(I,ATo-1);
               NestedWidths(I,J,W2,L2);
               Inc(CellWant,W2); CellLeast := Max(CellLeast,L2);
               I := J+1; Continue;
             end;
          2: begin
               AWant := Max(AWant,RowWant); ALeast := Max(ALeast,RowLeast);
               RowWant := 0; RowLeast := 0;
             end;
          3: begin
               InCell := True; CellWant := 0; CellLeast := 0; LineW := 0;
               Attrs.Text := FStyled[I].Meta;
               if Attrs.Values['cellpadding']<>'' then
                 Pad := PadOf(Attrs.Values['cellpadding'],2,FOpt.Scale)
               else Pad := TablePad;
             end;
          4: begin
               InCell := False;
               Inc(RowWant,CellWant+Pad.Left+Pad.Right);
               Inc(RowLeast,CellLeast+Pad.Left+Pad.Right);
             end;
          0: if InCell then WidthOfRun(FStyled[I],LineW,CellWant,CellLeast);
        end;
        Inc(I);
      end;
    finally Attrs.Free end;
    AWant := Max(AWant,RowWant); ALeast := Max(ALeast,RowLeast);
  end;

  procedure CellWidths(Index: Integer; out AWant, ALeast: Integer);
  var RunIndex, LineW, W2, L2, Stop: Integer;
  begin
    AWant := 0; ALeast := 0; LineW := 0;
    RunIndex := Cells[Index].StartRun;
    while RunIndex<=Cells[Index].EndRun do
    begin
      if (RunIndex<0) or (RunIndex>=Length(FStyled)) then Break;
      if FStyled[RunIndex].Control=1 then
      begin
        { a table in this cell is one thing of its own width, not a line
          of loose words }
        Stop := TableEnd(RunIndex,Cells[Index].EndRun);
        NestedWidths(RunIndex,Stop,W2,L2);
        Inc(LineW,W2);
        AWant := Max(AWant,LineW); ALeast := Max(ALeast,L2);
        RunIndex := Stop+1; Continue;
      end;
      if FStyled[RunIndex].Control=0 then
        WidthOfRun(FStyled[RunIndex],LineW,AWant,ALeast);
      Inc(RunIndex);
    end;
  end;

  { a cell's height: the rows it covers, and the spacing between them }
  function CellHeight(Index: Integer): Integer;
  var K: Integer;
  begin
    Result := 0;
    for K := Cells[Index].Row to Min(High(RowHeights),Cells[Index].Row+Cells[Index].Down-1) do
    begin
      Inc(Result,RowHeights[K]);
      if K>Cells[Index].Row then Inc(Result,Spacing);
    end;
  end;
  { the next column in this row that nothing above has claimed }
  procedure SkipBusy(var ACol: Integer);
  begin
    while (ACol<Length(Busy)) and (Busy[ACol]>0) do Inc(ACol);
  end;
  procedure Claim(ACol, ASpan, ADown: Integer);
  var K: Integer;
  begin
    if ACol+ASpan>Length(Busy) then SetLength(Busy,ACol+ASpan);
    { ADown, not ADown-1: every row takes one off the count before it looks
      at it, so the row the cell is in spends the first of them.  Taking one
      off here as well let a rowspan of three cover only two rows, and the
      third row's cells fell back into the column the cell was still in. }
    for K := ACol to ACol+ASpan-1 do Busy[K] := ADown;
  end;
begin
  SetLength(Cells,0); TableAttrs := TStringList.Create; CellAttrs := TStringList.Create;
  Merge := TStringList.Create;
  try
    TableAttrs.Text := FStyled[AStart].Meta;
    FixedLayout := LowerCase(TableAttrs.Values['layout'])='fixed';
    FillWidth := False; WidthPercent := 0; WidthText := Trim(TableAttrs.Values['width']);
    if (WidthText<>'') and (WidthText[Length(WidthText)]='%') then
    begin
      WidthPercent := EnsureRange(StrToIntDef(Copy(WidthText,1,Length(WidthText)-1),0),1,100);
      FillWidth := True;
    end
    else if WidthText<>'' then FillWidth := True;
    Spacing := InkRenderScalePx(StrToIntDef(TableAttrs.Values['cellspacing'],0),Options.Scale);
    { a cell a page says nothing about gets what a browser gives it: room
      enough to clear its border, and no more }
    DefaultPad := PadOf(TableAttrs.Values['cellpadding'],2,Options.Scale);

    { the cells, as ranges into the styled runs - no tree is needed for this }
    Row := -1; Col := 0; Rows := 0; Cols := 0; InCell := False;
    SetLength(Busy,0);
    I := AStart+1;
    while I<=AEnd-1 do
    begin
      { a table inside a cell is that cell's business: step over it whole,
        or its rows and cells would be counted as this table's }
      if FStyled[I].Control=1 then
      begin
        J := I+1; Want := 1;
        while (J<=AEnd-1) and (Want>0) do
        begin
          if FStyled[J].Control=1 then Inc(Want)
          else if FStyled[J].Control=6 then Dec(Want);
          if Want>0 then Inc(J);
        end;
        I := J+1; Continue;
      end;
      case FStyled[I].Control of
        2: begin
             Inc(Row); Rows := Max(Rows,Row+1);
             { a row that starts under a rowspan begins to its right }
             for J := 0 to High(Busy) do if Busy[J]>0 then Dec(Busy[J]);
             Col := 0; SkipBusy(Col);
           end;
        3: if not InCell then
           begin
             InCell := True; CellIndex := Length(Cells); SetLength(Cells,CellIndex+1);
             Cells[CellIndex].StartRun := I+1; Cells[CellIndex].EndRun := I;
             Cells[CellIndex].Row := Max(0,Row); Cells[CellIndex].Col := Col;
             Cells[CellIndex].AttrText := FStyled[I].Meta;
             CellAttrs.Text := FStyled[I].Meta;
             Cells[CellIndex].Span := Max(1,StrToIntDef(CellAttrs.Values['colspan'],1));
             Cells[CellIndex].Down := Max(1,StrToIntDef(CellAttrs.Values['rowspan'],1));
             { the rows this cell reaches down into are the table's too }
             Rows := Max(Rows,Cells[CellIndex].Row+Cells[CellIndex].Down);
             Claim(Cells[CellIndex].Col,Cells[CellIndex].Span,Cells[CellIndex].Down);
             if CellAttrs.Values['cellpadding']<>'' then
               Cells[CellIndex].Pad := PadOf(CellAttrs.Values['cellpadding'],2,Options.Scale)
             else Cells[CellIndex].Pad := DefaultPad;
             Cols := Max(Cols,Col+Cells[CellIndex].Span);
           end;
        4: if InCell then
           begin
             Cells[CellIndex].EndRun := I-1; InCell := False;
             Inc(Col,Cells[CellIndex].Span); SkipBusy(Col);
           end;
      end;
      Inc(I);
    end;
    if InCell then Cells[CellIndex].EndRun := AEnd-1;
    if (Rows=0) or (Cols=0) then Exit;

    SetLength(RowHeights,Rows); SetLength(ColWidths,Cols);
    SetLength(ColMin,Cols); SetLength(ColMax,Cols);
    for I := 0 to Cols-1 do begin ColMin[I] := 0; ColMax[I] := 0 end;
    if ALeft<0 then ALeft := Options.Borders.Left;
    if AWidth>0 then TableWidth := Max(1,AWidth)
    else TableWidth := Max(1,Options.Width-Options.Borders.Left-Options.Borders.Right);
    if (WidthPercent>0) and (WidthPercent<100) then
      TableWidth := Max(1,TableWidth*WidthPercent div 100);
    Dec(TableWidth,Spacing*(Cols+1));
    TableWidth := Max(Cols,TableWidth);

    for I := 0 to High(Cells) do
    begin
      CellWidths(I,W,H);
      Inc(W,Cells[I].Pad.Left+Cells[I].Pad.Right);
      Inc(H,Cells[I].Pad.Left+Cells[I].Pad.Right);
      if Cells[I].Span<=1 then
      begin
        ColMax[Cells[I].Col] := Max(ColMax[Cells[I].Col],W);
        ColMin[Cells[I].Col] := Max(ColMin[Cells[I].Col],H);
      end
      else
      begin
        { a cell across N columns asks each of them for its share, and no
          more: the columns a single-column cell sizes come first.  The
          pixels that do not divide evenly go to the first columns rather
          than being dropped - losing them made a spanning cell a pixel or
          two narrower than its own text, which is a whole wrapped line. }
        Share := (W-Spacing*(Cells[I].Span-1)) div Cells[I].Span;
        Over := (W-Spacing*(Cells[I].Span-1)) mod Cells[I].Span;
        ShareMin := (H-Spacing*(Cells[I].Span-1)) div Cells[I].Span;
        OverMin := (H-Spacing*(Cells[I].Span-1)) mod Cells[I].Span;
        for J := Cells[I].Col to Min(Cols-1,Cells[I].Col+Cells[I].Span-1) do
        begin
          if J-Cells[I].Col<Over then
            ColMax[J] := Max(ColMax[J],Share+1)
          else ColMax[J] := Max(ColMax[J],Share);
          if J-Cells[I].Col<OverMin then
            ColMin[J] := Max(ColMin[J],ShareMin+1)
          else ColMin[J] := Max(ColMin[J],ShareMin);
        end;
      end;
    end;
    for I := 0 to Cols-1 do
    begin
      if ColMax[I]=0 then ColMax[I] := DefaultPad.Left+DefaultPad.Right+12;
      ColMin[I] := Min(ColMin[I],ColMax[I]);
    end;

    Total := 0; for I := 0 to Cols-1 do Inc(Total,ColMax[I]);
    if FixedLayout then
      { equal columns, with the pixels that do not divide evenly given to
        the first of them rather than dropped off the end }
      for I := 0 to Cols-1 do
        if I<TableWidth mod Cols then ColWidths[I] := Max(1,TableWidth div Cols+1)
        else ColWidths[I] := Max(1,TableWidth div Cols)
    else if FillWidth and (Total<TableWidth) then
    begin
      { a table told to fill the width shares the slack out by how much
        wider each column would like to be }
      Extra := TableWidth-Total; Want := 0;
      for I := 0 to Cols-1 do Inc(Want,ColMax[I]);
      for I := 0 to Cols-1 do
        ColWidths[I] := ColMax[I]+Extra*ColMax[I] div Max(1,Want);
    end
    else if Total<=TableWidth then
      for I := 0 to Cols-1 do ColWidths[I] := ColMax[I]
    else
    begin
      { too wide: every column keeps its longest word, and what is left over
        is shared by how much wider each one still wants to be }
      Total := 0; for I := 0 to Cols-1 do Inc(Total,ColMin[I]);
      Extra := TableWidth-Total;
      Want := 0; for I := 0 to Cols-1 do Inc(Want,ColMax[I]-ColMin[I]);
      for I := 0 to Cols-1 do
        if Extra<=0 then ColWidths[I] := ColMin[I]
        else if Want<=0 then ColWidths[I] := ColMin[I]+Extra div Cols
        else ColWidths[I] := ColMin[I]+Extra*(ColMax[I]-ColMin[I]) div Want;
    end;
    for I := 0 to Cols-1 do ColWidths[I] := Max(1,ColWidths[I]);
    { a table never reaches past the room it was given: when even the
      longest words will not fit, the columns share what there is and a word
      may stick out of its cell, which is what a browser does too }
    Total := 0; for I := 0 to Cols-1 do Inc(Total,ColWidths[I]);
    if Total>TableWidth then
      for I := 0 to Cols-1 do
        ColWidths[I] := Max(1,ColWidths[I]*TableWidth div Total);

    { how tall each row has to be, now that the columns are settled }
    for I := 0 to Rows-1 do RowHeights[I] := 0;
    for I := 0 to High(Cells) do
    begin
      W := 0;
      for J := Cells[I].Col to Min(Cols-1,Cells[I].Col+Max(1,Cells[I].Span)-1) do
      begin
        Inc(W,ColWidths[J]);
        if J>Cells[I].Col then Inc(W,Spacing);
      end;
      H := LayCell(I,0,0,Max(1,W-Cells[I].Pad.Left-Cells[I].Pad.Right),False);
      { Columns are final: reuse this content height for rowspan and
        vertical alignment instead of recursively measuring the cell again. }
      Cells[I].MeasuredHeight := H;
      { a cell that reaches down over several rows does not make any one of
        them tall: the rows are sized by the cells that sit in one row, and
        only what is left over is added to the last row it covers }
      if Cells[I].Down<=1 then
        RowHeights[Cells[I].Row] := Max(RowHeights[Cells[I].Row],H);
    end;
    for I := 0 to High(Cells) do
      if Cells[I].Down>1 then
      begin
        H := Cells[I].MeasuredHeight;
        Want := CellHeight(I);
        if H>Want then
        begin
          J := Min(Rows-1,Cells[I].Row+Cells[I].Down-1);
          Inc(RowHeights[J],H-Want);
        end;
      end;
    for I := 0 to Rows-1 do
      if RowHeights[I]=0 then RowHeights[I] := DefaultPad.Top+DefaultPad.Bottom+Canvas.TextHeight('Tg');

    { Prefix offsets keep placement linear in the number of cells rather
      than summing all preceding rows and columns again for every cell. }
    SetLength(RowOffsets,Rows+1); SetLength(ColOffsets,Cols+1);
    RowOffsets[0] := 0; ColOffsets[0] := 0;
    for I := 0 to Rows-1 do RowOffsets[I+1] := RowOffsets[I]+RowHeights[I]+Spacing;
    for I := 0 to Cols-1 do ColOffsets[I+1] := ColOffsets[I]+ColWidths[I]+Spacing;
    { and now place them, each as a box of its own }
    SX := ALeft+Spacing; SY := Y+Spacing;
    for I := 0 to High(Cells) do
    begin
      CellX := SX+ColOffsets[Cells[I].Col];
      CellY := SY+RowOffsets[Cells[I].Row];
      CellW := 0;
      for J := Cells[I].Col to Min(Cols-1,Cells[I].Col+Max(1,Cells[I].Span)-1) do
      begin
        Inc(CellW,ColWidths[J]);
        if J>Cells[I].Col then Inc(CellW,Spacing);
      end;
      J := Length(FLayout.FRuns);
      { the cell's box, with the style it carries: its padding, its colors,
        its borders and how round its corners are.  Two cells in a row can
        differ in every one of them, which is the point. }
      { the cell's own attributes over the table's: a cell that says only
        bgcolor still takes the table's border color, as a cell inherits in
        a browser }
      CellAttrs.Text := TableAttrs.Text;
      Merge.Text := Cells[I].AttrText;
      { MI, not J: J is holding this cell's first run }
      for MI := 0 to Merge.Count-1 do
        if Merge.Names[MI]<>'' then
          CellAttrs.Values[Merge.Names[MI]] := Merge.ValueFromIndex[MI];
      { cellbg is the table's word for "what a cell's background is unless
        the cell says otherwise" }
      if (CellAttrs.Values['bgcolor']='') and (CellAttrs.Values['cellbg']<>'') then
        CellAttrs.Values['bgcolor'] := CellAttrs.Values['cellbg'];
      { a cell that draws its own border is not silenced by a table that
        says it has none: a grid of cards is a borderless table of bordered
        cells, and each card has to keep its outline }
      if (Merge.Values['border']='') and
        ((Merge.Values['sides']<>'') or (Merge.Values['bordercolor']<>'')) then
        CellAttrs.Values['border'] := '';
      if ABox<>nil then
      begin
        Box := ABox.AddChild(ibCell);
        Box.Tag := Cells[I].StartRun; Box.TagEnd := Cells[I].EndRun;
        Box.Meta := CellAttrs.Text;
        St := Box.Style;
        St.Padding := Cells[I].Pad;
        St.BackColor := InkRenderColor(CellAttrs.Values['bgcolor'],clNone);
        St.Color := InkRenderColor(CellAttrs.Values['color'],clNone);
        if LowerCase(Trim(CellAttrs.Values['border']))='none' then
          St.BorderColor := clNone
        else
          St.BorderColor := InkRenderColor(CellAttrs.Values['bordercolor'],clBlack);
        St.Sides := LowerCase(CellAttrs.Values['sides']);
        if St.Sides='' then St.Sides := 'trbl';
        St.Radius := InkRenderScalePx(StrToIntDef(CellAttrs.Values['radius'],0),Options.Scale);
        St.Content := ibTop;
        VA := LowerCase(Trim(CellAttrs.Values['valign']));
        if VA='middle' then St.Content := ibMiddle
        else if VA='bottom' then St.Content := ibBottom;
        Box.Style := St;
        Box.FBoundsForCell(Rect(CellX,CellY,CellX+CellW,
          CellY+CellHeight(I)));
      end;
      { the run the cell is painted from, filled in from that same style }
      R.Text := ''; R.Style := BaseStyle(Options);
      R.Bounds := Rect(CellX,CellY,CellX+CellW,CellY+CellHeight(I));
      R.Line := Length(FLayout.FLines); R.Part := Cells[I].Row*1000+Cells[I].Col;
      R.IsImage := False; R.ImageIndex := -1; R.Control := 8;
      R.Meta := CellAttrs.Text;
      SetLength(FLayout.FRuns,Length(FLayout.FRuns)+1);
      FLayout.FRuns[High(FLayout.FRuns)] := R;
      { how far down the cell its words start, when it is taller than they
        are and it says they should sit low }
      Drop := 0;
      if ABox<>nil then
      begin
        H := Cells[I].MeasuredHeight;
        case Box.Style.Content of
          ibMiddle: Drop := Max(0,(CellHeight(I)-H) div 2);
          ibBottom: Drop := Max(0,CellHeight(I)-H);
        else Drop := 0;   { the top, which is where a cell starts by default }
        end;
      end;
      LayCell(I,CellX,CellY+Drop,Max(1,CellW-Cells[I].Pad.Left-Cells[I].Pad.Right),True);
      AddLine(J,Length(FLayout.FRuns)-J,CellY,CellHeight(I),
        Cells[I].Row*1000+Cells[I].Col);
    end;

    Y := SY; for I := 0 to Rows-1 do Inc(Y,RowHeights[I]+Spacing);
    W := Spacing; for I := 0 to Cols-1 do Inc(W,ColWidths[I]+Spacing);
    X := ALeft+W; Inc(Line);
  finally TableAttrs.Free; CellAttrs.Free; Merge.Free end;
end;

function TInkRenderer.MeasureInline(ABox: TInkBox; const Canvas: TCanvas;
  AWidth, AY: Integer): Integer;
var I,P,Line,First,Count,X,Y,MaxLineH,Avail,W,RunAsc,RunDesc: Integer;
  R: TInkRenderRun; Sz, ImgSz: TSize; Text,Atom: string; Start,Bytes: Integer;
  CanBreak: Boolean;
  C: Cardinal; L: TInkRenderLine;
  { every run on the line is placed so its baseline is at the same height:
    the largest ascent on the line.  The line is that plus the largest
    descent, which is what makes a heading and small text sit together. }
  procedure AlignBaselines(First, Count: Integer; var ALineH: Integer;
    out ABaseline: Integer);
  var K, Asc, Desc, Shift, H: Integer;
  begin
    Asc := 0; Desc := 0;
    for K := First to First+Count-1 do
    begin
      Asc := Max(Asc,FLayout.FRuns[K].Ascent);
      Desc := Max(Desc,FLayout.FRuns[K].Descent);
    end;
    if Asc+Desc>ALineH then ALineH := Asc+Desc;
    ABaseline := Y+Asc;
    for K := First to First+Count-1 do
    begin
      Shift := 0;
      { superscript and subscript are offsets from the line's baseline, and
        they are measured against the line's own ascent so that small text
        beside big text is lifted by the same amount the reader expects }
      if FLayout.FRuns[K].Style.Script=nsSuper then Shift := -(Asc div 3)
      else if FLayout.FRuns[K].Style.Script=nsSub then Shift := Desc;
      H := FLayout.FRuns[K].Bounds.Bottom-FLayout.FRuns[K].Bounds.Top;
      FLayout.FRuns[K].Baseline := ABaseline+Shift;
      FLayout.FRuns[K].Bounds.Top := ABaseline+Shift-FLayout.FRuns[K].Ascent;
      FLayout.FRuns[K].Bounds.Bottom := FLayout.FRuns[K].Bounds.Top+H;
    end;
  end;
  procedure FinishLine(Forced: Boolean = False);
  var K,Shift,Base: Integer;
  begin
    if Count=0 then
    begin
      { <p> asks for two breaks in a row; the second one is a blank line,
        not nothing }
      if Forced then
        Inc(Y,Max(MaxLineH,Canvas.TextHeight('Tg'))+
          InkRenderScalePx(FOpt.LineSpacing,FOpt.Scale));
      Exit;
    end;
    AlignBaselines(First,Count,MaxLineH,Base); L.Baseline := Base; L.Bounds:=Rect(0,Y,Avail,Y+MaxLineH); L.FirstRun:=First; L.RunCount:=Count; L.Align:=FLayout.FRuns[First].Style.Align; L.Part:=FLayout.FRuns[First].Part;
    if L.Align=naCenter then Shift:=(Avail-(X-FOpt.Borders.Left)) div 2 else if L.Align=naRight then Shift:=Avail-(X-FOpt.Borders.Left) else Shift:=0;
    for K:=First to First+Count-1 do begin Inc(FLayout.FRuns[K].Bounds.Left,Shift); Inc(FLayout.FRuns[K].Bounds.Right,Shift); FLayout.FRuns[K].Line:=Line end;
    SetLength(FLayout.FLines,Length(FLayout.FLines)+1); FLayout.FLines[High(FLayout.FLines)]:=L; Inc(Line); Inc(Y,MaxLineH+InkRenderScalePx(FOpt.LineSpacing,FOpt.Scale)); X:=FOpt.Borders.Left; First:=Length(FLayout.FRuns); Count:=0; MaxLineH:=0;
    { a fresh line may break wherever its first words allow }
    CanBreak:=True;
  end;
begin
  { the inline pass, over the runs this box covers and no further }
  Avail:=AWidth; if Avail<1 then Avail:=1;
  X:=FOpt.Borders.Left; Y:=AY; First:=Length(FLayout.FRuns); Count:=0;
  CanBreak:=True;
  { a line is as tall as the words on it, and no taller: starting from the
    canvas font's TextHeight put a floor under every line that the platform
    had already rounded up, which is a pixel a line a browser does not spend }
  Line:=Length(FLayout.FLines); MaxLineH:=0;
  I := ABox.Tag;
  while (I<=ABox.TagEnd) and (I<=High(FStyled)) do
  begin
    R:=FStyled[I];
    if R.Control<>0 then begin Inc(I); Continue end;
    ImgSz:=Types.Size(0,0);
    if R.IsImage then
    begin
      { the picture's own size, kept aside: the run's text is a placeholder
        character and measuring that would say nothing about the picture }
      ImgSz:=Types.Size(InkRenderScalePx(16,FOpt.Scale),InkRenderScalePx(16,FOpt.Scale));
      if (FOpt.Images<>nil) and (R.ImageIndex>=0) and
        (R.ImageIndex<FOpt.Images.Count) then
        ImgSz:=Types.Size(InkRenderScalePx(FOpt.Images.Width,FOpt.Scale),
          InkRenderScalePx(FOpt.Images.Height,FOpt.Scale));
      Text:=#1
    end else Text:=R.Text;
    P:=1;
    while P<=Length(Text) do
    begin
      if Text[P]=#10 then begin Inc(P); FinishLine(True); Continue end;
      Start:=P;
      if Text[P] in [' ',#9] then
        while (P<=Length(Text)) and (Text[P] in [' ',#9]) do Inc(P)
      else
        while (P<=Length(Text)) and not (Text[P] in [' ',#9,#10]) do
        begin C:=CodepointAt(Text,P,Bytes); Inc(P,Bytes); if IsCJK(C) then Break end;
      Atom:=Copy(Text,Start,P-Start); R.Text:=Atom;
      if Count=0 then
      begin
        if odReserved1 in FOpt.OwnerState then
          X:=FOpt.Borders.Left+Round(R.Style.Indent*FOpt.Scale/100)
        else X:=FOpt.Borders.Left+R.Style.Indent;
      end;
      if R.IsImage then Sz:=ImgSz else Sz:=MeasureRun(Canvas,R);
      W:=Sz.cx;
      { a line breaks where the text allows it - after a space, or between
        two CJK characters - and nowhere else.  The end of a run is not a
        break: "<code>x</code>." is one word with a full stop on it, and
        breaking there put the stop alone at the start of the next line. }
      if (Count>0) and CanBreak and not FOpt.NoWrap and
        (X+W>FOpt.Width-FOpt.Borders.Right) and
        (Atom[1]<>' ') and (Atom[1]<>#9) then FinishLine;
      if Count=0 then First:=Length(FLayout.FRuns);
      if R.IsImage then
      begin
        { a picture sits on the baseline, as one does in a browser }
        RunAsc:=Max(1,Sz.cy); RunDesc:=0;
      end
      else Metrics(Canvas,R,RunAsc,RunDesc);
      R.Ascent:=RunAsc; R.Descent:=RunDesc;
      { a provisional place; AlignBaselines settles it when the line ends }
      R.Bounds:=Rect(X,Y,X+W,Y+Sz.cy);
      SetLength(FLayout.FRuns,Length(FLayout.FRuns)+1); FLayout.FRuns[High(FLayout.FRuns)]:=R; Inc(Count); Inc(X,W); MaxLineH:=Max(MaxLineH,RunAsc+RunDesc);
      { where the next break may fall: after whitespace, or after a CJK
        character, which needs no space to break beside }
      CanBreak := (Atom[1]=' ') or (Atom[1]=#9) or R.IsImage;
      if not CanBreak then
      begin
        Bytes := 1; Start := Length(Atom);
        while (Start>1) and ((Ord(Atom[Start]) and $C0)=$80) do Dec(Start);
        CanBreak := IsCJK(CodepointAt(Atom,Start,Bytes));
      end;
    end;
    Inc(I);
  end;
  FinishLine;
  Result:=Y-AY;
end;

function TInkRenderer.MeasureRule(ABox: TInkBox; const Canvas: TCanvas;
  AWidth, AY: Integer): Integer;
var R: TInkRenderRun; L: TInkRenderLine; Gap,First: Integer;
begin
  { a rule stands clear of the text on both sides, as it does in a browser
    and in the old engine }
  R:=FStyled[ABox.Tag]; Gap:=Canvas.TextHeight('Tg');
  R.Bounds:=Rect(FOpt.Borders.Left,AY+Gap,FOpt.Borders.Left+AWidth,AY+Gap+1);
  R.Line:=Length(FLayout.FLines); R.Ascent:=1; R.Descent:=0; R.Baseline:=AY+Gap;
  First:=Length(FLayout.FRuns);
  SetLength(FLayout.FRuns,First+1); FLayout.FRuns[First]:=R;
  L.Bounds:=Rect(0,AY+Gap,AWidth,AY+Gap+1); L.Baseline:=AY+Gap;
  L.FirstRun:=First; L.RunCount:=1; L.Align:=naLeft; L.Part:=R.Part;
  SetLength(FLayout.FLines,Length(FLayout.FLines)+1);
  FLayout.FLines[High(FLayout.FLines)]:=L;
  Result:=Gap*2+1;
end;

function TInkRenderer.MeasureTableBox(ABox: TInkBox; const Canvas: TCanvas;
  AWidth, AY: Integer): Integer;
var X,Y,Line: Integer;
begin
  X:=FOpt.Borders.Left; Y:=AY; Line:=Length(FLayout.FLines);
  LayoutTable(Canvas,FOpt,ABox.Tag,ABox.TagEnd,X,Y,Line,-1,AWidth,ABox);
  Result:=Y-AY;
end;

procedure TInkRenderer.BuildBoxTree;
var I,J,D,SegStart: Integer; Box: TInkBox;
  procedure CloseSegment(Last: Integer);
  begin
    if (SegStart<0) or (Last<SegStart) then begin SegStart:=-1; Exit end;
    Box:=FRoot.AddChild(ibInline); Box.Tag:=SegStart; Box.TagEnd:=Last;
    Box.OnMeasure:=@MeasureInline; SegStart:=-1;
  end;
begin
  { spec 2.1: the document is a tree, and laying it out is one operation on
    a box which calls itself on the children.  The root is a block, a
    stretch of text is an inline box, and a table is a box that measures
    its cells inside the columns it settles on. }
  FreeAndNil(FRoot);
  FRoot:=TInkBox.Create(ibBlock);
  SegStart:=-1; I:=0;
  while I<=High(FStyled) do
  begin
    if FStyled[I].Control=7 then
    begin
      CloseSegment(I-1);
      Box:=FRoot.AddChild(ibRule); Box.Tag:=I; Box.TagEnd:=I;
      Box.OnMeasure:=@MeasureRule; Inc(I); Continue;
    end;
    if FStyled[I].Control=1 then
    begin
      CloseSegment(I-1);
      J:=I+1; D:=1;
      while (J<=High(FStyled)) and (D>0) do
      begin
        if FStyled[J].Control=1 then Inc(D)
        else if FStyled[J].Control=6 then Dec(D);
        if D>0 then Inc(J);
      end;
      if J<=High(FStyled) then
      begin
        Box:=FRoot.AddChild(ibTable); Box.Tag:=I; Box.TagEnd:=J;
        Box.OnMeasure:=@MeasureTableBox;
      end;
      I:=J+1; Continue;
    end;
    if SegStart<0 then SegStart:=I;
    Inc(I);
  end;
  CloseSegment(High(FStyled));
end;

function TInkRenderer.Layout(const Canvas: TCanvas; const Options: TInkRenderOptions): TInkRenderLayout;
var I,P,W,H,Avail,Y: Integer; OptionKey: Cardinal;
begin
  OptionKey := HashOptions(Options);
  FLayoutKey := FSourceHash xor OptionKey xor Cardinal(Options.Width);
  if (FLayout.SourceHash=FLayoutKey) and (FLayout.Width=Options.Width) and
    (FLayout.FScale=Options.Scale) then Exit(FLayout);
  if FStyleKey<>OptionKey then
  begin
    BuildStyles(Options);
    FStyleKey := OptionKey;
  end;
  FOpt := Options;
  FLayout.Clear; FLayout.FSourceHash:=FLayoutKey; FLayout.FWidth:=Options.Width;
  FLayout.FScale:=Options.Scale;
  Avail:=Options.Width-Options.Borders.Left-Options.Borders.Right;
  if Avail<1 then Avail:=1;
  BuildBoxTree;
  { one call, and the tree lays itself out }
  Y := Options.Borders.Top+FRoot.Measure(Canvas,Avail,Options.Borders.Top);
  W:=0;
  for I:=0 to High(FLayout.FRuns) do
  begin
    { the width of what is written: a trailing space is not part of it, and
      a rule is as wide as the column by definition rather than by content }
    if FLayout.FRuns[I].Control=7 then Continue;
    if (FLayout.FRuns[I].Control=0) and not FLayout.FRuns[I].IsImage and
      (Trim(FLayout.FRuns[I].Text)='') then Continue;
    W:=Max(W,FLayout.FRuns[I].Bounds.Right);
  end;
  H:=Y+FOpt.Borders.Bottom;
  if (FOpt.Height>H) and (FOpt.VertAlign<>nvaTop) then
  begin
    if FOpt.VertAlign=nvaCenter then P:=(FOpt.Height-H) div 2
    else P:=FOpt.Height-H;
    for I:=0 to High(FLayout.FRuns) do begin Inc(FLayout.FRuns[I].Bounds.Top,P); Inc(FLayout.FRuns[I].Bounds.Bottom,P) end;
    for I:=0 to High(FLayout.FLines) do begin Inc(FLayout.FLines[I].Bounds.Top,P); Inc(FLayout.FLines[I].Bounds.Bottom,P) end;
  end;
  FLayout.FSize:=Types.Size(Max(0,W+FOpt.Borders.Right),H); Result:=FLayout;
end;

procedure TInkRenderer.Paint(Canvas: TCanvas; const Bounds: TRect; const Options: TInkRenderOptions;
  AOffsetX: Integer; AOffsetY: Integer);
begin
  PaintLayout(Canvas,Bounds,Options,Layout(Canvas,Options),AOffsetX,AOffsetY);
end;

procedure TInkRenderer.PaintLayout(Canvas: TCanvas; const Bounds: TRect;
  const Options: TInkRenderOptions; ALayout: TInkRenderLayout;
  AOffsetX: Integer; AOffsetY: Integer);
var I,J,DX,DY: Integer; L: TInkRenderLine; R: TInkRenderRun; Clip: TRect; C,BG: TColor; DrawRect: TRect;
  BoxAttrs: TStringList; Sides: string; BorderColor: TColor; BorderOn: Boolean; Radius: Integer;
  OldFont: TFont; OldBrushStyle: TBrushStyle; OldBrushColor: TColor;
begin
  Clip:=Bounds; IntersectRect(Clip,Clip,Canvas.ClipRect);
  { the offsets move the text inside Bounds; the clip does not move with it,
    which is what makes them a scroll rather than a second layout }
  DX:=Bounds.Left+AOffsetX; DY:=Bounds.Top+AOffsetY;
  OldFont:=TFont.Create; OldFont.PixelsPerInch:=Canvas.Font.PixelsPerInch; OldFont.Assign(Canvas.Font); OldBrushStyle:=Canvas.Brush.Style; OldBrushColor:=Canvas.Brush.Color; BoxAttrs:=TStringList.Create;
  try
    for I:=0 to High(ALayout.FLines) do begin L:=ALayout.FLines[I]; if (L.Bounds.Bottom+DY<Clip.Top) or (L.Bounds.Top+DY>Clip.Bottom) then Continue;
      for J:=L.FirstRun to L.FirstRun+L.RunCount-1 do begin
        R:=ALayout.FRuns[J];
        if (R.Bounds.Right+DX<Clip.Left) or (R.Bounds.Left+DX>Clip.Right) then Continue;
        DrawRect:=Rect(R.Bounds.Left+DX,R.Bounds.Top+DY,R.Bounds.Right+DX,R.Bounds.Bottom+DY);
        if R.Control=8 then
        begin
          BoxAttrs.Text:=R.Meta; BG:=InkRenderColor(BoxAttrs.Values['bgcolor'],clNone);
          { a table with nothing said about its borders gets a grid;
            border="none" is how a page asks for none }
          BorderOn:=LowerCase(Trim(BoxAttrs.Values['border']))<>'none';
          Sides:=LowerCase(BoxAttrs.Values['sides']); if Sides='' then Sides:='trbl';
          Radius:=InkRenderScalePx(StrToIntDef(BoxAttrs.Values['radius'],0),Options.Scale);
          BorderColor:=InkRenderColor(BoxAttrs.Values['bordercolor'],clBlack);
          { a cell with no background and no border has nothing to draw, and
            asking the canvas to draw it anyway is how an empty card ended up
            with an outline }
          if (BG=clNone) and not BorderOn then Continue;
          if (Radius>0) and (Sides='trbl') then
          begin
            { a rounded box is filled and outlined in one go: a square fill
              behind it would show in the corners the round cuts off }
            if BG<>clNone then begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=BG end
            else Canvas.Brush.Style:=bsClear;
            if BorderOn then Canvas.Pen.Color:=BorderColor
            else if BG<>clNone then Canvas.Pen.Color:=BG
            else Canvas.Pen.Style:=psClear;
            Canvas.Pen.Width:=1;
            Canvas.RoundRect(DrawRect.Left,DrawRect.Top,DrawRect.Right,DrawRect.Bottom,Radius,Radius);
            Canvas.Pen.Style:=psSolid;
            Continue;
          end;
          if BG<>clNone then begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=BG; Canvas.FillRect(DrawRect) end;
          if BorderOn then
          begin
            Canvas.Pen.Color:=BorderColor; Canvas.Pen.Width:=1;
            begin
              if Pos('t',Sides)>0 then Canvas.Line(DrawRect.Left,DrawRect.Top,DrawRect.Right,DrawRect.Top);
              if Pos('r',Sides)>0 then Canvas.Line(DrawRect.Right,DrawRect.Top,DrawRect.Right,DrawRect.Bottom);
              if Pos('b',Sides)>0 then Canvas.Line(DrawRect.Left,DrawRect.Bottom,DrawRect.Right,DrawRect.Bottom);
              if Pos('l',Sides)>0 then Canvas.Line(DrawRect.Left,DrawRect.Top,DrawRect.Left,DrawRect.Bottom);
            end;
          end;
          Continue;
        end;
        if Assigned(Options.OnRun) and (R.Control=0) then
        begin
          R.Bounds:=DrawRect; R.Part:=Options.RunPart;
          Options.OnRun(R);
        end;
        Canvas.Font.Name:=R.Style.Face; InkRenderApplySize(Canvas,R.Style.Size);
        Canvas.Font.Style:=R.Style.Styles;
        { a superscript is drawn as small as it was measured; its place on
          the line was settled from its baseline }
        if R.Style.Script<>nsNormal then
          InkRenderApplySize(Canvas,InkRenderSmaller(R.Style.Size,0.7));
        C:=R.Style.Color; BG:=R.Style.BackColor;
        if R.Style.LinkIndex>0 then begin C:=Options.LinkColor; if Options.LinkUnderline then Canvas.Font.Style:=Canvas.Font.Style+[fsUnderline]; if R.Style.LinkIndex=Options.HoverIndex then begin C:=Options.HoverColor; BG:=Options.HoverBackColor; if Options.HoverUnderline then Canvas.Font.Style:=Canvas.Font.Style+[fsUnderline] end end;
        if odSelected in Options.OwnerState then begin C:=clHighlightText; BG:=clHighlight end
        else if odDisabled in Options.OwnerState then begin C:=clGrayText; BG:=clNone end;
        Canvas.Font.Color:=C;
        { a run with a background of its own fills it; one without draws
          over what is there.  Saying so every time is what keeps a
          highlight from running on into the words after it: TextOut paints
          its own background whenever the brush is solid. }
        if BG<>clNone then
        begin
          Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=BG;
          Canvas.FillRect(DrawRect);
        end
        else Canvas.Brush.Style:=bsClear;
        if R.Control=7 then begin Canvas.Pen.Color:=C; Canvas.Line(DrawRect.Left,DrawRect.Top,DrawRect.Right,DrawRect.Top); Continue end;
        if R.IsImage and (Options.Images<>nil) and (R.ImageIndex>=0) and (R.ImageIndex<Options.Images.Count) then
          Options.Images.Draw(Canvas,DrawRect.Left,DrawRect.Top,R.ImageIndex)
        else if not R.IsImage then Canvas.TextOut(DrawRect.Left,DrawRect.Top,R.Text);
      end;
    end;
  finally
    { the color first and the style second, always: setting a brush color
      makes it solid as a side effect, so restoring the style before the
      color undoes the restore and every caller gets its canvas back with a
      solid brush }
    Canvas.Font.Assign(OldFont); Canvas.Brush.Color:=OldBrushColor;
    Canvas.Brush.Style:=OldBrushStyle; OldFont.Free; BoxAttrs.Free;
  end;
end;

procedure TInkRenderer.ReportRuns(const Options: TInkRenderOptions;
  AOffsetX: Integer; AOffsetY: Integer);
begin
  ReportLayoutRuns(Options,FLayout,AOffsetX,AOffsetY);
end;

procedure TInkRenderer.ReportLayoutRuns(const Options: TInkRenderOptions;
  ALayout: TInkRenderLayout; AOffsetX: Integer; AOffsetY: Integer);
var I: Integer; R: TInkRenderRun;
begin
  if not Assigned(Options.OnRun) or (ALayout=nil) then Exit;
  for I := 0 to High(ALayout.FRuns) do
  begin
    R := ALayout.FRuns[I];
    if R.Control<>0 then Continue;
    R.Bounds := Rect(R.Bounds.Left+AOffsetX,R.Bounds.Top+AOffsetY,
      R.Bounds.Right+AOffsetX,R.Bounds.Bottom+AOffsetY);
    R.Part := Options.RunPart;
    Options.OnRun(R);
  end;
end;

function TInkRenderer.HitTest(const Canvas: TCanvas; X, Y: Integer;
  AOffsetX: Integer; AOffsetY: Integer): TInkRenderHit;
begin
  Result := HitTestLayout(Canvas,X,Y,FLayout,AOffsetX,AOffsetY);
end;

function TInkRenderer.HitTestLayout(const Canvas: TCanvas; X, Y: Integer;
  ALayout: TInkRenderLayout; AOffsetX: Integer; AOffsetY: Integer): TInkRenderHit;
var I,K,Lo,Hi,Mid: Integer; R: TInkRenderRun; W: Integer; F: TFont; L: TInkRenderLine;
begin
  Result.OnLink := False; Result.LinkIndex := 0; Result.LinkName := '';
  Result.LinkText := ''; Result.RunIndex := -1; Result.CharacterOffset := 0;
  if ALayout=nil then Exit;
  Dec(X,AOffsetX); Dec(Y,AOffsetY);
  F:=TFont.Create; F.PixelsPerInch:=Canvas.Font.PixelsPerInch; F.Assign(Canvas.Font); try
    for K:=0 to High(ALayout.FLines) do
    begin
      L:=ALayout.FLines[K];
      if (Y<L.Bounds.Top) or (Y>L.Bounds.Bottom) then Continue;
      for I:=L.FirstRun to L.FirstRun+L.RunCount-1 do
      begin
        R:=ALayout.FRuns[I];
        if not PtInRect(R.Bounds,Point(X,Y)) or (R.Style.LinkIndex=0) then Continue;
        Result.OnLink:=True; Result.LinkIndex:=R.Style.LinkIndex; Result.LinkName:=R.Style.LinkName; Result.RunIndex:=I; Result.CharacterOffset:=0; Result.LinkText:='';
        for W:=0 to High(ALayout.FRuns) do
          if ALayout.FRuns[W].Style.LinkIndex=R.Style.LinkIndex then Result.LinkText:=Result.LinkText+ALayout.FRuns[W].Text;
        F.Assign(Canvas.Font); Canvas.Font.Name:=R.Style.Face;
        InkRenderApplySize(Canvas,R.Style.Size); Canvas.Font.Style:=R.Style.Styles;
        Lo:=0; Hi:=Length(R.Text);
        while Lo<Hi do
        begin
          Mid:=(Lo+Hi+1) div 2;
          if R.Bounds.Left+Canvas.TextWidth(Copy(R.Text,1,Mid))<=X then Lo:=Mid else Hi:=Mid-1;
        end;
        Result.CharacterOffset:=Lo; Exit;
      end;
      { and on to the next line that covers this point.  A table's cells are
        each a line of their own with the same top and bottom, so stopping at
        the first one to match would only ever find the leftmost column -
        which is exactly what used to happen. }
    end;
  finally Canvas.Font.Assign(F); F.Free end;
end;

end.
