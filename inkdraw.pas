{ InkDraw - the drawing calls LazInk's controls make, on LazInk's own engine.

  The controls have always asked for the same handful of things: draw this
  markup in this rectangle, measure it, say what is under this point, and
  give me its plain text.  This unit is that API, implemented on InkRender
  and InkBox, so the controls do not each have to know how the engine works.

  It is also what lets the package change engines without changing controls:
  the names and records here are the ones inkhtml.pas published, so a unit
  that used to say "uses InkHtml" says "uses InkDraw" and nothing else moves.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkDraw;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList, LCLType, StdCtrls, Types, Math, InkRender;

type
  { where a block sits when the rectangle is bigger than the text }
  TInkVertAlign = (ivaTop, ivaCenter, ivaBottom);
  TInkHorzAlign = (ihaLeft, ihaCenter, ihaRight);

  { told where every run of text went: how a control finds the character
    under the mouse, and paints a selection over the same pixels }
  THTMLRunEvent = procedure(const AText: string; ALeft, ATop, AWidth, AHeight,
    ALine, APart: integer; AFont: TFont) of object;

  { what a hit test answers }
  THTMLHitInfo = record
    OnLink: Boolean;
    LinkName: string;      { the href }
    LinkText: string;      { the words between <a> and </a> }
    LinkIndex: Integer;    { the ordinal of the link, counting from 1 }
  end;

  { Everything about a render beyond the text itself, passed as one record. }
  THTMLOptions = record
    SuperSubScriptRatio: Double;
    Scale: Integer;
    { extra pixels between lines }
    LineSpacing: Integer;
    { a line's height in pixels, as CSS line-height asks for it; zero leaves
      every line the height of the font in it }
    LineHeight: Integer;
    { margins taken off the drawing rectangle: Left, Top, Right, Bottom }
    Borders: TRect;
    VertAlign: TInkVertAlign;
    HorzAlign: TInkHorzAlign;
    { supplies <img src="n"> }
    Images: TCustomImageList;
    { how <a href=..> spans are painted }
    LinkColor: TColor;
    LinkBackColor: TColor;
    LinkUnderline: Boolean;
    { and the one under the mouse instead; HoverIndex counts from 1 }
    HoverIndex: Integer;
    HoverColor: TColor;
    HoverBackColor: TColor;
    HoverUnderline: Boolean;
    { code: laid out as written and cut off at the edge, never wrapped }
    NoWrap: Boolean;
    OnRun: THTMLRunEvent;
    RunPart: Integer;
  end;

  { how a link is painted, as a published property }
  TInkLinkStyle = class(TPersistent)
  private
    FColor, FBackColor: TColor;
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
    { clDefault leaves the surrounding color alone }
    property Color: TColor read FColor write SetColor;
    property BackColor: TColor read FBackColor write SetBackColor;
    property Underline: Boolean read FUnderline write SetUnderline;
  end;

  { the margins inside a control, as a published property }
  TInkBorders = class(TPersistent)
  private
    FSides: array[0..3] of Integer;
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
function InkOptions(ARatio: Double; AScale, ALineSpacing: Integer;
  ABorders: TInkBorders; AImages: TCustomImageList;
  ALink, AHover: TInkLinkStyle; AHoverIndex: Integer): THTMLOptions;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions);
function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions): TSize;
function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer): THTMLHitInfo;
{ Both engines are asked to re-flow markup to a width.  This one wraps while
  it lays out, so there is nothing to insert: the text comes back as it went
  in, and the wrapping happens when it is measured or drawn at that width. }
function HTMLWordWrap(Canvas: TCanvas; const Text: string; MaxWidth: Integer;
  SuperSubScriptRatio: Double; Scale: Integer = 100): string;
function HTMLPlainText(const Text: string): string;
function HTMLEscape(const Text: string): string;
function HTMLUnescape(const Text: string): string;
function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;
function HTMLContrastColor(ABackground: TColor): TColor;
function HTMLShadeColor(AColor: TColor; APercent: Integer): TColor;
{ a size the LCL's way: points when positive, pixels when negative, exactly
  as TFont.Size and TFont.Height spell it }
procedure HTMLFontSize(const ACanvas: TCanvas; ASize: Integer);
function HTMLIsCJK(const AChar: string): Boolean;

{ measure and hit test in one pass, for a control that wants both }
procedure HTMLMeasureAndHit(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  out Width, Height: Integer; out AHit: THTMLHitInfo);

implementation

var
  { one engine, reused: it keeps a layout per source and options, so drawing
    the same text again costs nothing }
  GEngine: TInkRenderer;
  GRunFont: TFont;
  GRunHandler: THTMLRunEvent;
  GRunPart: Integer;

type
  { turns the engine's runs into the call the controls expect }
  TRunRelay = class
    procedure Run(const ARun: TInkRenderRun);
  end;

var
  GRelay: TRunRelay;

procedure TRunRelay.Run(const ARun: TInkRenderRun);
begin
  if not Assigned(GRunHandler) then Exit;
  GRunFont.Name := ARun.Style.Face;
  GRunFont.Size := ARun.Style.Size;
  GRunFont.Style := ARun.Style.Styles;
  GRunFont.Color := ARun.Style.Color;
  GRunHandler(ARun.Text, ARun.Bounds.Left, ARun.Bounds.Top,
    ARun.Bounds.Right-ARun.Bounds.Left, ARun.Bounds.Bottom-ARun.Bounds.Top,
    ARun.Line, GRunPart, GRunFont);
end;

function Engine: TInkRenderer;
begin
  if GEngine=nil then GEngine := TInkRenderer.Create;
  Result := GEngine;
end;

{ the options the engine wants, from the ones the control gave }
function EngineOptions(Canvas: TCanvas; const Options: THTMLOptions;
  AWidth, AHeight: Integer; const State: TOwnerDrawState): TInkRenderOptions;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.BaseFont := Canvas.Font;
  Result.Images := Options.Images;
  Result.Width := AWidth;
  Result.Height := AHeight;
  case Options.VertAlign of
    ivaCenter: Result.VertAlign := nvaCenter;
    ivaBottom: Result.VertAlign := nvaBottom;
  else Result.VertAlign := nvaTop;
  end;
  Result.Scale := Options.Scale; if Result.Scale<=0 then Result.Scale := 100;
  Result.LineSpacing := Options.LineSpacing;
  Result.LineHeight := Options.LineHeight;
  Result.Borders := Options.Borders;
  Result.LinkColor := Options.LinkColor;
  Result.LinkBackColor := Options.LinkBackColor;
  Result.LinkUnderline := Options.LinkUnderline;
  Result.HoverIndex := Options.HoverIndex;
  Result.HoverColor := Options.HoverColor;
  Result.HoverBackColor := Options.HoverBackColor;
  Result.HoverUnderline := Options.HoverUnderline;
  Result.NoWrap := Options.NoWrap;
  Result.OwnerState := State;
  Result.RunPart := Options.RunPart;
end;

{ a block the control wants centered or right-aligned says so in its markup }
function Aligned(const Text: string; AHorz: TInkHorzAlign): string;
begin
  case AHorz of
    ihaCenter: Result := '<center>'+Text;
    ihaRight: Result := '<right>'+Text;
  else Result := Text;
  end;
end;

function DefaultHTMLOptions(ASuperSubScriptRatio: Double;
  AScale: Integer): THTMLOptions;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.SuperSubScriptRatio := ASuperSubScriptRatio;
  Result.Scale := AScale;
  Result.LineSpacing := 0;
  Result.LineHeight := 0;
  Result.Borders := Rect(0,0,0,0);
  Result.VertAlign := ivaTop;
  Result.HorzAlign := ihaLeft;
  Result.Images := nil;
  Result.LinkColor := clDefault;
  Result.LinkBackColor := clNone;
  Result.LinkUnderline := False;
  Result.HoverIndex := 0;
  Result.HoverColor := clDefault;
  Result.HoverBackColor := clNone;
  Result.HoverUnderline := False;
  Result.NoWrap := False;
  Result.OnRun := nil;
  Result.RunPart := 0;
end;

function InkOptions(ARatio: Double; AScale, ALineSpacing: Integer;
  ABorders: TInkBorders; AImages: TCustomImageList;
  ALink, AHover: TInkLinkStyle; AHoverIndex: Integer): THTMLOptions;
begin
  Result := DefaultHTMLOptions(ARatio, AScale);
  Result.LineSpacing := ALineSpacing;
  if ABorders<>nil then
    Result.Borders := Rect(ABorders.Left, ABorders.Top, ABorders.Right, ABorders.Bottom);
  Result.Images := AImages;
  if ALink<>nil then
  begin
    Result.LinkColor := ALink.Color;
    Result.LinkBackColor := ALink.BackColor;
    Result.LinkUnderline := ALink.Underline;
  end;
  if AHover<>nil then
  begin
    Result.HoverColor := AHover.Color;
    Result.HoverBackColor := AHover.BackColor;
    Result.HoverUnderline := AHover.Underline;
  end;
  Result.HoverIndex := AHoverIndex;
end;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions);
var O: TInkRenderOptions;
begin
  O := EngineOptions(Canvas, Options, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, State);
  if Assigned(Options.OnRun) then
  begin
    GRunHandler := Options.OnRun; GRunPart := Options.RunPart;
    O.OnRun := @GRelay.Run;
  end;
  try
    Engine.Tokenize(Aligned(Text, Options.HorzAlign));
    Engine.Paint(Canvas, Rect, O);
  finally GRunHandler := nil end;
end;

function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions): TSize;
var O: TInkRenderOptions; W: Integer;
begin
  W := Rect.Right-Rect.Left;
  if W<=0 then W := 32767;
  O := EngineOptions(Canvas, Options, W, 0, State);
  Engine.Tokenize(Aligned(Text, Options.HorzAlign));
  Result := Engine.Layout(Canvas, O).Size;
end;

function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer): THTMLHitInfo;
var O: TInkRenderOptions; Hit: TInkRenderHit;
begin
  Result.OnLink := False; Result.LinkName := ''; Result.LinkText := '';
  Result.LinkIndex := 0;
  O := EngineOptions(Canvas, AOpts, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, []);
  Engine.Tokenize(Aligned(Text, AOpts.HorzAlign));
  Engine.Layout(Canvas, O);
  Hit := Engine.HitTest(Canvas, MouseX, MouseY, Rect.Left, Rect.Top);
  Result.OnLink := Hit.OnLink;
  Result.LinkName := Hit.LinkName;
  Result.LinkText := Hit.LinkText;
  Result.LinkIndex := Hit.LinkIndex;
end;

procedure HTMLMeasureAndHit(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  out Width, Height: Integer; out AHit: THTMLHitInfo);
var O: TInkRenderOptions; Sz: TSize; Hit: TInkRenderHit;
begin
  AHit.OnLink := False; AHit.LinkName := ''; AHit.LinkText := ''; AHit.LinkIndex := 0;
  O := EngineOptions(Canvas, AOpts, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, []);
  if Assigned(AOpts.OnRun) then
  begin
    GRunHandler := AOpts.OnRun; GRunPart := AOpts.RunPart;
    O.OnRun := @GRelay.Run;
  end;
  try
    Engine.Tokenize(Aligned(Text, AOpts.HorzAlign));
    Sz := Engine.Layout(Canvas, O).Size;
    Width := Sz.cx; Height := Sz.cy;
    { the words, without drawing them: measuring must not need a clip }
    if Assigned(AOpts.OnRun) then Engine.ReportRuns(O, Rect.Left, Rect.Top);
    if (MouseX>=0) and (MouseY>=0) then
    begin
      Hit := Engine.HitTest(Canvas, MouseX, MouseY, Rect.Left, Rect.Top);
      AHit.OnLink := Hit.OnLink; AHit.LinkName := Hit.LinkName;
      AHit.LinkText := Hit.LinkText; AHit.LinkIndex := Hit.LinkIndex;
    end;
  finally GRunHandler := nil end;
end;

function HTMLWordWrap(Canvas: TCanvas; const Text: string; MaxWidth: Integer;
  SuperSubScriptRatio: Double; Scale: Integer): string;
begin
  { the engine wraps as it lays out; there is nothing to insert }
  Result := Text;
end;

function HTMLPlainText(const Text: string): string;
begin Result := InkRenderPlainText(Text) end;

function HTMLEscape(const Text: string): string;
begin Result := InkRenderEscape(Text) end;

function HTMLUnescape(const Text: string): string;
begin Result := InkRenderUnescape(Text) end;

function HTMLStringToColor(AText: string; ADefColor: TColor): TColor;
begin Result := InkRenderColor(AText, ADefColor) end;

function HTMLContrastColor(ABackground: TColor): TColor;
begin Result := InkRenderContrastColor(ABackground) end;

function HTMLShadeColor(AColor: TColor; APercent: Integer): TColor;
begin Result := InkRenderShadeColor(AColor, APercent) end;

procedure HTMLFontSize(const ACanvas: TCanvas; ASize: Integer);
begin InkRenderApplySize(ACanvas, ASize) end;

function HTMLIsCJK(const AChar: string): Boolean;
begin Result := InkRenderIsCJK(AChar) end;

{ --- the two published property classes --- }

constructor TInkLinkStyle.Create(ADefaultUnderline: Boolean);
begin
  inherited Create;
  FColor := clDefault; FBackColor := clNone; FUnderline := ADefaultUnderline;
end;

procedure TInkLinkStyle.Changed;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkLinkStyle.SetColor(AValue: TColor);
begin
  if FColor=AValue then Exit;
  FColor := AValue; Changed;
end;

procedure TInkLinkStyle.SetBackColor(AValue: TColor);
begin
  if FBackColor=AValue then Exit;
  FBackColor := AValue; Changed;
end;

procedure TInkLinkStyle.SetUnderline(AValue: Boolean);
begin
  if FUnderline=AValue then Exit;
  FUnderline := AValue; Changed;
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
  else inherited Assign(Source);
end;

function TInkBorders.GetSide(AIndex: Integer): Integer;
begin Result := FSides[AIndex] end;

procedure TInkBorders.SetSide(AIndex, AValue: Integer);
begin
  if FSides[AIndex]=AValue then Exit;
  FSides[AIndex] := AValue;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkBorders.SetAll(AValue: Integer);
var I: Integer;
begin
  for I := 0 to 3 do FSides[I] := AValue;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkBorders.Assign(Source: TPersistent);
var I: Integer;
begin
  if Source is TInkBorders then
  begin
    for I := 0 to 3 do FSides[I] := TInkBorders(Source).GetSide(I);
    if Assigned(FOnChange) then FOnChange(Self);
  end
  else inherited Assign(Source);
end;

initialization
  GRunFont := TFont.Create;
  GRelay := TRunRelay.Create;

finalization
  GEngine.Free;
  GRelay.Free;
  GRunFont.Free;

end.
