{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkLabel: a label that renders a subset of HTML inline markup
  (<b> <i> <u> <s> <font color= bgcolor= size=> <sup> <sub> <br> <hr>
  <center> <right> <ind=> <a href=>) using plain TCanvas drawing, so it
  looks identical on every LCL widgetset (win32, gtk2, gtk3, qt, cocoa).

  License: component code MIT; the renderer unit jvclHTMLUtils is derived
  from the JVCL project (MPL 1.1) — see that unit's header.
}
unit InkLabel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, LCLIntf, Types;

type
  TInkLinkEvent = procedure(Sender: TObject; const LinkName: string) of object;

  { TInkLabel }

  TInkLabel = class(TGraphicControl)
  private
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FTransparent: Boolean;
    FOnLinkClick: TInkLinkEvent;
    FMouseOnLink: Boolean;
    FLinkName: string;
    procedure SetHTMLScale(AValue: Integer);
    procedure SetTransparent(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Click; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: integer;
      WithThemeSpace: Boolean); override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The caption with all markup stripped }
    function PlainText: string;
  published
    property Caption;
    property HTMLScale: Integer read FHTMLScale write SetHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    property OnLinkClick: TInkLinkEvent read FOnLinkClick write FOnLinkClick;

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

uses
  jvclHTMLUtils;

{ TInkLabel }

constructor TInkLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FTransparent := True;
  ControlStyle := ControlStyle + [csSetCaption];
  Width := 80;
  Height := 20;
end;

procedure TInkLabel.SetHTMLScale(AValue: Integer);
begin
  if FHTMLScale = AValue then Exit;
  FHTMLScale := AValue;
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TInkLabel.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TInkLabel.TextChanged;
begin
  inherited TextChanged;
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TInkLabel.Paint;
var
  R: TRect;
  W, H: Integer;
  OnLink: Boolean;
  Link: string;
begin
  R := ClientRect;
  if not FTransparent then
  begin
    Canvas.Brush.Color := Color;
    Canvas.FillRect(R);
  end;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  Link := '';
  HTMLDrawTextEx2(Canvas, R, [], Caption, W, H, htmlShow, 0, 0, OnLink, Link,
    FSuperSubScriptRatio, FHTMLScale);
end;

procedure TInkLabel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  W: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  FLinkName := '';
  Canvas.Font := Font;
  HTMLDrawTextEx(Canvas, ClientRect, [], Caption, W, htmlHyperLink, X, Y,
    FMouseOnLink, FLinkName, FSuperSubScriptRatio, FHTMLScale);
  if FMouseOnLink then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TInkLabel.Click;
begin
  inherited Click;
  if FMouseOnLink and (FLinkName <> '') and Assigned(FOnLinkClick) then
    FOnLinkClick(Self, FLinkName);
end;

procedure TInkLabel.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: integer; WithThemeSpace: Boolean);
var
  Sz: TSize;
begin
  if (Parent = nil) or not Parent.HandleAllocated then
  begin
    inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
    Exit;
  end;
  Canvas.Font := Font;
  Sz := HTMLTextExtent(Canvas, Rect(0, 0, 100000, 100000), [], Caption,
    FSuperSubScriptRatio, FHTMLScale);
  PreferredWidth := Sz.cx;
  PreferredHeight := Sz.cy;
end;

function TInkLabel.PlainText: string;
begin
  Result := HTMLPlainText(Caption);
end;

end.
