{ InkDraw - the drawing calls LazInk's controls make, on LazInk's own engine.

  The controls have always asked for the same handful of things: draw this
  markup in this rectangle, measure it, say what is under this point, and
  give me its plain text.  This unit is that API, implemented on InkRender
  and InkBox, so the controls do not each have to know how the engine works.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkDraw;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList, LCLType, LCLIntf, StdCtrls, Types, Math, LazUTF8, InkRender;

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
    { a link keeps the color its markup gives it, as one styled by CSS does }
    LinkKeepsColor: Boolean;
    { lines are built as CSS builds them: each holds the block's own font,
      and a pill's padding reaches past its line instead of growing it }
    CSSLines: Boolean;
    { and the one under the mouse instead; HoverIndex counts from 1 }
    HoverIndex: Integer;
    HoverColor: TColor;
    HoverBackColor: TColor;
    HoverUnderline: Boolean;
    { code: laid out as written and cut off at the edge, never wrapped }
    NoWrap: Boolean;
    { with NoWrap: a line that does not fit ends in EllipsisText instead of
      stopping halfway through a letter.  '...' (U+2026) unless set. }
    Ellipsis: Boolean;
    EllipsisText: string;
    OnRun: THTMLRunEvent;
    RunPart: Integer;
  end;

  { A bounded, owner-scoped LRU of immutable layouts. Painting and interaction
    share geometry; source/options/device changes select a new entry. It keeps
    no tokens, box trees or per-block word caches. Use on the LCL thread. }
  THTMLLayoutCache = class
  private
    FEntries: TList;
    FBytes, FMaxBytes: SizeUInt;
    FMaxEntries: Integer;
    FHits, FMisses: QWord;
    { one renderer, kept for its word and metric caches }
    FBuilder: TInkRenderer;
    FBuilderDPIX, FBuilderDPIY, FBuilderFontDPI: Integer;
    procedure RemoveOldest;
    function Acquire(Canvas: TCanvas; const Text: string;
      const Options: TInkRenderOptions): TInkRenderLayout;
  public
    constructor Create(AMaxEntries: Integer = 128;
      AMaxBytes: SizeUInt = 16*1024*1024);
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    property Bytes: SizeUInt read FBytes;
    property Hits: QWord read FHits;
    property Misses: QWord read FMisses;
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

  { one run of one rendered text: where it went, in what font }
  TInkRun = record
    Text: string;
    { where Text begins in Words, from 0 }
    Start: Integer;
    Left, Top, Width, Height, LineHeight, Line, Part: Integer;
    FontName: string;
    FontSize: Integer;
    FontStyle: TFontStyles;
    FontColor: TColor;
  end;

  { The runs one rendered text left behind - how a control without the
    page's blocks (a label, a list box item) finds the character under the
    mouse, paints a selection over the same pixels, and hands back the
    selected words.  Build it with the same canvas font, rectangle and
    options the text is drawn with, and the runs land where the draw did. }
  TInkRunText = class
  private
    FRuns: array of TInkRun;
    FCount: Integer;
    FWords: string;
    procedure Collect(const AText: string; ALeft, ATop, AWidth, AHeight,
      ALine, APart: integer; AFont: TFont);
    procedure RunFont(ACanvas: TCanvas; const R: TInkRun);
    function RunX(ACanvas: TCanvas; const R: TInkRun; Offset: Integer): Integer;
  public
    procedure Build(ACanvas: TCanvas; const ARect: TRect; const AText: string;
      AOpts: THTMLOptions; ACache: THTMLLayoutCache = nil);
    procedure Clear;
    { the character boundary nearest X,Y, as an offset into Words (0..Length) }
    function OffsetAt(ACanvas: TCanvas; X, Y: Integer): Integer;
    { True when X,Y is on a run of text }
    function OverText(X, Y: Integer): Boolean;
    { the word around AOffset, a browser's double click }
    procedure WordAt(AOffset: Integer; out AFrom, ATo: Integer);
    { fills ABack behind Words[A+1..Z] and draws those characters again }
    procedure PaintSelection(ACanvas: TCanvas; A, Z: Integer; ABack: TColor);
    function TextRange(A, Z: Integer): string;
    property Words: string read FWords;
    property RunCount: Integer read FCount;
  end;

function DefaultHTMLOptions(ASuperSubScriptRatio: Double = 0.7;
  AScale: Integer = 100): THTMLOptions;
function InkOptions(ARatio: Double; AScale, ALineSpacing: Integer;
  ABorders: TInkBorders; AImages: TCustomImageList;
  ALink, AHover: TInkLinkStyle; AHoverIndex: Integer): THTMLOptions;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions;
  Cache: THTMLLayoutCache = nil);
{ the same, saying whether the ellipsis cut a line - for a tooltip with the
  whole text }
procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions; out ACut: Boolean;
  Cache: THTMLLayoutCache = nil);
function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions;
  Cache: THTMLLayoutCache = nil): TSize;
function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  Cache: THTMLLayoutCache = nil): THTMLHitInfo;
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
procedure HTMLFontSize(const ACanvas: TCanvas; ASize: Integer); overload;
procedure HTMLFontSize(const AFont: TFont; ASize: Integer); overload;
function HTMLIsCJK(const AChar: string): Boolean;

{ measure and hit test in one pass, for a control that wants both }
procedure HTMLMeasureAndHit(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  out Width, Height: Integer; out AHit: THTMLHitInfo;
  Cache: THTMLLayoutCache = nil);

implementation

var
  { Scratch engine for callers without an owner-scoped layout cache. }
  GEngine: TInkRenderer;

type
  { turns the engine's runs into the call the controls expect }
  TRunRelay = class
  private
    FFont: TFont;
    FHandler: THTMLRunEvent;
    FPart: Integer;
  public
    constructor Create(AHandler: THTMLRunEvent; APart: Integer);
    destructor Destroy; override;
    procedure Run(const ARun: TInkRenderRun);
  end;

constructor TRunRelay.Create(AHandler: THTMLRunEvent; APart: Integer);
begin
  inherited Create;
  FFont := TFont.Create; FHandler := AHandler; FPart := APart;
end;

destructor TRunRelay.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TRunRelay.Run(const ARun: TInkRenderRun);
begin
  FFont.Name := ARun.Style.Face;
  InkRenderApplySize(FFont, ARun.Style.Size);
  FFont.Style := ARun.Style.Styles;
  FFont.Color := ARun.Style.Color;
  FHandler(ARun.Text, ARun.Bounds.Left, ARun.Bounds.Top,
    ARun.Bounds.Right-ARun.Bounds.Left, ARun.Bounds.Bottom-ARun.Bounds.Top,
    ARun.Line, FPart, FFont);
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
  Result.LinkKeepsColor := Options.LinkKeepsColor;
  Result.CSSLines := Options.CSSLines;
  Result.HoverIndex := Options.HoverIndex;
  Result.HoverColor := Options.HoverColor;
  Result.HoverBackColor := Options.HoverBackColor;
  Result.HoverUnderline := Options.HoverUnderline;
  Result.NoWrap := Options.NoWrap;
  Result.Ellipsis := Options.Ellipsis;
  Result.EllipsisText := Options.EllipsisText;
  Result.OwnerState := State;
  Result.RunPart := Options.RunPart;
end;

type
  TLayoutIdentity = record
    Canvas, Device: PtrUInt;
    DPIX, DPIY, FontDPI, FontHeight, FontSize, Orientation: Integer;
    CharSet: TFontCharSet;
    Pitch: TFontPitch;
    Quality: TFontQuality;
    Styles: TFontStyles;
    Color: TColor;
    Width, Height, Scale, LineSpacing, LineHeight: Integer;
    Borders: TRect;
    VertAlign: TInkRenderVertAlign;
    NoWrap: Boolean;
    OwnerState: TOwnerDrawState;
    Images: PtrUInt;
    ImageWidth, ImageHeight, ImageCount: Integer;
  end;

  TLayoutEntry = class
    { the identity as a record rather than a string: comparing it needs no
      allocation, and the hash settles almost every entry in one integer }
    Ident: TLayoutIdentity;
    Face, Source: string;
    Hash: QWord;
    Layout: TInkRenderLayout;
    Bytes: SizeUInt;
    destructor Destroy; override;
  end;

{ FNV-1a over the identity, the face and the source.  The hash only decides
  which entry to compare properly; a collision costs a comparison, never the
  wrong text. }
function IdentityHash(const AIdent: TLayoutIdentity;
  const AFace, ASource: string): QWord;
const Prime = QWord(1099511628211);
var I: Integer; P: PByte;
begin
  Result := QWord(14695981039346656037);
  P := @AIdent;
  for I := 0 to SizeOf(AIdent)-1 do
  begin
    Result := (Result xor P[I])*Prime;
  end;
  for I := 1 to Length(AFace) do Result := (Result xor Byte(AFace[I]))*Prime;
  for I := 1 to Length(ASource) do Result := (Result xor Byte(ASource[I]))*Prime;
end;

destructor TLayoutEntry.Destroy;
begin
  if Layout<>nil then Layout.Release;
  inherited Destroy;
end;

constructor THTMLLayoutCache.Create(AMaxEntries: Integer; AMaxBytes: SizeUInt);
begin
  inherited Create;
  FEntries := TList.Create;
  FMaxEntries := Max(1,AMaxEntries);
  FMaxBytes := AMaxBytes;
end;

destructor THTMLLayoutCache.Destroy;
begin
  Clear;
  FEntries.Free;
  FBuilder.Free;
  inherited Destroy;
end;

procedure THTMLLayoutCache.RemoveOldest;
var E: TLayoutEntry;
begin
  E := TLayoutEntry(FEntries[0]);
  Dec(FBytes,E.Bytes);
  FEntries.Delete(0);
  E.Free;
end;

procedure THTMLLayoutCache.Clear;
begin
  while FEntries.Count>0 do RemoveOldest;
end;

function THTMLLayoutCache.Count: Integer;
begin
  Result := FEntries.Count;
end;

function THTMLLayoutCache.Acquire(Canvas: TCanvas; const Text: string;
  const Options: TInkRenderOptions): TInkRenderLayout;
var Identity: TLayoutIdentity; Face: string; I: Integer; Hash: QWord;
  E: TLayoutEntry; Builder: TInkRenderer; SavedFont: TFont;
begin
  { Exact identity, not a hash: a collision must never display other text.
    Zero padding before serializing the fixed-size portion. Position, clip,
    hover, run callbacks and selection colors are deliberately not geometry. }
  FillChar(Identity,SizeOf(Identity),0);
  Identity.Canvas := PtrUInt(Canvas);
  Identity.Device := PtrUInt(Canvas.Handle);
  Identity.DPIX := GetDeviceCaps(Canvas.Handle,LOGPIXELSX);
  Identity.DPIY := GetDeviceCaps(Canvas.Handle,LOGPIXELSY);
  with Options.BaseFont do
  begin
    Identity.FontDPI := PixelsPerInch;
    Identity.FontHeight := Height; Identity.FontSize := Size;
    Identity.Orientation := Orientation; Identity.CharSet := CharSet;
    Identity.Pitch := Pitch; Identity.Quality := Quality;
    Identity.Styles := Style; Identity.Color := Color;
  end;
  Identity.Width := Options.Width;
  if Options.VertAlign<>nvaTop then Identity.Height := Options.Height;
  Identity.Scale := Options.Scale;
  Identity.LineSpacing := Options.LineSpacing;
  Identity.LineHeight := Options.LineHeight;
  Identity.Borders := Options.Borders;
  Identity.VertAlign := Options.VertAlign;
  Identity.NoWrap := Options.NoWrap;
  { Only odReserved1 changes layout (indent scaling). Other owner states
    are applied by PaintLayout to the current draw. }
  Identity.OwnerState := Options.OwnerState * [odReserved1];
  Identity.Images := PtrUInt(Options.Images);
  if Options.Images<>nil then
  begin
    Identity.ImageWidth := Options.Images.Width;
    Identity.ImageHeight := Options.Images.Height;
    Identity.ImageCount := Options.Images.Count;
  end;
  Face := Options.BaseFont.Name;
  Hash := IdentityHash(Identity,Face,Text);
  for I := FEntries.Count-1 downto 0 do
  begin
    E := TLayoutEntry(FEntries[I]);
    if (E.Hash=Hash) and CompareMem(@E.Ident,@Identity,SizeOf(Identity)) and
      (E.Face=Face) and (E.Source=Text) then
    begin
      Inc(FHits);
      FEntries.Move(I,FEntries.Count-1);
      Result := E.Layout; Result.Retain;
      Exit;
    end;
  end;
  Inc(FMisses);
  E := TLayoutEntry.Create;
  try
    E.Ident := Identity; E.Face := Face; E.Source := Text; E.Hash := Hash;
    { One builder, kept: its word widths and font metrics are the expensive
      part of measuring, and a page's blocks share most of their words.  It
      is thrown away when the device it measured against changes, which is
      what the caches are keyed on but cannot see. }
    if (FBuilder<>nil) and ((FBuilderDPIX<>Identity.DPIX) or
      (FBuilderDPIY<>Identity.DPIY) or (FBuilderFontDPI<>Identity.FontDPI)) then
      FreeAndNil(FBuilder);
    if FBuilder=nil then
    begin
      FBuilder := TInkRenderer.Create;
      FBuilderDPIX := Identity.DPIX; FBuilderDPIY := Identity.DPIY;
      FBuilderFontDPI := Identity.FontDPI;
    end;
    Builder := FBuilder;
    SavedFont := TFont.Create;
    SavedFont.PixelsPerInch := Canvas.Font.PixelsPerInch;
    SavedFont.Assign(Canvas.Font);
    try
      Builder.Tokenize(Text);
      Builder.Layout(Canvas,Options);
      E.Layout := Builder.DetachLayout;
      E.Layout.Retain;
    finally
      Canvas.Font.Assign(SavedFont);
      SavedFont.Free;
    end;
    E.Bytes := E.Layout.StorageBytes+SizeUInt(Length(E.Source))+
      SizeUInt(SizeOf(TLayoutIdentity))+256;
    { Keep one oversized layout rather than repeatedly rebuilding a giant
      table. All other entries are evicted; active callers pin their layout. }
    while (FEntries.Count>0) and ((FEntries.Count>=FMaxEntries) or
      (FBytes+E.Bytes>FMaxBytes)) do RemoveOldest;
    FEntries.Add(E); Inc(FBytes,E.Bytes);
    Result := E.Layout; Result.Retain;
    E := nil;
  finally E.Free end;
end;

function PreparedLayout(Canvas: TCanvas; const Text: string;
  const Options: TInkRenderOptions; Cache: THTMLLayoutCache): TInkRenderLayout;
begin
  if Cache<>nil then Exit(Cache.Acquire(Canvas,Text,Options));
  Engine.Tokenize(Text);
  Result := Engine.Layout(Canvas,Options);
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
  Result.Ellipsis := False;
  Result.EllipsisText := '';
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
  const Text: string; const Options: THTMLOptions;
  Cache: THTMLLayoutCache = nil);
var Cut: Boolean;
begin
  HTMLDrawOpt(Canvas,Rect,State,Text,Options,Cut,Cache);
end;

procedure HTMLDrawOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions; out ACut: Boolean;
  Cache: THTMLLayoutCache = nil);
var O: TInkRenderOptions; L: TInkRenderLayout; Relay: TRunRelay;
begin
  ACut := False;
  O := EngineOptions(Canvas, Options, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, State);
  Relay := nil;
  if Assigned(Options.OnRun) then
  begin
    Relay := TRunRelay.Create(Options.OnRun,Options.RunPart);
    O.OnRun := @Relay.Run;
  end;
  try
    L := PreparedLayout(Canvas,Aligned(Text,Options.HorzAlign),O,Cache);
    try
      ACut := L.WasCut;
      Engine.PaintLayout(Canvas,Rect,O,L);
    finally if Cache<>nil then L.Release end;
  finally Relay.Free end;
end;

function HTMLTextExtentOpt(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; const Options: THTMLOptions;
  Cache: THTMLLayoutCache = nil): TSize;
var O: TInkRenderOptions; W: Integer; L: TInkRenderLayout;
begin
  W := Rect.Right-Rect.Left;
  if W<=0 then W := 32767;
  O := EngineOptions(Canvas, Options, W, 0, State);
  L := PreparedLayout(Canvas,Aligned(Text,Options.HorzAlign),O,Cache);
  try Result := L.Size
  finally if Cache<>nil then L.Release end;
end;

function HTMLHitTest(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  Cache: THTMLLayoutCache = nil): THTMLHitInfo;
var O: TInkRenderOptions; Hit: TInkRenderHit; L: TInkRenderLayout;
begin
  Result.OnLink := False; Result.LinkName := ''; Result.LinkText := '';
  Result.LinkIndex := 0;
  O := EngineOptions(Canvas, AOpts, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, []);
  L := PreparedLayout(Canvas,Aligned(Text,AOpts.HorzAlign),O,Cache);
  try Hit := Engine.HitTestLayout(Canvas,MouseX,MouseY,L,Rect.Left,Rect.Top)
  finally if Cache<>nil then L.Release end;
  Result.OnLink := Hit.OnLink;
  Result.LinkName := Hit.LinkName;
  Result.LinkText := Hit.LinkText;
  Result.LinkIndex := Hit.LinkIndex;
end;

procedure HTMLMeasureAndHit(Canvas: TCanvas; Rect: TRect; const Text: string;
  const AOpts: THTMLOptions; MouseX, MouseY: Integer;
  out Width, Height: Integer; out AHit: THTMLHitInfo;
  Cache: THTMLLayoutCache = nil);
var O: TInkRenderOptions; Sz: TSize; Hit: TInkRenderHit; L: TInkRenderLayout;
  Relay: TRunRelay;
begin
  AHit.OnLink := False; AHit.LinkName := ''; AHit.LinkText := ''; AHit.LinkIndex := 0;
  O := EngineOptions(Canvas, AOpts, Rect.Right-Rect.Left, Rect.Bottom-Rect.Top, []);
  Relay := nil;
  if Assigned(AOpts.OnRun) then
  begin
    Relay := TRunRelay.Create(AOpts.OnRun,AOpts.RunPart);
    O.OnRun := @Relay.Run;
  end;
  try
    L := PreparedLayout(Canvas,Aligned(Text,AOpts.HorzAlign),O,Cache);
    try
      Sz := L.Size;
      Width := Sz.cx; Height := Sz.cy;
      { the words, without drawing them: measuring must not need a clip }
      if Assigned(AOpts.OnRun) then Engine.ReportLayoutRuns(O,L,Rect.Left,Rect.Top);
      if (MouseX>=0) and (MouseY>=0) then
      begin
        Hit := Engine.HitTestLayout(Canvas,MouseX,MouseY,L,Rect.Left,Rect.Top);
        AHit.OnLink := Hit.OnLink; AHit.LinkName := Hit.LinkName;
        AHit.LinkText := Hit.LinkText; AHit.LinkIndex := Hit.LinkIndex;
      end;
    finally if Cache<>nil then L.Release end;
  finally Relay.Free end;
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

procedure HTMLFontSize(const AFont: TFont; ASize: Integer);
begin InkRenderApplySize(AFont, ASize) end;

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

{ --- TInkRunText -------------------------------------------------------- }

function IsWordByte(C: Char): Boolean;
begin
  Result := (C in ['a'..'z','A'..'Z','0'..'9','_']) or (Ord(C)>=$80);
end;

procedure TInkRunText.Clear;
begin
  FCount := 0;
  SetLength(FRuns,0);
  FWords := '';
end;

procedure TInkRunText.Collect(const AText: string; ALeft, ATop, AWidth, AHeight,
  ALine, APart: integer; AFont: TFont);
begin
  if FCount=Length(FRuns) then SetLength(FRuns,Max(8,FCount*2));
  with FRuns[FCount] do
  begin
    Text := AText; Left := ALeft; Top := ATop; Width := AWidth; Height := AHeight;
    Line := ALine; Part := APart; LineHeight := AHeight;
    FontName := AFont.Name; FontStyle := AFont.Style;
    { pixels when the font carries them, points otherwise - the same
      convention the renderer and TFont itself use }
    if AFont.Height<>0 then FontSize := AFont.Height else FontSize := AFont.Size;
    FontColor := AFont.Color;
  end;
  Inc(FCount);
end;

procedure TInkRunText.Build(ACanvas: TCanvas; const ARect: TRect; const AText: string;
  AOpts: THTMLOptions; ACache: THTMLLayoutCache);
var W,H,I,J,K,P,Q,Tallest: Integer; Hit: THTMLHitInfo; Plain: string;
begin
  Clear;
  if AText='' then Exit;
  AOpts.OnRun := @Collect; AOpts.RunPart := 0;
  { the same layout the text is drawn with, measured instead of painted }
  HTMLMeasureAndHit(ACanvas,ARect,AText,AOpts,-1,-1,W,H,Hit,ACache);
  SetLength(FRuns,FCount);
  { every run on a line is as tall as the line }
  I := 0;
  while I<FCount do
  begin
    J := I; Tallest := 0;
    while (J<FCount) and (FRuns[J].Line=FRuns[I].Line) and (FRuns[J].Part=FRuns[I].Part) do
    begin Tallest := Max(Tallest,FRuns[J].Height); Inc(J) end;
    for K := I to J-1 do FRuns[K].LineHeight := Tallest;
    I := J;
  end;
  { The words are the runs in order, with whatever lay between them in the
    source's own plain text: the space a wrap took away, the tab between
    two cells. }
  Plain := HTMLPlainText(AText);
  P := 1;
  for I := 0 to FCount-1 do
  begin
    Q := Pos(FRuns[I].Text,Plain,P);
    if Q>0 then
    begin
      FWords := FWords+Copy(Plain,P,Q-P);
      P := Q+Length(FRuns[I].Text);
    end
    else if (I>0) and ((FRuns[I].Line<>FRuns[I-1].Line) or (FRuns[I].Part<>FRuns[I-1].Part)) then
      FWords := FWords+' ';
    FRuns[I].Start := Length(FWords);
    FWords := FWords+FRuns[I].Text;
  end;
end;

procedure TInkRunText.RunFont(ACanvas: TCanvas; const R: TInkRun);
begin
  ACanvas.Font.Name := R.FontName;
  HTMLFontSize(ACanvas,R.FontSize);
  ACanvas.Font.Style := R.FontStyle;
end;

function TInkRunText.RunX(ACanvas: TCanvas; const R: TInkRun; Offset: Integer): Integer;
var K: Integer;
begin
  K := EnsureRange(Offset-R.Start,0,Length(R.Text));
  if K=0 then Exit(R.Left);
  if K=Length(R.Text) then Exit(R.Left+R.Width);
  RunFont(ACanvas,R);
  Result := R.Left+ACanvas.TextWidth(Copy(R.Text,1,K));
end;

function TInkRunText.OffsetAt(ACanvas: TCanvas; X, Y: Integer): Integer;
var K,Best,BestDY,BestDX,DY,DX,Prev,W,Len: Integer; R: TInkRun;
begin
  Result := 0;
  if FCount=0 then Exit;
  { the nearest line, then the nearest run on it }
  Best := 0; BestDY := MaxInt; BestDX := MaxInt;
  for K := 0 to FCount-1 do
  begin
    R := FRuns[K];
    if Y<R.Top then DY := R.Top-Y
    else if Y>=R.Top+R.LineHeight then DY := Y-(R.Top+R.LineHeight)+1
    else DY := 0;
    if X<R.Left then DX := R.Left-X
    else if X>R.Left+R.Width then DX := X-(R.Left+R.Width)
    else DX := 0;
    if (DY<BestDY) or ((DY=BestDY) and (DX<BestDX)) then
    begin Best := K; BestDY := DY; BestDX := DX end;
  end;
  R := FRuns[Best];
  Result := R.Start;
  if X<=R.Left then Exit;
  if X>=R.Left+R.Width then begin Result := R.Start+Length(R.Text); Exit end;
  { between the two characters whose middle it is nearest }
  RunFont(ACanvas,R);
  K := 1; Prev := 0;
  while K<=Length(R.Text) do
  begin
    Len := Max(1,UTF8CodepointSize(@R.Text[K]));
    W := ACanvas.TextWidth(Copy(R.Text,1,K+Len-1));
    if X-R.Left<(Prev+W) div 2 then Break;
    Result := R.Start+K+Len-1;
    Prev := W; Inc(K,Len);
  end;
end;

function TInkRunText.OverText(X, Y: Integer): Boolean;
var K: Integer; R: TInkRun;
begin
  Result := False;
  for K := 0 to FCount-1 do
  begin
    R := FRuns[K];
    if (X>=R.Left) and (X<R.Left+R.Width) and (Y>=R.Top) and (Y<R.Top+R.LineHeight) then
      Exit(True);
  end;
end;

procedure TInkRunText.WordAt(AOffset: Integer; out AFrom, ATo: Integer);
var A,Z: Integer; Kind: Boolean;
begin
  AFrom := EnsureRange(AOffset,0,Length(FWords)); ATo := AFrom;
  if FWords='' then Exit;
  A := AFrom;
  if A>=Length(FWords) then A := Length(FWords)-1;
  { the character after the place, as a browser takes it; a word, or a run
    of the same kind of not-word }
  Kind := IsWordByte(FWords[A+1]);
  if not Kind and (FWords[A+1] in [' ',#9]) and (A>0) and IsWordByte(FWords[A]) then
  begin Dec(A); Kind := True end;
  Z := A+1;
  while (A>0) and (IsWordByte(FWords[A])=Kind) and not (FWords[A] in [#10,#13]) do Dec(A);
  while (Z<Length(FWords)) and (IsWordByte(FWords[Z+1])=Kind) and not (FWords[Z+1] in [#10,#13]) do Inc(Z);
  if not Kind then
  begin
    { punctuation on its own is taken one character at a time }
    A := EnsureRange(AOffset,0,Length(FWords)-1);
    Z := A+1;
  end;
  AFrom := A; ATo := Z;
end;

procedure TInkRunText.PaintSelection(ACanvas: TCanvas; A, Z: Integer; ABack: TColor);
var K,SA,SZ,X1,X2,RunEnd: Integer; R: TInkRun; Space: Boolean;
begin
  if A>Z then begin K := A; A := Z; Z := K end;
  ACanvas.Brush.Color := ABack;
  for K := 0 to FCount-1 do
  begin
    R := FRuns[K];
    RunEnd := R.Start+Length(R.Text);
    SA := Max(A,R.Start); SZ := Min(Z,RunEnd);
    if SA>=SZ then Continue;
    X1 := RunX(ACanvas,R,SA); X2 := RunX(ACanvas,R,SZ);
    { a selection that runs on past the end of a line shows a little of
      the space it takes with it }
    Space := (SZ=RunEnd) and (Z>RunEnd) and
      ((K=FCount-1) or (FRuns[K+1].Line<>R.Line) or (FRuns[K+1].Part<>R.Part));
    if Space then begin RunFont(ACanvas,R); Inc(X2,ACanvas.TextWidth(' ')) end;
    { painted over the text, which is then drawn again on it: a span's own
      background would otherwise hide the selection }
    ACanvas.Brush.Style := bsSolid;
    ACanvas.FillRect(Rect(X1,R.Top,X2,R.Top+R.LineHeight));
    RunFont(ACanvas,R);
    ACanvas.Font.Color := R.FontColor;
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(X1,R.Top,Copy(R.Text,SA-R.Start+1,SZ-SA));
  end;
end;

function TInkRunText.TextRange(A, Z: Integer): string;
var K: Integer;
begin
  if A>Z then begin K := A; A := Z; Z := K end;
  A := EnsureRange(A,0,Length(FWords));
  Z := EnsureRange(Z,0,Length(FWords));
  Result := Copy(FWords,A+1,Z-A);
end;

finalization
  GEngine.Free;

end.
