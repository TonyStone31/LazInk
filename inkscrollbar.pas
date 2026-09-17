{ Canvas-drawn vertical scrollbar for LazInk. SPDX-License-Identifier: MIT }
unit InkScrollBar;
{$mode objfpc}{$H+}
interface
uses Classes, Controls, Graphics, Types;
type
  TInkScrollBar = class(TCustomControl)
  private
    FPosition, FMin, FMax, FPageSize, FGrabY, FGrabPosition: Integer;
    FDragging, FHover: Boolean;
    FThumbColor, FTrackColor: TColor;
    FOnChange: TNotifyEvent;
    procedure SetPosition(AValue: Integer);
    function LastPosition: Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseLeave; override;
    procedure CaptureChanged; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetParams(APosition, AMin, AMax, APageSize: Integer);
    procedure SetColors(AThumb, ATrack: TColor);
    function ThumbRect: TRect;
    procedure RenderTo(ACanvas: TCanvas; const Bounds: TRect);
    property Position: Integer read FPosition write SetPosition;
    property PageSize: Integer read FPageSize;
    property ThumbColor: TColor read FThumbColor;
    property TrackColor: TColor read FTrackColor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation
uses Math, LCLType;
constructor TInkScrollBar.Create(AOwner: TComponent);
begin
  inherited; Width := 18; Height := 100; TabStop := True;
  FPageSize := 1; FMax := 1; FThumbColor := clBtnShadow; FTrackColor := clBtnFace;
end;
function TInkScrollBar.LastPosition: Integer;
begin Result := Max(FMin,FMax-FPageSize) end;
procedure TInkScrollBar.SetPosition(AValue: Integer);
begin
  AValue := EnsureRange(AValue,FMin,LastPosition);
  if FPosition=AValue then Exit;
  FPosition := AValue; Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;
procedure TInkScrollBar.SetParams(APosition, AMin, AMax, APageSize: Integer);
begin
  FMin := AMin; FMax := Max(AMin,AMax); FPageSize := Max(1,APageSize);
  SetPosition(APosition); Invalidate;
end;
procedure TInkScrollBar.SetColors(AThumb, ATrack: TColor);
begin
  if (FThumbColor=AThumb) and (FTrackColor=ATrack) then Exit;
  FThumbColor := AThumb; FTrackColor := ATrack; Invalidate;
end;
function TInkScrollBar.ThumbRect: TRect;
var H,Y,TrackH: Integer;
begin
  TrackH := Max(0,ClientHeight-4);
  H := Min(TrackH,Max(24,Integer(Int64(TrackH)*FPageSize div Max(1,FMax-FMin))));
  Y := 2;
  if LastPosition>FMin then Inc(Y,Integer(Int64(TrackH-H)*(FPosition-FMin) div (LastPosition-FMin)));
  Result := Rect(2,Y,Max(2,ClientWidth-2),Y+H);
end;
procedure TInkScrollBar.RenderTo(ACanvas: TCanvas; const Bounds: TRect);
var R: TRect; C: TColor;
begin
  ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := FTrackColor;
  ACanvas.FillRect(Bounds);
  if LastPosition=FMin then Exit;
  R := ThumbRect; OffsetRect(R,Bounds.Left,Bounds.Top);
  C := ColorToRGB(FThumbColor);
  if FHover or FDragging or Focused then
    C := RGBToColor(Min(255,Red(C)+24),Min(255,Green(C)+24),Min(255,Blue(C)+24));
  ACanvas.Brush.Color := C; ACanvas.Pen.Color := C;
  ACanvas.RoundRect(R.Left,R.Top,R.Right,R.Bottom,Min(8,Width-4),Min(8,Width-4));
end;
procedure TInkScrollBar.Paint;
begin RenderTo(Canvas,ClientRect) end;
procedure TInkScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var R: TRect;
begin
  inherited;
  if (Button<>mbLeft) or (LastPosition=FMin) then Exit;
  if CanFocus then SetFocus;
  R := ThumbRect;
  if PtInRect(R,Point(X,Y)) then
  begin
    FDragging := True; FGrabY := Y; FGrabPosition := FPosition; MouseCapture := True;
  end
  else if Y<R.Top then Position := FPosition-FPageSize
  else Position := FPosition+FPageSize;
  Invalidate;
end;
procedure TInkScrollBar.MouseMove(Shift: TShiftState; X,Y: Integer);
var R: TRect; Travel: Integer; Hover: Boolean;
begin
  inherited; R := ThumbRect;
  Hover := PtInRect(R,Point(X,Y));
  if Hover<>FHover then begin FHover := Hover; Invalidate end;
  if FDragging then
  begin
    Travel := Max(1,ClientHeight-4-(R.Bottom-R.Top));
    Position := EnsureRange(Int64(FGrabPosition)+Int64(Y-FGrabY)*(LastPosition-FMin) div Travel,Int64(FMin),Int64(LastPosition));
  end;
end;
procedure TInkScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if Button<>mbLeft then Exit;
  FDragging := False; MouseCapture := False; Invalidate;
end;
procedure TInkScrollBar.MouseLeave;
begin inherited; FHover := False; Invalidate end;
procedure TInkScrollBar.CaptureChanged;
begin inherited; if not MouseCapture then begin FDragging := False; Invalidate end end;
procedure TInkScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  case Key of
    VK_UP: Position := FPosition-32;
    VK_DOWN: Position := FPosition+32;
    VK_PRIOR: Position := FPosition-FPageSize;
    VK_NEXT: Position := FPosition+FPageSize;
    VK_HOME: Position := FMin;
    VK_END: Position := LastPosition;
  else Exit end;
  Key := 0;
end;
function TInkScrollBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin Position := FPosition-WheelDelta div 3; Result := True end;
end.
