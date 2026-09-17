{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkRichEdit: a multi-line WYSIWYG editor for the LazInk markup subset. The
  caret and the selection live inside the *rendered* text — select a word in
  bold red 16pt and the caret sits between the actual glyphs you can see. Hit
  the bold button and that run stops being bold. There is no source view to
  keep in sync, because the document is not markup: markup is only what it is
  read from and written back to.

  Every character carries its own colour, background, size, face, style,
  script and link. Nothing is drawn by a native text widget, so this behaves
  and looks identical on win32, gtk2, gtk3, qt5/6 and cocoa — the whole point
  of LazInk. No RichMemo, no per-widgetset backend.

  The document is a flat array of UTF-8 characters with a parallel array of
  attributes; a paragraph break is the single character #10. That keeps caret
  arithmetic, selection, insert and delete to one dimension. Everything
  two-dimensional (wrapping, line heights, baselines) is derived in Relayout
  and cached in FLines/FCharX/FCharW.

  License: MIT.
}
unit InkRichEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, StdCtrls, Forms, LCLType,
  LCLIntf, LMessages, Clipbrd, LazUTF8, ExtCtrls, Types;

type
  TInkScript = (isNormal, isSuperscript, isSubscript);

  { Everything one character can carry. The sentinels — clDefault, clNone, 0,
    '' — mean "follow the control's Font", so a document that never mentions a
    colour still tracks the control when the control's Font changes. }
  TInkAttr = record
    Color: TColor;        // clDefault -> Font.Color
    BackColor: TColor;    // clNone    -> transparent
    Size: Integer;        // 0         -> Font.Size
    Face: string;         // ''        -> Font.Name
    Style: TFontStyles;
    Script: TInkScript;
    Link: string;         // ''        -> not a link
    Align: TAlignment;    // paragraph property, held per character
  end;

  { One visual line: a run of characters that share a baseline. A paragraph is
    one line plus one more for every wrap point inside it. }
  TInkVisLine = record
    First: Integer;       // index of the first character
    Count: Integer;       // how many characters, including a trailing #10
    Top: Integer;         // y of the line's top, in document space
    Height: Integer;
    Ascent: Integer;      // baseline offset from Top
    Width: Integer;
    Left: Integer;        // x of the line's start, after alignment
  end;

  TInkRichLinkEvent = procedure(Sender: TObject; const LinkName: string) of object;

  { TInkRichEdit }

  TInkRichEdit = class(TCustomControl)
  private
    FChars: array of string;      // one UTF-8 codepoint each; #10 = paragraph
    FAttrs: array of TInkAttr;
    FCaret: Integer;              // 0..CharCount, a gap between characters
    FAnchor: Integer;             // selection anchor; = FCaret when none
    FLines: array of TInkVisLine;
    FCharX: array of Integer;     // x of each character within its own line
    FCharW: array of Integer;
    FLayoutValid: Boolean;
    FDocHeight: Integer;
    FScrollY: Integer;
    FVScroll: TScrollBar;
    FTypingAttr: TInkAttr;        // what the next typed character will wear
    FHasTypingAttr: Boolean;
    FMarkup: TStrings;            // one paragraph per line
    FMarkupDirty: Boolean;
    FSettingMarkup: Boolean;
    FCaretTimer: TTimer;
    FCaretOn: Boolean;
    FGoalX: Integer;              // remembered column for up/down
    FUndo: TFPList;
    FRedo: TFPList;
    FLastUndoTick: QWord;
    FReadOnly: Boolean;
    FWordWrap: Boolean;
    FSuperSubScriptRatio: Double;
    FModified: Boolean;
    FMouseOnLink: Boolean;
    FHoverLink: string;
    FOnChange: TNotifyEvent;
    FOnSelectionChange: TNotifyEvent;
    FOnLinkClick: TInkRichLinkEvent;
    function CharCount: Integer;
    function GetSelStart: Integer;
    function GetSelLength: Integer;
    procedure SetSelStart(AValue: Integer);
    procedure SetSelLength(AValue: Integer);
    function GetSelText: string;
    procedure SetMarkup(AValue: TStrings);
    function GetMarkup: TStrings;
    procedure MarkupChanged(Sender: TObject);
    procedure RebuildFromMarkup;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    { layout }
    procedure InvalidateLayout;
    procedure Relayout;
    procedure NeedLayout;
    procedure ApplyAttrToCanvas(const A: TInkAttr);
    function MeasureChar(AIndex: Integer): Integer;
    function LineOfChar(AIndex: Integer): Integer;
    function CaretLine(ACaret: Integer): Integer;
    function LineTextWidth: Integer;
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure ScrollToCaret;
    function CaretPoint(ACaret: Integer): TPoint;   // document space
    function PointToCaret(X, Y: Integer): Integer;  // client space
    { document }
    procedure DoInsert(const AText: string; const AAttr: TInkAttr);
    procedure DoDelete(AFrom, ATo: Integer);
    procedure DeleteSelection;
    function AttrAtCaret: TInkAttr;
    procedure Changed;
    procedure SelectionChanged;
    procedure MoveCaret(ANew: Integer; AExtend: Boolean);
    { markup }
    procedure ParseInto(const AMarkup: string; AParaBreakFirst: Boolean);
    procedure SyncMarkupFromDoc;
    { undo }
    procedure PushUndo(ACoalesce: Boolean);
    procedure ClearUndoList(AList: TFPList);
    procedure RestoreSnapshot(ASnap: TObject);
    function TakeSnapshot: TObject;
    procedure CaretTimerTick(Sender: TObject);
    procedure RestartCaretBlink;
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
  protected
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure FontChanged(Sender: TObject); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Click; override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    class function GetControlClassDefaultSize: TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Clear;
    procedure SelectAll;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;

    { Formatting. With a selection they change it; with none they set what the
      next typed character will wear, the way every editor behaves. }
    procedure ApplyStyle(AStyle: TFontStyle; AOn: Boolean);
    procedure ToggleStyle(AStyle: TFontStyle);
    procedure ApplyColor(AColor: TColor);
    procedure ApplyBackColor(AColor: TColor);
    procedure ApplySize(ASize: Integer);
    procedure ApplyFace(const AFace: string);
    procedure ApplyScript(AScript: TInkScript);
    procedure ApplyLink(const AHref: string);
    procedure ApplyAlignment(AAlign: TAlignment);
    procedure ClearFormatting;
    procedure InsertParagraph;

    { What the toolbar should show as pressed: the value shared by the whole
      selection, or the sentinel when the selection disagrees with itself. }
    function SelStyle: TFontStyles;
    function SelColor: TColor;
    function SelBackColor: TColor;
    function SelSize: Integer;
    function SelFace: string;
    function SelScript: TInkScript;
    function SelAlignment: TAlignment;

    { The document as markup, paragraphs joined with ASep. Feed it straight to
      a TInkLabel caption or a TInkMemo line. }
    function AsHTML(const ASep: string = '<br>'): string;
    function PlainText: string;
    property SelText: string read GetSelText;
    property Modified: Boolean read FModified write FModified;
    { runtime only - a stored caret position would be meaningless in a .lfm }
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
  published
    { One paragraph per line. Editable in the Object Inspector, so a design-time
      document is real markup in the .lfm and renders in the form designer. }
    property Markup: TStrings read GetMarkup write SetMarkup;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default True;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnLinkClick: TInkRichLinkEvent read FOnLinkClick write FOnLinkClick;

    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle default bsSingle;
    property Color default clWindow;
    property Constraints;
    property Enabled;
    property Font;
    property Hint;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    property TabStop default True;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
    property OnUTF8KeyPress;
  end;

function DefaultInkAttr: TInkAttr;
function SameInkAttr(const A, B: TInkAttr): Boolean;

implementation

uses
  InkHtml, InkTouch;

const
  cMargin = 3;
  cScrollBarWidth = 16;
  cUndoDepth = 200;
  cUndoCoalesceMs = 700;

type
  { A whole-document snapshot. Documents in an editor like this are small, and
    a snapshot that cannot be subtly wrong beats a delta log that can. }
  TInkSnapshot = class
    Chars: array of string;
    Attrs: array of TInkAttr;
    Caret: Integer;
    Anchor: Integer;
  end;

var
  { Copying inside the app keeps the formatting: the plain text goes to the
    system clipboard as usual, and the attributes are parked here. A paste
    only uses them when the clipboard still holds the very text they belong
    to, so pasting from another app can never pick up stale styling. }
  gClipText: string = '';
  gClipAttrs: array of TInkAttr;

function DefaultInkAttr: TInkAttr;
begin
  Result.Color := clDefault;
  Result.BackColor := clNone;
  Result.Size := 0;
  Result.Face := '';
  Result.Style := [];
  Result.Script := isNormal;
  Result.Link := '';
  Result.Align := taLeftJustify;
end;

function SameInkAttr(const A, B: TInkAttr): Boolean;
begin
  Result := (A.Color = B.Color) and (A.BackColor = B.BackColor) and
    (A.Size = B.Size) and (A.Face = B.Face) and (A.Style = B.Style) and
    (A.Script = B.Script) and (A.Link = B.Link) and (A.Align = B.Align);
end;

{ '#RRGGBB' for a real colour, '' for the sentinels }
function InkColorToHTML(C: TColor): string;
var
  RGB: LongInt;
begin
  if (C = clDefault) or (C = clNone) then
    Exit('');
  RGB := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x', [Red(RGB), Green(RGB), Blue(RGB)]);
end;

{ TInkRichEdit }

procedure TInkRichEdit.CreateWnd;
begin
  inherited CreateWnd;
  { a finger places the caret and selects, as the mouse does }
  InkHookTouchAsMouse(Self);
end;

constructor TInkRichEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse, csOpaque, csRequiresKeyboardInput]
    - [csSetCaption];
  BorderStyle := bsSingle;
  TabStop := True;
  Cursor := crIBeam;
  Color := clWindow;
  Font.Color := clWindowText;
  FWordWrap := True;
  FSuperSubScriptRatio := 0.7;
  FCaret := 0;
  FAnchor := 0;
  FGoalX := -1;
  FTypingAttr := DefaultInkAttr;
  FMarkup := TStringList.Create;
  // Markup is a TStrings people will write to in place - "Markup.Text := x",
  // "Markup.Add(...)", the Object Inspector's string editor - and none of that
  // goes through the property setter. Listening to the list itself is the only
  // way to hear about all of it.
  TStringList(FMarkup).OnChange := @MarkupChanged;
  FUndo := TFPList.Create;
  FRedo := TFPList.Create;

  FVScroll := TScrollBar.Create(Self);
  FVScroll.Kind := sbVertical;
  FVScroll.Parent := Self;
  FVScroll.TabStop := False;
  FVScroll.Visible := False;
  FVScroll.Width := cScrollBarWidth;
  FVScroll.OnChange := @ScrollBarChange;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.Enabled := False;
  FCaretTimer.OnTimer := @CaretTimerTick;

  with GetControlClassDefaultSize do
    SetInitialBounds(0, 0, cx, cy);
end;

destructor TInkRichEdit.Destroy;
begin
  ClearUndoList(FUndo);
  ClearUndoList(FRedo);
  FreeAndNil(FUndo);
  FreeAndNil(FRedo);
  FreeAndNil(FMarkup);
  inherited Destroy;
end;

class function TInkRichEdit.GetControlClassDefaultSize: TSize;
begin
  Result.cx := 320;
  Result.cy := 200;
end;

function TInkRichEdit.CharCount: Integer;
begin
  Result := Length(FChars);
end;

{ ---------------------------------------------------------------- selection }

function TInkRichEdit.GetSelStart: Integer;
begin
  if FCaret < FAnchor then Result := FCaret else Result := FAnchor;
end;

function TInkRichEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

procedure TInkRichEdit.SetSelStart(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > CharCount then AValue := CharCount;
  FCaret := AValue;
  FAnchor := AValue;
  FHasTypingAttr := False;
  ScrollToCaret;
  RestartCaretBlink;
  Invalidate;
  SelectionChanged;
end;

procedure TInkRichEdit.SetSelLength(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FAnchor := GetSelStart;
  FCaret := FAnchor + AValue;
  if FCaret > CharCount then FCaret := CharCount;
  ScrollToCaret;
  Invalidate;
  SelectionChanged;
end;

function TInkRichEdit.GetSelText: string;
var
  i: Integer;
begin
  Result := '';
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

procedure TInkRichEdit.MoveCaret(ANew: Integer; AExtend: Boolean);
begin
  if ANew < 0 then ANew := 0;
  if ANew > CharCount then ANew := CharCount;
  FCaret := ANew;
  if not AExtend then FAnchor := FCaret;
  FHasTypingAttr := False;
  ScrollToCaret;
  RestartCaretBlink;
  Invalidate;
  SelectionChanged;
end;

procedure TInkRichEdit.SelectAll;
begin
  FAnchor := 0;
  FCaret := CharCount;
  Invalidate;
  SelectionChanged;
end;

{ ------------------------------------------------------------------- layout }

procedure TInkRichEdit.InvalidateLayout;
begin
  FLayoutValid := False;
  Invalidate;
end;

procedure TInkRichEdit.NeedLayout;
begin
  if not FLayoutValid then Relayout;
end;

procedure TInkRichEdit.ApplyAttrToCanvas(const A: TInkAttr);
var
  Sz: Integer;
begin
  if A.Face <> '' then
    Canvas.Font.Name := A.Face
  else
    Canvas.Font.Name := Font.Name;
  if A.Size > 0 then Sz := A.Size else Sz := Font.Size;
  if Sz = 0 then Sz := Screen.SystemFont.Size;
  if A.Script <> isNormal then
    Sz := Round(Sz * FSuperSubScriptRatio);
  if Sz < 1 then Sz := 1;
  Canvas.Font.Size := Sz;
  Canvas.Font.Style := A.Style;
  if A.Link <> '' then
  begin
    if A.Color = clDefault then
      Canvas.Font.Color := clBlue
    else
      Canvas.Font.Color := A.Color;
    Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
  end
  else if A.Color <> clDefault then
    Canvas.Font.Color := A.Color
  else if A.BackColor <> clNone then
    // highlighted, but nobody said what colour the text should be - so pick
    // one that can be read on that background rather than inheriting a
    // control colour that may well be invisible on it
    Canvas.Font.Color := HTMLContrastColor(A.BackColor)
  else
    Canvas.Font.Color := Font.Color;
end;

function TInkRichEdit.MeasureChar(AIndex: Integer): Integer;
begin
  if FChars[AIndex] = #10 then
    Result := 0
  else
    Result := Canvas.TextWidth(FChars[AIndex]);
end;

function TInkRichEdit.LineTextWidth: Integer;
begin
  Result := ClientWidth - 2 * cMargin;
  if FVScroll.Visible then Dec(Result, FVScroll.Width);
  if Result < 16 then Result := 16;
end;

procedure TInkRichEdit.Relayout;
var
  N, i, k, X, W, Avail, Y, LineStart, LastSpace, BreakAt: Integer;
  LineCount: Integer;
  LastAttr: TInkAttr;
  HasLast: Boolean;

  { Height and baseline of the characters [AFirst, AFirst+ACount). An empty
    paragraph still needs a line box, so fall back to the control font. }
  procedure EmitLine(AFirst, ACount: Integer);
  var
    j, H, Asc, MaxH, MaxAsc, Rise: Integer;
    tm: TLCLTextMetric;
    L: TInkVisLine;
    Al: TAlignment;
  begin
    Canvas.Font := Font;
    if Canvas.GetTextMetrics(tm) then
    begin
      MaxH := tm.Height;
      MaxAsc := tm.Ascender;
    end
    else
    begin
      MaxH := Canvas.TextHeight('Ag');
      MaxAsc := MaxH - (MaxH div 5);
    end;

    for j := AFirst to AFirst + ACount - 1 do
    begin
      if FChars[j] = #10 then Continue;
      ApplyAttrToCanvas(FAttrs[j]);
      if Canvas.GetTextMetrics(tm) then
      begin
        H := tm.Height;
        Asc := tm.Ascender;
      end
      else
      begin
        H := Canvas.TextHeight('Ag');
        Asc := H - (H div 5);
      end;
      // a raised run needs headroom above it, a lowered one below
      Rise := 0;
      if FAttrs[j].Script = isSuperscript then
        Rise := (MaxAsc * 35) div 100
      else if FAttrs[j].Script = isSubscript then
        Rise := -((MaxAsc * 18) div 100);
      if Asc + Rise > MaxAsc then MaxAsc := Asc + Rise;
      if H - Asc - Rise > MaxH - MaxAsc then MaxH := MaxAsc + (H - Asc - Rise);
    end;

    L.First := AFirst;
    L.Count := ACount;
    L.Top := Y;
    L.Height := MaxH + 1;
    L.Ascent := MaxAsc;
    if ACount > 0 then
      L.Width := FCharX[AFirst + ACount - 1] + FCharW[AFirst + ACount - 1]
    else
      L.Width := 0;
    if N = 0 then
      Al := taLeftJustify
    else if AFirst < N then
      Al := FAttrs[AFirst].Align
    else
      Al := FAttrs[N - 1].Align;
    case Al of
      taCenter: L.Left := cMargin + Max(0, (Avail - L.Width) div 2);
      taRightJustify: L.Left := cMargin + Max(0, Avail - L.Width);
    else
      L.Left := cMargin;
    end;

    if LineCount >= Length(FLines) then
      SetLength(FLines, Max(8, Length(FLines) * 2));
    FLines[LineCount] := L;
    Inc(LineCount);
    Inc(Y, L.Height);
    HasLast := False;   // canvas font was reset above
  end;

begin
  FLayoutValid := True;
  N := CharCount;
  SetLength(FCharX, N);
  SetLength(FCharW, N);
  SetLength(FLines, 0);
  LineCount := 0;
  Y := 0;
  Avail := LineTextWidth;
  LineStart := 0;
  X := 0;
  LastSpace := -1;
  HasLast := False;
  LastAttr := DefaultInkAttr;

  i := 0;
  while i < N do
  begin
    if FChars[i] = #10 then
    begin
      FCharX[i] := X;
      FCharW[i] := 0;
      EmitLine(LineStart, i - LineStart + 1);
      LineStart := i + 1;
      X := 0;
      LastSpace := -1;
      Inc(i);
      Continue;
    end;

    if (not HasLast) or (not SameInkAttr(LastAttr, FAttrs[i])) then
    begin
      ApplyAttrToCanvas(FAttrs[i]);
      LastAttr := FAttrs[i];
      HasLast := True;
    end;
    W := MeasureChar(i);

    if FWordWrap and (i > LineStart) and (X + W > Avail) then
    begin
      // break after the last blank if there was one, otherwise mid-word
      if LastSpace >= LineStart then
        BreakAt := LastSpace + 1
      else
        BreakAt := i;
      EmitLine(LineStart, BreakAt - LineStart);
      LineStart := BreakAt;
      X := 0;
      for k := BreakAt to i - 1 do
      begin
        FCharX[k] := X;
        Inc(X, FCharW[k]);
      end;
      LastSpace := -1;
      HasLast := False;
    end;

    FCharX[i] := X;
    FCharW[i] := W;
    Inc(X, W);
    // CJK writes without spaces, so every ideograph is somewhere a line may
    // break; otherwise a CJK paragraph would only ever break mid-character
    if (FChars[i] = ' ') or HTMLIsCJK(FChars[i]) then LastSpace := i;
    Inc(i);
  end;

  // the tail, and the empty line a document ending in #10 leaves behind
  EmitLine(LineStart, N - LineStart);
  SetLength(FLines, LineCount);
  FDocHeight := Y;
  UpdateScrollBar;
end;

function TInkRichEdit.LineOfChar(AIndex: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FLines) do
    if (AIndex >= FLines[i].First) and
       (AIndex < FLines[i].First + FLines[i].Count) then
      Exit(i);
  if Length(FLines) > 0 then Result := High(FLines);
end;

{ A caret on a wrap boundary could be claimed by either line; it goes to the
  start of the next one, except at the very end where there is no next one. }
function TInkRichEdit.CaretLine(ACaret: Integer): Integer;
var
  Idx: Integer;
begin
  NeedLayout;
  Result := High(FLines);
  if Length(FLines) = 0 then Exit(0);
  if ACaret >= CharCount then Exit(High(FLines));
  for Idx := 0 to High(FLines) do
    if ACaret < FLines[Idx].First + FLines[Idx].Count then
      Exit(Idx);
end;

function TInkRichEdit.CaretPoint(ACaret: Integer): TPoint;
var
  L: Integer;
begin
  NeedLayout;
  Result := Point(cMargin, 0);
  if Length(FLines) = 0 then Exit;
  L := CaretLine(ACaret);

  Result.Y := FLines[L].Top;
  if ACaret <= FLines[L].First then
    Result.X := FLines[L].Left
  else if ACaret >= FLines[L].First + FLines[L].Count then
    Result.X := FLines[L].Left + FLines[L].Width
  else
    Result.X := FLines[L].Left + FCharX[ACaret];
end;

function TInkRichEdit.PointToCaret(X, Y: Integer): Integer;
var
  L, i, DocY, CX, Last: Integer;
begin
  NeedLayout;
  if Length(FLines) = 0 then Exit(0);
  DocY := Y + FScrollY;

  L := High(FLines);
  for i := 0 to High(FLines) do
    if DocY < FLines[i].Top + FLines[i].Height then
    begin
      L := i;
      Break;
    end;
  if DocY < 0 then L := 0;

  Last := FLines[L].First + FLines[L].Count;
  // never let a click land past a paragraph break: that gap belongs to the
  // start of the next line, and putting the caret there looks like a bug
  if (FLines[L].Count > 0) and (FChars[Last - 1] = #10) then Dec(Last);

  Result := Last;
  for i := FLines[L].First to Last - 1 do
  begin
    CX := FLines[L].Left + FCharX[i] + (FCharW[i] div 2);
    if X < CX then
      Exit(i);
  end;
end;

{ --------------------------------------------------------------- scrolling  }

procedure TInkRichEdit.UpdateScrollBar;
var
  NeedBar: Boolean;
begin
  if FVScroll = nil then Exit;
  NeedBar := FDocHeight > ClientHeight;
  if NeedBar <> FVScroll.Visible then
  begin
    FVScroll.Visible := NeedBar;
    // the text column just got narrower or wider, so everything must re-flow
    FLayoutValid := False;
  end;
  if NeedBar then
  begin
    FVScroll.SetBounds(ClientWidth - cScrollBarWidth, 0, cScrollBarWidth,
      ClientHeight);
    FVScroll.Min := 0;
    FVScroll.Max := FDocHeight;
    FVScroll.PageSize := ClientHeight;
    FVScroll.LargeChange := ClientHeight;
    FVScroll.SmallChange := 16;
    if FScrollY > FDocHeight - ClientHeight then
      FScrollY := FDocHeight - ClientHeight;
    if FScrollY < 0 then FScrollY := 0;
    if FVScroll.Position <> FScrollY then
      FVScroll.Position := FScrollY;
  end
  else
    FScrollY := 0;
end;

procedure TInkRichEdit.ScrollBarChange(Sender: TObject);
begin
  if FScrollY = FVScroll.Position then Exit;
  FScrollY := FVScroll.Position;
  Invalidate;
end;

procedure TInkRichEdit.ScrollToCaret;
var
  P: TPoint;
  L, H: Integer;
begin
  if not HandleAllocated then Exit;
  NeedLayout;
  P := CaretPoint(FCaret);
  if Length(FLines) = 0 then Exit;
  L := CaretLine(FCaret);
  H := FLines[L].Height;

  if P.Y < FScrollY then
    FScrollY := P.Y
  else if P.Y + H > FScrollY + ClientHeight then
    FScrollY := P.Y + H - ClientHeight;
  if FScrollY > FDocHeight - ClientHeight then
    FScrollY := FDocHeight - ClientHeight;
  if FScrollY < 0 then FScrollY := 0;
  if FVScroll.Visible and (FVScroll.Position <> FScrollY) then
    FVScroll.Position := FScrollY;
end;

function TInkRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not FVScroll.Visible then Exit;
  FScrollY := FScrollY - (WheelDelta * 3) div 8;
  if FScrollY > FDocHeight - ClientHeight then
    FScrollY := FDocHeight - ClientHeight;
  if FScrollY < 0 then FScrollY := 0;
  FVScroll.Position := FScrollY;
  Invalidate;
  Result := True;
end;

{ ------------------------------------------------------------------ painting }

procedure TInkRichEdit.Paint;
var
  Li, i, RunEnd, SelA, SelB, LineEndIdx, BaseY, RunTop: Integer;
  S: string;
  Sel, RunSel: Boolean;
  L: TInkVisLine;
  tm: TLCLTextMetric;
  RunAsc, RunH, Rise, X: Integer;

  function IsSel(AIdx: Integer): Boolean;
  begin
    Result := (AIdx >= SelA) and (AIdx < SelB);
  end;

begin
  Canvas.Brush.Color := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  NeedLayout;
  SelA := GetSelStart;
  SelB := SelA + GetSelLength;

  for Li := 0 to High(FLines) do
  begin
    L := FLines[Li];
    if L.Top + L.Height - FScrollY < 0 then Continue;
    if L.Top - FScrollY > ClientHeight then Break;

    BaseY := L.Top - FScrollY + L.Ascent;
    LineEndIdx := L.First + L.Count;

    i := L.First;
    while i < LineEndIdx do
    begin
      if FChars[i] = #10 then
      begin
        // a selected paragraph break shows as a thin bar, so selecting across
        // paragraphs looks like it selected something
        if IsSel(i) then
        begin
          Canvas.Brush.Color := clHighlight;
          Canvas.Brush.Style := bsSolid;
          Canvas.FillRect(L.Left + FCharX[i], L.Top - FScrollY,
            L.Left + FCharX[i] + 4, L.Top - FScrollY + L.Height);
        end;
        Inc(i);
        Continue;
      end;

      RunSel := IsSel(i);
      RunEnd := i;
      while (RunEnd + 1 < LineEndIdx) and (FChars[RunEnd + 1] <> #10) and
        SameInkAttr(FAttrs[RunEnd + 1], FAttrs[i]) and
        (IsSel(RunEnd + 1) = RunSel) do
        Inc(RunEnd);

      S := '';
      for RunTop := i to RunEnd do
        S := S + FChars[RunTop];

      ApplyAttrToCanvas(FAttrs[i]);
      if Canvas.GetTextMetrics(tm) then
      begin
        RunAsc := tm.Ascender;
        RunH := tm.Height;
      end
      else
      begin
        RunH := Canvas.TextHeight('Ag');
        RunAsc := RunH - (RunH div 5);
      end;
      Rise := 0;
      if FAttrs[i].Script = isSuperscript then
        Rise := (L.Ascent * 35) div 100
      else if FAttrs[i].Script = isSubscript then
        Rise := -((L.Ascent * 18) div 100);

      X := L.Left + FCharX[i];
      RunTop := BaseY - RunAsc - Rise;

      Sel := RunSel and (Focused or (SelB > SelA));
      if Sel then
      begin
        Canvas.Brush.Color := clHighlight;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(X, L.Top - FScrollY,
          L.Left + FCharX[RunEnd] + FCharW[RunEnd], L.Top - FScrollY + L.Height);
        Canvas.Font.Color := clHighlightText;
        Canvas.Brush.Style := bsClear;
      end
      else if FAttrs[i].BackColor <> clNone then
      begin
        Canvas.Brush.Color := FAttrs[i].BackColor;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(X, RunTop, L.Left + FCharX[RunEnd] + FCharW[RunEnd],
          RunTop + RunH);
        Canvas.Brush.Style := bsClear;
      end
      else
        Canvas.Brush.Style := bsClear;

      Canvas.TextOut(X, RunTop, S);
      i := RunEnd + 1;
    end;
  end;

  if Focused and FCaretOn and (GetSelLength = 0) then
  begin
    if Length(FLines) > 0 then
    begin
      Li := CaretLine(FCaret);
      X := CaretPoint(FCaret).X;
      BaseY := CaretPoint(FCaret).Y - FScrollY;
      Canvas.Pen.Color := Font.Color;
      Canvas.Line(X, BaseY + 1, X, BaseY + FLines[Li].Height - 1);
      Canvas.Line(X + 1, BaseY + 1, X + 1, BaseY + FLines[Li].Height - 1);
    end;
  end;
end;

procedure TInkRichEdit.Resize;
begin
  inherited Resize;
  InvalidateLayout;
  if FVScroll <> nil then
    UpdateScrollBar;
end;

procedure TInkRichEdit.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  InvalidateLayout;
end;

procedure TInkRichEdit.CaretTimerTick(Sender: TObject);
begin
  FCaretOn := not FCaretOn;
  Invalidate;
end;

procedure TInkRichEdit.RestartCaretBlink;
begin
  FCaretOn := True;
  if Focused then
  begin
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
  end;
end;

procedure TInkRichEdit.DoEnter;
begin
  inherited DoEnter;
  FCaretOn := True;
  FCaretTimer.Enabled := True;
  Invalidate;
end;

procedure TInkRichEdit.DoExit;
begin
  inherited DoExit;
  FCaretTimer.Enabled := False;
  FCaretOn := False;
  Invalidate;
end;

{ ------------------------------------------------------------------ document }

function TInkRichEdit.AttrAtCaret: TInkAttr;
begin
  if FHasTypingAttr then
    Exit(FTypingAttr);
  if GetSelLength > 0 then
    Result := FAttrs[GetSelStart]
  else if (FCaret > 0) and (FCaret <= CharCount) and (FChars[FCaret - 1] <> #10) then
    Result := FAttrs[FCaret - 1]      // inherit from the character to the left
  else if FCaret < CharCount then
    Result := FAttrs[FCaret]
  else
    Result := DefaultInkAttr;
  Result.Link := '';                  // typing never extends a link by accident
end;

procedure TInkRichEdit.DoInsert(const AText: string; const AAttr: TInkAttr);
var
  Incoming: array of string;
  P: PChar;
  CharLen, N, i, Old: Integer;
begin
  if AText = '' then Exit;
  N := 0;
  SetLength(Incoming, UTF8Length(AText));
  P := PChar(AText);
  while P^ <> #0 do
  begin
    CharLen := UTF8CodepointSize(P);
    SetString(Incoming[N], P, CharLen);
    Inc(N);
    Inc(P, CharLen);
  end;
  if N = 0 then Exit;

  Old := CharCount;
  SetLength(FChars, Old + N);
  SetLength(FAttrs, Old + N);
  for i := Old + N - 1 downto FCaret + N do
  begin
    FChars[i] := FChars[i - N];
    FAttrs[i] := FAttrs[i - N];
  end;
  for i := 0 to N - 1 do
  begin
    FChars[FCaret + i] := Incoming[i];
    FAttrs[FCaret + i] := AAttr;
  end;
  Inc(FCaret, N);
  FAnchor := FCaret;
  Changed;
end;

procedure TInkRichEdit.DoDelete(AFrom, ATo: Integer);
var
  i, N: Integer;
begin
  if ATo <= AFrom then Exit;
  if AFrom < 0 then AFrom := 0;
  if ATo > CharCount then ATo := CharCount;
  N := ATo - AFrom;
  for i := ATo to CharCount - 1 do
  begin
    FChars[AFrom + (i - ATo)] := FChars[i];
    FAttrs[AFrom + (i - ATo)] := FAttrs[i];
  end;
  SetLength(FChars, CharCount - N);
  SetLength(FAttrs, Length(FChars));
  FCaret := AFrom;
  FAnchor := AFrom;
  Changed;
end;

procedure TInkRichEdit.DeleteSelection;
begin
  DoDelete(GetSelStart, GetSelStart + GetSelLength);
end;

procedure TInkRichEdit.Changed;
begin
  FModified := True;
  FMarkupDirty := True;
  FHasTypingAttr := False;
  InvalidateLayout;
  ScrollToCaret;
  RestartCaretBlink;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.SelectionChanged;
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TInkRichEdit.Clear;
begin
  PushUndo(False);
  SetLength(FChars, 0);
  SetLength(FAttrs, 0);
  FCaret := 0;
  FAnchor := 0;
  FScrollY := 0;
  Changed;
end;

procedure TInkRichEdit.InsertParagraph;
begin
  if FReadOnly then Exit;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  DoInsert(#10, AttrAtCaret);
end;

{ -------------------------------------------------------------- formatting  }

procedure TInkRichEdit.ApplyStyle(AStyle: TFontStyle; AOn: Boolean);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    if AOn then
      FTypingAttr.Style := FTypingAttr.Style + [AStyle]
    else
      FTypingAttr.Style := FTypingAttr.Style - [AStyle];
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    if AOn then
      FAttrs[i].Style := FAttrs[i].Style + [AStyle]
    else
      FAttrs[i].Style := FAttrs[i].Style - [AStyle];
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ToggleStyle(AStyle: TFontStyle);
begin
  ApplyStyle(AStyle, not (AStyle in SelStyle));
end;

{ The four value-setters below all do the same dance, so they share it. }
procedure TInkRichEdit.ApplyColor(AColor: TColor);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Color := AColor;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Color := AColor;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyBackColor(AColor: TColor);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.BackColor := AColor;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].BackColor := AColor;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplySize(ASize: Integer);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Size := ASize;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Size := ASize;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyFace(const AFace: string);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Face := AFace;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Face := AFace;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyScript(AScript: TInkScript);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Script := AScript;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Script := AScript;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyLink(const AHref: string);
var
  i: Integer;
begin
  if FReadOnly or (GetSelLength = 0) then Exit;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Link := AHref;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ Alignment belongs to whole paragraphs, so the selection is widened out to
  paragraph boundaries before it is applied. }
procedure TInkRichEdit.ApplyAlignment(AAlign: TAlignment);
var
  i, A, B: Integer;
begin
  if FReadOnly or (CharCount = 0) then Exit;
  PushUndo(False);
  A := GetSelStart;
  B := GetSelStart + GetSelLength;
  while (A > 0) and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> #10) do Inc(B);
  for i := A to B - 1 do
    FAttrs[i].Align := AAlign;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ClearFormatting;
var
  i: Integer;
  Keep: TAlignment;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := DefaultInkAttr;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
  begin
    Keep := FAttrs[i].Align;          // alignment is not character formatting
    FAttrs[i] := DefaultInkAttr;
    FAttrs[i].Align := Keep;
  end;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ ------------------------------------------------------- selection queries  }

function TInkRichEdit.SelStyle: TFontStyles;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Style);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Style);
  Result := FAttrs[A].Style;
  for i := A + 1 to B - 1 do
    Result := Result * FAttrs[i].Style;   // only what every character agrees on
end;

function TInkRichEdit.SelColor: TColor;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Color);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Color);
  Result := FAttrs[A].Color;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Color <> Result then Exit(clDefault);
end;

function TInkRichEdit.SelBackColor: TColor;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.BackColor);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.BackColor);
  Result := FAttrs[A].BackColor;
  for i := A + 1 to B - 1 do
    if FAttrs[i].BackColor <> Result then Exit(clNone);
end;

function TInkRichEdit.SelSize: Integer;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Size);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Size);
  Result := FAttrs[A].Size;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Size <> Result then Exit(0);
end;

function TInkRichEdit.SelFace: string;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Face);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Face);
  Result := FAttrs[A].Face;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Face <> Result then Exit('');
end;

function TInkRichEdit.SelScript: TInkScript;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Script);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Script);
  Result := FAttrs[A].Script;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Script <> Result then Exit(isNormal);
end;

function TInkRichEdit.SelAlignment: TAlignment;
begin
  if CharCount = 0 then Exit(taLeftJustify);
  if FCaret < CharCount then
    Result := FAttrs[FCaret].Align
  else
    Result := FAttrs[CharCount - 1].Align;
end;

{ ----------------------------------------------------------------- keyboard }

procedure TInkRichEdit.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  case Message.CharCode of
    VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_PRIOR, VK_NEXT,
    VK_RETURN:
      Message.Result := 1;      // an editor eats its own navigation keys
  else
    inherited;
  end;
end;

procedure TInkRichEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  Ext: Boolean;
  L, Target, i, Best, BestDX, DX: Integer;
  P: TPoint;

  { Home/End within the visual line the caret sits on }
  function LineHome(ALine: Integer): Integer;
  begin
    Result := FLines[ALine].First;
  end;

  function LineEnd(ALine: Integer): Integer;
  begin
    Result := FLines[ALine].First + FLines[ALine].Count;
    if (FLines[ALine].Count > 0) and (FChars[Result - 1] = #10) then Dec(Result);
  end;

begin
  inherited KeyDown(Key, Shift);
  if Key = 0 then Exit;
  NeedLayout;
  Ext := ssShift in Shift;

  case Key of
    VK_LEFT:
      begin
        if (GetSelLength > 0) and not Ext then
          MoveCaret(GetSelStart, False)
        else
          MoveCaret(FCaret - 1, Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if (GetSelLength > 0) and not Ext then
          MoveCaret(GetSelStart + GetSelLength, False)
        else
          MoveCaret(FCaret + 1, Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
      begin
        if Length(FLines) > 0 then
        begin
          P := CaretPoint(FCaret);
          if FGoalX < 0 then FGoalX := P.X;
          L := CaretLine(FCaret);
          case Key of
            VK_UP: Target := L - 1;
            VK_DOWN: Target := L + 1;
            VK_PRIOR: Target := L - Max(1, ClientHeight div Max(FLines[L].Height, 1));
          else
            Target := L + Max(1, ClientHeight div Max(FLines[L].Height, 1));
          end;
          if Target < 0 then Target := 0;
          if Target > High(FLines) then Target := High(FLines);

          // land on whichever character on the target line is nearest the
          // column we set out from, so up-then-down comes back where it began
          Best := LineHome(Target);
          BestDX := MaxInt;
          for i := LineHome(Target) to LineEnd(Target) do
          begin
            if i < FLines[Target].First + FLines[Target].Count then
              DX := Abs(FLines[Target].Left + FCharX[i] - FGoalX)
            else
              DX := Abs(FLines[Target].Left + FLines[Target].Width - FGoalX);
            if i = LineEnd(Target) then
              DX := Abs(FLines[Target].Left + FLines[Target].Width - FGoalX);
            if DX < BestDX then
            begin
              BestDX := DX;
              Best := i;
            end;
          end;
          L := FGoalX;
          MoveCaret(Best, Ext);
          FGoalX := L;              // MoveCaret must not forget the column
        end;
        Key := 0;
      end;
    VK_HOME:
      begin
        if ssCtrl in Shift then
          MoveCaret(0, Ext)
        else
          MoveCaret(LineHome(CaretLine(FCaret)), Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_END:
      begin
        if ssCtrl in Shift then
          MoveCaret(CharCount, Ext)
        else
        begin
          MoveCaret(LineEnd(CaretLine(FCaret)), Ext);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_RETURN:
      begin
        if not FReadOnly then InsertParagraph;
        FGoalX := -1;
        Key := 0;
      end;
    VK_BACK:
      begin
        if not FReadOnly then
        begin
          PushUndo(True);
          if GetSelLength > 0 then
            DeleteSelection
          else if FCaret > 0 then
            DoDelete(FCaret - 1, FCaret);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_DELETE:
      begin
        if not FReadOnly then
        begin
          PushUndo(True);
          if GetSelLength > 0 then
            DeleteSelection
          else if FCaret < CharCount then
            DoDelete(FCaret, FCaret + 1);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_A: if ssCtrl in Shift then begin SelectAll; Key := 0; end;
    VK_C: if ssCtrl in Shift then begin CopyToClipboard; Key := 0; end;
    VK_X: if ssCtrl in Shift then begin CutToClipboard; Key := 0; end;
    VK_V: if ssCtrl in Shift then begin PasteFromClipboard; Key := 0; end;
    VK_Z: if ssCtrl in Shift then
          begin
            if ssShift in Shift then Redo else Undo;
            Key := 0;
          end;
    VK_Y: if ssCtrl in Shift then begin Redo; Key := 0; end;
    VK_B: if ssCtrl in Shift then begin ToggleStyle(fsBold); Key := 0; end;
    VK_I: if ssCtrl in Shift then begin ToggleStyle(fsItalic); Key := 0; end;
    VK_U: if ssCtrl in Shift then begin ToggleStyle(fsUnderline); Key := 0; end;
  end;
end;

procedure TInkRichEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  A: TInkAttr;
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < #32) then Exit;
  if FReadOnly then Exit;

  A := AttrAtCaret;
  PushUndo(True);
  if GetSelLength > 0 then DeleteSelection;
  DoInsert(UTF8Key, A);
  FGoalX := -1;
  UTF8Key := '';
end;

{ -------------------------------------------------------------------- mouse }

procedure TInkRichEdit.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if CanSetFocus then SetFocus;
    FCaret := PointToCaret(X, Y);
    if not (ssShift in Shift) then FAnchor := FCaret;
    FGoalX := -1;
    FHasTypingAttr := False;
    RestartCaretBlink;
    Invalidate;
    SelectionChanged;
  end;
end;

procedure TInkRichEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if ssLeft in Shift then
  begin
    FCaret := PointToCaret(X, Y);
    ScrollToCaret;
    Invalidate;
    SelectionChanged;
    Exit;
  end;

  FMouseOnLink := False;
  FHoverLink := '';
  Idx := PointToCaret(X, Y);
  if (Idx >= 0) and (Idx < CharCount) and (FAttrs[Idx].Link <> '') then
  begin
    FMouseOnLink := True;
    FHoverLink := FAttrs[Idx].Link;
  end;
  if FMouseOnLink and (ssCtrl in Shift) then
    Cursor := crHandPoint
  else
    Cursor := crIBeam;
end;

procedure TInkRichEdit.Click;
begin
  inherited Click;
  // ctrl+click follows a link; a plain click has to keep placing the caret,
  // or the text under a link would be uneditable
  if FMouseOnLink and (FHoverLink <> '') and Assigned(FOnLinkClick) and
    (GetKeyState(VK_CONTROL) < 0) then
    FOnLinkClick(Self, FHoverLink);
end;

procedure TInkRichEdit.DblClick;
var
  A, B: Integer;
begin
  inherited DblClick;
  if CharCount = 0 then Exit;
  A := Min(FCaret, CharCount - 1);
  B := A;
  while (A > 0) and (FChars[A - 1] <> ' ') and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> ' ') and (FChars[B] <> #10) do Inc(B);
  FAnchor := A;
  FCaret := B;
  Invalidate;
  SelectionChanged;
end;

{ ---------------------------------------------------------------- clipboard */ }

procedure TInkRichEdit.CopyToClipboard;
var
  i, A, N: Integer;
begin
  if GetSelLength = 0 then Exit;
  A := GetSelStart;
  N := GetSelLength;
  gClipText := GetSelText;
  SetLength(gClipAttrs, N);
  for i := 0 to N - 1 do
    gClipAttrs[i] := FAttrs[A + i];
  Clipboard.AsText := gClipText;
end;

procedure TInkRichEdit.CutToClipboard;
begin
  CopyToClipboard;
  if FReadOnly or (GetSelLength = 0) then Exit;
  PushUndo(False);
  DeleteSelection;
end;

procedure TInkRichEdit.PasteFromClipboard;
var
  S: string;
  i, At: Integer;
  A: TInkAttr;
begin
  if FReadOnly then Exit;
  if not Clipboard.HasFormat(CF_TEXT) then Exit;
  S := Clipboard.AsText;
  if S = '' then Exit;

  A := AttrAtCaret;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  At := FCaret;

  S := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  S := StringReplace(S, #13, #10, [rfReplaceAll]);
  DoInsert(S, A);

  // same text we put there, so the formatting that went with it is still good
  if (gClipText <> '') and (Length(gClipAttrs) > 0) and
     (StringReplace(gClipText, LineEnding, #10, [rfReplaceAll]) = S) then
    for i := 0 to Length(gClipAttrs) - 1 do
      if At + i < CharCount then
        FAttrs[At + i] := gClipAttrs[i];
  InvalidateLayout;
end;

{ --------------------------------------------------------------------- undo */ }

function TInkRichEdit.TakeSnapshot: TObject;
var
  S: TInkSnapshot;
  i: Integer;
begin
  S := TInkSnapshot.Create;
  SetLength(S.Chars, CharCount);
  SetLength(S.Attrs, CharCount);
  for i := 0 to CharCount - 1 do
  begin
    S.Chars[i] := FChars[i];
    S.Attrs[i] := FAttrs[i];
  end;
  S.Caret := FCaret;
  S.Anchor := FAnchor;
  Result := S;
end;

procedure TInkRichEdit.RestoreSnapshot(ASnap: TObject);
var
  S: TInkSnapshot;
  i: Integer;
begin
  S := TInkSnapshot(ASnap);
  SetLength(FChars, Length(S.Chars));
  SetLength(FAttrs, Length(S.Attrs));
  for i := 0 to High(S.Chars) do
  begin
    FChars[i] := S.Chars[i];
    FAttrs[i] := S.Attrs[i];
  end;
  FCaret := Min(S.Caret, CharCount);
  FAnchor := Min(S.Anchor, CharCount);
  Changed;
end;

procedure TInkRichEdit.ClearUndoList(AList: TFPList);
var
  i: Integer;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    TObject(AList[i]).Free;
  AList.Clear;
end;

{ ACoalesce folds a run of keystrokes into one undo step, so ctrl+Z takes back
  a word rather than a letter. }
procedure TInkRichEdit.PushUndo(ACoalesce: Boolean);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  if ACoalesce and (FUndo.Count > 0) and (Now - FLastUndoTick < cUndoCoalesceMs) then
  begin
    FLastUndoTick := Now;
    Exit;
  end;
  FLastUndoTick := Now;
  FUndo.Add(TakeSnapshot);
  while FUndo.Count > cUndoDepth do
  begin
    TObject(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
  ClearUndoList(FRedo);
end;

function TInkRichEdit.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

function TInkRichEdit.CanRedo: Boolean;
begin
  Result := FRedo.Count > 0;
end;

procedure TInkRichEdit.Undo;
var
  Snap: TObject;
begin
  if FUndo.Count = 0 then Exit;
  FRedo.Add(TakeSnapshot);
  Snap := TObject(FUndo[FUndo.Count - 1]);
  FUndo.Delete(FUndo.Count - 1);
  RestoreSnapshot(Snap);
  Snap.Free;
  FLastUndoTick := 0;
end;

procedure TInkRichEdit.Redo;
var
  Snap: TObject;
begin
  if FRedo.Count = 0 then Exit;
  FUndo.Add(TakeSnapshot);
  Snap := TObject(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  RestoreSnapshot(Snap);
  Snap.Free;
  FLastUndoTick := 0;
end;

{ ------------------------------------------------------------------- markup */ }

procedure TInkRichEdit.SetReadOnly(AValue: Boolean);
begin
  FReadOnly := AValue;
end;

procedure TInkRichEdit.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  InvalidateLayout;
end;

function TInkRichEdit.GetMarkup: TStrings;
begin
  if FMarkupDirty then SyncMarkupFromDoc;
  Result := FMarkup;
end;

procedure TInkRichEdit.SetMarkup(AValue: TStrings);
begin
  FMarkup.Assign(AValue);   // fires MarkupChanged, which rebuilds the document
end;

procedure TInkRichEdit.MarkupChanged(Sender: TObject);
begin
  if FSettingMarkup then Exit;   // this is our own SyncMarkupFromDoc talking
  RebuildFromMarkup;
end;

procedure TInkRichEdit.RebuildFromMarkup;
var
  i: Integer;
begin
  FSettingMarkup := True;
  try
    SetLength(FChars, 0);
    SetLength(FAttrs, 0);
    for i := 0 to FMarkup.Count - 1 do
      ParseInto(FMarkup[i], i > 0);
    FCaret := 0;
    FAnchor := 0;
    FScrollY := 0;
    FHasTypingAttr := False;
    FMarkupDirty := False;
    ClearUndoList(FUndo);
    ClearUndoList(FRedo);
    FModified := False;
    InvalidateLayout;
  finally
    FSettingMarkup := False;
  end;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ Reads one paragraph of markup onto the end of the document. A stack of
  attributes mirrors the tag nesting: an opening tag pushes a modified copy,
  a closing tag pops back to what was in force before it. }
procedure TInkRichEdit.ParseInto(const AMarkup: string; AParaBreakFirst: Boolean);
var
  Stack: array of TInkAttr;
  Cur: TInkAttr;
  P, Len, Start, N: Integer;
  TagStr, Nm, Val: string;
  Body: string;
  Up: string;

  procedure Push;
  begin
    SetLength(Stack, Length(Stack) + 1);
    Stack[High(Stack)] := Cur;
  end;

  procedure Pop;
  begin
    if Length(Stack) = 0 then Exit;
    Cur := Stack[High(Stack)];
    SetLength(Stack, Length(Stack) - 1);
  end;

  procedure Emit(const S: string);
  var
    Q: PChar;
    CharLen, Old, k: Integer;
    Txt: string;
  begin
    if S = '' then Exit;
    Txt := S;
    Old := CharCount;
    k := UTF8Length(Txt);
    SetLength(FChars, Old + k);
    SetLength(FAttrs, Old + k);
    Q := PChar(Txt);
    k := Old;
    while Q^ <> #0 do
    begin
      CharLen := UTF8CodepointSize(Q);
      SetString(FChars[k], Q, CharLen);
      FAttrs[k] := Cur;
      Inc(k);
      Inc(Q, CharLen);
    end;
  end;

  procedure EmitBreak;
  begin
    SetLength(FChars, CharCount + 1);
    SetLength(FAttrs, Length(FChars));
    FChars[High(FChars)] := #10;
    FAttrs[High(FAttrs)] := Cur;
  end;

  { The value of APropName inside ATag, in the case it was written in - a font
    family name is not case insensitive to the font matcher. }
  function PropOf(const ATag, APropName: string): string;
  var
    ip, j: Integer;
    R: string;
    Q: Char;
  begin
    Result := '';
    ip := Pos(APropName, UpperCase(ATag));
    if ip = 0 then Exit;
    R := Copy(ATag, ip + Length(APropName), Length(ATag));
    R := TrimLeft(R);
    if (R = '') or (R[1] <> '=') then Exit;
    Delete(R, 1, 1);
    R := TrimLeft(R);
    if R = '' then Exit;
    if (R[1] = '"') or (R[1] = '''') then
    begin
      Q := R[1];
      Delete(R, 1, 1);
      j := Pos(Q, R);
      if j > 0 then
        Result := Copy(R, 1, j - 1)
      else
        Result := R;
    end
    else
    begin
      j := 1;
      while (j <= Length(R)) and (R[j] <> ' ') and (R[j] <> '>') and
        (R[j] <> #9) and (R[j] <> '/') do
        Inc(j);
      Result := Copy(R, 1, j - 1);
    end;
  end;

begin
  Cur := DefaultInkAttr;
  if AParaBreakFirst then EmitBreak;

  Body := AMarkup;
  P := 1;
  Len := Length(Body);
  while P <= Len do
  begin
    if Body[P] = '<' then
    begin
      Start := P;
      while (P <= Len) and (Body[P] <> '>') do Inc(P);
      if P <= Len then Inc(P);
      TagStr := Copy(Body, Start, P - Start);
      Up := UpperCase(TagStr);
      Nm := '';
      N := 2;
      if (N <= Length(Up)) and (Up[N] = '/') then
      begin
        Nm := '/';
        Inc(N);
      end;
      while (N <= Length(Up)) and (Up[N] in ['A'..'Z', '0'..'9']) do
      begin
        Nm := Nm + Up[N];
        Inc(N);
      end;

      if (Nm = 'BR') or (Nm = 'P') or (Nm = '/P') then
        EmitBreak
      else if Nm = 'B' then begin Push; Cur.Style := Cur.Style + [fsBold]; end
      else if Nm = 'I' then begin Push; Cur.Style := Cur.Style + [fsItalic]; end
      else if Nm = 'U' then begin Push; Cur.Style := Cur.Style + [fsUnderline]; end
      else if (Nm = 'S') or (Nm = 'STRIKE') then
        begin Push; Cur.Style := Cur.Style + [fsStrikeOut]; end
      else if Nm = 'SUP' then begin Push; Cur.Script := isSuperscript; end
      else if Nm = 'SUB' then begin Push; Cur.Script := isSubscript; end
      else if Nm = 'CENTER' then begin Push; Cur.Align := taCenter; end
      else if Nm = 'RIGHT' then begin Push; Cur.Align := taRightJustify; end
      else if Nm = 'A' then
      begin
        Push;
        Val := PropOf(TagStr, 'HREF');
        if Val <> '' then Cur.Link := Val;
      end
      else if Nm = 'FONT' then
      begin
        Push;
        Val := PropOf(TagStr, 'BGCOLOR');
        if Val <> '' then Cur.BackColor := HTMLStringToColor(Val, clNone);
        // "BGCOLOR" ends in "COLOR", so looking for the shorter name in the
        // raw tag finds the longer one and paints the text in its own
        // background. Mask it out first.
        Val := PropOf(StringReplace(TagStr, 'bgcolor', '#######',
          [rfReplaceAll, rfIgnoreCase]), 'COLOR');
        if Val <> '' then Cur.Color := HTMLStringToColor(Val, clDefault);
        Val := PropOf(TagStr, 'SIZE');
        if Val <> '' then Cur.Size := StrToIntDef(Val, 0);
        Val := PropOf(TagStr, 'FACE');
        if Val <> '' then Cur.Face := Val;
      end
      else if (Length(Nm) > 1) and (Nm[1] = '/') then
        Pop;
      Continue;
    end;

    Start := P;
    while (P <= Len) and (Body[P] <> '<') do Inc(P);
    Emit(HTMLUnescape(Copy(Body, Start, P - Start)));
  end;
end;

{ Writes the document back out as markup.

  Characters are gathered into runs that share an attribute, and each run's
  tags are matched against what is already open: the common prefix stays, the
  rest is closed innermost-first and the new tags opened. That way a paragraph
  of bold text with one red word in it comes out as <b>ab <font
  color="#FF0000">cd</font> ef</b>, not as a fresh <b> around every run.

  Ordering is fixed - a, font, b, i, u, s, sup/sub - so that two runs wanting
  the same tags always produce the same prefix and the comparison is
  meaningful. <a> is outermost because the renderer restores the whole font
  at </a>. }
procedure TInkRichEdit.SyncMarkupFromDoc;
const
  cMaxTags = 8;
var
  Line, Body: string;
  i, RunEnd, k, NOpen, NWant: Integer;
  OpenName, OpenTag: array[0..cMaxTags - 1] of string;
  WantName, WantTag: array[0..cMaxTags - 1] of string;
  ParaAlign: TAlignment;

  procedure CloseDownTo(ALevel: Integer);
  var
    j: Integer;
  begin
    for j := NOpen - 1 downto ALevel do
      Line := Line + '</' + OpenName[j] + '>';
    NOpen := ALevel;
  end;

  procedure AddWant(const AName, ATag: string);
  begin
    if NWant >= cMaxTags then Exit;
    WantName[NWant] := AName;
    WantTag[NWant] := ATag;
    Inc(NWant);
  end;

  procedure BuildWant(const A: TInkAttr);
  var
    F, C: string;
  begin
    NWant := 0;
    if A.Link <> '' then
      AddWant('a', '<a href="' + A.Link + '">');
    F := '';
    C := InkColorToHTML(A.Color);
    if C <> '' then F := F + ' color="' + C + '"';
    C := InkColorToHTML(A.BackColor);
    if C <> '' then F := F + ' bgcolor="' + C + '"';
    if A.Size > 0 then F := F + ' size="' + IntToStr(A.Size) + '"';
    if A.Face <> '' then F := F + ' face="' + A.Face + '"';
    if F <> '' then AddWant('font', '<font' + F + '>');
    if fsBold in A.Style then AddWant('b', '<b>');
    if fsItalic in A.Style then AddWant('i', '<i>');
    if fsUnderline in A.Style then AddWant('u', '<u>');
    if fsStrikeOut in A.Style then AddWant('s', '<s>');
    if A.Script = isSuperscript then AddWant('sup', '<sup>');
    if A.Script = isSubscript then AddWant('sub', '<sub>');
  end;

  { Nothing about an attribute says which of its tags ought to be outermost, so
    the canonical order above is arbitrary - and an arbitrary order re-emits
    tags that were perfectly good. Reordering each run's tags to lead with the
    ones already open (for as long as they match, since the stack can only be
    reused as a prefix) keeps <b>ab<font color=..>cd</font>ef</b> from turning
    into three separate <b> runs. }
  procedure OrderWantForReuse;
  var
    j, m, Cnt, Found: Integer;
    Used: array[0..cMaxTags - 1] of Boolean;
    TmpName, TmpTag: array[0..cMaxTags - 1] of string;
  begin
    for j := 0 to cMaxTags - 1 do
      Used[j] := False;
    Cnt := 0;
    for j := 0 to NOpen - 1 do
    begin
      Found := -1;
      for m := 0 to NWant - 1 do
        if (not Used[m]) and (WantTag[m] = OpenTag[j]) then
        begin
          Found := m;
          Break;
        end;
      if Found < 0 then Break;
      TmpName[Cnt] := WantName[Found];
      TmpTag[Cnt] := WantTag[Found];
      Used[Found] := True;
      Inc(Cnt);
    end;
    for m := 0 to NWant - 1 do
      if not Used[m] then
      begin
        TmpName[Cnt] := WantName[m];
        TmpTag[Cnt] := WantTag[m];
        Inc(Cnt);
      end;
    for j := 0 to Cnt - 1 do
    begin
      WantName[j] := TmpName[j];
      WantTag[j] := TmpTag[j];
    end;
    NWant := Cnt;
  end;

  procedure EndParagraph;
  begin
    CloseDownTo(0);
    case ParaAlign of
      taCenter: Line := '<center>' + Line + '</center>';
      taRightJustify: Line := '<right>' + Line + '</right>';
      taLeftJustify: ;   // the default needs no wrapper
    end;
    FMarkup.Add(Line);
    Line := '';
  end;

begin
  FSettingMarkup := True;
  try
    FMarkup.Clear;
    Line := '';
    NOpen := 0;
    for k := 0 to cMaxTags - 1 do
    begin
      OpenName[k] := '';
      OpenTag[k] := '';
      WantName[k] := '';
      WantTag[k] := '';
    end;
    if CharCount > 0 then ParaAlign := FAttrs[0].Align else ParaAlign := taLeftJustify;

    i := 0;
    while i <= CharCount do
    begin
      if (i = CharCount) or (FChars[i] = #10) then
      begin
        EndParagraph;
        Inc(i);
        if i < CharCount then
          ParaAlign := FAttrs[i].Align
        else
          ParaAlign := taLeftJustify;
        Continue;
      end;

      RunEnd := i;
      while (RunEnd + 1 < CharCount) and (FChars[RunEnd + 1] <> #10) and
        SameInkAttr(FAttrs[RunEnd + 1], FAttrs[i]) do
        Inc(RunEnd);

      BuildWant(FAttrs[i]);
      OrderWantForReuse;
      k := 0;
      while (k < NOpen) and (k < NWant) and (OpenTag[k] = WantTag[k]) do
        Inc(k);
      CloseDownTo(k);
      while k < NWant do
      begin
        Line := Line + WantTag[k];
        OpenName[NOpen] := WantName[k];
        OpenTag[NOpen] := WantTag[k];
        Inc(NOpen);
        Inc(k);
      end;

      Body := '';
      for k := i to RunEnd do
        Body := Body + FChars[k];
      Line := Line + HTMLEscape(Body);
      i := RunEnd + 1;
    end;
    FMarkupDirty := False;
  finally
    FSettingMarkup := False;
  end;
end;

function TInkRichEdit.AsHTML(const ASep: string): string;
var
  i: Integer;
  M: TStrings;
begin
  M := GetMarkup;
  Result := '';
  for i := 0 to M.Count - 1 do
  begin
    if i > 0 then Result := Result + ASep;
    Result := Result + M[i];
  end;
end;

function TInkRichEdit.PlainText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to CharCount - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

end.
