{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkMemo: a scrollable multi-line HTML text viewer. Each line of Lines is
  one paragraph of inline markup (<b> <i> <u> <s> <font ...> <sup> <sub>
  <br> <hr> <center> <right> <a href=> ...), rendered with plain TCanvas
  drawing, so it looks the same on every LCL widgetset. Lines can differ in
  height (font size tags, <br> inside a line).

  It is a display control — a log, a chat transcript, formatted help text —
  not a rich text editor. Text is changed through Lines/Append from code.
  <a href=...> links fire OnLinkClick.

  Implementation note: it rides on TCustomListBox with variable-height
  owner drawing, which supplies scrolling, invalidation, and keyboard
  navigation without a native text widget ever seeing the markup.

  License: component code MIT; the renderer unit InkHtml is derived
  from the JVCL project (MPL 1.1) — see that unit's header.
}
unit InkMemo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, LCLType, Types;

type
  TInkMemoLinkEvent = procedure(Sender: TObject; LineIndex: Integer;
    const LinkName: string) of object;

  { TInkMemo }

  TInkMemo = class(TCustomListBox)
  private
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FShowSelection: Boolean;
    FOnLinkClick: TInkMemoLinkEvent;
    FMouseOnLink: Boolean;
    FLinkName: string;
    FLinkLine: Integer;
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    procedure SetHTMLScale(AValue: Integer);
  protected
    procedure DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure MeasureItem(Index: Integer; var TheHeight: Integer); override;
    procedure Click; override;
    procedure Append(const ALine: string);
    { line ALine with all markup stripped }
    function GetPlainText(ALine: Integer): string;
    { the whole text with all markup stripped }
    function PlainText: string;
    procedure SaveAsPlain(const FileName: string);
    procedure SaveAsHTML(const FileName: string);
  published
    property Lines: TStrings read GetLines write SetLines;
    property HTMLScale: Integer read FHTMLScale write SetHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property ShowSelection: Boolean read FShowSelection write FShowSelection default False;
    property OnLinkClick: TInkMemoLinkEvent read FOnLinkClick write FOnLinkClick;

    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle;
    property Color;
    property Constraints;
    property Enabled;
    property Font;
    property Hint;
    property MultiSelect;
    property OnClick;
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnResize;
    property OnSelectionChange;
    property ParentColor;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ScrollWidth;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property Visible;
  end;

implementation

uses
  InkHtml;

{ TInkMemo }

constructor TInkMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FShowSelection := False;
  FLinkLine := -1;
  Style := lbOwnerDrawVariable;
end;

function TInkMemo.GetLines: TStrings;
begin
  Result := Items;
end;

procedure TInkMemo.SetLines(AValue: TStrings);
begin
  Items.Assign(AValue);
end;

procedure TInkMemo.SetHTMLScale(AValue: Integer);
begin
  if FHTMLScale = AValue then Exit;
  FHTMLScale := AValue;
  Invalidate;
end;

procedure TInkMemo.MeasureItem(Index: Integer; var TheHeight: Integer);
begin
  if (Index >= 0) and (Index < Items.Count) then
  begin
    Canvas.Font := Font;
    TheHeight := HTMLTextHeight(Canvas, Items[Index], FSuperSubScriptRatio,
      FHTMLScale) + 2;
  end
  else
    inherited MeasureItem(Index, TheHeight);
end;

procedure TInkMemo.DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState);
begin
  if FShowSelection and ([odSelected, odFocused] * State <> []) then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    Canvas.Brush.Color := Color;
    Canvas.Font.Color := Font.Color;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ARect);

  if (Index < 0) or (Index >= Items.Count) then Exit;

  Canvas.Brush.Style := bsClear;
  if FShowSelection then
    HTMLDrawText(Canvas, ARect, State, Items[Index], FSuperSubScriptRatio, FHTMLScale)
  else
    HTMLDrawText(Canvas, ARect, [], Items[Index], FSuperSubScriptRatio, FHTMLScale);
end;

procedure TInkMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx, W: Integer;
  R: TRect;
begin
  inherited MouseMove(Shift, X, Y);
  FMouseOnLink := False;
  FLinkName := '';
  FLinkLine := -1;
  Idx := GetIndexAtY(Y);
  if (Idx >= 0) and (Idx < Items.Count) then
  begin
    R := ItemRect(Idx);
    Canvas.Font := Font;
    HTMLDrawTextEx(Canvas, R, [], Items[Idx], W, htmlHyperLink, X, Y,
      FMouseOnLink, FLinkName, FSuperSubScriptRatio, FHTMLScale);
    if FMouseOnLink then FLinkLine := Idx;
  end;
  if FMouseOnLink then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TInkMemo.Click;
begin
  inherited Click;
  if FMouseOnLink and (FLinkName <> '') and Assigned(FOnLinkClick) then
    FOnLinkClick(Self, FLinkLine, FLinkName);
end;

procedure TInkMemo.Append(const ALine: string);
begin
  Items.Add(ALine);
  TopIndex := Items.Count - 1;
end;

function TInkMemo.GetPlainText(ALine: Integer): string;
begin
  if (ALine < 0) or (ALine >= Items.Count) then
    Result := ''
  else
    Result := HTMLPlainText(Items[ALine]);
end;

function TInkMemo.PlainText: string;
var
  SL: TStringList;
  i: Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to Items.Count - 1 do
      SL.Add(HTMLPlainText(Items[i]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TInkMemo.SaveAsPlain(const FileName: string);
var
  SL: TStringList;
  i: Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to Items.Count - 1 do
      SL.Add(HTMLPlainText(Items[i]));
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TInkMemo.SaveAsHTML(const FileName: string);
begin
  Items.SaveToFile(FileName);
end;

end.
