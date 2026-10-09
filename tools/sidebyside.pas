{ Side by side: a browser's rendering of a page, and LazInk's.

    tools/sidebyside.pas page.html [width]

  The left half is a picture of the page as a real browser draws it, taken
  by tools/browser_shot.sh (any Chromium-family browser, headless).  The
  right half is the page in a live LazInk control.  Both scroll together, so
  the same words are beside each other wherever you are on the page.

  Keys:

    arrows, PgUp/PgDn, Home/End   scroll both sides
    mouse wheel                    the same
    1                              the right side is a TInkPage (the default)
    2                              a TInkMemo
    3                              a TInkListBox
    4                              a TInkLabel
    S, or F5                       write a snapshot beside the page as
                                   sidebyside-NNN.png and say so
    L                              lock or unlock the two sides' scrolling
    Q, Esc                         quit

  So: scroll to something that looks wrong, press S, and the PNG is on disk
  to look at.

  It is a tool, not a test; tests/run.sh does not build it.

  SPDX-License-Identifier: 0BSD }
program sidebyside;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, LCLType, Math,
  ExtCtrls, StdCtrls, Process, InkPage, InkMemo, InkListBox, InkLabel, InkDraw, InkTouch;

type

  TCompareForm = class;

  { The page and the memo, with the form's crosshair painted on top of
    their own rendering.  A TShape cannot do it: a windowed control always
    paints above sibling graphic controls, so a shape's line would lie
    under the page.  The list box and the label are left out - the list
    paints per item, and the label is a graphic control the shapes do
    cover. }
  TGuidePage = class(TInkPage)
  protected
    procedure Paint; override;
  end;

  TGuideMemo = class(TInkMemo)
  protected
    procedure Paint; override;
  end;

  { TCompareForm }

  TCompareForm = class(TForm)
  private
    FWheelRest: Double;
    FShot: TPortableNetworkGraphic;
    FShotBmp: TBitmap;
    FPage: TInkPage;
    FMemo: TInkMemo;
    FList: TInkListBox;
    FLabel: TInkLabel;
    FLeft: TPaintBox;
    FBar: TPanel;
    FCaption: TLabel;
    FPath, FBrowserShot, FMarkup: string;
    FTop: Integer;
    FLocked: Boolean;
    FShown: Integer;
    FSnaps: Integer;
    { the crosshair: a horizontal line across both halves and a vertical
      line in each at the same offset from its half's left edge, so an
      edge on one side can be held against the other }
    FGuideH, FGuideVL: TShape;
    FGuideTimer: TTimer;
    FGuideOn: Boolean;
    FGuideY, FGuideLX: Integer;
    procedure GuideTick(Sender: TObject);
  public
    { called by the right-hand controls at the end of their Paint }
    procedure PaintGuide(ACanvas: TCanvas; AControl: TControl);
    procedure PaintLeft(Sender: TObject);
    procedure ScrollBoth(ADelta: Integer);
    procedure ShowWhich(N: Integer);
    procedure Snap;
    procedure Tell;
  protected
    procedure DoShow; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor CreateFor(const APage, AShot: string; AWidth: Integer);
    destructor Destroy; override;
  end;

constructor TCompareForm.CreateFor(const APage, AShot: string; AWidth: Integer);
var Html: TStringList; Half: Integer;
begin
  inherited CreateNew(nil);
  FPath := APage; FBrowserShot := AShot; FLocked := True; FShown := 1;
  Half := AWidth;
  SetBounds(0, 0, Half * 2 + 40, 900);
  Caption := 'Browser | LazInk - ' + ExtractFileName(APage);
  KeyPreview := True;
  Color := clWhite;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self; FBar.Align := alTop; FBar.Height := 24;
  FBar.BevelOuter := bvNone; FBar.Color := clBtnFace;
  FCaption := TLabel.Create(Self);
  FCaption.Parent := FBar; FCaption.Align := alClient; FCaption.Layout := tlCenter;

  FShot := TPortableNetworkGraphic.Create;
  if FileExists(AShot) then FShot.LoadFromFile(AShot);
  { the picture as one server-side bitmap: painting then copies only the
    visible slice, instead of pushing all 32000 rows per frame - which is
    what made a fast wheel freeze the window }
  FShotBmp := TBitmap.Create;
  if (FShot.Width > 0) and (FShot.Height > 0) then
    FShotBmp.Assign(FShot);

  FLeft := TPaintBox.Create(Self);
  FLeft.Parent := Self;
  FLeft.SetBounds(0, 24, Half, ClientHeight - 24);
  FLeft.Anchors := [akLeft, akTop, akBottom];
  FLeft.OnPaint := @PaintLeft;

  Html := TStringList.Create;
  try
    Html.LoadFromFile(APage);
    FMarkup := Html.Text;
  finally Html.Free end;

  FPage := TGuidePage.Create(Self);
  FPage.Parent := Self;
  { wider than the browser's half by exactly its scrollbar, so the two text
    columns are the same width.  A headless browser screenshot reserves no
    room for a scrollbar; LazInk does, and without this the right-hand text
    wraps a word early all the way down the page. }
  FPage.SetBounds(Half + 12, 24, Half + FPage.ScrollBar.Width, ClientHeight - 24);
  FPage.Anchors := [akLeft, akTop, akRight, akBottom];
  FPage.LoadFromFile(APage);

  { the other three controls are built the first time they are asked for:
    pouring seventy kilobytes of markup into a label is slow, and a run that
    only ever looks at the page should not wait for it }

  FGuideH := TShape.Create(Self);
  FGuideH.Parent := Self; FGuideH.Visible := False; FGuideH.Enabled := False;
  FGuideH.Brush.Color := clRed; FGuideH.Pen.Color := clRed;
  FGuideVL := TShape.Create(Self);
  FGuideVL.Parent := Self; FGuideVL.Visible := False; FGuideVL.Enabled := False;
  FGuideVL.Brush.Color := clRed; FGuideVL.Pen.Color := clRed;
  FGuideTimer := TTimer.Create(Self);
  FGuideTimer.Interval := 30; FGuideTimer.Enabled := False;
  FGuideTimer.OnTimer := @GuideTick;

  Tell;
end;

destructor TCompareForm.Destroy;
begin
  FShotBmp.Free;
  FShot.Free;
  inherited Destroy;
end;

procedure TCompareForm.Tell;
const Names: array[1..4] of string = ('TInkPage', 'TInkMemo', 'TInkListBox', 'TInkLabel');
var Drift: Integer; Sign: string;
begin
  { both heights, so a page that drifts says by how much }
  Drift := FPage.ContentHeight - FShot.Height;
  if Drift >= 0 then Sign := '+' else Sign := '-';
  FCaption.Caption := Format('  browser %d  |  %s %d  (%s%d)   -   y=%d   ' +
    'wheel/keys scroll, S snapshot, G crosshair, 1-4 control, L %s, Q quit',
    [FShot.Height, Names[FShown], FPage.ContentHeight, Sign, Abs(Drift), FTop,
     BoolToStr(FLocked, 'unlock', 'lock')]);
end;

procedure TCompareForm.DoShow;
begin
  inherited DoShow;
  { the page has no height until it has been laid out, and it lays out when
    it paints: make it paint, then ask, or the caption says nought }
  Application.ProcessMessages;
  FPage.Repaint;
  Application.ProcessMessages;
  Tell;
end;

procedure TCompareForm.PaintLeft(Sender: TObject);
var R: TRect;
begin
  FLeft.Canvas.Brush.Color := clWhite;
  FLeft.Canvas.Brush.Style := bsSolid;
  FLeft.Canvas.FillRect(0, 0, FLeft.Width, FLeft.Height);
  if (FShot.Width = 0) or (FShot.Height = 0) then
  begin
    FLeft.Canvas.TextOut(8, 8, 'no browser picture: run tools/browser_shot.sh first');
    Exit;
  end;
  { the browser's picture, moved up by however far the pair is scrolled -
    only the rows on screen, never the whole strip }
  R := Rect(0, FTop, FShot.Width, Min(FShot.Height, FTop + FLeft.Height));
  if R.Bottom > R.Top then
    FLeft.Canvas.CopyRect(Rect(0, 0, R.Right, R.Bottom - R.Top),
      FShotBmp.Canvas, R);
end;

procedure TCompareForm.ScrollBoth(ADelta: Integer);
var Limit: Integer;
begin
  Limit := FShot.Height;
  if FPage.ContentHeight > Limit then Limit := FPage.ContentHeight;
  Dec(Limit, FLeft.Height);
  if Limit < 0 then Limit := 0;
  FTop := FTop + ADelta;
  if FTop < 0 then FTop := 0;
  if FTop > Limit then FTop := Limit;
  if FLocked then
  begin
    FPage.ScrollTo(FTop);
    if FMemo <> nil then FMemo.ScrollTo(FTop);
  end;
  FLeft.Invalidate;
  Tell;
end;

procedure TCompareForm.ShowWhich(N: Integer);
var Where: TRect;
begin
  Where := Rect(FPage.Left, FPage.Top, FPage.Left + FPage.Width,
    FPage.Top + FPage.Height);
  { the same markup in the other controls, so the one renderer can be seen
    doing its work in each of them - made here, not at startup }
  if (N = 2) and (FMemo = nil) then
  begin
    FMemo := TGuideMemo.Create(Self);
    FMemo.Parent := Self; FMemo.BoundsRect := Where;
    FMemo.Anchors := FPage.Anchors; FMemo.WordWrap := True;
    FMemo.Lines.Text := FMarkup;
  end;
  if (N = 3) and (FList = nil) then
  begin
    FList := TInkListBox.Create(Self);
    FList.Parent := Self; FList.BoundsRect := Where;
    FList.Anchors := FPage.Anchors;
    FList.Items.Text := FMarkup;
  end;
  if (N = 4) and (FLabel = nil) then
  begin
    FLabel := TInkLabel.Create(Self);
    FLabel.Parent := Self; FLabel.BoundsRect := Where;
    FLabel.Anchors := FPage.Anchors; FLabel.WordWrap := True;
    FLabel.Caption := FMarkup;
  end;
  FShown := N;
  FPage.Visible := N = 1;
  if FMemo <> nil then FMemo.Visible := N = 2;
  if FList <> nil then FList.Visible := N = 3;
  if FLabel <> nil then FLabel.Visible := N = 4;
  Tell;
end;

procedure TCompareForm.Snap;
var Shot: TBitmap; PNG: TPortableNetworkGraphic; Target: string;
begin
  Inc(FSnaps);
  Target := ChangeFileExt(FPath, '') + Format('-snap-%.3d.png', [FSnaps]);
  Shot := TBitmap.Create;
  PNG := TPortableNetworkGraphic.Create;
  try
    Shot.SetSize(ClientWidth, ClientHeight);
    { the window as it stands: the browser's half painted from the picture,
      LazInk's half painted by the control itself }
    PaintTo(Shot.Canvas, 0, 0);
    PNG.Assign(Shot);
    PNG.SaveToFile(Target);
    FCaption.Caption := '  wrote ' + Target;
    WriteLn('snapshot: ', Target, '  (scrolled to y=', FTop, ')');
    Flush(Output);
  finally PNG.Free; Shot.Free end;
end;

procedure TCompareForm.GuideTick(Sender: TObject);
var P: TPoint; Half, LX, Y: Integer; R: TControl;
begin
  P := ScreenToClient(Mouse.CursorPos);
  Half := FLeft.Width;
  { the same offset from each half's left edge, whichever half the mouse
    is in }
  if P.X >= Half + 12 then LX := P.X - (Half + 12) else LX := P.X;
  LX := EnsureRange(LX, 0, Half - 1);
  Y := EnsureRange(P.Y, FBar.Height, ClientHeight - 2);
  if (Y = FGuideY) and (LX = FGuideLX) then Exit;
  FGuideY := Y; FGuideLX := LX;
  { the left half is a paint box, so shapes lie over it }
  FGuideH.SetBounds(0, Y, Half, 2);
  FGuideVL.SetBounds(LX, FBar.Height, 2, ClientHeight - FBar.Height);
  FGuideH.BringToFront; FGuideVL.BringToFront;
  { the right half paints its own cross, over its own rendering }
  R := nil;
  case FShown of
    1: R := FPage;
    2: R := FMemo;
  end;
  if R <> nil then R.Invalidate;
end;

procedure TCompareForm.PaintGuide(ACanvas: TCanvas; AControl: TControl);
var Y: Integer;
begin
  if not FGuideOn then Exit;
  Y := FGuideY - AControl.Top;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := clRed;
  if (Y >= 0) and (Y < AControl.Height) then
    ACanvas.FillRect(Rect(0, Y, AControl.Width, Y + 2));
  if FGuideLX < AControl.Width then
    ACanvas.FillRect(Rect(FGuideLX, 0, FGuideLX + 2, AControl.Height));
end;

procedure TGuidePage.Paint;
begin
  inherited Paint;
  TCompareForm(Owner).PaintGuide(Canvas, Self);
end;

procedure TGuideMemo.Paint;
begin
  inherited Paint;
  TCompareForm(Owner).PaintGuide(Canvas, Self);
end;

procedure TCompareForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN: ScrollBoth(40);
    VK_UP: ScrollBoth(-40);
    VK_NEXT: ScrollBoth(FLeft.Height - 40);
    VK_PRIOR: ScrollBoth(-(FLeft.Height - 40));
    VK_HOME: ScrollBoth(-MaxInt div 4);
    VK_END: ScrollBoth(MaxInt div 4);
    VK_F5: Snap;
    VK_ESCAPE: Close;
  else
    case Char(Key) of
      'S': Snap;
      'G':
        begin
          FGuideOn := not FGuideOn;
          FGuideH.Visible := FGuideOn; FGuideVL.Visible := FGuideOn;
          FGuideTimer.Enabled := FGuideOn;
          FGuideY := -1; FGuideLX := -1;
          if FGuideOn then GuideTick(nil) else FPage.Invalidate;
          if (FMemo <> nil) and not FGuideOn then FMemo.Invalidate;
          Tell;
        end;
      'L': begin FLocked := not FLocked; Tell end;
      'Q': Close;
      '1': ShowWhich(1);
      '2': ShowWhich(2);
      '3': ShowWhich(3);
      '4': ShowWhich(4);
    end;
  end;
  Key := 0;
  inherited KeyDown(Key, Shift);
end;

function TCompareForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  ScrollBoth(InkWheelPixels(WheelDelta, 60, FWheelRest));
  Result := True;
end;

var
  Form: TCompareForm;
  PagePath, ShotPath: string;
  Width: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: sidebyside page.html [width]');
    Halt(1);
  end;
  PagePath := ExpandFileName(ParamStr(1));
  Width := StrToIntDef(ParamStr(2), 700);
  ShotPath := ChangeFileExt(PagePath, '') + '-browser.png';
  if not FileExists(ShotPath) then
    WriteLn('no ', ShotPath, ' - run: tools/browser_shot.sh ', PagePath, ' ',
      ShotPath, ' ', Width, ' 4000');
  Application.Initialize;
  Form := TCompareForm.CreateFor(PagePath, ShotPath, Width);
  Form.Show;
  Application.Run;
end.
