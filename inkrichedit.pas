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

  SPDX-License-Identifier: 0BSD; see LICENSE.
}
unit InkRichEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, StdCtrls, Forms, LCLType,
  LCLIntf, LMessages, Clipbrd, LazUTF8, ExtCtrls, Types, Menus, InkMarkdown, InkDraw, InkEdit;

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
    ipkTableHead, ipkTableRow, ipkSource);

  { Everything one character can carry. The sentinels — clDefault, clNone, 0,
    '' — mean "follow the control's Font", so a document that never mentions a
    color still tracks the control when the control's Font changes. }
  TInkAttr = record
    Color: TColor;        // clDefault -> Font.Color
    BackColor: TColor;    // clNone    -> transparent
    Size: integer;        // 0         -> Font.Size
    Face: string;         // ''        -> Font.Name
    Style: TFontStyles;
    Script: TInkScript;
    ImageSource, ImageAlt, ImageTitle: string;
    ImageWidth, ImageHeight: integer; // from the tag; 0 is the picture's own
    LinkTitle: string;
    TaskState: shortint;  // -1 for text, 0 or 1 for a task checkbox
    HardBreak: boolean;
    Link: string;         // ''        -> not a link
    Align: TAlignment;    // paragraph property, held per character
    Kind: TInkParaKind;   // paragraph property, held per character
    Level: byte;          // a list item's nesting depth, 0 for the first
    Lang: string;         // a code line's fence language, '' unsaid
    TableAlign: string;   // one alignment per column: l, c, r or -
    CellBreak: boolean;   // a table divider, distinct from a literal pipe
    MarkdownBlock: integer; // source identity; 0 for documents built from markup
  end;

  { One visual line: a run of characters that share a baseline. A paragraph is
    one line plus one more for every wrap point inside it. }
  TInkVisLine = record
    First: integer;       // index of the first character
    Count: integer;       // how many characters, including a trailing #10
    Top: integer;         // y of the line's top, in document space
    Height: integer;
    Ascent: integer;      // baseline offset from Top
    Width: integer;
    Left: integer;        // x of the line's start, after alignment
  end;

  TInkMarkdownOriginal = record
    First, Count: integer;
    Canonical: string;
    { an HTML block: drawn as the page would draw it and kept byte for
      byte, because the editor cannot write it back.  The caret in it
      opens its source in place; Edited is that source once it has changed }
    Locked: boolean;
    Edited: string;
  end;

  TInkRichImageEvent = procedure(Sender: TObject; const Source: string; Picture: TPicture) of object;
  TInkRichLinkEvent = procedure(Sender: TObject; const LinkName: string) of object;

  { TInkRichEdit }

  TInkRichEdit = class(TCustomControl)
  private
    FImageBase: string;
    FImages: TStringList;
    FMoving: TStringList;         // source -> its TInkGIF or TInkWebP, for pictures that move
    FMovingRects: array of TRect; // where each was drawn in the last paint; empty when off screen
    FMotionTimer: TTimer;
    FOnImageNeeded: TInkRichImageEvent;
    FMarkdownSource: string;
    FMarkdownOriginals: array of TInkMarkdownOriginal;
    FOpenBlock: integer;          // the locked block whose source is open, 1-based; 0 none
    FSyncing: boolean;
    FChars: array of string;      // one UTF-8 codepoint each; #10 = paragraph
    FAttrs: array of TInkAttr;
    FCaret: integer;              // 0..CharCount, a gap between characters
    FAnchor: integer;             // selection anchor; = FCaret when none
    FLines: array of TInkVisLine;
    FCharX: array of integer;     // x of each character within its own line
    FCharW: array of integer;
    FLayoutValid: boolean;
    FDocHeight: integer;
    FScrollY: integer;
    FWheelRest: double;
    FVScroll: TScrollBar;
    FTypingAttr: TInkAttr;        // what the next typed character will wear
    FHasTypingAttr: boolean;
    FMarkup: TStrings;            // one paragraph per line
    FMarkupDirty: boolean;
    FSettingMarkup: boolean;
    FCaretTimer: TTimer;
    FCaretOn: boolean;
    FGoalX: integer;              // remembered column for up/down
    FUndo: TFPList;
    FRedo: TFPList;
    FLastUndoTick: QWord;
    FReadOnly: boolean;
    FWordWrap: boolean;
    FParagraphSpacing: boolean;
    FSuperSubScriptRatio: double;
    FModified: boolean;
    FMouseOnLink: boolean;
    FHoverLink: string;
    FOnChange: TNotifyEvent;
    FOnSelectionChange: TNotifyEvent;
    FOnGoToSource: TNotifyEvent;
    FOnLinkClick: TInkRichLinkEvent;
    FEditMenu: boolean;
    FMenu: TPopupMenu;
    FFindEdit: TInkEdit;
    FFindText: string;
    FClicks, FLastClickX, FLastClickY: integer;
    FLastClickTime: QWord;
    FSelectUnit: integer;         // what a drag selects by: 0 chars, 1 words, 2 paragraphs
    FUnitFrom, FUnitTo: integer;
    FDefaultSize: integer;        // points, when neither Font nor the system font has a size
    procedure UnitAt(AIndex: integer; out AFrom, ATo: integer);
    function FindFrom(const AText: string; AOptions: TInkFindOptions; AFrom: integer): integer;
    function FindBarRect: TRect;
    function FindButtonRect(Index: integer): TRect;
    procedure PlaceFindBar;
    procedure PaintFindBar;
    procedure FindEditChange(Sender: TObject);
    procedure FindEditKey(Sender: TObject; var Key: word; Shift: TShiftState);
    function GetFindBarVisible: boolean;
    function SelectImageAt(X, Y: integer): boolean;
    procedure ContextAt(X, Y: integer);
    procedure SetImageBaseURI(const Value: string);
    function ImagePicture(const Source: string): TPicture;
    procedure ClearImages;
    procedure MotionTick(Sender: TObject);
    function ImageWidth(AIndex: integer): integer;
    function ImageHeight(AIndex: integer): integer;
    function LockedAt(AIndex: integer): boolean;
    function RangeLocked(AFrom, ATo: integer): boolean;
    function EditLocked: boolean;
    function BlockRange(ABlock: integer; out AFirst, ALast: integer): boolean;
    function BlockSource(ABlock: integer): string;
    function ReplaceBlock(ABlock: integer; AText: string; const AAttrs: array of TInkAttr): integer;
    procedure OpenBlock(ABlock: integer);
    function CloseBlock(ABlock: integer): integer;
    procedure SyncOpenBlock;
    function MarkdownRange(AFirst, AEnd: integer): string;
    procedure MenuClick(Sender: TObject);
    function IsCellBreak(AIndex: integer): boolean;
    function FontEm: integer;
    function QuoteBarWidth: integer;
    function IsCodeSpan(AIndex: integer): boolean;
    function CharCount: integer;
    function GetSelStart: integer;
    function GetSelLength: integer;
    procedure SetSelStart(AValue: integer);
    procedure SetSelLength(AValue: integer);
    function GetSelText: string;
    procedure SetMarkup(AValue: TStrings);
    function GetMarkup: TStrings;
    procedure MarkupChanged(Sender: TObject);
    procedure RebuildFromMarkup;
    procedure SetReadOnly(AValue: boolean);
    procedure SetWordWrap(AValue: boolean);
    procedure SetParagraphSpacing(AValue: boolean);
    { layout }
    procedure InvalidateLayout;
    procedure Relayout;
    procedure NeedLayout;
    procedure ApplyAttrToCanvas(const A: TInkAttr);
    function ParaKindAt(AIndex: integer): TInkParaKind;
    function ParaLevelAt(AIndex: integer): integer;
    function ParaIndent(AKind: TInkParaKind; ALevel: integer): integer;
    function ParaNumber(AFirst: integer): integer;
    function MeasureChar(AIndex: integer): integer;
    function LineOfChar(AIndex: integer): integer;
    function CaretLine(ACaret: integer): integer;
    function LineTextWidth: integer;
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure ScrollToCaret;
    function CaretPoint(ACaret: integer): TPoint;   // document space
    function PointToCaret(X, Y: integer): integer;  // client space
    { document }
    procedure DoInsert(const AText: string; const AAttr: TInkAttr);
    procedure DoDelete(AFrom, ATo: integer);
    procedure DeleteSelection;
    function AttrAtCaret: TInkAttr;
    procedure Changed;
    procedure SelectionChanged;
    procedure MoveCaret(ANew: integer; AExtend: boolean);
    { markup }
    { reads one line of markup into the document; returns the paragraph's
      own attributes, its kind, level and language }
    function ParseInto(const AMarkup: string; AParaBreakFirst: boolean): TInkAttr;
    procedure SyncMarkupFromDoc;
    { undo }
    procedure PushUndo(ACoalesce: boolean);
    procedure ClearUndoList(AList: TFPList);
    procedure RestoreSnapshot(ASnap: TObject);
    function TakeSnapshot: TObject;
    procedure CaretTimerTick(Sender: TObject);
    procedure RestartCaretBlink;
  protected
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
    procedure DoContextPopup(MousePos: TPoint; var Handled: boolean); override;
    { What a character is drawn and measured as: FAttrs[AIndex], passed
      through AdjustAttr, which a descendant overrides to color characters
      on the fly - the plain editor's OnGetCharAttrs rides on this. }
    function EffAttr(AIndex: integer): TInkAttr;
    function CharAt(AIndex: integer): string;
    procedure AdjustAttr(AIndex: integer; var A: TInkAttr); virtual;
    { inserts plain text (line breaks kept) in the attributes at the caret }
    procedure InsertPlainText(const AText: string);
    { the laid-out document's height in pixels, for a box that grows }
    function DocumentHeight: integer;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure FontChanged(Sender: TObject); override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure Click; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    class function GetControlClassDefaultSize: TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Clear;
    { the caret to the heading whose GitHub-style slug is Anchor }
    function JumpToAnchor(const Anchor: string): boolean;
    procedure ScrollTo(AY: integer);
    property ScrollY: integer read FScrollY;
    { where relative image paths are resolved from; a file:// URI }
    property ImageBaseURI: string read FImageBase write SetImageBaseURI;
    { the selection's bytes in AsMarkdown, from 1; False when no range
      renders the same }
    function MarkdownSourceRange(out AFirst, ACount: integer): boolean;
    { fires OnGoToSource; the context menu's Go to source does the same }
    procedure GoToSource;
    procedure SelectAll;
    { Selects the next place AText appears after the selection - before it
      with ifoBackwards - going round the end, and scrolls it into view.
      False when it appears nowhere. }
    function Find(const AText: string; AOptions: TInkFindOptions = []): boolean;
    { how often AText appears, and which of them is selected (from 1; 0 when
      the selection is not one of them) }
    function FindCount(const AText: string; AOptions: TInkFindOptions; out Current: integer): integer;
    { The find bar, as TInkPage has it: a box at the top right.  Ctrl+F
      opens it, typing finds as you go, Enter and F3 go to the next, Shift
      with either to the one before, Esc closes it. }
    procedure ShowFindBar;
    procedure HideFindBar;
    property FindBarVisible: boolean read GetFindBarVisible;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard; virtual;
    procedure Undo;
    procedure Redo;
    function CanUndo: boolean;
    function CanRedo: boolean;

    { Formatting. With a selection they change it; with none they set what the
      next typed character will wear, the way every editor behaves. }
    procedure ApplyStyle(AStyle: TFontStyle; AOn: boolean);
    procedure ToggleStyle(AStyle: TFontStyle);
    procedure ApplyColor(AColor: TColor);
    procedure ApplyBackColor(AColor: TColor);
    procedure ApplySize(ASize: integer);
    procedure ApplyFace(const AFace: string);
    procedure ApplyScript(AScript: TInkScript);
    procedure ApplyLink(const AHref: string);
    procedure ApplyAlignment(AAlign: TAlignment);
    { the whole paragraphs the selection touches become AKind - a heading,
      a bullet or numbered item, a quote, a line of code, or plain text }
    procedure ApplyParaKind(AKind: TInkParaKind);
    { checks or clears the task checkbox of the caret's list item }
    procedure ToggleTask;
    { the list items the selection touches step ADelta levels deeper or
      back out - what Tab and Shift+Tab do on a list item }
    procedure ApplyParaLevel(ADelta: integer);
    { a fresh table at the caret: a head row and ARows body rows of ACols
      empty cells, the caret in the head's first cell }
    procedure InsertTable(ACols, ARows: integer);
    { an image at the caret, replacing the selection; one undo step }
    procedure InsertImage(const Source, AltText: string; const Title: string = '');
    procedure ClearFormatting;
    procedure InsertParagraph;

    { What the toolbar should show as pressed: the value shared by the whole
      selection, or the sentinel when the selection disagrees with itself. }
    function SelStyle: TFontStyles;
    function SelColor: TColor;
    function SelBackColor: TColor;
    function SelSize: integer;
    function SelFace: string;
    { the selection's link target, '' when none or mixed }
    function SelLink: string;
    function SelScript: TInkScript;
    function SelAlignment: TAlignment;
    function SelParaKind: TInkParaKind;

    { The document as markup, paragraphs joined with ASep. Feed it straight to
      a TInkLabel caption or a TInkMemo line. }
    function AsHTML(const ASep: string = '<br>'): string;
    function PlainText: string;
    { The document as Markdown, and a Markdown document read in.  After
      LoadMarkdown, blocks that were not edited come back byte for byte.
      What Markdown has no word for goes out as inline HTML (<u>, <sup>,
      <sub>); colors and faces are lost.  ABaseURI resolves relative images. }
    function AsMarkdown: string;
    procedure LoadMarkdown(const S: string; const ABaseURI: string = '');
    property SelText: string read GetSelText;
    property Modified: boolean read FModified write FModified;
    { runtime only - a stored caret position would be meaningless in a .lfm }
    property SelStart: integer read GetSelStart write SetSelStart;
    property SelLength: integer read GetSelLength write SetSelLength;
  published
    { One paragraph per line. Editable in the Object Inspector, so a design-time
      document is real markup in the .lfm and renders in the form designer. }
    property Markup: TStrings read GetMarkup write SetMarkup;
    { the document can be read, selected and copied but not changed }
    property ReadOnly: boolean read FReadOnly write SetReadOnly default False;
    { the selection, or the caret's paragraph, is in an HTML block the
      editor keeps as written: typing and formatting do nothing there }
    property SelLocked: boolean read EditLocked;
    { re-flow each paragraph to the control's width }
    property WordWrap: boolean read FWordWrap write SetWordWrap default True;
    { space between paragraphs, headings, lists, quotes, code and tables, as
      a browser leaves it; list items, quote lines and code lines stay
      together.  Off, every paragraph sits right under the one before. }
    property ParagraphSpacing: boolean read FParagraphSpacing write SetParagraphSpacing default False;
    { the size of <sup> and <sub> text as a fraction of the font's size }
    property SuperSubScriptRatio: double read FSuperSubScriptRatio write FSuperSubScriptRatio;
    { the editor's own right-click menu - Undo, Redo, Cut, Copy, Paste,
      Delete, Select All; a PopupMenu of the host's own still wins }
    property EditMenu: boolean read FEditMenu write FEditMenu default True;
    { fires after every edit of the document }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { the caret moved or the selection changed }
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    { Assigned, the context menu gets Go to source; show the source there. }
    property OnGoToSource: TNotifyEvent read FOnGoToSource write FOnGoToSource;
    { Supply pictures from the host's resources; local files load by default. }
    property OnImageNeeded: TInkRichImageEvent read FOnImageNeeded write FOnImageNeeded;
    { a link was clicked; LinkName is its href }
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
function SameInkAttr(const A, B: TInkAttr): boolean;

implementation

uses
  StrUtils, URIParser, InkTouch, InkGIF, InkWebP;

resourcestring
  SInkRichGoToSource = 'Go to source';

procedure MarkdownHTMLToParagraphs(const H: string; AOut: TStrings; AListLevel: integer = 0); forward;

const
  cMargin = 3;
  cCellPad = 13;          // a table cell's inset each side of its text
  cRowPad = 6;            // and above and below it
  cScrollBarWidth = 16;
  cUndoDepth = 200;
  cUndoCoalesceMs = 700;

type
  { A whole-document snapshot. Documents in an editor like this are small, and
    a snapshot that cannot be subtly wrong beats a delta log that can. }
  TInkSnapshot = class
    Chars: array of string;
    Attrs: array of TInkAttr;
    Caret: integer;
    Anchor: integer;
    Originals: array of TInkMarkdownOriginal;
    OpenBlock: integer;
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
  Result.ImageSource := '';
  Result.ImageAlt := '';
  Result.ImageTitle := '';
  Result.ImageWidth := 0;
  Result.ImageHeight := 0;
  Result.LinkTitle := '';
  Result.TaskState := -1;
  Result.HardBreak := False;
  Result.Link := '';
  Result.Align := taLeftJustify;
  Result.Kind := ipkText;
  Result.Level := 0;
  Result.Lang := '';
  Result.MarkdownBlock := 0;
  Result.TableAlign := '';
  Result.CellBreak := False;
end;

function SameInkAttr(const A, B: TInkAttr): boolean;
begin
  Result := (A.Color = B.Color) and (A.BackColor = B.BackColor) and (A.Size = B.Size) and (A.Face = B.Face) and (A.Style = B.Style) and
    (A.Script = B.Script) and (A.Link = B.Link) and (A.Align = B.Align) and (A.Kind = B.Kind) and (A.Level = B.Level) and (A.Lang = B.Lang) and
    (A.TableAlign = B.TableAlign) and (A.CellBreak = B.CellBreak) and (A.ImageSource = B.ImageSource) and (A.ImageAlt = B.ImageAlt) and
    (A.ImageTitle = B.ImageTitle) and (A.ImageWidth = B.ImageWidth) and (A.ImageHeight = B.ImageHeight) and
    (A.LinkTitle = B.LinkTitle) and (A.TaskState = B.TaskState) and (A.HardBreak = B.HardBreak);
end;

{ '#RRGGBB' for a real color, '' for the sentinels }
function InkColorToHTML(C: TColor): string;
var
  RGB: longint;
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
  FImages := TStringList.Create;
  FImages.OwnsObjects := True;
  FImages.CaseSensitive := True;
  FMoving := TStringList.Create;
  FMoving.OwnsObjects := True;
  FMoving.CaseSensitive := True;
  FEditMenu := True;
  inherited Create(AOwner);
  FMotionTimer := TTimer.Create(Self);
  FMotionTimer.Enabled := False;
  FMotionTimer.Interval := 20;
  FMotionTimer.OnTimer := @MotionTick;
  ControlStyle := ControlStyle + [csCaptureMouse, csOpaque, csRequiresKeyboardInput] - [csSetCaption];
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
  FMotionTimer.Enabled := False;
  FreeAndNil(FMoving);
  FreeAndNil(FImages);
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

function TInkRichEdit.IsCellBreak(AIndex: integer): boolean;
begin
  Result := (AIndex >= 0) and (AIndex < CharCount) and FAttrs[AIndex].CellBreak;
end;

{ the control font's em in pixels; a negative Height is it, the default
  font says 0 }
function TInkRichEdit.FontEm: integer;
var
  tm: TLCLTextMetric;
begin
  Canvas.Font := Font;
  Result := -Canvas.Font.Height;
  if (Result <= 0) and Canvas.GetTextMetrics(tm) then Result := tm.Height * 4 div 5;
  if Result <= 0 then Result := 12;
end;

{ a quote's bar, a quarter em as on TInkPage's Markdown page }
function TInkRichEdit.QuoteBarWidth: integer;
begin
  Result := Max(3, FontEm div 4);
end;

{ a character of an inline code span, which sits on a shaded chip; not in a
  code block or a table, which lay their characters out their own way }
function TInkRichEdit.IsCodeSpan(AIndex: integer): boolean;
begin
  Result := (AIndex >= 0) and (AIndex < CharCount) and (FChars[AIndex] <> #10) and (FAttrs[AIndex].Face = InkMonoFace) and not
    (FAttrs[AIndex].Kind in [ipkCode, ipkSource, ipkTableHead, ipkTableRow]);
end;

function TInkRichEdit.CharCount: integer;
begin
  Result := Length(FChars);
end;

{ ---------------------------------------------------------------- selection }

function TInkRichEdit.GetSelStart: integer;
begin
  if FCaret < FAnchor then Result := FCaret
  else
    Result := FAnchor;
end;

function TInkRichEdit.GetSelLength: integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

procedure TInkRichEdit.SetSelStart(AValue: integer);
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

procedure TInkRichEdit.SetSelLength(AValue: integer);
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
  i: integer;
begin
  Result := '';
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

procedure TInkRichEdit.MoveCaret(ANew: integer; AExtend: boolean);
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

function TInkRichEdit.JumpToAnchor(const Anchor: string): boolean;
var
  I, First, N: integer;
  HeadingText, Base, Slug: string;
  Slugs: TStringList;
begin
  Result := False;
  Slugs := TStringList.Create;
  try
    I := 0;
    while I < CharCount do
    begin
      First := I;
      HeadingText := '';
      while (I < CharCount) and (FChars[I] <> #10) do
      begin
        HeadingText := HeadingText + FChars[I];
        Inc(I);
      end;
      if ParaKindAt(First) in [ipkH1..ipkH6] then
      begin
        Base := MarkdownSlug(HeadingText);
        Slug := Base;
        N := 0;
        while Slugs.IndexOf(Slug) >= 0 do
        begin
          Inc(N);
          Slug := Base + '-' + IntToStr(N);
        end;
        Slugs.Add(Slug);
        if Slug = Anchor then
        begin
          MoveCaret(First, False);
          Exit(True);
        end;
      end;
      Inc(I);
    end;
  finally
    Slugs.Free
  end;
end;

procedure TInkRichEdit.ScrollTo(AY: integer);
begin
  NeedLayout;
  FScrollY := EnsureRange(AY, 0, Max(0, FDocHeight - ClientHeight));
  FVScroll.Position := FScrollY;
  Invalidate;
end;

function TInkRichEdit.MarkdownSourceRange(out AFirst, ACount: integer): boolean;
var
  Source, DisplayText, Marker: string;
  Probe: TInkRichEdit;
  Start, Finish, Last, ObjectCount: integer;

  function FindRange(FromChar, CharCount: integer; out ByteFirst, ByteCount: integer): boolean;
  var
    Needle, SearchNeedle, Expected, Candidate, Shown, Token: string;
    P, N, Attempts, E, NextText, NextEntity, NextTask: integer;
  begin
    Result := False;
    Needle := UTF8Copy(DisplayText, FromChar + 1, CharCount);
    if Needle = '' then Exit;
    SearchNeedle := Needle;
    if (CharCount = 1) and (FromChar < Length(FChars)) and (FAttrs[FromChar].TaskState >= 0) then
      if FAttrs[FromChar].TaskState = 1 then SearchNeedle := '[x]'
      else
        SearchNeedle := '[ ]';
    Expected := UTF8Copy(DisplayText, 1, FromChar) + Marker + UTF8Copy(DisplayText, FromChar + CharCount + 1, MaxInt);
    P := 1;
    Attempts := 0;
    while P <= Length(Source) do
    begin
      NextText := PosEx(SearchNeedle, Source, P);
      if SearchNeedle = '[x]' then
      begin
        NextTask := PosEx('[X]', Source, P);
        if (NextTask > 0) and ((NextText = 0) or (NextTask < NextText)) then NextText := NextTask;
      end;
      NextEntity := 0;
      if CharCount = 1 then NextEntity := PosEx('&', Source, P);
      if (NextEntity > 0) and ((NextText = 0) or (NextEntity < NextText)) then
      begin
        P := NextEntity;
        E := P + 1;
        while (E <= Length(Source)) and (E - P < 34) and not (Source[E] in [';', ' ', #10, #13]) do Inc(E);
        Token := Copy(Source, P, E - P + 1);
        if HTMLUnescape(Token) <> Needle then
        begin
          Inc(P);
          Continue;
        end;
        N := Length(Token);
      end
      else
      begin
        P := NextText;
        if P = 0 then Break;
        N := Length(SearchNeedle);
      end;
      if (CharCount = 1) and (P > 1) and (Source[P - 1] = '\') then
      begin
        Dec(P);
        Inc(N);
      end;
      { An entity is one rendered character but several source bytes. }
      if (CharCount = 1) and (Source[P] = '&') then
      begin
        E := P + 1;
        while (E <= Length(Source)) and (E - P < 34) and not (Source[E] in [';', ' ', #10, #13]) do Inc(E);
        if (E <= Length(Source)) and (Source[E] = ';') then
        begin
          Token := Copy(Source, P, E - P + 1);
          if HTMLUnescape(Token) = Needle then N := Length(Token);
        end;
      end;
      Candidate := Copy(Source, 1, P - 1) + Marker + Copy(Source, P + N, MaxInt);
      Probe.LoadMarkdown(Candidate);
      Shown := StringReplace(Probe.PlainText, LineEnding, #10, [rfReplaceAll]);
      if Shown = Expected then
      begin
        ByteFirst := P;
        ByteCount := N;
        Exit(True);
      end;
      Inc(P, N);
      Inc(Attempts);
      if Attempts >= 128 then Break;
    end;
  end;

  function FindImage(CharIndex: integer; out ByteFirst, ByteCount: integer): boolean;
  var
    P, E, Attempts: integer;
    Expected, Candidate, Shown: string;
  begin
    Result := False;
    if (CharIndex < 0) or (CharIndex >= CharCount) or (FAttrs[CharIndex].ImageSource = '') then Exit;
    Expected := UTF8Copy(DisplayText, 1, CharIndex) + Marker + UTF8Copy(DisplayText, CharIndex + 2, MaxInt);
    P := Pos('![', Source);
    Attempts := 0;
    while P > 0 do
    begin
      E := P + 2;
      while E <= Length(Source) do
      begin
        if Source[E] in [']', ')'] then
        begin
          Candidate := Copy(Source, 1, P - 1) + Marker + Copy(Source, E + 1, MaxInt);
          Probe.LoadMarkdown(Candidate);
          Shown := StringReplace(Probe.PlainText, LineEnding, #10, [rfReplaceAll]);
          if Shown = Expected then
          begin
            ByteFirst := P;
            ByteCount := E - P + 1;
            Exit(True);
          end;
          Inc(Attempts);
          if Attempts >= 256 then Exit;
        end;
        Inc(E);
      end;
      P := PosEx('![', Source, P + 2);
    end;
  end;

  function Endpoint(CharIndex, Limit: integer; AtEnd: boolean; out Offset: integer): boolean;
  var
    Width, P, N, FirstChar: integer;
  begin
    for Width := Min(8, Limit) downto 1 do
    begin
      FirstChar := CharIndex;
      if AtEnd then FirstChar := CharIndex - Width;
      if FindRange(FirstChar, Width, P, N) then
      begin
        Offset := P;
        if AtEnd then Inc(Offset, N);
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function EmptyPosition(out Offset: integer): boolean;
  var
    Blocks: TInkMarkdownBlocks;
    BlockID, P, FirstByte, EndByte, Attempts: integer;
    Expected, Candidate, Shown: string;
  begin
    Result := False;
    Expected := UTF8Copy(DisplayText, 1, GetSelStart) + Marker + UTF8Copy(DisplayText, GetSelStart + 1, MaxInt);
    FirstByte := 1;
    EndByte := Length(Source) + 1;
    Blocks := MarkdownBlocks(Source, [imoInlineHTML]);
    BlockID := 0;
    if GetSelStart < CharCount then BlockID := FAttrs[GetSelStart].MarkdownBlock
    else if CharCount > 0 then BlockID := FAttrs[CharCount - 1].MarkdownBlock;
    if (BlockID > 0) and (BlockID <= Length(Blocks)) then
    begin
      FirstByte := Blocks[BlockID - 1].First;
      EndByte := FirstByte + Blocks[BlockID - 1].Count;
    end;
    Attempts := 0;
    for P := FirstByte to EndByte do
      if (P > Length(Source)) or (Source[P] in [' ', #9, #10, #13, '|']) then
      begin
        Candidate := Copy(Source, 1, P - 1) + Marker + Copy(Source, P, MaxInt);
        Probe.LoadMarkdown(Candidate);
        Shown := StringReplace(Probe.PlainText, LineEnding, #10, [rfReplaceAll]);
        if Shown = Expected then
        begin
          Offset := P;
          Exit(True);
        end;
        Inc(Attempts);
        if Attempts >= 256 then Break;
      end;
  end;

begin
  AFirst := 0;
  ACount := 0;
  Source := AsMarkdown;
  DisplayText := StringReplace(PlainText, LineEnding, #10, [rfReplaceAll]);
  Marker := 'LazInkSourcePosition';
  while Pos(Marker, Source) > 0 do Marker := Marker + 'X';
  Probe := TInkRichEdit.Create(nil);
  try
    if GetSelLength = 0 then
    begin
      Start := GetSelStart;
      if FindImage(Start, AFirst, ObjectCount) then Exit(True);
      if FindImage(Start - 1, AFirst, ObjectCount) then
      begin
        Inc(AFirst, ObjectCount);
        Exit(True);
      end;
      Result := Endpoint(Start, CharCount - Start, False, AFirst) or Endpoint(Start, Start, True, AFirst) or EmptyPosition(AFirst);
      Exit;
    end;
    if (GetSelLength = 1) and FindImage(GetSelStart, AFirst, ACount) then Exit(True);
    if FindRange(GetSelStart, GetSelLength, AFirst, ACount) then Exit(True);
    Start := GetSelStart;
    Last := Start + GetSelLength;
    Result := Endpoint(Start, GetSelLength, False, AFirst) and Endpoint(Last, GetSelLength, True, Finish);
    if Result then
    begin
      ACount := Finish - AFirst;
      Result := ACount > 0;
    end;
  finally
    Probe.Free
  end;
end;

procedure TInkRichEdit.GoToSource;
begin
  if Assigned(FOnGoToSource) then FOnGoToSource(Self);
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
  cHeadFactor: array[ipkH1..ipkH6] of double = (2.0, 1.5, 1.17, 1.0, 0.83, 0.67);
var
  Sz: integer;
begin
  if A.Face <> '' then
    Canvas.Font.Name := A.Face
  else if A.Kind in [ipkCode, ipkSource] then
    Canvas.Font.Name := InkMonoFace
  else
    Canvas.Font.Name := Font.Name;
  if A.Size > 0 then Sz := A.Size
  else
    Sz := Font.Size;
  if Sz = 0 then Sz := Screen.SystemFont.Size;
  { GTK2 gives the system font no size; the handle knows it, in pixels }
  if Sz = 0 then
  begin
    if FDefaultSize = 0 then FDefaultSize := Max(1, Round(Abs(GetFontData(Font.Handle).Height) * 72 / Font.PixelsPerInch));
    Sz := FDefaultSize;
  end;
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
    { the same blues as TInkPage: dark on a light page, light on a dark one }
    if (A.Color = clDefault) and (HTMLContrastColor(Color) = clWhite) then
      Canvas.Font.Color := RGBToColor($58, $A6, $FF)
    else if A.Color = clDefault then
      Canvas.Font.Color := RGBToColor($09, $69, $DA)
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
  else if A.Kind = ipkQuote then
    { quoted words are muted, as on TInkPage's Markdown page }
    Canvas.Font.Color := MixColor(Font.Color, Color, 0.3)
  else
    Canvas.Font.Color := Font.Color;
end;

{ the paragraph kind at a character; the gap past the end is plain text }
function TInkRichEdit.ParaKindAt(AIndex: integer): TInkParaKind;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FAttrs[AIndex].Kind
  else
    Result := ipkText;
end;

function TInkRichEdit.ParaLevelAt(AIndex: integer): integer;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FAttrs[AIndex].Level
  else
    Result := 0;
end;

{ a list marker's gutter - one more gutter per nesting level - a quote's
  bar and inset, a code line's inset.  Measured in the control's font,
  which it leaves on the canvas. }
function TInkRichEdit.ParaIndent(AKind: TInkParaKind; ALevel: integer): integer;
begin
  Canvas.Font := Font;
  case AKind of
    ipkBullet, ipkNumber: Result := Canvas.TextWidth('99. ') * (ALevel + 1);
    ipkQuote: Result := QuoteBarWidth + FontEm;
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
function TInkRichEdit.ParaNumber(AFirst: integer): integer;
var
  i, j, MyLevel: integer;
begin
  Result := 1;
  MyLevel := ParaLevelAt(AFirst);
  i := AFirst - 1;
  while (i >= 0) and (FChars[i] = #10) do
  begin
    if (FAttrs[i].Kind = ipkNumber) and (FAttrs[i].Level = MyLevel) then
      Inc(Result)
    else if not ((FAttrs[i].Kind in [ipkBullet, ipkNumber]) and (FAttrs[i].Level > MyLevel)) then
      Break;
    j := i - 1;
    while (j >= 0) and (FChars[j] <> #10) do Dec(j);
    i := j;
  end;
end;

procedure TInkRichEdit.SetImageBaseURI(const Value: string);
begin
  if FImageBase = Value then Exit;
  FImageBase := Value;
  ClearImages;
  InvalidateLayout;
end;

procedure TInkRichEdit.ClearImages;
begin
  FImages.Clear;
  FMoving.Clear;
  FMovingRects := nil;
  FMotionTimer.Enabled := False;
end;

function TInkRichEdit.ImagePicture(const Source: string): TPicture;
var
  I: integer;
  Address, FileName: string;
  Data: TMemoryStream;
  Head: rawbytestring;
  Motion: TObject;
begin
  I := FImages.IndexOf(Source);
  if I >= 0 then Exit(TPicture(FImages.Objects[I]));
  Result := TPicture.Create;
  FImages.AddObject(Source, Result);
  Data := TMemoryStream.Create;
  Motion := nil;
  try
    try
      if Assigned(FOnImageNeeded) then FOnImageNeeded(Self, Source, Result);
      if Result.Graphic <> nil then Exit;
      if not ResolveRelativeURI(FImageBase, Source, Address) then Address := Source;
      if not URIToFilename(Address, FileName) then FileName := Address;
      if not FileExists(FileName) then Exit;
      Data.LoadFromFile(FileName);
      SetLength(Head, Min(12, Data.Size));
      if Head <> '' then Data.ReadBuffer(Head[1], Length(Head));
      Data.Position := 0;
      { TPicture cannot read WebP; LazInk's own decoders read it, and play
        a GIF or WebP that moves, as TInkPage does }
      if InkIsWebP(Head) then
      begin
        Motion := TInkWebP.Create(Data);
        if TInkWebP(Motion).Decoded then Result.Assign(TInkWebP(Motion).Bitmap);
        if not (TInkWebP(Motion).Decoded and TInkWebP(Motion).Animated) then FreeAndNil(Motion);
      end
      else
      begin
        Result.LoadFromStream(Data);
        if Result.Graphic is TGIFImage then
        begin
          Motion := TInkGIF.Create(Data);
          if TInkGIF(Motion).FrameCount > 1 then
            Result.Assign(TInkGIF(Motion).Bitmap)
          else
            FreeAndNil(Motion);
        end;
      end;
      if Motion <> nil then
      begin
        FMoving.AddObject(Source, Motion);
        Motion := nil;
        SetLength(FMovingRects, FMoving.Count);
        FMovingRects[FMoving.Count - 1] := Rect(0, 0, 0, 0);
        FMotionTimer.Enabled := True;
      end;
    except
      on E: Exception do Result.Clear;
    end;
  finally
    Motion.Free;
    Data.Free;
  end;
end;

procedure TInkRichEdit.MotionTick(Sender: TObject);
var
  I: integer;
  Moved: boolean;
  R: TRect;
begin
  if not Visible or not HandleAllocated then Exit;
  { only what was on screen at the last paint moves; the rest waits }
  for I := 0 to FMoving.Count - 1 do
  begin
    if IsRectEmpty(FMovingRects[I]) then Continue;
    if FMoving.Objects[I] is TInkWebP then
      Moved := TInkWebP(FMoving.Objects[I]).Advance
    else
      Moved := TInkGIF(FMoving.Objects[I]).Advance;
    if not Moved then Continue;
    if FMoving.Objects[I] is TInkWebP then
      ImagePicture(FMoving[I]).Assign(TInkWebP(FMoving.Objects[I]).Bitmap)
    else
      ImagePicture(FMoving[I]).Assign(TInkGIF(FMoving.Objects[I]).Bitmap);
    R := FMovingRects[I];
    LCLIntf.InvalidateRect(Handle, @R, False);
  end;
end;

{ The drawn size: the tag's width and height when it gives them, the
  picture's own otherwise, never wider than the line. }
function TInkRichEdit.ImageWidth(AIndex: integer): integer;
var
  Picture: TPicture;
  W: integer;
begin
  Picture := ImagePicture(FAttrs[AIndex].ImageSource);
  W := FAttrs[AIndex].ImageWidth;
  if (W = 0) and (FAttrs[AIndex].ImageHeight > 0) and (Picture.Height > 0) then
    W := Max(1, Round(Picture.Width * (FAttrs[AIndex].ImageHeight / Picture.Height)));
  if W = 0 then W := Picture.Width;
  if W > 0 then Result := Min(W, LineTextWidth)
  else
    Result := Min(LineTextWidth, Max(32, Canvas.TextWidth(FAttrs[AIndex].ImageAlt) + 8));
end;

function TInkRichEdit.ImageHeight(AIndex: integer): integer;
var
  Picture: TPicture;
  W, H, Asked: integer;
begin
  Picture := ImagePicture(FAttrs[AIndex].ImageSource);
  W := ImageWidth(AIndex);
  H := FAttrs[AIndex].ImageHeight;
  Asked := FAttrs[AIndex].ImageWidth;
  if (H > 0) and (Asked > 0) then
    Result := Max(1, Round(H * (W / Asked)))        { the tag's shape, scaled with a cut width }
  else if (H > 0) and (Picture.Height = 0) then
    Result := H
  else if (H > 0) and (Asked = 0) then
    Result := Max(1, Round(H * (W / Max(1, Round(Picture.Width * (H / Picture.Height))))))
  else if Picture.Width > 0 then Result := Max(1, Round(Picture.Height * (W / Picture.Width)))
  else
    Result := Canvas.TextHeight('Ag') + 8;
end;

function TInkRichEdit.LockedAt(AIndex: integer): boolean;
var
  B: integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= CharCount) then Exit;
  B := FAttrs[AIndex].MarkdownBlock;
  Result := (B > 0) and (B <= Length(FMarkdownOriginals)) and FMarkdownOriginals[B - 1].Locked and (B <> FOpenBlock);
end;

{ ---- an HTML block's source, edited in place ------------------------- }

{ the characters of one source block: [AFirst, ALast) }
function TInkRichEdit.BlockRange(ABlock: integer; out AFirst, ALast: integer): boolean;
begin
  AFirst := 0;
  while (AFirst < CharCount) and (FAttrs[AFirst].MarkdownBlock <> ABlock) do Inc(AFirst);
  ALast := AFirst;
  while (ALast < CharCount) and (FAttrs[ALast].MarkdownBlock = ABlock) do Inc(ALast);
  Result := ALast > AFirst;
end;

{ the block's HTML as it stands: edited here, or as the file has it }
function TInkRichEdit.BlockSource(ABlock: integer): string;
begin
  if FMarkdownOriginals[ABlock - 1].Edited <> '' then Result := FMarkdownOriginals[ABlock - 1].Edited
  else
    Result := Copy(FMarkdownSource, FMarkdownOriginals[ABlock - 1].First, FMarkdownOriginals[ABlock - 1].Count);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] in [#10, #13]) do Delete(Result, Length(Result), 1);
end;

{ AText takes the block's place, with one attribute for all of it or one per
  character; the #10 that ended the block stays.  Answers the change in length. }
function TInkRichEdit.ReplaceBlock(ABlock: integer; AText: string; const AAttrs: array of TInkAttr): integer;
var
  First, Last, I, N: integer;
  A: TInkAttr;
begin
  Result := 0;
  if not BlockRange(ABlock, First, Last) then Exit;
  if FChars[Last - 1] = #10 then AText := AText + #10;
  DoDelete(First, Last);
  A := AAttrs[0];
  A.MarkdownBlock := ABlock;
  FCaret := First;
  DoInsert(AText, A);
  N := FCaret - First;
  if Length(AAttrs) > 1 then
  begin
    for I := 0 to Min(N, Length(AAttrs)) - 1 do
    begin
      FAttrs[First + I] := AAttrs[I];
      FAttrs[First + I].MarkdownBlock := ABlock;
    end;
    { the #10 that ends the block is a break, not another picture or link:
      it carries only the kind and alignment of the paragraph it ends }
    if N > Length(AAttrs) then
    begin
      A := DefaultInkAttr;
      A.Kind := FAttrs[First + N - 2].Kind;
      A.Level := FAttrs[First + N - 2].Level;
      A.Align := FAttrs[First + N - 2].Align;
      A.MarkdownBlock := ABlock;
      FAttrs[First + N - 1] := A;
    end;
  end;
  Result := N - (Last - First);
end;

procedure TInkRichEdit.OpenBlock(ABlock: integer);
var
  A: TInkAttr;
begin
  A := DefaultInkAttr;
  A.Kind := ipkSource;
  ReplaceBlock(ABlock, BlockSource(ABlock), [A]);
  FOpenBlock := ABlock;
end;

{ The block draws again from its source as it now stands.  A source that
  draws nothing stays source, an ordinary block from here on. }
function TInkRichEdit.CloseBlock(ABlock: integer): integer;
var
  First, Last, I: integer;
  Src: string;
  Lines: TStringList;
  Chars: array of string;
  Attrs, Drawn: array of TInkAttr;
begin
  Result := 0;
  FOpenBlock := 0;
  if not BlockRange(ABlock, First, Last) then Exit;
  Src := '';
  for I := First to Last - 1 do Src := Src + FChars[I];
  while (Src <> '') and (Src[Length(Src)] = #10) do Delete(Src, Length(Src), 1);
  if Src <> BlockSource(ABlock) then FMarkdownOriginals[ABlock - 1].Edited := Src;
  Lines := TStringList.Create;
  try
    MarkdownHTMLToParagraphs(MarkdownToHTML(Src, [imoRawHTML]), Lines);
    if Lines.Count = 0 then
    begin
      FMarkdownOriginals[ABlock - 1].Locked := False;
      Exit;
    end;
    { the markup reader writes into the document; lend it an empty one }
    Chars := FChars;
    Attrs := FAttrs;
    FChars := nil;
    FAttrs := nil;
    for I := 0 to Lines.Count - 1 do ParseInto(Lines[I], I > 0);
    for I := High(FChars) downto 1 do
      if (FChars[I] = #10) and (FChars[I - 1] <> #10) then
      begin
        FAttrs[I].Kind := FAttrs[I - 1].Kind;
        FAttrs[I].Align := FAttrs[I - 1].Align;
      end;
    Src := '';
    for I := 0 to High(FChars) do Src := Src + FChars[I];
    Drawn := FAttrs;
    FChars := Chars;
    FAttrs := Attrs;
  finally
    Lines.Free;
  end;
  Result := ReplaceBlock(ABlock, Src, Drawn);
end;

{ The caret moved: the locked block it left draws again, the one it entered
  opens as source.  The caret keeps its place in the text around them. }
procedure TInkRichEdit.SyncOpenBlock;
var
  B, Keep, First, Last: integer;
  WasModified: boolean;
  Quiet: TNotifyEvent;
begin
  if FSyncing or (Length(FMarkdownOriginals) = 0) then Exit;
  B := 0;
  if FCaret < CharCount then B := FAttrs[FCaret].MarkdownBlock
  else if CharCount > 0 then B := FAttrs[CharCount - 1].MarkdownBlock;
  if B = FOpenBlock then Exit;
  if (FOpenBlock = 0) and not LockedAt(Min(FCaret, CharCount - 1)) then Exit;
  { opening and closing is not an edit: the document is as modified as it
    was, and the host hears nothing; typing inside the block says so itself }
  FSyncing := True;
  WasModified := FModified;
  Quiet := FOnChange;
  FOnChange := nil;
  try
    PushUndo(False);
    Keep := FCaret;
    if FOpenBlock > 0 then
    begin
      BlockRange(FOpenBlock, First, Last);
      if Keep >= Last then Inc(Keep, CloseBlock(FOpenBlock))
      else CloseBlock(FOpenBlock);
    end;
    if LockedAt(Min(Keep, CharCount - 1)) then
    begin
      B := FAttrs[Min(Keep, CharCount - 1)].MarkdownBlock;
      OpenBlock(B);
      BlockRange(B, Keep, Last);
    end;
    FCaret := Max(0, Min(Keep, CharCount));
    FAnchor := FCaret;
  finally
    FOnChange := Quiet;
    FModified := WasModified;
    FSyncing := False;
  end;
end;

function TInkRichEdit.RangeLocked(AFrom, ATo: integer): boolean;
var
  K: integer;
begin
  for K := Max(0, AFrom) to Min(CharCount, ATo) - 1 do
    if LockedAt(K) then Exit(True);
  Result := False;
end;

{ Typing goes before the character at the caret, so that character says
  whose paragraph it joins; after the last character, the last one does. }
function TInkRichEdit.EditLocked: boolean;
begin
  if GetSelLength > 0 then Exit(RangeLocked(GetSelStart, GetSelStart + GetSelLength));
  if CharCount = 0 then Exit(False);
  if FCaret < CharCount then Exit(LockedAt(FCaret));
  Result := LockedAt(CharCount - 1);
end;

function TInkRichEdit.MeasureChar(AIndex: integer): integer;
begin
  if FChars[AIndex] = #10 then
    Result := 0
  else if FAttrs[AIndex].TaskState >= 0 then
    Result := HTMLTextExtentOpt(Canvas, Rect(0, 0, 100, 100), [], InkCheckboxMarkup(FAttrs[AIndex].TaskState = 1), DefaultHTMLOptions).cx
  else if FAttrs[AIndex].ImageSource <> '' then
    Result := ImageWidth(AIndex)
  else if FChars[AIndex] = #9 then
    { a tab is four spaces wide, drawn as such; no tab stops }
    Result := Canvas.TextWidth('    ')
  else
    Result := Canvas.TextWidth(FChars[AIndex]);
end;

function TInkRichEdit.LineTextWidth: integer;
begin
  Result := ClientWidth - 2 * cMargin;
  if FVScroll.Visible then Dec(Result, FVScroll.Width);
  if Result < 16 then Result := 16;
end;

procedure TInkRichEdit.Relayout;
var
  N, i, k, X, W, Avail, AvailP, Y, LineStart, LastSpace, BreakAt: integer;
  LineCount: integer;
  LastAttr: TInkAttr;
  tm: TLCLTextMetric;
  { the word so far in the current run, and its measured width }
  WordText: string;
  WordW: integer;
  HasLast: boolean;
  CurKind: TInkParaKind;
  CurInd: integer;
  { the full width a table row's line reports, while one is being laid }
  TableRowW: integer;
  { space owed above the next paragraph's first line, the font's em, and
    the room either side of an inline code span }
  Gap, Em, CodePad: integer;

  { A block's margin in hundredths of the body's em, from the default
    stylesheet: 1em, and a heading's own margin times its size. }
  function Margin(AKind: TInkParaKind): integer;
  begin
    case AKind of
      ipkH1: Result := 134;
      ipkH2: Result := 125;
      ipkH3: Result := 117;
      ipkH4: Result := 133;
      ipkH5: Result := 139;
      ipkH6: Result := 156;
      ipkTableHead, ipkTableRow: Result := 0;
      else
        Result := 100;
    end;
  end;

  { the space between two paragraphs; margins collapse to the larger one }
  procedure SpaceBetween(AAt: integer);
  var
    Prev, Next: TInkParaKind;
    K: integer;
  begin
    Gap := 0;
    if not FParagraphSpacing then Exit;
    Prev := ParaKindAt(AAt);
    Next := ParaKindAt(AAt + 1);
    { one list goes on while it nests, or while its top level keeps its kind }
    if (Prev in [ipkBullet, ipkNumber]) and (Next in [ipkBullet, ipkNumber]) then
    begin
      if ParaLevelAt(AAt + 1) > 0 then Exit;
      K := AAt;
      while (K > 0) and (ParaKindAt(K) in [ipkBullet, ipkNumber]) and (ParaLevelAt(K) > 0) do Dec(K);
      if ParaKindAt(K) = Next then Exit;
    end;
    if (Prev = Next) and (Prev in [ipkQuote, ipkCode, ipkSource]) then Exit;
    Gap := Em * Max(Margin(Prev), Margin(Next)) div 100;
  end;

  { Height and baseline of the characters [AFirst, AFirst+ACount). An empty
    paragraph still needs a line box, so fall back to the control font. }
  procedure EmitLine(AFirst, ACount: integer);
  var
    j, H, Asc, MaxH, MaxAsc, Rise: integer;
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
      if FAttrs[j].ImageSource <> '' then
      begin
        H := ImageHeight(j);
        Asc := H;
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

    Inc(Y, Gap);
    Gap := 0;
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
    GEnd, j, c, NCols, RowStart, CellW, ColCount, CellFirst: integer;
    ColW, ColX: array of integer;

    procedure AlignCell(AEnd: integer);
    var
      K, Extra: integer;
      A: char;
    begin
      if (c >= NCols) or (CellFirst >= AEnd) then Exit;
      A := '-';
      if c < Length(FAttrs[CellFirst].TableAlign) then A := FAttrs[CellFirst].TableAlign[c + 1];
      Extra := Max(0, ColX[c + 1] - cCellPad - X);
      if A = 'c' then Extra := Extra div 2
      else if A <> 'r' then Exit;
      for K := CellFirst to AEnd - 1 do Inc(FCharX[K], Extra);
    end;

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
        if (GEnd + 1 >= N) or not (FAttrs[GEnd + 1].Kind in [ipkTableHead, ipkTableRow]) then
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
      if (FChars[j] = #10) or IsCellBreak(j) then
      begin
        FCharW[j] := 0;
        CloseCell;
        if IsCellBreak(j) then Inc(c)
        else
          c := 0;
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
    CellFirst := i;
    c := 0;
    X := ColX[0] + cCellPad;
    for j := i to GEnd - 1 do
    begin
      if FChars[j] = #10 then
      begin
        AlignCell(j);
        FCharX[j] := X;
        FCharW[j] := 0;
        EmitLine(RowStart, j - RowStart + 1);
        RowStart := j + 1;
        CellFirst := j + 1;
        c := 0;
        X := ColX[0] + cCellPad;
        Continue;
      end;
      if IsCellBreak(j) then
      begin
        AlignCell(j);
        CellFirst := j + 1;
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
    if RowStart < GEnd then
    begin
      AlignCell(GEnd);
      EmitLine(RowStart, GEnd - RowStart);
    end;
    TableRowW := 0;

    { the main loop picks up after the group }
    i := GEnd;
    LineStart := GEnd;
    X := 0;
    LastSpace := -1;
    HasLast := False;
    if GEnd > 0 then SpaceBetween(GEnd - 1);
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
  Gap := 0;
  WordText := '';
  WordW := 0;
  Canvas.Font := Font;
  Em := FontEm;
  CodePad := Em * 2 div 5;
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
      if not FAttrs[i].HardBreak then SpaceBetween(i);
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
      WordText := '';
      WordW := 0;
    end;
    { A word is measured whole and each letter gets what it adds: macOS
      widths are fractional, and rounding letter by letter drifts. }
    if (FChars[i] = ' ') or (FChars[i] = #9) or (FAttrs[i].TaskState >= 0) or (FAttrs[i].ImageSource <> '') then
    begin
      W := MeasureChar(i);
      WordText := '';
      WordW := 0;
    end
    else
    begin
      WordText := WordText + FChars[i];
      W := Canvas.TextWidth(WordText) - WordW;
      Inc(WordW, W);
    end;
    if IsCodeSpan(i) then
    begin
      if not IsCodeSpan(i - 1) then Inc(W, CodePad);
      if not IsCodeSpan(i + 1) then Inc(W, CodePad);
    end;

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
    if (FChars[i] = ' ') or (FChars[i] = #9) or HTMLIsCJK(FChars[i]) then LastSpace := i;
    Inc(i);
  end;

  // the tail, and the empty line a document ending in #10 leaves behind
  EmitLine(LineStart, N - LineStart);
  SetLength(FLines, LineCount);
  FDocHeight := Y;
  UpdateScrollBar;
end;

function TInkRichEdit.LineOfChar(AIndex: integer): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FLines) do
    if (AIndex >= FLines[i].First) and (AIndex < FLines[i].First + FLines[i].Count) then
      Exit(i);
  if Length(FLines) > 0 then Result := High(FLines);
end;

{ A caret on a wrap boundary could be claimed by either line; it goes to the
  start of the next one, except at the very end where there is no next one. }
function TInkRichEdit.CaretLine(ACaret: integer): integer;
var
  Idx: integer;
begin
  NeedLayout;
  Result := High(FLines);
  if Length(FLines) = 0 then Exit(0);
  if ACaret >= CharCount then Exit(High(FLines));
  for Idx := 0 to High(FLines) do
    if ACaret < FLines[Idx].First + FLines[Idx].Count then
      Exit(Idx);
end;

function TInkRichEdit.CaretPoint(ACaret: integer): TPoint;
var
  L: integer;
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

function TInkRichEdit.PointToCaret(X, Y: integer): integer;
var
  L, i, DocY, CX, Last: integer;
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
  NeedBar: boolean;
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
  L, H: integer;
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

function TInkRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not FVScroll.Visible then Exit;
  FScrollY := FScrollY + InkWheelPixels(WheelDelta, 45, FWheelRest);
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
  Li, i, RunEnd, SelA, SelB, LineEndIdx, BaseY, RunTop, WordStart, K: integer;
  S: string;
  Sel, RunSel: boolean;
  L: TInkVisLine;
  tm: TLCLTextMetric;
  RunAsc, RunH, Rise, X: integer;
  GridC: TColor;
  BX, LT, LB: integer;
  IsTbl: boolean;
  CodePad: integer;

{ the room in front of an inline code span's first letter }
  function CodeLead(AIndex: integer): integer;
  begin
    if IsCodeSpan(AIndex) and not IsCodeSpan(AIndex - 1) then
      Result := CodePad
    else
      Result := 0;
  end;

  { the grid's color: the background mixed a sixth toward the text }
  function BlendToText(ANum, ADen: integer): TColor;
  begin
    Result := RGBToColor(Red(ColorToRGB(Color)) + (Red(ColorToRGB(Font.Color)) - Red(ColorToRGB(Color))) * ANum div ADen,
      Green(ColorToRGB(Color)) + (Green(ColorToRGB(Font.Color)) - Green(ColorToRGB(Color))) * ANum div ADen, Blue(ColorToRGB(Color)) +
      (Blue(ColorToRGB(Font.Color)) - Blue(ColorToRGB(Color))) * ANum div ADen);
  end;

  function IsSel(AIdx: integer): boolean;
  begin
    Result := (AIdx >= SelA) and (AIdx < SelB);
  end;

begin
  CodePad := FontEm * 2 div 5;
  Canvas.Brush.Color := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  NeedLayout;
  for K := 0 to High(FMovingRects) do
    FMovingRects[K] := Rect(0, 0, 0, 0);
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
        Canvas.Brush.Color := RGBToColor(Red(ColorToRGB(Color)) + (Red(ColorToRGB(Font.Color)) - Red(ColorToRGB(Color))) div
          12, Green(ColorToRGB(Color)) + (Green(ColorToRGB(Font.Color)) - Green(ColorToRGB(Color))) div 12, Blue(ColorToRGB(Color)) +
          (Blue(ColorToRGB(Font.Color)) - Blue(ColorToRGB(Color))) div 12);
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(cMargin, L.Top - FScrollY,
          cMargin + LineTextWidth, L.Top - FScrollY + L.Height);
      end;
      ipkQuote:
      begin
        Canvas.Brush.Color := MixColor(Font.Color, Color, 0.6);
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(cMargin, L.Top - FScrollY,
          cMargin + QuoteBarWidth, L.Top - FScrollY + L.Height);
      end;
      ipkTableHead, ipkTableRow:
      begin
        LT := L.Top - FScrollY;
        LB := LT + L.Height;
        { the grid a quarter of the way to the text and the head row on the
          page's own background, as on TInkPage's Markdown page }
        GridC := BlendToText(1, 4);
        Canvas.Pen.Color := GridC;
        Canvas.Pen.Style := psSolid;
          { the frame: a top edge on the table's first row, a bottom edge
            and the two sides on every row }
        if (L.First = 0) or ((L.First > 0) and not (FAttrs[L.First - 1].Kind in [ipkTableHead, ipkTableRow])) then
          Canvas.Line(L.Left, LT, L.Left + L.Width, LT);
        Canvas.Line(L.Left, LB - 1, L.Left + L.Width, LB - 1);
        Canvas.Line(L.Left, LT, L.Left, LB);
        Canvas.Line(L.Left + L.Width - 1, LT, L.Left + L.Width - 1, LB);
        { and a line where each '|' hands one cell to the next }
        for BX := L.First to L.First + L.Count - 1 do
          if (BX < CharCount) and IsCellBreak(BX) then
            Canvas.Line(L.Left + FCharX[BX] + FCharW[BX] - cCellPad, LT,
              L.Left + FCharX[BX] + FCharW[BX] - cCellPad, LB);
      end;
      ipkBullet, ipkNumber:
        if (L.First = 0) or ((L.First > 0) and (L.First <= CharCount) and (FChars[L.First - 1] = #10)) then
        begin
          Canvas.Font := Font;
          Canvas.Font.Color := Font.Color;
          Canvas.Brush.Style := bsClear;
          if Canvas.GetTextMetrics(tm) then
            RunAsc := tm.Ascender
          else
            RunAsc := Canvas.TextHeight('Ag') * 4 div 5;
          if FAttrs[L.First].TaskState >= 0 then S := ''
          else if ParaKindAt(L.First) = ipkBullet then
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
      if (FChars[i] = #10) or (IsTbl and IsCellBreak(i)) then
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

      if FAttrs[i].TaskState >= 0 then
      begin
        Canvas.Font := Font;
        HTMLDrawOpt(Canvas, Rect(L.Left + FCharX[i], L.Top - FScrollY, L.Left + FCharX[i] + FCharW[i], L.Top - FScrollY + L.Height), [],
          InkCheckboxMarkup(FAttrs[i].TaskState = 1), DefaultHTMLOptions);
        Inc(i);
        Continue;
      end;

      if FAttrs[i].ImageSource <> '' then
      begin
        RunTop := BaseY - ImageHeight(i);
        if ImagePicture(FAttrs[i].ImageSource).Graphic <> nil then
        begin
          Canvas.StretchDraw(Rect(L.Left + FCharX[i], RunTop, L.Left + FCharX[i] + FCharW[i], BaseY), ImagePicture(FAttrs[i].ImageSource).Graphic);
          K := FMoving.IndexOf(FAttrs[i].ImageSource);
          if K >= 0 then
            if IsRectEmpty(FMovingRects[K]) then
              FMovingRects[K] := Rect(L.Left + FCharX[i], RunTop, L.Left + FCharX[i] + FCharW[i], BaseY)
            else
              UnionRect(FMovingRects[K], FMovingRects[K], Rect(L.Left + FCharX[i], RunTop, L.Left + FCharX[i] + FCharW[i], BaseY));
        end
        else
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Pen.Color := clGray;
          Canvas.Rectangle(L.Left + FCharX[i], RunTop, L.Left + FCharX[i] + FCharW[i], BaseY);
          Canvas.Font := Font;
          Canvas.Font.Color := Font.Color;
          Canvas.TextOut(L.Left + FCharX[i] + 4, RunTop + 4, FAttrs[i].ImageAlt);
        end;
        if IsSel(i) then
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Pen.Color := clHighlight;
          Canvas.Rectangle(L.Left + FCharX[i], RunTop, L.Left + FCharX[i] + FCharW[i], BaseY);
        end;
        Inc(i);
        Continue;
      end;

      RunSel := IsSel(i);
      RunEnd := i;
      while (RunEnd + 1 < LineEndIdx) and (FChars[RunEnd + 1] <> #10) and not (IsTbl and IsCellBreak(RunEnd + 1)) and
        SameInkAttr(EffAttr(RunEnd + 1), EffAttr(i)) and (IsSel(RunEnd + 1) = RunSel) do
        Inc(RunEnd);

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
      else if IsCodeSpan(i) and (EffAttr(i).BackColor = clNone) then
      begin
        { inline code on its chip, as on TInkPage's Markdown page }
        Canvas.Brush.Color := HTMLShadeColor(ColorToRGB(Color), 7);
        Canvas.Brush.Style := bsSolid;
        Canvas.Pen.Color := Canvas.Brush.Color;
        Canvas.RoundRect(X, RunTop, L.Left + FCharX[RunEnd] + FCharW[RunEnd], RunTop + RunH, 6, 6);
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

      { word by word, each where Relayout measured it to be, so a run drawn
        in one go cannot drift from the caret on fractional-width fonts.  An
        underline or a strike line has to run through the spaces, and Cocoa
        draws none under a space at either end of a piece, so those runs -
        links, mostly short - go in one piece. }
      WordStart := i;
      S := '';
      for K := i to RunEnd do
      begin
        if ((FChars[K] = ' ') or (FChars[K] = #9)) and (S <> '') and (Canvas.Font.Style * [fsUnderline, fsStrikeOut] = []) then
        begin
          Canvas.TextOut(L.Left + FCharX[WordStart] + CodeLead(WordStart), RunTop, S);
          WordStart := K;
          S := '';
        end;
        if FChars[K] = #9 then
          S := S + '    '
        else
          S := S + FChars[K];
      end;
      Canvas.TextOut(L.Left + FCharX[WordStart] + CodeLead(WordStart), RunTop, S);
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
  if FindBarVisible then PaintFindBar;
end;

procedure TInkRichEdit.Resize;
begin
  inherited Resize;
  InvalidateLayout;
  if FVScroll <> nil then
    UpdateScrollBar;
  PlaceFindBar;
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

function TInkRichEdit.EffAttr(AIndex: integer): TInkAttr;
begin
  Result := FAttrs[AIndex];
  AdjustAttr(AIndex, Result);
end;

procedure TInkRichEdit.AdjustAttr(AIndex: integer; var A: TInkAttr);
begin
  { the base editor draws what the document says }
end;

function TInkRichEdit.CharAt(AIndex: integer): string;
begin
  if (AIndex >= 0) and (AIndex < CharCount) then
    Result := FChars[AIndex]
  else
    Result := '';
end;

function TInkRichEdit.DocumentHeight: integer;
begin
  NeedLayout;
  Result := FDocHeight;
end;

procedure TInkRichEdit.InsertImage(const Source, AltText: string; const Title: string);
var
  A: TInkAttr;
begin
  if FReadOnly or EditLocked or (Trim(Source) = '') or (SelParaKind in [ipkCode, ipkSource]) then Exit;
  PushUndo(False);
  A := AttrAtCaret;
  A.Face := '';
  A.Style := [];
  A.ImageSource := Source;
  A.ImageAlt := AltText;
  A.ImageTitle := Title;
  if GetSelLength > 0 then DeleteSelection;
  DoInsert(#$EF#$BF#$BC, A);
end;

procedure TInkRichEdit.InsertPlainText(const AText: string);
var
  A: TInkAttr;
  Clean: string;
begin
  if FReadOnly or EditLocked then Exit;
  PushUndo(False);
  A := AttrAtCaret;
  if GetSelLength > 0 then DeleteSelection;
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
  else if (FCaret < CharCount) and ((FCaret = 0) or (FChars[FCaret - 1] = #10)) then
    Result := FAttrs[FCaret]
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
  Result.CellBreak := False;
  Result.ImageSource := '';
  Result.ImageAlt := '';
  Result.ImageTitle := '';
  Result.ImageWidth := 0;
  Result.ImageHeight := 0;
  Result.LinkTitle := '';
  Result.TaskState := -1;
  Result.HardBreak := False;
end;

procedure TInkRichEdit.DoInsert(const AText: string; const AAttr: TInkAttr);
var
  Incoming: array of string;
  P: PChar;
  CharLen, N, i, Old, BlockID: integer;
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

  BlockID := AAttr.MarkdownBlock;
  if (BlockID = 0) and (Length(FMarkdownOriginals) > 0) then
  begin
    BlockID := 1;
    if FCaret > 0 then BlockID := FAttrs[FCaret - 1].MarkdownBlock
    else if CharCount > 0 then BlockID := FAttrs[0].MarkdownBlock;
  end;
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
    FAttrs[FCaret + i].MarkdownBlock := BlockID;
    FAttrs[FCaret + i].CellBreak := AAttr.CellBreak and (Incoming[i] = '|');
  end;
  Inc(FCaret, N);
  FAnchor := FCaret;
  Changed;
end;

procedure TInkRichEdit.DoDelete(AFrom, ATo: integer);
var
  i, N, PS, PE, BlockID: integer;
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
  { Joining paragraphs makes the remaining paragraph one source block. }
  PS := AFrom;
  while (PS > 0) and (FChars[PS - 1] <> #10) do Dec(PS);
  PE := AFrom;
  while (PE < CharCount) and (FChars[PE] <> #10) do Inc(PE);
  if PS < PE then
  begin
    BlockID := FAttrs[PS].MarkdownBlock;
    for i := PS to PE - 1 do FAttrs[i].MarkdownBlock := BlockID;
  end;
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
  SyncOpenBlock;
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
  PS, PE, i, K: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
      if IsCellBreak(K) then Inc(i)
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
    A.CellBreak := True;
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
  PE := FCaret;
  while (PE < CharCount) and (FChars[PE] <> #10) do Inc(PE);
  DoInsert(#10, A);
  { a heading or a code line ends at its break; a list and a quote go on }
  if A.Kind in [ipkH1..ipkH6] then
  begin
    FTypingAttr := AttrAtCaret;
    FTypingAttr.Kind := ipkText;
    FTypingAttr.Style := FTypingAttr.Style - [fsBold];
    FHasTypingAttr := True;
  end
  { so does the last line of a source block, a --- for one; Enter there
    starts plain text, not more source }
  else if (A.Kind = ipkSource) and (FCaret = PE + 1) and (ParaKindAt(FCaret + 1) <> ipkSource) then
  begin
    if (FCaret < CharCount) and (FChars[FCaret] = #10) then FAttrs[FCaret].Kind := ipkText;
    FTypingAttr := A;
    FTypingAttr.Kind := ipkText;
    FHasTypingAttr := True;
  end;
end;

procedure TInkRichEdit.InsertTable(ACols, ARows: integer);
var
  A, TA: TInkAttr;
  r, Home: integer;
  RowTxt: string;
begin
  if FReadOnly or EditLocked then Exit;
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
  TA.CellBreak := True;
  TA.Kind := ipkTableHead;
  DoInsert(RowTxt, TA);
  for r := 1 to ARows do
  begin
    DoInsert(#10, TA);
    TA.Kind := ipkTableRow;
    DoInsert(RowTxt, TA);
  end;
  { and plain text follows it - the break belongs to the last row }
  if (FCaret >= CharCount) or (FChars[FCaret] <> #10) then
    DoInsert(#10, TA);
  FTypingAttr := A;
  FTypingAttr.Kind := ipkText;
  FHasTypingAttr := False;
  MoveCaret(Home, False);
end;

{ -------------------------------------------------------------- formatting  }

procedure TInkRichEdit.ApplyStyle(AStyle: TFontStyle; AOn: boolean);
var
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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

procedure TInkRichEdit.ApplySize(ASize: integer);
var
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
  i: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
  i: integer;
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
  i, A, B: integer;
begin
  if FReadOnly or EditLocked or (CharCount = 0) then Exit;
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
  i, A, B: integer;
begin
  if FReadOnly or EditLocked then Exit;
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
procedure TInkRichEdit.ApplyParaLevel(ADelta: integer);
var
  i, A, B, L: integer;
begin
  if FReadOnly or EditLocked or (CharCount = 0) then Exit;
  PushUndo(False);
  A := GetSelStart;
  B := GetSelStart + GetSelLength;
  while (A > 0) and (FChars[A - 1] <> #10) do Dec(A);
  while (B < CharCount) and (FChars[B] <> #10) do Inc(B);
  if (B < CharCount) and (FChars[B] = #10) then Inc(B);
  for i := A to B - 1 do
    if FAttrs[i].Kind in [ipkBullet, ipkNumber] then
    begin
      L := EnsureRange(integer(FAttrs[i].Level) + ADelta, 0, 5);
      FAttrs[i].Level := L;
    end;
  if FHasTypingAttr then
    FTypingAttr.Level := EnsureRange(integer(FTypingAttr.Level) + ADelta, 0, 5);
  FModified := True;
  FMarkupDirty := True;
  InvalidateLayout;
  if Assigned(FOnChange) then FOnChange(Self);
  SelectionChanged;
end;

procedure TInkRichEdit.ClearFormatting;
var
  i: integer;
  Keep: TAlignment;
  KeepKind: TInkParaKind;
  KeepAttr: TInkAttr;
begin
  if FReadOnly or EditLocked then Exit;
  if GetSelLength = 0 then
  begin
    KeepAttr := AttrAtCaret;
    FTypingAttr := DefaultInkAttr;
    FTypingAttr.Kind := KeepAttr.Kind;
    FTypingAttr.Level := KeepAttr.Level;
    FTypingAttr.Lang := KeepAttr.Lang;
    FTypingAttr.TableAlign := KeepAttr.TableAlign;
    FTypingAttr.MarkdownBlock := KeepAttr.MarkdownBlock;
    FHasTypingAttr := True;
    SelectionChanged;
    Exit;
  end;
  PushUndo(False);
  for i := GetSelStart to GetSelStart + GetSelLength - 1 do
  begin
    KeepAttr := FAttrs[i];
    Keep := FAttrs[i].Align;          // alignment is not character formatting
    KeepKind := FAttrs[i].Kind;       // and neither is what the paragraph is
    FAttrs[i] := DefaultInkAttr;
    FAttrs[i].Align := Keep;
    FAttrs[i].Kind := KeepKind;
    FAttrs[i].Level := KeepAttr.Level;
    FAttrs[i].Lang := KeepAttr.Lang;
    FAttrs[i].MarkdownBlock := KeepAttr.MarkdownBlock;
    FAttrs[i].TableAlign := KeepAttr.TableAlign;
    FAttrs[i].CellBreak := KeepAttr.CellBreak;
    FAttrs[i].ImageSource := KeepAttr.ImageSource;
    FAttrs[i].ImageAlt := KeepAttr.ImageAlt;
    FAttrs[i].ImageTitle := KeepAttr.ImageTitle;
    FAttrs[i].LinkTitle := KeepAttr.LinkTitle;
    FAttrs[i].TaskState := KeepAttr.TaskState;
    FAttrs[i].HardBreak := KeepAttr.HardBreak;
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
  i, A, B: integer;
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
  i, A, B: integer;
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
  i, A, B: integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.BackColor);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.BackColor);
  Result := FAttrs[A].BackColor;
  for i := A + 1 to B - 1 do
    if FAttrs[i].BackColor <> Result then Exit(clNone);
end;

function TInkRichEdit.SelSize: integer;
var
  i, A, B: integer;
begin
  if FHasTypingAttr then Exit(FTypingAttr.Size);
  A := GetSelStart;
  B := A + GetSelLength;
  if B = A then Exit(AttrAtCaret.Size);
  Result := FAttrs[A].Size;
  for i := A + 1 to B - 1 do
    if FAttrs[i].Size <> Result then Exit(0);
end;

function TInkRichEdit.SelLink: string;
var
  I, A, B: integer;
begin
  A := GetSelStart;
  B := A + GetSelLength;
  if A >= CharCount then Exit('');
  Result := FAttrs[A].Link;
  for I := A + 1 to B - 1 do
    if FAttrs[I].Link <> Result then Exit('');
end;

function TInkRichEdit.SelFace: string;
var
  i, A, B: integer;
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
  i, A, B: integer;
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

procedure TInkRichEdit.KeyDown(var Key: word; Shift: TShiftState);
var
  Ext: boolean;
  L, Target, i, Best, BestDX, DX: integer;
  P: TPoint;

{ Home/End within the visual line the caret sits on }
  function LineHome(ALine: integer): integer;
  begin
    Result := FLines[ALine].First;
  end;

  function LineEnd(ALine: integer): integer;
  begin
    Result := FLines[ALine].First + FLines[ALine].Count;
    if (FLines[ALine].Count > 0) and (FChars[Result - 1] = #10) then Dec(Result);
  end;

  { Tab in a table: the caret to the start of the next cell, into the next
    row's first cell past the last one, and a new row past the table's end.
    Shift takes it back the same way. }
  procedure TableHop(ABack: boolean);
  var
    RS, RE, C: integer;
  begin
    RS := FCaret;
    while (RS > 0) and (FChars[RS - 1] <> #10) do Dec(RS);
    RE := FCaret;
    while (RE < CharCount) and (FChars[RE] <> #10) do Inc(RE);
    if not ABack then
    begin
      C := FCaret;
      while (C < RE) and (not IsCellBreak(C)) do Inc(C);
      if C < RE then
        MoveCaret(C + 1, False)
      else if (RE + 1 < CharCount) and (FAttrs[RE + 1].Kind in [ipkTableHead, ipkTableRow]) and (FChars[RE] = #10) then
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
      while (C >= RS) and (not IsCellBreak(C)) do Dec(C);
      if C >= RS then
      begin
        { at a cell's own start already?  then the cell before it }
        if C + 1 = FCaret then
        begin
          Dec(C);
          while (C >= RS) and (not IsCellBreak(C)) do Dec(C);
        end;
        if C >= RS then MoveCaret(C + 1, False)
        else
          MoveCaret(RS, False);
      end
      else if FCaret > RS then
        MoveCaret(RS, False)
      else if (RS >= 2) and (FAttrs[RS - 2].Kind in [ipkTableHead, ipkTableRow]) then
      begin
        { the last cell of the row above }
        C := RS - 2;
        while (C >= 0) and (FChars[C] <> #10) and (not IsCellBreak(C)) do Dec(C);
        MoveCaret(C + 1, False);
      end;
    end;
    FGoalX := -1;
  end;

begin
  inherited KeyDown(Key, Shift);
  if Key = 0 then Exit;
  if (Key = VK_F) and (Shift = [ssCtrl]) then
  begin
    ShowFindBar;
    Key := 0;
    Exit;
  end;
  if (Key = VK_F3) and (FFindText <> '') then
  begin
    if ssShift in Shift then Find(FFindText, [ifoBackwards])
    else
      Find(FFindText);
    Key := 0;
    Exit;
  end;
  if (Key = VK_ESCAPE) and FindBarVisible then
  begin
    HideFindBar;
    Key := 0;
    Exit;
  end;
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
        if GetSelLength > 0 then
        begin
          if not EditLocked then
          begin
            PushUndo(True);
            DeleteSelection;
          end;
        end
        else if (FCaret > 0) and not LockedAt(FCaret - 1) then
        begin
          PushUndo(True);
          DoDelete(FCaret - 1, FCaret);
        end;
      FGoalX := -1;
      Key := 0;
    end;
    VK_DELETE:
    begin
      if not FReadOnly then
        if GetSelLength > 0 then
        begin
          if not EditLocked then
          begin
            PushUndo(True);
            DeleteSelection;
          end;
        end
        else if (FCaret < CharCount) and not LockedAt(FCaret) then
        begin
          PushUndo(True);
          DoDelete(FCaret, FCaret + 1);
        end;
      FGoalX := -1;
      Key := 0;
    end;
    VK_A: if ssCtrl in Shift then
      begin
        SelectAll;
        Key := 0;
      end;
    VK_C: if ssCtrl in Shift then
      begin
        CopyToClipboard;
        Key := 0;
      end;
    VK_X: if ssCtrl in Shift then
      begin
        CutToClipboard;
        Key := 0;
      end;
    VK_V: if ssCtrl in Shift then
      begin
        PasteFromClipboard;
        Key := 0;
      end;
    VK_Z: if ssCtrl in Shift then
      begin
        if ssShift in Shift then Redo
        else
          Undo;
        Key := 0;
      end;
    VK_Y: if ssCtrl in Shift then
      begin
        Redo;
        Key := 0;
      end;
    VK_B: if ssCtrl in Shift then
      begin
        ToggleStyle(fsBold);
        Key := 0;
      end;
    VK_I: if ssCtrl in Shift then
      begin
        ToggleStyle(fsItalic);
        Key := 0;
      end;
    VK_U: if ssCtrl in Shift then
      begin
        ToggleStyle(fsUnderline);
        Key := 0;
      end;
  end;
end;

procedure TInkRichEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  A: TInkAttr;
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < #32) then Exit;
  if EditLocked or FReadOnly then Exit;

  A := AttrAtCaret;
  PushUndo(True);
  if GetSelLength > 0 then DeleteSelection;
  DoInsert(UTF8Key, A);
  FGoalX := -1;
  UTF8Key := '';
end;

{ ------------------------------------------------------------------ finding }

{ where AText next starts at or after AFrom - at or before it with
  ifoBackwards - going round the end; -1 when nowhere }
function TInkRichEdit.FindFrom(const AText: string; AOptions: TInkFindOptions; AFrom: integer): integer;
var
  Needle, Hay: array of string;
  P: PChar;
  N, K, I, Step, Tries: integer;

  function Fold(const S: string): string;
  begin
    if ifoMatchCase in AOptions then
      Result := S
    else
      Result := UTF8LowerCase(S);
  end;

  function MatchAt(At: integer): boolean;
  var
    J: integer;
  begin
    Result := At + N <= CharCount;
    for J := 0 to N - 1 do
      if not Result then Exit
      else
        Result := Hay[At + J] = Needle[J];
  end;

begin
  Result := -1;
  N := 0;
  P := PChar(AText);
  while P^ <> #0 do
  begin
    K := UTF8CodepointSize(P);
    SetLength(Needle, N + 1);
    SetString(Needle[N], P, K);
    Needle[N] := Fold(Needle[N]);
    Inc(N);
    Inc(P, K);
  end;
  if (N = 0) or (CharCount = 0) then Exit;
  SetLength(Hay, CharCount);
  for I := 0 to CharCount - 1 do
    Hay[I] := Fold(FChars[I]);
  if ifoBackwards in AOptions then
    Step := -1
  else
    Step := 1;
  I := EnsureRange(AFrom, 0, CharCount - 1);
  for Tries := 1 to CharCount do
  begin
    if MatchAt(I) then Exit(I);
    Inc(I, Step);
    if I >= CharCount then I := 0
    else if I < 0 then I := CharCount - 1;
  end;
end;

function TInkRichEdit.Find(const AText: string; AOptions: TInkFindOptions): boolean;
var
  From, At: integer;
begin
  FFindText := AText;
  { the next one starts past the selection's start, the one before before it }
  From := GetSelStart;
  if ifoBackwards in AOptions then Dec(From)
  else if GetSelLength > 0 then Inc(From);
  if From < 0 then From := CharCount - 1;
  if From >= CharCount then From := 0;
  At := FindFrom(AText, AOptions, From);
  Result := At >= 0;
  if not Result then Exit;
  FAnchor := At;
  FCaret := At + UTF8Length(AText);
  FHasTypingAttr := False;
  ScrollToCaret;
  Invalidate;
  SelectionChanged;
end;

function TInkRichEdit.FindCount(const AText: string; AOptions: TInkFindOptions; out Current: integer): integer;
var
  First, At: integer;
begin
  Result := 0;
  Current := 0;
  First := FindFrom(AText, AOptions - [ifoBackwards], 0);
  if First < 0 then Exit;
  At := First;
  repeat
    Inc(Result);
    if (At = GetSelStart) and (GetSelLength = UTF8Length(AText)) then Current := Result;
    if At + 1 >= CharCount then Break;
    At := FindFrom(AText, AOptions - [ifoBackwards], At + 1);
  until (At <= First);
end;

function TInkRichEdit.GetFindBarVisible: boolean;
begin
  Result := Assigned(FFindEdit) and FFindEdit.Visible;
end;

function TInkRichEdit.FindBarRect: TRect;
var
  W, H, R: integer;
begin
  R := ClientWidth - 6;
  if Assigned(FVScroll) and FVScroll.Visible then Dec(R, FVScroll.Width);
  H := Scale96ToFont(34);
  W := Min(Scale96ToFont(360), R - 2);
  Result := Rect(R - W, 4, R, 4 + H);
end;

{ 0 previous, 1 next, 2 close }
function TInkRichEdit.FindButtonRect(Index: integer): TRect;
var
  Bar: TRect;
  S: integer;
begin
  Bar := FindBarRect;
  S := Bar.Bottom - Bar.Top - 8;
  Result := Rect(Bar.Right - 4 - (3 - Index) * S, Bar.Top + 4, Bar.Right - 4 - (2 - Index) * S, Bar.Bottom - 4);
end;

procedure TInkRichEdit.PlaceFindBar;
var
  Bar: TRect;
begin
  if not Assigned(FFindEdit) then Exit;
  Bar := FindBarRect;
  { the edit, then the count, then the three buttons }
  FFindEdit.SetBounds(Bar.Left + 6, Bar.Top + 5,
    Max(40, FindButtonRect(0).Left - Bar.Left - 6 - Scale96ToFont(64)), Bar.Bottom - Bar.Top - 10);
end;

procedure TInkRichEdit.ShowFindBar;
begin
  if not Assigned(FFindEdit) then
  begin
    FFindEdit := TInkEdit.Create(Self);
    FFindEdit.Parent := Self;
    FFindEdit.OnChange := @FindEditChange;
    FFindEdit.OnKeyDown := @FindEditKey;
  end;
  FFindEdit.Font.Assign(Font);
  FFindEdit.Font.Color := clWindowText;
  PlaceFindBar;
  FFindEdit.Visible := True;
  if FFindEdit.CanFocus then FFindEdit.SetFocus;
  { a selection on one line is what to look for }
  if (GetSelLength > 0) and (Pos(#10, GetSelText) = 0) and (Pos(#13, GetSelText) = 0) and (FFindEdit.Text <> GetSelText) then
    FFindEdit.Text := GetSelText;
  FFindEdit.SelectAll;
  Invalidate;
end;

procedure TInkRichEdit.HideFindBar;
begin
  if not FindBarVisible then Exit;
  FFindEdit.Visible := False;
  if CanFocus then SetFocus;
  Invalidate;
end;

procedure TInkRichEdit.FindEditChange(Sender: TObject);
var
  At: integer;
begin
  FFindText := FFindEdit.Text;
  { as it is typed: from where the match so far begins, so it grows in
    place; nothing found leaves the last match where it was }
  if FFindText <> '' then
  begin
    At := FindFrom(FFindText, [], GetSelStart);
    if At >= 0 then
    begin
      FAnchor := At;
      FCaret := At + UTF8Length(FFindText);
      ScrollToCaret;
      SelectionChanged;
    end;
  end;
  Invalidate;
end;

procedure TInkRichEdit.FindEditKey(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN, VK_F3:
    begin
      if ssShift in Shift then Find(FFindEdit.Text, [ifoBackwards])
      else
        Find(FFindEdit.Text);
      Key := 0;
    end;
    VK_ESCAPE:
    begin
      HideFindBar;
      Key := 0;
    end;
  end;
end;

procedure TInkRichEdit.PaintFindBar;
const
  Glyphs: array[0..2] of string = ('▲', '▼', '✕');
var
  Bar, R: TRect;
  Back, Fore: TColor;
  Total, Current, K: integer;
  Count: string;
begin
  Bar := FindBarRect;
  Back := ColorToRGB(Color);
  Fore := ColorToRGB(Font.Color);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := HTMLShadeColor(Back, 10);
  Canvas.Pen.Color := MixColor(Back, Fore, 0.4);
  Canvas.RoundRect(Bar, 8, 8);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := MixColor(Back, Fore, 0.8);
  Canvas.Brush.Style := bsClear;
  Total := FindCount(FFindEdit.Text, [], Current);
  if FFindEdit.Text = '' then Count := ''
  else if Total = 0 then Count := '0/0'
  else
    Count := IntToStr(Current) + '/' + IntToStr(Total);
  R := Rect(FFindEdit.Left + FFindEdit.Width + 4, Bar.Top, FindButtonRect(0).Left - 2, Bar.Bottom);
  Canvas.TextOut(R.Right - Canvas.TextWidth(Count), (Bar.Top + Bar.Bottom - Canvas.TextHeight(Count)) div 2, Count);
  for K := 0 to 2 do
  begin
    R := FindButtonRect(K);
    Canvas.TextOut((R.Left + R.Right - Canvas.TextWidth(Glyphs[K])) div 2, (R.Top + R.Bottom - Canvas.TextHeight(Glyphs[K])) div 2, Glyphs[K]);
  end;
end;

{ -------------------------------------------------------------------- mouse }

procedure TInkRichEdit.ToggleTask;
var
  I: integer;
begin
  if FReadOnly or EditLocked then Exit;
  I := GetSelStart;
  while (I > 0) and (FChars[I - 1] <> #10) do Dec(I);
  if (I >= CharCount) or (FAttrs[I].TaskState < 0) then Exit;
  PushUndo(False);
  FAttrs[I].TaskState := 1 - FAttrs[I].TaskState;
  if FAttrs[I].TaskState = 1 then FChars[I] := #$E2#$98#$91
  else
    FChars[I] := #$E2#$98#$90;
  Changed;
end;

function TInkRichEdit.SelectImageAt(X, Y: integer): boolean;
var
  I, J, L, ImageLeft, ImageBottom: integer;
begin
  Result := False;
  I := PointToCaret(X, Y);
  for J := Max(0, I - 1) to Min(CharCount - 1, I) do
    if FAttrs[J].ImageSource <> '' then
    begin
      L := LineOfChar(J);
      ImageLeft := FLines[L].Left + FCharX[J];
      ImageBottom := FLines[L].Top + FLines[L].Ascent - FScrollY;
      if (X >= ImageLeft) and (X < ImageLeft + FCharW[J]) and (Y >= ImageBottom - ImageHeight(J)) and (Y < ImageBottom) then
      begin
        FAnchor := J;
        FCaret := J + 1;
        FHasTypingAttr := False;
        Invalidate;
        SelectionChanged;
        Exit(True);
      end;
    end;
end;

procedure TInkRichEdit.ContextAt(X, Y: integer);
var
  I: integer;
begin
  if SelectImageAt(X, Y) then Exit;
  I := PointToCaret(X, Y);
  if (GetSelLength = 0) or (I < GetSelStart) or (I > GetSelStart + GetSelLength) then
    MoveCaret(I, False);
end;

procedure TInkRichEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  I: integer;
  P: TPoint;
  Now_: QWord;
  Near: boolean;
begin
  if FindBarVisible and (Button = mbLeft) and PtInRect(FindBarRect, Point(X, Y)) then
  begin
    if PtInRect(FindButtonRect(0), Point(X, Y)) then Find(FFindEdit.Text, [ifoBackwards])
    else if PtInRect(FindButtonRect(1), Point(X, Y)) then Find(FFindEdit.Text)
    else if PtInRect(FindButtonRect(2), Point(X, Y)) then HideFindBar;
    Exit;
  end;
  if Button = mbRight then ContextAt(X, Y);
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if CanSetFocus then SetFocus;
    FSelectUnit := 0;
    FCaret := PointToCaret(X, Y);
    I := FCaret;
    if (I = CharCount) or ((I < CharCount) and (FAttrs[I].TaskState < 0)) then Dec(I);
    if (I >= 0) and (FAttrs[I].TaskState >= 0) and (Shift = []) then
    begin
      P := CaretPoint(I);
      if (X >= P.X) and (X < P.X + FCharW[I]) then
      begin
        FCaret := I;
        FAnchor := I;
        ToggleTask;
        Exit;
      end;
    end;
    { counted as TInkCustomPage does: GTK sends a double click as a press and
      the same press again, marked double, at the same moment }
    Now_ := GetTickCount64;
    Near := (Abs(X - FLastClickX) <= 4) and (Abs(Y - FLastClickY) <= 4);
    if not (Near and (Now_ - FLastClickTime < 25)) then
    begin
      if Near and (Now_ - FLastClickTime <= GetDoubleClickTime) and (FClicks < 3) then
        Inc(FClicks)
      else
        FClicks := 1;
    end;
    FLastClickTime := Now_;
    FLastClickX := X;
    FLastClickY := Y;
    if ssTriple in Shift then FClicks := 3
    else if (ssDouble in Shift) and (FClicks < 2) then FClicks := 2;
    { a double click takes the word, a triple click the paragraph }
    FSelectUnit := FClicks - 1;
    if FSelectUnit > 0 then
    begin
      UnitAt(FCaret, FUnitFrom, FUnitTo);
      FAnchor := FUnitFrom;
      FCaret := FUnitTo;
    end
    else if not (ssShift in Shift) then
      FAnchor := FCaret;
    FGoalX := -1;
    FHasTypingAttr := False;
    RestartCaretBlink;
    Invalidate;
    SelectionChanged;
  end;
end;

procedure TInkRichEdit.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Idx, A, B: integer;
begin
  inherited MouseMove(Shift, X, Y);
  if ssLeft in Shift then
  begin
    FCaret := PointToCaret(X, Y);
    if FSelectUnit > 0 then
    begin
      { after a double or triple click a drag goes by words or paragraphs }
      UnitAt(FCaret, A, B);
      if A < FUnitFrom then
      begin
        FAnchor := FUnitTo;
        FCaret := A;
      end
      else
      begin
        FAnchor := FUnitFrom;
        FCaret := Max(B, FUnitTo);
      end;
    end;
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
  if FMouseOnLink and (FHoverLink <> '') and Assigned(FOnLinkClick) and (GetKeyState(VK_CONTROL) < 0) then
    FOnLinkClick(Self, FHoverLink);
end;

procedure TInkRichEdit.UnitAt(AIndex: integer; out AFrom, ATo: integer);
begin
  if FSelectUnit = 1 then
  begin
    InkWordAt(FChars, CharCount, AIndex, AFrom, ATo);
    Exit;
  end;
  { the paragraph, without the line break that ends it }
  AFrom := AIndex;
  while (AFrom > 0) and (FChars[AFrom - 1] <> #10) do Dec(AFrom);
  ATo := AIndex;
  while (ATo < CharCount) and (FChars[ATo] <> #10) do Inc(ATo);
end;

{ ---------------------------------------------------------------- clipboard */ }

procedure TInkRichEdit.CopyToClipboard;
var
  i, A, N: integer;
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
  if EditLocked or FReadOnly or (GetSelLength = 0) then Exit;
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
    6: if (not FReadOnly) and (GetSelLength > 0) and not EditLocked then
      begin
        PushUndo(False);
        DeleteSelection;
        FMarkupDirty := True;
        InvalidateLayout;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
    7: SelectAll;
    8: GoToSource;
  end;
end;

procedure TInkRichEdit.DoContextPopup(MousePos: TPoint; var Handled: boolean);
var
  P: TPoint;

  procedure AddItem(const ACaption: string; ATag: integer; AEnabled: boolean);
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
  if (MousePos.X >= 0) and (MousePos.Y >= 0) then ContextAt(MousePos.X, MousePos.Y);
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
  if Assigned(FOnGoToSource) then
  begin
    AddItem('-', 0, True);
    AddItem(SInkRichGoToSource, 8, True);
  end;
  P := MousePos;
  if (P.X < 0) or (P.Y < 0) then
  begin
    P := CaretPoint(FCaret);
    Dec(P.Y, FScrollY);
  end;
  P := ClientToScreen(P);
  FMenu.PopUp(P.X, P.Y);
end;

procedure TInkRichEdit.PasteFromClipboard;
var
  S: string;
  i, At: integer;
  A: TInkAttr;
begin
  if FReadOnly or EditLocked then Exit;
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
  if (gClipText <> '') and (Length(gClipAttrs) > 0) and (StringReplace(gClipText, LineEnding, #10, [rfReplaceAll]) = S) then
    for i := 0 to Length(gClipAttrs) - 1 do
      if At + i < CharCount then
      begin
        A := gClipAttrs[i];
        A.MarkdownBlock := FAttrs[At + i].MarkdownBlock;
        FAttrs[At + i] := A;
      end;
  InvalidateLayout;
end;

{ --------------------------------------------------------------------- undo */ }

function TInkRichEdit.TakeSnapshot: TObject;
var
  S: TInkSnapshot;
  i: integer;
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
  S.Originals := Copy(FMarkdownOriginals);
  S.OpenBlock := FOpenBlock;
  Result := S;
end;

procedure TInkRichEdit.RestoreSnapshot(ASnap: TObject);
var
  S: TInkSnapshot;
  i: integer;
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
  FMarkdownOriginals := Copy(S.Originals);
  FOpenBlock := S.OpenBlock;
  Changed;
end;

procedure TInkRichEdit.ClearUndoList(AList: TFPList);
var
  i: integer;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    TObject(AList[i]).Free;
  AList.Clear;
end;

{ ACoalesce folds a run of keystrokes into one undo step, so ctrl+Z takes back
  a word rather than a letter. }
procedure TInkRichEdit.PushUndo(ACoalesce: boolean);
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

function TInkRichEdit.CanUndo: boolean;
begin
  Result := FUndo.Count > 0;
end;

function TInkRichEdit.CanRedo: boolean;
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
  { the snapshot already says which block is open; nothing opens or
    closes while it is put back }
  FSyncing := True;
  try
    RestoreSnapshot(Snap);
  finally
    FSyncing := False;
  end;
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
  { the snapshot already says which block is open; nothing opens or
    closes while it is put back }
  FSyncing := True;
  try
    RestoreSnapshot(Snap);
  finally
    FSyncing := False;
  end;
  Snap.Free;
  FLastUndoTick := 0;
end;

{ ------------------------------------------------------------------- markup */ }

procedure TInkRichEdit.SetReadOnly(AValue: boolean);
begin
  FReadOnly := AValue;
end;

procedure TInkRichEdit.SetWordWrap(AValue: boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  InvalidateLayout;
end;

procedure TInkRichEdit.SetParagraphSpacing(AValue: boolean);
begin
  if FParagraphSpacing = AValue then Exit;
  FParagraphSpacing := AValue;
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
  i, B: integer;
  Paras: array of TInkAttr;
  Breaks: array of integer;
begin
  FSettingMarkup := True;
  try
    FMarkdownSource := '';
    SetLength(FMarkdownOriginals, 0);
    SetLength(FChars, 0);
    SetLength(FAttrs, 0);
    SetLength(Paras, FMarkup.Count);
    SetLength(Breaks, FMarkup.Count);
    for i := 0 to FMarkup.Count - 1 do
    begin
      Breaks[i] := CharCount;
      Paras[i] := ParseInto(FMarkup[i], i > 0);
    end;
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
    { an empty paragraph has no character to take them from: its wrapper says }
    for i := 1 to FMarkup.Count - 1 do
    begin
      B := Breaks[i];
      if (B < CharCount) and (FChars[B] = #10) and ((B = 0) or (FChars[B - 1] = #10)) then
      begin
        FAttrs[B].Kind := Paras[i - 1].Kind;
        FAttrs[B].Level := Paras[i - 1].Level;
        FAttrs[B].Lang := Paras[i - 1].Lang;
        FAttrs[B].TableAlign := Paras[i - 1].TableAlign;
      end;
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
function TInkRichEdit.ParseInto(const AMarkup: string; AParaBreakFirst: boolean): TInkAttr;
var
  Stack: array of TInkAttr;
  Cur: TInkAttr;
  P, Len, Start, N: integer;
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

  procedure Emit(const S: string; Dividers: boolean = True);
  var
    Q: PChar;
    CharLen, Old, k: integer;
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
      FAttrs[k].CellBreak := Dividers and (Cur.Kind in [ipkTableHead, ipkTableRow]) and (FChars[k] = '|');
      Inc(k);
      Inc(Q, CharLen);
    end;
  end;

  procedure EmitBreak(AHard: boolean = False);
  begin
    SetLength(FChars, CharCount + 1);
    SetLength(FAttrs, Length(FChars));
    FChars[High(FChars)] := #10;
    FAttrs[High(FAttrs)] := Cur;
    FAttrs[High(FAttrs)].HardBreak := AHard;
  end;

  { The value of APropName inside ATag, in the case it was written in - a font
    family name is not case insensitive to the font matcher. }
  function PropOf(const ATag, APropName: string): string;
  var
    ip, j: integer;
    R: string;
    Q: char;
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
      while (j <= Length(R)) and (R[j] <> ' ') and (R[j] <> '>') and (R[j] <> #9) and (R[j] <> '/') do
        Inc(j);
      Result := Copy(R, 1, j - 1);
    end;
  end;

begin
  Cur := DefaultInkAttr;
  Result := DefaultInkAttr;
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

      if Nm = 'BR' then EmitBreak(True)
      else if (Nm = 'P') or (Nm = '/P') then
        EmitBreak
      else if Nm = 'B' then
      begin
        Push;
        Cur.Style := Cur.Style + [fsBold];
      end
      else if Nm = 'I' then
      begin
        Push;
        Cur.Style := Cur.Style + [fsItalic];
      end
      else if Nm = 'U' then
      begin
        Push;
        Cur.Style := Cur.Style + [fsUnderline];
      end
      else if (Nm = 'S') or (Nm = 'STRIKE') then
      begin
        Push;
        Cur.Style := Cur.Style + [fsStrikeOut];
      end
      else if Nm = 'SUP' then
      begin
        Push;
        Cur.Script := isSuperscript;
      end
      else if Nm = 'SUB' then
      begin
        Push;
        Cur.Script := isSubscript;
      end
      else if Nm = 'CENTER' then
      begin
        Push;
        Cur.Align := taCenter;
      end
      else if Nm = 'RIGHT' then
      begin
        Push;
        Cur.Align := taRightJustify;
      end
      else if (Length(Nm) = 2) and (Nm[1] = 'H') and (Nm[2] in ['1'..'6']) then
      begin
        Push;
        Cur.Kind := TInkParaKind(Ord(ipkH1) + Ord(Nm[2]) - Ord('1'));
      end
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
      else if Nm = 'BLOCKQUOTE' then
      begin
        Push;
        Cur.Kind := ipkQuote;
      end
      else if Nm = 'PRE' then
      begin
        Push;
        Cur.Kind := ipkCode;
        Cur.Lang := PropOf(TagStr, 'LANG');
      end
      else if Nm = 'MDSOURCE' then
      begin
        Push;
        Cur.Kind := ipkSource;
      end
      else if Nm = 'TH' then
      begin
        Push;
        Cur.Kind := ipkTableHead;
        Cur.TableAlign := PropOf(TagStr, 'COLUMNS');
      end
      else if Nm = 'TR' then
      begin
        Push;
        Cur.Kind := ipkTableRow;
        Cur.TableAlign := PropOf(TagStr, 'COLUMNS');
      end
      else if Nm = 'CHECKBOX' then
      begin
        Push;
        Cur.TaskState := 0;
        if PropOf(TagStr, 'CHECKED') = '1' then Cur.TaskState := 1;
        if Cur.TaskState = 1 then Emit(#$E2#$98#$91)
        else
          Emit(#$E2#$98#$90);
        Pop;
      end
      else if Nm = 'IMG' then
      begin
        Push;
        Cur.ImageSource := HTMLUnescape(PropOf(TagStr, 'SRC'));
        Cur.ImageAlt := HTMLUnescape(PropOf(TagStr, 'ALT'));
        Cur.ImageTitle := HTMLUnescape(PropOf(TagStr, 'TITLE'));
        Cur.ImageWidth := Max(0, StrToIntDef(PropOf(TagStr, 'WIDTH'), 0));
        Cur.ImageHeight := Max(0, StrToIntDef(PropOf(TagStr, 'HEIGHT'), 0));
        if Cur.ImageSource <> '' then Emit(#$EF#$BF#$BC);
        Pop;
      end
      else if Nm = 'A' then
      begin
        Push;
        Val := PropOf(TagStr, 'HREF');
        if Val <> '' then Cur.Link := HTMLUnescape(Val);
        Cur.LinkTitle := HTMLUnescape(PropOf(TagStr, 'TITLE'));
      end
      else if Nm = 'FONT' then
      begin
        Push;
        Val := PropOf(TagStr, 'BGCOLOR');
        if Val <> '' then Cur.BackColor := HTMLStringToColor(Val, clNone);
        // "BGCOLOR" ends in "COLOR", so looking for the shorter name in the
        // raw tag finds the longer one and paints the text in its own
        // background. Mask it out first.
        Val := PropOf(StringReplace(TagStr, 'bgcolor', '#######', [rfReplaceAll, rfIgnoreCase]), 'COLOR');
        if Val <> '' then Cur.Color := HTMLStringToColor(Val, clDefault);
        Val := PropOf(TagStr, 'SIZE');
        if Val <> '' then Cur.Size := StrToIntDef(Val, 0);
        Val := PropOf(TagStr, 'FACE');
        if Val <> '' then Cur.Face := Val;
      end
      else if (Length(Nm) > 1) and (Nm[1] = '/') then
        Pop;
      if (Result.Kind = ipkText) and (Cur.Kind <> ipkText) then Result := Cur;
      Continue;
    end;

    Start := P;
    if Body[P] = '&' then
    begin
      while (P <= Len) and not (Body[P] in [';', '<', ' ', #10]) do Inc(P);
      if (P <= Len) and (Body[P] = ';') then Inc(P);
      Emit(HTMLUnescape(Copy(Body, Start, P - Start)), False);
    end
    else
    begin
      while (P <= Len) and not (Body[P] in ['<', '&']) do Inc(P);
      Emit(Copy(Body, Start, P - Start));
    end;
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
  i, RunEnd, k, NOpen, NWant: integer;
  OpenName, OpenTag: array[0..cMaxTags - 1] of string;
  WantName, WantTag: array[0..cMaxTags - 1] of string;
  ParaAlign: TAlignment;
  ParaKind: TInkParaKind;
  ParaLevel: integer;
  ParaLang, ParaColumns: string;

  procedure CloseDownTo(ALevel: integer);
  var
    j: integer;
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
    begin
      F := '<a href="' + HTMLEscape(A.Link) + '"';
      if A.LinkTitle <> '' then F := F + ' title="' + HTMLEscape(A.LinkTitle) + '"';
      AddWant('a', F + '>');
    end;
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
    j, m, Cnt, Found: integer;
    Used: array[0..cMaxTags - 1] of boolean;
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
      ('', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'oli', 'blockquote', 'pre', 'th', 'tr', 'mdsource');
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
      if (ParaKind in [ipkTableHead, ipkTableRow]) and (ParaColumns <> '') then
        Body := Body + ' columns="' + ParaColumns + '"';
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
    if CharCount > 0 then ParaAlign := FAttrs[0].Align
    else
      ParaAlign := taLeftJustify;
    if CharCount > 0 then ParaKind := FAttrs[0].Kind
    else
      ParaKind := ipkText;
    if CharCount > 0 then ParaLevel := FAttrs[0].Level
    else
      ParaLevel := 0;
    if CharCount > 0 then ParaLang := FAttrs[0].Lang
    else
      ParaLang := '';

    ParaColumns := '';
    if CharCount > 0 then ParaColumns := FAttrs[0].TableAlign;
    i := 0;
    while i <= CharCount do
    begin
      if (i < CharCount) and (FChars[i] = #10) and FAttrs[i].HardBreak then
      begin
        CloseDownTo(0);
        Line := Line + '<br>';
        Inc(i);
        Continue;
      end;
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
          ParaColumns := FAttrs[i].TableAlign;
        end
        else
        begin
          ParaAlign := taLeftJustify;
          ParaKind := ipkText;
          ParaLevel := 0;
          ParaLang := '';
          ParaColumns := '';
        end;
        Continue;
      end;

      RunEnd := i;
      while (RunEnd + 1 < CharCount) and (FChars[RunEnd + 1] <> #10) and SameInkAttr(FAttrs[RunEnd + 1], FAttrs[i]) do
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
        if FAttrs[k].TaskState >= 0 then Body := Body + InkCheckboxMarkup(FAttrs[k].TaskState = 1)
        else if FAttrs[k].ImageSource <> '' then
        begin
          Body := Body + '<img src="' + HTMLEscape(FAttrs[k].ImageSource) + '" alt="' + HTMLEscape(FAttrs[k].ImageAlt) + '"';
          if FAttrs[k].ImageWidth > 0 then Body := Body + ' width="' + IntToStr(FAttrs[k].ImageWidth) + '"';
          if FAttrs[k].ImageHeight > 0 then Body := Body + ' height="' + IntToStr(FAttrs[k].ImageHeight) + '"';
          if FAttrs[k].ImageTitle <> '' then Body := Body + ' title="' + HTMLEscape(FAttrs[k].ImageTitle) + '"';
          Body := Body + '>';
        end
        else if (FChars[k] = '|') and (FAttrs[k].Kind in [ipkTableHead, ipkTableRow]) and not IsCellBreak(k) then
          Body := Body + '&#124;'
        else
          Body := Body + HTMLEscape(FChars[k]);
      Line := Line + Body;
      i := RunEnd + 1;
    end;
    FMarkupDirty := False;
  finally
    FSettingMarkup := False;
  end;
end;

function TInkRichEdit.AsHTML(const ASep: string): string;
var
  i: integer;
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

{ Project HTML blocks into the editor's paragraphs while retaining list
  levels, table structure, images and inline character formatting. }
procedure MarkdownHTMLToParagraphs(const H: string; AOut: TStrings; AListLevel: integer = 0);
var
  P, Q, Depth: integer;
  Raw, Name, Inner, Wrap: string;
  Closing: boolean;
  InOrdered: boolean;

  function ReadTagIn(const Src: string; var AP: integer; out AName: string; out AClosing: boolean): string;
  var
    E, K: integer;
  begin
    Result := '';
    AName := '';
    AClosing := False;
    if (AP > Length(Src)) or (Src[AP] <> '<') then Exit;
    E := AP + 1;
    while (E <= Length(Src)) and (Src[E] <> '>') do Inc(E);
    if E > Length(Src) then
    begin
      AP := E;
      Exit;
    end;
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

  function ReadTag(var AP: integer; out AName: string; out AClosing: boolean): string;
  begin
    Result := ReadTagIn(H, AP, AName, AClosing);
  end;

  { everything up to the close of AName, nesting counted, cursor left after }
  function InnerOf(const AName: string): string;
  var
    S0, D, TP: integer;
    N: string;
    C: boolean;
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
    SP: integer;
  begin
    Ink := Trim(HTMLToInk(AInner, True));
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
    K: integer;
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
    TP, CE: integer;
    N, Row, Cell, Tag, Alignments, Columns: string;
    C, IsHead: boolean;
    Cells: TStringList;

    procedure FlushRow;
    var
      K: integer;
    begin
      if Cells.Count = 0 then Exit;
      Row := '';
      for K := 0 to Cells.Count - 1 do
      begin
        if K > 0 then Row := Row + '|';
        Row := Row + StringReplace(Trim(HTMLToInk(Cells[K], True)), '|', '&#124;', [rfReplaceAll]);
      end;
      Columns := '';
      if StringReplace(Alignments, '-', '', [rfReplaceAll]) <> '' then
        Columns := ' columns="' + Alignments + '"';
      if IsHead then
        AOut.Add('<th' + Columns + '>' + Row + '</th>')
      else
        AOut.Add('<tr' + Columns + '>' + Row + '</tr>');
      Cells.Clear;
      IsHead := False;
      Alignments := '';
    end;

  begin
    TP := 1;
    Alignments := '';
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
        Tag := ReadTagIn(AInner, TP, N, C);
        if (N = 'tr') and C then
          FlushRow
        else if ((N = 'td') or (N = 'th')) and not C then
        begin
          if N = 'th' then IsHead := True;
          if Pos('align="left"', Tag) > 0 then Alignments := Alignments + 'l'
          else if Pos('align="right"', Tag) > 0 then Alignments := Alignments + 'r'
          else if Pos('align="center"', Tag) > 0 then Alignments := Alignments + 'c'
          else
            Alignments := Alignments + '-';
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
    else if (Name = 'p') or (Name = 'div') then
    begin
      { align="center" is how a GitHub README centers a picture }
      Wrap := '';
      if Pos('align="center"', LowerCase(Raw)) > 0 then Wrap := 'center'
      else if Pos('align="right"', LowerCase(Raw)) > 0 then Wrap := 'right';
      Inner := InnerOf(Name);
      if (Name = 'div') and (Pos('<p', LowerCase(Inner)) > 0) then
        MarkdownHTMLToParagraphs(Inner, AOut, AListLevel)
      else
        AddWrapped(Wrap, Inner);
    end
    else if Name = 'center' then
      AddWrapped('center', InnerOf(Name))
    else if Name = 'img' then
      AddWrapped('', Raw)
    else if Name = 'a' then
      AddWrapped('', Raw + InnerOf(Name) + '</a>')
    else if Name = 'details' then
      MarkdownHTMLToParagraphs(InnerOf(Name), AOut, AListLevel)
    else if Name = 'summary' then
      AddWrapped('', '<b>' + InnerOf(Name) + '</b>')
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

{ Keep the writer's spelling of markup when a local text edit has an
  unambiguous source match and produces the same parsed result. }
function PreserveMarkdownText(const Source, Before, After: string): string;
var
  P, OldEnd, NewEnd, K, L, Context, Side, Tries: integer;
  Needle, Replacement, Candidate, Wanted: string;
begin
  Result := '';
  Wanted := MarkdownToHTML(After, [imoInlineHTML]);
  P := 1;
  while (P <= Length(Before)) and (P <= Length(After)) and (Before[P] = After[P]) do Inc(P);
  OldEnd := Length(Before);
  NewEnd := Length(After);
  while (OldEnd >= P) and (NewEnd >= P) and (Before[OldEnd] = After[NewEnd]) do
  begin
    Dec(OldEnd);
    Dec(NewEnd);
  end;
  { context on both sides of the change first, then on one side alone: the
    other side may be spelled differently in the source, as the indent of
    an indented code line or a tab }
  for Context := 8 downto 0 do
    for Side := 0 to 2 do
    begin
      K := Min(Context, P - 1);
      L := Min(Context, Length(Before) - OldEnd);
      if Side = 1 then L := 0
      else if Side = 2 then K := 0;
      Needle := Copy(Before, P - K, OldEnd - P + 1 + K + L);
      Replacement := Copy(After, P - K, NewEnd - P + 1 + K + L);
      if Needle = '' then Continue;
      { every place the context appears, the same line repeated in a code
        block say; the parse decides which one the edit was }
      K := Pos(Needle, Source);
      Tries := 0;
      while (K > 0) and (Tries < 16) do
      begin
        Candidate := Copy(Source, 1, K - 1) + Replacement + Copy(Source, K + Length(Needle), MaxInt);
        if MarkdownToHTML(Candidate, [imoInlineHTML]) = Wanted then Exit(Candidate);
        K := PosEx(Needle, Source, K + 1);
        Inc(Tries);
      end;
    end;
end;

{ Source blocks the editor cannot represent stay visible as literal Markdown.
  They can still be edited without discarding images, tasks or table alignment. }
procedure TInkRichEdit.LoadMarkdown(const S: string; const ABaseURI: string);
var
  Blocks: TInkMarkdownBlocks;
  Lines, SourceLines: TStringList;
  IDs: array of integer;
  First, Last: array of integer;
  B, I, J, P, LineNo, Pass: integer;
  Raw, Locked: array of boolean;
  Body, Canonical: string;

  { <strong><a>text</a></strong> and <a><strong>text</strong></a> are the
    same text, as are <i> and <em>: an author writes **[link](url)** and
    the editor writes [**link**](url) back.  Adjacent inline tags are put in
    one order, and the old names mapped, before two renderings are compared. }
  function SameNesting(const H: string): string;
  const
    Names = ',a,abbr,b,code,del,em,i,ins,kbd,mark,s,small,span,strong,sub,sup,u,';
  var
    P, E, K: integer;
    Closing, Run: boolean;
    Tag, Name: string;
    RunNames, RunTags: array of string;

    function InlineTag(AP: integer; out AEnd: integer; out AName: string; out AClosing: boolean): boolean;
    var
      Q: integer;
    begin
      Result := False;
      if (AP > Length(H)) or (H[AP] <> '<') then Exit;
      AEnd := AP + 1;
      while (AEnd <= Length(H)) and (H[AEnd] <> '>') do Inc(AEnd);
      if AEnd > Length(H) then Exit;
      Q := AP + 1;
      AClosing := (Q <= Length(H)) and (H[Q] = '/');
      if AClosing then Inc(Q);
      AName := '';
      while (Q <= Length(H)) and (H[Q] in ['a'..'z']) do
      begin
        AName := AName + H[Q];
        Inc(Q);
      end;
      Result := (AName <> '') and (Pos(',' + AName + ',', Names) > 0);
    end;

    procedure Flush;
    var
      A, B: integer;
      T: string;
    begin
      { opening tags by name, closing tags the other way, so pairs still nest }
      for A := 1 to High(RunNames) do
        for B := A downto 1 do
          if (RunNames[B] < RunNames[B - 1]) xor Run then
          begin
            T := RunNames[B]; RunNames[B] := RunNames[B - 1]; RunNames[B - 1] := T;
            T := RunTags[B]; RunTags[B] := RunTags[B - 1]; RunTags[B - 1] := T;
          end
          else
            Break;
      for A := 0 to High(RunTags) do Result := Result + RunTags[A];
      RunNames := nil;
      RunTags := nil;
    end;

  begin
    Result := '';
    P := 1;
    Run := False;
    while P <= Length(H) do
    begin
      if InlineTag(P, E, Name, Closing) then
      begin
        if (Length(RunTags) > 0) and (Closing <> Run) then Flush;
        Run := Closing;
        Tag := Copy(H, P, E - P + 1);
        if Name = 'i' then Name := 'em'
        else if Name = 'b' then Name := 'strong';
        if (Tag = '<i>') or (Tag = '<b>') then Tag := '<' + Name + '>'
        else if (Tag = '</i>') or (Tag = '</b>') then Tag := '</' + Name + '>';
        K := Length(RunTags);
        SetLength(RunNames, K + 1);
        SetLength(RunTags, K + 1);
        RunNames[K] := Name;
        RunTags[K] := Tag;
        P := E + 1;
        Continue;
      end;
      if Length(RunTags) > 0 then Flush;
      Result := Result + H[P];
      Inc(P);
    end;
    if Length(RunTags) > 0 then Flush;
  end;

  function Comparable(H: string): string;
  var
    K, E, P: integer;
    InPre, Space: boolean;
  begin
    H := SameNesting(H);
    { Heading IDs depend on earlier headings, not on their editable text. }
    K := Pos(' id="', H);
    while K > 0 do
    begin
      E := K + 5;
      while (E <= Length(H)) and (H[E] <> '"') do Inc(E);
      Delete(H, K, E - K + 1);
      K := Pos(' id="', H);
    end;
    Result := '';
    P := 1;
    InPre := False;
    Space := False;
    while P <= Length(H) do
    begin
      if H[P] = '&' then
      begin
        E := P + 1;
        while (E <= Length(H)) and (E - P < 34) and not (H[E] in [';', '<', ' ', #10, #13]) do Inc(E);
        if (E <= Length(H)) and (H[E] = ';') then
        begin
          Result := Result + HTMLEscape(HTMLUnescape(Copy(H, P, E - P + 1)));
          Space := False;
          P := E + 1;
          Continue;
        end;
      end;
      if Copy(H, P, 4) = '<pre' then InPre := True;
      if Copy(H, P, 6) = '</pre>' then InPre := False;
      if not InPre and (H[P] in [#9, #10, #13, ' ']) then
      begin
        if not Space then Result := Result + ' ';
        Space := True;
      end
      else
      begin
        Result := Result + H[P];
        Space := False;
      end;
      Inc(P);
    end;
  end;

begin
  FImageBase := ABaseURI;
  FOpenBlock := 0;
  ClearImages;
  Blocks := MarkdownBlocks(S, [imoInlineHTML]);
  SetLength(Raw, Length(Blocks));
  SetLength(Locked, Length(Blocks));
  { an HTML block - a <p align="center"> of pictures, a <details>, an
    <img> on a line of its own - is shown as the page shows it, from its
    own HTML, and kept as written; a comment stays visible source }
  for B := 0 to High(Blocks) do
  begin
    Body := Copy(S, Blocks[B].First, Blocks[B].Count);
    Locked[B] := IsHTMLStart(Body) and (Pos('<!', TrimLeft(Body)) <> 1);
  end;
  SetLength(First, Length(Blocks));
  SetLength(Last, Length(Blocks));
  Lines := TStringList.Create;
  SourceLines := TStringList.Create;
  try
    for Pass := 0 to 1 do
    begin
      Lines.Clear;
      SetLength(IDs, 0);
      for B := 0 to High(Blocks) do
      begin
        I := Lines.Count;
        if Locked[B] then
          MarkdownHTMLToParagraphs(MarkdownToHTML(Copy(S, Blocks[B].First, Blocks[B].Count), [imoRawHTML]), Lines);
        if Lines.Count = I then Locked[B] := False;  { nothing drawable in it: its source, then }
        if not Locked[B] then
          if Raw[B] then
          begin
            Body := Copy(S, Blocks[B].First, Blocks[B].Count);
            while (Body <> '') and (Body[Length(Body)] in [#10, #13]) do
              Delete(Body, Length(Body), 1);
            SourceLines.Text := Body;
            if SourceLines.Count = 0 then SourceLines.Add('');
            for J := 0 to SourceLines.Count - 1 do
              Lines.Add('<mdsource>' + HTMLEscape(SourceLines[J]) + '</mdsource>');
          end
          else
            MarkdownHTMLToParagraphs(Blocks[B].HTML, Lines);
        SetLength(IDs, Lines.Count);
        for J := I to Lines.Count - 1 do IDs[J] := B + 1;
      end;
      if Lines.Count = 0 then Lines.Add('');
      Markup := Lines;
      for B := 0 to High(Blocks) do
      begin
        First[B] := -1;
        Last[B] := -1;
      end;
      LineNo := 0;
      for P := 0 to CharCount - 1 do
      begin
        if LineNo < Length(IDs) then
        begin
          B := IDs[LineNo] - 1;
          FAttrs[P].MarkdownBlock := B + 1;
          if First[B] < 0 then First[B] := P;
          Last[B] := P + 1;
        end;
        if (FChars[P] = #10) and not FAttrs[P].HardBreak then Inc(LineNo);
      end;
      if Pass = 0 then
        for B := 0 to High(Blocks) do
        begin
          I := Last[B];
          if (I > First[B]) and (I < CharCount) and (FChars[I - 1] = #10) then Dec(I);
          Canonical := MarkdownRange(Max(0, First[B]), Max(0, I));
          Raw[B] := not Locked[B] and ((Comparable(MarkdownToHTML(Canonical, [imoInlineHTML])) <> Comparable(Blocks[B].HTML)) or
            (Pos('<!--', Copy(S, Blocks[B].First, Blocks[B].Count)) > 0));
        end;
    end;
    FMarkdownSource := S;
    SetLength(FMarkdownOriginals, Length(Blocks));
    for B := 0 to High(Blocks) do
    begin
      FMarkdownOriginals[B].First := Blocks[B].First;
      FMarkdownOriginals[B].Count := Blocks[B].Count;
      I := Last[B];
      if (I > First[B]) and (I < CharCount) and (FChars[I - 1] = #10) then Dec(I);
      FMarkdownOriginals[B].Canonical := MarkdownRange(Max(0, First[B]), Max(0, I));
      FMarkdownOriginals[B].Locked := Locked[B];
    end;
  finally
    SourceLines.Free;
    Lines.Free;
  end;
end;

function TInkRichEdit.AsMarkdown: string;
var
  B, I, J, P, First, Last: integer;
  Current, Original, Ending, EOL, Preserved: string;
begin
  if Length(FMarkdownOriginals) = 0 then
  begin
    if CharCount = 0 then Exit(FMarkdownSource);
    Exit(MarkdownRange(0, CharCount));
  end;
  { Each source block owns its characters, including inserted text and undo
    snapshots. Only a changed block is serialized; gaps stay byte for byte. }
  Result := '';
  P := 1;
  I := 0;
  EOL := #10;
  J := Pos(#13, FMarkdownSource);
  if J > 0 then
  begin
    EOL := #13;
    if Copy(FMarkdownSource, J, 2) = #13#10 then EOL := #13#10;
  end;
  for B := 0 to High(FMarkdownOriginals) do
  begin
    Result := Result + Copy(FMarkdownSource, P, FMarkdownOriginals[B].First - P);
    First := I;
    while (I < CharCount) and (FAttrs[I].MarkdownBlock = B + 1) do Inc(I);
    Last := I;
    if (Last > First) and (Last < CharCount) and (FChars[Last - 1] = #10) then Dec(Last);
    Original := Copy(FMarkdownSource, FMarkdownOriginals[B].First, FMarkdownOriginals[B].Count);
    if FMarkdownOriginals[B].Locked and (B + 1 <> FOpenBlock) then
    begin
      if FMarkdownOriginals[B].Edited = '' then
        Result := Result + Original
      else
      begin
        J := Length(Original);
        while (J > 0) and (Original[J] in [#10, #13]) do Dec(J);
        Result := Result + StringReplace(FMarkdownOriginals[B].Edited, #10, EOL, [rfReplaceAll]) + Copy(Original, J + 1, MaxInt);
      end;
      P := FMarkdownOriginals[B].First + FMarkdownOriginals[B].Count;
      Continue;
    end;
    if I > First then
    begin
      Current := MarkdownRange(First, Last);
      if Current = FMarkdownOriginals[B].Canonical then
        Result := Result + Original
      else
      begin
        Preserved := '';
        if FAttrs[First].Kind <> ipkSource then
          Preserved := PreserveMarkdownText(Original, Copy(FMarkdownOriginals[B].Canonical, 1, Length(FMarkdownOriginals[B].Canonical) - Length(LineEnding)),
            Copy(Current, 1, Length(Current) - Length(LineEnding)));
        if Preserved <> '' then
        begin
          Result := Result + Preserved;
          P := FMarkdownOriginals[B].First + FMarkdownOriginals[B].Count;
          Continue;
        end;
        Ending := '';
        J := Length(Original);
        while (J > 0) and (Original[J] in [#10, #13]) do Dec(J);
        Ending := Copy(Original, J + 1, MaxInt);
        if Copy(Current, Length(Current) - Length(LineEnding) + 1, Length(LineEnding)) = LineEnding then
          SetLength(Current, Length(Current) - Length(LineEnding));
        Current := StringReplace(Current, LineEnding, EOL, [rfReplaceAll]);
        Result := Result + Current + Ending;
      end;
    end;
    P := FMarkdownOriginals[B].First + FMarkdownOriginals[B].Count;
  end;
  Result := Result + Copy(FMarkdownSource, P, MaxInt);
end;

function TInkRichEdit.MarkdownRange(AFirst, AEnd: integer): string;
var
  i, PS, CS, CE, NCells: integer;
  Kind, PrevKind: TInkParaKind;
  Lines: TStringList;
  InFence: boolean;
  PrevLevel: integer;
  Back, FenceLang, Fence: string;
  FenceRun, FenceMax, Tildes: integer;
const
  WordChars = ['A'..'Z', 'a'..'z', '0'..'9', #128..#255];

{ an & that Markdown would read as the start of an entity }
  function EntityAt(const T: string; K: integer): boolean;
  var
    E: integer;
  begin
    E := K + 1;
    while (E <= Length(T)) and (E - K < 34) and (T[E] in ['A'..'Z', 'a'..'z', '0'..'9', '#']) do Inc(E);
    Result := (E > K + 1) and (E <= Length(T)) and (T[E] = ';');
  end;

  { a backslash only where Markdown would read the character as markup }
  function EscapeMD(const T: string): string;
  var
    K: integer;
    Escape: boolean;
  begin
    Result := '';
    for K := 1 to Length(T) do
    begin
      case T[K] of
        '\', '`', '*', '[', ']': Escape := True;
        '_': Escape := not ((K > 1) and (K < Length(T)) and (T[K - 1] in WordChars) and (T[K + 1] in WordChars));
        '|': Escape := Kind in [ipkTableHead, ipkTableRow];
        '~': Escape := Tildes > 1;
        '<': Escape := (K = Length(T)) or (T[K + 1] in ['A'..'Z', 'a'..'z', '/', '!', '?']);
        '&': Escape := EntityAt(T, K);
        else
          Escape := False;
      end;
      if Escape then Result := Result + '\';
      Result := Result + T[K];
    end;
  end;

  { text at the start of a line that would open a list, quote, heading or
    rule gets a backslash in front of its marker }
  function EscapeLineStart(const T: string): string;
  var
    K, D: integer;
  begin
    Result := T;
    K := 1;
    while (K <= Length(T)) and (T[K] in [' ', #9]) do Inc(K);
    if K > Length(T) then Exit;
    D := K;
    while (D <= Length(T)) and (T[D] in ['0'..'9']) do Inc(D);
    if (D > K) and (D - K <= 9) and (D <= Length(T)) and (T[D] in ['.', ')']) and ((D = Length(T)) or (T[D + 1] in [' ', #9])) then
      Insert('\', Result, D)
    else if (T[K] = '>') or ((T[K] in ['-', '+']) and ((K = Length(T)) or (T[K + 1] in [' ', #9]))) or ((T[K] in ['-', '=']) and
      (Trim(StringReplace(T, T[K], '', [rfReplaceAll])) = '')) then
      Insert('\', Result, K)
    else if T[K] = '#' then
    begin
      D := K;
      while (D <= Length(T)) and (T[D] = '#') do Inc(D);
      if (D - K <= 6) and ((D > Length(T)) or (T[D] in [' ', #9])) then Insert('\', Result, K);
    end;
  end;

  { a link or image destination, in angle brackets only when it needs them }
  function Destination(const Text: string): string;
  var
    K, Depth: integer;
    Angle: boolean;
  begin
    Result := '';
    Depth := 0;
    Angle := False;
    for K := 1 to Length(Text) do
    begin
      case Text[K] of
        #0..#31: Result := Result + '%' + IntToHex(Ord(Text[K]), 2);
        '\', '<', '>': Result := Result + '\' + Text[K];
        '&': if EntityAt(Text, K) then Result := Result + '\&'
          else
            Result := Result + '&';
        '|': if Kind in [ipkTableHead, ipkTableRow] then Result := Result + '\|'
          else
            Result := Result + '|';
        else
          Result := Result + Text[K];
      end;
      case Text[K] of
        ' ', '<', '>': Angle := True;
        '(': Inc(Depth);
        ')': begin
          Dec(Depth);
          if Depth < 0 then Angle := True;
        end;
      end;
    end;
    if Angle or (Depth <> 0) then Result := '<' + Result + '>';
  end;

  function TitleText(const Text: string): string;
  var
    K: integer;
  begin
    Result := '';
    for K := 1 to Length(Text) do
      case Text[K] of
        '\', '"': Result := Result + '\' + Text[K];
        '&': if EntityAt(Text, K) then Result := Result + '\&'
          else
            Result := Result + '&';
        '|': if Kind in [ipkTableHead, ipkTableRow] then Result := Result + '\|'
          else
            Result := Result + '|';
        else
          Result := Result + Text[K];
      end;
  end;

  function CodeSpan(const Text: string): string;
  var
    K, Run, Longest: integer;
    Delimiter, Padding: string;
  begin
    Run := 0;
    Longest := 0;
    for K := 1 to Length(Text) do
      if Text[K] = '`' then
      begin
        Inc(Run);
        Longest := Max(Longest, Run);
      end
      else
        Run := 0;
    Delimiter := StringOfChar('`', Longest + 1);
    Padding := '';
    if (Text <> '') and ((Text[1] = '`') or (Text[Length(Text)] = '`') or ((Text[1] = ' ') and (Text[Length(Text)] = ' ') and (Trim(Text) <> ''))) then Padding := ' ';
    if Kind in [ipkTableHead, ipkTableRow] then
      Result := StringReplace(Text, '|', '\|', [rfReplaceAll])
    else
      Result := Text;
    Result := Delimiter + Padding + Result + Padding + Delimiter;
  end;

  { the paragraph's characters as Markdown inline text }
  function InlineMD(AFrom, ATo: integer): string;
  var
    K, J, RunEnd: integer;
    A: TInkAttr;
    Txt, Piece, Leading, Trailing: string;
    LineStart: boolean;
  begin
    Result := '';
    Tildes := 0;
    for K := AFrom to ATo do
      if FChars[K] = '~' then Inc(Tildes);
    LineStart := not (Kind in [ipkTableHead, ipkTableRow]);
    K := AFrom;
    while K <= ATo do
    begin
      if (FChars[K] = #10) and FAttrs[K].HardBreak then
      begin
        Result := Result + '  ' + LineEnding;
        LineStart := True;
        Inc(K);
        Continue;
      end;
      A := FAttrs[K];
      RunEnd := K;
      while (RunEnd + 1 <= ATo) and (FChars[RunEnd + 1] <> #10) and SameInkAttr(FAttrs[RunEnd + 1], A) do
        Inc(RunEnd);
      Txt := '';
      for J := K to RunEnd do
        Txt := Txt + FChars[J];
      if A.TaskState >= 0 then
      begin
        if A.TaskState = 1 then
          Piece := '[x]'
        else
          Piece := '[ ]';
      end
      else if A.ImageSource <> '' then
      begin
        Piece := '![' + EscapeMD(A.ImageAlt) + '](' + Destination(A.ImageSource);
        if A.ImageTitle <> '' then Piece := Piece + ' "' + TitleText(A.ImageTitle) + '"';
        Piece := Piece + ')';
      end
      else if (A.Face <> '') and (A.Kind <> ipkCode) then
        { a monospaced run is a code span; nothing nests inside backticks }
        Piece := CodeSpan(Txt)
      else
      begin
        Leading := '';
        Trailing := '';
        if A.Style * [fsBold, fsItalic, fsStrikeOut] <> [] then
        begin
          while (Txt <> '') and (Txt[1] in [' ', #9]) do
          begin
            Leading := Leading + Txt[1];
            Delete(Txt, 1, 1);
          end;
          while (Txt <> '') and (Txt[Length(Txt)] in [' ', #9]) do
          begin
            Trailing := Txt[Length(Txt)] + Trailing;
            Delete(Txt, Length(Txt), 1);
          end;
        end;
        Piece := EscapeMD(Txt);
        if LineStart and (A.Link = '') and (A.Style * [fsBold, fsItalic, fsStrikeOut, fsUnderline] = []) and (A.Script = isNormal) then
          Piece := EscapeLineStart(Piece);
        if (Piece <> '') and (fsBold in A.Style) then Piece := '**' + Piece + '**';
        if (Piece <> '') and (fsItalic in A.Style) then Piece := '*' + Piece + '*';
        if (Piece <> '') and (fsStrikeOut in A.Style) then Piece := '~~' + Piece + '~~';
        if fsUnderline in A.Style then Piece := '<u>' + Piece + '</u>';
        if A.Script = isSuperscript then Piece := '<sup>' + Piece + '</sup>';
        if A.Script = isSubscript then Piece := '<sub>' + Piece + '</sub>';
        Piece := EscapeMD(Leading) + Piece + EscapeMD(Trailing);
      end;
      if A.Link <> '' then
      begin
        Piece := '[' + Piece + '](' + Destination(A.Link);
        if A.LinkTitle <> '' then Piece := Piece + ' "' + TitleText(A.LinkTitle) + '"';
        Piece := Piece + ')';
      end;
      Result := Result + Piece;
      LineStart := False;
      K := RunEnd + 1;
    end;
  end;

  { the three bars the reader stands in for an <hr>, plain and alone on
    their line: a rule, written back as the rule it came from }
  function IsRule(AFrom, ATo: integer): boolean;
  var
    K: integer;
  begin
    Result := False;
    if (ATo - AFrom <> 2) or (ParaKindAt(AFrom) <> ipkText) or (ParaLevelAt(AFrom) > 0) then Exit;
    for K := AFrom to ATo do
      if (FChars[K] <> #$E2#$80#$95) or (FAttrs[K].Link <> '') or
        (FAttrs[K].ImageSource <> '') or (FAttrs[K].Face <> '') or (FAttrs[K].Style <> []) then Exit;
    Result := True;
  end;

  function RawText(AFrom, ATo: integer): string;
  var
    K: integer;
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
    FenceRun := 0;
    FenceMax := 2;
    for i := AFirst to AEnd - 1 do
      if FChars[i] = '`' then
      begin
        Inc(FenceRun);
        FenceMax := Max(FenceMax, FenceRun);
      end
      else
        FenceRun := 0;
    Fence := StringOfChar('`', FenceMax + 1);
    InFence := False;
    i := AFirst;
    while i <= AEnd do
    begin
      PS := i;
      while (i < AEnd) and ((FChars[i] <> #10) or FAttrs[i].HardBreak) do Inc(i);
      Kind := ParaKindAt(PS);
      if (PS = AEnd) and (PS > AFirst) and (ParaKindAt(PS - 1) in [ipkSource, ipkCode]) then
        Kind := ParaKindAt(PS - 1);
      { fences open and close around an unbroken run of code lines }
      if InFence and (Kind <> ipkCode) then
      begin
        Lines.Add(Fence);
        InFence := False;
      end;
      { a blank line between blocks, except inside a list, a quote, a fence
        or a table.  A nested item continues its list whatever its kind;
        two different kinds at the top level are two lists, kept apart. }
      if (Lines.Count > 0) and not InFence then
        if not (((Kind in [ipkBullet, ipkNumber]) and (PrevKind in [ipkBullet, ipkNumber]) and ((Kind = PrevKind) or (ParaLevelAt(PS) > 0) or (PrevLevel > 0))) or
          ((Kind = PrevKind) and (Kind in [ipkQuote, ipkCode, ipkSource])) or ((Kind in [ipkTableHead, ipkTableRow]) and (PrevKind in [ipkTableHead, ipkTableRow]))) then
          Lines.Add('');
      case Kind of
        ipkSource: Lines.Add(RawText(PS, i - 1));
        ipkH1..ipkH6:
          Lines.Add(StringOfChar('#', Ord(Kind) - Ord(ipkH1) + 1) + ' ' + InlineMD(PS, i - 1));
        ipkBullet:
          { three spaces per level: deep enough to nest under "1. " as well
            as under "- ", and never deep enough to read as indented code }
          Lines.Add(StringOfChar(' ', 3 * ParaLevelAt(PS)) + '- ' + InlineMD(PS, i - 1));
        ipkNumber:
          Lines.Add(StringOfChar(' ', 3 * ParaLevelAt(PS)) + IntToStr(ParaNumber(PS)) + '. ' + InlineMD(PS, i - 1));
        ipkQuote:
          Lines.Add('> ' + InlineMD(PS, i - 1));
        ipkCode:
        begin
          if InFence and (PS < CharCount) and (FAttrs[PS].Lang <> FenceLang) then
          begin
            { the language changed: this is another fence }
            Lines.Add(Fence);
            InFence := False;
          end;
          if not InFence then
          begin
            FenceLang := '';
            if PS < CharCount then FenceLang := FAttrs[PS].Lang;
            Lines.Add(Fence + FenceLang);
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
            if (CE = i) or IsCellBreak(CE) then
            begin
              Back := Back + ' ' + InlineMD(CS, CE - 1) + ' |';
              Inc(NCells);
              CS := CE + 1;
            end;
          Lines.Add(Back);
          if Kind = ipkTableHead then
          begin
            Back := '|';
            for CE := 1 to NCells do
            begin
              if CE <= Length(FAttrs[PS].TableAlign) then
                case FAttrs[PS].TableAlign[CE] of
                  'l': Back := Back + ' :--- |';
                  'r': Back := Back + ' ---: |';
                  'c': Back := Back + ' :---: |';
                  else
                    Back := Back + ' --- |';
                end
              else
                Back := Back + ' --- |';
            end;
            Lines.Add(Back);
          end;
        end;
        else if IsRule(PS, i - 1) then
          Lines.Add('---')
        else
          Lines.Add(InlineMD(PS, i - 1));
      end;
      PrevKind := Kind;
      PrevLevel := ParaLevelAt(PS);
      Inc(i);
    end;
    if InFence then Lines.Add(Fence);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function TInkRichEdit.PlainText: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to CharCount - 1 do
    if FChars[i] = #10 then
      Result := Result + LineEnding
    else
      Result := Result + FChars[i];
end;

end.
