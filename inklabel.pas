{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkLabel: a label that renders a subset of HTML inline markup
  (<b> <i> <u> <s> <font color= bgcolor= size= face=> <sup> <sub> <br> <hr>
  <p> <center> <right> <ind=> <img src=> <a href=>) using plain TCanvas
  drawing, so it looks identical on every LCL widgetset (win32, gtk2, gtk3,
  qt, cocoa).

  SPDX-License-Identifier: 0BSD; see LICENSE.
}
unit InkLabel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, LCLType, LCLIntf, Types,
  Math, Menus, Clipbrd, InkDraw, InkMarkdown, InkCopyMenu;

type
  TInkLinkEvent = procedure(Sender: TObject; const LinkName: string) of object;

  { TInkLabel }

  TInkLabel = class(TGraphicControl)
  private
    FTextFormat: TInkTextFormat;
    procedure SetTextFormat(AValue: TInkTextFormat);
  private
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FTransparent: Boolean;
    FWordWrap: Boolean;
    FEllipsis: Boolean;
    FMaxWidth: Integer;
    FLineSpacing: Integer;
    FVertAlign: TInkVertAlign;
    FHorzAlign: TInkHorzAlign;
    FBorders: TInkBorders;
    FImages: TCustomImageList;
    FLinkStyle: TInkLinkStyle;
    FLinkHoverStyle: TInkLinkStyle;
    FAutoOpenLink: Boolean;
    FHoverIndex: Integer;
    FHoverLink: string;
    FHoverLinkText: string;
    FOnLinkClick: TInkLinkEvent;
    FOnLinkEnter: TInkLinkEvent;
    FOnLinkLeave: TInkLinkEvent;
    FOnLinkRightClick: TInkLinkEvent;
    procedure SetHTMLScale(AValue: Integer);
    procedure SetTransparent(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetEllipsis(AValue: Boolean);
    procedure SetMaxWidth(AValue: Integer);
    procedure SetLineSpacing(AValue: Integer);
    procedure SetVertAlign(AValue: TInkVertAlign);
    procedure SetHorzAlign(AValue: TInkHorzAlign);
    procedure SetBorders(AValue: TInkBorders);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetLinkStyle(AValue: TInkLinkStyle);
    procedure SetLinkHoverStyle(AValue: TInkLinkStyle);
    procedure SubPropChanged(Sender: TObject);
    procedure UpdateHover(const AHit: THTMLHitInfo);
  private
    { character selection: offsets into the run map's Words }
    FRunText: TInkRunText;
    FRunsReady: Boolean;
    FSelAnchor, FSelCaret: Integer;
    FSelecting, FSelMoved: Boolean;
    FSelectUnit: Integer;              // 0 characters, 1 words, 2 all
    FUnitFrom, FUnitTo: Integer;
    FPressX, FPressY: Integer;
    FClicks, FLastClickX, FLastClickY: Integer;
    FLastClickTime: QWord;
    procedure NeedRuns;
    procedure InvalidateRuns(AClearSelection: Boolean);
    procedure ExtendSelectionTo(AOffset: Integer);
    procedure DoSelectAll(Sender: TObject);
  private
    FCopyMenu: Boolean;
    FCopyMenuHost: TInkCopyMenu;
    FOnCopyMenu: TInkCopyMenuEvent;
    { Caption as it will actually be drawn: re-flowed when WordWrap or
      MaxWidth ask for it, otherwise the caption untouched. Sets Canvas.Font. }
    function RenderText: string;
  protected
    { Everything the renderer needs beyond the text itself. }
    function Options: THTMLOptions;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure FontChanged(Sender: TObject); override;
    procedure Click; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: integer;
      WithThemeSpace: Boolean); override;
    procedure TextChanged; override;
    procedure DoSetBounds(ALeft, ATop, AWidth, AHeight: integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The caption with all markup stripped }
    function PlainText: string;
    { character selection: a drag selects, a double click takes a word, a
      triple click everything; the copy menu then offers Copy }
    function HasSelection: Boolean;
    function SelectedText: string;
    procedure SelectAll;
    procedure ClearSelection;
    { fills the copy menu for client X, Y without opening it }
    function BuildCopyMenu(X, Y: Integer): TPopupMenu;
    { The href under the mouse, '' when none }
    property HoverLink: string read FHoverLink;
    { The text shown for that link }
    property HoverLinkText: string read FHoverLinkText;
  published
    property TextFormat: TInkTextFormat read FTextFormat write SetTextFormat default itfHTML;
    property Caption;
    property HTMLScale: Integer read FHTMLScale write SetHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    { Re-flow the caption to the control width. With AutoSize the width is left
      alone and only the height follows the text, the way TLabel behaves. }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    { with WordWrap off and AutoSize off: one line that ends in an ellipsis
      when the label is too narrow for it, instead of a word stopping
      halfway through a letter }
    property Ellipsis: Boolean read FEllipsis write SetEllipsis default False;
    { With AutoSize and no WordWrap the label grows sideways forever. MaxWidth
      caps that: past it the text wraps instead. 0 means no cap. }
    property MaxWidth: Integer read FMaxWidth write SetMaxWidth default 0;
    property LineSpacing: Integer read FLineSpacing write SetLineSpacing default 0;
    { Where the block of text sits when the control is bigger than it. }
    property VertAlign: TInkVertAlign read FVertAlign write SetVertAlign default ivaTop;
    property HorzAlign: TInkHorzAlign read FHorzAlign write SetHorzAlign default ihaLeft;
    property Borders: TInkBorders read FBorders write SetBorders;
    { Supplies <img src="n">, where n is an index into this list. }
    property Images: TCustomImageList read FImages write SetImages;
    property LinkStyle: TInkLinkStyle read FLinkStyle write SetLinkStyle;
    property LinkHoverStyle: TInkLinkStyle read FLinkHoverStyle write SetLinkHoverStyle;
    { Open a clicked link with the system browser. Only applies when no
      OnLinkClick handler is assigned - a handler always wins. }
    property AutoOpenLink: Boolean read FAutoOpenLink write FAutoOpenLink default False;
    property OnLinkClick: TInkLinkEvent read FOnLinkClick write FOnLinkClick;
    property OnLinkEnter: TInkLinkEvent read FOnLinkEnter write FOnLinkEnter;
    property OnLinkLeave: TInkLinkEvent read FOnLinkLeave write FOnLinkLeave;
    property OnLinkRightClick: TInkLinkEvent read FOnLinkRightClick write FOnLinkRightClick;
    { the right-click menu: Copy link address over a link, and Copy all.
      Not shown when off or when PopupMenu is set. }
    property CopyMenu: Boolean read FCopyMenu write FCopyMenu default True;
    { lets a program add its own items to that menu as it opens }
    property OnCopyMenu: TInkCopyMenuEvent read FOnCopyMenu write FOnCopyMenu;

    property Align;
    property Anchors;
    property AutoSize;
    property BorderSpacing;
    property Color;
    property Constraints;
    property Enabled;
    property Font;
    property Hint;
    property ParentColor;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnResize;
  end;

implementation

procedure TInkLabel.SetTextFormat(AValue: TInkTextFormat);
begin
  if FTextFormat = AValue then Exit;
  FTextFormat := AValue;
  SubPropChanged(nil);
end;


{ TInkLabel }

constructor TInkLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCopyMenu := True;
  FCopyMenuHost := TInkCopyMenu.Create(Self);
  FRunText := TInkRunText.Create;
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FTransparent := True;
  FHoverIndex := 0;
  FBorders := TInkBorders.Create;
  FBorders.OnChange := @SubPropChanged;
  FLinkStyle := TInkLinkStyle.Create(False);
  FLinkStyle.OnChange := @SubPropChanged;
  FLinkHoverStyle := TInkLinkStyle.Create(True);
  FLinkHoverStyle.OnChange := @SubPropChanged;
  ControlStyle := ControlStyle + [csSetCaption];
  Width := 80;
  Height := 20;
end;

destructor TInkLabel.Destroy;
begin
  FreeAndNil(FRunText);
  FreeAndNil(FBorders);
  FreeAndNil(FLinkStyle);
  FreeAndNil(FLinkHoverStyle);
  inherited Destroy;
end;

function TInkLabel.Options: THTMLOptions;
begin
  Result := InkOptions(FSuperSubScriptRatio, FHTMLScale, FLineSpacing,
    FBorders, FImages, FLinkStyle, FLinkHoverStyle, FHoverIndex);
  Result.VertAlign := FVertAlign;
  Result.HorzAlign := FHorzAlign;
  if FEllipsis and not FWordWrap then
  begin
    Result.NoWrap := True;
    Result.Ellipsis := True;
  end;
end;

procedure TInkLabel.SubPropChanged(Sender: TObject);
begin
  InvalidateRuns(True);
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TInkLabel.SetHTMLScale(AValue: Integer);
begin
  if FHTMLScale = AValue then Exit;
  FHTMLScale := AValue;
  SubPropChanged(nil);
end;

procedure TInkLabel.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TInkLabel.SetEllipsis(AValue: Boolean);
begin
  if FEllipsis = AValue then Exit;
  FEllipsis := AValue;
  SubPropChanged(nil);
end;

procedure TInkLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  SubPropChanged(nil);
end;

procedure TInkLabel.SetMaxWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FMaxWidth = AValue then Exit;
  FMaxWidth := AValue;
  SubPropChanged(nil);
end;

procedure TInkLabel.SetLineSpacing(AValue: Integer);
begin
  if FLineSpacing = AValue then Exit;
  FLineSpacing := AValue;
  SubPropChanged(nil);
end;

procedure TInkLabel.SetVertAlign(AValue: TInkVertAlign);
begin
  if FVertAlign = AValue then Exit;
  FVertAlign := AValue;
  InvalidateRuns(False);
  Invalidate;
end;

procedure TInkLabel.SetHorzAlign(AValue: TInkHorzAlign);
begin
  if FHorzAlign = AValue then Exit;
  FHorzAlign := AValue;
  InvalidateRuns(False);
  Invalidate;
end;

procedure TInkLabel.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  InvalidateRuns(False);
end;

procedure TInkLabel.NeedRuns;
begin
  if FRunsReady then Exit;
  FRunText.Build(Canvas, ClientRect, RenderText, Options);
  FRunsReady := True;
end;

procedure TInkLabel.InvalidateRuns(AClearSelection: Boolean);
begin
  FRunsReady := False;
  if AClearSelection and (FSelAnchor <> FSelCaret) then
  begin
    FSelAnchor := 0;
    FSelCaret := 0;
  end;
end;

function TInkLabel.HasSelection: Boolean;
begin
  Result := FSelAnchor <> FSelCaret;
end;

function TInkLabel.SelectedText: string;
begin
  Result := '';
  if not HasSelection then Exit;
  NeedRuns;
  Result := FRunText.TextRange(FSelAnchor, FSelCaret);
end;

procedure TInkLabel.SelectAll;
begin
  NeedRuns;
  FSelAnchor := 0;
  FSelCaret := Length(FRunText.Words);
  Invalidate;
end;

procedure TInkLabel.ClearSelection;
begin
  if not HasSelection then Exit;
  FSelAnchor := FSelCaret;
  Invalidate;
end;

procedure TInkLabel.DoSelectAll(Sender: TObject);
begin
  SelectAll;
end;

procedure TInkLabel.ExtendSelectionTo(AOffset: Integer);
var
  WordFrom, WordTo: Integer;
begin
  case FSelectUnit of
    1:
      begin
        FRunText.WordAt(AOffset, WordFrom, WordTo);
        if WordFrom < FUnitFrom then
        begin
          FSelAnchor := FUnitTo;
          FSelCaret := WordFrom;
        end
        else
        begin
          FSelAnchor := FUnitFrom;
          FSelCaret := WordTo;
        end;
      end;
    2: ;   // everything is selected already
  else
    FSelCaret := AOffset;
  end;
  Invalidate;
end;

procedure TInkLabel.SetBorders(AValue: TInkBorders);
begin
  FBorders.Assign(AValue);
end;

procedure TInkLabel.SetLinkStyle(AValue: TInkLinkStyle);
begin
  FLinkStyle.Assign(AValue);
end;

procedure TInkLabel.SetLinkHoverStyle(AValue: TInkLinkStyle);
begin
  FLinkHoverStyle.Assign(AValue);
end;

procedure TInkLabel.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  SubPropChanged(nil);
end;

procedure TInkLabel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TInkLabel.TextChanged;
begin
  inherited TextChanged;
  InvalidateRuns(True);
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

{ A narrower label needs more lines, so the height it wants changes with its
  width. Only a *width* change may say so, though: re-measuring on every bounds
  change means the height AdjustSize just applied triggers another measurement,
  which is what TControl's InvalidatePreferredSize loop detector shouts about.
  This is the same guard TCustomLabel uses. }
procedure TInkLabel.DoSetBounds(ALeft, ATop, AWidth, AHeight: integer);
var
  WidthChanged: Boolean;
begin
  WidthChanged := AWidth <> Width;
  if (AWidth <> Width) or (AHeight <> Height) then InvalidateRuns(False);
  inherited DoSetBounds(ALeft, ATop, AWidth, AHeight);
  if WidthChanged and FWordWrap then
  begin
    InvalidatePreferredSize;
    AdjustSize;
    Invalidate;
  end;
end;

function TInkLabel.RenderText: string;
var
  W: Integer;
begin
  Canvas.Font := Font;
  W := 0;
  if FWordWrap then
    W := Width - FBorders.Left - FBorders.Right
  else if FMaxWidth > 0 then
    W := FMaxWidth - FBorders.Left - FBorders.Right;
  if W > 0 then
    Result := HTMLWordWrap(Canvas, InkToHTML(Caption, FTextFormat), W, FSuperSubScriptRatio, FHTMLScale)
  else
    Result := InkToHTML(Caption, FTextFormat);
end;

procedure TInkLabel.Paint;
var
  R: TRect;
begin
  R := ClientRect;
  if not FTransparent then
  begin
    Canvas.Brush.Color := Color;
    Canvas.FillRect(R);
  end;
  Canvas.Brush.Style := bsClear;
  HTMLDrawOpt(Canvas, R, [], RenderText, Options);
  if HasSelection then
  begin
    NeedRuns;
    FRunText.PaintSelection(Canvas, FSelAnchor, FSelCaret, clHighlight);
  end;
end;

{ the mouse selects, as in a browser: a click places (and follows a link),
  a drag selects, a double click takes a word and a triple click all of it }
procedure TInkLabel.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  P, WordFrom, WordTo: Integer;
  Now_: QWord;
  Near: Boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  NeedRuns;
  P := FRunText.OffsetAt(Canvas, X, Y);
  FSelecting := True;
  FSelMoved := False;
  FPressX := X; FPressY := Y;
  { A press soon after another in the same place is its second or third
    click.  GTK sends a double click as a press and then the same press
    again, marked double, at the same moment: that is not one more click. }
  Now_ := GetTickCount64;
  Near := (Abs(X - FLastClickX) <= 4) and (Abs(Y - FLastClickY) <= 4);
  if not (Near and (Now_ - FLastClickTime < 25)) then
  begin
    if Near and (Now_ - FLastClickTime <= GetDoubleClickTime) and (FClicks < 3) then
      Inc(FClicks)
    else
      FClicks := 1;
  end;
  FLastClickTime := Now_; FLastClickX := X; FLastClickY := Y;
  if ssTriple in Shift then FClicks := 3
  else if (ssDouble in Shift) and (FClicks < 2) then FClicks := 2;
  if FClicks = 3 then
  begin
    FSelectUnit := 2; FSelMoved := True;
    SelectAll;
  end
  else if FClicks = 2 then
  begin
    FSelectUnit := 1; FSelMoved := True;
    FRunText.WordAt(P, WordFrom, WordTo);
    FUnitFrom := WordFrom; FUnitTo := WordTo;
    FSelAnchor := WordFrom; FSelCaret := WordTo;
    Invalidate;
  end
  else if (ssShift in Shift) and HasSelection then
  begin
    FSelectUnit := 0; FSelMoved := True;
    FSelCaret := P;
    Invalidate;
  end
  else
  begin
    FSelectUnit := 0;
    FSelAnchor := P; FSelCaret := P;
    Invalidate;
  end;
end;

{ Hover is tracked by link ordinal rather than by href, so two links to the
  same target still light up one at a time. }
procedure TInkLabel.UpdateHover(const AHit: THTMLHitInfo);
var
  NewIndex: Integer;
  OldLink: string;
begin
  if AHit.OnLink then NewIndex := AHit.LinkIndex else NewIndex := 0;
  if NewIndex = FHoverIndex then Exit;

  OldLink := FHoverLink;
  if (FHoverIndex > 0) and Assigned(FOnLinkLeave) then
    FOnLinkLeave(Self, OldLink);

  FHoverIndex := NewIndex;
  if NewIndex > 0 then
  begin
    FHoverLink := AHit.LinkName;
    FHoverLinkText := AHit.LinkText;
    Cursor := crHandPoint;
    if Assigned(FOnLinkEnter) then FOnLinkEnter(Self, FHoverLink);
  end
  else
  begin
    FHoverLink := '';
    FHoverLinkText := '';
    Cursor := crDefault;
  end;
  Invalidate;
end;

procedure TInkLabel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Opts: THTMLOptions;
begin
  inherited MouseMove(Shift, X, Y);
  if FSelecting and (ssLeft in Shift) then
  begin
    if not FSelMoved and ((Abs(X - FPressX) > 3) or (Abs(Y - FPressY) > 3)) then
      FSelMoved := True;
    if FSelMoved then
    begin
      NeedRuns;
      ExtendSelectionTo(FRunText.OffsetAt(Canvas, X, Y));
      Exit;
    end;
  end;
  Opts := Options;
  Opts.HoverIndex := 0;   // the hit test must not depend on the current hover
  Canvas.Font := Font;
  UpdateHover(HTMLHitTest(Canvas, ClientRect, RenderText, Opts, X, Y));
  if FHoverIndex = 0 then
  begin
    NeedRuns;
    if FRunText.OverText(X, Y) then Cursor := crIBeam else Cursor := crDefault;
  end;
end;

procedure TInkLabel.MouseLeave;
var
  Empty: THTMLHitInfo;
begin
  inherited MouseLeave;
  Empty.OnLink := False;
  Empty.LinkName := '';
  Empty.LinkText := '';
  Empty.LinkIndex := 0;
  UpdateHover(Empty);
end;

procedure TInkLabel.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and FSelecting then
  begin
    FSelecting := False;
    if FSelMoved and HasSelection then
      { X11's other clipboard: what is selected is ready for a middle click }
      Clipboard(ctPrimarySelection).AsText := SelectedText;
  end;
  if (Button = mbRight) and (FHoverIndex > 0) and (FHoverLink <> '') and
    Assigned(FOnLinkRightClick) then
    FOnLinkRightClick(Self, FHoverLink);
end;

procedure TInkLabel.Click;
begin
  inherited Click;
  { a drag that selected is not a click on a link }
  if FSelMoved then Exit;
  if (FHoverIndex > 0) and (FHoverLink <> '') then
  begin
    if Assigned(FOnLinkClick) then
      FOnLinkClick(Self, FHoverLink)
    else if FAutoOpenLink then
      OpenURL(FHoverLink);
  end;
end;

procedure TInkLabel.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: integer; WithThemeSpace: Boolean);
var
  Sz: TSize;
  R: TRect;
begin
  if (Parent = nil) or not Parent.HandleAllocated then
  begin
    inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
    Exit;
  end;
  Canvas.Font := Font;
  if FWordWrap then
  begin
    // wrapped text has no natural width - it takes whatever it is given and
    // grows downwards. PreferredWidth = 0 tells the LCL to leave width alone.
    R := Rect(0, 0, Width, 100000);
    Sz := HTMLTextExtentOpt(Canvas, R, [], RenderText, Options);
    PreferredWidth := 0;
    PreferredHeight := Sz.cy;
    Exit;
  end;
  R := Rect(0, 0, 100000, 100000);
  Sz := HTMLTextExtentOpt(Canvas, R, [], RenderText, Options);
  PreferredWidth := Sz.cx;
  PreferredHeight := Sz.cy;
end;

function TInkLabel.PlainText: string;
begin
  Result := HTMLPlainText(InkToHTML(Caption, FTextFormat));
end;

function TInkLabel.BuildCopyMenu(X, Y: Integer): TPopupMenu;
var Texts: TInkCopyTexts;
begin
  Texts := Default(TInkCopyTexts);
  Texts.CanSelect := True;
  Texts.Selection := SelectedText;
  Texts.SelectAll := @DoSelectAll;
  Texts.Link := FHoverLink;
  Texts.All := PlainText;
  FCopyMenuHost.Build(Self, Texts, X, Y, FOnCopyMenu);
  Result := FCopyMenuHost.Menu;
end;

procedure TInkLabel.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var P: TPoint;
begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or not FCopyMenu or Assigned(PopupMenu) then Exit;
  if (MousePos.X < 0) and (MousePos.Y < 0) then MousePos := Point(0, 0);
  BuildCopyMenu(MousePos.X, MousePos.Y);
  if FCopyMenuHost.Menu.Items.Count = 0 then Exit;
  P := ClientToScreen(MousePos);
  FCopyMenuHost.Menu.PopUp(P.X, P.Y);
  Handled := True;
end;

end.
