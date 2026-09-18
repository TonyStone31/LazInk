{ Native scrolling HTML help viewer; no browser engine. Component code: MIT. }
unit InkPage;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, StdCtrls, Graphics, Types, Menus, InkDraw, InkMarkdown, InkCSS, InkCode, InkGIF, ExtCtrls, InkScrollBar, InkTouch, InkCopyMenu, InkEdit;
type
  TInkPageLinkEvent = procedure(Sender: TObject; const URL: string) of object;
  { Everything about a clicked link. }
  TInkLinkInfo = record
    { resolved against the page, and as written }
    URL, Href: string;
    { the link's target attribute - "_blank" asks for a new window }
    Target: string;
    { the picture the link wraps, resolved; '' for a text link }
    Image: string;
    { the block it is in }
    Block: Integer;
  end;
  { Handled stops the page from doing anything more with the click. }
  TInkLinkActivateEvent = procedure(Sender: TObject; const Link: TInkLinkInfo;
    var Handled: Boolean) of object;
  { How a picture is sized: never larger than it is (the default), always as
    wide as the column, or as large as fits in the window - for a window that
    shows one picture. }
  TInkImageFit = (iifShrink, iifWidth, iifWindow);
  { Applications may supply remote/cached content here. Return True on success. }
  TInkPageResourceEvent = procedure(Sender: TObject; const URL: string;
    Destination: TStream; var Handled: Boolean) of object;
  { A place in the page's words: a block, and a byte offset into its
    Words, from 0.  An Offset past the end means the block's end. }
  TInkPagePosition = record
    Block, Offset: Integer;
  end;
  { what dragging with the left mouse button does; a finger always scrolls }
  TInkMouseDrag = (imdSelect, imdScroll);
  { ifoMatchCase: capitals must match; ifoBackwards: the one before }
  TInkFindOption = (ifoMatchCase, ifoBackwards);
  TInkFindOptions = set of TInkFindOption;
  { a run of text as the renderer laid it out, in page coordinates }
  TInkPageRun = record
    Text: string;
    { where Text begins in the block's Words, from 0 }
    Start: Integer;
    Left, Top, Width, Height, LineHeight, Line, Part: Integer;
    FontName: string;
    FontSize: Integer;
    FontStyle: TFontStyles;
    FontColor: TColor;
  end;
  { A code block, for a host that would rather color it itself - SynEdit's
    highlighters, say.  ACode is the code as plain text and ALanguage what
    the fence or the class said (lower case, '' when nothing did).  Answer
    with LazInk markup in AMarkup - escaped text with <font color="...">
    round it - and the page draws that instead of its own coloring; leave
    AMarkup empty and the page colors the block itself. }
  TInkHighlightEvent = procedure(Sender: TObject; const ACode, ALanguage: string;
    var AMarkup: string) of object;
  TInkPageBlock = class
  public
    Source, Wrapped, Tag, CSSClass: string;
    { a code block: the code as plain text, and the language the fence or
      the class named ('' when it named none) }
    Code, CodeLanguage: string;
    { the ids that lead to this block, separated by spaces }
    Anchor: string;
    { a list item's bullet, number or task box, drawn hanging to the left of
      the text }
    Marker: string;
    { what the block sits inside, outermost first: 'l' a list, 'q' a quote,
      'd' a definition }
    Nest: string;
    Picture: TPicture;
    Animation: TInkGIF;
    { a picture: where it came from, where it is drawn, and the link around
      it, if any (href as in markup) }
    ImageSrc, LinkHref, LinkTarget: string;
    ImageRect: TRect;
    { the target of each text link in the block, in order }
    LinkTargets: array of string;
    { the title of each text link, in the same order: its tooltip }
    LinkTitles: array of string;
    { what a style attribute on the block's own element asked for }
    StyleAttr: string;
    { A <details>: the fold the block is inside (-1 outside every fold), and
      for a <summary>, the fold it opens and closes (-1 for anything else).
      A summary sits in its details' parent fold, so it stays visible. }
    FoldGroup, FoldHead: Integer;
    { how links in this block look, when CSS says so for where it is }
    LinkColor: TColor;
    NoLinkUnderline: Boolean;
    { a table's own margins, which may be negative: cards spaced apart line
      up with the text when the table reaches out by the spacing }
    MarginLeft, MarginRight: Integer;
    { A flex or grid container: its items as table cells, laid out in rows
      of however many fit each time the width changes. }
    Flex, FlexWrap: Boolean;
    FlexCells: array of string;
    FlexBasis, FlexGap, FlexMaxCols, FlexCols: Integer;
    FlexAttrs: string;
    { the block, and the part of it the words are drawn in; page coordinates }
    Bounds, TextBounds: TRect;
    Indent, PointSize, Padding, GapBefore, GapAfter, MarkerWidth: Integer;
    { code: whitespace kept, the fixed face, never wrapped - a long line is
      cut off at the block's edge }
    Pre: Boolean;
    { laid out as written, and cut off at the edge - code, or a memo with
      WordWrap off }
    NoWrap: Boolean;
    Bold: Boolean;
    FaceName: string;
    { where the bars of the quotes it is in are drawn, from the column's left }
    Bars: array of Integer;
    BorderColor: TColor;
    TextColor, BackColor, BarColor: TColor;
    { where each run of its text was drawn, and its words as they are
      copied - filled in when first needed, after each layout }
    Runs: array of TInkPageRun;
    RunCount: Integer;
    Words: string;
    RunsReady: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;
  { The engine behind TInkPage and TInkMemo: blocks of markup laid out down
    a scrolling column, with selection, the copy menu, find, touch and
    history.  Descendants decide where the blocks come from (Parse), how
    they look (StyleBlock) and how wide the column is (LayoutColumn). }
  TInkCustomPage = class(TCustomControl)
  private
    FBlocks: TList;
    FStyles: TInkStyleSheet;
    FScroll: TInkScrollBar;
    FTimer: TTimer;
    procedure Animate(Sender: TObject);
    procedure SetImageFit(AValue: TInkImageFit);
  private
    FSource, FLocation, FTitle, FHoverLink: string;
    FHoverBlock, FHoverLinkIndex: Integer;
    FClickedLink: TInkLinkInfo;
    FOnLinkActivate: TInkLinkActivateEvent;
    FImageFit: TInkImageFit;
    { which of the page's @media width queries held when it was read }
    FMediaState: string;
    FHistory: TStringList;
    FHistoryIndex: Integer;
    FTextFormat: TInkTextFormat;
    FStyleSheet: TStringList;
    FMarkdownRawHTML: Boolean;
    FLayoutDirty: Boolean;
    FContentHeight, FColumnLeft: Integer;
    FOnLinkClick: TInkPageLinkEvent;
    FOnResource: TInkPageResourceEvent;
    FOnHighlightCode: TInkHighlightEvent;
    FHighlightCode: Boolean;
    { dragging the page, which is how a finger scrolls.  A finger arrives as
      a touch (GTK3, through InkTouch) or as mouse events (everywhere else);
      both end up in the Grab* methods, and FGrabFinger remembers which it
      was, so a finger and a mouse can be told apart. }
    FDragScroll, FGrab, FDragged, FGrabFinger: Boolean;
    FGrabY, FGrabAt: Integer;
    FLastTouchEnd: QWord;
    { a flick: the page coasts on after a quick drag and slows down }
    FFlickScroll: Boolean;
    FFlickTimer: TTimer;
    FVelocity: Double;
    FFlickLast: QWord;
    FSampleY: array[0..15] of Integer;
    FSampleTime: array[0..15] of QWord;
    FSampleCount: Integer;
    procedure GrabBegin(X,Y: Integer; Finger: Boolean; Time: QWord);
    procedure GrabMove(X,Y: Integer; Time: QWord);
    procedure GrabEnd(X,Y: Integer; Time: QWord);
    procedure ClickAt(X,Y: Integer);
    procedure StopFlick;
    procedure FlickTimer(Sender: TObject);
    function GetFlicking: Boolean;
  private
    { selection }
    FSelAnchor, FSelCaret, FUnitFrom, FUnitTo: TInkPagePosition;
    FSelecting, FSelMoved: Boolean;
    { what a drag extends by: 0 characters, 1 words, 2 blocks }
    FSelectUnit: Integer;
    FPressX, FPressY, FDragX, FDragY: Integer;
    { counting clicks ourselves: GTK3's backend reports the third press of a
      triple click as a plain press }
    FClicks, FLastClickX, FLastClickY: Integer;
    FLastClickTime: QWord;
    FMouseDrag: TInkMouseDrag;
    FSelectionColor: TColor;
    FAutoScroll: TTimer;
    FRunBlock: TInkPageBlock;
    FOnSelectionChange: TNotifyEvent;
    FCopyMenu: Boolean;
    FCopyMenuHost: TInkCopyMenu;
    FOnCopyMenu: TInkCopyMenuEvent;
    procedure CollectRun(const AText: string; ALeft, ATop, AWidth, AHeight,
      ALine, APart: Integer; AFont: TFont);
    procedure PrepareRuns(B: TInkPageBlock);
    procedure RunFont(ACanvas: TCanvas; const R: TInkPageRun);
    function RunX(const R: TInkPageRun; Offset: Integer): Integer;
    function Clamp(const P: TInkPagePosition): TInkPagePosition;
    function WordAt(const P: TInkPagePosition; out AFrom, ATo: TInkPagePosition): Boolean;
    procedure ExtendTo(const P: TInkPagePosition);
    procedure SelectionChanged;
    procedure PaintSelection(ACanvas: TCanvas; Index: Integer; B: TInkPageBlock;
      const AFrom, ATo: TInkPagePosition);
    function GetSelectionStart: TInkPagePosition;
    function GetSelectionEnd: TInkPagePosition;
    procedure SetSelectionColor(AValue: TColor);
    procedure DoSelectAll(Sender: TObject);
    function BlockAt(X,Y: Integer): Integer;
  private
    { find in page }
    FFindEdit: TInkEdit;
    FFindText: string;
    FOnNavigate: TNotifyEvent;
    procedure Navigated;
    function GetCanGoBack: Boolean;
    function GetCanGoForward: Boolean;
    function SearchWords(Index: Integer; AOptions: TInkFindOptions): string;
    function FindFrom(const AText: string; AOptions: TInkFindOptions;
      const AFrom: TInkPagePosition; out AMatch: TInkPagePosition): Boolean;
    function SelectMatch(const AText: string; AOptions: TInkFindOptions;
      const AFrom: TInkPagePosition): Boolean;
    function FindStart(AOptions: TInkFindOptions): TInkPagePosition;
    function FindBarRect: TRect;
    function FindButtonRect(Index: Integer): TRect;
    procedure PlaceFindBar;
    procedure FindEditChange(Sender: TObject);
    procedure FindEditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GetFindBarVisible: Boolean;
    procedure PaintFindBar(ACanvas: TCanvas);
    function GetScrollY: Integer;
    function GetStyleSheet: TStrings;
    procedure SetStyleSheet(AValue: TStrings);
    procedure StyleSheetChanged(Sender: TObject);
    procedure SetMarkdownRawHTML(AValue: Boolean);
    procedure StyleScrollBar;
    procedure ScrollChanged(Sender: TObject);
    procedure SetTextFormat(AValue: TInkTextFormat);
    procedure SetSource(const AValue: string);
    function ReadResource(const URL: string; Destination: TStream): Boolean;
    function ReadText(const URL: string): string;
    procedure Navigate(const URL: string; ARemember: Boolean);
    procedure AddHistory(const URL: string; ADoc: TObject);
    procedure AddTextHistory;
    procedure GoHistory(Index: Integer);
  protected
    { layout, worked out once per layout and shared by the blocks }
    FListWidth, FQuoteWidth, FLayoutBase, FLayoutWidth, FLayoutFrom: Integer;
    FBodyText, FPageBack, FQuoteText, FBarDefault, FCodeBack: TColor;
    FColumnWidth: Integer;
    { <details>: whether each fold is open, and the fold each one sits in
      (-1 for an outermost one), by fold number }
    FFoldOpen: array of Boolean;
    FFoldParent: array of Integer;
    procedure SetHighlightCode(AValue: Boolean);
    { a code block's markup: the host's coloring, or the page's own }
    function CodeMarkup(const ACode, ALanguage: string): string;
    procedure ClearBlocks;
    { another <details>: its number, given the fold it is inside }
    function AddFold(AParent: Integer; AOpen: Boolean): Integer;
    { a block inside a fold that is shut, or inside one that is }
    function BlockHidden(B: TInkPageBlock): Boolean;
    { no blocks, no styles, no selection: what Parse starts from }
    procedure BeginDocument;
    procedure AddBlock(B: TInkPageBlock);
    { blocks from Index on are laid out again when next needed; 0 for all }
    procedure InvalidateLayout(FromIndex: Integer = 0);
    procedure Layout;
    { where the blocks come from: the page reads Source; a memo, its Lines }
    procedure Parse; virtual;
    { the column the blocks are laid out in, in client coordinates }
    procedure LayoutColumn(out ALeft, AWidth: Integer); virtual;
    function LayoutTop: Integer; virtual;
    { a block's font, colors, padding and gaps, before it is measured }
    procedure StyleBlock(B: TInkPageBlock); virtual;
    function Options: THTMLOptions; virtual;
    { the options a block is drawn with - a hovered link, say }
    function BlockOptions(Index: Integer): THTMLOptions; virtual;
    function HitLink(X,Y: Integer): string;
    function HitTestLink(X,Y: Integer; out ABlock: Integer; out AHit: THTMLHitInfo): Boolean;
    { a link was clicked }
    procedure LinkClicked(const Link: TInkLinkInfo); virtual;
    { the pointer moved onto another link, or off one (ABlock -1) }
    procedure HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo); virtual;
    { the copy menu's name for the block under the pointer }
    function CopyBlockCaption: string; virtual;
    procedure BlockFont(ACanvas: TCanvas; B: TInkPageBlock);
    property TextFormat: TInkTextFormat read FTextFormat write SetTextFormat default itfHTML;
    procedure CreateWnd; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { scrolls on while a selection is dragged beyond the top or bottom }
    procedure AutoScrollTimer(Sender: TObject);
    { a finger at client X, Y; Time in milliseconds, as GetTickCount64 }
    procedure TouchAt(Phase: TInkTouchPhase; X,Y: Integer; Time: QWord); virtual;
    { moves a flick on by Milliseconds and slows it down }
    procedure FlickStep(Milliseconds: Integer);
    procedure Paint; override;
    procedure Resize; override;
    procedure FontChanged(Sender: TObject); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromURL(const URL: string);
    procedure LoadHTML(const HTML: string; const BaseURL: string = '');
    { Markdown, read the way GitHub reads it; relative links and images are
      resolved against BaseURL }
    procedure LoadMarkdown(const Markdown: string; const BaseURL: string = '');
    procedure RenderTo(ACanvas: TCanvas);
    function PlainText: string;
    function ImageCount: Integer;
    { the blocks the page was read into, in document order }
    function BlockCount: Integer;
    function Block(Index: Integer): TInkPageBlock;
    { A <details>: whether what is under its <summary> is showing, and a
      click on the summary to open or shut it.  Index is the summary's
      block; ToggleFold on any other block does nothing. }
    function FoldOpen(Index: Integer): Boolean;
    procedure ToggleFold(Index: Integer);
    { is this block showing, or is it folded away inside a shut <details> }
    function BlockVisible(Index: Integer): Boolean;
    { Through the pages visited by links and LoadFromFile / LoadFromURL.
      The mouse's back and forward buttons, Alt+Left / Alt+Right and a
      keyboard's Back / Forward keys do the same. }
    procedure Back;
    procedure Forward;
    { forgets where Back and Forward would go; what is showing stays }
    procedure ClearHistory;
    procedure ScrollTo(Y: Integer);
    procedure JumpToAnchor(const Anchor: string);
    { A finger on the page, in client coordinates.  The page hooks the
      platform's touches itself where it has to (GTK3); a program with a
      touch source of its own can feed it here. }
    procedure Touch(Phase: TInkTouchPhase; X,Y: Integer);
    { whether the page is still coasting after a flick }
    property Flicking: Boolean read GetFlicking;

    { The character under client X, Y: the nearest place between two
      characters, in the nearest line of the nearest block. }
    function PositionAt(X,Y: Integer): TInkPagePosition;
    { and back: the top left of that place, in client coordinates }
    function PositionPoint(const APosition: TInkPagePosition): TPoint;
    { a block's words, as they are copied: the text as drawn, with a space
      where a line was wrapped, a line break where the source had one, and a
      tab between table cells }
    function BlockText(Index: Integer): string;
    procedure Select(const AFrom, ATo: TInkPagePosition);
    procedure SelectAll;
    procedure ClearSelection;
    function HasSelection: Boolean;
    { the selection as plain text - list markers included for items whose
      start is selected - and as HTML }
    function SelectedText: string;
    function SelectedHTML: string;
    { the selection to the clipboard, as text and as HTML }
    procedure CopyToClipboard;
    { what is painted behind selected text }
    function SelectionBackground: TColor;
    { fills the copy menu for client X, Y without opening it }
    function BuildCopyMenu(X,Y: Integer): TPopupMenu;
    { Selects the next place AText appears after the selection - before it
      with ifoBackwards - going round the end of the page, and scrolls it
      into view.  False when it appears nowhere. }
    function Find(const AText: string; AOptions: TInkFindOptions = []): Boolean;
    { how often AText appears, and which of them is selected (from 1; 0 when
      the selection is not one of them) }
    function FindCount(const AText: string; AOptions: TInkFindOptions;
      out Current: Integer): Integer;
    { scrolls just far enough for the place to be on screen }
    procedure ScrollIntoView(const APosition: TInkPagePosition);
    { The find bar: a box at the page's top right.  Ctrl+F opens it, typing
      finds as you go, Enter and F3 go to the next, Shift with either to the
      one before, Esc closes it.  A form with KeyPreview sees Enter and Esc
      first. }
    procedure ShowFindBar;
    procedure HideFindBar;
    property FindBarVisible: Boolean read GetFindBarVisible;
    property FindEdit: TInkEdit read FFindEdit;
    { for Back and Forward buttons }
    property CanGoBack: Boolean read GetCanGoBack;
    property CanGoForward: Boolean read GetCanGoForward;
    { the link being followed, while OnLinkClick runs - its target, and the
      picture it wraps }
    property ClickedLink: TInkLinkInfo read FClickedLink;
    { the selection's first and last places, in document order }
    property SelectionStart: TInkPagePosition read GetSelectionStart;
    property SelectionEnd: TInkPagePosition read GetSelectionEnd;
    function ResolveURL(const Reference: string): string;
    property Location: string read FLocation;
    { the page's <title>, or its first heading when it has none }
    property DocumentTitle: string read FTitle;
    property ContentHeight: Integer read FContentHeight;
    { how far down the page is scrolled, in pixels }
    property ScrollY: Integer read GetScrollY;
    { The page's own scrollbar, drawn by LazInk and colored from the page's
      CSS: scrollbar-color (thumb, then track) and scrollbar-width (auto,
      thin or none), read from html or :root, falling back to body.  Without
      them the track is the page background and the thumb sits halfway
      between that and the text color. }
    property ScrollBar: TInkScrollBar read FScroll;
  protected
    property Source: string read FSource write SetSource;
    { CSS applied to every page before the page's own styles - how a program
      dresses a Markdown document, which has no stylesheet, in its theme.
      A page's own rules win over these where both say something. }
    property StyleSheet: TStrings read GetStyleSheet write SetStyleSheet;
    { HTML written inside a Markdown source is drawn as HTML, not shown as
      text.  Only for documents you trust. }
    property MarkdownRawHTML: Boolean read FMarkdownRawHTML write SetMarkdownRawHTML default False;
    property OnLinkClick: TInkPageLinkEvent read FOnLinkClick write FOnLinkClick;
    { Before OnLinkClick, with everything about the link: its target, and the
      picture it wraps.  Set Handled to stop there. }
    property OnLinkActivate: TInkLinkActivateEvent read FOnLinkActivate write FOnLinkActivate;
    property ImageFit: TInkImageFit read FImageFit write SetImageFit default iifShrink;
    property OnResource: TInkPageResourceEvent read FOnResource write FOnResource;
    { Colors a code block's comments, strings, numbers and keywords.  The
      language comes from the fence (```pascal) or from
      class="language-x"; a block that names none is colored by rules most
      languages agree on, so every block gets something.  The colors
      themselves suit the page's background, and CSS may name them:
      a :root rule may name them - --ink-code-comment, --ink-code-string,
      --ink-code-number, --ink-code-keyword. }
    property HighlightCode: Boolean read FHighlightCode write SetHighlightCode default True;
    { a host that would rather color code itself - see TInkHighlightEvent }
    property OnHighlightCode: TInkHighlightEvent read FOnHighlightCode write FOnHighlightCode;
    { drag the page with the left button - or a finger - to scroll it; a
      press that moves less than a few pixels is still a click }
    property DragScroll: Boolean read FDragScroll write FDragScroll default True;
    { a quick drag with a finger leaves the page coasting, slowing down }
    property FlickScroll: Boolean read FFlickScroll write FFlickScroll default True;
    { What a left-button drag with the mouse does: select text (as in a
      browser) or scroll the page.  A finger always scrolls - on GTK3 its
      touches are told apart, and on Windows the mouse events a finger
      makes are marked.  Where the platform cannot tell (Qt, GTK2), choose
      imdScroll for a touch screen. }
    property MouseDrag: TInkMouseDrag read FMouseDrag write FMouseDrag default imdSelect;
    { behind selected text; clDefault is the system highlight blended into
      the page, so the words stay readable.  A page's ::selection
      background wins. }
    property SelectionColor: TColor read FSelectionColor write SetSelectionColor default clDefault;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    { after a new document is shown - a link, Back, Forward or a load from
      code - so a program can update its title and its Back and Forward
      buttons }
    property OnNavigate: TNotifyEvent read FOnNavigate write FOnNavigate;
    { the right-click menu: Copy, Copy this paragraph, Copy link address,
      Copy all, Select all.  Not shown when off or when PopupMenu is set. }
    property CopyMenu: Boolean read FCopyMenu write FCopyMenu default True;
    { lets a program add its own items to that menu as it opens }
    property OnCopyMenu: TInkCopyMenuEvent read FOnCopyMenu write FOnCopyMenu;
  end;

  { A scrolling viewer for whole HTML or Markdown documents. }
  TInkPage = class(TInkCustomPage)
  published
    property Source;
    property TextFormat;
    property StyleSheet;
    property MarkdownRawHTML;
    property OnLinkClick;
    property OnLinkActivate;
    property ImageFit;
    property OnResource;
    property HighlightCode;
    property OnHighlightCode;
    property DragScroll;
    property FlickScroll;
    property MouseDrag;
    property SelectionColor;
    property OnSelectionChange;
    property OnNavigate;
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
{ a hit link's href as written: entities read, and the renderer's stand-in
  for an ampersand turned back into one }
function LinkHref(const AHit: THTMLHitInfo): string;

implementation
uses Math, URIParser, LCLType, LCLIntf, LazUTF8, Forms, Clipbrd;

type
  { a list, a quote or a definition the parser is inside }
  TPageContainer = record
    Kind: Char;
    Counter: Integer;
    Style: string;
  end;

function LinkHref(const AHit: THTMLHitInfo): string;
begin
  Result := StringReplace(HTMLUnescape(AHit.LinkName),#1,'&',[rfReplaceAll]);
end;
function Attribute(const Tag, Name: string): string;
var P,Q: Integer; Key: string; Quote: Char;
begin
  Result := ''; P := 1;
  while (P<=Length(Tag)) and not (Tag[P] in [' ',#9,#10,#13]) do Inc(P);
  while P<=Length(Tag) do
  begin
    while (P<=Length(Tag)) and (Tag[P] in [' ',#9,#10,#13,'>','/']) do Inc(P);
    Q := P;
    while (P<=Length(Tag)) and not (Tag[P] in ['=', ' ',#9,#10,#13,'>']) do Inc(P);
    Key := LowerCase(Copy(Tag,Q,P-Q));
    while (P<=Length(Tag)) and (Tag[P] in [' ',#9,#10,#13]) do Inc(P);
    if (P>Length(Tag)) or (Tag[P]<>'=') then Continue;
    Inc(P); while (P<=Length(Tag)) and (Tag[P] in [' ',#9,#10,#13]) do Inc(P);
    Quote := #0;
    if (P<=Length(Tag)) and (Tag[P] in ['"', '''']) then begin Quote := Tag[P]; Inc(P) end;
    Q := P;
    if Quote<>#0 then while (P<=Length(Tag)) and (Tag[P]<>Quote) do Inc(P)
    else while (P<=Length(Tag)) and not (Tag[P] in [' ',#9,#10,#13,'>']) do Inc(P);
    if Key=Name then Exit(HTMLUnescape(Copy(Tag,Q,P-Q)));
    if Quote<>#0 then Inc(P);
  end;
end;
{ whether a tag has the attribute at all - checked, with or without a value }
function HasAttribute(const Tag, Name: string): Boolean;
var P,Q: Integer; Lower: string;
begin
  Result := False;
  Lower := LowerCase(Tag);
  P := Pos(Name,Lower);
  while P>0 do
  begin
    Q := P+Length(Name);
    if (P>1) and (Lower[P-1] in [' ',#9,#10,#13]) and
      ((Q>Length(Lower)) or (Lower[Q] in [' ',#9,#10,#13,'=','>','/'])) then Exit(True);
    P := Pos(Name,Lower,P+1);
  end;
end;
function TagName(const Tag: string): string;
var P,Q: Integer;
begin
  P := 2; if (P<=Length(Tag)) and (Tag[P]='/') then Inc(P);
  Q := P; while (P<=Length(Tag)) and (Tag[P] in ['a'..'z','A'..'Z','0'..'9']) do Inc(P);
  Result := LowerCase(Copy(Tag,Q,P-Q));
end;
function IsHeadingTag(const Tag: string): Boolean;
begin
  Result := (Length(Tag)=2) and (Tag[1]='h') and (Tag[2] in ['1'..'6']);
end;
{ elements with no closing tag }
function IsVoidElement(const E: string): Boolean;
begin
  Result := (E='br') or (E='img') or (E='hr') or (E='input') or (E='meta') or
    (E='link') or (E='wbr') or (E='col') or (E='source') or (E='area') or
    (E='base') or (E='embed') or (E='param') or (E='track');
end;
{ the items of a flex container as a table, Cols to a row }
function FlexTable(B: TInkPageBlock; Cols: Integer): string;
var I, N: Integer;
begin
  N := Length(B.FlexCells);
  Cols := Max(1,Cols);
  if B.FlexWrap or (B.FlexMaxCols>0) then
    Result := '<table width="100%" layout="fixed" cellspacing="'+IntToStr(B.FlexGap)+'"'+B.FlexAttrs+'>'
  else
    { a row that does not wrap: items as wide as their content }
    Result := '<table cellspacing="'+IntToStr(B.FlexGap)+'"'+B.FlexAttrs+'>';
  for I := 0 to N-1 do
  begin
    if I mod Cols=0 then Result := Result+'<tr>';
    Result := Result+B.FlexCells[I];
    if I mod Cols=Cols-1 then Result := Result+'</tr>';
  end;
  if N mod Cols<>0 then
  begin
    { the last row keeps the columns of the others }
    for I := N mod Cols to Cols-1 do Result := Result+'<td border="none" bgcolor="none"></td>';
    Result := Result+'</tr>';
  end;
  Result := Result+'</table>';
end;
{ the elements that start a block of their own; everything else is inline }
function IsBlockElement(const E: string): Boolean;
begin
  Result := IsHeadingTag(E) or (E='p') or (E='div') or (E='header') or
    (E='footer') or (E='nav') or (E='figure') or (E='figcaption') or (E='li') or
    (E='section') or (E='article') or (E='main') or (E='aside') or
    (E='address') or (E='details') or (E='summary') or (E='dt') or (E='dd') or
    (E='dl') or (E='ul') or (E='ol') or (E='menu') or (E='blockquote') or
    (E='pre') or (E='table') or (E='hr') or (E='img');
end;
{ Text between tags as renderer markup.  Collapse: white space is one space,
  as in running HTML; otherwise it is kept, tabs become spaces and line
  breaks become <br>, as in <pre>. }
function TextMarkup(const S: string; Collapse: Boolean; out APlain: string): string;
var P,Q,N,Column: Integer; E,T: string; Space: Boolean;
begin
  T := ''; P := 1; Space := False; Column := 0;
  while P<=Length(S) do
  begin
    if S[P]='&' then
    begin
      Q := P+1; while (Q<=Length(S)) and (Q-P<16) and (S[Q]<>';') do Inc(Q);
      if (Q<=Length(S)) and (S[Q]=';') then
      begin
        E := Copy(S,P+1,Q-P-1); N := -1;
        if Copy(E,1,2)='#x' then N := StrToIntDef('$'+Copy(E,3,MaxInt),-1)
        else if Copy(E,1,1)='#' then N := StrToIntDef(Copy(E,2,MaxInt),-1);
        if (N>=0) and (N<=$10FFFF) and not ((N>=$D800) and (N<=$DFFF)) then E := UnicodeToUTF8(N)
        else if E='rsaquo' then E := '›'
        else if E='lsaquo' then E := '‹'
        else if E='uarr' then E := '↑'
        else if E='darr' then E := '↓'
        else if E='larr' then E := '←'
        else if E='rarr' then E := '→'
        else if E='ndash' then E := '–'
        else if E='mdash' then E := '—'
        else if E='hellip' then E := '…'
        else if E='lsquo' then E := '‘'
        else if E='rsquo' then E := '’'
        else if E='ldquo' then E := '“'
        else if E='rdquo' then E := '”'
        else if E='laquo' then E := '«'
        else if E='raquo' then E := '»'
        else if E='times' then E := '×'
        else if E='middot' then E := '·'
        else if E='bull' then E := '•'
        else if E='deg' then E := '°'
        else if E='check' then E := '✓'
        else E := HTMLUnescape('&'+E+';');
        T := T + E; P := Q+1; Space := False; Inc(Column); Continue;
      end;
    end;
    if not Collapse then
    begin
      case S[P] of
        #13: ;
        #10: begin T := T+#10; Column := 0 end;
        #9: repeat T := T+' '; Inc(Column) until Column mod 4 = 0;
      else
        T := T+S[P];
        { a column is a character, not a byte }
        if (Ord(S[P]) and $C0)<>$80 then Inc(Column);
      end;
    end
    else if S[P] in [' ',#9,#10,#13] then
    begin if not Space then T := T+' '; Space := True end
    else begin T := T+S[P]; Space := False end;
    Inc(P);
  end;
  APlain := T;
  Result := HTMLEscape(T);
  if not Collapse then Result := StringReplace(Result,#10,'<br>',[rfReplaceAll]);
end;
function TextMarkup(const S: string; Collapse: Boolean = True): string;
var Plain: string;
begin
  Result := TextMarkup(S,Collapse,Plain);
end;
function RomanNumeral(N: Integer): string;
const
  Values: array[0..12] of Integer = (1000,900,500,400,100,90,50,40,10,9,5,4,1);
  Digits: array[0..12] of string = ('m','cm','d','cd','c','xc','l','xl','x','ix','v','iv','i');
var I: Integer;
begin
  Result := '';
  if (N<=0) or (N>3999) then Exit(IntToStr(N));
  for I := 0 to High(Values) do
    while N>=Values[I] do begin Result := Result+Digits[I]; Dec(N,Values[I]) end;
end;
function AlphaNumeral(N: Integer): string;
begin
  Result := '';
  if N<=0 then Exit(IntToStr(N));
  while N>0 do
  begin
    Dec(N);
    Result := Chr(Ord('a')+N mod 26)+Result;
    N := N div 26;
  end;
end;
{ A list item's marker, for a list-style-type (or an <ol type>) and the
  item's number.  Depth picks the bullet of an unstyled nested list, as a
  browser does. }
function ListMarker(const Style: string; Ordered: Boolean; Number, Depth: Integer): string;
var S: string;
begin
  S := LowerCase(Trim(Style));
  if S='1' then S := 'decimal'
  else if Style='a' then S := 'lower-alpha'
  else if Style='A' then S := 'upper-alpha'
  else if Style='i' then S := 'lower-roman'
  else if Style='I' then S := 'upper-roman';
  if S='none' then Exit('');
  if (S='lower-alpha') or (S='lower-latin') then Exit(AlphaNumeral(Number)+'.');
  if (S='upper-alpha') or (S='upper-latin') then Exit(UpperCase(AlphaNumeral(Number))+'.');
  if S='lower-roman' then Exit(RomanNumeral(Number)+'.');
  if S='upper-roman' then Exit(UpperCase(RomanNumeral(Number))+'.');
  if S='decimal' then Exit(IntToStr(Number)+'.');
  if S='disc' then Exit('•');
  if S='circle' then Exit('◦');
  if S='square' then Exit('▪');
  if Ordered then Exit(IntToStr(Number)+'.');
  case Depth mod 3 of
    0: Result := '•';
    1: Result := '◦';
  else
    Result := '▪';
  end;
end;
function MixColor(A, B: TColor; Amount: Double): TColor;
begin
  A := ColorToRGB(A); B := ColorToRGB(B);
  Result := RGBToColor(Round(Red(A)+(Red(B)-Red(A))*Amount),
    Round(Green(A)+(Green(B)-Green(A))*Amount),Round(Blue(A)+(Blue(B)-Blue(A))*Amount));
end;
function ColorAttr(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x',[Red(C),Green(C),Blue(C)]);
end;
constructor TInkPageBlock.Create;
begin
  inherited; Picture := TPicture.Create; LinkColor := clNone;
  FoldGroup := -1; FoldHead := -1;
end;
destructor TInkPageBlock.Destroy;
begin Animation.Free; Picture.Free; inherited end;
constructor TInkCustomPage.Create(AOwner: TComponent);
begin
  inherited; Width := 640; Height := 480; TabStop := True;
  FHoverBlock := -1; FHighlightCode := True;
  FBlocks := TList.Create; FStyles := TInkStyleSheet.Create;
  FStyleSheet := TStringList.Create; FStyleSheet.OnChange := @StyleSheetChanged;
  FHistory := TStringList.Create; FHistory.OwnsObjects := True; FHistoryIndex := -1;
  FScroll := TInkScrollBar.Create(Self); FScroll.Parent := Self;
  FScroll.Align := alRight; FScroll.Width := 18;
  FScroll.OnChange := @ScrollChanged; FLayoutDirty := True; FLayoutFrom := 0;
  FTimer := TTimer.Create(Self); FTimer.Interval := 20; FTimer.OnTimer := @Animate;
  FDragScroll := True; FFlickScroll := True;
  FFlickTimer := TTimer.Create(Self); FFlickTimer.Enabled := False;
  FFlickTimer.Interval := 16; FFlickTimer.OnTimer := @FlickTimer;
  FAutoScroll := TTimer.Create(Self); FAutoScroll.Enabled := False;
  FAutoScroll.Interval := 40; FAutoScroll.OnTimer := @AutoScrollTimer;
  FSelectionColor := clDefault; FCopyMenu := True;
  FCopyMenuHost := TInkCopyMenu.Create(Self);
  Cursor := crIBeam;
  Color := clWindow; Font.Color := clWindowText; Font.Size := 11;
end;
destructor TInkCustomPage.Destroy;
begin
  FTimer.Enabled := False; FFlickTimer.Enabled := False; FAutoScroll.Enabled := False; ClearBlocks; FBlocks.Free; FStyles.Free; FHistory.Free;
  FStyleSheet.OnChange := nil; FStyleSheet.Free;
  inherited;
end;
procedure TInkCustomPage.BeginDocument;
begin
  ClearBlocks; FStyles.Clear; FTitle := ''; FHoverLink := ''; FHoverBlock := -1;
  FSelecting := False;
  if HasSelection then
  begin
    FSelAnchor.Block := 0; FSelAnchor.Offset := 0; FSelCaret := FSelAnchor;
    if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
  end;
end;
function TInkCustomPage.CodeMarkup(const ACode, ALanguage: string): string;
var Colors: TInkCodeColors;
  function Named(const AVar: string; ADefault: TColor): TColor;
  var V: string;
  begin
    Result := ADefault;
    V := FStyles.Value('html','',AVar,'');
    if V<>'' then Result := CSSColor(FStyles.Resolve(V),ADefault);
  end;
begin
  Result := '';
  { a host with a real highlighter answers first }
  if Assigned(FOnHighlightCode) then FOnHighlightCode(Self,ACode,ALanguage,Result);
  if (Result<>'') or not FHighlightCode then Exit;
  Colors := InkCodeColors(FStyles.Color('body','','background',
    FStyles.Color('body','','background-color',Color)));
  Colors.Comment := Named('--ink-code-comment',Colors.Comment);
  Colors.Quoted := Named('--ink-code-string',Colors.Quoted);
  Colors.Number := Named('--ink-code-number',Colors.Number);
  Colors.Keyword := Named('--ink-code-keyword',Colors.Keyword);
  Result := InkHighlight(ACode,ALanguage,Colors);
end;
procedure TInkCustomPage.SetHighlightCode(AValue: Boolean);
begin
  if FHighlightCode=AValue then Exit;
  FHighlightCode := AValue;
  { the coloring is in the blocks' markup, so they have to be read again }
  Parse;
end;
procedure TInkCustomPage.ClearBlocks;
var I: Integer;
begin
  for I := 0 to FBlocks.Count-1 do TObject(FBlocks[I]).Free;
  FBlocks.Clear;
  SetLength(FFoldOpen,0); SetLength(FFoldParent,0);
end;
function TInkCustomPage.AddFold(AParent: Integer; AOpen: Boolean): Integer;
begin
  Result := Length(FFoldOpen);
  SetLength(FFoldOpen,Result+1); SetLength(FFoldParent,Result+1);
  FFoldOpen[Result] := AOpen; FFoldParent[Result] := AParent;
end;
function TInkCustomPage.BlockHidden(B: TInkPageBlock): Boolean;
var G: Integer;
begin
  Result := False;
  G := B.FoldGroup;
  { shut anywhere up the chain of details and the block is away }
  while (G>=0) and (G<Length(FFoldOpen)) do
  begin
    if not FFoldOpen[G] then Exit(True);
    G := FFoldParent[G];
  end;
end;
function TInkCustomPage.FoldOpen(Index: Integer): Boolean;
var B: TInkPageBlock;
begin
  B := TInkPageBlock(FBlocks[Index]);
  Result := (B.FoldHead>=0) and (B.FoldHead<Length(FFoldOpen)) and FFoldOpen[B.FoldHead];
end;
procedure TInkCustomPage.ToggleFold(Index: Integer);
var B: TInkPageBlock;
begin
  if (Index<0) or (Index>=FBlocks.Count) then Exit;
  B := TInkPageBlock(FBlocks[Index]);
  if (B.FoldHead<0) or (B.FoldHead>=Length(FFoldOpen)) then Exit;
  FFoldOpen[B.FoldHead] := not FFoldOpen[B.FoldHead];
  { everything from the summary down moves }
  InvalidateLayout(Index);
end;
function TInkCustomPage.BlockVisible(Index: Integer): Boolean;
begin
  Result := not BlockHidden(TInkPageBlock(FBlocks[Index]));
end;
procedure TInkCustomPage.AddBlock(B: TInkPageBlock);
begin FBlocks.Add(B) end;
procedure TInkCustomPage.InvalidateLayout(FromIndex: Integer);
begin
  if not FLayoutDirty or (FromIndex<FLayoutFrom) then FLayoutFrom := Max(0,FromIndex);
  FLayoutDirty := True;
  Invalidate;
end;
function TInkCustomPage.BlockOptions(Index: Integer): THTMLOptions;
var B: TInkPageBlock;
begin
  Result := Options;
  B := TInkPageBlock(FBlocks[Index]);
  if B.NoLinkUnderline then Result.LinkUnderline := False;
  if B.LinkColor<>clNone then Result.LinkColor := B.LinkColor;
end;
procedure TInkCustomPage.LinkClicked(const Link: TInkLinkInfo);
var Handled: Boolean;
begin
  FClickedLink := Link;
  Handled := False;
  if Assigned(FOnLinkActivate) then FOnLinkActivate(Self,Link,Handled);
  if Handled then Exit;
  if Assigned(FOnLinkClick) then FOnLinkClick(Self,Link.URL) else LoadFromURL(Link.URL);
end;
procedure TInkCustomPage.SetImageFit(AValue: TInkImageFit);
begin
  if FImageFit=AValue then Exit;
  FImageFit := AValue;
  InvalidateLayout(0);
end;
procedure TInkCustomPage.HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo);
begin
end;
function TInkCustomPage.CopyBlockCaption: string;
begin Result := SInkCopyParagraph end;
procedure TInkCustomPage.Animate(Sender: TObject);
var I: Integer; B: TInkPageBlock;
begin
  if not Visible then Exit;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if Assigned(B.Animation) and (B.Bounds.Bottom>=FScroll.Position) and
      (B.Bounds.Top<=FScroll.Position+ClientHeight) and B.Animation.Advance then
    begin B.Picture.Assign(B.Animation.Bitmap); Invalidate end;
  end;
end;
procedure TInkCustomPage.ScrollChanged(Sender: TObject);
begin Invalidate end;
procedure TInkCustomPage.SetTextFormat(AValue: TInkTextFormat);
begin if FTextFormat=AValue then Exit; FTextFormat := AValue; Parse end;
procedure TInkCustomPage.SetSource(const AValue: string);
begin FSource := AValue; Parse end;
function TInkCustomPage.GetStyleSheet: TStrings;
begin Result := FStyleSheet end;
procedure TInkCustomPage.SetStyleSheet(AValue: TStrings);
begin FStyleSheet.Assign(AValue) end;
procedure TInkCustomPage.StyleSheetChanged(Sender: TObject);
begin Parse end;
procedure TInkCustomPage.SetMarkdownRawHTML(AValue: Boolean);
begin
  if FMarkdownRawHTML=AValue then Exit;
  FMarkdownRawHTML := AValue;
  if FTextFormat=itfMarkdown then Parse;
end;
function TInkCustomPage.ResolveURL(const Reference: string): string;
begin
  if not ResolveRelativeURI(FLocation,Reference,Result) then Result := Reference;
end;
function TInkCustomPage.ReadResource(const URL: string; Destination: TStream): Boolean;
var FileName: string; Stream: TFileStream;
begin
  Result := False;
  if Assigned(FOnResource) then FOnResource(Self,URL,Destination,Result);
  if Result then begin Destination.Position := 0; Exit end;
  if not URIToFilename(URL,FileName) then Exit;
  if not FileExists(FileName) then Exit;
  Stream := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try Destination.CopyFrom(Stream,0); Destination.Position := 0; Result := True finally Stream.Free end;
end;
function TInkCustomPage.ReadText(const URL: string): string;
var S: TStringStream;
begin
  S := TStringStream.Create('');
  try
    if not ReadResource(URL,S) then raise EReadError.Create('Cannot load '+URL);
    Result := S.DataString;
  finally S.Free end;
end;
procedure TInkCustomPage.LoadHTML(const HTML: string; const BaseURL: string);
begin FLocation := BaseURL; FSource := HTML; FTextFormat := itfHTML; Parse; AddTextHistory; Navigated end;
procedure TInkCustomPage.LoadMarkdown(const Markdown: string; const BaseURL: string);
begin FLocation := BaseURL; FSource := Markdown; FTextFormat := itfMarkdown; Parse; AddTextHistory; Navigated end;
procedure TInkCustomPage.Navigated;
begin
  if Assigned(FOnNavigate) then FOnNavigate(Self);
end;
function TInkCustomPage.GetCanGoBack: Boolean;
begin Result := FHistoryIndex>0 end;
function TInkCustomPage.GetCanGoForward: Boolean;
begin Result := FHistoryIndex+1<FHistory.Count end;
procedure TInkCustomPage.LoadFromFile(const FileName: string);
begin Navigate(FilenameToURI(ExpandFileName(FileName)),True) end;
procedure TInkCustomPage.LoadFromURL(const URL: string);
begin Navigate(ResolveURL(URL),True) end;
procedure TInkCustomPage.Navigate(const URL: string; ARemember: Boolean);
var P: Integer; PageURL,Anchor,NewSource,Ext: string;
begin
  PageURL := URL; Anchor := ''; P := Pos('#',PageURL);
  if P>0 then begin Anchor := Copy(PageURL,P+1,MaxInt); Delete(PageURL,P,MaxInt) end;
  if PageURL<>FLocation then
  begin
    Ext := LowerCase(ExtractFileExt(PageURL));
    if (Ext='.png') or (Ext='.gif') or (Ext='.jpg') or (Ext='.jpeg') or
      (Ext='.bmp') or (Ext='.ico') then
      { a picture on its own is a page with just the picture, as in a
        browser }
      NewSource := '<html><head><title>'+HTMLEscape(Copy(PageURL,LastDelimiter('/',PageURL)+1,MaxInt))+
        '</title></head><body><img src="'+
        StringReplace(HTMLEscape(PageURL),'"','&quot;',[rfReplaceAll])+'" alt=""></body></html>'
    else
      NewSource := ReadText(PageURL);
    FLocation := PageURL; FSource := NewSource;
    { a .md file is Markdown, whatever the page before it was }
    if (Ext='.md') or (Ext='.markdown') then FTextFormat := itfMarkdown
    else FTextFormat := itfHTML;
    Parse;
  end;
  if Anchor<>'' then JumpToAnchor(Anchor) else FScroll.Position := 0;
  if ARemember then AddHistory(URL,nil);
  Navigated;
end;
{ a table's plain text ends each cell with a tab; the last one on a row is
  not wanted }
function TidyCopy(const S: string): string;
begin
  Result := StringReplace(S,#9#13#10,#13#10,[rfReplaceAll]);
  Result := StringReplace(Result,#9#10,#10,[rfReplaceAll]);
  while (Result<>'') and (Result[Length(Result)] in [#9,#10,#13]) do
    SetLength(Result,Length(Result)-1);
end;

function TInkCustomPage.PlainText: string;
var I: Integer; B: TInkPageBlock;
begin
  Result := '';
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if B.Marker<>'' then Result := Result + B.Marker + ' ';
    Result := Result + TidyCopy(HTMLPlainText(B.Source)) + LineEnding;
  end;
end;
function TInkCustomPage.ImageCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FBlocks.Count-1 do
    if TInkPageBlock(FBlocks[I]).Picture.Graphic<>nil then Inc(Result);
end;
function TInkCustomPage.BlockCount: Integer;
begin Result := FBlocks.Count end;
function TInkCustomPage.Block(Index: Integer): TInkPageBlock;
begin Layout; Result := TInkPageBlock(FBlocks[Index]) end;
type
  { a page that was handed over as text, kept so Back can show it again }
  TInkHistoryDoc = class
    Source, Base: string;
    Format: TInkTextFormat;
  end;
procedure TInkCustomPage.AddHistory(const URL: string; ADoc: TObject);
begin
  while FHistory.Count>FHistoryIndex+1 do FHistory.Delete(FHistory.Count-1);
  FHistory.AddObject(URL,ADoc); FHistoryIndex := FHistory.Count-1;
end;
procedure TInkCustomPage.AddTextHistory;
var Doc: TInkHistoryDoc;
begin
  Doc := TInkHistoryDoc.Create;
  Doc.Source := FSource; Doc.Base := FLocation; Doc.Format := FTextFormat;
  AddHistory(FLocation,Doc);
end;
procedure TInkCustomPage.GoHistory(Index: Integer);
var Doc: TInkHistoryDoc;
begin
  FHistoryIndex := Index;
  if FHistory.Objects[Index] is TInkHistoryDoc then
  begin
    Doc := TInkHistoryDoc(FHistory.Objects[Index]);
    FLocation := Doc.Base; FSource := Doc.Source; FTextFormat := Doc.Format;
    Parse;
    Navigated;
  end
  else Navigate(FHistory[Index],False);
end;
procedure TInkCustomPage.ClearHistory;
begin
  FHistory.Clear; FHistoryIndex := -1;
  { what is showing stays, as the only entry }
  if FSource<>'' then AddTextHistory;
end;
procedure TInkCustomPage.Back;
begin
  if FHistoryIndex<=0 then Exit;
  GoHistory(FHistoryIndex-1);
end;
procedure TInkCustomPage.Forward;
begin
  if FHistoryIndex+1>=FHistory.Count then Exit;
  GoHistory(FHistoryIndex+1);
end;
procedure TInkCustomPage.Parse;
var
  S, Raw, Element, Cls, Buffer, BlockTag, BlockClass, PendingAnchor, PendingMarker,
    Prefix, URL, Nest, Box, Kind, PendingAlign: string;
  P,Q,I,Level,TableDepth,SkipDepth,PreDepth,Depth: Integer;
  Closing: Boolean;
  B: TInkPageBlock;
  ImageData: TMemoryStream;
  Containers: array of TPageContainer;
  CodeBack, PageBack: TColor;
  { the link open where the parser is, so a picture inside it is clickable,
    and the targets of the links in the buffer, in order }
  OpenHref, OpenTarget: string;
  Targets: TStringList;
  { the tooltip of each of those links, in the same order }
  Titles: TStringList;
  { The style attributes of the inline elements open here, innermost last,
    each "element=the markup that closes it"; and the one on the block
    element being read, which the block keeps. }
  StyleStack: TStringList;
  PendingStyle: string;
  { <center>, and <div align=center> around several blocks }
  CenterDepth, RightDepth: Integer;
  { the <details> the parser is inside, innermost last, and the fold each
    block being made belongs to }
  Folds: array of Integer;
  FoldSeen: array of Boolean;
  CurFold, PendingHead: Integer;
  { a table's <caption>: its words, kept out of the table's own markup }
  CaptionDepth: Integer;
  CaptionText: string;
  { the code block being read: its text, the language it named, whether the
    page had already colored it itself, and each piece as it arrives }
  CodeRaw, CodeLang, Piece, Marked: string;
  CodeMarked: Boolean;
  { the table being read: its classes as a CSS context }
  TableCtx: string;
  Margins: TRect;
  { a table whose cells are display: block - one to a row }
  CellsAsBlocks: Boolean;
  TableSpacing: Integer;
  { an element hidden by display: none, and how deep inside it we are }
  HideDepth: Integer;
  { a flex or grid container being read, its items so far, and how deep
    inside the current item we are }
  FlexDepth, ItemDepth: Integer;
  FlexEl, FlexCls, FlexCtx, ItemCtx, ItemTag, Display, FlexText: string;
  FlexItems: TStringList;
  FlexBasis, FlexGap, FlexMaxCols: Integer;
  FlexWrap, ItemIsLink: Boolean;
  FirstItemTag, FirstItemCls: string;
  FlexPad: TRect;
  function DotClasses(const AClasses: string): string;
  begin
    Result := Trim(AClasses);
    if Result<>'' then Result := '.'+StringReplace(Result,' ','.',[rfReplaceAll]);
  end;
  { where the text being read sits, for CSS }
  function Context: string;
  begin
    if FlexDepth>0 then
    begin
      if ItemCtx<>'' then Result := ItemCtx else Result := FlexCtx;
    end
    else if TableDepth>0 then
    begin
      if ItemCtx<>'' then Result := ItemCtx else Result := TableCtx+' td';
    end
    else Result := BlockTag+DotClasses(BlockClass);
  end;
  { center or right, from the block's style attribute, its align attribute,
    the stylesheet, or a <center> it sits in }
  function BlockAlign: string;
  begin
    Result := LowerCase(StyleValue(PendingStyle,'text-align'));
    if Result='' then Result := LowerCase(PendingAlign);
    if Result='' then
      Result := LowerCase(FStyles.Value(BlockTag,BlockClass,'text-align','',Context));
    if Result='' then
    begin
      if CenterDepth>0 then Result := 'center'
      else if RightDepth>0 then Result := 'right';
    end;
  end;
  procedure Flush;
  var Text, Align: string; K: Integer;
  begin
    Text := Buffer;
    if BlockTag='pre' then
    begin
      { the line break that ends the last line of code is not another line }
      Text := TrimRight(Text);
      while Copy(Text,Length(Text)-3,4)='<br>' do Text := TrimRight(Copy(Text,1,Length(Text)-4));
    end
    else Text := Trim(Text);
    { an id with nothing yet to show waits for the block that has; so does
      a buffer of tags alone, like the <a> before a picture }
    if (Text='') or ((BlockTag<>'table') and (Trim(HTMLPlainText(Text))='')) then
    begin
      Buffer := ''; Targets.Clear; Titles.Clear;
      Exit;
    end;
    { a block the page says is centered or right-aligned says so in its
      markup, from where the words start }
    if BlockTag<>'table' then
    begin
      Align := BlockAlign;
      if Align='center' then Text := '<center>'+Text
      else if Align='right' then Text := '<right>'+Text;
    end;
    B := TInkPageBlock.Create;
    B.LinkTargets := nil;
    SetLength(B.LinkTargets,Targets.Count);
    for K := 0 to Targets.Count-1 do B.LinkTargets[K] := Targets[K];
    SetLength(B.LinkTitles,Titles.Count);
    for K := 0 to Titles.Count-1 do B.LinkTitles[K] := Titles[K];
    Targets.Clear; Titles.Clear;
    B.StyleAttr := PendingStyle; B.FoldGroup := CurFold;
    if PendingHead>=0 then
    begin
      B.FoldHead := PendingHead; B.FoldGroup := FFoldParent[PendingHead];
      PendingHead := -1;
    end;
    B.Source := Text; B.Tag := BlockTag; B.CSSClass := BlockClass;
    if (BlockTag='pre') and (Trim(CodeRaw)<>'') then
    begin
      B.Code := TrimRight(CodeRaw); B.CodeLanguage := CodeLang;
      if not CodeMarked then
      begin
        Marked := CodeMarkup(B.Code,CodeLang);
        if Marked<>'' then B.Source := Marked;
      end;
    end;
    B.Anchor := PendingAnchor; B.Nest := Nest; B.Pre := BlockTag='pre';
    { links take their look from where they are: table.cards a }
    B.NoLinkUnderline := LowerCase(FStyles.Value('a','','text-decoration','',Context))='none';
    B.LinkColor := FStyles.Color('a','','color',clNone,Context);
    if BlockTag='table' then
    begin
      Margins := FStyles.Box('table',BlockClass,'margin',Rect(0,0,0,0));
      B.MarginLeft := Margins.Left; B.MarginRight := Margins.Right;
      { cards stacked one to a row reach the edges, as blocks do }
      if CellsAsBlocks then
      begin
        Dec(B.MarginLeft,TableSpacing); Dec(B.MarginRight,TableSpacing);
      end;
    end;
    { an item's marker goes on its first words, not on an anchor before them }
    if Text<>'' then begin B.Marker := PendingMarker; PendingMarker := '' end;
    FBlocks.Add(B); Buffer := ''; PendingAnchor := '';
  end;
  procedure OpenContainer(AKind: Char; const AStyle: string; AStart: Integer);
  begin
    Level := Length(Containers); SetLength(Containers,Level+1);
    Containers[Level].Kind := AKind; Containers[Level].Style := AStyle;
    Containers[Level].Counter := AStart;
    if AKind in ['o','u'] then Nest := Nest+'l' else Nest := Nest+AKind;
  end;
  procedure CloseContainer(AKinds: TSysCharSet);
  begin
    Level := High(Containers);
    if (Level<0) or not (Containers[Level].Kind in AKinds) then Exit;
    SetLength(Containers,Level); Delete(Nest,Length(Nest),1);
  end;
  { the text directly inside a container, when no block element says what
    it is }
  function ContainerTag: string;
  begin
    Result := 'p';
    if Length(Containers)=0 then Exit;
    case Containers[High(Containers)].Kind of
      'q': Result := 'blockquote';
      'd': Result := 'dd';
    end;
  end;
  function ColorText(C: TColor): string;
  begin
    if C=clNone then Result := 'none' else Result := ColorAttr(C);
  end;
  { a cell's look from CSS - the table's rules for td, and the cell's own }
  function CellStyleAttrs(const El, AClasses, Ctx: string): string;
  var V: string; C: TColor; Sides: string; K: Integer;
  begin
    Result := '';
    V := FStyles.Value(El,AClasses,'background','',Ctx);
    if V='' then V := FStyles.Value(El,AClasses,'background-color','',Ctx);
    if V<>'' then Result := Result+' bgcolor="'+ColorText(CSSColor(V,clNone))+'"';
    if FStyles.Border(El,AClasses,C,Sides,Ctx) then
    begin
      if Sides='' then Result := Result+' border="none"'
      else
      begin
        Result := Result+' sides="'+Sides+'"';
        if (C<>clNone) and (C<>clDefault) then Result := Result+' bordercolor="'+ColorAttr(C)+'"';
      end;
    end;
    V := FStyles.Value(El,AClasses,'color','',Ctx);
    if V<>'' then
    begin
      C := CSSColor(V,clNone);
      if C<>clNone then Result := Result+' color="'+ColorAttr(C)+'"';
    end;
    K := FStyles.Pixels(El,AClasses,'border-radius',-1,Ctx);
    if K>=0 then Result := Result+' radius="'+IntToStr(K)+'"';
  end;
  function TableAttrs: string;
  var Pad: TRect; K: Integer; V: string;
  begin
    Result := '';
    CellsAsBlocks := LowerCase(FStyles.Value('td','','display','',TableCtx))='block';
    TableSpacing := 0;
    if CellsAsBlocks then
    begin
      { cells that are blocks: one to a row, the whole width, apart by
        their bottom margin }
      Result := Result+' width="100%" layout="fixed"';
      TableSpacing := Max(0,FStyles.Box('td','','margin',Rect(0,0,0,0),TableCtx).Bottom);
      if TableSpacing>0 then Result := Result+' cellspacing="'+IntToStr(TableSpacing)+'"';
    end
    else
    begin
      if FStyles.Value('table',Cls,'width','')='100%' then Result := Result+' width="100%"';
      V := FStyles.Value('td','','width','',TableCtx);
      if (LowerCase(FStyles.Value('table',Cls,'table-layout',''))='fixed') or
        ((V<>'') and (V[Length(V)]='%')) then Result := Result+' layout="fixed"';
      if LowerCase(FStyles.Value('table',Cls,'border-collapse',''))<>'collapse' then
      begin
        K := FStyles.Pixels('table',Cls,'border-spacing',0);
        if K>0 then Result := Result+' cellspacing="'+IntToStr(K)+'"';
      end;
    end;
    Pad := FStyles.Box('td','','padding',Rect(-1,-1,-1,-1),TableCtx);
    if (Pad.Left>=0) or (Pad.Top>=0) or (Pad.Right>=0) or (Pad.Bottom>=0) then
      Result := Result+Format(' cellpadding="%d %d %d %d"',[Max(0,Pad.Top),Max(0,Pad.Right),
        Max(0,Pad.Bottom),Max(0,Pad.Left)]);
    V := CellStyleAttrs('td','',TableCtx);
    { the table's default cell look goes on the table }
    V := StringReplace(V,' bgcolor=',' cellbg=',[]);
    Result := Result+V;
  end;
  function CellAlign: string;
  var A: string;
  begin
    A := LowerCase(Attribute(Raw,'align'));
    if A='' then
    begin
      A := LowerCase(StringReplace(Attribute(Raw,'style'),' ','',[rfReplaceAll]));
      if Pos('text-align:center',A)>0 then A := 'center'
      else if Pos('text-align:right',A)>0 then A := 'right'
      else A := LowerCase(FStyles.Value(Element,Cls,'text-align','',TableCtx));
    end;
    if A='center' then Result := '<center>'
    else if A='right' then Result := '<right>'
    else Result := '';
  end;
  { What a style attribute asks for, as markup, and in AClose the markup
    that puts it back.  Colors, size, weight, slant and decoration: the
    things people write a style attribute for. }
  function StyleMarkup(const AStyle: string; out AClose: string): string;
  var V, FG, BG, Sz: string; C: TColor; K: Integer;
  begin
    Result := ''; AClose := '';
    if Pos(':',AStyle)=0 then Exit;
    FG := ''; BG := ''; Sz := '';
    V := StyleValue(AStyle,'color');
    if V<>'' then
    begin
      C := CSSColor(FStyles.Resolve(V),clNone);
      if C<>clNone then FG := ' color="'+ColorAttr(C)+'"';
    end;
    V := StyleValue(AStyle,'background-color');
    if V='' then V := StyleValue(AStyle,'background');
    if V<>'' then
    begin
      C := CSSColor(FStyles.Resolve(V),clNone);
      if C<>clNone then BG := ' bgcolor="'+ColorAttr(C)+'"';
    end;
    { a size in pixels, as CSS writes it, is three quarters of it in points }
    K := CSSPixels(StyleValue(AStyle,'font-size'),-1);
    if K>0 then Sz := ' size="'+IntToStr(Max(1,K*3 div 4))+'"';
    if (FG<>'') or (BG<>'') or (Sz<>'') then
    begin
      Result := '<font'+Sz+FG+BG+'>'; AClose := '</font>';
    end;
    V := LowerCase(StyleValue(AStyle,'font-weight'));
    if (V='bold') or (V='bolder') or (StrToIntDef(V,0)>=600) then
    begin
      Result := Result+'<b>'; AClose := '</b>'+AClose;
    end;
    V := LowerCase(StyleValue(AStyle,'font-style'));
    if (V='italic') or (V='oblique') then
    begin
      Result := Result+'<i>'; AClose := '</i>'+AClose;
    end;
    V := LowerCase(StyleValue(AStyle,'text-decoration'));
    if Pos('underline',V)>0 then
    begin
      Result := Result+'<u>'; AClose := '</u>'+AClose;
    end;
    if Pos('line-through',V)>0 then
    begin
      Result := Result+'<s>'; AClose := '</s>'+AClose;
    end;
  end;
  function InlineMarkup: string;
  var BG, FG: string; C: TColor; K: Integer;
  begin
    Result := '';
    if Closing then Prefix := '/' else Prefix := '';
    if (Element='b') or (Element='strong') then Exit('<'+Prefix+'b>');
    if (Element='i') or (Element='em') or (Element='cite') or (Element='dfn') then Exit('<'+Prefix+'i>');
    if (Element='u') or (Element='s') or (Element='sup') or (Element='sub') then Exit('<'+Prefix+Element+'>');
    if (Element='del') or (Element='strike') then Exit('<'+Prefix+'s>');
    if Element='ins' then Exit('<'+Prefix+'u>');
    if Element='br' then Exit('<br>');
    if Element='a' then
    begin
      if Closing then
      begin
        OpenHref := ''; OpenTarget := '';
        Exit('</a>');
      end;
      if Attribute(Raw,'href')='' then Exit;
      Result := StringReplace(HTMLEscape(Attribute(Raw,'href')),'"','&quot;',[rfReplaceAll]);
      OpenHref := Result; OpenTarget := Attribute(Raw,'target');
      Targets.Add(OpenTarget); Titles.Add(Attribute(Raw,'title'));
      Exit('<a href="'+Result+'">');
    end;
    if (Element='code') or (Element='kbd') or (Element='tt') or (Element='samp') then
    begin
      { inside <pre> the whole block is already code }
      if PreDepth>0 then Exit;
      if Closing then Exit('</font>');
      BG := ''; FG := '';
      C := FStyles.Color(Element,Cls,'background',
        FStyles.Color(Element,Cls,'background-color',CodeBack));
      if C<>clNone then BG := ' bgcolor="'+ColorAttr(C)+'"';
      C := FStyles.Color(Element,Cls,'color',clNone);
      if C<>clNone then FG := ' color="'+ColorAttr(C)+'"';
      Exit('<font face="'+InkMonoFace+'"'+BG+FG+'>');
    end;
    if Element='small' then
    begin
      if Closing then Exit('</font>');
      K := FStyles.Pixels('small',Cls,'font-size',-1,Context);
      if K>0 then K := Max(1,K*3 div 4)
      else if Font.Size>0 then K := Max(1,Round(Font.Size*0.85))
      else K := 9;
      C := FStyles.Color('small',Cls,'color',clNone,Context);
      FG := '';
      if C<>clNone then FG := ' color="'+ColorAttr(C)+'"';
      Exit('<font size="'+IntToStr(K)+'"'+FG+'>');
    end;
    if Element='mark' then
    begin
      if Closing then Exit('</font>');
      Exit('<font bgcolor="'+ColorAttr(FStyles.Color('mark',Cls,'background',RGBToColor($FF,$F3,$A0)))+'">');
    end;
    if Element='q' then
    begin
      { a quotation inside a sentence wears its quotation marks }
      if Closing then Exit('”') else Exit('“');
    end;
    if Element='font' then Exit(Raw);
  end;
  { an inline element, with whatever its own style attribute asks for
    wrapped round it }
  function InlineTag: string;
  var Open, Close: string; K: Integer;
  begin
    Result := InlineMarkup;
    if IsVoidElement(Element) or (Element='') then Exit;
    if Closing then
    begin
      { the style of the element this closes, innermost first }
      for K := StyleStack.Count-1 downto 0 do
        if StyleStack.Names[K]=Element then
        begin
          Result := StyleStack.ValueFromIndex[K]+Result;
          StyleStack.Delete(K);
          Break;
        end;
      Exit;
    end;
    Open := StyleMarkup(Attribute(Raw,'style'),Close);
    StyleStack.Add(Element+'='+Close);
    Result := Result+Open;
  end;
  { a length from a list of them, like gap: 10px 12px, or flex: 1 1 220px }
  function FirstPixels(const V: string; Last: Boolean): Integer;
  var Parts: TStringList; K: Integer;
  begin
    Result := -1;
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
      Parts.DelimitedText := V;
      for K := 0 to Parts.Count-1 do
        if (Pos('px',LowerCase(Parts[K]))>0) or (Pos('em',LowerCase(Parts[K]))>0) or
          ((Parts.Count=1) and (CSSPixels(Parts[K],-1)>0)) then
        begin
          Result := CSSPixels(Parts[K],-1);
          if not Last then Exit;
        end;
    finally Parts.Free end;
  end;
  procedure StartFlex(const ADisplay: string);
  var V: string; K: Integer;
  begin
    Flush;
    FlexEl := Element; FlexCls := Cls;
    FlexCtx := Trim(Context+' '+Element+DotClasses(Cls));
    if TableDepth=0 then FlexCtx := Element+DotClasses(Cls);
    FlexItems.Clear; FlexText := '';
    FlexDepth := 1; ItemDepth := 0; ItemCtx := '';
    FlexBasis := -1; FlexMaxCols := 0; FlexPad := Rect(-1,-1,-1,-1);
    V := FStyles.Value(Element,Cls,'column-gap','');
    if V='' then V := FStyles.Value(Element,Cls,'gap','');
    FlexGap := Max(0,FirstPixels(V,False));
    if Pos('grid',ADisplay)>0 then
    begin
      V := LowerCase(FStyles.Value(Element,Cls,'grid-template-columns',''));
      FlexWrap := (Pos('auto-fill',V)>0) or (Pos('auto-fit',V)>0);
      K := Pos('minmax(',V);
      if K>0 then FlexBasis := FirstPixels(StringReplace(Copy(V,K+7,MaxInt),',',' ',[rfReplaceAll]),False);
      K := Pos('repeat(',V);
      if (K>0) and not FlexWrap then
        FlexMaxCols := StrToIntDef(Trim(Copy(V,K+7,Pos(',',Copy(V,K+7,MaxInt))-1)),0)
      else if (K=0) and (V<>'') then
      begin
        { "1fr 1fr 1fr": as many columns as it names }
        V := Trim(V); FlexMaxCols := 1;
        for K := 1 to Length(V) do if (V[K]=' ') and (V[K-1]<>' ') then Inc(FlexMaxCols);
      end;
      if FlexMaxCols=0 then FlexWrap := True;
    end
    else
      FlexWrap := Pos('wrap',LowerCase(FStyles.Value(Element,Cls,'flex-wrap',
        FStyles.Value(Element,Cls,'flex-flow',''))))>0;
  end;
  procedure StartItem;
  var V: string;
  begin
    ItemTag := Element;
    ItemCtx := FlexCtx+' '+Element+DotClasses(Cls);
    { the first item says how wide the items want to be, and their padding }
    if FlexBasis<0 then
    begin
      V := FStyles.Value(Element,Cls,'flex-basis','',FlexCtx);
      if V='' then V := FStyles.Value(Element,Cls,'flex','',FlexCtx);
      FlexBasis := FirstPixels(V,True);
      if FlexBasis<=0 then FlexBasis := FStyles.Pixels(Element,Cls,'min-width',-1,FlexCtx);
      if FlexBasis<=0 then FlexBasis := FStyles.Pixels(Element,Cls,'width',-1,FlexCtx);
    end;
    if FlexPad.Top<0 then
    begin
      FlexPad := FStyles.Box(Element,Cls,'padding',Rect(0,0,0,0),FlexCtx);
      FirstItemTag := Element; FirstItemCls := Cls;
    end;
    Buffer := '<td'+CellStyleAttrs(Element,Cls,FlexCtx)+'>';
    ItemIsLink := (Element='a') and (Attribute(Raw,'href')<>'');
    if ItemIsLink then Buffer := Buffer+InlineTag;
  end;
  procedure EndItem;
  begin
    if ItemIsLink then Buffer := Buffer+'</a>';
    ItemIsLink := False;
    Buffer := TrimRight(Buffer);
    while Copy(Buffer,Length(Buffer)-3,4)='<br>' do SetLength(Buffer,Length(Buffer)-4);
    FlexItems.Add(Buffer+'</td>');
    Buffer := ''; ItemCtx := '';
  end;
  procedure EndFlex;
  var K: Integer;
  begin
    FlexDepth := 0;
    if FlexItems.Count=0 then Exit;
    B := TInkPageBlock.Create;
    B.Tag := 'table'; B.CSSClass := FlexCls; B.Nest := Nest;
    B.Anchor := PendingAnchor; PendingAnchor := '';
    B.Flex := True; B.FlexWrap := FlexWrap; B.FlexGap := FlexGap;
    if FlexBasis<=0 then FlexBasis := Scale96ToFont(200);
    B.FlexBasis := FlexBasis; B.FlexMaxCols := FlexMaxCols;
    B.FlexAttrs := Format(' cellpadding="%d %d %d %d" border="none"',
      [Max(0,FlexPad.Top),Max(0,FlexPad.Right),Max(0,FlexPad.Bottom),Max(0,FlexPad.Left)]);
    SetLength(B.FlexCells,FlexItems.Count);
    for K := 0 to FlexItems.Count-1 do B.FlexCells[K] := FlexItems[K];
    B.FlexCols := FlexItems.Count;
    B.Source := FlexTable(B,B.FlexCols);
    SetLength(B.LinkTargets,Targets.Count);
    for K := 0 to Targets.Count-1 do B.LinkTargets[K] := Targets[K];
    Targets.Clear;
    { links take their look from the item when it is the link (a.card),
      or from rules for links inside the items }
    if FirstItemTag='a' then
    begin
      B.NoLinkUnderline := LowerCase(FStyles.Value('a',FirstItemCls,'text-decoration','',FlexCtx))='none';
      B.LinkColor := FStyles.Color('a',FirstItemCls,'color',clNone,FlexCtx);
    end
    else
    begin
      B.NoLinkUnderline := LowerCase(FStyles.Value('a','','text-decoration','',
        FlexCtx+' '+FirstItemTag+DotClasses(FirstItemCls)))='none';
      B.LinkColor := FStyles.Color('a','','color',clNone,FlexCtx+' '+FirstItemTag+DotClasses(FirstItemCls));
    end;
    { the outer gap the table adds is not the container's: reach out by it }
    Margins := FStyles.Box(FlexEl,FlexCls,'margin',Rect(0,0,0,0));
    B.MarginLeft := Margins.Left-FlexGap; B.MarginRight := Margins.Right-FlexGap;
    FBlocks.Add(B);
    BlockTag := ContainerTag; BlockClass := '';
    FirstItemTag := ''; FirstItemCls := '';
  end;
begin
  if FBlocks=nil then Exit;
  BeginDocument;
  if FTextFormat=itfMarkdown then
  begin
    if FMarkdownRawHTML then S := MarkdownToHTML(FSource,[imoRawHTML])
    else S := MarkdownToHTML(FSource);
  end
  else S := FSource;
  { @media width queries are judged against the page's own width }
  if ClientWidth>0 then FStyles.MediaWidth := ClientWidth else FStyles.MediaWidth := 1024;
  { the host's styles first, so the page's own come after them and win }
  if FStyleSheet.Count>0 then FStyles.Add(FStyleSheet.Text);
  { Collect external styles before layout; scripts and page metadata never paint. }
  P := 1;
  while P<=Length(S) do
  begin
    if S[P]<>'<' then begin Inc(P); Continue end;
    Q := P; while (Q<=Length(S)) and (S[Q]<>'>') do Inc(Q);
    Raw := Copy(S,P,Q-P+1); Element := TagName(Raw);
    if (Element='link') and (LowerCase(Attribute(Raw,'rel'))='stylesheet') then
    begin
      URL := ResolveURL(Attribute(Raw,'href'));
      try FStyles.Add(ReadText(URL)) except on E: EReadError do { fallback to control theme } ; end;
    end;
    if (Element='style') and (Copy(Raw,1,2)<>'</') then
    begin
      I := Pos('</style',LowerCase(Copy(S,Q+1,MaxInt)));
      if I>0 then FStyles.Add(Copy(S,Q+1,I-1));
    end;
    if (Element='title') and (Copy(Raw,1,2)<>'</') then
    begin
      I := Pos('</title',LowerCase(Copy(S,Q+1,MaxInt)));
      if I>0 then FTitle := HTMLPlainText(TextMarkup(Copy(S,Q+1,I-1)));
    end;
    P := Q+1;
  end;
  FMediaState := FStyles.MediaState(FStyles.MediaWidth);
  { code with no background of its own gets a shade of the page's, so it
    still reads as code }
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  CodeBack := HTMLShadeColor(PageBack,7);
  Targets := TStringList.Create; Titles := TStringList.Create;
  StyleStack := TStringList.Create;
  try
  OpenHref := ''; OpenTarget := '';
  HideDepth := 0; FlexDepth := 0; ItemDepth := 0; ItemCtx := ''; ItemIsLink := False;
  CellsAsBlocks := False; TableSpacing := 0;
  FlexItems := TStringList.Create;
  P := 1; Buffer := ''; BlockTag := 'p'; BlockClass := ''; Nest := '';
  PendingAnchor := ''; PendingMarker := ''; TableDepth := 0; SkipDepth := 0; PreDepth := 0;
  PendingStyle := ''; PendingAlign := ''; CenterDepth := 0; RightDepth := 0;
  CaptionDepth := 0; CaptionText := ''; CurFold := -1; PendingHead := -1;
  CodeRaw := ''; CodeLang := ''; CodeMarked := False;
  SetLength(Folds,0); SetLength(FoldSeen,0);
  SetLength(Containers,0);
  while P<=Length(S) do
  begin
    if S[P]<>'<' then
    begin
      Q := P; while (P<=Length(S)) and (S[P]<>'<') do Inc(P);
      if (SkipDepth>0) or (HideDepth>0) then Continue;
      if CaptionDepth>0 then
      begin
        CaptionText := CaptionText+TextMarkup(Copy(S,Q,P-Q));
        Continue;
      end;
      if (FlexDepth>0) and (ItemDepth=0) then
      begin
        { words straight inside a flex container are an item of their own }
        if Trim(Copy(S,Q,P-Q))<>'' then
          FlexItems.Add('<td>'+TextMarkup(Copy(S,Q,P-Q))+'</td>');
        Continue;
      end;
      if PreDepth>0 then
      begin
        { code is kept as text as well, for the highlighter to read }
        Buffer := Buffer+TextMarkup(Copy(S,Q,P-Q),False,Piece);
        CodeRaw := CodeRaw+Piece;
        Continue;
      end;
      Buffer := Buffer+TextMarkup(Copy(S,Q,P-Q));
      Continue;
    end;
    if Copy(S,P,4)='<!--' then
    begin
      Q := Pos('-->',Copy(S,P+4,MaxInt));
      if Q=0 then Break;
      Inc(P,Q+6); Continue;
    end;
    Q := P; while (Q<=Length(S)) and (S[Q]<>'>') do Inc(Q);
    Raw := Copy(S,P,Q-P+1); P := Q+1; Element := TagName(Raw);
    Closing := Copy(Raw,1,2)='</'; Cls := Attribute(Raw,'class');
    if (Element='head') or (Element='script') or (Element='style') or
      (Element='template') or (Element='svg') then
    begin
      { a drawing or a template holds nothing the page should read out - an
        <svg> keeps its <title> inside it.  One written <svg ... /> holds
        nothing at all. }
      if Copy(Raw,Length(Raw)-1,2)<>'/>' then
        if Closing then SkipDepth := Max(0,SkipDepth-1) else Inc(SkipDepth);
      Continue;
    end;
    if SkipDepth>0 then Continue;
    { display: none - the element and everything in it }
    if HideDepth>0 then
    begin
      if not IsVoidElement(Element) then
        if Closing then Dec(HideDepth) else Inc(HideDepth);
      Continue;
    end;
    if not Closing and not IsVoidElement(Element) and (PreDepth=0) then
    begin
      Display := LowerCase(FStyles.Value(Element,Cls,'display','',Context));
      if (Display='none') or HasAttribute(Raw,'hidden') then
      begin
        HideDepth := 1;
        Continue;
      end;
      if (FlexDepth=0) and (TableDepth=0) and
        ((Display='flex') or (Display='inline-flex') or (Display='grid') or (Display='inline-grid')) then
      begin
        StartFlex(Display);
        Continue;
      end;
    end;
    if FlexDepth>0 then
    begin
      { inside a flex container: each child is an item, its insides one
        cell's worth of words }
      if IsVoidElement(Element) then
      begin
        if ItemDepth=0 then
        begin
          if Element='img' then FlexItems.Add('<td>'+HTMLEscape(Attribute(Raw,'alt'))+'</td>');
        end
        else if Element='br' then Buffer := Buffer+'<br>'
        else if Element='img' then Buffer := Buffer+HTMLEscape(Attribute(Raw,'alt'))
        else if Element='input' then Buffer := Buffer+InlineTag;
        Continue;
      end;
      if not Closing then
      begin
        Inc(ItemDepth);
        if ItemDepth=1 then StartItem
        else if IsHeadingTag(Element) then Buffer := Buffer+'<b>'
        else if Element='li' then Buffer := Buffer+'• '
        else if not IsBlockElement(Element) then Buffer := Buffer+InlineTag;
        Continue;
      end;
      if ItemDepth=0 then
      begin
        EndFlex;
        Continue;
      end;
      if ItemDepth=1 then EndItem
      else if IsHeadingTag(Element) then Buffer := Buffer+'</b><br>'
      else if IsBlockElement(Element) then
      begin
        if (Buffer<>'') and (Copy(Buffer,Length(Buffer)-3,4)<>'<br>') then Buffer := Buffer+'<br>';
      end
      else Buffer := Buffer+InlineTag;
      Dec(ItemDepth);
      Continue;
    end;
    if not Closing then
    begin
      URL := Attribute(Raw,'id');
      if (URL='') and (Element='a') then URL := Attribute(Raw,'name');
      if URL<>'' then
      begin
        { a block's id belongs to the block, so what came before is
          finished first; an inline id marks the block it is in }
        if IsBlockElement(Element) and (TableDepth=0) and (PreDepth=0) then Flush;
        PendingAnchor := Trim(PendingAnchor+' '+URL);
      end;
    end;
    if Element='table' then
    begin
      if Closing then
      begin
        Buffer := Buffer+'</table>'; Dec(TableDepth);
        if TableDepth=0 then begin Flush; BlockTag := ContainerTag; BlockClass := '' end;
      end
      else
      begin
        Flush; BlockTag := 'table'; BlockClass := Cls; Inc(TableDepth);
        if TableDepth=1 then
        begin
          TableCtx := 'table'+DotClasses(Cls);
          Buffer := '<table'+TableAttrs+'>';
        end
        else Buffer := '<table>';
      end;
      Continue;
    end;
    { a table's caption is a line of its own above the table }
    if Element='caption' then
    begin
      if Closing then
      begin
        CaptionDepth := Max(0,CaptionDepth-1);
        if Trim(HTMLPlainText(CaptionText))<>'' then
        begin
          B := TInkPageBlock.Create;
          B.Tag := 'caption'; B.Source := '<center>'+Trim(CaptionText);
          B.Nest := Nest; B.FoldGroup := CurFold;
          FBlocks.Add(B);
        end;
        CaptionText := '';
      end
      else Inc(CaptionDepth);
      Continue;
    end;
    if CaptionDepth>0 then
    begin
      { markup inside a caption decorates the caption's own line }
      CaptionText := CaptionText+InlineTag;
      Continue;
    end;
    if TableDepth>0 then
    begin
      if (Element='tr') or (Element='td') or (Element='th') then
      begin
        if CellsAsBlocks and (TableDepth=1) then
        begin
          { every cell a row of its own }
          if Element='tr' then
          else if Closing then Buffer := Buffer+'</'+Element+'></tr>'
          else Buffer := Buffer+'<tr><'+Element+CellStyleAttrs(Element,Cls,TableCtx)+'>'+CellAlign;
        end
        else if Closing then Buffer := Buffer+'</'+Element+'>'
        else if Element='tr' then Buffer := Buffer+'<tr>'
        else Buffer := Buffer+'<'+Element+CellStyleAttrs(Element,Cls,TableCtx)+'>'+CellAlign;
        if (Element<>'tr') then
        begin
          if Closing then ItemCtx := ''
          else ItemCtx := TableCtx+' '+Element+DotClasses(Cls);
        end;
      end
      else if (Element='p') and Closing then Buffer := Buffer+'<br>'
      else if Element='img' then Buffer := Buffer+HTMLEscape(Attribute(Raw,'alt'))
      else Buffer := Buffer+InlineTag;
      Continue;
    end;
    if Element='pre' then
    begin
      Flush;
      if Closing then begin PreDepth := Max(0,PreDepth-1); BlockTag := ContainerTag; BlockClass := '' end
      else
      begin
        Inc(PreDepth); BlockTag := 'pre'; BlockClass := Cls;
        CodeRaw := ''; CodeMarked := False;
        CodeLang := InkCodeLanguage(Cls);
        { a line break straight after <pre> is not part of the code }
        if (P<=Length(S)) and (S[P]=#13) then Inc(P);
        if (P<=Length(S)) and (S[P]=#10) then Inc(P);
      end;
      Continue;
    end;
    if (Element='code') and not Closing and (PreDepth>0) and (Trim(Buffer)='') then
    begin
      { <pre><code> - the newline GitHub-style HTML puts after <code> is
        not code either }
      if CodeLang='' then CodeLang := InkCodeLanguage(Cls);
      if (P<=Length(S)) and (S[P]=#10) then Inc(P);
      Continue;
    end;
    if PreDepth>0 then
    begin
      Piece := InlineTag;
      { a page that colored its own code keeps its colors: ours would be
        drawn over the top of them }
      if Piece<>'' then CodeMarked := True;
      Buffer := Buffer+Piece;
      Continue;
    end;
    if (Element='ul') or (Element='ol') or (Element='menu') then
    begin
      Flush;
      if Closing then CloseContainer(['o','u'])
      else
      begin
        { the style from the tag's type, then the stylesheet }
        Kind := Attribute(Raw,'type');
        if Kind='' then Kind := FStyles.Value(Element,Cls,'list-style-type',
          FStyles.Value(Element,Cls,'list-style',''));
        if Element='ol' then OpenContainer('o',Kind,StrToIntDef(Attribute(Raw,'start'),1))
        else OpenContainer('u',Kind,0);
      end;
      BlockTag := ContainerTag; BlockClass := '';
      Continue;
    end;
    if Element='blockquote' then
    begin
      Flush;
      if Closing then CloseContainer(['q']) else OpenContainer('q','',0);
      BlockTag := ContainerTag; BlockClass := Cls;
      Continue;
    end;
    if (Element='dd') or (Element='dl') then
    begin
      Flush;
      if Element='dd' then
      begin
        if Closing then CloseContainer(['d']) else OpenContainer('d','',0);
      end;
      BlockTag := ContainerTag; BlockClass := '';
      Continue;
    end;
    if Element='hr' then
    begin
      Flush; B := TInkPageBlock.Create; B.Tag := 'hr'; B.CSSClass := Cls; B.Nest := Nest;
      B.Anchor := PendingAnchor; PendingAnchor := '';
      FBlocks.Add(B); Continue;
    end;
    if Element='input' then
    begin
      if LowerCase(Attribute(Raw,'type'))='checkbox' then
      begin
        if HasAttribute(Raw,'checked') then Box := '☑' else Box := '☐';
        { a task list's box takes the bullet's place }
        if (PendingMarker<>'') and (Trim(Buffer)='') then PendingMarker := Box
        else Buffer := Buffer+Box+' ';
      end;
      Continue;
    end;
    if Element='img' then
    begin
      Flush; B := TInkPageBlock.Create; B.Tag := 'img'; B.Source := Attribute(Raw,'alt');
      B.Nest := Nest;
      B.ImageSrc := ResolveURL(Attribute(Raw,'src'));
      B.LinkHref := OpenHref; B.LinkTarget := OpenTarget;
      B.Anchor := PendingAnchor; PendingAnchor := ''; ImageData := TMemoryStream.Create;
      try
        try
          if ReadResource(ResolveURL(Attribute(Raw,'src')),ImageData) then
          begin
            B.Picture.LoadFromStream(ImageData);
            if B.Picture.Graphic is TGIFImage then
            begin
              B.Animation := TInkGIF.Create(ImageData);
              B.Picture.Assign(B.Animation.Bitmap);
            end;
          end;
        except on E: Exception do B.Picture.Clear end;
      finally ImageData.Free end;
      if B.Picture.Graphic=nil then
      begin
        { a picture that did not load is its alt text - still a link }
        B.Source := '[Image: '+HTMLEscape(B.Source)+']';
        if B.LinkHref<>'' then
        begin
          B.Source := '<a href="'+B.LinkHref+'">'+B.Source+'</a>';
          SetLength(B.LinkTargets,1); B.LinkTargets[0] := B.LinkTarget;
          B.LinkHref := '';
        end;
      end;
      FBlocks.Add(B);
      { the words after the picture are still inside the link }
      if OpenHref<>'' then
      begin
        Buffer := '<a href="'+OpenHref+'">';
        Targets.Add(OpenTarget);
      end;
      Continue;
    end;
    if Element='center' then
    begin
      Flush;
      if Closing then CenterDepth := Max(0,CenterDepth-1) else Inc(CenterDepth);
      BlockTag := ContainerTag; BlockClass := ''; PendingStyle := ''; PendingAlign := '';
      Continue;
    end;
    { <details>: everything in it belongs to a fold that its <summary>
      opens and shuts }
    if Element='details' then
    begin
      Flush;
      if Closing then
      begin
        if Length(Folds)>0 then
        begin
          { a fold with no summary has nothing to open it: leave it open }
          if not FoldSeen[High(Folds)] then FFoldOpen[Folds[High(Folds)]] := True;
          SetLength(Folds,Length(Folds)-1); SetLength(FoldSeen,Length(Folds));
        end;
        if Length(Folds)>0 then CurFold := Folds[High(Folds)] else CurFold := -1;
      end
      else
      begin
        CurFold := AddFold(CurFold,HasAttribute(Raw,'open'));
        SetLength(Folds,Length(Folds)+1); Folds[High(Folds)] := CurFold;
        SetLength(FoldSeen,Length(Folds)); FoldSeen[High(FoldSeen)] := False;
      end;
      BlockTag := ContainerTag; BlockClass := ''; PendingStyle := ''; PendingAlign := '';
      Continue;
    end;
    if Element='summary' then
    begin
      Flush;
      if Closing then begin BlockTag := ContainerTag; BlockClass := ''; PendingHead := -1 end
      else
      begin
        BlockTag := 'summary'; BlockClass := Cls;
        PendingStyle := Attribute(Raw,'style'); PendingAlign := '';
        { the first summary is the one that works the fold, as in a browser }
        if (Length(Folds)>0) and not FoldSeen[High(FoldSeen)] then
        begin
          PendingHead := CurFold; FoldSeen[High(FoldSeen)] := True;
        end;
      end;
      Continue;
    end;
    if (Element='p') or (Element='div') or (Element='header') or (Element='footer') or
      (Element='nav') or (Element='figure') or (Element='figcaption') or (Element='li') or
      (Element='section') or (Element='article') or (Element='main') or (Element='aside') or
      (Element='address') or (Element='dt') or
      IsHeadingTag(Element) then
    begin
      Flush;
      if Closing then
      begin
        BlockTag := ContainerTag; BlockClass := '';
        PendingStyle := ''; PendingAlign := '';
      end
      else
      begin
        BlockTag := Element; BlockClass := Cls;
        PendingStyle := Attribute(Raw,'style'); PendingAlign := Attribute(Raw,'align');
        if Element='li' then
        begin
          Level := High(Containers);
          if (Level>=0) and (Containers[Level].Kind in ['o','u']) then
          begin
            { how many unordered lists deep, for the bullet's shape }
            Depth := 0;
            for I := 0 to Level-1 do if Containers[I].Kind='u' then Inc(Depth);
            PendingMarker := ListMarker(Containers[Level].Style,
              Containers[Level].Kind='o',Containers[Level].Counter,Depth);
            Inc(Containers[Level].Counter);
          end
          else PendingMarker := '•';
        end;
      end;
      Continue;
    end;
    Buffer := Buffer+InlineTag;
  end;
  if FlexDepth>0 then
  begin
    if ItemDepth>0 then EndItem;
    EndFlex;
  end;
  Flush;
  finally Targets.Free; Titles.Free; StyleStack.Free; FlexItems.Free end;
  if PendingAnchor<>'' then
  begin
    { ids at the very end still lead somewhere: the end }
    B := TInkPageBlock.Create; B.Tag := 'p'; B.Anchor := PendingAnchor;
    FBlocks.Add(B);
  end;
  { a Markdown document has no <title>: its first heading names it }
  if FTitle='' then
    for I := 0 to FBlocks.Count-1 do
      if IsHeadingTag(TInkPageBlock(FBlocks[I]).Tag) and
        (TInkPageBlock(FBlocks[I]).Source<>'') then
      begin
        FTitle := Trim(HTMLPlainText(TInkPageBlock(FBlocks[I]).Source));
        Break;
      end;
  FScroll.Position := 0; InvalidateLayout(0);
end;
function TInkCustomPage.Options: THTMLOptions;
var Link: TColor;
begin
  Result := DefaultHTMLOptions;
  { without a color from the page, a link is a blue that reads on its
    background: dark blue on a light page, light blue on a dark one }
  if HTMLContrastColor(FStyles.Color('body','','background',
    FStyles.Color('body','','background-color',Color)))=clWhite then
    Link := RGBToColor($58,$A6,$FF)
  else
    Link := RGBToColor($09,$69,$DA);
  Result.LinkColor := FStyles.Color('a','','color',Link);
  Result.LinkUnderline := True;
end;
procedure TInkCustomPage.BlockFont(ACanvas: TCanvas; B: TInkPageBlock);
begin
  ACanvas.Font.Assign(Font); ACanvas.Font.Size := B.PointSize; ACanvas.Font.Color := B.TextColor;
  if B.Bold then ACanvas.Font.Style := ACanvas.Font.Style+[fsBold];
  if B.FaceName<>'' then ACanvas.Font.Name := B.FaceName;
end;
procedure TInkCustomPage.StyleScrollBar;
var Track,Thumb,TextColor,C1,C2: TColor; Colors,SizeValue: string;
  Tokens: TStringList; P,Q,Depth,NewWidth: Integer;
  { #rgb, #rrggbb, a color name, currentcolor, or rgb()/rgba() with the
    three numbers separated by commas or spaces (alpha is ignored - the
    control has nothing behind it to show through) }
  function ParseColor(const S: string): TColor;
  var V, Inner: string; Parts: TStringList; R,G,B: Integer;
  begin
    V := Trim(S);
    if LowerCase(V)='currentcolor' then Exit(TextColor);
    if (LowerCase(Copy(V,1,4))='rgb(') or (LowerCase(Copy(V,1,5))='rgba(') then
    begin
      Result := clNone;
      if V[Length(V)]<>')' then Exit;
      Inner := Copy(V,Pos('(',V)+1,Length(V)-Pos('(',V)-1);
      Inner := StringReplace(Inner,',',' ',[rfReplaceAll]);
      Inner := StringReplace(Inner,'/',' ',[rfReplaceAll]);
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
        Parts.DelimitedText := Inner;
        if Parts.Count<3 then Exit;
        R := StrToIntDef(Parts[0],-1); G := StrToIntDef(Parts[1],-1);
        B := StrToIntDef(Parts[2],-1);
        if (R<0) or (G<0) or (B<0) or (R>255) or (G>255) or (B>255) then Exit;
        Result := RGBToColor(R,G,B);
      finally Parts.Free end;
      Exit;
    end;
    if (Length(V)=4) and (V[1]='#') then
      V := '#'+V[2]+V[2]+V[3]+V[3]+V[4]+V[4];
    Result := HTMLStringToColor(V,clNone);
  end;
begin
  Track := ColorToRGB(FStyles.Color('body','','background',Color));
  TextColor := ColorToRGB(FStyles.Color('body','','color',Font.Color));
  Thumb := RGBToColor((Red(Track)+Red(TextColor)) div 2,
    (Green(Track)+Green(TextColor)) div 2,(Blue(Track)+Blue(TextColor)) div 2);
  { Root declarations take priority. Body is a native-viewer convenience
    fallback, not browser viewport propagation. }
  Colors := FStyles.Value('html','','scrollbar-color',
    FStyles.Value('body','','scrollbar-color','auto'));
  Tokens := TStringList.Create;
  try
    P := 1;
    while P<=Length(Colors) do
    begin
      while (P<=Length(Colors)) and (Colors[P] in [' ',#9,#10,#13]) do Inc(P);
      Q := P; Depth := 0;
      while P<=Length(Colors) do
      begin
        if (Depth=0) and (Colors[P] in [' ',#9,#10,#13]) then Break;
        if Colors[P]='(' then Inc(Depth) else if Colors[P]=')' then Dec(Depth);
        Inc(P);
      end;
      if P>Q then Tokens.Add(Copy(Colors,Q,P-Q));
    end;
    if Tokens.Count=2 then
    begin
      C1 := ParseColor(Tokens[0]); C2 := ParseColor(Tokens[1]);
      if (C1<>clNone) and (C2<>clNone) then begin Thumb := C1; Track := C2 end;
    end;
  finally Tokens.Free end;
  FScroll.SetColors(Thumb,Track);
  SizeValue := LowerCase(FStyles.Value('html','','scrollbar-width',
    FStyles.Value('body','','scrollbar-width','auto')));
  NewWidth := Scale96ToFont(18);
  if SizeValue='thin' then NewWidth := Scale96ToFont(10)
  else if SizeValue='none' then NewWidth := 0;
  FScroll.Visible := NewWidth>0;
  FScroll.Width := NewWidth;
end;
procedure TInkCustomPage.LayoutColumn(out ALeft, AWidth: Integer);
var MaxWidth: Integer;
begin
  if FImageFit=iifWindow then
  begin
    { a window for pictures uses all of itself }
    ALeft := 8;
    AWidth := Max(40,ClientWidth-FScroll.Width-16);
    Exit;
  end;
  MaxWidth := FStyles.Pixels('div','wrap','max-width',820);
  AWidth := Max(40,Min(ClientWidth-FScroll.Width-40,MaxWidth));
  ALeft := Max(20,(ClientWidth-FScroll.Width-AWidth) div 2);
end;
function TInkCustomPage.LayoutTop: Integer;
begin
  if FImageFit=iifWindow then Result := 8 else Result := 24;
end;
procedure TInkCustomPage.StyleBlock(B: TInkPageBlock);
var J,X,K: Integer; BorderSpec,V: string; Base: Integer; C: TColor;
  function Defaulted(const Prop: string; Fallback: Integer): Integer;
  begin
    Result := Max(0,FStyles.Pixels(B.Tag,B.CSSClass,Prop,Fallback));
  end;
begin
  Base := FLayoutBase;
  X := 0; SetLength(B.Bars,0);
  for J := 1 to Length(B.Nest) do
    if B.Nest[J]='q' then
    begin
      SetLength(B.Bars,Length(B.Bars)+1); B.Bars[High(B.Bars)] := X; Inc(X,FQuoteWidth);
    end
    else Inc(X,FListWidth);
  B.Indent := X;
  B.PointSize := Base;
  if B.Tag='h1' then B.PointSize := Round(Base*1.9)
  else if B.Tag='h2' then B.PointSize := Round(Base*1.36)
  else if B.Tag='h3' then B.PointSize := Round(Base*1.15)
  else if (B.Tag='h5') or (B.Tag='h6') then B.PointSize := Max(1,Round(Base*0.9));
  B.PointSize := Max(1,FStyles.Pixels(B.Tag,B.CSSClass,'font-size',B.PointSize*4 div 3)*3 div 4);
  { a table's caption is a smaller line above it }
  if B.Tag='caption' then
    B.PointSize := Max(1,FStyles.Pixels('caption',B.CSSClass,'font-size',
      Round(Base*0.92)*4 div 3)*3 div 4);
  B.Bold := IsHeadingTag(B.Tag) or (B.Tag='dt') or (B.Tag='summary');
  { a <summary> wears the triangle that says which way it goes }
  if B.FoldHead>=0 then
    if (B.FoldHead<Length(FFoldOpen)) and FFoldOpen[B.FoldHead] then B.Marker := '▾'
    else B.Marker := '▸';
  if B.Pre then B.FaceName := InkMonoFace else B.FaceName := '';
  B.NoWrap := B.Pre;
  if Length(B.Bars)>0 then
    B.TextColor := FStyles.Color(B.Tag,B.CSSClass,'color',FQuoteText)
  else
    B.TextColor := FStyles.Color(B.Tag,B.CSSClass,'color',FBodyText);
  if B.Pre then B.Padding := Defaulted('padding',10)
  else if B.Tag='table' then B.Padding := Defaulted('padding',0)
  else B.Padding := Defaulted('padding',6);
  B.GapBefore := Defaulted('margin-top',0);
  if B.Tag='li' then B.GapAfter := Defaulted('margin-bottom',2)
  else B.GapAfter := Defaulted('margin-bottom',12);
  B.BorderColor := clNone;
  BorderSpec := FStyles.Value(B.Tag,B.CSSClass,'border','');
  K := Pos('var(',BorderSpec);
  if K>0 then BorderSpec := Copy(BorderSpec,K,MaxInt)
  else begin K := LastDelimiter(' ',BorderSpec); if K>0 then Delete(BorderSpec,1,K) end;
  if BorderSpec<>'' then
    B.BorderColor := HTMLStringToColor(FStyles.Resolve(BorderSpec),clNone);
  B.BackColor := FStyles.Color(B.Tag,B.CSSClass,'background',
    FStyles.Color(B.Tag,B.CSSClass,'background-color',clNone));
  if B.Pre and (B.BackColor=clNone) then B.BackColor := FCodeBack;
  B.BarColor := FBarDefault;
  if B.StyleAttr<>'' then
  begin
    { what the element's own style attribute says wins: it is the page's
      last word on that one block }
    V := StyleValue(B.StyleAttr,'color');
    if V<>'' then
    begin
      C := CSSColor(FStyles.Resolve(V),clNone);
      if C<>clNone then B.TextColor := C;
    end;
    V := StyleValue(B.StyleAttr,'background-color');
    if V='' then V := StyleValue(B.StyleAttr,'background');
    if V<>'' then B.BackColor := CSSColor(FStyles.Resolve(V),B.BackColor);
    K := CSSPixels(StyleValue(B.StyleAttr,'font-size'),-1);
    if K>0 then B.PointSize := Max(1,K*3 div 4);
    V := LowerCase(StyleValue(B.StyleAttr,'font-weight'));
    if (V='bold') or (V='bolder') or (StrToIntDef(V,0)>=600) then B.Bold := True
    else if (V='normal') or (V='400') then B.Bold := False;
    K := CSSPixels(StyleValue(B.StyleAttr,'margin-top'),-1);
    if K>=0 then B.GapBefore := K;
    K := CSSPixels(StyleValue(B.StyleAttr,'margin-bottom'),-1);
    if K>=0 then B.GapAfter := K;
    K := CSSPixels(StyleValue(B.StyleAttr,'padding'),-1);
    if K>=0 then B.Padding := K;
  end;
  if B.Tag='hr' then
    { a rule: its color from color, border-color or background, in that
      order }
    B.BarColor := FStyles.Color('hr',B.CSSClass,'color',
      FStyles.Color('hr',B.CSSClass,'border-color',
      FStyles.Color('hr',B.CSSClass,'background',MixColor(FBodyText,FPageBack,0.7))));
end;
procedure TInkCustomPage.Layout;
var I,Y,W,BlockLeft,ImageW,ImageH,ImageX,TextW,Thick,Start,KeepY,Cols: Integer;
  B,Prev: TInkPageBlock; Sz: TSize; O: THTMLOptions;
begin
  if not FLayoutDirty then Exit;
  { a width that crosses one of the page's @media queries reads it again }
  if (ClientWidth>0) and (FStyles.MediaState(ClientWidth)<>FMediaState) then
  begin
    KeepY := FScroll.Position;
    Parse;
    FScroll.Position := KeepY;
  end;
  FLayoutDirty := False;
  StyleScrollBar;
  LayoutColumn(BlockLeft,W);
  { only the blocks from FLayoutFrom on, unless the column changed }
  Start := FLayoutFrom;
  if (W<>FColumnWidth) or (BlockLeft<>FColumnLeft) or (FLayoutWidth<>ClientWidth) then Start := 0;
  if Start>=FBlocks.Count then Start := FBlocks.Count;
  FLayoutFrom := MaxInt;
  FColumnLeft := BlockLeft; FColumnWidth := W; FLayoutWidth := ClientWidth;
  if Start=0 then Y := LayoutTop
  else
  begin
    Prev := TInkPageBlock(FBlocks[Start-1]);
    Y := Prev.Bounds.Bottom+Prev.GapAfter;
  end;
  O := Options;
  FLayoutBase := Font.Size;
  if FLayoutBase<=0 then FLayoutBase := Screen.SystemFont.Size;
  if FLayoutBase<=0 then FLayoutBase := 11;
  { a list's indent is room for its markers; a quote's, room for its bar }
  Canvas.Font.Assign(Font); Canvas.Font.Size := FLayoutBase;
  FListWidth := Max(Scale96ToFont(24),Canvas.TextWidth('00. '));
  FQuoteWidth := Scale96ToFont(18);
  FBodyText := FStyles.Color('body','','color',Font.Color);
  FPageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  FQuoteText := FStyles.Color('blockquote','','color',MixColor(FBodyText,FPageBack,0.3));
  FBarDefault := FStyles.Color('blockquote','','border-color',MixColor(FBodyText,FPageBack,0.6));
  FCodeBack := FStyles.Color('code','','background',
    FStyles.Color('code','','background-color',HTMLShadeColor(FPageBack,7)));
  for I := Start to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    B.RunsReady := False;
    StyleBlock(B);
    { folded away inside a shut <details>: no room, nothing drawn }
    if BlockHidden(B) then
    begin
      B.Bounds := Rect(BlockLeft,Y,BlockLeft,Y); B.TextBounds := B.Bounds;
      B.ImageRect := B.Bounds; B.Wrapped := ''; B.MarkerWidth := 0;
      Continue;
    end;
    Inc(Y,B.GapBefore);
    BlockFont(Canvas,B);
    B.MarkerWidth := 0;
    if B.Tag='hr' then
    begin
      Thick := Max(1,Scale96ToFont(2));
      Sz.cx := W-B.Indent; Sz.cy := Thick;
      B.Wrapped := '';
    end
    else if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) and (B.Picture.Height>0) then
    begin
      TextW := W-B.Indent;
      case FImageFit of
        iifWidth: ImageW := TextW;
        iifWindow:
          ImageW := Min(TextW,Round(B.Picture.Width*
            (Max(1,ClientHeight-2*LayoutTop-B.GapBefore-B.GapAfter-2*B.Padding)/B.Picture.Height)));
      else
        ImageW := Min(TextW,B.Picture.Width);
      end;
      ImageW := Max(1,ImageW);
      ImageH := Max(1,Round(B.Picture.Height*ImageW/B.Picture.Width));
      Sz.cx := ImageW; Sz.cy := ImageH;
      B.Wrapped := '';
    end
    else
    begin
      if B.Marker<>'' then
        B.MarkerWidth := Canvas.TextWidth(B.Marker+' ');
      { a summary's triangle sits in front of its words, not out in the margin }
      if B.FoldHead>=0 then Inc(B.Indent,B.MarkerWidth);
      TextW := Max(20,W-B.Indent-B.Padding*2-B.MarginLeft-B.MarginRight);
      if B.Flex then
      begin
        { as many items to a row as fit at their width, with the gaps }
        Cols := Length(B.FlexCells);
        if B.FlexWrap then
          Cols := Max(1,Min(Cols,(TextW-B.FlexGap) div Max(1,B.FlexBasis+B.FlexGap)));
        if B.FlexMaxCols>0 then Cols := Min(Cols,B.FlexMaxCols);
        if (Cols<>B.FlexCols) or (B.Source='') then
        begin
          B.FlexCols := Cols;
          B.Source := FlexTable(B,Cols);
        end;
      end;
      if B.NoWrap then B.Wrapped := B.Source
      else B.Wrapped := HTMLWordWrap(Canvas,B.Source,TextW,O.SuperSubScriptRatio,O.Scale);
      Sz := HTMLTextExtentOpt(Canvas,Rect(0,0,TextW,0),[],B.Wrapped,O);
    end;
    B.Bounds := Rect(BlockLeft+B.Indent+B.MarginLeft,Y,BlockLeft+W-B.MarginRight,Y+Sz.cy+B.Padding*2);
    B.TextBounds := Rect(B.Bounds.Left+B.Padding,B.Bounds.Top+B.Padding,
      B.Bounds.Right-B.Padding,B.Bounds.Bottom-B.Padding);
    { a picture sits at the block's top; one fitted to the window, centered }
    ImageX := B.Bounds.Left;
    if FImageFit=iifWindow then ImageX := B.Bounds.Left+Max(0,(W-B.Indent-Sz.cx) div 2);
    B.ImageRect := Rect(ImageX,Y,ImageX+Sz.cx,Y+Sz.cy);
    Inc(Y,Sz.cy+B.Padding*2+B.GapAfter);
  end;
  if (Start>0) and (Start>=FBlocks.Count) and (FBlocks.Count>0) then
  begin
    Prev := TInkPageBlock(FBlocks[FBlocks.Count-1]);
    Y := Prev.Bounds.Bottom+Prev.GapAfter;
  end;
  if FBlocks.Count=0 then Y := LayoutTop;
  FContentHeight := Y;
  FScroll.SetParams(Min(FScroll.Position,Max(0,Y-ClientHeight)),0,Max(ClientHeight,Y),Max(1,ClientHeight));
end;
procedure TInkCustomPage.Paint;
begin RenderTo(Canvas) end;
procedure TInkCustomPage.RenderTo(ACanvas: TCanvas);
var I,J,BarTop,BarBottom,Saved: Integer; B,Next: TInkPageBlock; R,TR: TRect; O: THTMLOptions;
  SelFrom, SelTo: TInkPagePosition; Selected: Boolean;
begin
  Layout;
  Selected := HasSelection;
  SelFrom := SelectionStart; SelTo := SelectionEnd;
  ACanvas.Brush.Color := FStyles.Color('body','','background',
    FStyles.Color('body','','background-color',Color));
  ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(ClientRect); O := Options;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
    if (R.Bottom+B.GapAfter<0) or (R.Top-B.GapBefore>ClientHeight) then Continue;
    if BlockHidden(B) then Continue;
    { a quote's bar runs on through the gap to the next block in the same
      quote, so a quote of several paragraphs has one bar }
    if Length(B.Bars)>0 then
    begin
      Next := nil;
      if I+1<FBlocks.Count then Next := TInkPageBlock(FBlocks[I+1]);
      ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := B.BarColor;
      for J := 0 to High(B.Bars) do
      begin
        BarTop := R.Top; BarBottom := R.Bottom;
        if (Next<>nil) and (Length(Next.Bars)>J) then Inc(BarBottom,B.GapAfter+Next.GapBefore);
        ACanvas.FillRect(Rect(FColumnLeft+B.Bars[J]+Scale96ToFont(4),BarTop,
          FColumnLeft+B.Bars[J]+Scale96ToFont(4)+Max(2,Scale96ToFont(3)),BarBottom));
      end;
    end;
    BlockFont(ACanvas,B);
    if B.Tag='hr' then
    begin
      ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := B.BarColor;
      TR := B.TextBounds; OffsetRect(TR,0,-FScroll.Position);
      ACanvas.FillRect(TR);
      Continue;
    end;
    if B.BackColor<>clNone then begin ACanvas.Brush.Color := B.BackColor; ACanvas.Brush.Style := bsSolid; ACanvas.FillRect(R) end;
    ACanvas.Brush.Style := bsClear;
    if B.BorderColor<>clNone then begin ACanvas.Pen.Color := B.BorderColor; ACanvas.Rectangle(R) end;
    if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) then
    begin
      R := B.ImageRect; OffsetRect(R,0,-FScroll.Position);
      ACanvas.StretchDraw(R,B.Picture.Graphic);
      Continue;
    end;
    TR := B.TextBounds; OffsetRect(TR,0,-FScroll.Position);
    if B.Marker<>'' then
      HTMLDrawOpt(ACanvas,Rect(TR.Left-B.MarkerWidth,TR.Top,TR.Left,TR.Bottom),[],
        HTMLEscape(B.Marker),O);
    O := BlockOptions(I);
    if B.NoWrap then
    begin
      { a long line of code is cut off at the block's edge, not wrapped }
      Saved := SaveDC(ACanvas.Handle);
      try
        IntersectClipRect(ACanvas.Handle,R.Left,R.Top,R.Right,R.Bottom);
        HTMLDrawOpt(ACanvas,TR,[],B.Wrapped,O);
        if Selected and (I>=SelFrom.Block) and (I<=SelTo.Block) then
          PaintSelection(ACanvas,I,B,SelFrom,SelTo);
      finally RestoreDC(ACanvas.Handle,Saved) end;
    end
    else
    begin
      HTMLDrawOpt(ACanvas,TR,[],B.Wrapped,O);
      if Selected and (I>=SelFrom.Block) and (I<=SelTo.Block) then
        PaintSelection(ACanvas,I,B,SelFrom,SelTo);
    end;
  end;
  if FScroll.Visible then
    FScroll.RenderTo(ACanvas,Rect(ClientWidth-FScroll.Width,0,ClientWidth,ClientHeight));
  if FindBarVisible then PaintFindBar(ACanvas);
end;
procedure TInkCustomPage.Resize;
begin inherited; InvalidateLayout(0); PlaceFindBar end;
procedure TInkCustomPage.FontChanged(Sender: TObject);
begin inherited; InvalidateLayout(0) end;
function TInkCustomPage.HitTestLink(X,Y: Integer; out ABlock: Integer; out AHit: THTMLHitInfo): Boolean;
var I: Integer; B: TInkPageBlock; R: TRect;
begin
  Result := False; ABlock := -1;
  AHit.OnLink := False; AHit.LinkName := ''; AHit.LinkText := ''; AHit.LinkIndex := 0;
  Layout;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
    if not PtInRect(R,Point(X,Y)) then Continue;
    { a picture in a link is the link, all of it }
    if (B.LinkHref<>'') and (B.Picture.Graphic<>nil) then
    begin
      R := B.ImageRect; OffsetRect(R,0,-FScroll.Position);
      if not PtInRect(R,Point(X,Y)) then Continue;
      AHit.OnLink := True; AHit.LinkName := B.LinkHref;
      AHit.LinkText := B.Source; AHit.LinkIndex := 1;
      ABlock := I;
      Exit(True);
    end;
    if B.Wrapped='' then Continue;
    BlockFont(Canvas,B);
    R := B.TextBounds; OffsetRect(R,0,-FScroll.Position);
    AHit := HTMLHitTest(Canvas,R,B.Wrapped,Options,X,Y);
    if AHit.OnLink then
    begin
      ABlock := I;
      Exit(True);
    end;
  end;
end;
function TInkCustomPage.HitLink(X,Y: Integer): string;
var B: Integer; Hit: THTMLHitInfo;
begin
  Result := '';
  if HitTestLink(X,Y,B,Hit) then Result := ResolveURL(LinkHref(Hit));
end;
function TInkCustomPage.GetScrollY: Integer;
begin
  Result := FScroll.Position;
end;

procedure TInkCustomPage.CreateWnd;
begin
  inherited CreateWnd;
  InkHookTouch(Self,@Touch);
end;

const
  { A press that wanders less than this is still a click.  Wider than a
    mouse needs, because a fingertip rolls a little as it taps, and a tap on
    a link that scrolled the page by three pixels instead would read as the
    link being dead. }
  SLOP = 8;
  { how far back a flick's speed is measured from the moment it lets go }
  FLICK_WINDOW = 100;
  { pixels a second: slower than this is a drag that stopped, not a flick }
  FLICK_MIN = 150;
  FLICK_MAX = 8000;
  { what is left of the speed after a second of coasting }
  FLICK_FRICTION = 0.05;

procedure TInkCustomPage.GrabBegin(X,Y: Integer; Finger: Boolean; Time: QWord);
begin
  StopFlick;
  FGrab := True; FDragged := False; FGrabFinger := Finger;
  FGrabY := Y; FGrabAt := FScroll.Position;
  FSampleCount := 0;
  GrabMove(X,Y,Time);
end;

procedure TInkCustomPage.GrabMove(X,Y: Integer; Time: QWord);
var K: Integer;
begin
  if not FGrab then Exit;
  if FSampleCount=Length(FSampleY) then
  begin
    for K := 1 to High(FSampleY) do
    begin FSampleY[K-1] := FSampleY[K]; FSampleTime[K-1] := FSampleTime[K] end;
    Dec(FSampleCount);
  end;
  FSampleY[FSampleCount] := Y; FSampleTime[FSampleCount] := Time; Inc(FSampleCount);
  if not FDragScroll then Exit;
  if FDragged or (Abs(Y-FGrabY)>SLOP) then
  begin
    { the page follows the finger: drag down and the words come down }
    FDragged := True;
    FScroll.Position := EnsureRange(FGrabAt-(Y-FGrabY),0,Max(0,FContentHeight-ClientHeight));
  end;
end;

procedure TInkCustomPage.GrabEnd(X,Y: Integer; Time: QWord);
var WasDrag: Boolean; K: Integer; DT: Int64;
begin
  if not FGrab then Exit;
  GrabMove(X,Y,Time);
  WasDrag := FDragged; FGrab := False; FDragged := False;
  if not WasDrag then begin ClickAt(X,Y); Exit end;
  { a drag that happened to end over a link was a scroll, not a click; a
    quick one with a finger carries on }
  if not (FGrabFinger and FFlickScroll) then Exit;
  K := FSampleCount-1;
  while (K>0) and (Time-FSampleTime[K-1]<=FLICK_WINDOW) do Dec(K);
  DT := Int64(Time)-Int64(FSampleTime[K]);
  if (DT<=0) or (K>=FSampleCount-1) then Exit;
  FVelocity := (FSampleY[K]-Y)*1000/DT;
  if Abs(FVelocity)<FLICK_MIN then begin FVelocity := 0; Exit end;
  FVelocity := EnsureRange(FVelocity,-FLICK_MAX,FLICK_MAX);
  FFlickLast := GetTickCount64;
  FFlickTimer.Enabled := True;
end;

procedure TInkCustomPage.ClickAt(X,Y: Integer);
var B: Integer; Hit: THTMLHitInfo; Info: TInkLinkInfo; Blk: TInkPageBlock;
begin
  if CanFocus then SetFocus;
  if not HitTestLink(X,Y,B,Hit) then
  begin
    { not a link: a click on a <summary> opens or shuts its <details> }
    B := BlockAt(X,Y);
    if (B>=0) and (TInkPageBlock(FBlocks[B]).FoldHead>=0) then ToggleFold(B);
    Exit;
  end;
  Blk := TInkPageBlock(FBlocks[B]);
  Info.Href := LinkHref(Hit);
  Info.URL := ResolveURL(Info.Href);
  Info.Block := B;
  Info.Target := ''; Info.Image := '';
  if Blk.LinkHref<>'' then
  begin
    Info.Target := Blk.LinkTarget;
    Info.Image := Blk.ImageSrc;
  end
  else if (Hit.LinkIndex>=1) and (Hit.LinkIndex<=Length(Blk.LinkTargets)) then
    Info.Target := Blk.LinkTargets[Hit.LinkIndex-1];
  LinkClicked(Info);
end;

procedure TInkCustomPage.StopFlick;
begin
  FVelocity := 0;
  FFlickTimer.Enabled := False;
end;

function TInkCustomPage.GetFlicking: Boolean;
begin
  Result := FVelocity<>0;
end;

procedure TInkCustomPage.FlickStep(Milliseconds: Integer);
var Last, Next: Integer;
begin
  if FVelocity=0 then Exit;
  Last := Max(0,FContentHeight-ClientHeight);
  Next := EnsureRange(FScroll.Position+Round(FVelocity*Milliseconds/1000),0,Last);
  FScroll.Position := Next;
  FVelocity := FVelocity*Power(FLICK_FRICTION,Milliseconds/1000);
  { it stops when it has slowed right down, or reached an end }
  if (Abs(FVelocity)<20) or ((Next=0) and (FVelocity<0)) or ((Next=Last) and (FVelocity>0)) then
    StopFlick;
end;

procedure TInkCustomPage.FlickTimer(Sender: TObject);
var Now_: QWord;
begin
  Now_ := GetTickCount64;
  FlickStep(Min(100,Integer(Now_-FFlickLast)));
  FFlickLast := Now_;
end;

procedure TInkCustomPage.Touch(Phase: TInkTouchPhase; X,Y: Integer);
begin
  TouchAt(Phase,X,Y,GetTickCount64);
end;

procedure TInkCustomPage.TouchAt(Phase: TInkTouchPhase; X,Y: Integer; Time: QWord);
begin
  case Phase of
    itpBegin: GrabBegin(X,Y,True,Time);
    itpMove: if FGrabFinger then GrabMove(X,Y,Time);
    itpEnd:
      if FGrab and FGrabFinger then
      begin
        GrabEnd(X,Y,Time);
        FLastTouchEnd := GetTickCount64;
      end;
    itpCancel:
      if FGrabFinger then
      begin
        FGrab := False; FDragged := False;
        FLastTouchEnd := GetTickCount64;
      end;
  end;
end;

procedure TInkCustomPage.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var P, WordFrom, WordTo: TInkPagePosition; Now_: QWord; Near: Boolean;
begin
  inherited;
  StopFlick;
  if Button<>mbLeft then Exit;
  if FindBarVisible and PtInRect(FindBarRect,Point(X,Y)) then
  begin
    if PtInRect(FindButtonRect(0),Point(X,Y)) then Find(FFindEdit.Text,[ifoBackwards])
    else if PtInRect(FindButtonRect(1),Point(X,Y)) then Find(FFindEdit.Text)
    else if PtInRect(FindButtonRect(2),Point(X,Y)) then HideFindBar;
    Exit;
  end;
  { a platform that sends a copy of a touch as mouse events as well must not
    move the page twice }
  if (FGrab and FGrabFinger) or (GetTickCount64-FLastTouchEnd<500) then Exit;
  if InkMouseIsTouch or (FMouseDrag=imdScroll) then
  begin
    GrabBegin(X,Y,InkMouseIsTouch,GetTickCount64);
    Exit;
  end;
  { the mouse selects, as in a browser: a click places, a drag selects,
    a double click takes a word and a triple click a block; Shift extends }
  if CanFocus then SetFocus;
  P := PositionAt(X,Y);
  FSelecting := True; FSelMoved := False;
  FPressX := X; FPressY := Y; FDragX := X; FDragY := Y;
  { A press soon after another in the same place is its second or third
    click.  GTK sends a double click as a press and then the same press
    again, marked double, at the same moment: that is not one more click. }
  Now_ := GetTickCount64;
  Near := (Abs(X-FLastClickX)<=4) and (Abs(Y-FLastClickY)<=4);
  if not (Near and (Now_-FLastClickTime<25)) then
  begin
    if Near and (Now_-FLastClickTime<=GetDoubleClickTime) and (FClicks<3) then Inc(FClicks)
    else FClicks := 1;
  end;
  FLastClickTime := Now_; FLastClickX := X; FLastClickY := Y;
  if ssTriple in Shift then FClicks := 3
  else if (ssDouble in Shift) and (FClicks<2) then FClicks := 2;
  if FClicks=3 then
  begin
    FSelectUnit := 2; FSelMoved := True;
    FUnitFrom.Block := P.Block; FUnitFrom.Offset := 0;
    FUnitTo.Block := P.Block; FUnitTo.Offset := MaxInt;
    Select(FUnitFrom,FUnitTo);
  end
  else if FClicks=2 then
  begin
    FSelectUnit := 1; FSelMoved := True;
    if not WordAt(P,WordFrom,WordTo) then begin WordFrom := P; WordTo := P end;
    FUnitFrom := WordFrom; FUnitTo := WordTo;
    Select(WordFrom,WordTo);
  end
  else if (ssShift in Shift) and HasSelection then
  begin
    FSelectUnit := 0; FSelMoved := True;
    FSelCaret := P; SelectionChanged;
  end
  else
  begin
    FSelectUnit := 0;
    Select(P,P);
  end;
end;

procedure TInkCustomPage.MouseMove(Shift: TShiftState; X,Y: Integer);
var I,Fold: Integer; B: TInkPageBlock; OnText: Boolean; R: TRect; Tip: string;
  HoverBlock: Integer; HoverHit: THTMLHitInfo;
begin
  inherited;
  if FGrab then
  begin
    if not FGrabFinger or InkMouseIsTouch then GrabMove(X,Y,GetTickCount64);
    if FDragged then Exit;
  end;
  if FSelecting then
  begin
    FDragX := X; FDragY := Y;
    if not FSelMoved and ((Abs(X-FPressX)>3) or (Abs(Y-FPressY)>3)) then FSelMoved := True;
    if FSelMoved then
    begin
      ExtendTo(PositionAt(X,EnsureRange(Y,0,ClientHeight-1)));
      { beyond the top or bottom, the page scrolls on its own }
      FAutoScroll.Enabled := (Y<0) or (Y>=ClientHeight);
      Exit;
    end;
  end;
  HitTestLink(X,Y,HoverBlock,HoverHit);
  if HoverHit.OnLink then FHoverLink := ResolveURL(LinkHref(HoverHit))
  else FHoverLink := '';
  if (HoverBlock<>FHoverBlock) or (HoverHit.LinkIndex<>FHoverLinkIndex) then
  begin
    FHoverBlock := HoverBlock; FHoverLinkIndex := HoverHit.LinkIndex;
    HoverChanged(HoverBlock,HoverHit);
  end;
  { a link's title, or a summary's, is the tooltip - as a browser shows it }
  Tip := '';
  if HoverHit.OnLink and (HoverBlock>=0) then
  begin
    B := TInkPageBlock(FBlocks[HoverBlock]);
    if (HoverHit.LinkIndex>=1) and (HoverHit.LinkIndex<=Length(B.LinkTitles)) then
      Tip := B.LinkTitles[HoverHit.LinkIndex-1];
  end;
  if Tip<>Hint then
  begin
    Hint := Tip; ShowHint := Tip<>'';
    { a tooltip already showing is for the link the pointer has left }
    Application.CancelHint;
  end;
  Fold := BlockAt(X,Y);
  if (Fold>=0) and (TInkPageBlock(FBlocks[Fold]).FoldHead>=0) and (FHoverLink='') then
    Cursor := crHandPoint
  else if FHoverLink<>'' then Cursor := crHandPoint
  else
  begin
    OnText := False;
    for I := 0 to FBlocks.Count-1 do
    begin
      B := TInkPageBlock(FBlocks[I]);
      R := B.TextBounds; OffsetRect(R,0,-FScroll.Position);
      if (B.Wrapped<>'') and PtInRect(R,Point(X,Y)) then begin OnText := True; Break end;
    end;
    if OnText and (FMouseDrag=imdSelect) then Cursor := crIBeam else Cursor := crDefault;
  end;
end;

procedure TInkCustomPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  { the mouse's own back and forward buttons }
  if Button=mbExtra1 then begin Back; Exit end;
  if Button=mbExtra2 then begin Forward; Exit end;
  if Button<>mbLeft then Exit;
  if FSelecting then
  begin
    FSelecting := False;
    FAutoScroll.Enabled := False;
    { a press that did not move is a click: on a link, it is followed }
    if not FSelMoved then ClickAt(X,Y)
    else if HasSelection then
      { X11's other clipboard: what is selected is ready for a middle click }
      Clipboard(ctPrimarySelection).AsText := SelectedText;
    Exit;
  end;
  if FGrab and FGrabFinger and not InkMouseIsTouch then Exit;
  GrabEnd(X,Y,GetTickCount64);
end;

procedure TInkCustomPage.MouseLeave;
var NoHit: THTMLHitInfo;
begin
  inherited MouseLeave;
  if FHoverBlock<0 then Exit;
  FHoverBlock := -1; FHoverLinkIndex := 0; FHoverLink := '';
  NoHit.OnLink := False; NoHit.LinkName := ''; NoHit.LinkText := ''; NoHit.LinkIndex := 0;
  HoverChanged(-1,NoHit);
end;

procedure TInkCustomPage.AutoScrollTimer(Sender: TObject);
var Delta: Integer;
begin
  if not FSelecting then begin FAutoScroll.Enabled := False; Exit end;
  if FDragY<0 then Delta := Max(-60,FDragY) div 2 - 4
  else if FDragY>=ClientHeight then Delta := Min(60,FDragY-ClientHeight) div 2 + 4
  else Exit;
  FScroll.Position := EnsureRange(FScroll.Position+Delta,0,Max(0,FContentHeight-ClientHeight));
  ExtendTo(PositionAt(FDragX,EnsureRange(FDragY,0,ClientHeight-1)));
end;

procedure TInkCustomPage.CollectRun(const AText: string; ALeft, ATop, AWidth, AHeight,
  ALine, APart: Integer; AFont: TFont);
var B: TInkPageBlock;
begin
  B := FRunBlock;
  if B=nil then Exit;
  if B.RunCount=Length(B.Runs) then SetLength(B.Runs,Max(8,B.RunCount*2));
  with B.Runs[B.RunCount] do
  begin
    Text := AText; Left := ALeft; Top := ATop; Width := AWidth; Height := AHeight;
    Line := ALine; Part := APart; LineHeight := AHeight;
    FontName := AFont.Name; FontSize := AFont.Size; FontStyle := AFont.Style;
    FontColor := AFont.Color;
  end;
  Inc(B.RunCount);
end;

procedure TInkCustomPage.PrepareRuns(B: TInkPageBlock);
var O: THTMLOptions; W,H,I,J,K,P,Q,Tallest: Integer; Hit: THTMLHitInfo; Plain: string;
begin
  Layout;
  if B.RunsReady then Exit;
  B.RunsReady := True; B.RunCount := 0; SetLength(B.Runs,0); B.Words := '';
  if B.Wrapped='' then Exit;
  BlockFont(Canvas,B);
  O := Options; O.OnRun := @CollectRun; O.RunPart := 0;
  FRunBlock := B;
  try
    { the same layout the block is drawn with, measured instead of painted }
    HTMLMeasureAndHit(Canvas,B.TextBounds,B.Wrapped,O,-1,-1,W,H,Hit);
  finally FRunBlock := nil end;
  SetLength(B.Runs,B.RunCount);
  { every run on a line is as tall as the line }
  I := 0;
  while I<B.RunCount do
  begin
    J := I; Tallest := 0;
    while (J<B.RunCount) and (B.Runs[J].Line=B.Runs[I].Line) and (B.Runs[J].Part=B.Runs[I].Part) do
    begin Tallest := Max(Tallest,B.Runs[J].Height); Inc(J) end;
    for K := I to J-1 do B.Runs[K].LineHeight := Tallest;
    I := J;
  end;
  { The words are the runs in order, with whatever lay between them in the
    source's own plain text: the space a wrap took away, a line break, the
    tab between two cells. }
  Plain := HTMLPlainText(B.Source);
  P := 1;
  for I := 0 to B.RunCount-1 do
  begin
    Q := Pos(B.Runs[I].Text,Plain,P);
    if Q>0 then
    begin
      B.Words := B.Words+Copy(Plain,P,Q-P);
      P := Q+Length(B.Runs[I].Text);
    end
    else if (I>0) and ((B.Runs[I].Line<>B.Runs[I-1].Line) or (B.Runs[I].Part<>B.Runs[I-1].Part)) then
      B.Words := B.Words+' ';
    B.Runs[I].Start := Length(B.Words);
    B.Words := B.Words+B.Runs[I].Text;
  end;
end;

procedure TInkCustomPage.RunFont(ACanvas: TCanvas; const R: TInkPageRun);
begin
  ACanvas.Font.Name := R.FontName;
  ACanvas.Font.Size := R.FontSize;
  ACanvas.Font.Style := R.FontStyle;
end;

function TInkCustomPage.RunX(const R: TInkPageRun; Offset: Integer): Integer;
var K: Integer;
begin
  K := EnsureRange(Offset-R.Start,0,Length(R.Text));
  if K=0 then Exit(R.Left);
  if K=Length(R.Text) then Exit(R.Left+R.Width);
  RunFont(Canvas,R);
  Result := R.Left+Canvas.TextWidth(Copy(R.Text,1,K));
end;

function TInkCustomPage.BlockAt(X,Y: Integer): Integer;
var I,DocY: Integer; B: TInkPageBlock;
begin
  Layout;
  Result := -1;
  DocY := Y+FScroll.Position;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if (DocY>=B.Bounds.Top) and (DocY<B.Bounds.Bottom) then Exit(I);
  end;
end;

function TInkCustomPage.PositionAt(X,Y: Integer): TInkPagePosition;
var I,K,DocY,Best,BestDY,BestDX,DY,DX,Prev,W,Len: Integer; B: TInkPageBlock; R: TInkPageRun;
begin
  Layout;
  Result.Block := 0; Result.Offset := 0;
  if FBlocks.Count=0 then Exit;
  DocY := Y+FScroll.Position;
  { the block, or the one after the gap the point is in }
  I := 0;
  while (I<FBlocks.Count-1) and
    (DocY>=TInkPageBlock(FBlocks[I]).Bounds.Bottom+TInkPageBlock(FBlocks[I]).GapAfter) do Inc(I);
  B := TInkPageBlock(FBlocks[I]);
  Result.Block := I;
  PrepareRuns(B);
  if B.RunCount=0 then Exit;
  if DocY<B.Bounds.Top then Exit;
  if DocY>=B.Bounds.Bottom+B.GapAfter then begin Result.Offset := Length(B.Words); Exit end;
  { the nearest line, then the nearest run on it }
  Best := 0; BestDY := MaxInt; BestDX := MaxInt;
  for K := 0 to B.RunCount-1 do
  begin
    R := B.Runs[K];
    if DocY<R.Top then DY := R.Top-DocY
    else if DocY>=R.Top+R.LineHeight then DY := DocY-(R.Top+R.LineHeight)+1
    else DY := 0;
    if X<R.Left then DX := R.Left-X
    else if X>R.Left+R.Width then DX := X-(R.Left+R.Width)
    else DX := 0;
    if (DY<BestDY) or ((DY=BestDY) and (DX<BestDX)) then
    begin Best := K; BestDY := DY; BestDX := DX end;
  end;
  R := B.Runs[Best];
  Result.Offset := R.Start;
  if X<=R.Left then Exit;
  if X>=R.Left+R.Width then begin Result.Offset := R.Start+Length(R.Text); Exit end;
  { between the two characters whose middle it is nearest }
  RunFont(Canvas,R);
  K := 1; Prev := 0;
  while K<=Length(R.Text) do
  begin
    Len := Max(1,UTF8CodepointSize(@R.Text[K]));
    W := Canvas.TextWidth(Copy(R.Text,1,K+Len-1));
    if X-R.Left<(Prev+W) div 2 then Break;
    Result.Offset := R.Start+K+Len-1;
    Prev := W; Inc(K,Len);
  end;
end;

function TInkCustomPage.PositionPoint(const APosition: TInkPagePosition): TPoint;
var P: TInkPagePosition; B: TInkPageBlock; K,Found: Integer;
begin
  P := Clamp(APosition);
  Result := Point(0,0);
  if FBlocks.Count=0 then Exit;
  B := TInkPageBlock(FBlocks[P.Block]);
  PrepareRuns(B);
  Result := Point(B.TextBounds.Left,B.TextBounds.Top-FScroll.Position);
  Found := -1;
  for K := 0 to B.RunCount-1 do
  begin
    if B.Runs[K].Start>P.Offset then Break;
    Found := K;
    if P.Offset<B.Runs[K].Start+Length(B.Runs[K].Text) then Break;
  end;
  if Found<0 then Exit;
  Result := Point(RunX(B.Runs[Found],P.Offset),B.Runs[Found].Top-FScroll.Position);
end;

function TInkCustomPage.BlockText(Index: Integer): string;
begin
  PrepareRuns(TInkPageBlock(FBlocks[Index]));
  Result := TInkPageBlock(FBlocks[Index]).Words;
end;

function TInkCustomPage.Clamp(const P: TInkPagePosition): TInkPagePosition;
var B: TInkPageBlock;
begin
  Result := P;
  if FBlocks.Count=0 then begin Result.Block := 0; Result.Offset := 0; Exit end;
  Result.Block := EnsureRange(P.Block,0,FBlocks.Count-1);
  B := TInkPageBlock(FBlocks[Result.Block]);
  PrepareRuns(B);
  Result.Offset := EnsureRange(P.Offset,0,Length(B.Words));
end;

function ComparePositions(const A, B: TInkPagePosition): Integer;
begin
  if A.Block<>B.Block then Result := A.Block-B.Block
  else if A.Offset<B.Offset then Result := -1
  else if A.Offset>B.Offset then Result := 1
  else Result := 0;
end;

function IsWordByte(C: Char): Boolean;
begin
  Result := (C in ['a'..'z','A'..'Z','0'..'9','_']) or (Ord(C)>=$80);
end;

function TInkCustomPage.WordAt(const P: TInkPagePosition; out AFrom, ATo: TInkPagePosition): Boolean;
var Words: string; A,Z: Integer; Kind: Boolean;
begin
  AFrom := Clamp(P); ATo := AFrom;
  Words := TInkPageBlock(FBlocks[AFrom.Block]).Words;
  Result := Words<>'';
  if not Result then Exit;
  A := AFrom.Offset;
  if A>=Length(Words) then A := Length(Words)-1;
  { the character after the place, as a browser takes it; a word, or a run
    of the same kind of not-word }
  Kind := IsWordByte(Words[A+1]);
  if not Kind and (Words[A+1] in [' ',#9]) and (A>0) and IsWordByte(Words[A]) then
  begin Dec(A); Kind := True end;
  Z := A+1;
  while (A>0) and (IsWordByte(Words[A])=Kind) and not (Words[A] in [#10,#13]) do Dec(A);
  while (Z<Length(Words)) and (IsWordByte(Words[Z+1])=Kind) and not (Words[Z+1] in [#10,#13]) do Inc(Z);
  if not Kind then
  begin
    { punctuation on its own is taken one character at a time }
    A := EnsureRange(AFrom.Offset,0,Length(Words)-1);
    Z := A+1;
  end;
  AFrom.Offset := A; ATo.Offset := Z;
end;

procedure TInkCustomPage.ExtendTo(const P: TInkPagePosition);
var WordFrom, WordTo: TInkPagePosition;
begin
  case FSelectUnit of
    1:
      begin
        if not WordAt(P,WordFrom,WordTo) then begin WordFrom := P; WordTo := P end;
        if ComparePositions(WordFrom,FUnitFrom)<0 then
        begin FSelAnchor := FUnitTo; FSelCaret := WordFrom end
        else
        begin FSelAnchor := FUnitFrom; FSelCaret := WordTo end;
      end;
    2:
      if P.Block<FUnitFrom.Block then
      begin
        FSelAnchor := FUnitTo; FSelCaret.Block := P.Block; FSelCaret.Offset := 0;
      end
      else
      begin
        FSelAnchor := FUnitFrom; FSelCaret.Block := P.Block; FSelCaret.Offset := MaxInt;
      end;
  else
    FSelCaret := P;
  end;
  SelectionChanged;
end;

procedure TInkCustomPage.SelectionChanged;
begin
  Invalidate;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TInkCustomPage.Select(const AFrom, ATo: TInkPagePosition);
begin
  FSelAnchor := Clamp(AFrom); FSelCaret := Clamp(ATo);
  SelectionChanged;
end;

procedure TInkCustomPage.SelectAll;
begin
  FSelAnchor.Block := 0; FSelAnchor.Offset := 0;
  FSelCaret.Block := Max(0,FBlocks.Count-1); FSelCaret.Offset := MaxInt;
  SelectionChanged;
end;

procedure TInkCustomPage.DoSelectAll(Sender: TObject);
begin
  SelectAll;
end;

procedure TInkCustomPage.ClearSelection;
begin
  if not HasSelection then Exit;
  FSelAnchor := FSelCaret;
  SelectionChanged;
end;

function TInkCustomPage.HasSelection: Boolean;
begin
  Result := (FBlocks<>nil) and (FBlocks.Count>0) and
    (ComparePositions(FSelAnchor,FSelCaret)<>0);
end;

function TInkCustomPage.GetSelectionStart: TInkPagePosition;
begin
  if ComparePositions(FSelAnchor,FSelCaret)<=0 then Result := FSelAnchor else Result := FSelCaret;
end;

function TInkCustomPage.GetSelectionEnd: TInkPagePosition;
begin
  if ComparePositions(FSelAnchor,FSelCaret)<=0 then Result := FSelCaret else Result := FSelAnchor;
end;

function TInkCustomPage.SelectedText: string;
var I,A,Z: Integer; B: TInkPageBlock; SelFrom,SelTo: TInkPagePosition; Part: string;
begin
  Result := '';
  if not HasSelection then Exit;
  SelFrom := SelectionStart; SelTo := SelectionEnd;
  for I := SelFrom.Block to Min(SelTo.Block,FBlocks.Count-1) do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if I=SelFrom.Block then A := SelFrom.Offset else A := 0;
    if I=SelTo.Block then Z := SelTo.Offset else Z := MaxInt;
    PrepareRuns(B);
    Z := Min(Z,Length(B.Words));
    if A>=Z then
    begin
      if I>SelFrom.Block then Result := Result+LineEnding;
      Continue;
    end;
    Part := TidyCopy(Copy(B.Words,A+1,Z-A));
    if (A=0) and (B.Marker<>'') then Part := B.Marker+' '+Part;
    if I>SelFrom.Block then Result := Result+LineEnding;
    Result := Result+Part;
  end;
end;

function TInkCustomPage.SelectedHTML: string;
var I,A,Z: Integer; B: TInkPageBlock; SelFrom,SelTo: TInkPagePosition; Element,Part: string;
begin
  Result := '';
  if not HasSelection then Exit;
  SelFrom := SelectionStart; SelTo := SelectionEnd;
  for I := SelFrom.Block to Min(SelTo.Block,FBlocks.Count-1) do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if I=SelFrom.Block then A := SelFrom.Offset else A := 0;
    if I=SelTo.Block then Z := SelTo.Offset else Z := MaxInt;
    PrepareRuns(B);
    Z := Min(Z,Length(B.Words));
    if A>=Z then Continue;
    Element := B.Tag;
    if (Element='li') or (Element='dt') or (Element='dd') or (Element='blockquote') or (Element='') then Element := 'p';
    { a whole block keeps its formatting; part of one is its words }
    if (A=0) and (Z=Length(B.Words)) and not B.Pre then Part := B.Source
    else Part := StringReplace(HTMLEscape(TidyCopy(Copy(B.Words,A+1,Z-A))),#10,'<br>',[rfReplaceAll]);
    if B.Pre then Part := StringReplace(Part,'<br>',#10,[rfReplaceAll]);
    if (A=0) and (B.Marker<>'') then Part := HTMLEscape(B.Marker)+' '+Part;
    Result := Result+'<'+Element+'>'+Part+'</'+Element+'>'+LineEnding;
  end;
  Result := '<html><body>'+LineEnding+Result+'</body></html>';
end;

procedure TInkCustomPage.CopyToClipboard;
begin
  if HasSelection then InkCopyText(SelectedText,SelectedHTML);
end;

function TInkCustomPage.SelectionBackground: TColor;
var PageBack: TColor;
begin
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  if FSelectionColor<>clDefault then Result := FSelectionColor
  else Result := MixColor(PageBack,clHighlight,0.45);
  Result := HTMLStringToColor(FStyles.RuleValue('::selection','background',
    FStyles.RuleValue('::selection','background-color','')),Result);
end;

procedure TInkCustomPage.SetSelectionColor(AValue: TColor);
begin
  if FSelectionColor=AValue then Exit;
  FSelectionColor := AValue;
  Invalidate;
end;

procedure TInkCustomPage.PaintSelection(ACanvas: TCanvas; Index: Integer; B: TInkPageBlock;
  const AFrom, ATo: TInkPagePosition);
var K,A,Z,SelA,SelZ,X1,X2,RunEnd: Integer; R: TInkPageRun; Space: Boolean;
begin
  PrepareRuns(B);
  if Index=AFrom.Block then SelA := AFrom.Offset else SelA := 0;
  if Index=ATo.Block then SelZ := ATo.Offset else SelZ := MaxInt;
  ACanvas.Brush.Color := SelectionBackground;
  for K := 0 to B.RunCount-1 do
  begin
    R := B.Runs[K];
    RunEnd := R.Start+Length(R.Text);
    A := Max(SelA,R.Start); Z := Min(SelZ,RunEnd);
    if A>=Z then Continue;
    X1 := RunX(R,A); X2 := RunX(R,Z);
    { a selection that runs on past the end of a line shows a little of
      the space it takes with it }
    Space := (Z=RunEnd) and (SelZ>RunEnd) and
      ((K=B.RunCount-1) or (B.Runs[K+1].Line<>R.Line) or (B.Runs[K+1].Part<>R.Part));
    if Space then begin RunFont(Canvas,R); Inc(X2,Canvas.TextWidth(' ')) end;
    { painted over the text, which is then drawn again on it: a code span's
      own background would otherwise hide the selection }
    ACanvas.Brush.Style := bsSolid;
    ACanvas.FillRect(Rect(X1,R.Top-FScroll.Position,X2,R.Top+R.LineHeight-FScroll.Position));
    RunFont(ACanvas,R);
    ACanvas.Font.Color := R.FontColor;
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(X1,R.Top-FScroll.Position,Copy(R.Text,A-R.Start+1,Z-A));
  end;
end;

function TInkCustomPage.BuildCopyMenu(X,Y: Integer): TPopupMenu;
var Texts: TInkCopyTexts; I: Integer; B: TInkPageBlock;
begin
  Texts := Default(TInkCopyTexts);
  Texts.CanSelect := True;
  if HasSelection then
  begin
    Texts.Selection := SelectedText;
    Texts.SelectionHTML := SelectedHTML;
  end;
  I := BlockAt(X,Y);
  if I>=0 then
  begin
    B := TInkPageBlock(FBlocks[I]);
    Texts.Block := TidyCopy(BlockText(I));
    Texts.BlockCaption := CopyBlockCaption;
    if (Texts.Block<>'') and (B.Marker<>'') then Texts.Block := B.Marker+' '+Texts.Block;
  end;
  Texts.Link := HitLink(X,Y);
  Texts.All := TrimRight(PlainText);
  Texts.SelectAll := @DoSelectAll;
  FCopyMenuHost.Build(Self,Texts,X,Y,FOnCopyMenu);
  Result := FCopyMenuHost.Menu;
end;

procedure TInkCustomPage.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var P: TPoint;
begin
  inherited DoContextPopup(MousePos,Handled);
  if Handled or not FCopyMenu or Assigned(PopupMenu) then Exit;
  { from the keyboard's menu key the place is unknown: the page's corner }
  if (MousePos.X<0) and (MousePos.Y<0) then MousePos := Point(8,8);
  BuildCopyMenu(MousePos.X,MousePos.Y);
  if FCopyMenuHost.Menu.Items.Count=0 then Exit;
  P := ClientToScreen(MousePos);
  FCopyMenuHost.Menu.PopUp(P.X,P.Y);
  Handled := True;
end;

function TInkCustomPage.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FScroll.Position := EnsureRange(FScroll.Position-WheelDelta div 3,0,Max(0,FContentHeight-ClientHeight));
  Result := True;
end;
procedure TInkCustomPage.KeyDown(var Key: Word; Shift: TShiftState);
var Delta: Integer;
begin
  inherited; Delta := 0;
  if ssCtrl in Shift then
    case Key of
      VK_A: begin SelectAll; Key := 0; Exit end;
      VK_C, VK_INSERT: begin CopyToClipboard; Key := 0; Exit end;
      VK_F: begin ShowFindBar; Key := 0; Exit end;
    end;
  if (Shift*[ssAlt,ssCtrl,ssShift]=[ssAlt]) and (Key in [VK_LEFT,VK_RIGHT]) then
  begin
    if Key=VK_LEFT then Back else Forward;
    Key := 0; Exit;
  end;
  if Key in [VK_BROWSER_BACK,VK_BROWSER_FORWARD] then
  begin
    if Key=VK_BROWSER_BACK then Back else Forward;
    Key := 0; Exit;
  end;
  if (Key=VK_F3) and (FFindText<>'') then
  begin
    if ssShift in Shift then Find(FFindText,[ifoBackwards]) else Find(FFindText);
    Key := 0; Exit;
  end;
  case Key of
    VK_UP: Delta := -32;
    VK_DOWN: Delta := 32;
    VK_PRIOR: Delta := -ClientHeight;
    VK_NEXT: Delta := ClientHeight;
    VK_HOME: Delta := -FContentHeight;
    VK_END: Delta := FContentHeight;
  end;
  if Delta<>0 then begin FScroll.Position := EnsureRange(FScroll.Position+Delta,0,Max(0,FContentHeight-ClientHeight)); Key := 0 end;
end;
procedure TInkCustomPage.ScrollTo(Y: Integer);
begin
  Layout; FScroll.Position := EnsureRange(Y,0,Max(0,FContentHeight-ClientHeight));
end;
procedure TInkCustomPage.JumpToAnchor(const Anchor: string);
var I: Integer; B: TInkPageBlock;
begin
  Layout;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if Pos(' '+Anchor+' ',' '+B.Anchor+' ')>0 then begin FScroll.Position := Min(B.Bounds.Top,Max(0,FContentHeight-ClientHeight)); Exit end;
  end;
end;
{ --- finding ------------------------------------------------------------ }

function TInkCustomPage.SearchWords(Index: Integer; AOptions: TInkFindOptions): string;
var Lower: string;
begin
  Result := BlockText(Index);
  if ifoMatchCase in AOptions then Exit;
  { UTF-8 lower case, unless it would change where the characters are }
  Lower := UTF8LowerCase(Result);
  if Length(Lower)=Length(Result) then Result := Lower else Result := LowerCase(Result);
end;

function TInkCustomPage.FindFrom(const AText: string; AOptions: TInkFindOptions;
  const AFrom: TInkPagePosition; out AMatch: TInkPagePosition): Boolean;
var Needle, Hay: string; I, Step, K, N, Q, Last: Integer; Start: TInkPagePosition;
begin
  Result := False;
  AMatch.Block := 0; AMatch.Offset := 0;
  if (AText='') or (FBlocks.Count=0) then Exit;
  Needle := AText;
  if not (ifoMatchCase in AOptions) then
  begin
    Needle := UTF8LowerCase(AText);
    if Length(Needle)<>Length(AText) then Needle := LowerCase(AText);
  end;
  Start := Clamp(AFrom);
  if ifoBackwards in AOptions then Step := -1 else Step := 1;
  { every block once, starting with the one the search starts in, and that
    one again at the end for what lies on the other side of the start }
  I := Start.Block;
  for N := 0 to FBlocks.Count do
  begin
    Hay := SearchWords(I,AOptions);
    if Step>0 then
    begin
      if N=0 then K := Start.Offset+1 else K := 1;
      Q := Pos(Needle,Hay,K);
      if (N=FBlocks.Count) and (Q>Start.Offset) then Q := 0;
      if Q>0 then
      begin
        AMatch.Block := I; AMatch.Offset := Q-1;
        Exit(True);
      end;
    end
    else
    begin
      { the last match that begins before the start (or anywhere, after
        the first block) }
      Last := 0; Q := Pos(Needle,Hay);
      while Q>0 do
      begin
        if (N=0) and (Q-1>=Start.Offset) then Break;
        if (N=FBlocks.Count) and (Q-1<Start.Offset) then begin Q := Pos(Needle,Hay,Q+1); Continue end;
        Last := Q;
        Q := Pos(Needle,Hay,Q+1);
      end;
      if Last>0 then
      begin
        AMatch.Block := I; AMatch.Offset := Last-1;
        Exit(True);
      end;
    end;
    I := I+Step;
    if I>=FBlocks.Count then I := 0;
    if I<0 then I := FBlocks.Count-1;
  end;
end;

function TInkCustomPage.SelectMatch(const AText: string; AOptions: TInkFindOptions;
  const AFrom: TInkPagePosition): Boolean;
var Match, MatchEnd: TInkPagePosition;
begin
  FFindText := AText;
  Result := FindFrom(AText,AOptions,AFrom,Match);
  if not Result then Exit;
  MatchEnd := Match;
  MatchEnd.Offset := Match.Offset+Length(AText);
  FSelAnchor := Match; FSelCaret := MatchEnd;
  ScrollIntoView(Match);
  SelectionChanged;
end;

function TInkCustomPage.FindStart(AOptions: TInkFindOptions): TInkPagePosition;
begin
  if HasSelection then Exit(SelectionStart);
  { nothing selected: from what is on screen }
  if ifoBackwards in AOptions then Result := PositionAt(ClientWidth,ClientHeight-1)
  else Result := PositionAt(0,0);
end;

function TInkCustomPage.Find(const AText: string; AOptions: TInkFindOptions): Boolean;
var From: TInkPagePosition;
begin
  From := FindStart(AOptions);
  { the next match begins after the current one does; the one before,
    before it }
  if HasSelection and not (ifoBackwards in AOptions) then Inc(From.Offset);
  Result := SelectMatch(AText,AOptions,From);
end;

function TInkCustomPage.FindCount(const AText: string; AOptions: TInkFindOptions;
  out Current: Integer): Integer;
var I, Q: Integer; Needle, Hay: string; SelFrom, SelTo: TInkPagePosition;
begin
  Result := 0; Current := 0;
  if AText='' then Exit;
  Needle := AText;
  if not (ifoMatchCase in AOptions) then
  begin
    Needle := UTF8LowerCase(AText);
    if Length(Needle)<>Length(AText) then Needle := LowerCase(AText);
  end;
  SelFrom := SelectionStart; SelTo := SelectionEnd;
  for I := 0 to FBlocks.Count-1 do
  begin
    Hay := SearchWords(I,AOptions);
    Q := Pos(Needle,Hay);
    while Q>0 do
    begin
      Inc(Result);
      if HasSelection and (SelFrom.Block=I) and (SelFrom.Offset=Q-1) and
        (SelTo.Block=I) and (SelTo.Offset=Q-1+Length(Needle)) then Current := Result;
      Q := Pos(Needle,Hay,Q+Length(Needle));
    end;
  end;
end;

procedure TInkCustomPage.ScrollIntoView(const APosition: TInkPagePosition);
var P: TPoint; B: TInkPageBlock; Margin, PlaceTop, PlaceBottom: Integer;
begin
  P := PositionPoint(APosition);
  B := TInkPageBlock(FBlocks[Clamp(APosition).Block]);
  Margin := Scale96ToFont(40);
  PlaceTop := P.Y;
  PlaceBottom := P.Y+Max(B.PointSize*2,16);
  if FindBarVisible then Inc(Margin,FindBarRect.Bottom);
  if PlaceTop<Margin then
    FScroll.Position := EnsureRange(FScroll.Position+PlaceTop-Margin,0,Max(0,FContentHeight-ClientHeight))
  else if PlaceBottom>ClientHeight-Scale96ToFont(40) then
    FScroll.Position := EnsureRange(FScroll.Position+PlaceBottom-ClientHeight+Scale96ToFont(40)+ClientHeight div 3,
      0,Max(0,FContentHeight-ClientHeight));
end;

function TInkCustomPage.GetFindBarVisible: Boolean;
begin
  Result := Assigned(FFindEdit) and FFindEdit.Visible;
end;

function TInkCustomPage.FindBarRect: TRect;
var W, H: Integer;
begin
  H := Scale96ToFont(34);
  W := Min(Scale96ToFont(360),ClientWidth-FScroll.Width-8);
  Result := Rect(ClientWidth-FScroll.Width-W-6,4,ClientWidth-FScroll.Width-6,4+H);
end;

{ 0 previous, 1 next, 2 close }
function TInkCustomPage.FindButtonRect(Index: Integer): TRect;
var Bar: TRect; S: Integer;
begin
  Bar := FindBarRect;
  S := Bar.Bottom-Bar.Top-8;
  Result := Rect(Bar.Right-4-(3-Index)*S,Bar.Top+4,Bar.Right-4-(2-Index)*S,Bar.Bottom-4);
end;

procedure TInkCustomPage.PlaceFindBar;
var Bar: TRect;
begin
  if not Assigned(FFindEdit) then Exit;
  Bar := FindBarRect;
  { the edit, then the count, then the three buttons }
  FFindEdit.SetBounds(Bar.Left+6,Bar.Top+5,
    Max(40,FindButtonRect(0).Left-Bar.Left-6-Scale96ToFont(64)),Bar.Bottom-Bar.Top-10);
end;

procedure TInkCustomPage.ShowFindBar;
begin
  if not Assigned(FFindEdit) then
  begin
    FFindEdit := TInkEdit.Create(Self);
    FFindEdit.Parent := Self;
    FFindEdit.OnChange := @FindEditChange;
    FFindEdit.OnKeyDown := @FindEditKey;
  end;
  FFindEdit.Font.Assign(Font);
  PlaceFindBar;
  FFindEdit.Visible := True;
  if FFindEdit.CanFocus then FFindEdit.SetFocus;
  { a selection on one line is what to look for, as in a browser }
  if HasSelection and (Pos(#10,SelectedText)=0) and (FFindEdit.Text<>SelectedText) then
    FFindEdit.Text := SelectedText;
  FFindEdit.SelectAll;
  Invalidate;
end;

procedure TInkCustomPage.HideFindBar;
begin
  if not FindBarVisible then Exit;
  FFindEdit.Visible := False;
  if CanFocus then SetFocus;
  Invalidate;
end;

procedure TInkCustomPage.FindEditChange(Sender: TObject);
begin
  if FFindEdit.Text='' then
  begin
    FFindText := '';
    ClearSelection;
    Invalidate;
    Exit;
  end;
  { as it is typed: from where the match so far begins, so it grows in
    place; nothing found leaves the last match where it was }
  SelectMatch(FFindEdit.Text,[],FindStart([]));
  Invalidate;
end;

procedure TInkCustomPage.FindEditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN, VK_F3:
      begin
        if ssShift in Shift then Find(FFindEdit.Text,[ifoBackwards])
        else Find(FFindEdit.Text);
        Invalidate;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        HideFindBar;
        Key := 0;
      end;
  end;
end;

procedure TInkCustomPage.PaintFindBar(ACanvas: TCanvas);
const
  Glyphs: array[0..2] of string = ('▲','▼','✕');
var Bar, R: TRect; PageBack, Fore: TColor; Total, Current, K: Integer; Count: string;
begin
  Bar := FindBarRect;
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  Fore := FStyles.Color('body','','color',Font.Color);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := HTMLShadeColor(PageBack,10);
  ACanvas.Pen.Color := MixColor(PageBack,Fore,0.4);
  ACanvas.RoundRect(Bar,8,8);
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := MixColor(PageBack,Fore,0.8);
  ACanvas.Brush.Style := bsClear;
  Total := FindCount(FFindEdit.Text,[],Current);
  if FFindEdit.Text='' then Count := ''
  else if Total=0 then Count := '0/0'
  else Count := IntToStr(Current)+'/'+IntToStr(Total);
  R := Rect(FFindEdit.Left+FFindEdit.Width+4,Bar.Top,FindButtonRect(0).Left-2,Bar.Bottom);
  ACanvas.TextOut(R.Right-ACanvas.TextWidth(Count),
    (Bar.Top+Bar.Bottom-ACanvas.TextHeight(Count)) div 2,Count);
  for K := 0 to 2 do
  begin
    R := FindButtonRect(K);
    ACanvas.TextOut((R.Left+R.Right-ACanvas.TextWidth(Glyphs[K])) div 2,
      (R.Top+R.Bottom-ACanvas.TextHeight(Glyphs[K])) div 2,Glyphs[K]);
  end;
end;

end.
