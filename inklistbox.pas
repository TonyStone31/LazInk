unit InkListBox;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls, ImgList,
  LCLType, LCLIntf, Types, Forms, Menus, InkHtml, InkMarkdown, InkCopyMenu;

type
  { When the in-place editor opens by itself.  Whatever the mode, a program
    can open it with EditItem, and F2 opens it on the current item unless
    the mode is emNone.
      emNone             never by itself
      emOnSelect         when the user selects an item
      emOnDblClick       on a double click
      emOnTripleClick    on a triple click
      emOnClickSelected  on a click on the item already selected, after a
                         moment, as a file manager renames - a double click
                         in that moment does not edit }
  TInkEditMode = (emNone, emOnSelect, emOnDblClick, emOnTripleClick, emOnClickSelected);

  TBeforeEditEvent = procedure(Sender: TObject; Index: Integer;
    var Cancel: Boolean) of object;

  TItemEditedEvent = procedure(Sender: TObject; Index: Integer;
    const OldText, NewText: string; var Accept: Boolean) of object;

  TInkListLinkEvent = procedure(Sender: TObject; Index: Integer;
    const LinkName: string) of object;

  { TInkListBox }

  TInkListBox = class(TCustomListBox)
  private
    FTextFormat: TInkTextFormat;
    procedure SetTextFormat(AValue: TInkTextFormat);
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
    FEditRawHTML: Boolean;
    FAlternateColor: TColor;
    FLineSpacing: Integer;
    FBorders: TInkBorders;
    FImages: TCustomImageList;
    FLinkStyle: TInkLinkStyle;
    FLinkHoverStyle: TInkLinkStyle;
    FAutoOpenLink: Boolean;
    FHoverItem: Integer;     // -1 when the mouse is not over a link
    FHoverIndex: Integer;    // ordinal of that link within its item
    FHoverLink: string;
    FHoverLinkText: string;
    FOnBeforeEdit: TBeforeEditEvent;
    FOnItemEdited: TItemEditedEvent;
    FOnLinkClick: TInkListLinkEvent;
    FOnLinkEnter: TInkListLinkEvent;
    FOnLinkLeave: TInkListLinkEvent;
    FOnLinkRightClick: TInkListLinkEvent;
    FOnUserSelectionChange: TSelectionChangeEvent;
  private
    { the copy menu, and Ctrl+A / Ctrl+C }
    FCopyMenu: Boolean;
    FCopyMenuHost: TInkCopyMenu;
    FOnCopyMenu: TInkCopyMenuEvent;
    { Ctrl+A was the last thing done: Ctrl+C copies everything }
    FAllChosen: Boolean;
    { clicks counted here: GTK3's backend reports a triple click's third
      press as a plain one }
    FClicks, FLastClickX, FLastClickY, FPressItem, FPendingEdit: Integer;
    FLastClickTime: QWord;
    FPressWasSelected: Boolean;
    { the left button is down on the list: the selection follows the
      pointer, and emOnSelect waits for the release }
    FButtonDown, FEditOnRelease: Boolean;
    FClickEditTimer: TTimer;
    procedure ClickEditTick(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure SetAlternateColor(AValue: TColor);
    procedure SetLineSpacing(AValue: Integer);
    procedure SetBorders(AValue: TInkBorders);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetLinkStyle(AValue: TInkLinkStyle);
    procedure SetLinkHoverStyle(AValue: TInkLinkStyle);
    procedure SubPropChanged(Sender: TObject);
    procedure UpdateHover(AItem: Integer; const AHit: THTMLHitInfo);
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
    { Everything the renderer needs beyond the text itself. }
    function Options(AHoverIndex: Integer = 0): THTMLOptions;
    procedure DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState); override;
    procedure DblClick; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Resize; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Click; override;
    procedure MeasureItem(Index: Integer; var TheHeight: Integer); override;
    { Opens the in-place editor on Index from code - whatever EditMode is,
      so a program can edit on its own terms. }
    procedure EditItem(Index: Integer);
    { whether the in-place editor is open, and closing it unchanged }
    function Editing: Boolean;
    procedure CancelEdit;
    function GetPlainText(Index: Integer): string;
    { The href under the mouse, '' when none }
    property HoverLink: string read FHoverLink;
    property HoverLinkText: string read FHoverLinkText;
    procedure SaveAsPlain(const FileName: string);
    procedure SaveAsHTML(const FileName: string);
    { every item with its markup stripped, a line each }
    function PlainText: string;
    { the selected items as plain text - every one after Ctrl+A }
    function SelectedText: string;
    procedure CopyToClipboard;
    { fills the copy menu for client X, Y without opening it }
    function BuildCopyMenu(X, Y: Integer): TPopupMenu;
  published
    property TextFormat: TInkTextFormat read FTextFormat write SetTextFormat default itfHTML;
    { the right-click menu: Copy, Copy this item, Copy link address,
      Copy all, Select all.  Not shown when off or when PopupMenu is set. }
    property CopyMenu: Boolean read FCopyMenu write FCopyMenu default True;
    { lets a program add its own items to that menu as it opens }
    property OnCopyMenu: TInkCopyMenuEvent read FOnCopyMenu write FOnCopyMenu;

    property HTMLEnabled: Boolean read FHTMLEnabled write FHTMLEnabled default True;
    property HTMLScale: Integer read FHTMLScale write FHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property EditMode: TInkEditMode read FEditMode write FEditMode default emOnSelect;
    property ReadOnlyEdit: Boolean read FReadOnlyEdit write FReadOnlyEdit default True;
    { What the in-place editor shows. False (the default) hands the user the
      item with the markup stripped - good for copying a log line out. True
      hands over the markup itself, so the item can be re-styled in place and
      the result is visible the moment Enter is pressed. }
    property EditRawHTML: Boolean read FEditRawHTML write FEditRawHTML default False;
    { Background for odd-numbered rows. clNone (the default) turns it off. }
    property AlternateColor: TColor read FAlternateColor write SetAlternateColor default clNone;
    property LineSpacing: Integer read FLineSpacing write SetLineSpacing default 0;
    { Margins around the text. Each row is drawn on its own, so Top and Bottom
      are padding inside every row rather than once for the whole control;
      LineSpacing is what separates lines within a row. }
    property Borders: TInkBorders read FBorders write SetBorders;
    { Supplies <img src="n">, where n is an index into this list - a status
      icon per row, which is what a log listbox usually wants. }
    property Images: TCustomImageList read FImages write SetImages;
    property LinkStyle: TInkLinkStyle read FLinkStyle write SetLinkStyle;
    property LinkHoverStyle: TInkLinkStyle read FLinkHoverStyle write SetLinkHoverStyle;
    { Open a clicked link with the system browser. Only applies when no
      OnLinkClick handler is assigned - a handler always wins. }
    property AutoOpenLink: Boolean read FAutoOpenLink write FAutoOpenLink default False;
    property EditTimeout: Integer read FEditTimeout write FEditTimeout default 5000;
    property EditOverhang: Integer read FEditOverhang write FEditOverhang default 2;
    property SelectionColor: TColor read FSelectionColor write FSelectionColor default clHighlight;
    property SelectionTextColor: TColor read FSelectionTextColor write FSelectionTextColor default clHighlightText;
    property OnBeforeEdit: TBeforeEditEvent read FOnBeforeEdit write FOnBeforeEdit;
    property OnItemEdited: TItemEditedEvent read FOnItemEdited write FOnItemEdited;
    property OnLinkClick: TInkListLinkEvent read FOnLinkClick write FOnLinkClick;
    property OnLinkEnter: TInkListLinkEvent read FOnLinkEnter write FOnLinkEnter;
    property OnLinkLeave: TInkListLinkEvent read FOnLinkLeave write FOnLinkLeave;
    property OnLinkRightClick: TInkListLinkEvent read FOnLinkRightClick write FOnLinkRightClick;

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
  Math;

procedure TInkListBox.SetTextFormat(AValue: TInkTextFormat);
begin
  if FTextFormat = AValue then Exit;
  FTextFormat := AValue;
  SubPropChanged(nil);
end;


{ TInkListBox }

constructor TInkListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCopyMenu := True;
  FCopyMenuHost := TInkCopyMenu.Create(Self);
  FClickEditTimer := TTimer.Create(Self);
  FClickEditTimer.Enabled := False;
  FClickEditTimer.OnTimer := @ClickEditTick;
  FPendingEdit := -1;
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
  FEditRawHTML := False;
  FAlternateColor := clNone;
  FHoverItem := -1;
  FBorders := TInkBorders.Create;
  FBorders.OnChange := @SubPropChanged;
  FLinkStyle := TInkLinkStyle.Create(False);
  FLinkStyle.OnChange := @SubPropChanged;
  FLinkHoverStyle := TInkLinkStyle.Create(True);
  FLinkHoverStyle.OnChange := @SubPropChanged;
  Style := lbOwnerDrawVariable;
  inherited OnSelectionChange := @InternalSelectionChange;
end;

destructor TInkListBox.Destroy;
begin
  FClickEditTimer.Enabled := False;
  FreeAndNil(FEditTimer);
  FreeAndNil(FEdit);
  FreeAndNil(FBorders);
  FreeAndNil(FLinkStyle);
  FreeAndNil(FLinkHoverStyle);
  inherited Destroy;
end;

function TInkListBox.Options(AHoverIndex: Integer = 0): THTMLOptions;
begin
  Result := InkOptions(FSuperSubScriptRatio, FHTMLScale, FLineSpacing,
    FBorders, FImages, FLinkStyle, FLinkHoverStyle, AHoverIndex);
end;

procedure TInkListBox.SubPropChanged(Sender: TObject);
begin
  if HandleAllocated then begin Items.BeginUpdate; Items.EndUpdate end;
  Invalidate;
end;

procedure TInkListBox.SetLineSpacing(AValue: Integer);
begin
  if FLineSpacing = AValue then Exit;
  FLineSpacing := AValue;
  Invalidate;
end;

procedure TInkListBox.SetBorders(AValue: TInkBorders);
begin
  FBorders.Assign(AValue);
end;

procedure TInkListBox.SetLinkStyle(AValue: TInkLinkStyle);
begin
  FLinkStyle.Assign(AValue);
end;

procedure TInkListBox.SetLinkHoverStyle(AValue: TInkLinkStyle);
begin
  FLinkHoverStyle.Assign(AValue);
end;

procedure TInkListBox.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TInkListBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
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

{ The edit keeps the height its widgetset wants - forcing it to a row's
  height fought the theme's minimum and LCL stopped with a layout loop -
  and sits centered on the row.  It is only moved when something changed:
  this runs from DrawItem, and moving it repaints the list. }
procedure TInkListBox.PositionEdit;
var
  R: TRect;
  NewLeft, NewTop, NewWidth: Integer;
begin
  if (FEdit = nil) or (FEditingIndex < 0) or (FEditingIndex >= Items.Count) then
    Exit;
  R := ItemRect(FEditingIndex);
  if (R.Bottom <= 0) or (R.Top >= ClientHeight) then
    NewTop := -1000             // scrolled out of sight
  else
    NewTop := Self.Top + (R.Top + R.Bottom - FEdit.Height) div 2;
  NewLeft := R.Left + Self.Left - FEditOverhang;
  NewWidth := (Self.ClientWidth - R.Left) + (FEditOverhang * 2);
  if (FEdit.Left <> NewLeft) or (FEdit.Top <> NewTop) or (FEdit.Width <> NewWidth) then
    FEdit.SetBounds(NewLeft, NewTop, NewWidth, FEdit.Height);
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
  if (Index < 0) or (Index >= Items.Count) then Exit;

  Cancel := False;
  if Assigned(FOnBeforeEdit) then FOnBeforeEdit(Self, Index, Cancel);
  if Cancel then Exit;

  EnsureEdit;
  if FEdit = nil then Exit;

  FEditingIndex := Index;
  FEdit.ReadOnly := FReadOnlyEdit;
  if FEditRawHTML then
    FEdit.Text := Items[Index]
  else
    FEdit.Text := HTMLPlainText(InkToHTML(Items[Index], FTextFormat));
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
  if FEditRawHTML then
  begin
    if NewText = OldText then Exit;
  end
  else
  if NewText = HTMLPlainText(InkToHTML(OldText, FTextFormat)) then
    Exit;

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

procedure TInkListBox.MeasureItem(Index: Integer; var TheHeight: Integer);
var Sz: TSize;
begin
  TheHeight := ItemHeight;
  if (Index < 0) or (Index >= Items.Count) or not FHTMLEnabled then Exit;
  Canvas.Font := Font;
  Sz := HTMLTextExtentOpt(Canvas, Rect(0,0,ClientWidth,0), [],
    InkToHTML(Items[Index], FTextFormat), Options);
  if Sz.cy + 2 > TheHeight then TheHeight := Sz.cy + 2;
end;

procedure TInkListBox.DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  TextR: TRect;
  Opts: THTMLOptions;
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
    if (FAlternateColor <> clNone) and Odd(Index) then
      Canvas.Brush.Color := FAlternateColor
    else
      Canvas.Brush.Color := Color;
    Canvas.Font.Color := Font.Color;
  end;
  Canvas.FillRect(ARect);

  if (Index < 0) or (Index >= Items.Count) then Exit;

  // alignment tags place themselves inside the rectangle they are handed, and
  // the row rectangle can be wider than the column actually on screen
  TextR := ARect;
  if TextR.Right > ClientWidth then
    TextR.Right := ClientWidth;

  // the hovered link only lights up on the row it is actually on
  if Index = FHoverItem then
    Opts := Options(FHoverIndex)
  else
    Opts := Options;
  if FHTMLEnabled then
    HTMLDrawOpt(Canvas, TextR, State, InkToHTML(Items[Index], FTextFormat), Opts)
  else
    Canvas.TextRect(TextR, TextR.Left + 2, TextR.Top, Items[Index]);
end;

procedure TInkListBox.InternalSelectionChange(Sender: TObject; User: Boolean);
begin
  if Assigned(FOnUserSelectionChange) then
    FOnUserSelectionChange(Self, User);
  if User and (FEditMode = emOnSelect) then
  begin
    if FButtonDown then FEditOnRelease := True
    else BeginEdit(ItemIndex);
  end;
  { a selection that moved is not a click on the selected item }
  FClickEditTimer.Enabled := False;
end;

procedure TInkListBox.DblClick;
begin
  inherited DblClick;
  if FEditMode = emOnDblClick then
    BeginEdit(ItemIndex);
  FClickEditTimer.Enabled := False;
end;

procedure TInkListBox.EditItem(Index: Integer);
begin
  BeginEdit(Index);
end;

function TInkListBox.Editing: Boolean;
begin
  Result := (FEdit <> nil) and FEdit.Visible;
end;

procedure TInkListBox.CancelEdit;
begin
  if Editing then HideEdit;
end;

procedure TInkListBox.SetAlternateColor(AValue: TColor);
begin
  if FAlternateColor = AValue then Exit;
  FAlternateColor := AValue;
  Invalidate;
end;

{ Hover is tracked as (row, ordinal-of-link-in-that-row), so two links with the
  same target still light up one at a time. }
procedure TInkListBox.UpdateHover(AItem: Integer; const AHit: THTMLHitInfo);
var
  NewIndex, OldItem: Integer;
  OldLink: string;
begin
  if AHit.OnLink then NewIndex := AHit.LinkIndex else NewIndex := 0;
  if NewIndex = 0 then AItem := -1;
  if (AItem = FHoverItem) and (NewIndex = FHoverIndex) then Exit;

  OldItem := FHoverItem;
  OldLink := FHoverLink;
  if (OldItem >= 0) and Assigned(FOnLinkLeave) then
    FOnLinkLeave(Self, OldItem, OldLink);

  FHoverItem := AItem;
  FHoverIndex := NewIndex;
  if AItem >= 0 then
  begin
    FHoverLink := AHit.LinkName;
    FHoverLinkText := AHit.LinkText;
    Cursor := crHandPoint;
    if Assigned(FOnLinkEnter) then FOnLinkEnter(Self, AItem, FHoverLink);
  end
  else
  begin
    FHoverLink := '';
    FHoverLinkText := '';
    Cursor := crDefault;
  end;
  Invalidate;
end;

procedure TInkListBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  R: TRect;
  Hit: THTMLHitInfo;
begin
  inherited MouseMove(Shift, X, Y);
  { with the button held the highlight follows the pointer, as in most
    list boxes - and past the top or bottom the list scrolls along }
  if FButtonDown and (ssLeft in Shift) and not MultiSelect and (Items.Count > 0) then
  begin
    if Y < 0 then Idx := Max(0, TopIndex - 1)
    else if Y >= ClientHeight then
    begin
      Idx := ItemAtPos(Point(X, ClientHeight - 1), False);
      Idx := Min(Items.Count - 1, Idx + 1);
    end
    else Idx := ItemAtPos(Point(X, Y), False);
    Idx := EnsureRange(Idx, 0, Items.Count - 1);
    if Idx <> ItemIndex then
    begin
      ItemIndex := Idx;
      MakeCurrentVisible;
      if FEditMode = emOnSelect then FEditOnRelease := True;
    end;
  end;
  Hit.OnLink := False;
  Hit.LinkName := '';
  Hit.LinkText := '';
  Hit.LinkIndex := 0;
  Idx := GetIndexAtY(Y);
  if FHTMLEnabled and (Idx >= 0) and (Idx < Items.Count) then
  begin
    R := ItemRect(Idx);
    if R.Right > ClientWidth then
      R.Right := ClientWidth;
    Canvas.Font := Font;
    Hit := HTMLHitTest(Canvas, R, InkToHTML(Items[Idx], FTextFormat), Options, X, Y);
  end;
  UpdateHover(Idx, Hit);
end;

procedure TInkListBox.MouseLeave;
var
  Empty: THTMLHitInfo;
begin
  inherited MouseLeave;
  Empty.OnLink := False;
  Empty.LinkName := '';
  Empty.LinkText := '';
  Empty.LinkIndex := 0;
  UpdateHover(-1, Empty);
end;

procedure TInkListBox.Click;
begin
  inherited Click;
  if (FHoverItem >= 0) and (FHoverLink <> '') then
  begin
    if Assigned(FOnLinkClick) then
      FOnLinkClick(Self, FHoverItem, FHoverLink)
    else if FAutoOpenLink then
      OpenURL(FHoverLink);
  end;
end;

{ The floating editor is a sibling positioned in the parent's coordinates, so a
  resize moves the listbox out from under it. }
procedure TInkListBox.Resize;
begin
  inherited Resize;
  if Assigned(FLinkHoverStyle) then SubPropChanged(nil);
  if (FEdit <> nil) and FEdit.Visible then
    PositionEdit;
end;

function TInkListBox.GetPlainText(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Items.Count) then
    Result := ''
  else
    Result := HTMLPlainText(InkToHTML(Items[Index], FTextFormat));
end;

procedure TInkListBox.SaveAsPlain(const FileName: string);
var
  SL: TStringList;
  i: Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to Items.Count - 1 do
      SL.Add(HTMLPlainText(InkToHTML(Items[i], FTextFormat)));
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TInkListBox.SaveAsHTML(const FileName: string);
var SL: TStringList; I: Integer;
begin
  SL := TStringList.Create;
  try
    for I := 0 to Items.Count - 1 do SL.Add(InkToHTML(Items[I], FTextFormat));
    SL.SaveToFile(FileName);
  finally SL.Free end;
end;


function TInkListBox.PlainText: string;
var I: Integer;
begin
  Result := '';
  for I := 0 to Items.Count - 1 do
    Result := Result + GetPlainText(I) + LineEnding;
end;

{ --- copying ------------------------------------------------------------ }

procedure TInkListBox.DoSelectAll(Sender: TObject);
begin
  if MultiSelect then SelectAll;
  FAllChosen := True;
end;

function TInkListBox.SelectedText: string;
begin
  if FAllChosen then Result := TrimRight(PlainText)
  else Result := InkListSelection(Self, @GetPlainText);
end;

procedure TInkListBox.CopyToClipboard;
var S: string;
begin
  S := SelectedText;
  if S <> '' then InkCopyText(S);
end;

function TInkListBox.BuildCopyMenu(X, Y: Integer): TPopupMenu;
var Texts: TInkCopyTexts; I: Integer;
begin
  Texts := Default(TInkCopyTexts);
  Texts.CanSelect := True;
  Texts.Selection := SelectedText;
  I := ItemAtPos(Point(X, Y), True);
  if I >= 0 then
  begin
    Texts.Block := GetPlainText(I);
    Texts.BlockCaption := SInkCopyItem;
  end;
  Texts.Link := FHoverLink;
  Texts.All := TrimRight(PlainText);
  Texts.SelectAll := @DoSelectAll;
  FCopyMenuHost.Build(Self, Texts, X, Y, FOnCopyMenu);
  Result := FCopyMenuHost.Menu;
end;

procedure TInkListBox.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var P: TPoint;
begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or not FCopyMenu or Assigned(PopupMenu) then Exit;
  if (MousePos.X < 0) and (MousePos.Y < 0) then MousePos := Point(8, 8);
  BuildCopyMenu(MousePos.X, MousePos.Y);
  if FCopyMenuHost.Menu.Items.Count = 0 then Exit;
  P := ClientToScreen(MousePos);
  FCopyMenuHost.Menu.PopUp(P.X, P.Y);
  Handled := True;
end;

procedure TInkListBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Shift * [ssCtrl, ssAlt, ssShift] = [ssCtrl]) and (Key = VK_A) then
  begin
    DoSelectAll(Self);
    Key := 0;
    Exit;
  end;
  if (ssCtrl in Shift) and ((Key = VK_C) or (Key = VK_INSERT)) then
  begin
    CopyToClipboard;
    Key := 0;
    Exit;
  end;
  { Ctrl on its own is how both of those begin; anything else ends "all" }
  if not (Key in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL]) then FAllChosen := False;
  if (Key = VK_F2) and (Shift = []) and (FEditMode <> emNone) and (ItemIndex >= 0) then
  begin
    BeginEdit(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TInkListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Now_: QWord;
  Near: Boolean;
  Idx: Integer;
begin
  if Button <> mbLeft then
  begin
    inherited MouseDown(Button, Shift, X, Y);
    Exit;
  end;
  FAllChosen := False;
  { A press soon after another in the same place is its second or third
    click; GTK repeats a press, marked double, at the same moment, which is
    not one more. }
  Now_ := GetTickCount64;
  Near := (Abs(X - FLastClickX) <= 4) and (Abs(Y - FLastClickY) <= 4);
  if not (Near and (Now_ - FLastClickTime < 25)) then
  begin
    if Near and (Now_ - FLastClickTime <= GetDoubleClickTime) and (FClicks < 3) then
      Inc(FClicks)
    else
    begin
      FClicks := 1;
      { what was selected before this press decides a click-to-rename }
      FPressItem := ItemAtPos(Point(X, Y), True);
      FPressWasSelected := (FPressItem >= 0) and (FPressItem = ItemIndex);
    end;
  end;
  FLastClickTime := Now_; FLastClickX := X; FLastClickY := Y;
  if ssTriple in Shift then FClicks := 3
  else if (ssDouble in Shift) and (FClicks < 2) then FClicks := 2;
  FButtonDown := True;
  FEditOnRelease := False;
  if (FEditMode = emOnSelect) and not MultiSelect then
  begin
    { the item is selected here rather than by the widget, so that the
      editor can wait for the release instead of opening under the press }
    Idx := ItemAtPos(Point(X, Y), True);
    if (Idx >= 0) and (Idx <> ItemIndex) then
    begin
      ItemIndex := Idx;
      FEditOnRelease := True;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
  if FClicks > 1 then FClickEditTimer.Enabled := False;
  if (FClicks = 3) and (FEditMode = emOnTripleClick) then
    BeginEdit(ItemAtPos(Point(X, Y), True));
end;

procedure TInkListBox.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FButtonDown := False;
    if FEditOnRelease and (FEditMode = emOnSelect) and (FHoverLink = '') then
    begin
      FEditOnRelease := False;
      BeginEdit(ItemIndex);
      Exit;
    end;
    FEditOnRelease := False;
  end;
  if (Button = mbRight) and (FHoverItem >= 0) and (FHoverLink <> '') and
    Assigned(FOnLinkRightClick) then
    FOnLinkRightClick(Self, FHoverItem, FHoverLink);
  if (Button = mbLeft) and (FEditMode = emOnClickSelected) and (FClicks = 1) and
    FPressWasSelected and (ItemAtPos(Point(X, Y), True) = FPressItem) and
    (FHoverLink = '') then
  begin
    { wait: this may be the first half of a double click }
    FPendingEdit := FPressItem;
    FClickEditTimer.Interval := GetDoubleClickTime;
    FClickEditTimer.Enabled := False;
    FClickEditTimer.Enabled := True;
  end;
end;

procedure TInkListBox.ClickEditTick(Sender: TObject);
begin
  FClickEditTimer.Enabled := False;
  if (FPendingEdit >= 0) and (FPendingEdit = ItemIndex) then BeginEdit(FPendingEdit);
end;

end.
