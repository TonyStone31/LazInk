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

  License: MIT.
}
unit InkEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, LCLIntf, Clipbrd,
  LazUTF8, ExtCtrls, Types;

type
  TInkGetCharAttrsEvent = procedure(Sender: TObject; AIndex: Integer;
    const AChar: string; var AColor: TColor; var AStyle: TFontStyles) of object;

  { TInkEdit }

  TInkEdit = class(TCustomControl)
  private
    FChars: array of string;   // one UTF-8 codepoint per entry
    FCaret: Integer;           // 0..Length(FChars), position between chars
    FAnchor: Integer;          // selection anchor; = FCaret when no selection
    FScrollX: Integer;         // horizontal scroll offset in pixels
    FMaxLength: Integer;
    FReadOnly: Boolean;
    FAlignment: TAlignment;
    FCaretTimer: TTimer;
    FCaretOn: Boolean;
    FOnChange: TNotifyEvent;
    FOnGetCharAttrs: TInkGetCharAttrsEvent;
    function GetTextValue: string;
    procedure SetTextValue(const AValue: string);
    function GetSelStart: Integer;
    procedure SetSelStart(AValue: Integer);
    function GetSelLength: Integer;
    procedure SetSelLength(AValue: Integer);
    function GetSelText: string;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetReadOnly(AValue: Boolean);
    function CharCount: Integer;
    procedure SplitText(const AValue: string);
    procedure CaretTimerTick(Sender: TObject);
    procedure RestartCaretBlink;
    { Layout: x pixel position before each char, in unscrolled text space.
      Positions[i] is the left edge of char i+1; Positions[CharCount] is the
      right edge of the text. StartX is where the text begins for the current
      alignment, before FScrollX is applied. }
    procedure ComputeLayout(out StartX: Integer; out Positions: TIntegerDynArray);
    function CaretToX(ACaret: Integer): Integer;
    function XToCaret(X: Integer): Integer;
    procedure EnsureCaretVisible;
    procedure DeleteRange(AFrom, ATo: Integer);  // chars [AFrom+1..ATo], 0-based gap positions
    procedure InsertText(const AValue: string);
    procedure DeleteSelection;
    procedure Changed;
  protected
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
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
    property SelText: string read GetSelText;
  published
    property Text: string read GetTextValue write SetTextValue;
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property MaxLength: Integer read FMaxLength write FMaxLength default 0;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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

implementation

uses
  InkTouch;

const
  cTextMargin = 4;

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
  ControlStyle := ControlStyle + [csCaptureMouse, csOpaque, csRequiresKeyboardInput]
    - [csSetCaption];
  BorderStyle := bsSingle;
  TabStop := True;
  Cursor := crIBeam;
  Color := clWindow;
  Font.Color := clWindowText;
  FAlignment := taLeftJustify;
  FCaretTimer := TTimer.Create(nil);
  FCaretTimer.Interval := 530;
  FCaretTimer.Enabled := False;
  FCaretTimer.OnTimer := @CaretTimerTick;
  with GetControlClassDefaultSize do
    SetInitialBounds(0, 0, cx, cy);
end;

destructor TInkEdit.Destroy;
begin
  FreeAndNil(FCaretTimer);
  inherited Destroy;
end;

class function TInkEdit.GetControlClassDefaultSize: TSize;
begin
  Result.cx := 160;
  Result.cy := 30;
end;

function TInkEdit.CharCount: Integer;
begin
  Result := Length(FChars);
end;

procedure TInkEdit.SplitText(const AValue: string);
var
  P: PChar;
  CharLen, N: Integer;
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
  i: Integer;
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
  SplitText(Clean);
  FCaret := CharCount;
  FAnchor := FCaret;
  FScrollX := 0;
  Changed;
end;

function TInkEdit.GetSelStart: Integer;
begin
  if FCaret < FAnchor then Result := FCaret else Result := FAnchor;
end;

procedure TInkEdit.SetSelStart(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > CharCount then AValue := CharCount;
  FCaret := AValue;
  FAnchor := AValue;
  RestartCaretBlink;
  EnsureCaretVisible;
  Invalidate;
end;

function TInkEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

procedure TInkEdit.SetSelLength(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FAnchor := GetSelStart;
  FCaret := FAnchor + AValue;
  if FCaret > CharCount then FCaret := CharCount;
  Invalidate;
end;

function TInkEdit.GetSelText: string;
var
  i: Integer;
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

procedure TInkEdit.SetReadOnly(AValue: Boolean);
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

procedure TInkEdit.ComputeLayout(out StartX: Integer; out Positions: TIntegerDynArray);
var
  i, X, TotalW: Integer;
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
    if Assigned(FOnGetCharAttrs) then
      FOnGetCharAttrs(Self, i + 1, FChars[i], AColor, AStyle);
    Canvas.Font.Style := AStyle;
    Inc(X, Canvas.TextWidth(FChars[i]));
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

function TInkEdit.CaretToX(ACaret: Integer): Integer;
var
  StartX: Integer;
  Positions: TIntegerDynArray;
begin
  ComputeLayout(StartX, Positions);
  if ACaret < 0 then ACaret := 0;
  if ACaret > CharCount then ACaret := CharCount;
  Result := StartX + Positions[ACaret] - FScrollX;
end;

function TInkEdit.XToCaret(X: Integer): Integer;
var
  StartX, i, TextX: Integer;
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
  CaretX: Integer;
begin
  if not HandleAllocated then Exit;
  CaretX := CaretToX(FCaret);
  if CaretX < cTextMargin then
    Dec(FScrollX, cTextMargin - CaretX)
  else if CaretX > ClientWidth - cTextMargin then
    Inc(FScrollX, CaretX - (ClientWidth - cTextMargin));
  if FScrollX < 0 then FScrollX := 0;
end;

procedure TInkEdit.DeleteRange(AFrom, ATo: Integer);
var
  i: Integer;
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
  CharLen, N, i, Room: Integer;
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
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TInkEdit.Paint;
var
  StartX, i, X, W, TextY, TH, SelA, SelB, CaretX: Integer;
  Positions: TIntegerDynArray;
  AColor: TColor;
  AStyle: TFontStyles;
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
    if Assigned(FOnGetCharAttrs) then
      FOnGetCharAttrs(Self, i + 1, FChars[i], AColor, AStyle);
    if (i >= SelA) and (i < SelB) and Focused then
      AColor := clHighlightText;
    Canvas.Font.Color := AColor;
    Canvas.Font.Style := AStyle;
    Canvas.TextOut(X, TextY, FChars[i]);
  end;

  if Focused and FCaretOn then
  begin
    CaretX := StartX + Positions[FCaret] - FScrollX;
    Canvas.Pen.Color := Font.Color;
    Canvas.Line(CaretX, TextY, CaretX, TextY + TH);
    Canvas.Line(CaretX + 1, TextY, CaretX + 1, TextY + TH);
  end;
end;

procedure TInkEdit.KeyDown(var Key: Word; Shift: TShiftState);

  procedure MoveCaret(NewPos: Integer);
  begin
    if NewPos < 0 then NewPos := 0;
    if NewPos > CharCount then NewPos := CharCount;
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
    VK_HOME: begin MoveCaret(0); Key := 0; end;
    VK_END: begin MoveCaret(CharCount); Key := 0; end;
    VK_BACK:
      begin
        if not FReadOnly then
        begin
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
          if GetSelLength > 0 then
            DeleteSelection
          else if FCaret < CharCount then
            DeleteRange(FCaret, FCaret + 1);
        end;
        Key := 0;
      end;
    VK_A: if ssCtrl in Shift then begin SelectAll; Key := 0; end;
    VK_C: if ssCtrl in Shift then begin CopyToClipboard; Key := 0; end;
    VK_X: if ssCtrl in Shift then begin CutToClipboard; Key := 0; end;
    VK_V: if ssCtrl in Shift then begin PasteFromClipboard; Key := 0; end;
  end;
end;

procedure TInkEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < #32) then Exit;
  InsertText(UTF8Key);
  UTF8Key := '';
end;

procedure TInkEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if CanSetFocus then SetFocus;
    FCaret := XToCaret(X);
    if not (ssShift in Shift) then FAnchor := FCaret;
    RestartCaretBlink;
    Invalidate;
  end;
end;

procedure TInkEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if ssLeft in Shift then
  begin
    FCaret := XToCaret(X);
    EnsureCaretVisible;
    Invalidate;
  end;
end;

procedure TInkEdit.DblClick;
begin
  inherited DblClick;
  SelectAll;
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
  if GetSelLength > 0 then
    Clipboard.AsText := GetSelText
  else
    Clipboard.AsText := GetTextValue;
end;

procedure TInkEdit.CutToClipboard;
begin
  if FReadOnly then
  begin
    CopyToClipboard;
    Exit;
  end;
  if GetSelLength > 0 then
  begin
    Clipboard.AsText := GetSelText;
    DeleteSelection;
  end;
end;

procedure TInkEdit.PasteFromClipboard;
begin
  if not FReadOnly and Clipboard.HasFormat(CF_TEXT) then
    InsertText(Clipboard.AsText);
end;

end.
