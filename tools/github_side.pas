{ GitHub's rendering of a Markdown file beside TInkPage and TInkRichEdit,
  for tools/github_side.sh, which makes the picture and numbers the
  headings.

    github_side PICTURE.png FILE.md BASEDIR WIDTH

  SPDX-License-Identifier: 0BSD }
program github_side;

{$mode objfpc}{$H+}

uses
  Interfaces,
  Forms,
  Classes,
  SysUtils,
  Math,
  Controls,
  StdCtrls,
  ExtCtrls,
  Graphics,
  FPImage,
  FPReadPNG,
  FPWritePNG,
  InkPage,
  InkRichEdit;

type

  { TfrmSide }

  TfrmSide = class(TForm)
    pnlTop, pnlGitHub, pnlPage, pnlEdit: TPanel;
    chkTogether: TCheckBox;
    lblFile, lblGitHub, lblPage, lblEdit: TLabel;
    pgGitHub, pgInk: TInkPage;
    reInk: TInkRichEdit;
    tmrSync: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure tmrSyncTimer(Sender: TObject);
  private
    FLast: array[0..2] of integer;
    function Fraction(I: integer): double;
    procedure ScrollFraction(I: integer; F: double);
  end;

  { DocumentHeight is protected; this tool only reads it }
  TEditAccess = class(TInkRichEdit);

var
  frmSide: TfrmSide;

  {$R *.lfm}

{ The browser's picture is as tall as the window it was taken in; the white
  below the page would throw scrolling together off, so it goes. }
  function TrimPicture(const AFile, AOut: string): integer;
  var
    Img, Cut: TFPMemoryImage;
    X, Y, Last: integer;
    White: TFPColor;
  begin
    Img := TFPMemoryImage.Create(0, 0);
    try
      Img.LoadFromFile(AFile);
      White := Img.Colors[Img.Width - 1, Img.Height - 1];
      Last := 0;
      for Y := Img.Height - 1 downto 0 do
      begin
        for X := 0 to Img.Width - 1 do
          if Img.Colors[X, Y] <> White then
          begin
            Last := Y;
            Break;
          end;
        if Last > 0 then Break;
      end;
      Result := Min(Img.Height, Last + 24);
      Cut := TFPMemoryImage.Create(Img.Width, Result);
      try
        for Y := 0 to Result - 1 do
          for X := 0 to Img.Width - 1 do
            Cut.Colors[X, Y] := Img.Colors[X, Y];
        Cut.SaveToFile(AOut);
      finally
        Cut.Free;
      end;
    finally
      Img.Free;
    end;
  end;

  procedure TfrmSide.FormCreate(Sender: TObject);
  var
    L: TStringList;
    W, H: integer;
    Base, Trimmed: string;
  begin
    W := StrToIntDef(ParamStr(4), 620);
    pnlGitHub.Width := W + pgGitHub.ScrollBar.Width;
    pnlPage.Width := pnlGitHub.Width;
    Width := Min(Screen.Width - 20, 3 * pnlGitHub.Width + 10);
    Base := 'file://' + IncludeTrailingPathDelimiter(ParamStr(3));
    Trimmed := ChangeFileExt(ParamStr(1), '-trim.png');
    H := TrimPicture(ParamStr(1), Trimmed);
    pgGitHub.LoadHTML('<html><body style="margin:0;background:#fff"><img src="' + ExtractFileName(Trimmed) + '" width="' + IntToStr(W) +
      '" height="' + IntToStr(H) + '"></body></html>', 'file://' + IncludeTrailingPathDelimiter(ExtractFilePath(Trimmed)));
    L := TStringList.Create;
    try
      L.LoadFromFile(ParamStr(2));
      pgInk.Font.Height := -16;
      reInk.Font.Height := -16;
      pgInk.LoadMarkdown(L.Text, Base);
      reInk.LoadMarkdown(L.Text, Base);
    finally
      L.Free;
    end;
    lblFile.Caption := 'Sections are numbered on all three.  ' + ParamStr(3);
  end;

  { how far down a pane is, 0 to 1 }
  function TfrmSide.Fraction(I: integer): double;
  var
    Y, Room: integer;
  begin
    case I of
      0:
      begin
        Y := pgGitHub.ScrollY;
        Room := pgGitHub.ContentHeight - pgGitHub.ClientHeight;
      end;
      1:
      begin
        Y := pgInk.ScrollY;
        Room := pgInk.ContentHeight - pgInk.ClientHeight;
      end;
      else
      begin
        Y := reInk.ScrollY;
        Room := TEditAccess(reInk).DocumentHeight - reInk.ClientHeight;
      end;
    end;
    if Room <= 0 then
      Result := 0
    else
      Result := Y / Room;
  end;

  procedure TfrmSide.ScrollFraction(I: integer; F: double);
  begin
    case I of
      0: pgGitHub.ScrollTo(Round(F * Max(0, pgGitHub.ContentHeight - pgGitHub.ClientHeight)));
      1: pgInk.ScrollTo(Round(F * Max(0, pgInk.ContentHeight - pgInk.ClientHeight)));
      else
        reInk.ScrollTo(Round(F * Max(0, TEditAccess(reInk).DocumentHeight - reInk.ClientHeight)));
    end;
  end;

{ whichever pane moved since the last tick leads, the others follow at the
  same fraction of the way down }
  procedure TfrmSide.tmrSyncTimer(Sender: TObject);
  var
    I, J: integer;
    Now: array[0..2] of integer;
  begin
    Now[0] := pgGitHub.ScrollY;
    Now[1] := pgInk.ScrollY;
    Now[2] := reInk.ScrollY;
    if chkTogether.Checked then
      for I := 0 to 2 do
        if Now[I] <> FLast[I] then
        begin
          for J := 0 to 2 do
            if J <> I then ScrollFraction(J, Fraction(I));
          Break;
        end;
    FLast[0] := pgGitHub.ScrollY;
    FLast[1] := pgInk.ScrollY;
    FLast[2] := reInk.ScrollY;
  end;

begin
  Application.Initialize;
  Application.CreateForm(TfrmSide, frmSide);
  Application.Run;
end.
