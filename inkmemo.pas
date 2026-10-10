{ LazInk - lightweight HTML-formatted text controls for Lazarus.

  TInkMemo: a scrollable multi-line viewer for formatted text - a log, a chat
  transcript, a page of help.  Each line of Lines is one paragraph of inline
  markup (<b> <i> <u> <s> <font ...> <sup> <sub> <br> <hr> <center> <right>
  <a href=> <img src="n"> ...), or of Markdown with TextFormat itfMarkdown.
  Lines can differ in height, and with WordWrap they re-flow to the width.

  It is drawn by the same engine as TInkPage, so its text is selected the
  way a browser's is - drag, double-click a word, triple-click a line,
  Ctrl+A and Ctrl+C - and it has the copy menu, find (Ctrl+F) and finger
  scrolling.  Unlike the page, it reads no stylesheet: its look is its
  Font, Color, Borders and LineSpacing, and a message added whole
  (AppendBlock) is laid out as a browser lays out a page with no CSS of
  its own.

  It is a viewer, not an editor: text changes through Lines, Append and
  LoadDocument.  Append keeps the view on the newest line when it was
  already showing the end, and leaves it alone when the reader has scrolled
  back.

  When to use it, and when not:
    - the program adds lines as things happen (a log, a chat, an event
      history)                                          -> TInkMemo
    - an author wrote a whole document (help, release notes, a README) with
      headings, lists, code and pictures               -> TInkPage
    - the user writes and formats the text             -> TInkRichEdit
    - each line is an item the user picks or renames   -> TInkListBox
  If you would call Append, it is a memo; if you would call LoadFromFile,
  it is a page.

  SPDX-License-Identifier: 0BSD; see LICENSE.
}
unit InkMemo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, LCLType, LCLIntf,
  Types, InkDraw, InkMarkdown, InkPage, InkCopyMenu, InkDOM;

type
  TInkMemoLinkEvent = procedure(Sender: TObject; LineIndex: Integer;
    const LinkName: string) of object;

  { what one entry of the memo is: its line of Lines holds the source }
  TInkMemoEntry = record
    { itfHTML/itfMarkdown as an override; UseFormat False follows the
      memo's own TextFormat }
    Format: TInkTextFormat;
    UseFormat: Boolean;
    { shown exactly as written, markup and all }
    Plain: Boolean;
    { a whole message laid out like a fragment of a page - paragraphs,
      lists, quotes, fenced code - instead of one line of inline markup }
    Block: Boolean;
    { a band behind the entry, and an inset, so a question can be set
      apart from an answer }
    Color: TColor;
    Indent: Integer;
  end;

  { TInkMemo }

  TInkMemo = class(TInkCustomPage)
  private
    FLines: TStringList;
    FEntries: array of TInkMemoEntry;
    FHTMLScale: Integer;
    FSuperSubScriptRatio: Double;
    FShowSelection: Boolean;
    FWordWrap: Boolean;
    FLineSpacing: Integer;
    FBorders: TInkBorders;
    FNoBorders: TInkBorders;
    FImages: TCustomImageList;
    FLinkStyle: TInkLinkStyle;
    FLinkHoverStyle: TInkLinkStyle;
    FAutoOpenLink: Boolean;
    FHoverLine: Integer;     // -1 when the mouse is not over a link
    FHoverBlock: Integer;    // the block it is in
    FHoverIndex: Integer;    // ordinal of that link within its block
    FHoverHref: string;
    FHoverLinkText: string;
    FOnLinkClick: TInkMemoLinkEvent;
    FOnLinkEnter: TInkMemoLinkEvent;
    FOnLinkLeave: TInkMemoLinkEvent;
    FOnLinkRightClick: TInkMemoLinkEvent;
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    procedure LinesChanged(Sender: TObject);
    procedure SetHTMLScale(AValue: Integer);
    procedure SetSuperSubScriptRatio(AValue: Double);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetLineSpacing(AValue: Integer);
    procedure SetBorders(AValue: TInkBorders);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetLinkStyle(AValue: TInkLinkStyle);
    procedure SetLinkHoverStyle(AValue: TInkLinkStyle);
    procedure SubPropChanged(Sender: TObject);
    function MakeLine(AIndex: Integer): TInkPageBlock;
    function AtEnd: Boolean;
    function DefaultEntry: TInkMemoEntry;
    function EntryFormat(const E: TInkMemoEntry): TInkTextFormat;
    procedure MakeEntry(AIndex: Integer);
    procedure AddEntry(const AText: string; const E: TInkMemoEntry);
    procedure MemoStyler;
  protected
    procedure Parse; override;
    procedure LayoutColumn(out ALeft, AWidth: Integer); override;
    procedure StyleBlock(B: TInkPageBlock); override;
    procedure StyleSection(S: TInkTreeSection); override;
    function Options: THTMLOptions; override;
    function BlockOptions(Index: Integer): THTMLOptions; override;
    procedure LinkClicked(const Link: TInkLinkInfo); override;
    procedure HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo); override;
    function CopyBlockCaption(AIndex: Integer): string; override;
    function MenuBlockText(AIndex: Integer): string; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    { the messages are styled with the font: it changes, and the memo is
      read again }
    procedure FontChanged(Sender: TObject); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { adds a line at the end; the view follows it if it was at the end }
    procedure Append(const ALine: string);
    { text that must never be read as markup, shown exactly as written -
      what a stranger or a model wrote }
    procedure AppendPlain(const AText: string);
    { A whole message as ONE entry, laid out like a fragment of a page:
      paragraphs, lists, quotes, tables, fenced code through
      OnHighlightCode.  AColor puts a band behind it and AIndent sets it
      in, so a question reads apart from an answer. }
    procedure AppendBlock(const AText: string; AFormat: TInkTextFormat;
      AColor: TColor = clNone; AIndent: Integer = 0);
    { replaces the last entry's text and lays out only that entry - for an
      answer arriving a word at a time.  The view follows only when it was
      already at the end, and a selection elsewhere stays put. }
    procedure ReplaceLast(const AText: string);
    { the entry under a client point, -1 for none - for "Copy this answer"
      on a right click }
    function EntryAt(X, Y: Integer): Integer;
    { entry AIndex with all markup stripped, however many paragraphs }
    function GetEntryText(AIndex: Integer): string;
    { one complete HTML or Markdown document as the only line - a table or
      a list cannot be split across lines }
    procedure LoadDocument(const ADocument: string);
    procedure Clear;
    { line ALine with all markup stripped }
    function GetPlainText(ALine: Integer): string;
    { the whole text with all markup stripped, a line each }
    function PlainText: string;
    procedure SaveAsPlain(const FileName: string);
    procedure SaveAsHTML(const FileName: string);
    { how many lines there are }
    function Count: Integer;
    { The href under the mouse, '' when none }
    property HoverLink: string read FHoverHref;
    property HoverLinkText: string read FHoverLinkText;
  published
    property TextFormat;
    property Lines: TStrings read GetLines write SetLines;
    property HighlightCode;
    property OnHighlightCode;
    property CodeHeader;
    property CodeFoldLines;
    property CodeActions;
    property OnCodeAction;
    { the text's size, in percent of Font }
    property HTMLScale: Integer read FHTMLScale write SetHTMLScale default 100;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write SetSuperSubScriptRatio;
    { kept so forms from before selection existed still load; text is now
      selected with the mouse whatever this says }
    property ShowSelection: Boolean read FShowSelection write FShowSelection default False;
    { extra pixels between the lines inside one line of Lines }
    property LineSpacing: Integer read FLineSpacing write SetLineSpacing default 0;
    { Left and Right are margins beside the text; Top and Bottom are space
      above and below every line of Lines }
    property Borders: TInkBorders read FBorders write SetBorders;
    { Supplies <img src="n">, where n is an index into this list. }
    property Images: TCustomImageList read FImages write SetImages;
    property LinkStyle: TInkLinkStyle read FLinkStyle write SetLinkStyle;
    property LinkHoverStyle: TInkLinkStyle read FLinkHoverStyle write SetLinkHoverStyle;
    { Open a clicked link with the system browser. Only applies when no
      OnLinkClick handler is assigned - a handler always wins. }
    property AutoOpenLink: Boolean read FAutoOpenLink write FAutoOpenLink default False;
    property OnLinkClick: TInkMemoLinkEvent read FOnLinkClick write FOnLinkClick;
    property OnLinkEnter: TInkMemoLinkEvent read FOnLinkEnter write FOnLinkEnter;
    property OnLinkLeave: TInkMemoLinkEvent read FOnLinkLeave write FOnLinkLeave;
    property OnLinkRightClick: TInkMemoLinkEvent read FOnLinkRightClick write FOnLinkRightClick;
    { Re-flow each line to the width.  Off, a long line is cut off at the
      right edge. }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    property DragScroll;
    property FlickScroll;
    property MouseDrag;
    property ScrollBars;
    property SelectionColor;
    property OnSelectionChange;
    property CopyMenu;
    property OnCopyMenu;
    property PopupMenu;
    property Align; property Anchors; property BorderSpacing; property BorderStyle;
    property Color; property Constraints; property Enabled; property Font;
    property Hint; property ParentColor; property ParentFont; property ParentShowHint;
    property ShowHint; property TabStop default True; property TabOrder; property Visible;
    property OnClick; property OnDblClick; property OnEnter; property OnExit;
    property OnKeyDown; property OnKeyPress; property OnKeyUp; property OnUTF8KeyPress;
    property OnMouseDown; property OnMouseEnter; property OnMouseLeave; property OnMouseMove;
    property OnMouseUp; property OnMouseWheel; property OnResize;
  end;

implementation

uses
  Math;

{ TInkMemo }

constructor TInkMemo.Create(AOwner: TComponent);
begin
  FLines := TStringList.Create;
  inherited Create(AOwner);
  FLines.OnChange := @LinesChanged;
  FHTMLScale := 100;
  FSuperSubScriptRatio := 0.7;
  FWordWrap := False;
  FHoverLine := -1;
  FHoverBlock := -1;
  FBorders := TInkBorders.Create;
  FBorders.OnChange := @SubPropChanged;
  FNoBorders := TInkBorders.Create;
  FLinkStyle := TInkLinkStyle.Create(False);
  FLinkStyle.OnChange := @SubPropChanged;
  FLinkHoverStyle := TInkLinkStyle.Create(True);
  FLinkHoverStyle.OnChange := @SubPropChanged;
  { a memo is text first: the mouse selects, like any memo }
  Width := 300; Height := 150;
  Color := clWindow;
  Font.Color := clWindowText;
  Font.Size := 0;
  ParentFont := True;
end;

destructor TInkMemo.Destroy;
begin
  FLines.OnChange := nil;
  inherited Destroy;
  FreeAndNil(FLines);
  FreeAndNil(FBorders);
  FreeAndNil(FNoBorders);
  FreeAndNil(FLinkStyle);
  FreeAndNil(FLinkHoverStyle);
end;

function TInkMemo.DefaultEntry: TInkMemoEntry;
begin
  Result := Default(TInkMemoEntry);
  Result.Color := clNone;
end;

function TInkMemo.EntryFormat(const E: TInkMemoEntry): TInkTextFormat;
begin
  if E.Plain then Exit(itfPlain);
  if E.UseFormat then Result := E.Format else Result := TextFormat;
end;

function TInkMemo.MakeLine(AIndex: Integer): TInkPageBlock;
begin
  Result := TInkPageBlock.Create;
  Result.Tag := 'line';
  Result.Source := InkToHTML(FLines[AIndex], EntryFormat(FEntries[AIndex]));
end;

{ the styler the messages are styled with: no sheets but the browser's own
  and the memo's, which lets a message sit flush in its entry }
procedure TInkMemo.MemoStyler;
begin
  ResetStyler;
  Styler.MediumFont := Max(1, Round(ControlFontPixels * FHTMLScale / 100));
  Styler.AddSheet(ImageFitSheet);
  Styler.AddSheet(MarkdownSheet);
  Styler.AddSheet('html, body { margin: 0; padding: 0 } ' +
    'body > :first-child { margin-top: 0 } body > :last-child { margin-bottom: 0 }');
end;

{ entry AIndex as the memo's item AIndex: a line of inline markup, or a
  message laid out whole as a small document - paragraphs, lists, quotes,
  tables and fenced code as on a page }
procedure TInkMemo.MakeEntry(AIndex: Integer);
var S: string;
begin
  if FEntries[AIndex].Block then
  begin
    if Styler = nil then MemoStyler;
    if EntryFormat(FEntries[AIndex]) = itfMarkdown then S := MarkdownToHTML(FLines[AIndex])
    else S := FLines[AIndex];
    AddSection(InkParseHTML('<!doctype html>' + S), True);
  end
  else
    AddBlock(MakeLine(AIndex));
end;

{ every entry's items, and the view stays where it was }
procedure TInkMemo.Parse;
var
  I: Integer;
begin
  if FLines = nil then Exit;
  BeginDocument;
  MemoStyler;
  if Length(FEntries) <> FLines.Count then
  begin
    I := Length(FEntries);
    SetLength(FEntries, FLines.Count);
    while I < Length(FEntries) do
    begin
      FEntries[I] := DefaultEntry;
      Inc(I);
    end;
  end;
  for I := 0 to FLines.Count - 1 do
    MakeEntry(I);
  InvalidateLayout(0);
end;

procedure TInkMemo.LinesChanged(Sender: TObject);
var
  I: Integer;
begin
  { Lines changed from outside: every entry is an ordinary line again.
    The entry kinds live with AppendPlain, AppendBlock and ReplaceLast,
    which keep them while they edit Lines. }
  SetLength(FEntries, FLines.Count);
  for I := 0 to High(FEntries) do
    FEntries[I] := DefaultEntry;
  Parse;
end;

{ at the end, or everything fits - then new lines are followed, as in a
  terminal }
function TInkMemo.AtEnd: Boolean;
begin
  Layout;
  Result := ScrollY >= ContentHeight - ClientHeight - 2;
end;

{ one new entry and only its blocks laid out, not the whole memo again }
procedure TInkMemo.AddEntry(const AText: string; const E: TInkMemoEntry);
var
  Follow: Boolean;
begin
  Follow := AtEnd;
  FLines.OnChange := nil;
  try
    FLines.Add(AText);
  finally
    FLines.OnChange := @LinesChanged;
  end;
  SetLength(FEntries, FLines.Count);
  FEntries[FLines.Count - 1] := E;
  { a memo filled before it had a styler gets one now }
  if ItemCount <> FLines.Count - 1 then Parse
  else
  begin
    MakeEntry(FLines.Count - 1);
    InvalidateLayout(FLines.Count - 1);
  end;
  if Follow then ScrollTo(MaxInt);
end;

procedure TInkMemo.Append(const ALine: string);
begin
  AddEntry(ALine, DefaultEntry);
end;

procedure TInkMemo.AppendPlain(const AText: string);
var
  E: TInkMemoEntry;
begin
  E := DefaultEntry;
  E.Plain := True;
  AddEntry(AText, E);
end;

procedure TInkMemo.AppendBlock(const AText: string; AFormat: TInkTextFormat;
  AColor: TColor; AIndent: Integer);
var
  E: TInkMemoEntry;
begin
  E := DefaultEntry;
  E.Block := True;
  E.Format := AFormat;
  E.UseFormat := True;
  E.Color := AColor;
  E.Indent := Max(0, AIndent);
  AddEntry(AText, E);
end;

procedure TInkMemo.ReplaceLast(const AText: string);
var
  Follow: Boolean;
  N: Integer;
begin
  N := FLines.Count - 1;
  if N < 0 then
  begin
    Append(AText);
    Exit;
  end;
  if FLines[N] = AText then Exit;
  Follow := AtEnd;
  FLines.OnChange := nil;
  try
    FLines[N] := AText;
  finally
    FLines.OnChange := @LinesChanged;
  end;
  { only the last entry is rebuilt and laid out; everything before it - and
    a selection in it - stays exactly where it was }
  if ItemCount <> FLines.Count then Parse
  else
  begin
    TruncateItems(N);
    MakeEntry(N);
    InvalidateLayout(N);
  end;
  if Follow then ScrollTo(MaxInt);
end;

function TInkMemo.EntryAt(X, Y: Integer): Integer;
var
  I: Integer;
  R: TRect;
begin
  Result := -1;
  Layout;
  for I := 0 to BlockCount - 1 do
  begin
    R := Block(I).Bounds;
    if (Y + ScrollY >= R.Top) and (Y + ScrollY < R.Bottom) then
      Exit(Block(I).Entry);
  end;
end;

function TInkMemo.GetEntryText(AIndex: Integer): string;
var
  I: Integer;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FLines.Count) then Exit;
  Layout;
  for I := 0 to BlockCount - 1 do
    if Block(I).Entry = AIndex then
    begin
      if Result <> '' then Result := Result + LineEnding;
      Result := Result + BlockText(I);
    end;
end;

procedure TInkMemo.LoadDocument(const ADocument: string);
begin
  FLines.BeginUpdate;
  try
    FLines.Clear;
    FLines.Add(ADocument);
  finally FLines.EndUpdate end;
end;

procedure TInkMemo.Clear;
begin
  FLines.Clear;
end;

function TInkMemo.Count: Integer;
begin
  Result := FLines.Count;
end;

function TInkMemo.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TInkMemo.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
end;

procedure TInkMemo.SubPropChanged(Sender: TObject);
begin
  InvalidateLayout(0);
end;

procedure TInkMemo.SetHTMLScale(AValue: Integer);
begin
  AValue := EnsureRange(AValue, 10, 1000);
  if FHTMLScale = AValue then Exit;
  FHTMLScale := AValue;
  { the messages are styled at the scale }
  Parse;
end;

procedure TInkMemo.SetSuperSubScriptRatio(AValue: Double);
begin
  if FSuperSubScriptRatio = AValue then Exit;
  FSuperSubScriptRatio := AValue;
  SubPropChanged(nil);
end;

procedure TInkMemo.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  SubPropChanged(nil);
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
  begin
    FImages := nil;
    SubPropChanged(nil);
  end;
end;

{ --- how it is laid out and drawn --------------------------------------- }

procedure TInkMemo.LayoutColumn(out ALeft, AWidth: Integer);
begin
  ALeft := FBorders.Left;
  AWidth := Max(20, ClientWidth - ScrollBar.Width - FBorders.Left - FBorders.Right);
end;

procedure TInkMemo.StyleBlock(B: TInkPageBlock);
var
  C: TColor;
  E: TInkMemoEntry;
begin
  E := DefaultEntry;
  if (B.Entry >= 0) and (B.Entry <= High(FEntries)) then E := FEntries[B.Entry];
  B.Indent := E.Indent;
  { negative: pixels, the way every other block spells its size - positive
    read as points and drew the memo's text a third too big }
  B.PointSize := -Max(1, Round(FLayoutBase * FHTMLScale / 100));
  B.Bold := False;
  B.FaceName := '';
  B.Pre := False;
  B.NoWrap := not FWordWrap;
  C := Font.Color;
  if C = clDefault then C := clWindowText;
  B.TextColor := C;
  B.Padding := 0;
  B.GapBefore := FBorders.Top;
  B.GapAfter := FBorders.Bottom;
  B.BackColor := E.Color;
end;

procedure TInkMemo.StyleSection(S: TInkTreeSection);
var
  E: TInkMemoEntry;
begin
  E := DefaultEntry;
  if (S.Item >= 0) and (S.Item <= High(FEntries)) then E := FEntries[S.Item];
  S.GapBefore := FBorders.Top;
  S.GapAfter := FBorders.Bottom;
  S.Indent := E.Indent;
  S.Back := E.Color;
end;

function TInkMemo.Options: THTMLOptions;
begin
  { the borders are the layout's business here, not the renderer's }
  Result := InkOptions(FSuperSubScriptRatio, FHTMLScale, FLineSpacing,
    FNoBorders, FImages, FLinkStyle, FLinkHoverStyle, 0);
end;

function TInkMemo.BlockOptions(Index: Integer): THTMLOptions;
begin
  { the block's own say first - a code block in an entry never wraps, and
    a block entry keeps its line height - as on a page }
  Result := inherited BlockOptions(Index);
  { the hovered link only lights up in the block it is actually in }
  if Index = FHoverBlock then Result.HoverIndex := FHoverIndex;
end;

function TInkMemo.CopyBlockCaption(AIndex: Integer): string;
begin
  Result := SInkCopyLine;
  if (AIndex >= 0) and (AIndex < BlockCount) then
    if FEntries[Block(AIndex).Entry].Block then Result := SInkCopyMessage;
end;

function TInkMemo.MenuBlockText(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < BlockCount) and
    FEntries[Block(AIndex).Entry].Block then
    { the whole message, not the paragraph the mouse happened to be on }
    Result := GetEntryText(Block(AIndex).Entry)
  else
    Result := inherited MenuBlockText(AIndex);
end;

{ --- links -------------------------------------------------------------- }

{ Hover is tracked as (line, ordinal-of-link-on-that-line), so two links with
  the same target still light up one at a time. }
procedure TInkMemo.HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo);
var
  OldLine: Integer;
  OldLink: string;
begin
  OldLine := FHoverLine;
  OldLink := FHoverHref;
  if (OldLine >= 0) and Assigned(FOnLinkLeave) then
    FOnLinkLeave(Self, OldLine, OldLink);
  if AHit.OnLink and (ABlock >= 0) then
  begin
    FHoverLine := Block(ABlock).Entry;
    FHoverBlock := ABlock;
    FHoverIndex := AHit.LinkIndex;
    FHoverHref := LinkHref(AHit);
    FHoverLinkText := AHit.LinkText;
    if Assigned(FOnLinkEnter) then FOnLinkEnter(Self, FHoverLine, FHoverHref);
  end
  else
  begin
    FHoverLine := -1;
    FHoverBlock := -1;
    FHoverIndex := 0;
    FHoverHref := '';
    FHoverLinkText := '';
  end;
  Invalidate;
end;

procedure TInkMemo.LinkClicked(const Link: TInkLinkInfo);
begin
  if Assigned(FOnLinkClick) then
    FOnLinkClick(Self, Block(Link.Block).Entry, Link.Href)
  else if FAutoOpenLink then
    OpenURL(Link.Href);
end;

procedure TInkMemo.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbRight) and (FHoverLine >= 0) and (FHoverHref <> '') and
    Assigned(FOnLinkRightClick) then
    FOnLinkRightClick(Self, FHoverLine, FHoverHref);
end;

procedure TInkMemo.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  if Styler <> nil then Parse;
end;

{ --- text --------------------------------------------------------------- }

function TInkMemo.GetPlainText(ALine: Integer): string;
begin
  if (ALine < 0) or (ALine >= FLines.Count) then
    Result := ''
  else if FEntries[ALine].Block then
    Result := GetEntryText(ALine)
  else
    Result := HTMLPlainText(InkToHTML(FLines[ALine], EntryFormat(FEntries[ALine])));
end;

function TInkMemo.PlainText: string;
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    for I := 0 to FLines.Count - 1 do
      SL.Add(GetPlainText(I));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TInkMemo.SaveAsPlain(const FileName: string);
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    for I := 0 to FLines.Count - 1 do
      SL.Add(GetPlainText(I));
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TInkMemo.SaveAsHTML(const FileName: string);
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    for I := 0 to FLines.Count - 1 do
      SL.Add(InkToHTML(FLines[I], TextFormat));
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

end.
