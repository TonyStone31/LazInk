{ InkHtml — HTML canvas rendering for LazInk.
  SPDX-License-Identifier: MPL-1.1

  The contents of this file are subject to the Mozilla Public License
  Version 1.1 (the "License"); you may not use this file except in
  compliance with the License. You may obtain a copy of the License at
  https://www.mozilla.org/MPL/1.1/ or in LICENSES/MPL-1.1.txt.

  Software distributed under the License is distributed on an "AS IS"
  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
  License for the specific language governing rights and limitations
  under the License.

  The Original Code is portions of Project JEDI's JVCL HTML drawing code:

  JvHTControls.PAS, released on 2002-07-04.
  The Initial Developer is Andrei Prygounkov.
  Copyright (c) 1999, 2002 Andrei Prygounkov. All Rights Reserved.
  Listed contributors: Maciej Kaczkowski, Timo Tegtmeier, Andreas Hausladen.

  JvJVCLUtils.PAS, released on 2002-09-24.
  The Initial Developers are Fedor Koshevnikov, Igor Pavluk and Serge Korolev.
  Copyright (c) 1997, 1998 Fedor Koshevnikov, Igor Pavluk and Serge Korolev.
  Copyright (c) 2001,2002 SGB Software. All Rights Reserved.

  Contributor(s): Project JEDI/JVCL contributors; wp (standalone Lazarus
  extraction and adaptations); LazInk contributors (subsequent modifications).

  Upstream: https://github.com/project-jedi/jvcl
  Provenance and full upstream notices: THIRD_PARTY_NOTICES.md.
  Modification history and dates: docs/RENDERER_CHANGES.md.
  Keep these notices intact in redistributions. }
unit InkHtml;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList, LCLIntf, LCLType, Types;

type
  TJvHTMLCalcType = (htmlShow, htmlCalcWidth, htmlCalcHeight, htmlHyperLink);

  { How the whole block of text sits inside the rectangle it is given. }
  TInkVertAlign = (ivaTop, ivaCenter, ivaBottom);
  TInkHorzAlign = (ihaLeft, ihaCenter, ihaRight);

  { Told about each run of text as it is laid out: the text as drawn, where
    (ALeft, ATop is the top of the line it sits on), how big, which line of
    its part it is on, and the font it is drawn in.  APart numbers the pieces
    a text with tables in it is laid out in - the text around the tables and
    each cell - from the options' RunPart on. }
  THTMLRunEvent = procedure(const AText: string; ALeft, ATop, AWidth, AHeight,
    ALine, APart: integer; AFont: TFont) of object;

  { Everything about a render beyond the text itself. Passed as one record so
    that adding a knob does not mean changing five overloads; DefaultHTMLOptions
    fills it with the behavior the plain HTMLDrawText has always had. }
  THTMLOptions = record
    SuperSubScriptRatio: Double;
    Scale: Integer;
    { extra pixels between lines }
    LineSpacing: Integer;
    { margins taken off the drawing rectangle: Left, Top, Right, Bottom }
    Borders: TRect;
    { where the block sits when it is smaller than the rectangle }
    VertAlign: TInkVertAlign;
    HorzAlign: TInkHorzAlign;
    { supplies <img src="n"> }
    Images: TCustomImageList;
    { how <a href=..> spans are painted. clDefault / clNone leave the
      surrounding color alone. }
    LinkColor: TColor;
    LinkBackColor: TColor;
    LinkUnderline: Boolean;
    { and how the one under the mouse is painted instead. HoverIndex is the
      ordinal of the link within this text, counting from 1; 0 means none. }
    HoverIndex: Integer;
    HoverColor: TColor;
    HoverBackColor: TColor;
    HoverUnderline: Boolean;
    { when set, told where every run of text goes - how a control finds
      the character under the mouse.  Measuring calls made inside the
      renderer do not report. }
    OnRun: THTMLRunEvent;
    RunPart: Integer;
  end;

  { What the mouse was over, filled in when CalcType is htmlHyperLink. }
  THTMLHitInfo = record
    OnLink: Boolean;
    LinkName: string;      // the href
    LinkText: string;      // the text between <a> and </a>
    LinkIndex: Integer;    // ordinal of the link, counting from 1
  end;

type
  { How <a href=..> spans look. Published as a sub-property so the whole thing
    can be set in the Object Inspector. }
  TInkLinkStyle = class(TPersistent)
  private
    FColor: TColor;
    FBackColor: TColor;
    FUnderline: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetColor(AValue: TColor);
    procedure SetBackColor(AValue: TColor);
    procedure SetUnderline(AValue: Boolean);
    procedure Changed;
  public
    constructor Create(ADefaultUnderline: Boolean = False);
    procedure Assign(Source: TPersistent); override;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    { clDefault leaves the surrounding text color alone. None of these three
      declare a default: the hover style is born underlined and the normal one
      is not, so a single declared default would be wrong for one of them and
      the writer would drop the value. }
    property Color: TColor read FColor write SetColor;
    { clNone means no background at all }
    property BackColor: TColor read FBackColor write SetBackColor;
    property Underline: Boolean read FUnderline write SetUnderline;
  end;

  { Margins between the control's edge and its text. }
  TInkBorders = class(TPersistent)
  private
    FLeft, FTop, FRight, FBottom: Integer;
    FOnChange: TNotifyEvent;
    procedure SetSide(AIndex, AValue: Integer);
    function GetSide(AIndex: Integer): Integer;
  public
    procedure Assign(Source: TPersistent); override;
    procedure SetAll(AValue: Integer);
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    property Left: Integer index 0 read GetSide write SetSide default 0;
    property Top: Integer index 1 read GetSide write SetSide default 0;
    property Right: Integer index 2 read GetSide write SetSide default 0;
    property Bottom: Integer index 3 read GetSide write SetSide default 0;
  end;

function DefaultHTMLOptions(ASuperSubScriptRatio: Double = 0.7;
  AScale: Integer = 100): THTMLOptions;
{ Gathers a control's published properties into the record the renderer wants.
  Every LazInk control builds its options through this, so they all behave the
  same way. }
function InkOptions(ARatio: Double; AScale, ALineSpacing: Integer;
  ABorders: TInkBorders; AImages: TCustomImageList;
  ALink, AHover: TInkLinkStyle; AHoverIndex: Integer): THTMLOptions;

{ The full renderer. Everything else in this unit is a convenience wrapper. }
procedure HTMLDrawTextEx3(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; const AOpts: THTMLOptions;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer;
  out Width, Height: integer; out AHit: THTMLHitInfo);

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const AOpts: THTMLOptions);
function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string;
  const AOpts: THTMLOptions): TSize;
function HTMLTextHeightOpt(Canvas: TCanvas; const Text: string;
  const AOpts: THTMLOptions): integer;
{ Hit-tests Text drawn in Rect against a mouse position. }
function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: integer): THTMLHitInfo;

procedure HTMLDrawTextEx(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; out Width: integer; CalcType: TJvHTMLCalcType;
  MouseX, MouseY: integer; out MouseOnLink: boolean; var LinkName: string;
  SuperSubScriptRatio: double; Scale: integer = 100); overload;
procedure HTMLDrawTextEx2(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; out Width, Height: integer;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer; out MouseOnLink: boolean;
  var LinkName: string; SuperSubScriptRatio: double; Scale: integer = 100); overload;
procedure HTMLDrawText(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100);
procedure HTMLDrawTextHL(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; MouseX, MouseY: integer; SuperSubScriptRatio: double;
  Scale: integer = 100);
function HTMLPlainText(const Text: string): string;
function HTMLTextExtent(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): TSize;
function HTMLTextWidth(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): integer;
function HTMLTextHeight(Canvas: TCanvas; const Text: string;
  SuperSubScriptRatio: double; Scale: integer = 100): integer;
function HTMLPrepareText(const Text: string): string;
function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;
{ Turns text into markup-safe text and back. Escape only touches the three
  characters that would otherwise be read as markup; Unescape understands the
  entities this renderer emits and accepts. }
{ Black or white, whichever can be read on ABackground. }
function HTMLContrastColor(ABackground: TColor): TColor;
{ AColor nudged APercent toward its opposite end - lighter if it is dark,
  darker if it is light. For zebra striping that follows the current theme
  instead of assuming a white background. }
function HTMLShadeColor(AColor: TColor; APercent: Integer): TColor;
function HTMLEscape(const Text: string): string;
function HTMLUnescape(const Text: string): string;
{ Re-flows Text so that no rendered line is wider than MaxWidth, by inserting
  <br> at word boundaries. Formatting tags open across an inserted break stay
  in effect, exactly as they would without wrapping. Canvas must already carry
  the font the text will be drawn with. }
function HTMLWordWrap(Canvas: TCanvas; const Text: string; MaxWidth: integer;
  SuperSubScriptRatio: double; Scale: integer = 100): string;
{ True when AChar starts a Chinese, Japanese or Korean character. Those scripts
  do not separate words with spaces, so every character is a place a line may
  break - without this, CJK text never wraps at all. }
function HTMLIsCJK(const AChar: string): boolean;


implementation

uses
  Math, Forms;

const
  cBR = '<BR>';
  cBR2 = '<BR/>';
  cHR = '<HR>';
  cTagBegin = '<';
  cTagEnd = '>';
  cLT = '<';
  cGT = '>';
  //cQuote = '"';
  cCENTER = 'CENTER';
  cRIGHT = 'RIGHT';
  cHREF = 'HREF';
  cIND = 'IND';
  cCOLOR = 'COLOR';
  cBGCOLOR = 'BGCOLOR';
  cFACE = 'FACE';
  cSRC = 'SRC';
  { same length as BGCOLOR and contains no 'COLOR' }
  cBGMask = '#######';
  { stands in for a literal ampersand between prepare and draw }
  cAmpMark = #1;
  cPOpen = '<P>';
  cPOpen2 = '<P/>';
  cPClose = '</P>';

var
  { GetTextMetrics is slow on some widgetsets (GTK3 asks Pango every time),
    and a render asks for every run of text, so the answer is remembered
    for the last few fonts. }
  MetricKeys: array[0..15] of string;
  MetricValues: array[0..15] of integer;
  MetricNext: integer = 0;

function CanvasMaxTextHeight(Canvas: TCanvas): integer;
var
  tt: TTextMetric;
  Key: string;
  I: integer;
begin
  with Canvas.Font do
    Key := Name + '|' + IntToStr(Height) + '|' + IntToStr(Size) + '|' +
      IntToStr(Integer(Style)) + '|' + IntToStr(PixelsPerInch) + '|' +
      IntToStr(Ord(Pitch)) + '|' + IntToStr(Ord(Quality));
  for I := 0 to High(MetricKeys) do
    if MetricKeys[I] = Key then
      Exit(MetricValues[I]);
  // (ahuser) Qt returns different values for TextHeight('Ay') and TextHeigth(#1..#255)
  GetTextMetrics(Canvas.Handle, tt{%H-});
  Result := tt.tmHeight;
  MetricKeys[MetricNext] := Key;
  MetricValues[MetricNext] := Result;
  MetricNext := (MetricNext + 1) mod Length(MetricKeys);
end;

// moved from JvHTControls and renamed
function HTMLPrepareText(const Text: string): string;
type
  THtmlCode = record
    Html: string;
    { plain string, not UTF8String: the replacements below are already UTF-8
      byte sequences, and letting the compiler transcode a UTF8String into the
      default ansi codepage on assignment is what turned © into Â© }
    Html2: string;
  end;
const
  Conversions: array [0..5] of THtmlCode = (
    (Html: '&quot;'; Html2: '"'),
    (Html: '&reg;'; Html2: #$C2#$AE),
    (Html: '&copy;'; Html2: #$C2#$A9),
    (Html: '&trade;'; Html2: #$E2#$84#$A2),
    (Html: '&euro;'; Html2: #$E2#$82#$AC),
    (Html: '&nbsp;'; Html2: ' ')
    );
var
  I: integer;
begin
  Result := Text;
  // "&amp;" stands aside as a marker until every other entity has been read,
  // so that "&amp;lt;" ends up as the literal text "&lt;" instead of being
  // unescaped twice into "<". The marker turns back into "&" at draw time.
  Result := StringReplace(Result, '&amp;', cAmpMark, [rfReplaceAll, rfIgnoreCase]);
  for I := Low(Conversions) to High(Conversions) do
    // the replacements are already UTF-8, which is what the LCL wants; running
    // them through Utf8ToAnsi mangled them into mojibake
    Result := StringReplace(Result, Conversions[I].Html,
      Conversions[I].Html2, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  // only <BR> can be new line
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  // only <BR> can be new line

  // <p>..</p> paragraphs. </p> only closes, so it vanishes; <p> starts a new
  // paragraph, which is a line break plus a blank line. A <p> at the very
  // beginning has nothing to separate itself from, so it just goes away.
  Result := StringReplace(Result, cPClose, '', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cPOpen2, cBR + cBR, [rfReplaceAll, rfIgnoreCase]);
  // Skip only real blanks looking for a leading <p>. TrimLeft would do it in
  // one line, but it also eats everything below #32 - including the ampersand
  // marker parked above.
  I := 1;
  while (I <= Length(Result)) and ((Result[I] = ' ') or (Result[I] = #9)) do
    Inc(I);
  if SameText(Copy(Result, I, Length(cPOpen)), cPOpen) then
    Delete(Result, I, Length(cPOpen));
  Result := StringReplace(Result, cPOpen, cBR + cBR, [rfReplaceAll, rfIgnoreCase]);

  Result := StringReplace(Result, cBR, sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cBR2, sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  // Fixes <BR/>, but not <BR />!
  Result := StringReplace(Result, cHR, cHR + sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  // fixed <HR><BR>
end;

function HTMLContrastColor(ABackground: TColor): TColor;
var
  RGB: LongInt;
begin
  // a control left at clDefault is painted in the window color; taken
  // literally, clDefault comes out black
  if ABackground = clDefault then ABackground := clWindow;
  RGB := ColorToRGB(ABackground);
  // Rec. 601 luma, which is close enough to how bright a color looks
  if (Red(RGB) * 299 + Green(RGB) * 587 + Blue(RGB) * 114) div 1000 >= 140 then
    Result := clBlack
  else
    Result := clWhite;
end;

function HTMLShadeColor(AColor: TColor; APercent: Integer): TColor;
var
  RGB: LongInt;
  R, G, B, D: Integer;
begin
  if AColor = clDefault then AColor := clWindow;
  RGB := ColorToRGB(AColor);
  R := Red(RGB); G := Green(RGB); B := Blue(RGB);
  if HTMLContrastColor(AColor) = clBlack then
    D := -((255 * APercent) div 100)     // light color: darken it
  else
    D := (255 * APercent) div 100;       // dark color: lighten it
  R := EnsureRange(R + D, 0, 255);
  G := EnsureRange(G + D, 0, 255);
  B := EnsureRange(B + D, 0, 255);
  Result := RGBToColor(R, G, B);
end;

function HTMLEscape(const Text: string): string;
begin
  Result := StringReplace(Text, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

function HTMLUnescape(const Text: string): string;
begin
  Result := StringReplace(Text, '&lt;', '<', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&nbsp;', ' ', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&reg;', #$C2#$AE, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&copy;', #$C2#$A9, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&trade;', #$E2#$84#$A2, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&euro;', #$E2#$82#$AC, [rfReplaceAll, rfIgnoreCase]);
  // last, so that "&amp;lt;" comes back as the literal text "&lt;"
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll, rfIgnoreCase]);
end;

function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;
type
  TRGBA = packed record
    R, G, B, A: byte;
  end;
var
  c: Int32;
begin
  if AText = '' then
  begin
    Result := ADefColor;
    exit;
  end;

  if AText[1] = '#' then
    AText[1] := '$';
  if TryStrToInt(AText, c) then
  begin
    TRgba(Result).R := TRgba(c).B;
    TRgba(Result).G := TRgba(c).G;
    TRgba(Result).B := TRgba(c).R;
    TRgba(Result).A := 0;
  end
  else
  begin
    if Lowercase(Copy(AText, 1, 2)) <> 'cl' then
      AText := 'cl' + AText;
    Result := StringToColorDef(AText, ADefColor);
  end;
end;

function HTMLBeforeTag(var Str: string; DeleteToTag: boolean = False): string;
begin
  if Pos(cTagBegin, Str) > 0 then
  begin
    Result := Copy(Str, 1, Pos(cTagBegin, Str) - 1);
    if DeleteToTag then
      Delete(Str, 1, Pos(cTagBegin, Str) - 1);
  end
  else
  begin
    Result := Str;
    if DeleteToTag then
      Str := '';
  end;
end;

function GetChar(const Str: string; Pos: word; Up: boolean = False): char;
begin
  if Length(Str) >= Pos then
    Result := Str[Pos]
  else
    Result := ' ';
  if Up then
    Result := UpCase(Result);
end;

function HTMLDeleteTag(const Str: string): string;
begin
  Result := Str;
  if (GetChar(Result, 1) = cTagBegin) and (Pos(cTagEnd, Result) > 1) then
    Delete(Result, 1, Pos(cTagEnd, Result));
end;

// wp: Made Width and MouseOnLink out parameters (were "var" in the original)
// to silence the compiler
procedure HTMLDrawTextEx(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; out Width: integer; CalcType: TJvHTMLCalcType;
  MouseX, MouseY: integer; out MouseOnLink: boolean; var LinkName: string;
  SuperSubScriptRatio: double; Scale: integer);
var
  H: integer;
begin
  HTMLDrawTextEx2(Canvas, Rect, State, Text, Width, H, CalcType,
    MouseX, MouseY, MouseOnLink,
    LinkName, SuperSubScriptRatio, Scale);
  if CalcType = htmlCalcHeight then
    Width := H;
end;

type
  TScriptPosition = (spNormal, spSuperscript, spSubscript);

// wp: Make Width, Height and MouseOnLink "out" parameters
// (they were "var" in the original) to silence the compiler
{ TInkLinkStyle }

constructor TInkLinkStyle.Create(ADefaultUnderline: Boolean = False);
begin
  inherited Create;
  FColor := clBlue;
  FBackColor := clNone;
  FUnderline := ADefaultUnderline;
end;

procedure TInkLinkStyle.Changed;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkLinkStyle.SetColor(AValue: TColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  Changed;
end;

procedure TInkLinkStyle.SetBackColor(AValue: TColor);
begin
  if FBackColor = AValue then Exit;
  FBackColor := AValue;
  Changed;
end;

procedure TInkLinkStyle.SetUnderline(AValue: Boolean);
begin
  if FUnderline = AValue then Exit;
  FUnderline := AValue;
  Changed;
end;

procedure TInkLinkStyle.Assign(Source: TPersistent);
begin
  if Source is TInkLinkStyle then
  begin
    FColor := TInkLinkStyle(Source).Color;
    FBackColor := TInkLinkStyle(Source).BackColor;
    FUnderline := TInkLinkStyle(Source).Underline;
    Changed;
  end
  else
    inherited Assign(Source);
end;

{ TInkBorders }

function TInkBorders.GetSide(AIndex: Integer): Integer;
begin
  case AIndex of
    0: Result := FLeft;
    1: Result := FTop;
    2: Result := FRight;
  else
    Result := FBottom;
  end;
end;

procedure TInkBorders.SetSide(AIndex, AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if GetSide(AIndex) = AValue then Exit;
  case AIndex of
    0: FLeft := AValue;
    1: FTop := AValue;
    2: FRight := AValue;
  else
    FBottom := AValue;
  end;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkBorders.SetAll(AValue: Integer);
begin
  SetSide(0, AValue);
  SetSide(1, AValue);
  SetSide(2, AValue);
  SetSide(3, AValue);
end;

procedure TInkBorders.Assign(Source: TPersistent);
begin
  if Source is TInkBorders then
  begin
    FLeft := TInkBorders(Source).Left;
    FTop := TInkBorders(Source).Top;
    FRight := TInkBorders(Source).Right;
    FBottom := TInkBorders(Source).Bottom;
    if Assigned(FOnChange) then FOnChange(Self);
  end
  else
    inherited Assign(Source);
end;

function InkOptions(ARatio: Double; AScale, ALineSpacing: Integer;
  ABorders: TInkBorders; AImages: TCustomImageList;
  ALink, AHover: TInkLinkStyle; AHoverIndex: Integer): THTMLOptions;
begin
  Result := DefaultHTMLOptions(ARatio, AScale);
  Result.LineSpacing := ALineSpacing;
  Result.Images := AImages;
  Result.HoverIndex := AHoverIndex;
  if ABorders <> nil then
  begin
    Result.Borders.Left := ABorders.Left;
    Result.Borders.Top := ABorders.Top;
    Result.Borders.Right := ABorders.Right;
    Result.Borders.Bottom := ABorders.Bottom;
  end;
  if ALink <> nil then
  begin
    Result.LinkColor := ALink.Color;
    Result.LinkBackColor := ALink.BackColor;
    Result.LinkUnderline := ALink.Underline;
  end;
  if AHover <> nil then
  begin
    Result.HoverColor := AHover.Color;
    Result.HoverBackColor := AHover.BackColor;
    Result.HoverUnderline := AHover.Underline;
  end;
end;

function DefaultHTMLOptions(ASuperSubScriptRatio: Double = 0.7;
  AScale: Integer = 100): THTMLOptions;
begin
  Result.SuperSubScriptRatio := ASuperSubScriptRatio;
  Result.Scale := AScale;
  Result.LineSpacing := 0;
  Result.Borders := Rect(0, 0, 0, 0);
  Result.VertAlign := ivaTop;
  Result.HorzAlign := ihaLeft;
  Result.Images := nil;
  // clBlue and an underline is what a link has always looked like here
  Result.LinkColor := clBlue;
  Result.LinkBackColor := clNone;
  Result.LinkUnderline := False;
  Result.HoverIndex := 0;
  Result.HoverColor := clBlue;
  Result.HoverBackColor := clNone;
  Result.HoverUnderline := True;
  Result.OnRun := nil;
  Result.RunPart := 0;
end;

{ The old entry point, kept so that nothing outside this unit had to change. }
procedure HTMLDrawTextEx2(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; out Width, Height: integer;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer; out MouseOnLink: boolean;
  var LinkName: string; SuperSubScriptRatio: double; Scale: integer);
var
  Hit: THTMLHitInfo;
begin
  HTMLDrawTextEx3(Canvas, Rect, State, Text,
    DefaultHTMLOptions(SuperSubScriptRatio, Scale), CalcType, MouseX, MouseY,
    Width, Height, Hit);
  MouseOnLink := Hit.OnLink;
  LinkName := Hit.LinkName;
end;

procedure HTMLDrawInline(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; const AOpts: THTMLOptions;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer;
  out Width, Height: integer; out AHit: THTMLHitInfo);
const
  DefaultLeft = 0; // (ahuser) was 2
var
  SuperSubScriptRatio: double;
  Scale: integer;
  MouseOnLink: boolean;
  LinkName: string;
  LinkIndex: integer;      // ordinal of the <a> being drawn, from 1
  CurLinkText: string;     // display text of the link being drawn
  OldLinkBrush: TColor;    // brush/transparency to restore at </a>
  OldLinkTrans: boolean;
  ImgIdx: integer;
  BlockW, BlockH: integer;
  PreOpts: THTMLOptions;
  PreHit: THTMLHitInfo;
  PreRect: TRect;
  vText, vM, TagPrp, Prp, TempLink: string;
  vCount: integer;
  vStr: TStringList;
  Selected: boolean;
  Alignment: TAlignment;
  Trans, IsLink: boolean;
  CurLeft: integer;
  // for begin and end
  OldFontStyles: TFontStyles;
  OldFontColor: TColor;
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldAlignment: TAlignment;
  OldFont: TFont;
  OldWidth: integer;
  OldFontSize: integer;
  OldFontName: string;
  // for font style
  RemFontColor, RemBrushColor: TColor;
  RemFontSize: integer;
  RemFontName: string;
  TagRaw: string;
  TagNoBg: string;
  ScriptPosition: TScriptPosition;
  LineH: integer;   // tallest glyph box seen on the line being built

  function ExtractPropertyValue(const Tag: string; PropName: string): string;
  var
    I: integer;
  begin
    Result := '';
    PropName := UpperCase(PropName);
    if Pos(PropName, UpperCase(Tag)) > 0 then
    begin
      Result := Copy(Tag, Pos(PropName, UpperCase(Tag)) + Length(PropName), Length(Tag));
      if Pos('"', Result) <> 0 then
      begin
        Result := Copy(Result, Pos('"', Result) + 1, Length(Result));
        Result := Copy(Result, 1, Pos('"', Result) - 1);
      end
      else
      if Pos('''', Result) <> 0 then
      begin
        Result := Copy(Result, Pos('''', Result) + 1, Length(Result));
        Result := Copy(Result, 1, Pos('''', Result) - 1);
      end
      else
      begin
        Result := Trim(Result);
        Delete(Result, 1, 1);
        Result := Trim(Result);
        I := 1;
        while (I < Length(Result)) and (Result[I + 1] <> ' ') do
          Inc(I);
        Result := Copy(Result, 1, I);
      end;
    end;
  end;

  procedure ApplyLinkStyle(AColor, ABackColor: TColor; AUnderline: boolean);
  begin
    if not Assigned(Canvas) then Exit;
    if AColor <> clDefault then
      Canvas.Font.Color := AColor;
    if ABackColor <> clNone then
    begin
      Canvas.Brush.Color := ABackColor;
      Trans := False;
    end;
    if AUnderline then
      Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
  end;

  procedure Style(const Style: TFontStyle; const Include: boolean);
  begin
    if Assigned(Canvas) then
      if Include then
        Canvas.Font.Style := Canvas.Font.Style + [Style]
      else
        Canvas.Font.Style := Canvas.Font.Style - [Style];
  end;

  function CalcPos(const Str: string): integer;
  begin
    case Alignment of
      taRightJustify:
        Result := (Rect.Right - Rect.Left) - HTMLTextWidth(Canvas,
          Rect, State, Str, SuperSubScriptRatio, Scale);
      taCenter:
        Result := DefaultLeft + ((Rect.Right - Rect.Left) -
          HTMLTextWidth(Canvas, Rect, State, Str, SuperSubScriptRatio,
          Scale)) div 2;
      else
        Result := DefaultLeft;
    end;
    if Result <= 0 then
      Result := DefaultLeft;
  end;

  procedure Draw(const M: string);
  var
    Width, Height: integer;
    R: TRect;
    OriginalFontSize: integer;
    lineHeight: integer;
  begin
    R := Rect;
    Inc(R.Left, CurLeft);
    if Assigned(Canvas) then
    begin
      lineHeight := Canvas.TextHeight('Tg');
      OriginalFontSize := Canvas.Font.Size;
      try
        if ScriptPosition <> spNormal then
          Canvas.Font.Size := Round(Canvas.Font.Size * SuperSubScriptRatio);

        Width := Canvas.TextWidth(M);
        Height := CanvasMaxTextHeight(Canvas);
        // a line carrying <font size="18"> is as tall as the 18pt text in it,
        // not as tall as whatever font happened to be current at its end
        if Height > LineH then
          LineH := Height;

        if ScriptPosition = spSubscript then
          R.Top := R.Top + lineHeight - Height - 1;

        if Assigned(AOpts.OnRun) then
          AOpts.OnRun(M, R.Left, Rect.Top, Width, Height, vCount,
            AOpts.RunPart, Canvas.Font);

        if IsLink then
        begin
          CurLinkText := CurLinkText + M;
          if not MouseOnLink then
            if (MouseY >= R.Top) and (MouseY <= R.Top + Height) and
              (MouseX >= R.Left) and (MouseX <= R.Left + Width) and
              ((MouseY > 0) or (MouseX > 0)) then
            begin
              MouseOnLink := True;
              LinkName := TempLink;
              AHit.LinkIndex := LinkIndex;
            end;
        end;

        if CalcType = htmlShow then
        begin
          if Trans then
            Canvas.Brush.Style := bsClear; // for transparent
          Canvas.TextOut(R.Left, R.Top, M);
        end;
        CurLeft := CurLeft + Width;
      finally
        Canvas.Font.Size := OriginalFontSize;
      end;
    end;
  end;

  { <img src="n"> - one entry of the supplied image list, sitting on the line
    like an oversized character. }
  procedure DrawImage(AIndex: integer);
  var
    W, H: integer;
  begin
    if (AOpts.Images = nil) or (AIndex < 0) or (AIndex >= AOpts.Images.Count) then
      Exit;
    W := AOpts.Images.Width;
    H := AOpts.Images.Height;
    if H > LineH then
      LineH := H;                  // the line has to make room for it
    if (CalcType = htmlShow) and Assigned(Canvas) then
      AOpts.Images.Draw(Canvas, Rect.Left + CurLeft, Rect.Top, AIndex, True);
    CurLeft := CurLeft + W;
  end;

  procedure NewLine(Always: boolean = False);
  var
    H: integer;
  begin
    if Assigned(Canvas) then
      if Always or (vCount < vStr.Count - 1) then
      begin
        Width := Max(Width, CurLeft);
        CurLeft := DefaultLeft;
        H := LineH;
        if H = 0 then                  // an empty line still occupies one
          H := CanvasMaxTextHeight(Canvas);
        Rect.Top := Rect.Top + H + AOpts.LineSpacing;
        LineH := 0;
      end;
  end;

begin
  SuperSubScriptRatio := AOpts.SuperSubScriptRatio;
  Scale := AOpts.Scale;
  if Scale = 0 then Scale := 100;
  LinkIndex := 0;
  CurLinkText := '';
  OldLinkBrush := clNone;
  OldLinkTrans := True;
  ImgIdx := -1;
  MouseOnLink := False;
  LinkName := '';
  AHit.OnLink := False;
  AHit.LinkName := '';
  AHit.LinkText := '';
  AHit.LinkIndex := 0;

  // borders simply shrink the area the text is laid out in
  Inc(Rect.Left, AOpts.Borders.Left);
  Inc(Rect.Top, AOpts.Borders.Top);
  Dec(Rect.Right, AOpts.Borders.Right);
  Dec(Rect.Bottom, AOpts.Borders.Bottom);

  // Placing the block anywhere but top-left means knowing how big it is before
  // a single word is drawn, so measure it first with the placement switched
  // off - otherwise this would call itself forever.
  if (CalcType = htmlShow) and (Canvas <> nil) and
    ((AOpts.VertAlign <> ivaTop) or (AOpts.HorzAlign <> ihaLeft)) then
  begin
    PreOpts := AOpts;
    PreOpts.OnRun := nil;
    PreOpts.VertAlign := ivaTop;
    PreOpts.HorzAlign := ihaLeft;
    PreOpts.Borders.Left := 0;
    PreOpts.Borders.Top := 0;
    PreOpts.Borders.Right := 0;
    PreOpts.Borders.Bottom := 0;
    PreRect.Left := 0;
    PreRect.Top := 0;
    PreRect.Right := Rect.Right - Rect.Left;
    PreRect.Bottom := 0;
    HTMLDrawTextEx3(Canvas, PreRect, State, Text, PreOpts, htmlCalcWidth,
      0, 0, BlockW, BlockH, PreHit);
    case AOpts.VertAlign of
      ivaCenter: Inc(Rect.Top, Max(0, ((Rect.Bottom - Rect.Top) - BlockH) div 2));
      ivaBottom: Inc(Rect.Top, Max(0, (Rect.Bottom - Rect.Top) - BlockH));
      ivaTop: ;
    end;
    case AOpts.HorzAlign of
      ihaCenter: Inc(Rect.Left, Max(0, ((Rect.Right - Rect.Left) - BlockW) div 2));
      ihaRight: Inc(Rect.Left, Max(0, (Rect.Right - Rect.Left) - BlockW));
      ihaLeft: ;
    end;
  end;

  // (p3) remove warnings
  OldFontColor := 0;
  OldBrushColor := 0;
  OldBrushStyle := bsClear;
  RemFontSize := 0;
  RemFontColor := 0;
  RemBrushColor := 0;
  RemFontName := '';
  OldFontSize := 0;
  OldFontName := '';
  OldAlignment := taLeftJustify;
  OldFont := TFont.Create;

  if Canvas <> nil then
  begin
    if Lowercase(Canvas.Font.Name) = 'default' then
      Canvas.Font.Name := Screen.SystemFont.Name;
    if Canvas.Font.Size = 0 then
      Canvas.Font.Size := Screen.SystemFont.Size;
    OldFontStyles := Canvas.Font.Style;
    OldFontColor := Canvas.Font.Color;
    OldBrushColor := Canvas.Brush.Color;
    OldBrushStyle := Canvas.Brush.Style;
    //  OldAlignment  := Alignment;
    RemFontColor := Canvas.Font.Color;
    RemBrushColor := Canvas.Brush.Color;
    RemFontSize := Canvas.Font.Size;
    RemFontName := Canvas.Font.Name;
    OldFontSize := Canvas.Font.Size;
    OldFontName := Canvas.Font.Name;
  end;

  vStr := TStringList.Create;
  try
    Alignment := taLeftJustify;
    IsLink := False;
    MouseOnLink := False;
    vText := Text;
    vStr.Text := HTMLPrepareText(vText);
    LinkName := '';
    TempLink := '';
    ScriptPosition := spNormal;

    Selected := (odSelected in State) or (odDisabled in State);
    Trans := (Canvas.Brush.Style = bsClear) and not selected;

    Width := DefaultLeft;
    CurLeft := DefaultLeft;
    LineH := 0;

    vM := '';
    for vCount := 0 to vStr.Count - 1 do
    begin
      //      vText := HTMLPrepareText(vStr[vCount]);
      vText := vStr[vCount];
      CurLeft := CalcPos(vText);
      while vText <> '' do
      begin
        vM := HTMLBeforeTag(vText, True);
        vM := StringReplace(vM, '&lt;', cLT, [rfReplaceAll, rfIgnoreCase]);
        // <--+ this must be here
        vM := StringReplace(vM, '&gt;', cGT, [rfReplaceAll, rfIgnoreCase]); // <--/
        vM := StringReplace(vM, cAmpMark, '&', [rfReplaceAll]);
        if GetChar(vText, 1) = cTagBegin then
        begin
          if vM <> '' then
            Draw(vM);
          if Pos(cTagEnd, vText) = 0 then
            Insert(cTagEnd, vText, 2);
          if GetChar(vText, 2) = '/' then
          begin
            case GetChar(vText, 3, True) of
              'A':
              begin
                if IsLink and (AHit.LinkIndex = LinkIndex) and
                  (AHit.LinkText = '') then
                  AHit.LinkText := CurLinkText;
                IsLink := False;
                CurLinkText := '';
                Canvas.Font.Assign(OldFont);
                if OldLinkBrush <> clNone then
                  Canvas.Brush.Color := OldLinkBrush;
                Trans := OldLinkTrans;
              end;
              'B':
                Style(fsBold, False);
              'I':
                Style(fsItalic, False);
              'U':
                Style(fsUnderline, False);
              'S':
              begin
                ScriptPosition := spNormal;
                Style(fsStrikeOut, False);
              end;
              'C', 'R', 'L':
              begin   // </center> </right> </left>
                TagPrp := UpperCase(Copy(vText, 3, Pos(cTagEnd, vText) - 3));
                // back to the default from the next line on. CurLeft must not
                // be touched here: the line this tag closes is still being
                // drawn, and resetting the pen would also zero its width.
                if (TagPrp = cCENTER) or (TagPrp = cRIGHT) or (TagPrp = 'LEFT') then
                  Alignment := taLeftJustify;
              end;
              'F':
              begin
                if not Selected then // restore old colors
                begin
                  Canvas.Font.Color := RemFontColor;
                  Canvas.Brush.Color := RemBrushColor;
                  Canvas.Font.Size := RemFontSize;
                  Canvas.Font.Name := RemFontName;
                  Trans := True;
                end;
              end;
            end;
          end
          else
          begin
            case GetChar(vText, 2, True) of
              'A':
              begin
                if GetChar(vText, 3, True) = 'L' then // ALIGN
                begin
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  if Pos(cCENTER, TagPrp) > 0 then
                    Alignment := taCenter
                  else
                  if Pos(cRIGHT, TagPrp) > 0 then
                    Alignment := taRightJustify
                  else
                    Alignment := taLeftJustify;
                  CurLeft := DefaultLeft;
                  if CalcType in [htmlShow, htmlHyperLink] then
                    CurLeft := CalcPos(vText);
                end
                else
                begin   // A HREF
                  TagPrp := Copy(vText, 2, Pos(cTagEnd, vText) - 2);
                  if Pos(cHREF, UpperCase(TagPrp)) > 0 then
                  begin
                    IsLink := True;
                    Inc(LinkIndex);
                    CurLinkText := '';
                    OldFont.Assign(Canvas.Font);
                    OldLinkBrush := Canvas.Brush.Color;
                    OldLinkTrans := Trans;
                    TempLink := ExtractPropertyValue(TagPrp, cHREF);
                    // the link under the mouse gets to look different from
                    // the rest, which is the whole point of a hover style
                    if not Selected then
                      if LinkIndex = AOpts.HoverIndex then
                        ApplyLinkStyle(AOpts.HoverColor, AOpts.HoverBackColor,
                          AOpts.HoverUnderline)
                      else
                        ApplyLinkStyle(AOpts.LinkColor, AOpts.LinkBackColor,
                          AOpts.LinkUnderline);
                  end;
                end;
              end;
              'C', 'R', 'L':
                // <center> <right> <left>: the ALIGN branch above handles the
                // <align=..> spelling, these are the ones people actually type
                begin
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  if (TagPrp = cCENTER) or (TagPrp = cRIGHT) or (TagPrp = 'LEFT') then
                  begin
                    if TagPrp = cCENTER then
                      Alignment := taCenter
                    else if TagPrp = cRIGHT then
                      Alignment := taRightJustify
                    else
                      Alignment := taLeftJustify;
                    // only re-place the pen while the line is still empty:
                    // moving it after something has been drawn would strand it
                    if (CurLeft = DefaultLeft) and
                      (CalcType in [htmlShow, htmlHyperLink]) then
                      CurLeft := CalcPos(vText);
                  end;
                end;
              'B':
                Style(fsBold, True);
              'I':
                if GetChar(vText, 3, True) = 'N' then //IND="%d"
                begin
                  TagPrp := Copy(vText, 2, Pos(cTagEnd, vText) - 2);
                  CurLeft := StrToIntDef(ExtractPropertyValue(TagPrp, cIND), 0);
                  if odReserved1 in State then
                    CurLeft := Round((CurLeft * Scale) div 100);
                end
                else if GetChar(vText, 3, True) = 'M' then // IMG SRC="n"
                begin
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  ImgIdx := StrToIntDef(ExtractPropertyValue(TagPrp, cSRC), -1);
                  DrawImage(ImgIdx);
                end
                else
                  Style(fsItalic, True); // ITALIC
              'U':
                Style(fsUnderline, True);
              'S':
              begin
                if GetChar(vText, 4, True) = 'P' then
                begin
                  ScriptPosition := spSuperscript;
                end
                else if GetChar(vText, 4, True) = 'B' then
                begin
                  ScriptPosition := spSubscript;
                end
                else
                begin
                  ScriptPosition := spNormal;
                  Style(fsStrikeOut, True);
                end;
              end;
              'H':
                if (GetChar(vText, 3, True) = 'R') and Assigned(Canvas) then // HR
                begin
                  if odDisabled in State then // only when disabled
                    Canvas.Pen.Color := Canvas.Font.Color;
                  OldWidth := Canvas.Pen.Width;
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  Canvas.Pen.Width :=
                    StrToIntDef(ExtractPropertyValue(TagPrp, 'SIZE'), 1); // ex HR="10"
                  if odReserved1 in State then
                    Canvas.Pen.Width := Round((Canvas.Pen.Width * Scale) div 100);
                  if CalcType = htmlShow then
                  begin
                    Canvas.MoveTo(Rect.Left, Rect.Top + CanvasMaxTextHeight(Canvas));
                    Canvas.LineTo(Rect.Right, Rect.Top + CanvasMaxTextHeight(Canvas));
                  end;
                  Rect.Top := Rect.Top + 1 + Canvas.Pen.Width;
                  Canvas.Pen.Width := OldWidth;
                  NewLine(HTMLDeleteTag(vText) <> '');
                end;
              'F':
                if (Pos(cTagEnd, vText) > 0) and (not Selected) and
                  Assigned(Canvas) {and (CalcType in [htmlShow, htmlHyperLink])} then // F from FONT
                begin
                  TagRaw := Copy(vText, 2, Pos(cTagEnd, vText) - 2);
                  TagPrp := UpperCase(TagRaw);
                  // "BGCOLOR" contains "COLOR", so a tag carrying only a
                  // bgcolor would otherwise read as setting the font color
                  // too - and text painted in its own background is invisible.
                  // Mask the longer name out before looking for the shorter.
                  TagNoBg := StringReplace(TagPrp, cBGCOLOR, cBGMask,
                    [rfReplaceAll]);
                  RemFontColor := Canvas.Font.Color;
                  RemBrushColor := Canvas.Brush.Color;
                  RemFontName := Canvas.Font.Name;

                  if Pos(cCOLOR, TagNoBg) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagNoBg, cCOLOR);
                    Canvas.Font.Color := HTMLStringToColor(Prp);
                  end;
                  if Pos(cBGCOLOR, TagPrp) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagPrp, cBGCOLOR);
                    if UpperCase(Prp) = 'CLNONE' then
                      Trans := True
                    else
                    begin
                      Canvas.Brush.Color := HTMLStringToColor(Prp);
                      Trans := False;
                      // a highlighter that hides the text it highlights is no
                      // use: with no color asked for in this same tag, pick
                      // one that reads on the background just set
                      if Pos(cCOLOR, TagNoBg) = 0 then
                        Canvas.Font.Color :=
                          HTMLContrastColor(Canvas.Brush.Color);
                    end;
                  end;
                  if Pos('SIZE', TagPrp) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagPrp, 'SIZE');
                    Canvas.Font.Size := StrToIntDef(Prp, 2){ * Canvas.Font.Size div 2};
                  end;
                  if Pos(cFACE, TagPrp) > 0 then
                  begin
                    // read the face from the tag as typed - a font family name
                    // is not case insensitive to the font matcher
                    Prp := Trim(ExtractPropertyValue(TagRaw, cFACE));
                    if Prp <> '' then
                      Canvas.Font.Name := Prp;
                  end;
                end;
            end;
          end;
          vText := HTMLDeleteTag(vText);
          vM := '';
        end;
      end;
      if vM <> '' then
        Draw(vM);
      NewLine;
      vM := '';
    end;
  finally
    if Canvas <> nil then
    begin
      Canvas.Font.Style := OldFontStyles;
      Canvas.Font.Color := OldFontColor;
      // an unclosed <font size=..> or face=.. must not leak out onto the
      // canvas and grow every following measurement
      Canvas.Font.Size := OldFontSize;
      if OldFontName <> '' then
        Canvas.Font.Name := OldFontName;
      Canvas.Brush.Color := OldBrushColor;
      Canvas.Brush.Style := OldBrushStyle;
      Alignment := OldAlignment;
  {    Canvas.Font.Color := RemFontColor;
      Canvas.Brush.Color:= RemBrushColor;}
    end;
    FreeAndNil(vStr);
    FreeAndNil(OldFont);
  end;
  Width := Max(Width, CurLeft - DefaultLeft);
  Height := Rect.Top + Max(LineH, CanvasMaxTextHeight(Canvas));

  AHit.OnLink := MouseOnLink;
  AHit.LinkName := LinkName;
  if MouseOnLink and (AHit.LinkText = '') then
    AHit.LinkText := CurLinkText;   // text ran to the end without a </a>
end;

{$I inktables.inc}

// wp: I made this a procedure - it was a function in the original with the
// result being unassigned.
procedure HTMLDrawText(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer);
var
  W: integer;
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, W, htmlShow, 0, 0, S, St,
    SuperSubScriptRatio, Scale);
end;

// wp: I made this a procedure - it was a function in the original with the
// result being unassigned.
procedure HTMLDrawTextHL(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; MouseX, MouseY: integer; SuperSubScriptRatio: double;
  Scale: integer);
var
  W: integer;
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, W, htmlShow, MouseX,
    MouseY, S, St, SuperSubScriptRatio, Scale);
end;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const AOpts: THTMLOptions);
var
  W, H: integer;
  Hit: THTMLHitInfo;
begin
  HTMLDrawTextEx3(Canvas, Rect, State, Text, AOpts, htmlShow, 0, 0, W, H, Hit);
end;

function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string;
  const AOpts: THTMLOptions): TSize;
var
  Hit: THTMLHitInfo;
begin
  HTMLDrawTextEx3(Canvas, Rect, State, Text, AOpts, htmlCalcWidth, 0, 0,
    Result.cx, Result.cy, Hit);
  if Result.cy = 0 then
    Result.cy := CanvasMaxTextHeight(Canvas);
  Inc(Result.cy);
  // The borders are part of the space the text needs. The top one is already
  // in the height, because it moved the first line down; the width is measured
  // from the left border inwards, so neither side of it is counted yet.
  Inc(Result.cx, AOpts.Borders.Left + AOpts.Borders.Right);
  Inc(Result.cy, AOpts.Borders.Bottom);
end;

function HTMLTextHeightOpt(Canvas: TCanvas; const Text: string;
  const AOpts: THTMLOptions): integer;
var
  W: integer;
  R: TRect;
  Hit: THTMLHitInfo;
begin
  R := Rect(0, 0, 0, 0);
  HTMLDrawTextEx3(Canvas, R, [], Text, AOpts, htmlCalcHeight, 0, 0, W, Result, Hit);
  if Result = 0 then
    Result := CanvasMaxTextHeight(Canvas);
  Inc(Result);
  Inc(Result, AOpts.Borders.Bottom);   // the top border is already in Result
end;

function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: integer): THTMLHitInfo;
var
  W, H: integer;
begin
  HTMLDrawTextEx3(Canvas, Rect, [], Text, AOpts, htmlHyperLink, MouseX, MouseY,
    W, H, Result);
end;

function HTMLPlainText(const Text: string): string;
var
  S, Tag: string;
  P: Integer;
begin
  Result := '';
  S := HTMLPrepareText(Text);
  while Pos(cTagBegin, S) > 0 do
  begin
    Result := Result + Copy(S, 1, Pos(cTagBegin, S) - 1);
    if Pos(cTagEnd, S) > 0 then
    begin
      P := Pos(cTagBegin, S);
      Tag := LowerCase(Copy(S, P, Pos(cTagEnd, S)-P+1));
      if (Tag = '</td>') or (Tag = '</th>') then Result := Result + #9;
      if (Tag = '</tr>') or (Tag = '<br>') or (Tag = '<br/>') or
        (Tag = '</p>') then Result := Result + LineEnding;
      Delete(S, 1, Pos(cTagEnd, S));
    end
    else
      Delete(S, 1, Pos(cTagBegin, S));
  end;
  Result := Result + S;
  // now that no tag delimiters are left, an unescaped '<' cannot be mistaken
  // for the start of one
  Result := StringReplace(Result, '&lt;', cLT, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '&gt;', cGT, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cAmpMark, '&', [rfReplaceAll]);
end;

function HTMLTextExtent(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): TSize;
var
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx2(Canvas, Rect, State, Text, Result.cx, Result.cy,
    htmlCalcWidth, 0, 0, S, St, SuperSubScriptRatio, Scale);
  if Result.cy = 0 then
    Result.cy := CanvasMaxTextHeight(Canvas);
  Inc(Result.cy);
end;

function HTMLTextWidth(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): integer;
var
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, Result, htmlCalcWidth,
    0, 0, S, St, SuperSubScriptRatio, Scale);
end;

function HTMLTextHeight(Canvas: TCanvas; const Text: string;
  SuperSubScriptRatio: double; Scale: integer = 100): integer;
var
  S: boolean;
  St: string = '';
  R: TRect;
begin
  R := Rect(0, 0, 0, 0);
  HTMLDrawTextEx(Canvas, R, [], Text, Result, htmlCalcHeight, 0, 0,
    S, St, SuperSubScriptRatio, Scale);
  if Result = 0 then
    Result := CanvasMaxTextHeight(Canvas);
  Inc(Result);
end;


{ The Unicode codepoint starting at byte P, and how many bytes it occupies.
  ALen is never 0, so a caller advancing by it cannot loop forever. }
function InkCodepointAt(const S: string; P: integer; out ALen: integer): Cardinal;
var
  B: byte;
  L: integer;
begin
  ALen := 1;
  Result := 0;
  L := Length(S);
  if (P < 1) or (P > L) then Exit;
  B := Ord(S[P]);
  if B < $80 then
    Result := B
  else if (B and $E0) = $C0 then
  begin
    ALen := 2;
    if P + 1 <= L then
      Result := ((B and $1F) shl 6) or (Ord(S[P + 1]) and $3F);
  end
  else if (B and $F0) = $E0 then
  begin
    ALen := 3;
    if P + 2 <= L then
      Result := ((B and $0F) shl 12) or ((Ord(S[P + 1]) and $3F) shl 6) or
        (Ord(S[P + 2]) and $3F);
  end
  else if (B and $F8) = $F0 then
  begin
    ALen := 4;
    if P + 3 <= L then
      Result := ((B and $07) shl 18) or ((Ord(S[P + 1]) and $3F) shl 12) or
        ((Ord(S[P + 2]) and $3F) shl 6) or (Ord(S[P + 3]) and $3F);
  end
  else
    Result := B;      // stray continuation byte - take it as one character
end;

function InkIsCJKCodepoint(ACp: Cardinal): boolean;
begin
  Result :=
    ((ACp >= $1100) and (ACp <= $11FF)) or      // Hangul Jamo
    ((ACp >= $2E80) and (ACp <= $A4CF)) or      // radicals, kana, ideographs, Yi
    ((ACp >= $AC00) and (ACp <= $D7A3)) or      // Hangul syllables
    ((ACp >= $F900) and (ACp <= $FAFF)) or      // compatibility ideographs
    ((ACp >= $FE30) and (ACp <= $FE4F)) or      // compatibility forms
    ((ACp >= $FF00) and (ACp <= $FF9F)) or      // fullwidth forms
    ((ACp >= $20000) and (ACp <= $2FA1F));      // extensions B..F
end;

{ Punctuation that must not be pushed to the start of the next line. }
function InkIsNoBreakBefore(ACp: Cardinal): boolean;
begin
  case ACp of
    $3001, $3002,                               // ideographic comma, full stop
    $FF01, $FF0C, $FF0E, $FF1A, $FF1B, $FF1F,   // fullwidth ! , . : ; ?
    $3009, $300B, $300D, $300F, $3011,          // closing brackets
    $FF09, $FF3D, $FF5D:
      Result := True;
  else
    Result := False;
  end;
end;

function HTMLIsCJK(const AChar: string): boolean;
var
  L: integer;
begin
  Result := (AChar <> '') and InkIsCJKCodepoint(InkCodepointAt(AChar, 1, L));
end;

{ Word wrap.

  The renderer breaks a line only where the markup says so (<br>, <hr>, <p>),
  so wrapping is done by rewriting the markup: walk the text word by word,
  measure what the current visual line would come to, and drop in a <br> when
  the next word would not fit.

  The catch is formatting that is still open at the break. <b>a very long
  sentence</b> that wraps must stay bold on the second line, and the width of
  that second line has to be measured in bold too. So a stack of the currently
  open tags is kept, and its concatenation (LineOpen) is prepended to whatever
  is measured. The renderer itself carries font state across a <br> already,
  so nothing has to be re-emitted into the output - LineOpen is only ever used
  for measuring. }
function HTMLWordWrap(Canvas: TCanvas; const Text: string; MaxWidth: integer;
  SuperSubScriptRatio: double; Scale: integer = 100): string;
var
  Stack: TStringList;             // open formatting tags, innermost last
  Res, Line, LineOpen, Pending: string;
  LineHasText: boolean;           // a line of nothing but tags is still empty
  LineWidth: integer;             // how wide Line is drawn
  Atom, Nm: string;
  P, Start, Len, I, CpLen: integer;
  Cp: Cardinal;
  R: TRect;

  function OpenPrefix: string;
  var
    K: integer;
  begin
    Result := '';
    for K := 0 to Stack.Count - 1 do
      Result := Result + Stack[K];
  end;

  // '<b>' -> 'B', '</font color=x>' -> '/FONT', '<br/>' -> 'BR'
  function TagNameOf(const ATag: string): string;
  var
    K: integer;
    C: char;
  begin
    Result := '';
    K := 2;                                   // skip '<'
    if (K <= Length(ATag)) and (ATag[K] = '/') then
    begin
      Result := '/';
      Inc(K);
    end;
    while K <= Length(ATag) do
    begin
      C := ATag[K];
      if not (((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or
              ((C >= '0') and (C <= '9'))) then
        Break;
      Result := Result + UpCase(C);
      Inc(K);
    end;
  end;

  function IsBreakTag(const AName: string): boolean;
  begin
    Result := (AName = 'BR') or (AName = 'HR') or (AName = 'P') or (AName = '/P');
  end;

  function IsStyleTag(const AName: string): boolean;
  begin
    Result := (AName = 'B') or (AName = 'I') or (AName = 'U') or (AName = 'S') or
      (AName = 'SUP') or (AName = 'SUB') or (AName = 'FONT') or (AName = 'A');
  end;

  procedure StartNewLine;
  begin
    Line := '';
    LineHasText := False;
    LineWidth := 0;
    Pending := '';
    LineOpen := OpenPrefix;
  end;

  { Only the new word is measured, in the formatting open around it, and
    added to the width of the line so far: measuring the whole line again
    for every word made wrapping a long document take seconds. }
  procedure AddWord(const W: string);
  var
    Extra: integer;
  begin
    Extra := HTMLTextWidth(Canvas, R, [], OpenPrefix + Pending + W,
      SuperSubScriptRatio, Scale);
    if LineHasText and (LineWidth + Extra > MaxWidth) then
    begin
      Res := Res + cBR;                       // the held spaces die with the break
      StartNewLine;
      Pending := '';
      Extra := HTMLTextWidth(Canvas, R, [], OpenPrefix + W, SuperSubScriptRatio, Scale);
    end;
    Res := Res + Pending + W;
    Line := Line + Pending + W;
    LineWidth := LineWidth + Extra;
    LineHasText := True;
    Pending := '';
  end;

begin
  Result := Text;
  if (Canvas = nil) or (MaxWidth <= 0) or (Text = '') then
    Exit;

  P := Pos('<table', LowerCase(Text));
  if P > 0 then
  begin
    Start := Pos('</table>', LowerCase(Text));
    if Start = 0 then Start := Length(Text) + 1 else Inc(Start, 8);
    Result := HTMLWordWrap(Canvas, Copy(Text, 1, P-1), MaxWidth,
      SuperSubScriptRatio, Scale) + Copy(Text, P, Start-P) +
      HTMLWordWrap(Canvas, Copy(Text, Start, MaxInt), MaxWidth,
        SuperSubScriptRatio, Scale);
    Exit;
  end;
  R := Rect(0, 0, MaxWidth, 0);
  Stack := TStringList.Create;
  try
    Res := '';
    Line := '';
    LineHasText := False;
    LineWidth := 0;
    LineOpen := '';
    Pending := '';
    P := 1;
    Len := Length(Text);
    while P <= Len do
    begin
      if Text[P] = cTagBegin then
      begin
        Start := P;
        while (P <= Len) and (Text[P] <> cTagEnd) do
          Inc(P);
        if P <= Len then
          Inc(P);                             // take the '>' too
        Atom := Copy(Text, Start, P - Start);
        Nm := TagNameOf(Atom);
        if Pending <> '' then
          LineWidth := LineWidth + HTMLTextWidth(Canvas, R, [], OpenPrefix + Pending,
            SuperSubScriptRatio, Scale);
        Res := Res + Pending + Atom;
        Line := Line + Pending + Atom;
        Pending := '';
        if IsBreakTag(Nm) then
          StartNewLine
        else if IsStyleTag(Nm) then
          Stack.Add(Atom)
        else if (Length(Nm) > 1) and (Nm[1] = '/') then
        begin
          for I := Stack.Count - 1 downto 0 do
            if TagNameOf(Stack[I]) = Copy(Nm, 2, Length(Nm)) then
            begin
              Stack.Delete(I);
              Break;
            end;
        end
        else
          { an image, an indent or an alignment moves or widens the line:
            measure it whole again }
          LineWidth := HTMLTextWidth(Canvas, R, [], LineOpen + Line,
            SuperSubScriptRatio, Scale);
      end
      else if (Text[P] = ' ') or (Text[P] = #9) then
      begin
        Start := P;
        while (P <= Len) and ((Text[P] = ' ') or (Text[P] = #9)) do
          Inc(P);
        Pending := Pending + Copy(Text, Start, P - Start);
      end
      else
      begin
        // A word runs to the next tag or blank. CJK is the exception: it has no
        // blanks, so each character is its own word and may start a line -
        // except closing punctuation, which is kept with what it follows.
        // A slash also ends a word, so long paths can break somewhere.
        Start := P;
        Cp := InkCodepointAt(Text, P, CpLen);
        if InkIsCJKCodepoint(Cp) then
        begin
          Inc(P, CpLen);
          while P <= Len do
          begin
            Cp := InkCodepointAt(Text, P, CpLen);
            if not InkIsNoBreakBefore(Cp) then Break;
            Inc(P, CpLen);
          end;
        end
        else
          while (P <= Len) and (Text[P] <> cTagBegin) and (Text[P] <> ' ') and
            (Text[P] <> #9) do
          begin
            Cp := InkCodepointAt(Text, P, CpLen);
            if InkIsCJKCodepoint(Cp) then Break;   // starts the next word
            Inc(P, CpLen);
            if (Text[P - 1] = '/') or (Text[P - 1] = '\') then Break;
          end;
        AddWord(Copy(Text, Start, P - Start));
      end;
    end;
    Result := Res + Pending;
  finally
    Stack.Free;
  end;
end;

end.
