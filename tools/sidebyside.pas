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
  Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, LCLType,
  ExtCtrls, StdCtrls, Process, InkPage, InkMemo, InkListBox, InkLabel, InkDraw;

type

  { TCompareForm }

  TCompareForm = class(TForm)
  private
    FShot: TPortableNetworkGraphic;
    FPage: TInkPage;
    FMemo: TInkMemo;
    FList: TInkListBox;
    FLabel: TInkLabel;
    FLeft: TPaintBox;
    FBar: TPanel;
    FCaption: TLabel;
    FPath, FBrowserShot: string;
    FTop: Integer;
    FLocked: Boolean;
    FShown: Integer;
    FSnaps: Integer;
    procedure PaintLeft(Sender: TObject);
    procedure ScrollBoth(ADelta: Integer);
    procedure ShowWhich(N: Integer);
    procedure Snap;
    procedure Tell;
  protected
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
  SetBounds(0, 0, Half * 2 + 12, 900);
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

  FLeft := TPaintBox.Create(Self);
  FLeft.Parent := Self;
  FLeft.SetBounds(0, 24, Half, ClientHeight - 24);
  FLeft.Anchors := [akLeft, akTop, akBottom];
  FLeft.OnPaint := @PaintLeft;

  Html := TStringList.Create;
  try
    Html.LoadFromFile(APage);

    FPage := TInkPage.Create(Self);
    FPage.Parent := Self;
    FPage.SetBounds(Half + 12, 24, Half, ClientHeight - 24);
    FPage.Anchors := [akLeft, akTop, akRight, akBottom];
    FPage.LoadFromFile(APage);

    { the same markup in the other controls, so the one renderer can be seen
      doing its work in each of them }
    FMemo := TInkMemo.Create(Self);
    FMemo.Parent := Self; FMemo.SetBounds(Half + 12, 24, Half, ClientHeight - 24);
    FMemo.Anchors := FPage.Anchors; FMemo.Visible := False;
    FMemo.WordWrap := True;
    FMemo.Lines.Text := Html.Text;

    FList := TInkListBox.Create(Self);
    FList.Parent := Self; FList.SetBounds(Half + 12, 24, Half, ClientHeight - 24);
    FList.Anchors := FPage.Anchors; FList.Visible := False;
    FList.Items.Text := Html.Text;

    FLabel := TInkLabel.Create(Self);
    FLabel.Parent := Self; FLabel.SetBounds(Half + 12, 24, Half, ClientHeight - 24);
    FLabel.Anchors := FPage.Anchors; FLabel.Visible := False;
    FLabel.WordWrap := True;
    FLabel.Caption := Html.Text;
  finally Html.Free end;

  Tell;
end;

destructor TCompareForm.Destroy;
begin
  FShot.Free;
  inherited Destroy;
end;

procedure TCompareForm.Tell;
const Names: array[1..4] of string = ('TInkPage', 'TInkMemo', 'TInkListBox', 'TInkLabel');
begin
  FCaption.Caption := Format('  browser  |  %s   -   scroll with the wheel or the keys,' +
    ' S for a snapshot, 1-4 to change the control, L to %s the sides, Q to quit   (y=%d)',
    [Names[FShown], BoolToStr(FLocked, 'unlock', 'lock'), FTop]);
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
  { the browser's picture, moved up by however far the pair is scrolled }
  R := Rect(0, -FTop, FShot.Width, FShot.Height - FTop);
  FLeft.Canvas.Draw(R.Left, R.Top, FShot);
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
    FMemo.ScrollTo(FTop);
  end;
  FLeft.Invalidate;
  Tell;
end;

procedure TCompareForm.ShowWhich(N: Integer);
begin
  FShown := N;
  FPage.Visible := N = 1;
  FMemo.Visible := N = 2;
  FList.Visible := N = 3;
  FLabel.Visible := N = 4;
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
  ScrollBoth(-WheelDelta div 2);
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
