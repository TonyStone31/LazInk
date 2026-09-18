{ LazInk demo - a tour of the package, a tab for each control.

  Documents opens on tour.md, a Markdown page about LazInk shown by
  TInkPage, which links on to the README.  Markdown editor is the source
  and its live preview side by side, and opens the README too.  Then the
  WYSIWYG editor, the labels and edit boxes, the memo, the list box the
  package grew out of, and the credits.

  Everything here is built at design time. Open main.lfm in the Lazarus form
  designer and every control, panel and event handler is there to be pushed
  around - nothing is conjured up in code at run time, because a demo you
  cannot open and poke at is not much of a demo.

  The Documents and Markdown tabs open files, and the Markdown tab saves
  them; the rest is about what the controls can do, not about being an
  application you would ship.

  lazinkdemo FILE opens FILE on the Documents tab.
  lazinkdemo --screenshots DIR saves a picture of every tab and quits.
}
unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Buttons, ImgList, LCLIntf, LCLType,
  InkLabel, InkEdit, InkMemo, InkListBox, InkRichEdit, InkDraw, InkMarkdown, InkPage;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    { header }
    pnlHeader: TPanel;
    lblTitle: TInkLabel;
    lblTagline: TInkLabel;
    pcMain: TPageControl;

    { ---- tab: WYSIWYG editor ---- }
    tabEditor: TTabSheet;
    pnlTools: TPanel;
    btnBold: TSpeedButton;
    btnItalic: TSpeedButton;
    btnUnder: TSpeedButton;
    btnStrike: TSpeedButton;
    btnSup: TSpeedButton;
    btnSub: TSpeedButton;
    btnColor: TSpeedButton;
    btnFill: TSpeedButton;
    cbSize: TComboBox;
    cbFace: TComboBox;
    btnAlignL: TSpeedButton;
    btnAlignC: TSpeedButton;
    btnAlignR: TSpeedButton;
    btnLink: TSpeedButton;
    btnClearFmt: TSpeedButton;
    btnUndo: TSpeedButton;
    btnRedo: TSpeedButton;
    pnlEditArea: TPanel;
    reMain: TInkRichEdit;
    splEditor: TSplitter;
    pnlSource: TPanel;
    pnlSourceHdr: TPanel;
    lblSourceHdr: TInkLabel;
    btnApplySource: TButton;
    memSource: TMemo;
    pnlEditStatus: TPanel;
    lblEditStatus: TInkLabel;

    { ---- tab: list box ---- }
    tabListBox: TTabSheet;
    lstLog: TInkListBox;
    pnlListSide: TPanel;
    lblListHelp: TInkLabel;
    lblMarkupHint: TInkLabel;
    edtMarkup: TInkEdit;
    btnAddItem: TButton;
    btnFromEditor: TButton;
    btnClearList: TButton;
    btnStartLog: TButton;
    btnStopLog: TButton;
    chkRawEdit: TCheckBox;
    chkStripes: TCheckBox;
    lblListStatus: TInkLabel;
    lblListCopy: TInkLabel;
    lblEditMode: TInkLabel;
    cbEditMode: TComboBox;
    lblEditModeHint: TInkLabel;
    tmrLog: TTimer;

    { ---- tab: label + edit ---- }
    tabLabelEdit: TTabSheet;
    lblSection1: TInkLabel;
    lblSection2: TInkLabel;
    lblWrapHdr: TInkLabel;
    lblDemo1: TInkLabel;
    lblDemo2: TInkLabel;
    lblDemo3: TInkLabel;
    lblDemo4: TInkLabel;
    lblWrapDemo: TInkLabel;
    lblEditHdr: TInkLabel;
    edtPassword: TInkEdit;
    lblStrength: TInkLabel;
    rgCharMode: TRadioGroup;
    lblSection3: TInkLabel;
    lblLiveHint: TInkLabel;
    edtLive: TInkEdit;
    chkLiveMarkdown: TCheckBox;
    lblLive: TInkLabel;
    lblSection4: TInkLabel;
    lblMdDemo: TInkLabel;
    lblLabelCopy: TInkLabel;

    { ---- tab: memo ---- }
    tabMemo: TTabSheet;
    memCheat: TInkMemo;
    pnlMemoSide: TPanel;
    chkMemoWrap: TCheckBox;
    lblScale: TInkLabel;
    tbScale: TTrackBar;
    lblMemoHelp: TInkLabel;
    lblAppendHdr: TInkLabel;
    edtAppend: TInkEdit;
    btnAppend, btnMemoClear: TButton;

    { ---- tab: documents ---- }
    tabDocuments: TTabSheet;
    pnlDocTools: TPanel;
    btnDocOpen, btnDocBack, btnDocForward, btnDocFind: TButton;
    cbDocTheme: TComboBox;
    lblDocHint: TInkLabel;
    pageDoc: TInkPage;
    dlgDocOpen: TOpenDialog;

    { ---- tab: Markdown editor ---- }
    tabMarkdown: TTabSheet;
    pnlMdTools: TPanel;
    btnMdOpen, btnMdSave, btnMdSaveAs: TButton;
    chkMdRawHTML: TCheckBox;
    lblMdFile: TInkLabel;
    memMarkdown: TMemo;
    splMarkdown: TSplitter;
    pageMdPreview: TInkPage;
    tmrMarkdown: TTimer;
    dlgMdOpen: TOpenDialog;
    dlgMdSave: TSaveDialog;

    { ---- tab: credits ---- }
    tabCredits: TTabSheet;
    memCredits: TInkMemo;

    dlgColor: TColorDialog;
    { status icons for <img src="n"> in the log listbox }
    ilStatus: TImageList;

    procedure FormCreate(Sender: TObject);
    { documents }
    procedure DocOpen(Sender: TObject);
    procedure DocBack(Sender: TObject);
    procedure DocForward(Sender: TObject);
    procedure DocFind(Sender: TObject);
    procedure DocNavigate(Sender: TObject);
    procedure DocThemeChange(Sender: TObject);
    procedure DocLinkClick(Sender: TObject; const URL: string);
    { Markdown editor }
    procedure MdOpen(Sender: TObject);
    procedure MdSave(Sender: TObject);
    procedure MdSaveAs(Sender: TObject);
    procedure MdRawHTMLChange(Sender: TObject);
    procedure MdSourceChange(Sender: TObject);
    procedure MdTimer(Sender: TObject);
    { editor }
    procedure reMainChange(Sender: TObject);
    procedure reMainSelectionChange(Sender: TObject);
    procedure reMainLinkClick(Sender: TObject; const LinkName: string);
    procedure btnStyleClick(Sender: TObject);
    procedure btnScriptClick(Sender: TObject);
    procedure btnColorClick(Sender: TObject);
    procedure btnFillClick(Sender: TObject);
    procedure cbSizeChange(Sender: TObject);
    procedure cbFaceChange(Sender: TObject);
    procedure btnAlignClick(Sender: TObject);
    procedure btnLinkClick(Sender: TObject);
    procedure btnClearFmtClick(Sender: TObject);
    procedure btnUndoClick(Sender: TObject);
    procedure btnRedoClick(Sender: TObject);
    procedure btnApplySourceClick(Sender: TObject);
    { list box }
    procedure edtMarkupChange(Sender: TObject);
    procedure edtMarkupGetCharAttrs(Sender: TObject; AIndex: Integer;
      const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
    procedure btnAddItemClick(Sender: TObject);
    procedure btnFromEditorClick(Sender: TObject);
    procedure btnClearListClick(Sender: TObject);
    procedure btnStartLogClick(Sender: TObject);
    procedure btnStopLogClick(Sender: TObject);
    procedure chkRawEditChange(Sender: TObject);
    procedure chkStripesChange(Sender: TObject);
    procedure cbEditModeChange(Sender: TObject);
    procedure lstLogItemEdited(Sender: TObject; Index: Integer;
      const OldText, NewText: string; var Accept: Boolean);
    procedure lstLogLinkClick(Sender: TObject; Index: Integer;
      const LinkName: string);
    procedure tmrLogTimer(Sender: TObject);
    { label + edit }
    procedure edtPasswordChange(Sender: TObject);
    procedure edtPasswordGetCharAttrs(Sender: TObject; AIndex: Integer;
      const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
    procedure rgCharModeClick(Sender: TObject);
    procedure LiveChange(Sender: TObject);
    procedure LiveMarkdownChange(Sender: TObject);
    procedure lblLinkClick(Sender: TObject; const LinkName: string);
    { memo }
    procedure chkMemoWrapChange(Sender: TObject);
    procedure tbScaleChange(Sender: TObject);
    procedure memLinkClick(Sender: TObject; LineIndex: Integer;
      const LinkName: string);
    procedure edtAppendChange(Sender: TObject);
    procedure edtAppendKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnAppendClick(Sender: TObject);
    procedure btnMemoClearClick(Sender: TObject);
  private
    FSyncing: Boolean;
    { one entry per character of edtMarkup: 0 plain, 1 tag, 2 attribute value.
      Worked out once when the text changes rather than per character, because
      OnGetCharAttrs is handed a character with no idea what surrounds it. }
    FTagMask, FLiveMask, FAppendMask: TBytes;
    FMdFile: string;
    procedure UpdateSource;
    function TagMask(const S: string): TBytes;
    function DemoFile(const AName: string): string;
    procedure OpenDocument(const AFileName: string);
    procedure LoadMarkdownFile(const AFileName: string);
    procedure ShowMdFile;
    procedure UpdateToolbar;
    procedure SetStatus(const AMarkup: string);
  public
    { every tab as a PNG in ADir, named after the tab - how the README's
      pictures are made: lazinkdemo --screenshots images }
    procedure SaveScreenshots(const ADir: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

uses
  LazUTF8, URIParser;

const
  FORUM_URL = 'https://forum.lazarus.freepascal.org/index.php/topic,55971.0.html';

{ ------------------------------------------------------------------ startup }

procedure TfrmMain.SaveScreenshots(const ADir: string);
var
  I: Integer;
  Shot: TBitmap;
  Png: TPortableNetworkGraphic;
  TabName: string;
  DC: HDC;
begin
  ForceDirectories(ADir);
  Shot := TBitmap.Create;
  Png := TPortableNetworkGraphic.Create;
  try
    for I := 0 to pcMain.PageCount - 1 do
    begin
      pcMain.ActivePageIndex := I;
      Application.ProcessMessages;
      Sleep(150);
      Application.ProcessMessages;
      { the window as it is on screen, which draws native widgets properly;
        where that cannot be had, the form paints itself }
      Shot.SetSize(ClientWidth, ClientHeight);
      DC := GetDC(Handle);
      try
        Shot.LoadFromDevice(DC);
      finally
        ReleaseDC(Handle, DC);
      end;
      if (Shot.Width <> ClientWidth) or (Shot.Height <> ClientHeight) then
      begin
        Shot.SetSize(ClientWidth, ClientHeight);
        PaintTo(Shot.Canvas, 0, 0);
      end;
      Png.Assign(Shot);
      TabName := LowerCase(pcMain.Pages[I].Name);
      if Copy(TabName, 1, 3) = 'tab' then Delete(TabName, 1, 3);
      Png.SaveToFile(IncludeTrailingPathDelimiter(ADir) + 'demo-' + TabName + '.png');
    end;
  finally
    Png.Free;
    Shot.Free;
  end;
end;


{ tour.md and the README sit beside the program or a folder up from it, as
  they do in the source tree; the working folder is tried last }
function TfrmMain.DemoFile(const AName: string): string;
var
  Dir, Candidate: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for Candidate in [Dir + AName, Dir + '..' + PathDelim + AName,
    Dir + 'demo' + PathDelim + AName, AName] do
    if FileExists(Candidate) then Exit(ExpandFileName(Candidate));
  Result := '';
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  S: string;
begin
  Randomize;
  memMarkdown.Font.Name := InkMonoFace;
  if (ParamCount > 0) and (ParamStr(1) <> '--screenshots') then
    OpenDocument(ParamStr(1))
  else
  begin
    S := DemoFile('tour.md');
    if S <> '' then OpenDocument(S)
    else
      pageDoc.LoadMarkdown('# LazInk' + LineEnding + LineEnding +
        '`tour.md` was not found next to the program. **Open...** shows ' +
        'any HTML or Markdown page.');
  end;
  S := DemoFile('README.md');
  if S <> '' then LoadMarkdownFile(S)
  else
  begin
    memMarkdown.Text := '# A heading' + LineEnding + LineEnding +
      'Type **Markdown** on the left and watch it on the right.' + LineEnding;
    ShowMdFile;
  end;
  LiveChange(nil);
  edtAppendChange(nil);
  chkStripesChange(chkStripes);
  cbSize.ItemIndex := 0;
  cbFace.ItemIndex := 0;
  UpdateSource;
  UpdateToolbar;
  edtMarkupChange(edtMarkup);
  edtPasswordChange(edtPassword);
  SetStatus('Select some text and press <b>B</b>, or just start typing.');
end;

{ -------------------------------------------------------------- documents }

procedure TfrmMain.OpenDocument(const AFileName: string);
begin
  try
    pageDoc.LoadFromFile(AFileName);
  except
    on E: Exception do
      pageDoc.LoadMarkdown('# Could not open that' + LineEnding + LineEnding +
        '`' + AFileName + '`' + LineEnding + LineEnding + E.Message);
  end;
end;

procedure TfrmMain.DocOpen(Sender: TObject);
begin
  if dlgDocOpen.Execute then OpenDocument(dlgDocOpen.FileName);
end;

procedure TfrmMain.DocBack(Sender: TObject);
begin
  pageDoc.Back;
end;

procedure TfrmMain.DocForward(Sender: TObject);
begin
  pageDoc.Forward;
end;

procedure TfrmMain.DocFind(Sender: TObject);
begin
  pageDoc.ShowFindBar;
end;

{ the buttons follow the page's history, whether it moved by a button, a
  link, the mouse's own back and forward buttons or Alt+arrow }
procedure TfrmMain.DocNavigate(Sender: TObject);
begin
  btnDocBack.Enabled := pageDoc.CanGoBack;
  btnDocForward.Enabled := pageDoc.CanGoForward;
  if pageDoc.DocumentTitle <> '' then
    tabDocuments.Caption := 'Documents - ' + pageDoc.DocumentTitle
  else
    tabDocuments.Caption := 'Documents';
end;

{ StyleSheet dresses a page from outside: here, the program's own themes.
  A page with a stylesheet of its own keeps its rules where both speak. }
procedure TfrmMain.DocThemeChange(Sender: TObject);
begin
  case cbDocTheme.ItemIndex of
    1: pageDoc.StyleSheet.Text :=
         'body { background: #1e2127; color: #c8ccd4 } ' +
         'h1, h2 { color: #61afef } h3 { color: #e5c07b } a { color: #56b6c2 } ' +
         'code, pre { background: #2c313a } blockquote { color: #8a9099 } ' +
         'html { scrollbar-color: #61afef #1e2127; scrollbar-width: thin }';
    2: pageDoc.StyleSheet.Text :=
         'body { background: #f4ecd8; color: #433422 } ' +
         'h1, h2, h3 { color: #7a4a1c } a { color: #8b3a1a } ' +
         'code, pre { background: #e8dcc0 } ' +
         'html { scrollbar-color: #b89b72 #f4ecd8 }';
  else
    pageDoc.StyleSheet.Clear;
  end;
end;

{ web addresses go to the browser; everything else stays in the page it
  was clicked in }
procedure TfrmMain.DocLinkClick(Sender: TObject; const URL: string);
var
  Page: TInkPage;
begin
  if (Pos('http://', URL) = 1) or (Pos('https://', URL) = 1) or
    (Pos('mailto:', URL) = 1) then
  begin
    OpenURL(URL);
    Exit;
  end;
  Page := Sender as TInkPage;
  if Page = pageMdPreview then
  begin
    { the preview is the editor's; a link to another page opens it in
      Documents, an anchor scrolls the preview }
    if Pos('#', URL) = 1 then Page.JumpToAnchor(Copy(URL, 2, MaxInt))
    else
    begin
      pcMain.ActivePage := tabDocuments;
      try pageDoc.LoadFromURL(URL) except on E: Exception do ShowMessage(E.Message) end;
    end;
    Exit;
  end;
  try
    Page.LoadFromURL(URL);
  except
    on E: Exception do ShowMessage(E.Message);
  end;
end;

{ -------------------------------------------------------- Markdown editor }

procedure TfrmMain.LoadMarkdownFile(const AFileName: string);
begin
  memMarkdown.Lines.LoadFromFile(AFileName);
  FMdFile := AFileName;
  memMarkdown.Modified := False;
  ShowMdFile;
  MdTimer(nil);
end;

procedure TfrmMain.ShowMdFile;
var
  FileName: string;
begin
  if FMdFile = '' then FileName := 'untitled' else FileName := ExtractFileName(FMdFile);
  if memMarkdown.Modified then
    lblMdFile.Caption := '<b>' + HTMLEscape(FileName) + '</b> <font color="#C0392B">(changed)</font>'
  else
    lblMdFile.Caption := '<b>' + HTMLEscape(FileName) + '</b>';
end;

procedure TfrmMain.MdOpen(Sender: TObject);
begin
  if dlgMdOpen.Execute then LoadMarkdownFile(dlgMdOpen.FileName);
end;

procedure TfrmMain.MdSave(Sender: TObject);
begin
  if FMdFile = '' then
  begin
    MdSaveAs(Sender);
    Exit;
  end;
  memMarkdown.Lines.SaveToFile(FMdFile);
  memMarkdown.Modified := False;
  ShowMdFile;
end;

procedure TfrmMain.MdSaveAs(Sender: TObject);
begin
  if FMdFile <> '' then dlgMdSave.FileName := FMdFile;
  if not dlgMdSave.Execute then Exit;
  FMdFile := dlgMdSave.FileName;
  MdSave(Sender);
end;

procedure TfrmMain.MdRawHTMLChange(Sender: TObject);
begin
  pageMdPreview.MarkdownRawHTML := chkMdRawHTML.Checked;
end;

{ the preview follows the typing, a moment after it stops }
procedure TfrmMain.MdSourceChange(Sender: TObject);
begin
  tmrMarkdown.Enabled := False;
  tmrMarkdown.Enabled := True;
  ShowMdFile;
end;

procedure TfrmMain.MdTimer(Sender: TObject);
var
  Y: Integer;
  Base: string;
begin
  tmrMarkdown.Enabled := False;
  Y := pageMdPreview.ScrollY;
  { relative images and links are found beside the file }
  if FMdFile <> '' then Base := FilenameToURI(FMdFile) else Base := '';
  pageMdPreview.LoadMarkdown(memMarkdown.Text, Base);
  pageMdPreview.ScrollTo(Y);
end;

{ ----------------------------------------------------------- WYSIWYG editor }

{ The editor is the document; the memo on the right is a view of the markup it
  would be saved as. It follows every change - unless the user is typing in it,
  in which case overwriting what they are halfway through writing would be
  rude. Their edits go back the other way through Apply. }
procedure TfrmMain.UpdateSource;
begin
  if FSyncing or memSource.Focused then Exit;
  FSyncing := True;
  try
    memSource.Lines.Assign(reMain.Markup);
  finally
    FSyncing := False;
  end;
end;

procedure TfrmMain.reMainChange(Sender: TObject);
begin
  UpdateSource;
  btnUndo.Enabled := reMain.CanUndo;
  btnRedo.Enabled := reMain.CanRedo;
end;

{ The toolbar shows the formatting of whatever is selected, so that pressing B
  on already-bold text un-bolds it and the button says so beforehand. }
procedure TfrmMain.UpdateToolbar;
var
  St: TFontStyles;
  Sz: Integer;
  Fc: string;
  i: Integer;
begin
  St := reMain.SelStyle;
  btnBold.Down := fsBold in St;
  btnItalic.Down := fsItalic in St;
  btnUnder.Down := fsUnderline in St;
  btnStrike.Down := fsStrikeOut in St;
  btnSup.Down := reMain.SelScript = isSuperscript;
  btnSub.Down := reMain.SelScript = isSubscript;
  btnAlignL.Down := reMain.SelAlignment = taLeftJustify;
  btnAlignC.Down := reMain.SelAlignment = taCenter;
  btnAlignR.Down := reMain.SelAlignment = taRightJustify;

  Sz := reMain.SelSize;
  if Sz = 0 then
    cbSize.ItemIndex := 0
  else
  begin
    i := cbSize.Items.IndexOf(IntToStr(Sz));
    if i >= 0 then cbSize.ItemIndex := i else cbSize.Text := IntToStr(Sz);
  end;

  Fc := reMain.SelFace;
  if Fc = '' then
    cbFace.ItemIndex := 0
  else
  begin
    i := cbFace.Items.IndexOf(Fc);
    if i >= 0 then cbFace.ItemIndex := i else cbFace.Text := Fc;
  end;

  btnUndo.Enabled := reMain.CanUndo;
  btnRedo.Enabled := reMain.CanRedo;
end;

procedure TfrmMain.reMainSelectionChange(Sender: TObject);
begin
  UpdateToolbar;
  if reMain.SelLength > 0 then
    SetStatus(Format('<b>%d</b> characters selected', [reMain.SelLength]))
  else
    SetStatus('Caret at <b>' + IntToStr(reMain.SelStart) + '</b>. ' +
      'Ctrl+B / Ctrl+I / Ctrl+U, Ctrl+Z to undo.');
end;

procedure TfrmMain.reMainLinkClick(Sender: TObject; const LinkName: string);
begin
  OpenURL(LinkName);
end;

{ All four style buttons share this: the Tag set in the designer says which. }
procedure TfrmMain.btnStyleClick(Sender: TObject);
begin
  case TComponent(Sender).Tag of
    0: reMain.ToggleStyle(fsBold);
    1: reMain.ToggleStyle(fsItalic);
    2: reMain.ToggleStyle(fsUnderline);
    3: reMain.ToggleStyle(fsStrikeOut);
  end;
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnScriptClick(Sender: TObject);
var
  Want: TInkScript;
begin
  if TComponent(Sender).Tag = 0 then Want := isSuperscript else Want := isSubscript;
  if reMain.SelScript = Want then
    reMain.ApplyScript(isNormal)      // pressing it again puts it back down
  else
    reMain.ApplyScript(Want);
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnColorClick(Sender: TObject);
begin
  dlgColor.Color := clRed;
  if dlgColor.Execute then
    reMain.ApplyColor(dlgColor.Color);
  reMain.SetFocus;
end;

procedure TfrmMain.btnFillClick(Sender: TObject);
begin
  dlgColor.Color := clYellow;
  if dlgColor.Execute then
    reMain.ApplyBackColor(dlgColor.Color);
  reMain.SetFocus;
end;

procedure TfrmMain.cbSizeChange(Sender: TObject);
begin
  // the first entry is "default", meaning: follow the control's own font
  if cbSize.ItemIndex <= 0 then
    reMain.ApplySize(0)
  else
    reMain.ApplySize(StrToIntDef(cbSize.Text, 0));
  reMain.SetFocus;
end;

procedure TfrmMain.cbFaceChange(Sender: TObject);
begin
  if cbFace.ItemIndex <= 0 then
    reMain.ApplyFace('')
  else
    reMain.ApplyFace(cbFace.Text);
  reMain.SetFocus;
end;

procedure TfrmMain.btnAlignClick(Sender: TObject);
begin
  case TComponent(Sender).Tag of
    0: reMain.ApplyAlignment(taLeftJustify);
    1: reMain.ApplyAlignment(taCenter);
    2: reMain.ApplyAlignment(taRightJustify);
  end;
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnLinkClick(Sender: TObject);
var
  Href: string;
begin
  if reMain.SelLength = 0 then
  begin
    SetStatus('<font color="#C0392B">Select the text to link first.</font>');
    Exit;
  end;
  Href := 'https://www.lazarus-ide.org/';
  if InputQuery('Link', 'Target for the selected text:', Href) then
    reMain.ApplyLink(Href);
  reMain.SetFocus;
end;

procedure TfrmMain.btnClearFmtClick(Sender: TObject);
begin
  reMain.ClearFormatting;
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnUndoClick(Sender: TObject);
begin
  reMain.Undo;
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnRedoClick(Sender: TObject);
begin
  reMain.Redo;
  reMain.SetFocus;
  UpdateToolbar;
end;

procedure TfrmMain.btnApplySourceClick(Sender: TObject);
begin
  FSyncing := True;
  try
    reMain.Markup := memSource.Lines;
  finally
    FSyncing := False;
  end;
  reMain.SetFocus;
  UpdateToolbar;
  SetStatus('Markup applied to the editor.');
end;

procedure TfrmMain.SetStatus(const AMarkup: string);
begin
  lblEditStatus.Caption := AMarkup;
end;

{ --------------------------------------------------------------- list box  }

{ Color the markup as it is typed. TInkEdit keeps the text plain and asks
  per character how to draw it, so this is syntax highlighting without the
  text ever containing anything but what the user typed. }
function TfrmMain.TagMask(const S: string): TBytes;
var
  i, N: Integer;
  InTag, InQuote: Boolean;
  Ch: string;
begin
  N := UTF8Length(S);
  Result := nil;
  SetLength(Result, N);
  InTag := False;
  InQuote := False;
  for i := 1 to N do
  begin
    Ch := UTF8Copy(S, i, 1);
    if Ch = '<' then InTag := True;
    if InTag and (Ch = '"') then InQuote := not InQuote;
    if InTag then
    begin
      if InQuote or (Ch = '"') then
        Result[i - 1] := 2
      else
        Result[i - 1] := 1;
    end
    else
      Result[i - 1] := 0;
    if Ch = '>' then
    begin
      InTag := False;
      InQuote := False;
    end;
  end;
end;

procedure TfrmMain.edtMarkupChange(Sender: TObject);
begin
  FTagMask := TagMask(edtMarkup.Text);
  edtMarkup.Invalidate;
end;

procedure TfrmMain.edtMarkupGetCharAttrs(Sender: TObject; AIndex: Integer;
  const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
var
  Mask: TBytes;
begin
  { both markup boxes share this; each has its own mask }
  if Sender = edtLive then Mask := FLiveMask
  else if Sender = edtAppend then Mask := FAppendMask
  else Mask := FTagMask;
  if (AIndex < 1) or (AIndex > Length(Mask)) then Exit;
  case Mask[AIndex - 1] of
    1: begin AColor := $00A05A2C; AStyle := [fsBold]; end;   // the tag itself
    2: AColor := $002080108;                                 // quoted value
  else
    AColor := clWindowText;
  end;
end;

procedure TfrmMain.btnAddItemClick(Sender: TObject);
begin
  if Trim(edtMarkup.Text) = '' then Exit;
  lstLog.Items.Add(edtMarkup.Text);
  lstLog.ItemIndex := lstLog.Items.Count - 1;
end;

procedure TfrmMain.btnFromEditorClick(Sender: TObject);
begin
  // the editor's document, flattened to a single line of markup
  lstLog.Items.Add(reMain.AsHTML(' '));
  lstLog.ItemIndex := lstLog.Items.Count - 1;
end;

procedure TfrmMain.btnClearListClick(Sender: TObject);
begin
  lstLog.Items.Clear;
end;

procedure TfrmMain.btnStartLogClick(Sender: TObject);
begin
  tmrLog.Enabled := True;
  btnStartLog.Enabled := False;
  btnStopLog.Enabled := True;
end;

procedure TfrmMain.btnStopLogClick(Sender: TObject);
begin
  tmrLog.Enabled := False;
  btnStartLog.Enabled := True;
  btnStopLog.Enabled := False;
end;

{ The original demo from the forum thread: a fake log that keeps arriving, so
  you can watch formatted items being appended and scrolled. }
{ The original demo from the forum thread: a fake log that keeps arriving, so
  you can watch formatted items being appended and scrolled. Each line leads
  with <img src="n">, which pulls entry n out of the listbox's Images. }
procedure TfrmMain.tmrLogTimer(Sender: TObject);
const
  EVENTS: array[0..4] of string = (
    '<img src="1"> Process <u>%s</u> <font color="#1E8449">started</font>',
    '<img src="0"> Process <u>%s</u> finished',
    '<img src="2"> Process <u>%s</u> <font color="#B7950B">halted</font>',
    '<img src="3"> Process <u>%s</u> <font color="#C0392B"><b>error</b></font>',
    '<img src="4"> Process <u>%s</u> retrying — see <a href="' + FORUM_URL + '">thread</a>'
  );
  NAMES: array[0..5] of string = ('alpha', 'bravo', 'charlie', 'delta',
    'echo', 'foxtrot');
var
  Msg: string;
begin
  Msg := Format(EVENTS[Random(Length(EVENTS))], [NAMES[Random(Length(NAMES))]]);
  // the icon has to come first, then the timestamp, then the event text
  Insert(Format('<font color="#7F8C8D">%s</font> ',
    [FormatDateTime('hh:nn:ss.zzz', Now)]), Msg, Pos('> ', Msg) + 2);
  lstLog.Items.Add(Msg);
  lstLog.TopIndex := lstLog.Items.Count - 1;
  tmrLog.Interval := 250 + Random(900);
end;

procedure TfrmMain.chkRawEditChange(Sender: TObject);
begin
  lstLog.EditRawHTML := chkRawEdit.Checked;
  if chkRawEdit.Checked then
    lblListStatus.Caption :=
      'Click an item: the popup holds its <b>markup</b>, edit and press Enter.'
  else
    lblListStatus.Caption :=
      'Click an item: the popup holds its <b>plain text</b>, tags stripped.';
end;

procedure TfrmMain.chkStripesChange(Sender: TObject);
begin
  if chkStripes.Checked then
    // derived from the listbox's own color rather than hard-coded, so the
    // stripe stays readable whether the theme is light or dark
    lstLog.AlternateColor := HTMLShadeColor(lstLog.Color, 5)
  else
    lstLog.AlternateColor := clNone;
end;

{ the list box's EditMode, in the order the combo box lists them }
procedure TfrmMain.cbEditModeChange(Sender: TObject);
begin
  lstLog.CancelEdit;
  lstLog.EditMode := TInkEditMode(cbEditMode.ItemIndex);
end;

procedure TfrmMain.lstLogItemEdited(Sender: TObject; Index: Integer;
  const OldText, NewText: string; var Accept: Boolean);
begin
  Accept := True;
  lblListStatus.Caption := Format('Item <b>%d</b> changed to: <i>%s</i>',
    [Index, HTMLEscape(NewText)]);
end;

procedure TfrmMain.lstLogLinkClick(Sender: TObject; Index: Integer;
  const LinkName: string);
begin
  OpenURL(LinkName);
end;

{ ----------------------------------------------------------- label + edit  }

procedure TfrmMain.lblLinkClick(Sender: TObject; const LinkName: string);
begin
  OpenURL(LinkName);
end;

procedure TfrmMain.edtPasswordChange(Sender: TObject);
var
  Score: Integer;
  S: string;
  i: Integer;
  HasUp, HasLo, HasDig, HasSym: Boolean;
begin
  S := edtPassword.Text;
  HasUp := False; HasLo := False; HasDig := False; HasSym := False;
  for i := 1 to Length(S) do
    case S[i] of
      'A'..'Z': HasUp := True;
      'a'..'z': HasLo := True;
      '0'..'9': HasDig := True;
    else
      HasSym := True;
    end;
  Score := Ord(HasUp) + Ord(HasLo) + Ord(HasDig) + Ord(HasSym);
  if Length(S) >= 12 then Inc(Score);

  if S = '' then
    lblStrength.Caption := '<font color="#7F8C8D">type something…</font>'
  else if Score <= 2 then
    lblStrength.Caption := '<b><font color="#C0392B">weak</font></b>'
  else if Score = 3 then
    lblStrength.Caption := '<b><font color="#B7950B">fair</font></b>'
  else if Score = 4 then
    lblStrength.Caption := '<b><font color="#1E8449">good</font></b>'
  else
    lblStrength.Caption := '<b><font color="#1E8449">strong</font></b> ✔';
  edtPassword.Invalidate;
end;

{ Two ways of using OnGetCharAttrs, chosen by the radio group. The control
  never sees any markup - it hands over one character at a time and takes back
  a color and a style. }
procedure TfrmMain.edtPasswordGetCharAttrs(Sender: TObject; AIndex: Integer;
  const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
var
  C: Char;
begin
  if AChar = '' then Exit;
  C := AChar[1];
  case rgCharMode.ItemIndex of
    0:  // character classes
      case C of
        '0'..'9': begin AColor := $001E8449; AStyle := [fsBold]; end;
        'A'..'Z': AColor := $00DE862E;
        'a'..'z': AColor := clWindowText;
      else
        begin AColor := $002E57E4; AStyle := [fsBold]; end;
      end;
    1:  // a rainbow, because we can
      case AIndex mod 6 of
        0: AColor := $002E57E4;
        1: AColor := $00108020;
        2: AColor := $00E48A2E;
        3: AColor := $00A05AC0;
        4: AColor := $001EA4C0;
      else
        AColor := $00C03080;
      end;
  else  // every other character emphasized
    if Odd(AIndex) then
      AStyle := [fsBold]
    else
      begin AStyle := [fsItalic]; AColor := $007F8C8D; end;
  end;
end;

procedure TfrmMain.rgCharModeClick(Sender: TObject);
begin
  edtPassword.Invalidate;
end;

procedure TfrmMain.LiveChange(Sender: TObject);
begin
  FLiveMask := TagMask(edtLive.Text);
  edtLive.Invalidate;
  lblLive.Caption := edtLive.Text;
end;

procedure TfrmMain.LiveMarkdownChange(Sender: TObject);
begin
  if chkLiveMarkdown.Checked then
  begin
    lblLive.TextFormat := itfMarkdown;
    if Pos('<', edtLive.Text) > 0 then
      edtLive.Text := 'Say **hello** in *Markdown*, with `code` and a [link](https://www.lazarus-ide.org/)';
  end
  else
    lblLive.TextFormat := itfHTML;
  LiveChange(nil);
end;

{ ------------------------------------------------------------------- memo  }

procedure TfrmMain.chkMemoWrapChange(Sender: TObject);
begin
  memCheat.WordWrap := chkMemoWrap.Checked;
end;

procedure TfrmMain.tbScaleChange(Sender: TObject);
begin
  memCheat.HTMLScale := tbScale.Position;
  lblScale.Caption := Format('Scale: <b>%d%%</b>', [tbScale.Position]);
end;

procedure TfrmMain.memLinkClick(Sender: TObject; LineIndex: Integer;
  const LinkName: string);
begin
  OpenURL(LinkName);
end;

{ ---------------------------------------------------------- memo: append }

procedure TfrmMain.edtAppendChange(Sender: TObject);
begin
  FAppendMask := TagMask(edtAppend.Text);
  edtAppend.Invalidate;
end;

procedure TfrmMain.edtAppendKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    btnAppendClick(Sender);
    Key := 0;
  end;
end;

{ a timestamp, then the line as typed; the memo follows it down if the view
  was at the end }
procedure TfrmMain.btnAppendClick(Sender: TObject);
begin
  if Trim(edtAppend.Text) = '' then Exit;
  memCheat.Append(Format('<font color="#7F8C8D">%s</font> %s',
    [FormatDateTime('hh:nn:ss', Now), edtAppend.Text]));
end;

procedure TfrmMain.btnMemoClearClick(Sender: TObject);
begin
  memCheat.Clear;
end;

end.
