{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkLabel: a label that renders a subset of HTML inline markup
  (<b> <i> <u> <s> <font color= bgcolor= size= face=> <sup> <sub> <br> <hr>
  <p> <center> <right> <ind=> <img src=> <a href=>) using plain TCanvas
  drawing, so it looks identical on every LCL widgetset (win32, gtk2, gtk3,
  qt, cocoa).

  License: component code MIT; the renderer unit InkHtml is derived
  from the JVCL project (MPL 1.1) — see that unit's header.
}
unit InkLabel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, LCLType, LCLIntf, Types,
  Menus, InkHtml, InkMarkdown, InkCopyMenu;

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
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseLeave; override;
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
end;

procedure TInkLabel.SubPropChanged(Sender: TObject);
begin
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
  Invalidate;
end;

procedure TInkLabel.SetHorzAlign(AValue: TInkHorzAlign);
begin
  if FHorzAlign = AValue then Exit;
  FHorzAlign := AValue;
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
  Opts := Options;
  Opts.HoverIndex := 0;   // the hit test must not depend on the current hover
  Canvas.Font := Font;
  UpdateHover(HTMLHitTest(Canvas, ClientRect, RenderText, Opts, X, Y));
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
  if (Button = mbRight) and (FHoverIndex > 0) and (FHoverLink <> '') and
    Assigned(FOnLinkRightClick) then
    FOnLinkRightClick(Self, FHoverLink);
end;

procedure TInkLabel.Click;
begin
  inherited Click;
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
