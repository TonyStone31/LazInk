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
  Classes, SysUtils, Controls, Graphics, StdCtrls, ImgList, LCLType, LCLIntf,
  Types, Menus, InkHtml, InkMarkdown, InkCopyMenu;

type
  TInkMemoLinkEvent = procedure(Sender: TObject; LineIndex: Integer;
    const LinkName: string) of object;

  { TInkMemo }

  TInkMemo = class(TCustomListBox)
  private
    FTextFormat: TInkTextFormat;
    procedure SetTextFormat(AValue: TInkTextFormat);
  private
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FShowSelection: Boolean;
    FWordWrap: Boolean;
    FWrapSrc: TStringList;   { the item text each cache entry was built from }
    FWrapOut: TStringList;   { the wrapped markup for it }
    FWrapWidth: Integer;     { the width the cache was built for, -1 = empty }
    FLineSpacing: Integer;
    FBorders: TInkBorders;
    FImages: TCustomImageList;
    FLinkStyle: TInkLinkStyle;
    FLinkHoverStyle: TInkLinkStyle;
    FAutoOpenLink: Boolean;
    FHoverLine: Integer;     // -1 when the mouse is not over a link
    FHoverIndex: Integer;    // ordinal of that link within its line
    FHoverLink: string;
    FHoverLinkText: string;
    FOnLinkClick: TInkMemoLinkEvent;
    FOnLinkEnter: TInkMemoLinkEvent;
    FOnLinkLeave: TInkMemoLinkEvent;
    FOnLinkRightClick: TInkMemoLinkEvent;
  private
    { the copy menu, and Ctrl+A / Ctrl+C }
    FCopyMenu: Boolean;
    FCopyMenuHost: TInkCopyMenu;
    FOnCopyMenu: TInkCopyMenuEvent;
    { Ctrl+A was the last thing done: Ctrl+C copies everything }
    FAllChosen: Boolean;
    procedure DoSelectAll(Sender: TObject);
    procedure SetLineSpacing(AValue: Integer);
    procedure SetBorders(AValue: TInkBorders);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetLinkStyle(AValue: TInkLinkStyle);
    procedure SetLinkHoverStyle(AValue: TInkLinkStyle);
    procedure SubPropChanged(Sender: TObject);
    procedure UpdateHover(ALine: Integer; const AHit: THTMLHitInfo);
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    procedure SetHTMLScale(AValue: Integer);
    procedure SetWordWrap(AValue: Boolean);
    procedure InvalidateWrap;
    procedure RemeasureItems;
    { The markup for line Index as it will actually be drawn - re-flowed to the
      client width when WordWrap is on, otherwise the line untouched. }
    function RenderText(Index: Integer): string;
  public
    { The href under the mouse, '' when none }
    property HoverLink: string read FHoverLink;
    property HoverLinkText: string read FHoverLinkText;
  protected
    { Everything the renderer needs beyond the text itself. }
    function Options(AHoverIndex: Integer = 0): THTMLOptions;
    procedure DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState); override;
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
    procedure MeasureItem(Index: Integer; var TheHeight: Integer); override;
    procedure Click; override;
    procedure Append(const ALine: string);
    procedure LoadDocument(const Source: string);
    { line ALine with all markup stripped }
    function GetPlainText(ALine: Integer): string;
    { the whole text with all markup stripped }
    function PlainText: string;
    procedure SaveAsPlain(const FileName: string);
    procedure SaveAsHTML(const FileName: string);
    { the selected lines as plain text - every one after Ctrl+A }
    function SelectedText: string;
    procedure CopyToClipboard;
    { fills the copy menu for client X, Y without opening it }
    function BuildCopyMenu(X, Y: Integer): TPopupMenu;
  published
    property TextFormat: TInkTextFormat read FTextFormat write SetTextFormat default itfHTML;
    property Lines: TStrings read GetLines write SetLines;
    { the right-click menu: Copy, Copy this line, Copy link address,
      Copy all, Select all.  Not shown when off or when PopupMenu is set. }
    property CopyMenu: Boolean read FCopyMenu write FCopyMenu default True;
    { lets a program add its own items to that menu as it opens }
    property OnCopyMenu: TInkCopyMenuEvent read FOnCopyMenu write FOnCopyMenu;

    property HTMLScale: Integer read FHTMLScale write SetHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property ShowSelection: Boolean read FShowSelection write FShowSelection default False;
    property LineSpacing: Integer read FLineSpacing write SetLineSpacing default 0;
    { Margins around the text. Each row is drawn on its own, so Top and Bottom
      are padding inside every row rather than once for the whole control;
      LineSpacing is what separates lines within a row. }
    property Borders: TInkBorders read FBorders write SetBorders;
    { Supplies <img src="n">, where n is an index into this list. }
    property Images: TCustomImageList read FImages write SetImages;
    property LinkStyle: TInkLinkStyle read FLinkStyle write SetLinkStyle;
    property LinkHoverStyle: TInkLinkStyle read FLinkHoverStyle write SetLinkHoverStyle;
    { Open a clicked link with the system browser. Only applies when no
      OnLinkClick handler is assigned - a handler always wins. }
    property AutoOpenLink: Boolean read FAutoOpenLink write FAutoOpenLink default False;
    property OnLinkEnter: TInkMemoLinkEvent read FOnLinkEnter write FOnLinkEnter;
    property OnLinkLeave: TInkMemoLinkEvent read FOnLinkLeave write FOnLinkLeave;
    property OnLinkRightClick: TInkMemoLinkEvent read FOnLinkRightClick write FOnLinkRightClick;
    { Re-flow each line to the control width instead of letting it run off the
      right edge. Lines still break at <br>/<p> as well; wrapping only adds
      breaks. Set ScrollWidth to 0 so no horizontal scrollbar appears. }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
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

procedure TInkMemo.LoadDocument(const Source: string);
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    Items.Add(Source);
  finally Items.EndUpdate end;
end;

procedure TInkMemo.SetTextFormat(AValue: TInkTextFormat);
begin
  if FTextFormat = AValue then Exit;
  FTextFormat := AValue;
  SubPropChanged(nil);
end;


const
  { room for the border and the couple of pixels the renderer leaves }
  cWrapMargin = 6;
  { cache sentinel - no real item ever starts with this }
  cNeverAnItem = #1'?';

{ TInkMemo }

constructor TInkMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCopyMenu := True;
  FCopyMenuHost := TInkCopyMenu.Create(Self);
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FShowSelection := False;
  FWordWrap := False;
  FHoverLine := -1;
  FBorders := TInkBorders.Create;
  FBorders.OnChange := @SubPropChanged;
  FLinkStyle := TInkLinkStyle.Create(False);
  FLinkStyle.OnChange := @SubPropChanged;
  FLinkHoverStyle := TInkLinkStyle.Create(True);
  FLinkHoverStyle.OnChange := @SubPropChanged;
  FWrapSrc := TStringList.Create;
  FWrapOut := TStringList.Create;
  FWrapWidth := -1;
  Style := lbOwnerDrawVariable;
end;

destructor TInkMemo.Destroy;
begin
  FreeAndNil(FWrapSrc);
  FreeAndNil(FWrapOut);
  FreeAndNil(FBorders);
  FreeAndNil(FLinkStyle);
  FreeAndNil(FLinkHoverStyle);
  inherited Destroy;
end;

function TInkMemo.Options(AHoverIndex: Integer = 0): THTMLOptions;
begin
  Result := InkOptions(FSuperSubScriptRatio, FHTMLScale, FLineSpacing,
    FBorders, FImages, FLinkStyle, FLinkHoverStyle, AHoverIndex);
end;

procedure TInkMemo.SubPropChanged(Sender: TObject);
begin
  InvalidateWrap;
  RemeasureItems;
end;

procedure TInkMemo.SetLineSpacing(AValue: Integer);
begin
  if FLineSpacing = AValue then Exit;
  FLineSpacing := AValue;
  SubPropChanged(nil);
end;

procedure TInkMemo.SetBorders(AValue: TInkBorders);
begin
  FBorders.Assign(AValue);
end;

procedure TInkMemo.SetLinkStyle(AValue: TInkLinkStyle);
begin
  FLinkStyle.Assign(AValue);
end;

procedure TInkMemo.SetLinkHoverStyle(AValue: TInkLinkStyle);
begin
  FLinkHoverStyle.Assign(AValue);
end;

procedure TInkMemo.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  SubPropChanged(nil);
end;

procedure TInkMemo.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
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
  InvalidateWrap;
  RemeasureItems;
end;

procedure TInkMemo.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  InvalidateWrap;
  RemeasureItems;
end;

procedure TInkMemo.InvalidateWrap;
begin
  FWrapWidth := -1;
  FWrapSrc.Clear;
  FWrapOut.Clear;
end;

{ Line heights come from MeasureItem, which the widgetset only asks for when it
  thinks something changed. Touching Items is the portable way to say so. }
procedure TInkMemo.RemeasureItems;
begin
  if HandleAllocated then
  begin
    Items.BeginUpdate;
    Items.EndUpdate;
  end;
  Invalidate;
end;

procedure TInkMemo.Resize;
begin
  inherited Resize;
  if Assigned(FWrapSrc) and (FWrapWidth <> ClientWidth - cWrapMargin - FBorders.Left - FBorders.Right) then
  begin
    InvalidateWrap;
    RemeasureItems;
  end;
end;

function TInkMemo.RenderText(Index: Integer): string;
var
  W: Integer;
begin
  if (Index < 0) or (Index >= Items.Count) then
    Exit('');
  if not FWordWrap then
    Exit(InkToHTML(Items[Index], FTextFormat));

  W := ClientWidth - cWrapMargin - FBorders.Left - FBorders.Right;
  if W <= 0 then
    Exit(InkToHTML(Items[Index], FTextFormat));

  // wrapping a line is not cheap and both MeasureItem and DrawItem want the
  // same answer, so keep it until the line or the width it was fitted to changes
  if W <> FWrapWidth then
  begin
    FWrapWidth := W;
    FWrapSrc.Clear;
    FWrapOut.Clear;
  end;
  while FWrapSrc.Count > Items.Count do
  begin
    FWrapSrc.Delete(FWrapSrc.Count - 1);
    FWrapOut.Delete(FWrapOut.Count - 1);
  end;
  while FWrapSrc.Count <= Index do
  begin
    FWrapSrc.Add(cNeverAnItem);
    FWrapOut.Add('');
  end;
  if FWrapSrc[Index] <> Items[Index] then
  begin
    Canvas.Font := Font;
    FWrapOut[Index] := HTMLWordWrap(Canvas, InkToHTML(Items[Index], FTextFormat), W,
      FSuperSubScriptRatio, FHTMLScale);
    FWrapSrc[Index] := Items[Index];
  end;
  Result := FWrapOut[Index];
end;

procedure TInkMemo.MeasureItem(Index: Integer; var TheHeight: Integer);
begin
  if (Index >= 0) and (Index < Items.Count) then
  begin
    Canvas.Font := Font;
    TheHeight := HTMLTextExtentOpt(Canvas, Rect(0, 0, ClientWidth, 0), [], RenderText(Index), Options).cy + 2;
  end
  else
    inherited MeasureItem(Index, TheHeight);
end;

procedure TInkMemo.DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  TextR: TRect;
  Opts: THTMLOptions;
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
  // The row rectangle the widgetset hands over can be wider than the column
  // actually on screen, and <center>/<right> place themselves relative to
  // whatever rectangle they are given - which would push a centred line off
  // to the right and a right-aligned one clean out of view.
  TextR := ARect;
  if TextR.Right > ClientWidth then
    TextR.Right := ClientWidth;

  // the hovered link only lights up on the line it is actually on
  if Index = FHoverLine then
    Opts := Options(FHoverIndex)
  else
    Opts := Options;
  if FShowSelection then
    HTMLDrawOpt(Canvas, TextR, State, RenderText(Index), Opts)
  else
    HTMLDrawOpt(Canvas, TextR, [], RenderText(Index), Opts);
end;

{ Hover is tracked as (line, ordinal-of-link-on-that-line), so two links with
  the same target still light up one at a time. }
procedure TInkMemo.UpdateHover(ALine: Integer; const AHit: THTMLHitInfo);
var
  NewIndex, OldLine: Integer;
  OldLink: string;
begin
  if AHit.OnLink then NewIndex := AHit.LinkIndex else NewIndex := 0;
  if NewIndex = 0 then ALine := -1;
  if (ALine = FHoverLine) and (NewIndex = FHoverIndex) then Exit;

  OldLine := FHoverLine;
  OldLink := FHoverLink;
  if (OldLine >= 0) and Assigned(FOnLinkLeave) then
    FOnLinkLeave(Self, OldLine, OldLink);

  FHoverLine := ALine;
  FHoverIndex := NewIndex;
  if ALine >= 0 then
  begin
    FHoverLink := AHit.LinkName;
    FHoverLinkText := AHit.LinkText;
    Cursor := crHandPoint;
    if Assigned(FOnLinkEnter) then FOnLinkEnter(Self, ALine, FHoverLink);
  end
  else
  begin
    FHoverLink := '';
    FHoverLinkText := '';
    Cursor := crDefault;
  end;
  Invalidate;
end;

procedure TInkMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  R: TRect;
  Hit: THTMLHitInfo;
begin
  inherited MouseMove(Shift, X, Y);
  Hit.OnLink := False;
  Hit.LinkName := '';
  Hit.LinkText := '';
  Hit.LinkIndex := 0;
  Idx := GetIndexAtY(Y);
  if (Idx >= 0) and (Idx < Items.Count) then
  begin
    R := ItemRect(Idx);
    if R.Right > ClientWidth then
      R.Right := ClientWidth;
    Canvas.Font := Font;
    Hit := HTMLHitTest(Canvas, R, RenderText(Idx), Options, X, Y);
  end;
  UpdateHover(Idx, Hit);
end;

procedure TInkMemo.MouseLeave;
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

procedure TInkMemo.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbRight) and (FHoverLine >= 0) and (FHoverLink <> '') and
    Assigned(FOnLinkRightClick) then
    FOnLinkRightClick(Self, FHoverLine, FHoverLink);
end;

procedure TInkMemo.Click;
begin
  inherited Click;
  if (FHoverLine >= 0) and (FHoverLink <> '') then
  begin
    if Assigned(FOnLinkClick) then
      FOnLinkClick(Self, FHoverLine, FHoverLink)
    else if FAutoOpenLink then
      OpenURL(FHoverLink);
  end;
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
    Result := HTMLPlainText(InkToHTML(Items[ALine], FTextFormat));
end;

function TInkMemo.PlainText: string;
var
  SL: TStringList;
  i: Integer;
begin
  SL := TStringList.Create;
  try
    for i := 0 to Items.Count - 1 do
      SL.Add(HTMLPlainText(InkToHTML(Items[i], FTextFormat)));
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
      SL.Add(HTMLPlainText(InkToHTML(Items[i], FTextFormat)));
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TInkMemo.SaveAsHTML(const FileName: string);
var SL: TStringList; I: Integer;
begin
  SL := TStringList.Create;
  try
    for I := 0 to Items.Count - 1 do SL.Add(InkToHTML(Items[I], FTextFormat));
    SL.SaveToFile(FileName);
  finally SL.Free end;
end;


{ --- copying ------------------------------------------------------------ }

procedure TInkMemo.DoSelectAll(Sender: TObject);
begin
  if MultiSelect then SelectAll;
  FAllChosen := True;
end;

function TInkMemo.SelectedText: string;
begin
  if FAllChosen then Result := TrimRight(PlainText)
  else Result := InkListSelection(Self, @GetPlainText);
end;

procedure TInkMemo.CopyToClipboard;
var S: string;
begin
  S := SelectedText;
  if S <> '' then InkCopyText(S);
end;

function TInkMemo.BuildCopyMenu(X, Y: Integer): TPopupMenu;
var Texts: TInkCopyTexts; I: Integer;
begin
  Texts := Default(TInkCopyTexts);
  Texts.CanSelect := True;
  Texts.Selection := SelectedText;
  I := ItemAtPos(Point(X, Y), True);
  if I >= 0 then
  begin
    Texts.Block := GetPlainText(I);
    Texts.BlockCaption := SInkCopyLine;
  end;
  Texts.Link := FHoverLink;
  Texts.All := TrimRight(PlainText);
  Texts.SelectAll := @DoSelectAll;
  FCopyMenuHost.Build(Self, Texts, X, Y, FOnCopyMenu);
  Result := FCopyMenuHost.Menu;
end;

procedure TInkMemo.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
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

procedure TInkMemo.KeyDown(var Key: Word; Shift: TShiftState);
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
  inherited KeyDown(Key, Shift);
end;

procedure TInkMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then FAllChosen := False;
  inherited MouseDown(Button, Shift, X, Y);
end;

end.
