unit InkListBox;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls,
  LCLType, Types, Forms;

type
  TInkEditMode = (emNone, emOnSelect, emOnDblClick);

  TBeforeEditEvent = procedure(Sender: TObject; Index: Integer;
    var Cancel: Boolean) of object;

  TItemEditedEvent = procedure(Sender: TObject; Index: Integer;
    const OldText, NewText: string; var Accept: Boolean) of object;

  { TInkListBox }

  TInkListBox = class(TCustomListBox)
  private
    FHTMLEnabled: Boolean;
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FEditMode: TInkEditMode;
    FReadOnlyEdit: Boolean;
    FEditTimeout: Integer;
    FEditOverhang: Integer;
    FSelectionColor: TColor;
    FSelectionTextColor: TColor;
    FEdit: TEdit;
    FEditTimer: TTimer;
    FEditingIndex: Integer;
    FOnBeforeEdit: TBeforeEditEvent;
    FOnItemEdited: TItemEditedEvent;
    FOnUserSelectionChange: TSelectionChangeEvent;
    procedure InternalSelectionChange(Sender: TObject; User: Boolean);
    procedure EnsureEdit;
    procedure PositionEdit;
    procedure HideEdit;
    procedure BeginEdit(Index: Integer);
    procedure CommitEdit;
    procedure ResetEditTimeout;
    procedure EditTimerTick(Sender: TObject);
    procedure EditMouseEnter(Sender: TObject);
    procedure EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure EditKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
  protected
    procedure DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetPlainText(Index: Integer): string;
    procedure SaveAsPlain(const FileName: string);
    procedure SaveAsHTML(const FileName: string);
  published
    property HTMLEnabled: Boolean read FHTMLEnabled write FHTMLEnabled default True;
    property HTMLScale: Integer read FHTMLScale write FHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property EditMode: TInkEditMode read FEditMode write FEditMode default emOnSelect;
    property ReadOnlyEdit: Boolean read FReadOnlyEdit write FReadOnlyEdit default True;
    property EditTimeout: Integer read FEditTimeout write FEditTimeout default 5000;
    property EditOverhang: Integer read FEditOverhang write FEditOverhang default 2;
    property SelectionColor: TColor read FSelectionColor write FSelectionColor default clHighlight;
    property SelectionTextColor: TColor read FSelectionTextColor write FSelectionTextColor default clHighlightText;
    property OnBeforeEdit: TBeforeEditEvent read FOnBeforeEdit write FOnBeforeEdit;
    property OnItemEdited: TItemEditedEvent read FOnItemEdited write FOnItemEdited;

    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle;
    property ClickOnSelChange;
    property Color;
    property Columns;
    property Constraints;
    property DragCursor;
    property DragMode;
    property Enabled;
    property ExtendedSelect;
    property Font;
    property IntegralHeight;
    property Items;
    property ItemHeight;
    property MultiSelect;
    property OnChangeBounds;
    property OnClick;
    property OnContextPopup;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
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
    property OnMouseWheelDown;
    property OnMouseWheelUp;
    property OnResize;
    property OnSelectionChange: TSelectionChangeEvent
      read FOnUserSelectionChange write FOnUserSelectionChange;
    property OnShowHint;
    property OnStartDrag;
    property OnUTF8KeyPress;
    property ParentColor;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ScrollWidth;
    property ShowHint;
    property Sorted;
    property Style;
    property TabOrder;
    property TabStop;
    property TopIndex;
    property Visible;
  end;

implementation

uses
  InkHtml;

{ TInkListBox }

constructor TInkListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHTMLEnabled := True;
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FEditMode := emOnSelect;
  FReadOnlyEdit := True;
  FEditTimeout := 5000;
  FEditOverhang := 2;
  FSelectionColor := clHighlight;
  FSelectionTextColor := clHighlightText;
  FEditingIndex := -1;
  Style := lbOwnerDrawFixed;
  inherited OnSelectionChange := @InternalSelectionChange;
end;

destructor TInkListBox.Destroy;
begin
  FreeAndNil(FEditTimer);
  FreeAndNil(FEdit);
  inherited Destroy;
end;

procedure TInkListBox.EnsureEdit;
begin
  if FEdit <> nil then Exit;
  if Parent = nil then Exit;
  if csDesigning in ComponentState then Exit;

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Parent;
  FEdit.Visible := False;
  FEdit.ReadOnly := FReadOnlyEdit;
  FEdit.OnMouseEnter := @EditMouseEnter;
  FEdit.OnMouseMove := @EditMouseMove;
  FEdit.OnKeyPress := @EditKeyPress;
  FEdit.OnKeyUp := @EditKeyUp;
  FEdit.OnExit := @EditExit;

  FEditTimer := TTimer.Create(Self);
  FEditTimer.Enabled := False;
  FEditTimer.OnTimer := @EditTimerTick;
end;

procedure TInkListBox.PositionEdit;
var
  R: TRect;
begin
  if (FEdit = nil) or (FEditingIndex < 0) or (FEditingIndex >= Items.Count) then
    Exit;
  R := ItemRect(FEditingIndex);
  if (R.Top <= 0) or (R.Top >= (Height - FEdit.Height)) then
  begin
    FEdit.Top := -1000;
    Exit;
  end;
  FEdit.Left := R.Left + Self.Left - FEditOverhang;
  FEdit.Top := R.Top + Self.Top - FEditOverhang;
  FEdit.Width := (Self.ClientWidth - R.Left) + (FEditOverhang * 2);
  FEdit.Height := R.Height + (FEditOverhang * 2);
end;

procedure TInkListBox.HideEdit;
begin
  if FEditTimer <> nil then FEditTimer.Enabled := False;
  if FEdit <> nil then FEdit.Visible := False;
  FEditingIndex := -1;
end;

procedure TInkListBox.BeginEdit(Index: Integer);
var
  Cancel: Boolean;
begin
  if FEditMode = emNone then Exit;
  if (Index < 0) or (Index >= Items.Count) then Exit;

  Cancel := False;
  if Assigned(FOnBeforeEdit) then FOnBeforeEdit(Self, Index, Cancel);
  if Cancel then Exit;

  EnsureEdit;
  if FEdit = nil then Exit;

  FEditingIndex := Index;
  FEdit.ReadOnly := FReadOnlyEdit;
  FEdit.Text := HTMLPlainText(Items[Index]);
  PositionEdit;
  FEdit.Visible := True;
  FEdit.BringToFront;
  if FEdit.CanFocus then
    FEdit.SetFocus;
  FEdit.SelectAll;
  if FEditTimeout > 0 then
  begin
    FEditTimer.Interval := FEditTimeout;
    FEditTimer.Enabled := True;
  end;
end;

procedure TInkListBox.CommitEdit;
var
  Idx: Integer;
  OldText, NewText: string;
  Accept: Boolean;
begin
  if FReadOnlyEdit then Exit;
  if (FEdit = nil) or (FEditingIndex < 0) or (FEditingIndex >= Items.Count) then
    Exit;

  Idx := FEditingIndex;
  OldText := Items[Idx];
  NewText := FEdit.Text;
  if NewText = HTMLPlainText(OldText) then Exit;

  Accept := True;
  if Assigned(FOnItemEdited) then FOnItemEdited(Self, Idx, OldText, NewText, Accept);
  if Accept then Items[Idx] := NewText;
end;

procedure TInkListBox.ResetEditTimeout;
begin
  if (FEditTimer = nil) or (FEditTimeout <= 0) then Exit;
  FEditTimer.Enabled := False;
  FEditTimer.Enabled := True;
end;

procedure TInkListBox.EditTimerTick(Sender: TObject);
begin
  HideEdit;
end;

procedure TInkListBox.EditMouseEnter(Sender: TObject);
begin
  ResetEditTimeout;
end;

procedure TInkListBox.EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  ResetEditTimeout;
end;

procedure TInkListBox.EditKeyPress(Sender: TObject; var Key: Char);
begin
  ResetEditTimeout;
  if Key = #13 then
  begin
    CommitEdit;
    HideEdit;
    Key := #0;
  end
  else if Key = #27 then
  begin
    HideEdit;
    Key := #0;
  end;
end;

procedure TInkListBox.EditKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ResetEditTimeout;
end;

procedure TInkListBox.EditExit(Sender: TObject);
begin
  CommitEdit;
  HideEdit;
end;

procedure TInkListBox.DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState);
begin
  if (FEdit <> nil) and FEdit.Visible then
    PositionEdit;

  if [odSelected, odFocused] * State <> [] then
  begin
    Canvas.Brush.Color := FSelectionColor;
    Canvas.Font.Color := FSelectionTextColor;
  end
  else
  begin
    Canvas.Brush.Color := Color;
    Canvas.Font.Color := Font.Color;
  end;
  Canvas.FillRect(ARect);

  if (Index < 0) or (Index >= Items.Count) then Exit;

  if FHTMLEnabled then
    HTMLDrawText(Canvas, ARect, State, Items[Index],
      FSuperSubScriptRatio, FHTMLScale)
  else
    Canvas.TextRect(ARect, ARect.Left + 2, ARect.Top, Items[Index]);
end;

procedure TInkListBox.InternalSelectionChange(Sender: TObject; User: Boolean);
begin
  if Assigned(FOnUserSelectionChange) then
    FOnUserSelectionChange(Self, User);
  if User and (FEditMode = emOnSelect) then
    BeginEdit(ItemIndex);
end;

procedure TInkListBox.DblClick;
begin
  inherited DblClick;
  if FEditMode = emOnDblClick then
    BeginEdit(ItemIndex);
end;

function TInkListBox.GetPlainText(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Items.Count) then
    Result := ''
  else
    Result := HTMLPlainText(Items[Index]);
end;

procedure TInkListBox.SaveAsPlain(const FileName: string);
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

procedure TInkListBox.SaveAsHTML(const FileName: string);
begin
  Items.SaveToFile(FileName);
end;

end.
