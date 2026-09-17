{ LazInk demo — a WYSIWYG editor for the LazInk markup subset, side by side
  with the markup it produces, plus a tab for each of the other controls.

  Everything here is built at design time. Open main.lfm in the Lazarus form
  designer and every control, panel and event handler is there to be pushed
  around — nothing is conjured up in code at run time, because a demo you
  cannot open and poke at is not much of a demo.

  There are deliberately no File/Open/Save actions: this is about what the
  controls can do, not about being a text editor you would actually ship.
}
unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Buttons, ImgList, LCLIntf, LCLType,
  InkLabel, InkEdit, InkMemo, InkListBox, InkRichEdit, InkHtml, InkMarkdown, InkPage;

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
    tabList: TTabSheet;
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

    { ---- tab: memo ---- }
    tabMemo: TTabSheet;
    memCheat: TInkMemo;
    pnlMemoSide: TPanel;
    chkMemoWrap: TCheckBox;
    lblScale: TInkLabel;
    tbScale: TTrackBar;
    lblMemoHelp: TInkLabel;

    tabHelpPage: TTabSheet;
    helpPage: TInkPage;
    pnlHelpTools: TPanel;
    btnHelpOpen, btnHelpBack, btnHelpForward: TButton;
    dlgHelp: TOpenDialog;
    tabTables: TTabSheet;
    cbTableFormat: TComboBox;
    memTableSource: TMemo;
    tablePreview: TInkMemo;

    { ---- tab: credits ---- }
    tabCredits: TTabSheet;
    memCredits: TInkMemo;

    dlgColor: TColorDialog;
    { status icons for <img src="n"> in the log listbox }
    ilStatus: TImageList;

    procedure FormCreate(Sender: TObject);
    procedure HelpOpen(Sender: TObject);
    procedure HelpBack(Sender: TObject);
    procedure HelpForward(Sender: TObject);
    procedure TableFormatChange(Sender: TObject);
    procedure TableSourceChange(Sender: TObject);
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
    procedure lblLinkClick(Sender: TObject; const LinkName: string);
    { memo }
    procedure chkMemoWrapChange(Sender: TObject);
    procedure tbScaleChange(Sender: TObject);
    procedure memLinkClick(Sender: TObject; LineIndex: Integer;
      const LinkName: string);
  private
    FSyncing: Boolean;
    { one entry per character of edtMarkup: 0 plain, 1 tag, 2 attribute value.
      Worked out once when the text changes rather than per character, because
      OnGetCharAttrs is handed a character with no idea what surrounds it. }
    FTagMask: array of Byte;
    procedure UpdateSource;
    procedure UpdateToolbar;
    procedure SetStatus(const AMarkup: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

uses
  LazUTF8;

const
  FORUM_URL = 'https://forum.lazarus.freepascal.org/index.php/topic,55971.0.html';

{ ------------------------------------------------------------------ startup }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Randomize;
  TableFormatChange(nil);
  if ParamCount > 0 then helpPage.LoadFromFile(ParamStr(1));
  chkStripesChange(chkStripes);
  cbSize.ItemIndex := 0;
  cbFace.ItemIndex := 0;
  UpdateSource;
  UpdateToolbar;
  edtMarkupChange(edtMarkup);
  edtPasswordChange(edtPassword);
  SetStatus('Select some text and press <b>B</b>, or just start typing.');
end;

procedure TfrmMain.HelpOpen(Sender: TObject);
begin
  if dlgHelp.Execute then helpPage.LoadFromFile(dlgHelp.FileName);
end;
procedure TfrmMain.HelpBack(Sender: TObject);
begin helpPage.Back end;
procedure TfrmMain.HelpForward(Sender: TObject);
begin helpPage.Forward end;

procedure TfrmMain.TableFormatChange(Sender: TObject);
begin
  tablePreview.TextFormat := TInkTextFormat(cbTableFormat.ItemIndex);
  if tablePreview.TextFormat = itfMarkdown then
    memTableSource.Text := '# Tables in Markdown' + LineEnding +
      'Edit this source to update the preview.' + LineEnding + LineEnding +
      '| Control | Purpose |' + LineEnding + '| --- | --- |' + LineEnding +
      '| **TInkLabel** | Captions and formatted help |' + LineEnding +
      '| TInkMemo | Scrollable text with [links](https://www.freepascal.org/) |' + LineEnding
  else
    memTableSource.Text := '<b>Tables in HTML</b><br>' + LineEnding +
      '<table><tr><th>Control</th><th>Purpose</th></tr>' + LineEnding +
      '<tr><td><b>TInkLabel</b></td><td>Captions and formatted help</td></tr>' + LineEnding +
      '<tr><td>TInkMemo</td><td>Scrollable text with <a href="https://www.freepascal.org/">links</a></td></tr></table>';
  TableSourceChange(nil);
end;

procedure TfrmMain.TableSourceChange(Sender: TObject);
begin
  tablePreview.LoadDocument(memTableSource.Text);
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

{ Colour the markup as it is typed. TInkEdit keeps the text plain and asks
  per character how to draw it, so this is syntax highlighting without the
  text ever containing anything but what the user typed. }
procedure TfrmMain.edtMarkupChange(Sender: TObject);
var
  S: string;
  i, N: Integer;
  InTag, InQuote: Boolean;
  Ch: string;
begin
  S := edtMarkup.Text;
  N := UTF8Length(S);
  SetLength(FTagMask, N);
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
        FTagMask[i - 1] := 2
      else
        FTagMask[i - 1] := 1;
    end
    else
      FTagMask[i - 1] := 0;
    if Ch = '>' then
    begin
      InTag := False;
      InQuote := False;
    end;
  end;
  edtMarkup.Invalidate;
end;

procedure TfrmMain.edtMarkupGetCharAttrs(Sender: TObject; AIndex: Integer;
  const AChar: string; var AColor: TColor; var AStyle: TFontStyles);
begin
  if (AIndex < 1) or (AIndex > Length(FTagMask)) then Exit;
  case FTagMask[AIndex - 1] of
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
    // derived from the listbox's own colour rather than hard-coded, so the
    // stripe stays readable whether the theme is light or dark
    lstLog.AlternateColor := HTMLShadeColor(lstLog.Color, 5)
  else
    lstLog.AlternateColor := clNone;
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
  a colour and a style. }
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
  else  // every other character emphasised
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

end.
