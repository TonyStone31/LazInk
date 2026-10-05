{ LazInk — lightweight HTML-formatted text controls for Lazarus.

  TInkRichEdit: a multi-line WYSIWYG editor for the LazInk markup subset. The
  caret and the selection live inside the *rendered* text — select a word in
  bold red 16pt and the caret sits between the actual glyphs you can see. Hit
  the bold button and that run stops being bold. There is no source view to
  keep in sync, because the document is not markup: markup is only what it is
  read from and written back to.

  Every character carries its own color, background, size, face, style,
  script and link. Nothing is drawn by a native text widget, so this behaves
  and looks identical on win32, gtk2, gtk3, qt5/6 and cocoa — the whole point
  of LazInk. No RichMemo, no per-widgetset backend.

  The document is a flat array of UTF-8 characters with a parallel array of
  attributes; a paragraph break is the single character #10. That keeps caret
  arithmetic, selection, insert and delete to one dimension. Everything
  two-dimensional (wrapping, line heights, baselines) is derived in Relayout
  and cached in FLines/FCharX/FCharW.

  License: MIT.
}
unit InkRichEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, StdCtrls, Forms, LCLType,
  LCLIntf, LMessages, Clipbrd, LazUTF8, ExtCtrls, Types, Menus;

type
  TInkScript = (isNormal, isSuperscript, isSubscript);

  { What a paragraph is - plain text, a heading, a list item, a quote or a
    line of code.  Held per character like Align, so the flat document
    stays flat; every character of a paragraph (its #10 included) carries
    the same kind. }
  TInkParaKind = (ipkText, ipkH1, ipkH2, ipkH3, ipkH4, ipkH5, ipkH6,
    ipkBullet, ipkNumber, ipkQuote, ipkCode,
    { a table row: its cells are the text between literal '|' characters,
      which draw as the grid, not as glyphs.  Consecutive table rows are
      one table and share their column widths; the head row is bold on a
      band.  Tab hops to the next cell, Enter adds a row. }
    ipkTableHead, ipkTableRow);

  { Everything one character can carry. The sentinels — clDefault, clNone, 0,
    '' — mean "follow the control's Font", so a document that never mentions a
    color still tracks the control when the control's Font changes. }
  TInkAttr = record
    Color: TColor;        // clDefault -> Font.Color
    BackColor: TColor;    // clNone    -> transparent
    Size: Integer;        // 0         -> Font.Size
    Face: string;         // ''        -> Font.Name
    Style: TFontStyles;
    Script: TInkScript;
    Link: string;         // ''        -> not a link
    Align: TAlignment;    // paragraph property, held per character
    Kind: TInkParaKind;   // paragraph property, held per character
    Level: Byte;          // a list item's nesting depth, 0 for the first
    Lang: string;         // a code line's fence language, '' unsaid
  end;

  { One visual line: a run of characters that share a baseline. A paragraph is
    one line plus one more for every wrap point inside it. }
  TInkVisLine = record
    First: Integer;       // index of the first character
    Count: Integer;       // how many characters, including a trailing #10
    Top: Integer;         // y of the line's top, in document space
    Height: Integer;
    Ascent: Integer;      // baseline offset from Top
    Width: Integer;
    Left: Integer;        // x of the line's start, after alignment
  end;

  TInkRichLinkEvent = procedure(Sender: TObject; const LinkName: string) of object;

  { TInkRichEdit }

  TInkRichEdit = class(TCustomControl)
  private
    FChars: array of string;      // one UTF-8 codepoint each; #10 = paragraph
    FAttrs: array of TInkAttr;
    FCaret: Integer;              // 0..CharCount, a gap between characters
    FAnchor: Integer;             // selection anchor; = FCaret when none
    FLines: array of TInkVisLine;
    FCharX: array of Integer;     // x of each character within its own line
    FCharW: array of Integer;
    FLayoutValid: Boolean;
    FDocHeight: Integer;
    FScrollY: Integer;
    FVScroll: TScrollBar;
    FTypingAttr: TInkAttr;        // what the next typed character will wear
    FHasTypingAttr: Boolean;
    FMarkup: TStrings;            // one paragraph per line
    FMarkupDirty: Boolean;
    FSettingMarkup: Boolean;
    FCaretTimer: TTimer;
    FCaretOn: Boolean;
    FGoalX: Integer;              // remembered column for up/down
    FUndo: TFPList;
    FRedo: TFPList;
    FLastUndoTick: QWord;
    FReadOnly: Boolean;
    FWordWrap: Boolean;
    FSuperSubScriptRatio: Double;
    FModified: Boolean;
    FMouseOnLink: Boolean;
    FHoverLink: string;
    FOnChange: TNotifyEvent;
    FOnSelectionChange: TNotifyEvent;
    FOnLinkClick: TInkRichLinkEvent;
    FEditMenu: Boolean;
    FMenu: TPopupMenu;
    procedure MenuClick(Sender: TObject);
    function CharCount: Integer;
    function GetSelStart: Integer;
    function GetSelLength: Integer;
    procedure SetSelStart(AValue: Integer);
    procedure SetSelLength(AValue: Integer);
    function GetSelText: string;
    procedure SetMarkup(AValue: TStrings);
    function GetMarkup: TStrings;
    procedure MarkupChanged(Sender: TObject);
    procedure RebuildFromMarkup;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    { layout }
    procedure InvalidateLayout;
    procedure Relayout;
    procedure NeedLayout;
    procedure ApplyAttrToCanvas(const A: TInkAttr);
    function ParaKindAt(AIndex: Integer): TInkParaKind;
    function ParaLevelAt(AIndex: Integer): Integer;
    function ParaIndent(AKind: TInkParaKind; ALevel: Integer): Integer;
    function ParaNumber(AFirst: Integer): Integer;
    function MeasureChar(AIndex: Integer): Integer;
    function LineOfChar(AIndex: Integer): Integer;
    function CaretLine(ACaret: Integer): Integer;
    function LineTextWidth: Integer;
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure ScrollToCaret;
    function CaretPoint(ACaret: Integer): TPoint;   // document space
    function PointToCaret(X, Y: Integer): Integer;  // client space
    { document }
    procedure DoInsert(const AText: string; const AAttr: TInkAttr);
    procedure DoDelete(AFrom, ATo: Integer);
    procedure DeleteSelection;
    function AttrAtCaret: TInkAttr;
    procedure Changed;
    procedure SelectionChanged;
    procedure MoveCaret(ANew: Integer; AExtend: Boolean);
    { markup }
    procedure ParseInto(const AMarkup: string; AParaBreakFirst: Boolean);
    procedure SyncMarkupFromDoc;
    { undo }
    procedure PushUndo(ACoalesce: Boolean);
    procedure ClearUndoList(AList: TFPList);
    procedure RestoreSnapshot(ASnap: TObject);
    function TakeSnapshot: TObject;
    procedure CaretTimerTick(Sender: TObject);
    procedure RestartCaretBlink;
  protected
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { What a character is drawn and measured as: FAttrs[AIndex], passed
      through AdjustAttr, which a descendant overrides to color characters
      on the fly - the plain editor's OnGetCharAttrs rides on this. }
    function EffAttr(AIndex: Integer): TInkAttr;
    function CharAt(AIndex: Integer): string;
    procedure AdjustAttr(AIndex: Integer; var A: TInkAttr); virtual;
    { inserts plain text (line breaks kept) in the attributes at the caret }
    procedure InsertPlainText(const AText: string);
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure FontChanged(Sender: TObject); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Click; override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    class function GetControlClassDefaultSize: TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Clear;
    procedure SelectAll;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard; virtual;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;

    { Formatting. With a selection they change it; with none they set what the
      next typed character will wear, the way every editor behaves. }
    procedure ApplyStyle(AStyle: TFontStyle; AOn: Boolean);
    procedure ToggleStyle(AStyle: TFontStyle);
    procedure ApplyColor(AColor: TColor);
    procedure ApplyBackColor(AColor: TColor);
    procedure ApplySize(ASize: Integer);
    procedure ApplyFace(const AFace: string);
    procedure ApplyScript(AScript: TInkScript);
    procedure ApplyLink(const AHref: string);
    procedure ApplyAlignment(AAlign: TAlignment);
    { the whole paragraphs the selection touches become AKind - a heading,
      a bullet or numbered item, a quote, a line of code, or plain text }
    procedure ApplyParaKind(AKind: TInkParaKind);
    { the list items the selection touches step ADelta levels deeper or
      back out - what Tab and Shift+Tab do on a list item }
    procedure ApplyParaLevel(ADelta: Integer);
    { a fresh table at the caret: a head row and ARows body rows of ACols
      empty cells, the caret in the head's first cell }
    procedure InsertTable(ACols, ARows: Integer);
    procedure ClearFormatting;
    procedure InsertParagraph;

    { What the toolbar should show as pressed: the value shared by the whole
      selection, or the sentinel when the selection disagrees with itself. }
    function SelStyle: TFontStyles;
    function SelColor: TColor;
    function SelBackColor: TColor;
    function SelSize: Integer;
    function SelFace: string;
    function SelScript: TInkScript;
    function SelAlignment: TAlignment;
    function SelParaKind: TInkParaKind;

    { The document as markup, paragraphs joined with ASep. Feed it straight to
      a TInkLabel caption or a TInkMemo line. }
    function AsHTML(const ASep: string = '<br>'): string;
    function PlainText: string;
    { The document as Markdown, and a Markdown document read in: headings,
      bullet and numbered lists, quotes, fenced code, bold, italic, strike,
      code spans and links.  What Markdown has no word for rides as inline
      HTML (<u>, <sup>, <sub>); colors and faces do not survive the trip. }
    function AsMarkdown: string;
    procedure LoadMarkdown(const S: string);
    property SelText: string read GetSelText;
    property Modified: Boolean read FModified write FModified;
    { runtime only - a stored caret position would be meaningless in a .lfm }
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
  published
    { One paragraph per line. Editable in the Object Inspector, so a design-time
      document is real markup in the .lfm and renders in the form designer. }
    property Markup: TStrings read GetMarkup write SetMarkup;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default True;
    property SuperSubScriptRatio: Double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    { the editor's own right-click menu - Undo, Redo, Cut, Copy, Paste,
      Delete, Select All; a PopupMenu of the host's own still wins }
    property EditMenu: Boolean read FEditMenu write FEditMenu default True;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnLinkClick: TInkRichLinkEvent read FOnLinkClick write FOnLinkClick;

    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle default bsSingle;
    property Color default clWindow;
    property Constraints;
    property Enabled;
    property Font;
    property Hint;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    property TabStop default True;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
    property OnUTF8KeyPress;
  end;

function DefaultInkAttr: TInkAttr;
function SameInkAttr(const A, B: TInkAttr): Boolean;

implementation

uses
  StrUtils, InkDraw, InkTouch, InkMarkdown, InkEdit;

const
  cMargin = 3;
  cCellPad = 8;           // a table cell's inset each side of its text
  cRowPad = 4;            // and above and below it
  cScrollBarWidth = 16;
  cUndoDepth = 200;
  cUndoCoalesceMs = 700;

type
  { A whole-document snapshot. Documents in an editor like this are small, and
    a snapshot that cannot be subtly wrong beats a delta log that can. }
  TInkSnapshot = class
    Chars: array of string;
    Attrs: array of TInkAttr;
    Caret: Integer;
    Anchor: Integer;
  end;

var
  { Copying inside the app keeps the formatting: the plain text goes to the
    system clipboard as usual, and the attributes are parked here. A paste
    only uses them when the clipboard still holds the very text they belong
    to, so pasting from another app can never pick up stale styling. }
  gClipText: string = '';
  gClipAttrs: array of TInkAttr;

function DefaultInkAttr: TInkAttr;
begin
  Result.Color := clDefault;
  Result.BackColor := clNone;
  Result.Size := 0;
  Result.Face := '';
  Result.Style := [];
  Result.Script := isNormal;
  Result.Link := '';
  Result.Align := taLeftJustify;
  Result.Kind := ipkText;
  Result.Level := 0;
  Result.Lang := '';
end;

function SameInkAttr(const A, B: TInkAttr): Boolean;
begin
  Result := (A.Color = B.Color) and (A.BackColor = B.BackColor) and
    (A.Size = B.Size) and (A.Face = B.Face) and (A.Style = B.Style) and
    (A.Script = B.Script) and (A.Link = B.Link) and (A.Align = B.Align) and
    (A.Kind = B.Kind) and (A.Level = B.Level) and (A.Lang = B.Lang);
end;

{ '#RRGGBB' for a real color, '' for the sentinels }
function InkColorToHTML(C: TColor): string;
var
  RGB: LongInt;
begin
  if (C = clDefault) or (C = clNone) then
    Exit('');
  RGB := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x', [Red(RGB), Green(RGB), Blue(RGB)]);
end;

{ TInkRichEdit }

procedure TInkRichEdit.CreateWnd;
begin
  inherited CreateWnd;
  { a finger places the caret and selects, as the mouse does }
  InkHookTouchAsMouse(Self);
end;

constructor TInkRichEdit.Create(AOwner: TComponent);
begin
  FEditMenu := True;
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse, csOpaque, csRequiresKeyboardInput]
    - [csSetCaption];
  BorderStyle := bsSingle;
  TabStop := True;
  Cursor := crIBeam;
  Color := clWindow;
  Font.Color := clWindowText;
  FWordWrap := True;
  FSuperSubScriptRatio := 0.7;
  FCaret := 0;
  FAnchor := 0;
  FGoalX := -1;
  FTypingAttr := DefaultInkAttr;
  FMarkup := TStringList.Create;
  // Markup is a TStrings people will write to in place - "Markup.Text := x",
  // "Markup.Add(...)", the Object Inspector's string editor - and none of that
  // goes through the property setter. Listening to the list itself is the only
  // way to hear about all of it.
  TStringList(FMarkup).OnChange := @MarkupChanged;
  FUndo := TFPList.Create;
  FRedo := TFPList.Create;

  FVScroll := TScrollBar.Create(Self);
  FVScroll.Kind := sbVertical;
  FVScroll.Parent := Self;
  FVScroll.TabStop := False;
  FVScroll.Visible := False;
  FVScroll.Width := cScrollBarWidth;
  FVScroll.OnChange := @ScrollBarChange;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.Enabled := False;
  FCaretTimer.OnTimer := @CaretTimerTick;

  with GetControlClassDefaultSize do
    SetInitialBounds(0, 0, cx, cy);
end;

destructor TInkRichEdit.Destroy;
begin
  FreeAndNil(FMenu);
  ClearUndoList(FUndo);
  ClearUndoList(FRedo);
  FreeAndNil(FUndo);
  FreeAndNil(FRedo);
  FreeAndNil(FMarkup);
  inherited Destroy;
end;

class function TInkRichEdit.GetControlClassDefaultSize: TSize;
begin
  Result.cx := 320;
  Result.cy := 200;
end;

function TInkRichEdit.CharCount: Integer;
begin
  Result := Length(FChars);
end;

{ ---------------------------------------------------------------- selection }

function TInkRichEdit.GetSelStart: Integer;
begin
  if FCaret < FAnchor then Result := FCaret else Result := FAnchor;
end;

function TInkRichEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

procedure TInkRichEdit.SetSelStart(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > CharCount then AValue := CharCount;
  FCaret := AValue;
  FAnchor := AValue;
  FHasTypingAttr := False;
  ScrollToCaret;
  RestartCaretBlink;
  Invalidate;
  SelectionChanged;
end;

procedure TInkRichEdit.SetSelLength(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FAnchor := GetSelStart;
  FCaret := FAnchor + AValue;
  if FCaret > CharCount then FCaret := CharCount;
  ScrollToCaret;
  Invalidate;
  SelectionChanged;
end;

function TInkRichEdit.GetSelText: string;
var
  i: Integer;
begin
  Result := '';
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

procedure TInkRichEdit.MoveCaret(ANew: Integer; AExtend: Boolean);
begin
  if ANew < 0 then ANew := 0;
  if ANew > CharCount then ANew := CharCount;
  FCaret := ANew;
  if not AExtend then FAnchor := FCaret;
  FHasTypingAttr := False;
  ScrollToCaret;
  RestartCaretBlink;
  Invalidate;
  SelectionChanged;
end;

procedure TInkRichEdit.SelectAll;
begin
  FAnchor := 0;
  FCaret := CharCount;
  Invalidate;
  SelectionChanged;
end;

{ ------------------------------------------------------------------- layout }

procedure TInkRichEdit.InvalidateLayout;
begin
  FLayoutValid := False;
  Invalidate;
end;

procedure TInkRichEdit.NeedLayout;
begin
  if not FLayoutValid then Relayout;
end;

procedure TInkRichEdit.ApplyAttrToCanvas(const A: TInkAttr);
const
  { a browser's own heading factors }
  cHeadFactor: array[ipkH1..ipkH6] of Double = (2.0, 1.5, 1.17, 1.0, 0.83, 0.67);
var
  Sz: Integer;
begin
  if A.Face <> '' then
    Canvas.Font.Name := A.Face
  else if A.Kind = ipkCode then
    Canvas.Font.Name := InkMonoFace
  else
    Canvas.Font.Name := Font.Name;
  if A.Size > 0 then Sz := A.Size else Sz := Font.Size;
  if Sz = 0 then Sz := Screen.SystemFont.Size;
  { a heading's size and weight come from its kind, unless the character
    picked its own size }
  if (A.Kind in [ipkH1..ipkH6]) and (A.Size = 0) then
    Sz := Max(1, Round(Sz * cHeadFactor[A.Kind]));
  if A.Script <> isNormal then
    Sz := Round(Sz * FSuperSubScriptRatio);
  if Sz < 1 then Sz := 1;
  Canvas.Font.Size := Sz;
  if A.Kind in [ipkH1..ipkH6, ipkTableHead] then
    Canvas.Font.Style := A.Style + [fsBold]
  else
    Canvas.Font.Style := A.Style;
  if A.Link <> '' then
  begin
    if A.Color = clDefault then
      Canvas.Font.Color := clBlue
    else
      Canvas.Font.Color := A.Color;
    Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
  end
  else if A.Color <> clDefault then
    Canvas.Font.Color := A.Color
  else if A.BackColor <> clNone then
    // highlighted, but nobody said what color the text should be - so pick
    // one that can be read on that background rather than inheriting a
    // control color that may well be invisible on it
    Canvas.Font.Color := HTMLContrastColor(A.BackColor)
  else
    Canvas.Font.Color := Font.Color;
end;

{ the paragraph kind at a character; the gap past the end is plain text }
function TInkRichEdit.ParaKindAt(AIndex: Integer): TInkParaKind;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FAttrs[AIndex].Kind
  else
    Result := ipkText;
end;

function TInkRichEdit.ParaLevelAt(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FAttrs[AIndex].Level
  else
    Result := 0;
end;

{ a list marker's gutter - one more gutter per nesting level - a quote's
  bar and inset, a code line's inset.  Measured in the control's font,
  which it leaves on the canvas. }
function TInkRichEdit.ParaIndent(AKind: TInkParaKind; ALevel: Integer): Integer;
begin
  Canvas.Font := Font;
  case AKind of
    ipkBullet, ipkNumber: Result := Canvas.TextWidth('99. ') * (ALevel + 1);
    ipkQuote: Result := Canvas.TextWidth('AB');
    ipkCode: Result := Canvas.TextWidth('A') div 2 + 4;
  else
    Result := 0;
  end;
end;

{ Which number a numbered item carries: one more than the unbroken run of
  numbered paragraphs above it at its own level.  A deeper sublist between
  two items does not break their numbering; a shallower item or anything
  else does.  The #10 that ends a paragraph carries the paragraph's own
  kind and level, which is what makes this walk cheap. }
function TInkRichEdit.ParaNumber(AFirst: Integer): Integer;
var
  i, j, MyLevel: Integer;
begin
  Result := 1;
  MyLevel := ParaLevelAt(AFirst);
  i := AFirst - 1;
  while (i >= 0) and (FChars[i] = #10) do
  begin
    if (FAttrs[i].Kind = ipkNumber) and (FAttrs[i].Level = MyLevel) then
      Inc(Result)
    else if not ((FAttrs[i].Kind in [ipkBullet, ipkNumber]) and
      (FAttrs[i].Level > MyLevel)) then
      Break;
    j := i - 1;
    while (j >= 0) and (FChars[j] <> #10) do Dec(j);
    i := j;
  end;
end;

function TInkRichEdit.MeasureChar(AIndex: Integer): Integer;
begin
  if FChars[AIndex] = #10 then
    Result := 0
  else
    Result := Canvas.TextWidth(FChars[AIndex]);
end;

function TInkRichEdit.LineTextWidth: Integer;
begin
  Result := ClientWidth - 2 * cMargin;
  if FVScroll.Visible then Dec(Result, FVScroll.Width);
  if Result < 16 then Result := 16;
end;

procedure TInkRichEdit.Relayout;
var
  N, i, k, X, W, Avail, AvailP, Y, LineStart, LastSpace, BreakAt: Integer;
  LineCount: Integer;
  LastAttr: TInkAttr;
  HasLast: Boolean;
  CurKind: TInkParaKind;
  CurInd: Integer;
  { the full width a table row's line reports, while one is being laid }
  TableRowW: Integer;

  { Height and baseline of the characters [AFirst, AFirst+ACount). An empty
    paragraph still needs a line box, so fall back to the control font. }
  procedure EmitLine(AFirst, ACount: Integer);
  var
    j, H, Asc, MaxH, MaxAsc, Rise: Integer;
    tm: TLCLTextMetric;
    L: TInkVisLine;
    Al: TAlignment;
  begin
    Canvas.Font := Font;
    if Canvas.GetTextMetrics(tm) then
    begin
      MaxH := tm.Height;
      MaxAsc := tm.Ascender;
    end
    else
    begin
      MaxH := Canvas.TextHeight('Ag');
      MaxAsc := MaxH - (MaxH div 5);
    end;

    for j := AFirst to AFirst + ACount - 1 do
    begin
      if FChars[j] = #10 then Continue;
      ApplyAttrToCanvas(EffAttr(j));
      if Canvas.GetTextMetrics(tm) then
      begin
        H := tm.Height;
        Asc := tm.Ascender;
      end
      else
      begin
        H := Canvas.TextHeight('Ag');
        Asc := H - (H div 5);
      end;
      // a raised run needs headroom above it, a lowered one below
      Rise := 0;
      if FAttrs[j].Script = isSuperscript then
        Rise := (MaxAsc * 35) div 100
      else if FAttrs[j].Script = isSubscript then
        Rise := -((MaxAsc * 18) div 100);
      if Asc + Rise > MaxAsc then MaxAsc := Asc + Rise;
      if H - Asc - Rise > MaxH - MaxAsc then MaxH := MaxAsc + (H - Asc - Rise);
    end;

    L.First := AFirst;
    L.Count := ACount;
    L.Top := Y;
    L.Height := MaxH + 1;
    L.Ascent := MaxAsc;
    if TableRowW > 0 then
    begin
      Inc(L.Height, 2 * cRowPad);
      Inc(L.Ascent, cRowPad);
    end;
    if ACount > 0 then
      L.Width := FCharX[AFirst + ACount - 1] + FCharW[AFirst + ACount - 1]
    else
      L.Width := 0;
    if N = 0 then
      Al := taLeftJustify
    else if AFirst < N then
      Al := FAttrs[AFirst].Align
    else
      Al := FAttrs[N - 1].Align;
    if TableRowW > 0 then L.Width := TableRowW;
    { the paragraph's indent first - a list marker's gutter, a quote's bar,
      a code line's inset - then the alignment inside what is left }
    case Al of
      taCenter: L.Left := cMargin + CurInd + Max(0, (Avail - CurInd - L.Width) div 2);
      taRightJustify: L.Left := cMargin + CurInd + Max(0, Avail - CurInd - L.Width);
    else
      L.Left := cMargin + CurInd;
    end;
    if TableRowW > 0 then L.Left := cMargin;

    if LineCount >= Length(FLines) then
      SetLength(FLines, Max(8, Length(FLines) * 2));
    FLines[LineCount] := L;
    Inc(LineCount);
    Inc(Y, L.Height);
    HasLast := False;   // canvas font was reset above
  end;

  { A run of table rows laid out as one table: the columns are shared by
    every row of the group, a '|' takes the width of the border gap it
    draws in, and each row is one line that never wraps.  Everything else
    - the caret, clicks, selection - keeps working through FCharX/FCharW. }
  procedure LayTableGroup;
  var
    GEnd, j, c, NCols, RowStart, CellW, ColCount: Integer;
    ColW, ColX: array of Integer;

    procedure CloseCell;
    begin
      if c >= Length(ColW) then
      begin
        SetLength(ColW, c + 1);
        ColW[c] := 0;
      end;
      if CellW > ColW[c] then ColW[c] := CellW;
      CellW := 0;
    end;

  begin
    { the group: this paragraph and every table row after it }
    GEnd := i;
    while GEnd < N do
    begin
      if FChars[GEnd] = #10 then
        if (GEnd + 1 >= N) or
          not (FAttrs[GEnd + 1].Kind in [ipkTableHead, ipkTableRow]) then
        begin
          Inc(GEnd);
          Break;
        end;
      Inc(GEnd);
    end;

    { pass 1: every character in its own attrs; the widest cell per column }
    c := 0;
    CellW := 0;
    for j := i to GEnd - 1 do
    begin
      if (FChars[j] = #10) or (FChars[j] = '|') then
      begin
        FCharW[j] := 0;
        CloseCell;
        if FChars[j] = '|' then Inc(c) else c := 0;
        Continue;
      end;
      ApplyAttrToCanvas(EffAttr(j));
      FCharW[j] := MeasureChar(j);
      Inc(CellW, FCharW[j]);
    end;
    if (GEnd = N) or (GEnd > i) then CloseCell;
    NCols := Length(ColW);
    if NCols = 0 then
    begin
      SetLength(ColW, 1);
      ColW[0] := 0;
      NCols := 1;
    end;
    SetLength(ColX, NCols + 1);
    ColX[0] := 0;
    for c := 0 to NCols - 1 do
      ColX[c + 1] := ColX[c] + Max(ColW[c], 16) + 2 * cCellPad;
    TableRowW := ColX[NCols];

    { pass 2: place each row and emit its line }
    RowStart := i;
    c := 0;
    X := ColX[0] + cCellPad;
    for j := i to GEnd - 1 do
    begin
      if FChars[j] = #10 then
      begin
        FCharX[j] := X;
        FCharW[j] := 0;
        EmitLine(RowStart, j - RowStart + 1);
        RowStart := j + 1;
        c := 0;
        X := ColX[0] + cCellPad;
        Continue;
      end;
      if FChars[j] = '|' then
      begin
        FCharX[j] := X;
        ColCount := Min(c + 1, NCols);
        FCharW[j] := Max(0, ColX[ColCount] + cCellPad - X);
        X := ColX[ColCount] + cCellPad;
        c := ColCount;
        Continue;
      end;
      FCharX[j] := X;
      Inc(X, FCharW[j]);
    end;
    if RowStart < GEnd then EmitLine(RowStart, GEnd - RowStart);
    TableRowW := 0;

    { the main loop picks up after the group }
    i := GEnd;
    LineStart := GEnd;
    X := 0;
    LastSpace := -1;
    HasLast := False;
    CurKind := ParaKindAt(GEnd);
    CurInd := ParaIndent(CurKind, ParaLevelAt(GEnd));
    AvailP := Max(16, Avail - CurInd);
  end;

begin
  FLayoutValid := True;
  N := CharCount;
  SetLength(FCharX, N);
  SetLength(FCharW, N);
  SetLength(FLines, 0);
  LineCount := 0;
  Y := 0;
  Avail := LineTextWidth;
  LineStart := 0;
  X := 0;
  LastSpace := -1;
  HasLast := False;
  LastAttr := DefaultInkAttr;
  TableRowW := 0;
  CurKind := ParaKindAt(0);
  CurInd := ParaIndent(CurKind, ParaLevelAt(0));
  AvailP := Max(16, Avail - CurInd);

  i := 0;
  while i < N do
  begin
    { a table group is laid out as one block of shared columns }
    if (i = LineStart) and (CurKind in [ipkTableHead, ipkTableRow]) then
    begin
      LayTableGroup;
      Continue;
    end;
    if FChars[i] = #10 then
    begin
      FCharX[i] := X;
      FCharW[i] := 0;
      EmitLine(LineStart, i - LineStart + 1);
      LineStart := i + 1;
      X := 0;
      LastSpace := -1;
      CurKind := ParaKindAt(i + 1);
      CurInd := ParaIndent(CurKind, ParaLevelAt(i + 1));
      AvailP := Max(16, Avail - CurInd);
      HasLast := False;    { ParaIndent used the canvas font }
      Inc(i);
      Continue;
    end;

    if (not HasLast) or (not SameInkAttr(LastAttr, EffAttr(i))) then
    begin
      LastAttr := EffAttr(i);
      ApplyAttrToCanvas(LastAttr);
      HasLast := True;
    end;
    W := MeasureChar(i);

    if FWordWrap and (i > LineStart) and (X + W > AvailP) then
    begin
      // break after the last blank if there was one, otherwise mid-word
      if LastSpace >= LineStart then
        BreakAt := LastSpace + 1
      else
        BreakAt := i;
      EmitLine(LineStart, BreakAt - LineStart);
      LineStart := BreakAt;
      X := 0;
      for k := BreakAt to i - 1 do
      begin
        FCharX[k] := X;
        Inc(X, FCharW[k]);
      end;
      LastSpace := -1;
      HasLast := False;
    end;

    FCharX[i] := X;
    FCharW[i] := W;
    Inc(X, W);
    // CJK writes without spaces, so every ideograph is somewhere a line may
    // break; otherwise a CJK paragraph would only ever break mid-character
    if (FChars[i] = ' ') or HTMLIsCJK(FChars[i]) then LastSpace := i;
    Inc(i);
  end;

  // the tail, and the empty line a document ending in #10 leaves behind
  EmitLine(LineStart, N - LineStart);
  SetLength(FLines, LineCount);
  FDocHeight := Y;
  UpdateScrollBar;
end;

function TInkRichEdit.LineOfChar(AIndex: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FLines) do
    if (AIndex >= FLines[i].First) and
       (AIndex < FLines[i].First + FLines[i].Count) then
      Exit(i);
  if Length(FLines) > 0 then Result := High(FLines);
end;

{ A caret on a wrap boundary could be claimed by either line; it goes to the
  start of the next one, except at the very end where there is no next one. }
function TInkRichEdit.CaretLine(ACaret: Integer): Integer;
var
  Idx: Integer;
begin
  NeedLayout;
  Result := High(FLines);
  if Length(FLines) = 0 then Exit(0);
  if ACaret >= CharCount then Exit(High(FLines));
  for Idx := 0 to High(FLines) do
    if ACaret < FLines[Idx].First + FLines[Idx].Count then
      Exit(Idx);
end;

function TInkRichEdit.CaretPoint(ACaret: Integer): TPoint;
var
  L: Integer;
begin
  NeedLayout;
  Result := Point(cMargin, 0);
  if Length(FLines) = 0 then Exit;
  L := CaretLine(ACaret);

  Result.Y := FLines[L].Top;
  if ACaret <= FLines[L].First then
    Result.X := FLines[L].Left
  else if ACaret >= FLines[L].First + FLines[L].Count then
    Result.X := FLines[L].Left + FLines[L].Width
  else
    Result.X := FLines[L].Left + FCharX[ACaret];
end;

function TInkRichEdit.PointToCaret(X, Y: Integer): Integer;
var
  L, i, DocY, CX, Last: Integer;
begin
  NeedLayout;
  if Length(FLines) = 0 then Exit(0);
  DocY := Y + FScrollY;

  L := High(FLines);
  for i := 0 to High(FLines) do
    if DocY < FLines[i].Top + FLines[i].Height then
    begin
      L := i;
      Break;
    end;
  if DocY < 0 then L := 0;

  Last := FLines[L].First + FLines[L].Count;
  // never let a click land past a paragraph break: that gap belongs to the
  // start of the next line, and putting the caret there looks like a bug
  if (FLines[L].Count > 0) and (FChars[Last - 1] = #10) then Dec(Last);

  Result := Last;
  for i := FLines[L].First to Last - 1 do
  begin
    CX := FLines[L].Left + FCharX[i] + (FCharW[i] div 2);
    if X < CX then
      Exit(i);
  end;
end;

{ --------------------------------------------------------------- scrolling  }

procedure TInkRichEdit.UpdateScrollBar;
var
  NeedBar: Boolean;
begin
  if FVScroll = nil then Exit;
  NeedBar := FDocHeight > ClientHeight;
  if NeedBar <> FVScroll.Visible then
  begin
    FVScroll.Visible := NeedBar;
    // the text column just got narrower or wider, so everything must re-flow
    FLayoutValid := False;
  end;
  if NeedBar then
  begin
    FVScroll.SetBounds(ClientWidth - cScrollBarWidth, 0, cScrollBarWidth,
      ClientHeight);
    FVScroll.Min := 0;
    FVScroll.Max := FDocHeight;
    FVScroll.PageSize := ClientHeight;
    FVScroll.LargeChange := ClientHeight;
    FVScroll.SmallChange := 16;
    if FScrollY > FDocHeight - ClientHeight then
      FScrollY := FDocHeight - ClientHeight;
    if FScrollY < 0 then FScrollY := 0;
    if FVScroll.Position <> FScrollY then
      FVScroll.Position := FScrollY;
  end
  else
    FScrollY := 0;
end;

procedure TInkRichEdit.ScrollBarChange(Sender: TObject);
begin
  if FScrollY = FVScroll.Position then Exit;
  FScrollY := FVScroll.Position;
  Invalidate;
end;

procedure TInkRichEdit.ScrollToCaret;
var
  P: TPoint;
  L, H: Integer;
begin
  if not HandleAllocated then Exit;
  NeedLayout;
  P := CaretPoint(FCaret);
  if Length(FLines) = 0 then Exit;
  L := CaretLine(FCaret);
  H := FLines[L].Height;

  if P.Y < FScrollY then
    FScrollY := P.Y
  else if P.Y + H > FScrollY + ClientHeight then
    FScrollY := P.Y + H - ClientHeight;
  if FScrollY > FDocHeight - ClientHeight then
    FScrollY := FDocHeight - ClientHeight;
  if FScrollY < 0 then FScrollY := 0;
  if FVScroll.Visible and (FVScroll.Position <> FScrollY) then
    FVScroll.Position := FScrollY;
end;

function TInkRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not FVScroll.Visible then Exit;
  FScrollY := FScrollY - (WheelDelta * 3) div 8;
  if FScrollY > FDocHeight - ClientHeight then
    FScrollY := FDocHeight - ClientHeight;
  if FScrollY < 0 then FScrollY := 0;
  FVScroll.Position := FScrollY;
  Invalidate;
  Result := True;
end;

{ ------------------------------------------------------------------ painting }

procedure TInkRichEdit.Paint;
var
  Li, i, RunEnd, SelA, SelB, LineEndIdx, BaseY, RunTop: Integer;
  S: string;
  Sel, RunSel: Boolean;
  L: TInkVisLine;
  tm: TLCLTextMetric;
  RunAsc, RunH, Rise, X: Integer;
  GridC: TColor;
  BX, LT, LB: Integer;
  IsTbl: Boolean;

  { the grid's color: the background mixed a sixth toward the text }
  function BlendToText(ANum, ADen: Integer): TColor;
  begin
    Result := RGBToColor(
      Red(ColorToRGB(Color)) + (Red(ColorToRGB(Font.Color)) - Red(ColorToRGB(Color))) * ANum div ADen,
      Green(ColorToRGB(Color)) + (Green(ColorToRGB(Font.Color)) - Green(ColorToRGB(Color))) * ANum div ADen,
      Blue(ColorToRGB(Color)) + (Blue(ColorToRGB(Font.Color)) - Blue(ColorToRGB(Color))) * ANum div ADen);
  end;

  function IsSel(AIdx: Integer): Boolean;
  begin
    Result := (AIdx >= SelA) and (AIdx < SelB);
  end;

begin
  Canvas.Brush.Color := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  NeedLayout;
  SelA := GetSelStart;
  SelB := SelA + GetSelLength;

  for Li := 0 to High(FLines) do
  begin
    L := FLines[Li];
    if L.Top + L.Height - FScrollY < 0 then Continue;
    if L.Top - FScrollY > ClientHeight then Break;

    BaseY := L.Top - FScrollY + L.Ascent;
    LineEndIdx := L.First + L.Count;
    IsTbl := ParaKindAt(L.First) in [ipkTableHead, ipkTableRow];

    { what the paragraph is wearing: a code line's shaded band, a quote's
      bar, and a marker on a list item's first line }
    case ParaKindAt(L.First) of
      ipkCode:
        begin
          { the background mixed a twelfth toward the text color, so the
            band shows on a light editor and a dark one alike }
          Canvas.Brush.Color := RGBToColor(
            Red(ColorToRGB(Color)) + (Red(ColorToRGB(Font.Color)) - Red(ColorToRGB(Color))) div 12,
            Green(ColorToRGB(Color)) + (Green(ColorToRGB(Font.Color)) - Green(ColorToRGB(Color))) div 12,
            Blue(ColorToRGB(Color)) + (Blue(ColorToRGB(Font.Color)) - Blue(ColorToRGB(Color))) div 12);
          Canvas.Brush.Style := bsSolid;
          Canvas.FillRect(cMargin, L.Top - FScrollY,
            cMargin + LineTextWidth, L.Top - FScrollY + L.Height);
        end;
      ipkQuote:
        begin
          Canvas.Brush.Color := RGBToColor(
            (Red(ColorToRGB(Color)) + Red(ColorToRGB(Font.Color))) div 2,
            (Green(ColorToRGB(Color)) + Green(ColorToRGB(Font.Color))) div 2,
            (Blue(ColorToRGB(Color)) + Blue(ColorToRGB(Font.Color))) div 2);
          Canvas.Brush.Style := bsSolid;
          Canvas.FillRect(cMargin, L.Top - FScrollY,
            cMargin + 3, L.Top - FScrollY + L.Height);
        end;
      ipkTableHead, ipkTableRow:
        begin
          LT := L.Top - FScrollY;
          LB := LT + L.Height;
          GridC := BlendToText(1, 6);
          if ParaKindAt(L.First) = ipkTableHead then
          begin
            Canvas.Brush.Color := BlendToText(1, 14);
            Canvas.Brush.Style := bsSolid;
            Canvas.FillRect(L.Left, LT, L.Left + L.Width, LB);
          end;
          Canvas.Pen.Color := GridC;
          Canvas.Pen.Style := psSolid;
          { the frame: a top edge on the table's first row, a bottom edge
            and the two sides on every row }
          if (L.First = 0) or ((L.First > 0) and
            not (FAttrs[L.First - 1].Kind in [ipkTableHead, ipkTableRow])) then
            Canvas.Line(L.Left, LT, L.Left + L.Width, LT);
          Canvas.Line(L.Left, LB - 1, L.Left + L.Width, LB - 1);
          Canvas.Line(L.Left, LT, L.Left, LB);
          Canvas.Line(L.Left + L.Width - 1, LT, L.Left + L.Width - 1, LB);
          { and a line where each '|' hands one cell to the next }
          for BX := L.First to L.First + L.Count - 1 do
            if (BX < CharCount) and (FChars[BX] = '|') then
              Canvas.Line(L.Left + FCharX[BX] + FCharW[BX] - cCellPad, LT,
                L.Left + FCharX[BX] + FCharW[BX] - cCellPad, LB);
        end;
      ipkBullet, ipkNumber:
        if (L.First = 0) or ((L.First > 0) and (L.First <= CharCount) and
          (FChars[L.First - 1] = #10)) then
        begin
          Canvas.Font := Font;
          Canvas.Font.Color := Font.Color;
          Canvas.Brush.Style := bsClear;
          if Canvas.GetTextMetrics(tm) then
            RunAsc := tm.Ascender
          else
            RunAsc := Canvas.TextHeight('Ag') * 4 div 5;
          if ParaKindAt(L.First) = ipkBullet then
            S := #$E2#$80#$A2' '
          else
            S := IntToStr(ParaNumber(L.First)) + '. ';
          Canvas.TextOut(cMargin + Canvas.TextWidth('99. ') * ParaLevelAt(L.First),
            BaseY - RunAsc, S);
        end;
    end;

    i := L.First;
    while i < LineEndIdx do
    begin
      if (FChars[i] = #10) or (IsTbl and (FChars[i] = '|')) then
      begin
        // a selected paragraph break shows as a thin bar, so selecting across
        // paragraphs looks like it selected something; a table's '|' draws
        // as the grid, so selected it shows as its border gap highlighted
        if IsSel(i) then
        begin
          Canvas.Brush.Color := clHighlight;
          Canvas.Brush.Style := bsSolid;
          Canvas.FillRect(L.Left + FCharX[i], L.Top - FScrollY,
            L.Left + FCharX[i] + Max(4, FCharW[i]), L.Top - FScrollY + L.Height);
        end;
        Inc(i);
        Continue;
      end;

      RunSel := IsSel(i);
      RunEnd := i;
      while (RunEnd + 1 < LineEndIdx) and (FChars[RunEnd + 1] <> #10) and
        not (IsTbl and (FChars[RunEnd + 1] = '|')) and
        SameInkAttr(EffAttr(RunEnd + 1), EffAttr(i)) and
        (IsSel(RunEnd + 1) = RunSel) do
        Inc(RunEnd);

      S := '';
      for RunTop := i to RunEnd do
        S := S + FChars[RunTop];

      ApplyAttrToCanvas(EffAttr(i));
      if Canvas.GetTextMetrics(tm) then
      begin
        RunAsc := tm.Ascender;
        RunH := tm.Height;
      end
      else
      begin
        RunH := Canvas.TextHeight('Ag');
        RunAsc := RunH - (RunH div 5);
      end;
      Rise := 0;
      if FAttrs[i].Script = isSuperscript then
        Rise := (L.Ascent * 35) div 100
      else if FAttrs[i].Script = isSubscript then
        Rise := -((L.Ascent * 18) div 100);

      X := L.Left + FCharX[i];
      RunTop := BaseY - RunAsc - Rise;

      Sel := RunSel and (Focused or (SelB > SelA));
      if Sel then
      begin
        Canvas.Brush.Color := clHighlight;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(X, L.Top - FScrollY,
          L.Left + FCharX[RunEnd] + FCharW[RunEnd], L.Top - FScrollY + L.Height);
        Canvas.Font.Color := clHighlightText;
        Canvas.Brush.Style := bsClear;
      end
      else if EffAttr(i).BackColor <> clNone then
      begin
        Canvas.Brush.Color := EffAttr(i).BackColor;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(X, RunTop, L.Left + FCharX[RunEnd] + FCharW[RunEnd],
          RunTop + RunH);
        Canvas.Brush.Style := bsClear;
      end
      else
        Canvas.Brush.Style := bsClear;

      Canvas.TextOut(X, RunTop, S);
      i := RunEnd + 1;
    end;
  end;

  if Focused and FCaretOn and (GetSelLength = 0) then
  begin
    if Length(FLines) > 0 then
    begin
      Li := CaretLine(FCaret);
      X := CaretPoint(FCaret).X;
      BaseY := CaretPoint(FCaret).Y - FScrollY;
      Canvas.Pen.Color := Font.Color;
      Canvas.Line(X, BaseY + 1, X, BaseY + FLines[Li].Height - 1);
      Canvas.Line(X + 1, BaseY + 1, X + 1, BaseY + FLines[Li].Height - 1);
    end;
  end;
end;

procedure TInkRichEdit.Resize;
begin
  inherited Resize;
  InvalidateLayout;
  if FVScroll <> nil then
    UpdateScrollBar;
end;

procedure TInkRichEdit.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  InvalidateLayout;
end;

procedure TInkRichEdit.CaretTimerTick(Sender: TObject);
begin
  FCaretOn := not FCaretOn;
  Invalidate;
end;

procedure TInkRichEdit.RestartCaretBlink;
begin
  FCaretOn := True;
  if Focused then
  begin
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
  end;
end;

procedure TInkRichEdit.DoEnter;
begin
  inherited DoEnter;
  FCaretOn := True;
  FCaretTimer.Enabled := True;
  Invalidate;
end;

procedure TInkRichEdit.DoExit;
begin
  inherited DoExit;
  FCaretTimer.Enabled := False;
  FCaretOn := False;
  Invalidate;
end;

{ ------------------------------------------------------------------ document }

function TInkRichEdit.EffAttr(AIndex: Integer): TInkAttr;
begin
  Result := FAttrs[AIndex];
  AdjustAttr(AIndex, Result);
end;

procedure TInkRichEdit.AdjustAttr(AIndex: Integer; var A: TInkAttr);
begin
  { the base editor draws what the document says }
end;

function TInkRichEdit.CharAt(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FChars[AIndex]
  else
    Result := '';
end;

procedure TInkRichEdit.InsertPlainText(const AText: string);
var
  A: TInkAttr;
  Clean: string;
begin
  if FReadOnly then Exit;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  A := AttrAtCaret;
  Clean := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Clean := StringReplace(Clean, #13, #10, [rfReplaceAll]);
  DoInsert(Clean, A);
end;

function TInkRichEdit.AttrAtCaret: TInkAttr;
begin
  if FHasTypingAttr then
    Exit(FTypingAttr);
  if GetSelLength > 0 then
    Result := FAttrs[GetSelStart]
  else if (FCaret > 0) and (FCaret <= CharCount) then
    { inherit from the character to the left; right after a break that is
      the #10 itself, which carries its paragraph's kind, level and
      language - so Enter at a list's end continues the list }
    Result := FAttrs[FCaret - 1]
  else if FCaret < CharCount then
    Result := FAttrs[FCaret]
  else
    Result := DefaultInkAttr;
  Result.Link := '';                  // typing never extends a link by accident
end;

procedure TInkRichEdit.DoInsert(const AText: string; const AAttr: TInkAttr);
var
  Incoming: array of string;
  P: PChar;
  CharLen, N, i, Old: Integer;
begin
  if AText = '' then Exit;
  N := 0;
  SetLength(Incoming, UTF8Length(AText));
  P := PChar(AText);
  while P^ <> #0 do
  begin
    CharLen := UTF8CodepointSize(P);
    SetString(Incoming[N], P, CharLen);
    Inc(N);
    Inc(P, CharLen);
  end;
  if N = 0 then Exit;

  Old := CharCount;
  SetLength(FChars, Old + N);
  SetLength(FAttrs, Old + N);
  for i := Old + N - 1 downto FCaret + N do
  begin
    FChars[i] := FChars[i - N];
    FAttrs[i] := FAttrs[i - N];
  end;
  for i := 0 to N - 1 do
  begin
    FChars[FCaret + i] := Incoming[i];
    FAttrs[FCaret + i] := AAttr;
  end;
  Inc(FCaret, N);
  FAnchor := FCaret;
  Changed;
end;

procedure TInkRichEdit.DoDelete(AFrom, ATo: Integer);
var
  i, N: Integer;
begin
  if ATo <= AFrom then Exit;
  if AFrom < 0 then AFrom := 0;
  if ATo > CharCount then ATo := CharCount;
  N := ATo - AFrom;
  for i := ATo to CharCount - 1 do
  begin
    FChars[AFrom + (i - ATo)] := FChars[i];
    FAttrs[AFrom + (i - ATo)] := FAttrs[i];
  end;
  SetLength(FChars, CharCount - N);
  SetLength(FAttrs, Length(FChars));
  FCaret := AFrom;
  FAnchor := AFrom;
  Changed;
end;

procedure TInkRichEdit.DeleteSelection;
begin
  DoDelete(GetSelStart, GetSelStart + GetSelLength);
end;

procedure TInkRichEdit.Changed;
begin
  FModified := True;
  FMarkupDirty := True;
  FHasTypingAttr := False;
  InvalidateLayout;
  ScrollToCaret;
  RestartCaretBlink;
  { reading a stored document while the form loads is not a change }
  if not (csLoading in ComponentState) then
    if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.SelectionChanged;
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TInkRichEdit.Clear;
begin
  PushUndo(False);
  SetLength(FChars, 0);
  SetLength(FAttrs, 0);
  FCaret := 0;
  FAnchor := 0;
  FScrollY := 0;
  Changed;
end;

procedure TInkRichEdit.InsertParagraph;
var
  A: TInkAttr;
  PS, PE, i, K: Integer;
begin
  if FReadOnly then Exit;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  A := AttrAtCaret;
  { Enter in a table makes another row of the same columns; on a row that
    is still empty it ends the table, the way an empty item ends a list }
  if A.Kind in [ipkTableHead, ipkTableRow] then
  begin
    PS := FCaret;
    while (PS > 0) and (FChars[PS - 1] <> #10) do Dec(PS);
    PE := FCaret;
    while (PE < CharCount) and (FChars[PE] <> #10) do Inc(PE);
    i := 0;                               { the row's cells, and its words }
    for K := PS to PE - 1 do
      if FChars[K] = '|' then Inc(i)
      else if FChars[K] <> ' ' then i := i or $10000;
    if i and $10000 = 0 then
    begin
      { an empty row: the table ends here }
      DoDelete(PS, PE);
      if (PS < CharCount) and (FChars[PS] = #10) then FAttrs[PS].Kind := ipkText;
      FTypingAttr := A;
      FTypingAttr.Kind := ipkText;
      FHasTypingAttr := True;
      FModified := True;
      FMarkupDirty := True;
      InvalidateLayout;
      if Assigned(FOnChange) then FOnChange(Self);
      SelectionChanged;
      Exit;
    end;
    { a new body row with the same columns, the caret in its first cell }
    A.Kind := ipkTableRow;
    A.Link := '';
    MoveCaret(PE, False);
    DoInsert(#10 + StringOfChar('|', i and $FFFF), A);
    MoveCaret(PE + 1, False);
    Exit;
  end;
  { Enter on an empty list item or quote line steps back to plain text
    instead of making another empty one, the way every editor ends a list }
  if A.Kind in [ipkBullet, ipkNumber, ipkQuote] then
  begin
    PS := FCaret;
    while (PS > 0) and (FChars[PS - 1] <> #10) do Dec(PS);
    PE := FCaret;
    while (PE < CharCount) and (FChars[PE] <> #10) do Inc(PE);
    if PS = PE then
    begin
      { an empty nested item steps out a level first; at the top it steps
        back to plain text, as before.  At the document's end the empty
        item has no characters of its own, so its level lives on the
        typing attributes. }
      if (A.Kind in [ipkBullet, ipkNumber]) and (A.Level > 0) then
      begin
        if PE < CharCount then
          ApplyParaLevel(-1)
        else
        begin
          FTypingAttr := A;
          FTypingAttr.Level := A.Level - 1;
          FHasTypingAttr := True;
          FModified := True;
          InvalidateLayout;
          SelectionChanged;
        end;
        Exit;
      end;
      if (PE < CharCount) and (FChars[PE] = #10) then
        FAttrs[PE].Kind := ipkText;
      FTypingAttr := A;
      FTypingAttr.Kind := ipkText;
      FHasTypingAttr := True;
      FModified := True;
      FMarkupDirty := True;
      InvalidateLayout;
      if Assigned(FOnChange) then FOnChange(Self);
      SelectionChanged;
      Exit;
    end;
  end;
  DoInsert(#10, A);
  { a heading or a code line ends at its break; a list and a quote go on }
  if A.Kind in [ipkH1..ipkH6] then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Kind := ipkText;
    FTypingAttr.Style := FTypingAttr.Style - [fsBold];
    FHasTypingAttr := True;
  end;
end;

procedure TInkRichEdit.InsertTable(ACols, ARows: Integer);
var
  A, TA: TInkAttr;
  r, Home: Integer;
  RowTxt: string;
begin
  if FReadOnly then Exit;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  ACols := Max(1, ACols);
  ARows := Max(1, ARows);
  RowTxt := StringOfChar('|', ACols - 1);
  A := AttrAtCaret;
  A.Link := '';
  { the table starts on a line of its own }
  if (FCaret > 0) and (FChars[FCaret - 1] <> #10) then DoInsert(#10, A);
  Home := FCaret;
  TA := A;
  TA.Kind := ipkTableHead;
  DoInsert(RowTxt, TA);
  TA.Kind := ipkTableRow;
  for r := 1 to ARows do
    DoInsert(#10 + RowTxt, TA);
  { and plain text follows it - the break belongs to the last row }
  if (FCaret >= CharCount) or (FChars[FCaret] <> #10) then
    DoInsert(#10, TA);
  FTypingAttr := A;
  FTypingAttr.Kind := ipkText;
  FHasTypingAttr := False;
  MoveCaret(Home, False);
end;

{ -------------------------------------------------------------- formatting  }

procedure TInkRichEdit.ApplyStyle(AStyle: TFontStyle; AOn: Boolean);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    if AOn then
      FTypingAttr.Style := FTypingAttr.Style + [AStyle]
    else
      FTypingAttr.Style := FTypingAttr.Style - [AStyle];
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    if AOn then
      FAttrs[i].Style := FAttrs[i].Style + [AStyle]
    else
      FAttrs[i].Style := FAttrs[i].Style - [AStyle];
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ToggleStyle(AStyle: TFontStyle);
begin
  ApplyStyle(AStyle, not (AStyle in SelStyle));
end;

{ The four value-setters below all do the same dance, so they share it. }
procedure TInkRichEdit.ApplyColor(AColor: TColor);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Color := AColor;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Color := AColor;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyBackColor(AColor: TColor);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.BackColor := AColor;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].BackColor := AColor;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplySize(ASize: Integer);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Size := ASize;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Size := ASize;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyFace(const AFace: string);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Face := AFace;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Face := AFace;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyScript(AScript: TInkScript);
var
  i: Integer;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Script := AScript;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Script := AScript;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyLink(const AHref: string);
var
  i: Integer;
begin
  if FReadOnly or (GetSelLength = 0) then Exit;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    FAttrs[i].Link := AHref;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ Alignment belongs to whole paragraphs, so the selection is widened out to
  paragraph boundaries before it is applied. }
procedure TInkRichEdit.ApplyAlignment(AAlign: TAlignment);
var
  i, A, B: Integer;
begin
  if FReadOnly or (CharCount = 0) then Exit;
  PushUndo(False);
  A := GetSelStart;
  B := GetSelStart + GetSelLength;
  while (A > 0) and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> #10) do Inc(B);
  for i := A to B - 1 do
    FAttrs[i].Align := AAlign;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ApplyParaKind(AKind: TInkParaKind);
var
  i, A, B: Integer;
begin
  if FReadOnly then Exit;
  if CharCount = 0 then
  begin
    { an empty document: the kind is what the first typed character wears }
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Kind := AKind;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  A := GetSelStart;
  B := GetSelStart + GetSelLength;
  while (A > 0) and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> #10) do Inc(B);
  { the paragraph's #10 carries the kind too, so an empty paragraph keeps it }
  if (B < CharCount) and (FChars[B] = #10) then Inc(B);
  for i := A to B - 1 do
    FAttrs[i].Kind := AKind;
  if FHasTypingAttr then FTypingAttr.Kind := AKind;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ the list items the selection touches step ADelta levels deeper (or back
  out); five levels is as deep as anyone can read }
procedure TInkRichEdit.ApplyParaLevel(ADelta: Integer);
var
  i, A, B, L: Integer;
begin
  if FReadOnly or (CharCount = 0) then Exit;
  PushUndo(False);
  A := GetSelStart;
  B := GetSelStart + GetSelLength;
  while (A > 0) and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> #10) do Inc(B);
  if (B < CharCount) and (FChars[B] = #10) then Inc(B);
  for i := A to B - 1 do
    if FAttrs[i].Kind in [ipkBullet, ipkNumber] then
    begin
      L := EnsureRange(Integer(FAttrs[i].Level) + ADelta, 0, 5);
      FAttrs[i].Level := L;
    end;
  if FHasTypingAttr then
    FTypingAttr.Level := EnsureRange(Integer(FTypingAttr.Level) + ADelta, 0, 5);
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ClearFormatting;
var
  i: Integer;
  Keep: TAlignment;
  KeepKind: TInkParaKind;
begin
  if FReadOnly then Exit;
  if GetSelLength = 0 then
  begin
    FTypingAttr := DefaultInkAttr;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
  begin
    Keep := FAttrs[i].Align;          // alignment is not character formatting
    KeepKind := FAttrs[i].Kind;       // and neither is what the paragraph is
    FAttrs[i] := DefaultInkAttr;
    FAttrs[i].Align := Keep;
    FAttrs[i].Kind := KeepKind;
  end;
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ ------------------------------------------------------- selection queries  }

function TInkRichEdit.SelStyle: TFontStyles;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Style);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Style);
  Result := FAttrs[A].Style;
  for i := A + 1 to B - 1 do
    Result := Result * FAttrs[i].Style;   // only what every character agrees on
end;

function TInkRichEdit.SelColor: TColor;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Color);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Color);
  Result := FAttrs[A].Color;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Color <> Result then Exit(clDefault);
end;

function TInkRichEdit.SelBackColor: TColor;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.BackColor);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.BackColor);
  Result := FAttrs[A].BackColor;
  for i := A + 1 to B - 1 do
    if FAttrs[i].BackColor <> Result then Exit(clNone);
end;

function TInkRichEdit.SelSize: Integer;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Size);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Size);
  Result := FAttrs[A].Size;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Size <> Result then Exit(0);
end;

function TInkRichEdit.SelFace: string;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Face);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Face);
  Result := FAttrs[A].Face;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Face <> Result then Exit('');
end;

function TInkRichEdit.SelScript: TInkScript;
var
  i, A, B: Integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Script);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Script);
  Result := FAttrs[A].Script;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Script <> Result then Exit(isNormal);
end;

function TInkRichEdit.SelAlignment: TAlignment;
begin
  if CharCount = 0 then Exit(taLeftJustify);
  if FCaret < CharCount then
    Result := FAttrs[FCaret].Align
  else
    Result := FAttrs[CharCount - 1].Align;
end;

function TInkRichEdit.SelParaKind: TInkParaKind;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Kind);
  if CharCount = 0 then Exit(ipkText);
  if FCaret < CharCount then
    Result := FAttrs[FCaret].Kind
  else
    Result := FAttrs[CharCount - 1].Kind;
end;

{ ----------------------------------------------------------------- keyboard }

procedure TInkRichEdit.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  case Message.CharCode of
    VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_PRIOR, VK_NEXT,
    VK_RETURN:
      Message.Result := 1;      // an editor eats its own navigation keys
    VK_TAB:
      // in a table Tab hops cells, in a list it changes the nesting,
      // instead of leaving the control
      if SelParaKind in [ipkTableHead, ipkTableRow, ipkBullet, ipkNumber] then
        Message.Result := 1
      else
        inherited;
  else
    inherited;
  end;
end;

procedure TInkRichEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  Ext: Boolean;
  L, Target, i, Best, BestDX, DX: Integer;
  P: TPoint;

  { Home/End within the visual line the caret sits on }
  function LineHome(ALine: Integer): Integer;
  begin
    Result := FLines[ALine].First;
  end;

  function LineEnd(ALine: Integer): Integer;
  begin
    Result := FLines[ALine].First + FLines[ALine].Count;
    if (FLines[ALine].Count > 0) and (FChars[Result - 1] = #10) then Dec(Result);
  end;

  { Tab in a table: the caret to the start of the next cell, into the next
    row's first cell past the last one, and a new row past the table's end.
    Shift takes it back the same way. }
  procedure TableHop(ABack: Boolean);
  var
    RS, RE, C: Integer;
  begin
    RS := FCaret;
    while (RS > 0) and (FChars[RS - 1] <> #10) do Dec(RS);
    RE := FCaret;
    while (RE < CharCount) and (FChars[RE] <> #10) do Inc(RE);
    if not ABack then
    begin
      C := FCaret;
      while (C < RE) and (FChars[C] <> '|') do Inc(C);
      if C < RE then
        MoveCaret(C + 1, False)
      else if (RE + 1 < CharCount) and
        (FAttrs[RE + 1].Kind in [ipkTableHead, ipkTableRow]) and
        (FChars[RE] = #10) then
        MoveCaret(RE + 1, False)
      else
      begin
        { past the last cell of the last row: another row }
        MoveCaret(RE, False);
        InsertParagraph;
      end;
    end
    else
    begin
      { the start of this cell, or of the one before it, or of the row above }
      C := FCaret - 1;
      while (C >= RS) and (FChars[C] <> '|') do Dec(C);
      if C >= RS then
      begin
        { at a cell's own start already?  then the cell before it }
        if C + 1 = FCaret then
        begin
          Dec(C);
          while (C >= RS) and (FChars[C] <> '|') do Dec(C);
        end;
        if C >= RS then MoveCaret(C + 1, False) else MoveCaret(RS, False);
      end
      else if FCaret > RS then
        MoveCaret(RS, False)
      else if (RS >= 2) and (FAttrs[RS - 2].Kind in [ipkTableHead, ipkTableRow]) then
      begin
        { the last cell of the row above }
        C := RS - 2;
        while (C >= 0) and (FChars[C] <> #10) and (FChars[C] <> '|') do Dec(C);
        MoveCaret(C + 1, False);
      end;
    end;
    FGoalX := -1;
  end;

begin
  inherited KeyDown(Key, Shift);
  if Key = 0 then Exit;
  NeedLayout;
  Ext := ssShift in Shift;

  case Key of
    VK_TAB:
      if SelParaKind in [ipkTableHead, ipkTableRow] then
      begin
        TableHop(ssShift in Shift);
        Key := 0;
      end
      else if SelParaKind in [ipkBullet, ipkNumber] then
      begin
        { a list item steps deeper on Tab and back out on Shift+Tab }
        if ssShift in Shift then
          ApplyParaLevel(-1)
        else
          ApplyParaLevel(1);
        Key := 0;
      end;
    VK_LEFT:
      begin
        if (GetSelLength > 0) and not Ext then
          MoveCaret(GetSelStart, False)
        else
          MoveCaret(FCaret - 1, Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if (GetSelLength > 0) and not Ext then
          MoveCaret(GetSelStart + GetSelLength, False)
        else
          MoveCaret(FCaret + 1, Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
      begin
        if Length(FLines) > 0 then
        begin
          P := CaretPoint(FCaret);
          if FGoalX < 0 then FGoalX := P.X;
          L := CaretLine(FCaret);
          case Key of
            VK_UP: Target := L - 1;
            VK_DOWN: Target := L + 1;
            VK_PRIOR: Target := L - Max(1, ClientHeight div Max(FLines[L].Height, 1));
          else
            Target := L + Max(1, ClientHeight div Max(FLines[L].Height, 1));
          end;
          if Target < 0 then Target := 0;
          if Target > High(FLines) then Target := High(FLines);

          // land on whichever character on the target line is nearest the
          // column we set out from, so up-then-down comes back where it began
          Best := LineHome(Target);
          BestDX := MaxInt;
          for i := LineHome(Target) to LineEnd(Target) do
          begin
            if i < FLines[Target].First + FLines[Target].Count then
              DX := Abs(FLines[Target].Left + FCharX[i] - FGoalX)
            else
              DX := Abs(FLines[Target].Left + FLines[Target].Width - FGoalX);
            if i = LineEnd(Target) then
              DX := Abs(FLines[Target].Left + FLines[Target].Width - FGoalX);
            if DX < BestDX then
            begin
              BestDX := DX;
              Best := i;
            end;
          end;
          L := FGoalX;
          MoveCaret(Best, Ext);
          FGoalX := L;              // MoveCaret must not forget the column
        end;
        Key := 0;
      end;
    VK_HOME:
      begin
        if ssCtrl in Shift then
          MoveCaret(0, Ext)
        else
          MoveCaret(LineHome(CaretLine(FCaret)), Ext);
        FGoalX := -1;
        Key := 0;
      end;
    VK_END:
      begin
        if ssCtrl in Shift then
          MoveCaret(CharCount, Ext)
        else
        begin
          MoveCaret(LineEnd(CaretLine(FCaret)), Ext);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_RETURN:
      begin
        if not FReadOnly then InsertParagraph;
        FGoalX := -1;
        Key := 0;
      end;
    VK_BACK:
      begin
        if not FReadOnly then
        begin
          PushUndo(True);
          if GetSelLength > 0 then
            DeleteSelection
          else if FCaret > 0 then
            DoDelete(FCaret - 1, FCaret);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_DELETE:
      begin
        if not FReadOnly then
        begin
          PushUndo(True);
          if GetSelLength > 0 then
            DeleteSelection
          else if FCaret < CharCount then
            DoDelete(FCaret, FCaret + 1);
        end;
        FGoalX := -1;
        Key := 0;
      end;
    VK_A: if ssCtrl in Shift then begin SelectAll; Key := 0; end;
    VK_C: if ssCtrl in Shift then begin CopyToClipboard; Key := 0; end;
    VK_X: if ssCtrl in Shift then begin CutToClipboard; Key := 0; end;
    VK_V: if ssCtrl in Shift then begin PasteFromClipboard; Key := 0; end;
    VK_Z: if ssCtrl in Shift then
          begin
            if ssShift in Shift then Redo else Undo;
            Key := 0;
          end;
    VK_Y: if ssCtrl in Shift then begin Redo; Key := 0; end;
    VK_B: if ssCtrl in Shift then begin ToggleStyle(fsBold); Key := 0; end;
    VK_I: if ssCtrl in Shift then begin ToggleStyle(fsItalic); Key := 0; end;
    VK_U: if ssCtrl in Shift then begin ToggleStyle(fsUnderline); Key := 0; end;
  end;
end;

procedure TInkRichEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  A: TInkAttr;
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < #32) then Exit;
  if FReadOnly then Exit;

  A := AttrAtCaret;
  PushUndo(True);
  if GetSelLength > 0 then DeleteSelection;
  DoInsert(UTF8Key, A);
  FGoalX := -1;
  UTF8Key := '';
end;

{ -------------------------------------------------------------------- mouse }

procedure TInkRichEdit.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if CanSetFocus then SetFocus;
    FCaret := PointToCaret(X, Y);
    if not (ssShift in Shift) then FAnchor := FCaret;
    FGoalX := -1;
    FHasTypingAttr := False;
    RestartCaretBlink;
    Invalidate;
    SelectionChanged;
  end;
end;

procedure TInkRichEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if ssLeft in Shift then
  begin
    FCaret := PointToCaret(X, Y);
    ScrollToCaret;
    Invalidate;
    SelectionChanged;
    Exit;
  end;

  FMouseOnLink := False;
  FHoverLink := '';
  Idx := PointToCaret(X, Y);
  if (Idx >= 0) and (Idx < CharCount) and (FAttrs[Idx].Link <> '') then
  begin
    FMouseOnLink := True;
    FHoverLink := FAttrs[Idx].Link;
  end;
  if FMouseOnLink and (ssCtrl in Shift) then
    Cursor := crHandPoint
  else
    Cursor := crIBeam;
end;

procedure TInkRichEdit.Click;
begin
  inherited Click;
  // ctrl+click follows a link; a plain click has to keep placing the caret,
  // or the text under a link would be uneditable
  if FMouseOnLink and (FHoverLink <> '') and Assigned(FOnLinkClick) and
    (GetKeyState(VK_CONTROL) < 0) then
    FOnLinkClick(Self, FHoverLink);
end;

procedure TInkRichEdit.DblClick;
var
  A, B: Integer;
begin
  inherited DblClick;
  if CharCount = 0 then Exit;
  A := Min(FCaret, CharCount - 1);
  B := A;
  while (A > 0) and (FChars[A - 1] <> ' ') and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> ' ') and (FChars[B] <> #10) do Inc(B);
  FAnchor := A;
  FCaret := B;
  Invalidate;
  SelectionChanged;
end;

{ ---------------------------------------------------------------- clipboard */ }

procedure TInkRichEdit.CopyToClipboard;
var
  i, A, N: Integer;
begin
  if GetSelLength = 0 then Exit;
  A := GetSelStart;
  N := GetSelLength;
  gClipText := GetSelText;
  SetLength(gClipAttrs, N);
  for i := 0 to N - 1 do
    gClipAttrs[i] := FAttrs[A + i];
  Clipboard.AsText := gClipText;
end;

procedure TInkRichEdit.CutToClipboard;
begin
  CopyToClipboard;
  if FReadOnly or (GetSelLength = 0) then Exit;
  PushUndo(False);
  DeleteSelection;
end;

procedure TInkRichEdit.MenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    1: Undo;
    2: Redo;
    3: CutToClipboard;
    4: CopyToClipboard;
    5: PasteFromClipboard;
    6: if (not FReadOnly) and (GetSelLength > 0) then
       begin
         PushUndo(False);
         DeleteSelection;
         FMarkupDirty := True;
         InvalidateLayout;
         if Assigned(FOnChange) then FOnChange(Self);
       end;
    7: SelectAll;
  end;
end;

procedure TInkRichEdit.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;

  procedure AddItem(const ACaption: string; ATag: Integer; AEnabled: Boolean);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(FMenu);
    It.Caption := ACaption;
    It.Tag := ATag;
    It.Enabled := AEnabled;
    It.OnClick := @MenuClick;
    FMenu.Items.Add(It);
  end;

begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or (PopupMenu <> nil) or not FEditMenu then Exit;
  Handled := True;
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(Self);
  if not FReadOnly then
  begin
    AddItem(SInkEditUndo, 1, CanUndo);
    AddItem(SInkEditRedo, 2, CanRedo);
    AddItem('-', 0, True);
    AddItem(SInkEditCut, 3, GetSelLength > 0);
  end;
  AddItem(SInkEditCopy, 4, GetSelLength > 0);
  if not FReadOnly then
  begin
    AddItem(SInkEditPaste, 5, Clipboard.HasFormat(CF_TEXT));
    AddItem(SInkEditDelete, 6, GetSelLength > 0);
  end;
  AddItem('-', 0, True);
  AddItem(SInkEditSelectAll, 7, CharCount > 0);
  P := ClientToScreen(MousePos);
  FMenu.PopUp(P.X, P.Y);
end;

procedure TInkRichEdit.PasteFromClipboard;
var
  S: string;
  i, At: Integer;
  A: TInkAttr;
begin
  if FReadOnly then Exit;
  if not Clipboard.HasFormat(CF_TEXT) then Exit;
  S := Clipboard.AsText;
  if S = '' then Exit;

  A := AttrAtCaret;
  PushUndo(False);
  if GetSelLength > 0 then DeleteSelection;
  At := FCaret;

  S := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  S := StringReplace(S, #13, #10, [rfReplaceAll]);
  DoInsert(S, A);

  // same text we put there, so the formatting that went with it is still good
  if (gClipText <> '') and (Length(gClipAttrs) > 0) and
     (StringReplace(gClipText, LineEnding, #10, [rfReplaceAll]) = S) then
    for i := 0 to Length(gClipAttrs) - 1 do
      if At + i < CharCount then
        FAttrs[At + i] := gClipAttrs[i];
  InvalidateLayout;
end;

{ --------------------------------------------------------------------- undo */ }

function TInkRichEdit.TakeSnapshot: TObject;
var
  S: TInkSnapshot;
  i: Integer;
begin
  S := TInkSnapshot.Create;
  SetLength(S.Chars, CharCount);
  SetLength(S.Attrs, CharCount);
  for i := 0 to CharCount - 1 do
  begin
    S.Chars[i] := FChars[i];
    S.Attrs[i] := FAttrs[i];
  end;
  S.Caret := FCaret;
  S.Anchor := FAnchor;
  Result := S;
end;

procedure TInkRichEdit.RestoreSnapshot(ASnap: TObject);
var
  S: TInkSnapshot;
  i: Integer;
begin
  S := TInkSnapshot(ASnap);
  SetLength(FChars, Length(S.Chars));
  SetLength(FAttrs, Length(S.Attrs));
  for i := 0 to High(S.Chars) do
  begin
    FChars[i] := S.Chars[i];
    FAttrs[i] := S.Attrs[i];
  end;
  FCaret := Min(S.Caret, CharCount);
  FAnchor := Min(S.Anchor, CharCount);
  Changed;
end;

procedure TInkRichEdit.ClearUndoList(AList: TFPList);
var
  i: Integer;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    TObject(AList[i]).Free;
  AList.Clear;
end;

{ ACoalesce folds a run of keystrokes into one undo step, so ctrl+Z takes back
  a word rather than a letter. }
procedure TInkRichEdit.PushUndo(ACoalesce: Boolean);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  if ACoalesce and (FUndo.Count > 0) and (Now - FLastUndoTick < cUndoCoalesceMs) then
  begin
    FLastUndoTick := Now;
    Exit;
  end;
  FLastUndoTick := Now;
  FUndo.Add(TakeSnapshot);
  while FUndo.Count > cUndoDepth do
  begin
    TObject(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
  ClearUndoList(FRedo);
end;

function TInkRichEdit.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

function TInkRichEdit.CanRedo: Boolean;
begin
  Result := FRedo.Count > 0;
end;

procedure TInkRichEdit.Undo;
var
  Snap: TObject;
begin
  if FUndo.Count = 0 then Exit;
  FRedo.Add(TakeSnapshot);
  Snap := TObject(FUndo[FUndo.Count - 1]);
  FUndo.Delete(FUndo.Count - 1);
  RestoreSnapshot(Snap);
  Snap.Free;
  FLastUndoTick := 0;
end;

procedure TInkRichEdit.Redo;
var
  Snap: TObject;
begin
  if FRedo.Count = 0 then Exit;
  FUndo.Add(TakeSnapshot);
  Snap := TObject(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  RestoreSnapshot(Snap);
  Snap.Free;
  FLastUndoTick := 0;
end;

{ ------------------------------------------------------------------- markup */ }

procedure TInkRichEdit.SetReadOnly(AValue: Boolean);
begin
  FReadOnly := AValue;
end;

procedure TInkRichEdit.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  InvalidateLayout;
end;

function TInkRichEdit.GetMarkup: TStrings;
begin
  if FMarkupDirty then SyncMarkupFromDoc;
  Result := FMarkup;
end;

procedure TInkRichEdit.SetMarkup(AValue: TStrings);
begin
  FMarkup.Assign(AValue);   // fires MarkupChanged, which rebuilds the document
end;

procedure TInkRichEdit.MarkupChanged(Sender: TObject);
begin
  if FSettingMarkup then Exit;   // this is our own SyncMarkupFromDoc talking
  RebuildFromMarkup;
end;

procedure TInkRichEdit.RebuildFromMarkup;
var
  i: Integer;
begin
  FSettingMarkup := True;
  try
    SetLength(FChars, 0);
    SetLength(FAttrs, 0);
    for i := 0 to FMarkup.Count - 1 do
      ParseInto(FMarkup[i], i > 0);
    { the #10 between paragraphs was emitted before its paragraph's wrapper
      was read: give each one the kind, level and language of the paragraph
      it ends }
    for i := High(FChars) downto 1 do
      if (FChars[i] = #10) and (FChars[i - 1] <> #10) then
      begin
        FAttrs[i].Kind := FAttrs[i - 1].Kind;
        FAttrs[i].Level := FAttrs[i - 1].Level;
        FAttrs[i].Lang := FAttrs[i - 1].Lang;
      end;
    FCaret := 0;
    FAnchor := 0;
    FScrollY := 0;
    FHasTypingAttr := False;
    FMarkupDirty := False;
    ClearUndoList(FUndo);
    ClearUndoList(FRedo);
    FModified := False;
    InvalidateLayout;
  finally
    FSettingMarkup := False;
  end;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

{ Reads one paragraph of markup onto the end of the document. A stack of
  attributes mirrors the tag nesting: an opening tag pushes a modified copy,
  a closing tag pops back to what was in force before it. }
procedure TInkRichEdit.ParseInto(const AMarkup: string; AParaBreakFirst: Boolean);
var
  Stack: array of TInkAttr;
  Cur: TInkAttr;
  P, Len, Start, N: Integer;
  TagStr, Nm, Val: string;
  Body: string;
  Up: string;

  procedure Push;
  begin
    SetLength(Stack, Length(Stack) + 1);
    Stack[High(Stack)] := Cur;
  end;

  procedure Pop;
  begin
    if Length(Stack) = 0 then Exit;
    Cur := Stack[High(Stack)];
    SetLength(Stack, Length(Stack) - 1);
  end;

  procedure Emit(const S: string);
  var
    Q: PChar;
    CharLen, Old, k: Integer;
    Txt: string;
  begin
    if S = '' then Exit;
    Txt := S;
    Old := CharCount;
    k := UTF8Length(Txt);
    SetLength(FChars, Old + k);
    SetLength(FAttrs, Old + k);
    Q := PChar(Txt);
    k := Old;
    while Q^ <> #0 do
    begin
      CharLen := UTF8CodepointSize(Q);
      SetString(FChars[k], Q, CharLen);
      FAttrs[k] := Cur;
      Inc(k);
      Inc(Q, CharLen);
    end;
  end;

  procedure EmitBreak;
  begin
    SetLength(FChars, CharCount + 1);
    SetLength(FAttrs, Length(FChars));
    FChars[High(FChars)] := #10;
    FAttrs[High(FAttrs)] := Cur;
  end;

  { The value of APropName inside ATag, in the case it was written in - a font
    family name is not case insensitive to the font matcher. }
  function PropOf(const ATag, APropName: string): string;
  var
    ip, j: Integer;
    R: string;
    Q: Char;
  begin
    Result := '';
    ip := Pos(APropName, UpperCase(ATag));
    if ip = 0 then Exit;
    R := Copy(ATag, ip + Length(APropName), Length(ATag));
    R := TrimLeft(R);
    if (R = '') or (R[1] <> '=') then Exit;
    Delete(R, 1, 1);
    R := TrimLeft(R);
    if R = '' then Exit;
    if (R[1] = '"') or (R[1] = '''') then
    begin
      Q := R[1];
      Delete(R, 1, 1);
      j := Pos(Q, R);
      if j > 0 then
        Result := Copy(R, 1, j - 1)
      else
        Result := R;
    end
    else
    begin
      j := 1;
      while (j <= Length(R)) and (R[j] <> ' ') and (R[j] <> '>') and
        (R[j] <> #9) and (R[j] <> '/') do
        Inc(j);
      Result := Copy(R, 1, j - 1);
    end;
  end;

begin
  Cur := DefaultInkAttr;
  if AParaBreakFirst then EmitBreak;

  Body := AMarkup;
  P := 1;
  Len := Length(Body);
  while P <= Len do
  begin
    if Body[P] = '<' then
    begin
      Start := P;
      while (P <= Len) and (Body[P] <> '>') do Inc(P);
      if P <= Len then Inc(P);
      TagStr := Copy(Body, Start, P - Start);
      Up := UpperCase(TagStr);
      Nm := '';
      N := 2;
      if (N <= Length(Up)) and (Up[N] = '/') then
      begin
        Nm := '/';
        Inc(N);
      end;
      while (N <= Length(Up)) and (Up[N] in ['A'..'Z', '0'..'9']) do
      begin
        Nm := Nm + Up[N];
        Inc(N);
      end;

      if (Nm = 'BR') or (Nm = 'P') or (Nm = '/P') then
        EmitBreak
      else if Nm = 'B' then begin Push; Cur.Style := Cur.Style + [fsBold]; end
      else if Nm = 'I' then begin Push; Cur.Style := Cur.Style + [fsItalic]; end
      else if Nm = 'U' then begin Push; Cur.Style := Cur.Style + [fsUnderline]; end
      else if (Nm = 'S') or (Nm = 'STRIKE') then
        begin Push; Cur.Style := Cur.Style + [fsStrikeOut]; end
      else if Nm = 'SUP' then begin Push; Cur.Script := isSuperscript; end
      else if Nm = 'SUB' then begin Push; Cur.Script := isSubscript; end
      else if Nm = 'CENTER' then begin Push; Cur.Align := taCenter; end
      else if Nm = 'RIGHT' then begin Push; Cur.Align := taRightJustify; end
      else if (Length(Nm) = 2) and (Nm[1] = 'H') and (Nm[2] in ['1'..'6']) then
        begin Push; Cur.Kind := TInkParaKind(Ord(ipkH1) + Ord(Nm[2]) - Ord('1')); end
      else if Nm = 'LI' then
      begin
        Push;
        Cur.Kind := ipkBullet;
        Cur.Level := EnsureRange(StrToIntDef(PropOf(TagStr, 'LEVEL'), 0), 0, 5);
      end
      else if Nm = 'OLI' then
      begin
        Push;
        Cur.Kind := ipkNumber;
        Cur.Level := EnsureRange(StrToIntDef(PropOf(TagStr, 'LEVEL'), 0), 0, 5);
      end
      else if Nm = 'BLOCKQUOTE' then begin Push; Cur.Kind := ipkQuote; end
      else if Nm = 'PRE' then
      begin
        Push;
        Cur.Kind := ipkCode;
        Cur.Lang := PropOf(TagStr, 'LANG');
      end
      else if Nm = 'TH' then begin Push; Cur.Kind := ipkTableHead; end
      else if Nm = 'TR' then begin Push; Cur.Kind := ipkTableRow; end
      else if Nm = 'A' then
      begin
        Push;
        Val := PropOf(TagStr, 'HREF');
        if Val <> '' then Cur.Link := Val;
      end
      else if Nm = 'FONT' then
      begin
        Push;
        Val := PropOf(TagStr, 'BGCOLOR');
        if Val <> '' then Cur.BackColor := HTMLStringToColor(Val, clNone);
        // "BGCOLOR" ends in "COLOR", so looking for the shorter name in the
        // raw tag finds the longer one and paints the text in its own
        // background. Mask it out first.
        Val := PropOf(StringReplace(TagStr, 'bgcolor', '#######',
          [rfReplaceAll, rfIgnoreCase]), 'COLOR');
        if Val <> '' then Cur.Color := HTMLStringToColor(Val, clDefault);
        Val := PropOf(TagStr, 'SIZE');
        if Val <> '' then Cur.Size := StrToIntDef(Val, 0);
        Val := PropOf(TagStr, 'FACE');
        if Val <> '' then Cur.Face := Val;
      end
      else if (Length(Nm) > 1) and (Nm[1] = '/') then
        Pop;
      Continue;
    end;

    Start := P;
    while (P <= Len) and (Body[P] <> '<') do Inc(P);
    Emit(HTMLUnescape(Copy(Body, Start, P - Start)));
  end;
end;

{ Writes the document back out as markup.

  Characters are gathered into runs that share an attribute, and each run's
  tags are matched against what is already open: the common prefix stays, the
  rest is closed innermost-first and the new tags opened. That way a paragraph
  of bold text with one red word in it comes out as <b>ab <font
  color="#FF0000">cd</font> ef</b>, not as a fresh <b> around every run.

  Ordering is fixed - a, font, b, i, u, s, sup/sub - so that two runs wanting
  the same tags always produce the same prefix and the comparison is
  meaningful. <a> is outermost because the renderer restores the whole font
  at </a>. }
procedure TInkRichEdit.SyncMarkupFromDoc;
const
  cMaxTags = 8;
var
  Line, Body: string;
  i, RunEnd, k, NOpen, NWant: Integer;
  OpenName, OpenTag: array[0..cMaxTags - 1] of string;
  WantName, WantTag: array[0..cMaxTags - 1] of string;
  ParaAlign: TAlignment;
  ParaKind: TInkParaKind;
  ParaLevel: Integer;
  ParaLang: string;

  procedure CloseDownTo(ALevel: Integer);
  var
    j: Integer;
  begin
    for j := NOpen - 1 downto ALevel do
      Line := Line + '</' + OpenName[j] + '>';
    NOpen := ALevel;
  end;

  procedure AddWant(const AName, ATag: string);
  begin
    if NWant >= cMaxTags then Exit;
    WantName[NWant] := AName;
    WantTag[NWant] := ATag;
    Inc(NWant);
  end;

  procedure BuildWant(const A: TInkAttr);
  var
    F, C: string;
  begin
    NWant := 0;
    if A.Link <> '' then
      AddWant('a', '<a href="' + A.Link + '">');
    F := '';
    C := InkColorToHTML(A.Color);
    if C <> '' then F := F + ' color="' + C + '"';
    C := InkColorToHTML(A.BackColor);
    if C <> '' then F := F + ' bgcolor="' + C + '"';
    if A.Size > 0 then F := F + ' size="' + IntToStr(A.Size) + '"';
    if A.Face <> '' then F := F + ' face="' + A.Face + '"';
    if F <> '' then AddWant('font', '<font' + F + '>');
    if fsBold in A.Style then AddWant('b', '<b>');
    if fsItalic in A.Style then AddWant('i', '<i>');
    if fsUnderline in A.Style then AddWant('u', '<u>');
    if fsStrikeOut in A.Style then AddWant('s', '<s>');
    if A.Script = isSuperscript then AddWant('sup', '<sup>');
    if A.Script = isSubscript then AddWant('sub', '<sub>');
  end;

  { Nothing about an attribute says which of its tags ought to be outermost, so
    the canonical order above is arbitrary - and an arbitrary order re-emits
    tags that were perfectly good. Reordering each run's tags to lead with the
    ones already open (for as long as they match, since the stack can only be
    reused as a prefix) keeps <b>ab<font color=..>cd</font>ef</b> from turning
    into three separate <b> runs. }
  procedure OrderWantForReuse;
  var
    j, m, Cnt, Found: Integer;
    Used: array[0..cMaxTags - 1] of Boolean;
    TmpName, TmpTag: array[0..cMaxTags - 1] of string;
  begin
    for j := 0 to cMaxTags - 1 do
      Used[j] := False;
    Cnt := 0;
    for j := 0 to NOpen - 1 do
    begin
      Found := -1;
      for m := 0 to NWant - 1 do
        if (not Used[m]) and (WantTag[m] = OpenTag[j]) then
        begin
          Found := m;
          Break;
        end;
      if Found < 0 then Break;
      TmpName[Cnt] := WantName[Found];
      TmpTag[Cnt] := WantTag[Found];
      Used[Found] := True;
      Inc(Cnt);
    end;
    for m := 0 to NWant - 1 do
      if not Used[m] then
      begin
        TmpName[Cnt] := WantName[m];
        TmpTag[Cnt] := WantTag[m];
        Inc(Cnt);
      end;
    for j := 0 to Cnt - 1 do
    begin
      WantName[j] := TmpName[j];
      WantTag[j] := TmpTag[j];
    end;
    NWant := Cnt;
  end;

  procedure EndParagraph;
  const
    cKindTag: array[TInkParaKind] of string =
      ('', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'oli', 'blockquote', 'pre',
       'th', 'tr');
  begin
    CloseDownTo(0);
    case ParaAlign of
      taCenter: Line := '<center>' + Line + '</center>';
      taRightJustify: Line := '<right>' + Line + '</right>';
      taLeftJustify: ;   // the default needs no wrapper
    end;
    { the paragraph's kind is the outermost wrapper, carrying a list
      item's nesting and a code line's fence language }
    if ParaKind <> ipkText then
    begin
      Body := '<' + cKindTag[ParaKind];
      if (ParaKind in [ipkBullet, ipkNumber]) and (ParaLevel > 0) then
        Body := Body + ' level="' + IntToStr(ParaLevel) + '"';
      if (ParaKind = ipkCode) and (ParaLang <> '') then
        Body := Body + ' lang="' + ParaLang + '"';
      Line := Body + '>' + Line + '</' + cKindTag[ParaKind] + '>';
    end;
    FMarkup.Add(Line);
    Line := '';
  end;

begin
  FSettingMarkup := True;
  try
    FMarkup.Clear;
    Line := '';
    NOpen := 0;
    for k := 0 to cMaxTags - 1 do
    begin
      OpenName[k] := '';
      OpenTag[k] := '';
      WantName[k] := '';
      WantTag[k] := '';
    end;
    if CharCount > 0 then ParaAlign := FAttrs[0].Align else ParaAlign := taLeftJustify;
    if CharCount > 0 then ParaKind := FAttrs[0].Kind else ParaKind := ipkText;
    if CharCount > 0 then ParaLevel := FAttrs[0].Level else ParaLevel := 0;
    if CharCount > 0 then ParaLang := FAttrs[0].Lang else ParaLang := '';

    i := 0;
    while i <= CharCount do
    begin
      if (i = CharCount) or (FChars[i] = #10) then
      begin
        EndParagraph;
        Inc(i);
        if i < CharCount then
        begin
          ParaAlign := FAttrs[i].Align;
          ParaKind := FAttrs[i].Kind;
          ParaLevel := FAttrs[i].Level;
          ParaLang := FAttrs[i].Lang;
        end
        else
        begin
          ParaAlign := taLeftJustify;
          ParaKind := ipkText;
          ParaLevel := 0;
          ParaLang := '';
        end;
        Continue;
      end;

      RunEnd := i;
      while (RunEnd + 1 < CharCount) and (FChars[RunEnd + 1] <> #10) and
        SameInkAttr(FAttrs[RunEnd + 1], FAttrs[i]) do
        Inc(RunEnd);

      BuildWant(FAttrs[i]);
      OrderWantForReuse;
      k := 0;
      while (k < NOpen) and (k < NWant) and (OpenTag[k] = WantTag[k]) do
        Inc(k);
      CloseDownTo(k);
      while k < NWant do
      begin
        Line := Line + WantTag[k];
        OpenName[NOpen] := WantName[k];
        OpenTag[NOpen] := WantTag[k];
        Inc(NOpen);
        Inc(k);
      end;

      Body := '';
      for k := i to RunEnd do
        Body := Body + FChars[k];
      Line := Line + HTMLEscape(Body);
      i := RunEnd + 1;
    end;
    FMarkupDirty := False;
  finally
    FSettingMarkup := False;
  end;
end;

function TInkRichEdit.AsHTML(const ASep: string): string;
var
  i: Integer;
  M: TStrings;
begin
  M := GetMarkup;
  Result := '';
  for i := 0 to M.Count - 1 do
  begin
    if i > 0 then Result := Result + ASep;
    Result := Result + M[i];
  end;
end;

{ The blocks of MarkdownToHTML's output, re-spoken as the editor's own
  markup lines: one line per paragraph, wrapped in the editor's paragraph
  tags, inline content flattened through HTMLToInk.  Nested lists flatten
  to one level, and a table becomes plain rows - the editor has no tables
  yet. }
procedure MarkdownHTMLToParagraphs(const H: string; AOut: TStrings;
  AListLevel: Integer = 0);
var
  P, Q, Depth: Integer;
  Raw, Name, Inner, Wrap: string;
  Closing: Boolean;
  InOrdered: Boolean;

  function ReadTagIn(const Src: string; var AP: Integer; out AName: string;
    out AClosing: Boolean): string;
  var
    E, K: Integer;
  begin
    Result := '';
    AName := '';
    AClosing := False;
    if (AP > Length(Src)) or (Src[AP] <> '<') then Exit;
    E := AP + 1;
    while (E <= Length(Src)) and (Src[E] <> '>') do Inc(E);
    if E > Length(Src) then begin AP := E; Exit end;
    Result := Copy(Src, AP, E - AP + 1);
    AP := E + 1;
    K := 2;
    if (K <= Length(Result)) and (Result[K] = '/') then
    begin
      AClosing := True;
      Inc(K);
    end;
    while (K <= Length(Result)) and (Result[K] in ['a'..'z', 'A'..'Z', '0'..'9']) do
    begin
      AName := AName + LowerCase(Result[K]);
      Inc(K);
    end;
  end;

  function ReadTag(var AP: Integer; out AName: string; out AClosing: Boolean): string;
  begin
    Result := ReadTagIn(H, AP, AName, AClosing);
  end;

  { everything up to the close of AName, nesting counted, cursor left after }
  function InnerOf(const AName: string): string;
  var
    S0, D, TP: Integer;
    N: string;
    C: Boolean;
  begin
    S0 := P;
    D := 1;
    while P <= Length(H) do
    begin
      if H[P] = '<' then
      begin
        TP := P;
        ReadTag(P, N, C);
        if N = AName then
        begin
          if C then
          begin
            Dec(D);
            if D = 0 then Exit(Copy(H, S0, TP - S0));
          end
          else
            Inc(D);
        end;
        Continue;
      end;
      Inc(P);
    end;
    Result := Copy(H, S0, MaxInt);
  end;

  procedure AddWrapped(const AWrap, AInner: string);
  var
    Ink, CloseName: string;
    SP: Integer;
  begin
    Ink := Trim(HTMLToInk(AInner));
    if AWrap = '' then
      AOut.Add(Ink)
    else
    begin
      CloseName := AWrap;
      SP := Pos(' ', CloseName);
      if SP > 0 then CloseName := Copy(CloseName, 1, SP - 1);
      AOut.Add('<' + AWrap + '>' + Ink + '</' + CloseName + '>');
    end;
  end;

  procedure AddCode(const AInner: string);
  var
    T, Lang, Open: string;
    Lines: TStringList;
    K: Integer;
  begin
    T := AInner;
    { the code tag inside pre carries the fence's language as
      class="language-x"; keep it, then strip the tag and its partner }
    Lang := '';
    K := Pos('>', T);
    if (Pos('<code', LowerCase(T)) = 1) and (K > 0) then
    begin
      Lang := Copy(T, 1, K);
      Q := Pos('language-', LowerCase(Lang));
      if Q > 0 then
      begin
        Lang := Copy(Lang, Q + 9, MaxInt);
        Q := 1;
        while (Q <= Length(Lang)) and not (Lang[Q] in ['"', '''', ' ', '>']) do
          Inc(Q);
        SetLength(Lang, Q - 1);
      end
      else
        Lang := '';
      Delete(T, 1, K);
    end;
    K := Pos('</code>', LowerCase(T));
    if K > 0 then SetLength(T, K - 1);
    if (T <> '') and (T[Length(T)] = #10) then SetLength(T, Length(T) - 1);
    Open := '<pre>';
    if Lang <> '' then Open := '<pre lang="' + Lang + '">';
    Lines := TStringList.Create;
    try
      Lines.Text := HTMLUnescape(T);
      if Lines.Count = 0 then Lines.Add('');
      for K := 0 to Lines.Count - 1 do
        AOut.Add(Open + HTMLEscape(Lines[K]) + '</pre>');
    finally
      Lines.Free;
    end;
  end;

  { a table becomes the editor's table rows: the head from its <th> cells,
    a body row per <tr>, the cells joined by the '|' that draws the grid }
  procedure AddTable(const AInner: string);
  var
    TP, CE: Integer;
    N, Row, Cell: string;
    C, IsHead: Boolean;
    Cells: TStringList;

    procedure FlushRow;
    var
      K: Integer;
    begin
      if Cells.Count = 0 then Exit;
      Row := '';
      for K := 0 to Cells.Count - 1 do
      begin
        if K > 0 then Row := Row + '|';
        Row := Row + Trim(HTMLToInk(Cells[K]));
      end;
      if IsHead then
        AOut.Add('<th>' + Row + '</th>')
      else
        AOut.Add('<tr>' + Row + '</tr>');
      Cells.Clear;
      IsHead := False;
    end;

  begin
    TP := 1;
    IsHead := False;
    Cells := TStringList.Create;
    try
      while TP <= Length(AInner) do
      begin
        if AInner[TP] <> '<' then
        begin
          Inc(TP);
          Continue;
        end;
        ReadTagIn(AInner, TP, N, C);
        if (N = 'tr') and C then
          FlushRow
        else if ((N = 'td') or (N = 'th')) and not C then
        begin
          if N = 'th' then IsHead := True;
          CE := Pos('</' + N + '>', LowerCase(Copy(AInner, TP, MaxInt)));
          if CE = 0 then
            Cell := Copy(AInner, TP, MaxInt)
          else
            Cell := Copy(AInner, TP, CE - 1);
          Cells.Add(Cell);
          Inc(TP, Length(Cell));
        end;
      end;
      FlushRow;
    finally
      Cells.Free;
    end;
  end;

begin
  P := 1;
  InOrdered := False;
  while P <= Length(H) do
  begin
    if H[P] <> '<' then
    begin
      Inc(P);
      Continue;
    end;
    Raw := ReadTag(P, Name, Closing);
    if Closing then
    begin
      if (Name = 'ul') or (Name = 'ol') then InOrdered := False;
      Continue;
    end;
    if (Length(Name) = 2) and (Name[1] = 'h') and (Name[2] in ['1'..'6']) then
      AddWrapped(Name, InnerOf(Name))
    else if Name = 'p' then
      AddWrapped('', InnerOf(Name))
    else if Name = 'ol' then
      InOrdered := True
    else if Name = 'ul' then
      InOrdered := False
    else if Name = 'li' then
    begin
      Inner := InnerOf('li');
      { a nested list inside the item is the next level down }
      Wrap := 'li';
      if InOrdered then Wrap := 'oli';
      if AListLevel > 0 then
        Wrap := Wrap + ' level="' + IntToStr(Min(AListLevel, 5)) + '"';
      Q := Pos('<ul', LowerCase(Inner));
      if Q = 0 then Q := Pos('<ol', LowerCase(Inner));
      if Q > 0 then
      begin
        AddWrapped(Wrap, Copy(Inner, 1, Q - 1));
        MarkdownHTMLToParagraphs(Copy(Inner, Q, MaxInt), AOut, AListLevel + 1);
      end
      else
        AddWrapped(Wrap, Inner);
    end
    else if Name = 'blockquote' then
    begin
      { each paragraph inside the quote is a quote line of its own }
      Inner := InnerOf('blockquote');
      Inner := StringReplace(Inner, '</p>', #1, [rfReplaceAll, rfIgnoreCase]);
      Inner := StringReplace(Inner, '<p>', '', [rfReplaceAll, rfIgnoreCase]);
      for Q := 1 to WordCount(Inner, [#1]) do
        if Trim(ExtractWord(Q, Inner, [#1])) <> '' then
          AOut.Add('<blockquote>' + Trim(HTMLToInk(ExtractWord(Q, Inner, [#1]))) + '</blockquote>');
    end
    else if Name = 'pre' then
      AddCode(InnerOf('pre'))
    else if Name = 'table' then
      AddTable(InnerOf('table'))
    else if Name = 'hr' then
      AOut.Add(#$E2#$80#$95#$E2#$80#$95#$E2#$80#$95);
  end;
end;

procedure TInkRichEdit.LoadMarkdown(const S: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    MarkdownHTMLToParagraphs(MarkdownToHTML(S), Lines);
    if Lines.Count = 0 then Lines.Add('');
    Markup := Lines;
  finally
    Lines.Free;
  end;
end;

function TInkRichEdit.AsMarkdown: string;
var
  i, PS, CS, CE, NCells: Integer;
  Kind, PrevKind: TInkParaKind;
  Lines: TStringList;
  InFence: Boolean;
  PrevLevel: Integer;
  Back, FenceLang: string;

  function EscapeMD(const T: string): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 1 to Length(T) do
    begin
      if T[K] in ['\', '`', '*', '_', '[', '|'] then Result := Result + '\';
      Result := Result + T[K];
    end;
  end;

  { the paragraph's characters as Markdown inline text }
  function InlineMD(AFrom, ATo: Integer): string;
  var
    K, J, RunEnd: Integer;
    A: TInkAttr;
    Txt, Piece: string;
  begin
    Result := '';
    K := AFrom;
    while K <= ATo do
    begin
      A := FAttrs[K];
      RunEnd := K;
      while (RunEnd + 1 <= ATo) and SameInkAttr(FAttrs[RunEnd + 1], A) do
        Inc(RunEnd);
      Txt := '';
      for J := K to RunEnd do
        Txt := Txt + FChars[J];
      if (A.Face <> '') and (A.Kind <> ipkCode) then
        { a monospaced run is a code span; nothing nests inside backticks }
        Piece := '`' + Txt + '`'
      else
      begin
        Piece := EscapeMD(Txt);
        if fsBold in A.Style then Piece := '**' + Piece + '**';
        if fsItalic in A.Style then Piece := '*' + Piece + '*';
        if fsStrikeOut in A.Style then Piece := '~~' + Piece + '~~';
        if fsUnderline in A.Style then Piece := '<u>' + Piece + '</u>';
        if A.Script = isSuperscript then Piece := '<sup>' + Piece + '</sup>';
        if A.Script = isSubscript then Piece := '<sub>' + Piece + '</sub>';
      end;
      if A.Link <> '' then Piece := '[' + Piece + '](' + A.Link + ')';
      Result := Result + Piece;
      K := RunEnd + 1;
    end;
  end;

  function RawText(AFrom, ATo: Integer): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := AFrom to ATo do
      Result := Result + FChars[K];
  end;

begin
  Lines := TStringList.Create;
  try
    PrevKind := ipkText;
    PrevLevel := 0;
    FenceLang := '';
    InFence := False;
    i := 0;
    while i <= CharCount do
    begin
      PS := i;
      while (i < CharCount) and (FChars[i] <> #10) do Inc(i);
      if (PS = CharCount) and (PS > 0) then Break;  { nothing past the last break }
      Kind := ParaKindAt(PS);
      { fences open and close around an unbroken run of code lines }
      if InFence and (Kind <> ipkCode) then
      begin
        Lines.Add('```');
        InFence := False;
      end;
      { a blank line between blocks, except inside a list, a quote, a fence
        or a table.  A nested item continues its list whatever its kind;
        two different kinds at the top level are two lists, kept apart. }
      if (Lines.Count > 0) and not InFence then
        if not (((Kind in [ipkBullet, ipkNumber]) and
             (PrevKind in [ipkBullet, ipkNumber]) and
             ((Kind = PrevKind) or (ParaLevelAt(PS) > 0) or (PrevLevel > 0))) or
          ((Kind = PrevKind) and (Kind in [ipkQuote, ipkCode])) or
          ((Kind in [ipkTableHead, ipkTableRow]) and
           (PrevKind in [ipkTableHead, ipkTableRow]))) then
          Lines.Add('');
      case Kind of
        ipkH1..ipkH6:
          Lines.Add(StringOfChar('#', Ord(Kind) - Ord(ipkH1) + 1) + ' ' + InlineMD(PS, i - 1));
        ipkBullet:
          { three spaces per level: deep enough to nest under "1. " as well
            as under "- ", and never deep enough to read as indented code }
          Lines.Add(StringOfChar(' ', 3 * ParaLevelAt(PS)) + '- ' + InlineMD(PS, i - 1));
        ipkNumber:
          Lines.Add(StringOfChar(' ', 3 * ParaLevelAt(PS)) +
            IntToStr(ParaNumber(PS)) + '. ' + InlineMD(PS, i - 1));
        ipkQuote:
          Lines.Add('> ' + InlineMD(PS, i - 1));
        ipkCode:
          begin
            if InFence and (FAttrs[PS].Lang <> FenceLang) then
            begin
              { the language changed: this is another fence }
              Lines.Add('```');
              InFence := False;
            end;
            if not InFence then
            begin
              FenceLang := '';
              if PS < CharCount then FenceLang := FAttrs[PS].Lang;
              Lines.Add('```' + FenceLang);
              InFence := True;
            end;
            Lines.Add(RawText(PS, i - 1));
          end;
        ipkTableHead, ipkTableRow:
          begin
            { cells between the pipes, each written as inline Markdown }
            Back := '|';
            NCells := 0;
            CS := PS;
            for CE := PS to i do
              if (CE = i) or (FChars[CE] = '|') then
              begin
                Back := Back + ' ' + InlineMD(CS, CE - 1) + ' |';
                Inc(NCells);
                CS := CE + 1;
              end;
            Lines.Add(Back);
            if Kind = ipkTableHead then
            begin
              Back := '|';
              for CE := 1 to NCells do Back := Back + ' --- |';
              Lines.Add(Back);
            end;
          end;
      else
        Lines.Add(InlineMD(PS, i - 1));
      end;
      PrevKind := Kind;
      PrevLevel := ParaLevelAt(PS);
      Inc(i);
    end;
    if InFence then Lines.Add('```');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function TInkRichEdit.PlainText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to CharCount - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

end.
