{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkEdit: a single-line edit box drawn entirely with TCanvas, so every
  character can carry its own color and font style. Styling is supplied by
  the OnGetCharAttrs event — the control hands you each character and you
  hand back a color and style. Classic uses: password strength coloring,
  highlighting digits/symbols, flagging duplicate characters.

  The text itself stays plain — what you Get/Set through Text is exactly
  what the user typed, no markup involved. Editing behaves like a normal
  TEdit: caret, selection with mouse or shift+arrows, clipboard shortcuts,
  Home/End, MaxLength, ReadOnly, alignment.

  Because it never touches a native text widget it renders identically on
  every LCL widgetset (win32, gtk2, gtk3, qt, cocoa).

  SPDX-License-Identifier: 0BSD; see LICENSE.
}
unit InkEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf, Clipbrd,
  LazUTF8, ExtCtrls, Types, Menus;

resourcestring
  SInkEditUndo = 'Undo';
  SInkEditRedo = 'Redo';
  SInkEditCut = 'Cut';
  SInkEditCopy = 'Copy';
  SInkEditPaste = 'Paste';
  SInkEditDelete = 'Delete';
  SInkEditSelectAll = 'Select all';

type
  TInkGetCharAttrsEvent = procedure(Sender: TObject; AIndex: integer; const AChar: string; var AColor: TColor; var AStyle: TFontStyles) of object;

  { TInkEdit }

  TInkEdit = class(TCustomControl)
  private
    FChars: array of string;   // one UTF-8 codepoint per entry
    FCaret: integer;           // 0..Length(FChars), position between chars
    FAnchor: integer;          // selection anchor; = FCaret when no selection
    FScrollX: integer;         // horizontal scroll offset in pixels
    FMaxLength: integer;
    FReadOnly: boolean;
    FAlignment: TAlignment;
    FCaretTimer: TTimer;
    FCaretOn: boolean;
    FOnChange: TNotifyEvent;
    FOnGetCharAttrs: TInkGetCharAttrsEvent;
    FTextHint: string;
    FTextHintColor: TColor;
    FPasswordChar: char;
    FEditMenu: boolean;
    FMenu: TPopupMenu;
    FUndo, FRedo: TFPList;
    FUndoKind: integer;        // 1 typing, 2 deleting, 0 anything else
    FUndoTick: QWord;
    FLastTyped: string;
    FClicks, FLastClickX, FLastClickY: integer;
    FLastClickTime: QWord;
    FSelectUnit: integer;      // what a drag selects by: 0 chars, 1 words, 2 all
    FUnitFrom, FUnitTo: integer;
    procedure SetTextHint(const AValue: string);
    procedure SetTextHintColor(AValue: TColor);
    procedure SetPasswordChar(AValue: char);
    { what character i is drawn and measured as - the mask while hidden }
    function DisplayChar(AIndex: integer): string;
    procedure PushUndo(AKind: integer);
    procedure ClearUndoList(AList: TFPList);
    procedure MenuClick(Sender: TObject);
    function GetTextValue: string;
    procedure SetTextValue(const AValue: string);
    function GetSelStart: integer;
    procedure SetSelStart(AValue: integer);
    function GetSelLength: integer;
    procedure SetSelLength(AValue: integer);
    function GetSelText: string;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetReadOnly(AValue: boolean);
    function CharCount: integer;
    procedure SplitText(const AValue: string);
    procedure CaretTimerTick(Sender: TObject);
    procedure RestartCaretBlink;
    { Layout: x pixel position before each char, in unscrolled text space.
      Positions[i] is the left edge of char i+1; Positions[CharCount] is the
      right edge of the text. StartX is where the text begins for the current
      alignment, before FScrollX is applied. }
    procedure ComputeLayout(out StartX: integer; out Positions: TIntegerDynArray);
    function CaretToX(ACaret: integer): integer;
    function XToCaret(X: integer): integer;
    procedure EnsureCaretVisible;
    procedure DeleteRange(AFrom, ATo: integer);  // chars [AFrom+1..ATo], 0-based gap positions
    procedure InsertText(const AValue: string);
    procedure DeleteSelection;
    procedure Changed;
  protected
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: boolean); override;
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
    function CanUndo: boolean;
    function CanRedo: boolean;
    procedure ClearUndo;
    property SelText: string read GetSelText;
  published
    { the box's text; the hint is never part of it }
    property Text: string read GetTextValue write SetTextValue;
    { where the selection starts, in characters from 0; the caret when
      nothing is selected }
    property SelStart: integer read GetSelStart write SetSelStart;
    { how many characters are selected; 0 is a bare caret }
    property SelLength: integer read GetSelLength write SetSelLength;
    { at most this many characters; 0 is no cap }
    property MaxLength: integer read FMaxLength write FMaxLength default 0;
    { the text can be selected and copied but not changed }
    property ReadOnly: boolean read FReadOnly write SetReadOnly default False;
    { the text sits at the left, in the middle or at the right of the box }
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { the gray words an empty box shows - what goes in the field, said
      without a second label.  Never part of Text, never copied; drawn in
      TextHintColor, or with clDefault the font color blended halfway into
      the background, so it suits a light and a dark box unset. }
    property TextHint: string read FTextHint write SetTextHint;
    { the color of TextHint; clDefault blends the font color halfway into
      the background }
    property TextHintColor: TColor read FTextHintColor write SetTextHintColor default clDefault;
    { a typed secret: every character drawn as this one (a bullet when it
      is '*', the way most toolkits draw it now).  While hidden, Copy and
      Cut do nothing and the text never reaches the clipboard.  Text is
      the real text, and undo still works. }
    property PasswordChar: char read FPasswordChar write SetPasswordChar default #0;
    { the box's own right-click menu - Undo, Redo, Cut, Copy, Paste, Delete,
      Select All, each enabled only when it can do something.  A PopupMenu
      of the host's own still wins. }
    property EditMenu: boolean read FEditMenu write FEditMenu default True;
    { fires after the text changed }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { every character's color and style, asked as it is drawn and measured -
      AIndex counts from 1 }
    property OnGetCharAttrs: TInkGetCharAttrsEvent read FOnGetCharAttrs write FOnGetCharAttrs;

    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle default bsSingle;
    property Color;
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

{ The word a double click at caret AIndex takes, as caret positions AFrom..ATo.
  AChars holds one codepoint each; letters, digits, _ and anything not ASCII
  make words, any other character is taken on its own. }
procedure InkWordAt(const AChars: array of string; ACount, AIndex: integer; out AFrom, ATo: integer);

implementation

uses
  InkTouch;

const
  cTextMargin = 4;
  cUndoDepth = 100;
  cUndoCoalesceMs = 1000;

type
  { a whole-text snapshot: a one-line edit is small, and a snapshot that
    cannot be subtly wrong beats a delta log that can }
  TInkEditSnap = class
    Chars: array of string;
    Caret, Anchor: integer;
  end;

function IsWordChar(const C: string): boolean;
begin
  Result := (Length(C) > 1) or ((C <> '') and (C[1] in ['a'..'z', 'A'..'Z', '0'..'9', '_']));
end;

procedure InkWordAt(const AChars: array of string; ACount, AIndex: integer; out AFrom, ATo: integer);
begin
  AFrom := EnsureRange(AIndex, 0, ACount);
  ATo := AFrom;
  if ACount = 0 then Exit;
  if AFrom = ACount then Dec(AFrom);
  { a click on the space or line end just after a word takes the word }
  if not IsWordChar(AChars[AFrom]) and (AFrom > 0) and IsWordChar(AChars[AFrom - 1]) and ((AChars[AFrom] = ' ') or (AChars[AFrom] = #9) or
    (AChars[AFrom] = #10) or (AIndex = ACount)) then Dec(AFrom);
  ATo := AFrom;
  if AChars[AFrom] = #10 then Exit;
  Inc(ATo);
  if not IsWordChar(AChars[AFrom]) then Exit;
  while (AFrom > 0) and IsWordChar(AChars[AFrom - 1]) do Dec(AFrom);
  while (ATo < ACount) and IsWordChar(AChars[ATo]) do Inc(ATo);
end;

{ TInkEdit }

procedure TInkEdit.CreateWnd;
begin
  inherited CreateWnd;
  { a finger places the caret and selects, as the mouse does }
  InkHookTouchAsMouse(Self);
end;

constructor TInkEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse, csOpaque, csRequiresKeyboardInput] - [csSetCaption];
  BorderStyle := bsSingle;
  TabStop := True;
  Cursor := crIBeam;
  Color := clWindow;
  Font.Color := clWindowText;
  FAlignment := taLeftJustify;
  FTextHintColor := clDefault;
  FEditMenu := True;
  FUndo := TFPList.Create;
  FRedo := TFPList.Create;
  { owned, so it outlives the DoExit a focused edit gets while it is freed }
  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.Enabled := False;
  FCaretTimer.OnTimer := @CaretTimerTick;
  with GetControlClassDefaultSize do
    SetInitialBounds(0, 0, cx, cy);
end;

destructor TInkEdit.Destroy;
begin
  ClearUndoList(FUndo);
  ClearUndoList(FRedo);
  FreeAndNil(FUndo);
  FreeAndNil(FRedo);
  FreeAndNil(FMenu);
  inherited Destroy;
end;

{ ------------------------------------------------------------- undo & redo }

procedure TInkEdit.ClearUndoList(AList: TFPList);
var
  i: integer;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    TObject(AList[i]).Free;
  AList.Clear;
end;

{ One step is one typed run: a run ends at a pause, a caret move, a change
  from typing to deleting, a paste or a cut, and at a word boundary - so
  undoing "two words" gives back a word, not a letter and not the day. }
procedure TInkEdit.PushUndo(AKind: integer);
var
  Snap: TInkEditSnap;
  i: integer;
begin
  ClearUndoList(FRedo);
  if (AKind > 0) and (AKind = FUndoKind) and (GetTickCount64 - FUndoTick < cUndoCoalesceMs) and (FUndo.Count > 0) then
  begin
    FUndoTick := GetTickCount64;
    Exit;                        // still the same run: one snapshot covers it
  end;
  Snap := TInkEditSnap.Create;
  SetLength(Snap.Chars, Length(FChars));
  for i := 0 to High(FChars) do
    Snap.Chars[i] := FChars[i];
  Snap.Caret := FCaret;
  Snap.Anchor := FAnchor;
  FUndo.Add(Snap);
  while FUndo.Count > cUndoDepth do
  begin
    TObject(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
  FUndoKind := AKind;
  FUndoTick := GetTickCount64;
end;

procedure TInkEdit.Undo;
var
  Snap, Back: TInkEditSnap;
  i: integer;
begin
  if FUndo.Count = 0 then Exit;
  Back := TInkEditSnap.Create;
  SetLength(Back.Chars, Length(FChars));
  for i := 0 to High(FChars) do
    Back.Chars[i] := FChars[i];
  Back.Caret := FCaret;
  Back.Anchor := FAnchor;
  FRedo.Add(Back);
  Snap := TInkEditSnap(FUndo[FUndo.Count - 1]);
  FUndo.Delete(FUndo.Count - 1);
  SetLength(FChars, Length(Snap.Chars));
  for i := 0 to High(Snap.Chars) do
    FChars[i] := Snap.Chars[i];
  FCaret := Snap.Caret;
  FAnchor := Snap.Anchor;
  Snap.Free;
  FUndoKind := 0;
  Changed;
end;

procedure TInkEdit.Redo;
var
  Snap, Back: TInkEditSnap;
  i: integer;
begin
  if FRedo.Count = 0 then Exit;
  Back := TInkEditSnap.Create;
  SetLength(Back.Chars, Length(FChars));
  for i := 0 to High(FChars) do
    Back.Chars[i] := FChars[i];
  Back.Caret := FCaret;
  Back.Anchor := FAnchor;
  FUndo.Add(Back);
  Snap := TInkEditSnap(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  SetLength(FChars, Length(Snap.Chars));
  for i := 0 to High(Snap.Chars) do
    FChars[i] := Snap.Chars[i];
  FCaret := Snap.Caret;
  FAnchor := Snap.Anchor;
  Snap.Free;
  FUndoKind := 0;
  Changed;
end;

function TInkEdit.CanUndo: boolean;
begin
  Result := (FUndo <> nil) and (FUndo.Count > 0);
end;

function TInkEdit.CanRedo: boolean;
begin
  Result := (FRedo <> nil) and (FRedo.Count > 0);
end;

procedure TInkEdit.ClearUndo;
begin
  ClearUndoList(FUndo);
  ClearUndoList(FRedo);
  FUndoKind := 0;
end;

procedure TInkEdit.SetPasswordChar(AValue: char);
begin
  if FPasswordChar = AValue then Exit;
  FPasswordChar := AValue;
  Invalidate;
end;

function TInkEdit.DisplayChar(AIndex: integer): string;
begin
  if FPasswordChar = #0 then
    Result := FChars[AIndex]
  else if FPasswordChar = '*' then
    Result := #$E2#$80#$A2
  else
    Result := FPasswordChar;
end;

procedure TInkEdit.SetTextHint(const AValue: string);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  Invalidate;
end;

procedure TInkEdit.SetTextHintColor(AValue: TColor);
begin
  if FTextHintColor = AValue then Exit;
  FTextHintColor := AValue;
  Invalidate;
end;

class function TInkEdit.GetControlClassDefaultSize: TSize;
begin
  Result.cx := 160;
  Result.cy := 30;
end;

function TInkEdit.CharCount: integer;
begin
  Result := Length(FChars);
end;

procedure TInkEdit.SplitText(const AValue: string);
var
  P: PChar;
  CharLen, N: integer;
begin
  SetLength(FChars, UTF8Length(AValue));
  N := 0;
  P := PChar(AValue);
  while P^ <> #0 do
  begin
    CharLen := UTF8CodepointSize(P);
    SetString(FChars[N], P, CharLen);
    Inc(N);
    Inc(P, CharLen);
  end;
end;

function TInkEdit.GetTextValue: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(FChars) do
    Result := Result + FChars[i];
end;

procedure TInkEdit.SetTextValue(const AValue: string);
var
  Clean: string;
begin
  // single-line control: line breaks have no meaning here
  Clean := StringReplace(AValue, #13, '', [rfReplaceAll]);
  Clean := StringReplace(Clean, #10, '', [rfReplaceAll]);
  if (FMaxLength > 0) and (UTF8Length(Clean) > FMaxLength) then
    Clean := UTF8Copy(Clean, 1, FMaxLength);
  if Clean = GetTextValue then Exit;
  { a form filling its fields is not something to undo }
  ClearUndo;
  SplitText(Clean);
  FCaret := CharCount;
  FAnchor := FCaret;
  FScrollX := 0;
  Changed;
end;

function TInkEdit.GetSelStart: integer;
begin
  if FCaret < FAnchor then Result := FCaret
  else
    Result := FAnchor;
end;

procedure TInkEdit.SetSelStart(AValue: integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > CharCount then AValue := CharCount;
  FCaret := AValue;
  FAnchor := AValue;
  RestartCaretBlink;
  EnsureCaretVisible;
  Invalidate;
end;

function TInkEdit.GetSelLength: integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

procedure TInkEdit.SetSelLength(AValue: integer);
begin
  if AValue < 0 then AValue := 0;
  FAnchor := GetSelStart;
  FCaret := FAnchor + AValue;
  if FCaret > CharCount then FCaret := CharCount;
  Invalidate;
end;

function TInkEdit.GetSelText: string;
var
  i: integer;
begin
  Result := '';
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    Result := Result + FChars[i];
end;

procedure TInkEdit.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TInkEdit.SetReadOnly(AValue: boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
end;

procedure TInkEdit.CaretTimerTick(Sender: TObject);
begin
  FCaretOn := not FCaretOn;
  Invalidate;
end;

procedure TInkEdit.RestartCaretBlink;
begin
  FCaretOn := True;
  if Focused then
  begin
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
  end;
end;

procedure TInkEdit.ComputeLayout(out StartX: integer; out Positions: TIntegerDynArray);
var
  i, X, TotalW: integer;
  AColor: TColor;
  AStyle: TFontStyles;
begin
  SetLength(Positions, CharCount + 1);
  Canvas.Font := Font;
  X := 0;
  for i := 0 to High(FChars) do
  begin
    Positions[i] := X;
    // style can change the width (bold), so styling has to be applied
    // while measuring too
    AColor := Font.Color;
    AStyle := Font.Style;
    if Assigned(FOnGetCharAttrs) and (FPasswordChar = #0) then
      FOnGetCharAttrs(Self, i + 1, FChars[i], AColor, AStyle);
    Canvas.Font.Style := AStyle;
    Inc(X, Canvas.TextWidth(DisplayChar(i)));
  end;
  Positions[CharCount] := X;
  TotalW := X;
  case FAlignment of
    taCenter:
      if TotalW < ClientWidth - 2 * cTextMargin then
        StartX := (ClientWidth - TotalW) div 2
      else
        StartX := cTextMargin;
    taRightJustify:
      if TotalW < ClientWidth - 2 * cTextMargin then
        StartX := ClientWidth - cTextMargin - TotalW
      else
        StartX := cTextMargin;
    else
      StartX := cTextMargin;
  end;
end;

function TInkEdit.CaretToX(ACaret: integer): integer;
var
  StartX: integer;
  Positions: TIntegerDynArray;
begin
  ComputeLayout(StartX, Positions);
  if ACaret < 0 then ACaret := 0;
  if ACaret > CharCount then ACaret := CharCount;
  Result := StartX + Positions[ACaret] - FScrollX;
end;

function TInkEdit.XToCaret(X: integer): integer;
var
  StartX, i, TextX: integer;
  Positions: TIntegerDynArray;
begin
  ComputeLayout(StartX, Positions);
  TextX := X - StartX + FScrollX;
  Result := CharCount;
  for i := 0 to CharCount - 1 do
    if TextX < (Positions[i] + Positions[i + 1]) div 2 then
    begin
      Result := i;
      Break;
    end;
end;

procedure TInkEdit.EnsureCaretVisible;
var
  CaretX: integer;
begin
  if not HandleAllocated then Exit;
  CaretX := CaretToX(FCaret);
  if CaretX < cTextMargin then
    Dec(FScrollX, cTextMargin - CaretX)
  else if CaretX > ClientWidth - cTextMargin then
    Inc(FScrollX, CaretX - (ClientWidth - cTextMargin));
  if FScrollX < 0 then FScrollX := 0;
end;

procedure TInkEdit.DeleteRange(AFrom, ATo: integer);
var
  i: integer;
begin
  if ATo <= AFrom then Exit;
  for i := ATo to High(FChars) do
    FChars[AFrom + (i - ATo)] := FChars[i];
  SetLength(FChars, Length(FChars) - (ATo - AFrom));
  FCaret := AFrom;
  FAnchor := AFrom;
  Changed;
end;

procedure TInkEdit.DeleteSelection;
begin
  DeleteRange(GetSelStart, GetSelStart + GetSelLength);
end;

procedure TInkEdit.InsertText(const AValue: string);
var
  Incoming: array of string;
  P: PChar;
  CharLen, N, i, Room: integer;
  Clean: string;
begin
  if FReadOnly then Exit;
  if GetSelLength > 0 then DeleteSelection;
  Clean := StringReplace(AValue, #13, '', [rfReplaceAll]);
  Clean := StringReplace(Clean, #10, '', [rfReplaceAll]);
  if Clean = '' then Exit;

  N := 0;
  SetLength(Incoming, UTF8Length(Clean));
  P := PChar(Clean);
  while P^ <> #0 do
  begin
    CharLen := UTF8CodepointSize(P);
    SetString(Incoming[N], P, CharLen);
    Inc(N);
    Inc(P, CharLen);
  end;

  if FMaxLength > 0 then
  begin
    Room := FMaxLength - CharCount;
    if Room <= 0 then Exit;
    if N > Room then N := Room;
  end;

  SetLength(FChars, Length(FChars) + N);
  for i := High(FChars) downto FCaret + N do
    FChars[i] := FChars[i - N];
  for i := 0 to N - 1 do
    FChars[FCaret + i] := Incoming[i];
  Inc(FCaret, N);
  FAnchor := FCaret;
  Changed;
end;

procedure TInkEdit.Changed;
begin
  EnsureCaretVisible;
  RestartCaretBlink;
  Invalidate;
  { reading a stored Text while the form loads is not a change - the stock
    edits are silent here too, and a handler that runs this early touches
    controls that do not exist yet }
  if (csLoading in ComponentState) then Exit;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkEdit.Paint;
var
  StartX, i, X, W, TextY, TH, SelA, SelB, CaretX: integer;
  Positions: TIntegerDynArray;
  AColor: TColor;
  AStyle: TFontStyles;
  AHint: string;
begin
  Canvas.Brush.Color := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  ComputeLayout(StartX, Positions);
  Canvas.Font := Font;
  TH := Canvas.TextHeight('Ag');
  TextY := (ClientHeight - TH) div 2;

  SelA := GetSelStart;
  SelB := SelA + GetSelLength;

  // the hint in the empty box: what goes here, said in dimmed words that
  // are never part of Text.  It stays under the caret until typing starts.
  if (CharCount = 0) and (FTextHint <> '') then
  begin
    if FTextHintColor = clDefault then
      Canvas.Font.Color := RGBToColor((Red(ColorToRGB(Font.Color)) + Red(ColorToRGB(Color))) div 2, (Green(ColorToRGB(Font.Color)) +
        Green(ColorToRGB(Color))) div 2, (Blue(ColorToRGB(Font.Color)) + Blue(ColorToRGB(Color))) div 2)
    else
      Canvas.Font.Color := FTextHintColor;
    Canvas.Brush.Style := bsClear;
    W := ClientWidth - 2 * cTextMargin;
    AHint := FTextHint;
    if Canvas.TextWidth(AHint) > W then
    begin
      while (AHint <> '') and (Canvas.TextWidth(AHint + #$E2#$80#$A6) > W) do
        AHint := UTF8Copy(AHint, 1, UTF8Length(AHint) - 1);
      AHint := AHint + #$E2#$80#$A6;
    end;
    case FAlignment of
      taCenter: X := cTextMargin + Max(0, (W - Canvas.TextWidth(AHint)) div 2);
      taRightJustify: X := cTextMargin + Max(0, W - Canvas.TextWidth(AHint));
      else
        X := cTextMargin;
    end;
    Canvas.TextOut(X, TextY, AHint);
    Canvas.Font.Color := Font.Color;
  end;

  // selection band behind the glyphs
  if (SelB > SelA) and Focused then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.FillRect(StartX + Positions[SelA] - FScrollX, TextY,
      StartX + Positions[SelB] - FScrollX, TextY + TH);
  end;

  Canvas.Brush.Style := bsClear;
  for i := 0 to High(FChars) do
  begin
    X := StartX + Positions[i] - FScrollX;
    W := Positions[i + 1] - Positions[i];
    if (X + W < 0) or (X > ClientWidth) then Continue;
    AColor := Font.Color;
    AStyle := Font.Style;
    if Assigned(FOnGetCharAttrs) and (FPasswordChar = #0) then
      FOnGetCharAttrs(Self, i + 1, FChars[i], AColor, AStyle);
    if (i >= SelA) and (i < SelB) and Focused then
      AColor := clHighlightText;
    Canvas.Font.Color := AColor;
    Canvas.Font.Style := AStyle;
    Canvas.TextOut(X, TextY, DisplayChar(i));
  end;

  if Focused and FCaretOn then
  begin
    CaretX := StartX + Positions[FCaret] - FScrollX;
    Canvas.Pen.Color := Font.Color;
    Canvas.Line(CaretX, TextY, CaretX, TextY + TH);
    Canvas.Line(CaretX + 1, TextY, CaretX + 1, TextY + TH);
  end;
end;

procedure TInkEdit.KeyDown(var Key: word; Shift: TShiftState);

  procedure MoveCaret(NewPos: integer);
  begin
    if NewPos < 0 then NewPos := 0;
    if NewPos > CharCount then NewPos := CharCount;
    FUndoKind := 0;            // a caret move ends a typing run
    FCaret := NewPos;
    if not (ssShift in Shift) then FAnchor := FCaret;
    EnsureCaretVisible;
    RestartCaretBlink;
    Invalidate;
  end;

begin
  inherited KeyDown(Key, Shift);
  if Key = 0 then Exit;
  case Key of
    VK_LEFT:
    begin
      if (GetSelLength > 0) and not (ssShift in Shift) then
        MoveCaret(GetSelStart)
      else
        MoveCaret(FCaret - 1);
      Key := 0;
    end;
    VK_RIGHT:
    begin
      if (GetSelLength > 0) and not (ssShift in Shift) then
        MoveCaret(GetSelStart + GetSelLength)
      else
        MoveCaret(FCaret + 1);
      Key := 0;
    end;
    VK_HOME: begin
      MoveCaret(0);
      Key := 0;
    end;
    VK_END: begin
      MoveCaret(CharCount);
      Key := 0;
    end;
    VK_BACK:
    begin
      if not FReadOnly then
      begin
        PushUndo(2);
        if GetSelLength > 0 then
          DeleteSelection
        else if FCaret > 0 then
          DeleteRange(FCaret - 1, FCaret);
      end;
      Key := 0;
    end;
    VK_DELETE:
    begin
      if not FReadOnly then
      begin
        PushUndo(2);
        if GetSelLength > 0 then
          DeleteSelection
        else if FCaret < CharCount then
          DeleteRange(FCaret, FCaret + 1);
      end;
      Key := 0;
    end;
    VK_A: if ssCtrl in Shift then
      begin
        SelectAll;
        Key := 0;
      end;
    VK_C: if ssCtrl in Shift then
      begin
        CopyToClipboard;
        Key := 0;
      end;
    VK_X: if ssCtrl in Shift then
      begin
        CutToClipboard;
        Key := 0;
      end;
    VK_V: if ssCtrl in Shift then
      begin
        PasteFromClipboard;
        Key := 0;
      end;
    VK_Z:
      if ssCtrl in Shift then
      begin
        if ssShift in Shift then Redo
        else
          Undo;
        Key := 0;
      end;
    VK_Y: if ssCtrl in Shift then
      begin
        Redo;
        Key := 0;
      end;
  end;
end;

procedure TInkEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < #32) then Exit;
  if not FReadOnly then
  begin
    { a space after a word starts a new undo run, so undo gives back words }
    if (UTF8Key = ' ') and (FLastTyped <> '') and (FLastTyped <> ' ') then
      FUndoKind := 0;
    PushUndo(1);
    FLastTyped := UTF8Key;
  end;
  InsertText(UTF8Key);
  UTF8Key := '';
end;

procedure TInkEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Now_: QWord;
  Near: boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if CanSetFocus then SetFocus;
    FUndoKind := 0;
    FCaret := XToCaret(X);
    { counted as TInkCustomPage does: GTK sends a double click as a press and
      the same press again, marked double, at the same moment }
    Now_ := GetTickCount64;
    Near := (Abs(X - FLastClickX) <= 4) and (Abs(Y - FLastClickY) <= 4);
    if not (Near and (Now_ - FLastClickTime < 25)) then
    begin
      if Near and (Now_ - FLastClickTime <= GetDoubleClickTime) and (FClicks < 3) then
        Inc(FClicks)
      else
        FClicks := 1;
    end;
    FLastClickTime := Now_;
    FLastClickX := X;
    FLastClickY := Y;
    if ssTriple in Shift then FClicks := 3
    else if (ssDouble in Shift) and (FClicks < 2) then FClicks := 2;
    FSelectUnit := 0;
    { a hidden text has no words to show; a double click takes it all }
    if (FClicks = 3) or ((FClicks = 2) and (FPasswordChar <> #0)) then
    begin
      FSelectUnit := 2;
      FAnchor := 0;
      FCaret := CharCount;
    end
    else if FClicks = 2 then
    begin
      FSelectUnit := 1;
      InkWordAt(FChars, CharCount, FCaret, FUnitFrom, FUnitTo);
      FAnchor := FUnitFrom;
      FCaret := FUnitTo;
    end
    else if not (ssShift in Shift) then
      FAnchor := FCaret;
    RestartCaretBlink;
    Invalidate;
  end;
end;

procedure TInkEdit.MouseMove(Shift: TShiftState; X, Y: integer);
var
  A, B: integer;
begin
  inherited MouseMove(Shift, X, Y);
  if (ssLeft in Shift) and (FSelectUnit < 2) then
  begin
    FCaret := XToCaret(X);
    if FSelectUnit = 1 then
    begin
      { after a double click a drag goes by whole words }
      InkWordAt(FChars, CharCount, FCaret, A, B);
      if A < FUnitFrom then
      begin
        FAnchor := FUnitTo;
        FCaret := A;
      end
      else
      begin
        FAnchor := FUnitFrom;
        FCaret := Max(B, FUnitTo);
      end;
    end;
    EnsureCaretVisible;
    Invalidate;
  end;
end;

procedure TInkEdit.DoEnter;
begin
  inherited DoEnter;
  FCaretOn := True;
  FCaretTimer.Enabled := True;
  Invalidate;
end;

procedure TInkEdit.DoExit;
begin
  inherited DoExit;
  FCaretTimer.Enabled := False;
  FCaretOn := False;
  Invalidate;
end;

procedure TInkEdit.Clear;
begin
  SetTextValue('');
end;

procedure TInkEdit.SelectAll;
begin
  FAnchor := 0;
  FCaret := CharCount;
  Invalidate;
end;

procedure TInkEdit.CopyToClipboard;
begin
  { a hidden text never reaches the clipboard }
  if FPasswordChar <> #0 then Exit;
  if GetSelLength > 0 then
    Clipboard.AsText := GetSelText
  else
    Clipboard.AsText := GetTextValue;
end;

procedure TInkEdit.CutToClipboard;
begin
  { a hidden text never reaches the clipboard }
  if FPasswordChar <> #0 then Exit;
  if FReadOnly then
  begin
    CopyToClipboard;
    Exit;
  end;
  if GetSelLength > 0 then
  begin
    PushUndo(0);
    Clipboard.AsText := GetSelText;
    DeleteSelection;
  end;
end;

procedure TInkEdit.PasteFromClipboard;
begin
  if not FReadOnly and Clipboard.HasFormat(CF_TEXT) then
  begin
    PushUndo(0);
    InsertText(Clipboard.AsText);
  end;
end;

{ ------------------------------------------------------------ context menu }

procedure TInkEdit.MenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    1: Undo;
    2: Redo;
    3: CutToClipboard;
    4: CopyToClipboard;
    5: PasteFromClipboard;
    6: if (not FReadOnly) and (GetSelLength > 0) then
      begin
        PushUndo(0);
        DeleteSelection;
      end;
    7: SelectAll;
  end;
end;

procedure TInkEdit.DoContextPopup(MousePos: TPoint; var Handled: boolean);
var
  P: TPoint;

  procedure AddItem(const ACaption: string; ATag: integer; AEnabled: boolean);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(FMenu);
    It.Caption := ACaption;
    It.Tag := ATag;
    It.Enabled := AEnabled;
    It.OnClick := @MenuClick;
    FMenu.Items.Add(It);
  end;

begin
  inherited DoContextPopup(MousePos, Handled);
  { a PopupMenu of the host's own was shown by the LCL before this runs }
  if Handled or (PopupMenu <> nil) or not FEditMenu then Exit;
  Handled := True;
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(Self);
  if not FReadOnly then
  begin
    AddItem(SInkEditUndo, 1, CanUndo);
    AddItem(SInkEditRedo, 2, CanRedo);
    AddItem('-', 0, True);
    AddItem(SInkEditCut, 3, (GetSelLength > 0) and (FPasswordChar = #0));
  end;
  AddItem(SInkEditCopy, 4, (GetSelLength > 0) and (FPasswordChar = #0));
  if not FReadOnly then
  begin
    AddItem(SInkEditPaste, 5, Clipboard.HasFormat(CF_TEXT));
    AddItem(SInkEditDelete, 6, GetSelLength > 0);
  end;
  AddItem('-', 0, True);
  AddItem(SInkEditSelectAll, 7, CharCount > 0);
  P := ClientToScreen(MousePos);
  FMenu.PopUp(P.X, P.Y);
end;

end.
