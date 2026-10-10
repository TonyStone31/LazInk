{ Native scrolling HTML help viewer; no browser engine. SPDX-License-Identifier: 0BSD; see LICENSE. }
unit InkPage;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, StdCtrls, Graphics, Types, Menus, LMessages, InkDraw, InkMarkdown, InkCode, InkGIF, InkWebP, ExtCtrls, InkScrollBar, InkTouch, InkCopyMenu, InkEdit, InkDOM, InkStyle, InkLayout;
type
  { how a control answers @media (prefers-color-scheme) }
  TInkColorScheme = (icsAuto, icsLight, icsDark);
  { one thing the tree layout paints: a box's background and borders, or a
    block's words, and the rectangle overflow cuts it to }
  TInkTreePaint = record
    Box: TObject;
    Block: Integer;
    Clip: TRect;
    Clipped: Boolean;
    { a memo entry's band, behind the document it shows }
    Section: TObject;
  end;

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
  { whether the control shows its scrollbar: issAuto lets the stylesheet
    decide (scrollbar-width), issNone never shows one.  The content still
    scrolls by wheel, keys, finger and code either way. }
  TInkScrollBarStyle = (issAuto, issNone);
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
  { A press on one of the buttons CodeActions puts on every code block's
    header: the block (Block(ABlock).Entry is a memo's entry), the button's
    caption, and the block's code as plain text with its language. }
  TInkCodeActionEvent = procedure(Sender: TObject; ABlock: Integer;
    const AAction, ACode, ALanguage: string) of object;
  { a button on a code block's header, in page coordinates: Kind 0 folds
    and opens, 1 is one of CodeActions (Action says which), 2 is Copy }
  TInkCodeButton = record
    Kind, Action: Integer;
    Caption: string;
    R: TRect;
  end;
  TInkCodeButtons = array of TInkCodeButton;
  TInkPageBlock = class
  public
    Source, Wrapped, Tag, CSSClass: string;
    { a code block: the code as plain text, and the language the fence or
      the class named ('' when it named none) }
    Code, CodeLanguage: string;
    { A code block's header (CodeHeader): its height, 0 for none; how many
      lines the code has; whether it shows only its first CodeFoldLines
      lines, decided once and then the reader's to change; and when Copy
      was pressed, for the "Copied" it says for a moment. }
    CodeHead, CodeLines: Integer;
    CodeFolded, CodeFoldSet: Boolean;
    CodeCopiedAt: QWord;
    { the ids that lead to this block, separated by spaces }
    Anchor: string;
    { a list item's bullet, number or task box, drawn hanging to the left of
      the text }
    Marker: string;
    Picture: TPicture;
    Animation: TInkGIF;
    WebP: TInkWebP;
    { a picture: where it came from, where it is drawn, and the link around
      it, if any (href as in markup) }
    ImageSrc, LinkHref, LinkTarget: string;
    ImageRect: TRect;
    { a line's height in pixels when the page asked for one, zero when it
      left every line the height of the font in it }
    LineHeight: Integer;
    { the target of each text link in the block, in order }
    LinkTargets: array of string;
    { the title of each text link, in the same order: its tooltip }
    LinkTitles: array of string;
    { a <summary>: the fold it opens and shuts, -1 for anything else }
    FoldHead: Integer;
    { the block, and the part of it the words are drawn in; page coordinates }
    Bounds, TextBounds: TRect;
    Indent, PointSize, Padding, GapBefore, GapAfter, MarkerWidth: Integer;
    { the item it belongs to: a memo's entry; on a page, 0 }
    Entry: Integer;
    { code: whitespace kept, the fixed face, never wrapped - a long line is
      cut off at the block's edge }
    Pre: Boolean;
    { laid out as written, and cut off at the edge - code, or a memo with
      WordWrap off }
    NoWrap: Boolean;
    Bold: Boolean;
    FaceName: string;
    TextColor, BackColor: TColor;
    { where each run of its text was drawn, and its words as they are
      copied - filled in when first needed, after each layout }
    Runs: array of TInkPageRun;
    RunCount: Integer;
    Words: string;
    RunsReady: Boolean;
    { made by the tree layout: its box, its words' narrowest and widest, the
      width last wrapped at and the height it came to, and whether a list
      marker hangs in the margin or stands in the words }
    Tree: Boolean;
    TreeBox: TObject;
    TextMinW, TextMaxW, WrapWidth, TreeTextH: Integer;
    WidthsKnown, MarkerHangs: Boolean;
    { where it is in the page's blocks, and the document it was made from
      (nil for a line of markup of its own) }
    Index: Integer;
    Section: TObject;
    constructor Create;
    destructor Destroy; override;
  end;

  { A document laid out from its tree: the page shows one, a memo one for
    each message it lays out whole.  Its blocks are the page's blocks
    BlockFrom to BlockFrom+BlockCount-1. }
  TInkTreeSection = class
  public
    Doc: TInkDocument;
    OwnsDoc: Boolean;
    Layout: TInkLayout;
    { the <details> each summary in it opens and shuts }
    Folds: array of TInkNode;
    { how many elements the styler had before this one's }
    StyleMark: Integer;
    Item, BlockFrom, BlockCount: Integer;
    { where it was laid out, page pixels }
    Left, Top, Width, Height: Integer;
    { set by StyleSection: room above and below, an inset, and a band }
    GapBefore, GapAfter, Indent: Integer;
    Back: TColor;
    destructor Destroy; override;
  end;
  { The engine behind TInkPage and TInkMemo: items laid out down a
    scrolling column - documents laid out from their trees, and a memo's
    lines of markup - with selection, the copy menu, find, touch and
    history.  Descendants decide where the items come from (Parse), how a
    line looks (StyleBlock) and how wide the column is (LayoutColumn). }
  TInkCustomPage = class(TCustomControl)
  private
    FBlocks: TList;
    { what is laid out down the column, in order: a TInkPageBlock for a
      line of markup, a TInkTreeSection for a document }
    FItems: TList;
    { the blocks with a moving picture in them, so the twenty-millisecond
      tick has a short list to walk instead of the whole document - and so
      it can be switched off altogether when there is nothing to move }
    FAnimated: TList;
    FRenderCache: THTMLLayoutCache;
    { the page as a tree, and whether it was changed through Document and
      must be shown as it stands rather than parsed again }
    FDocument: TInkDocument;
    FKeepDocument: Boolean;
    { the document's computed styles, worked out the first time they are
      asked for }
    FStyler: TInkStyler;
    FStyled: Boolean;
    { the page's own document laid out, what measures words, which @media
      queries held, the paint order, and the canvas's color }
    FPageSection: TInkTreeSection;
    FTreeMeasure: TObject;
    FTreeKey: string;
    FTreePaint: array of TInkTreePaint;
    { the clip a block being painted is inside, in window pixels }
    FPaintClip: TRect;
    FPaintClipped: Boolean;
    FCanvasBack: TColor;
    { the wheel's part of a pixel not yet scrolled, and when the page last
      reached the screen }
    FWheelRest: Double;
    FLastPaint: QWord;
    { pictures decoded for the page at FImageCacheFor, by address }
    FImageCache: TStringList;
    FImageCacheFor: string;
    FScroll: TInkScrollBar;
    FScrollBars: TInkScrollBarStyle;
    FColorScheme: TInkColorScheme;
    { what the last read of the document resolved icsAuto to }
    FSchemeApplied: TInkColorScheme;
    FTimer: TTimer;
    function FetchSheet(const URL: string): string;
    function TreeTextHeight(B: TInkPageBlock; AWidth: Integer): Integer;
    procedure TreeTextWidths(B: TInkPageBlock; out AMin, AMax: Integer);
    procedure TreeText(ABox: TInkBox; B: TInkPageBlock);
    procedure TreeStyle(AWidth: Integer);
    procedure BuildSection(S: TInkTreeSection);
    procedure ClearSectionBlocks(S: TInkTreeSection);
    procedure Renumber(AFromItem: Integer);
    function TreeViewWidth: Integer;
    function TreeCanvasBack: TColor;
    { the page's root element's style, or its body's; nil without a page }
    function PageStyle(ABody: Boolean): TInkStyle;
    { a property the root sets, or else the body }
    function PageValue(const AProp: string): string;
    procedure LayLine(B: TInkPageBlock; ALeft, AWidth: Integer; var Y, Pending: Integer;
      var O: THTMLOptions);
    procedure LaySection(S: TInkTreeSection; ALeft, AWidth: Integer; var Y, Pending: Integer);
    procedure TreePaintOrder;
    procedure TreePaintBox(ACanvas: TCanvas; ABox: TInkBox);
    procedure TreeRender(ACanvas: TCanvas);
    function TreePaintMarker(ACanvas: TCanvas; B: TInkPageBlock; const TR: TRect): Boolean;
    function TreeBlockAt(X, DocY: Integer; ANearest: Boolean): Integer;
    procedure TreeToggleFold(Index: Integer);
    procedure LoadPicture(B: TInkPageBlock);
    procedure Animate(Sender: TObject);
    procedure SetImageFit(AValue: TInkImageFit);
    procedure SetScrollBars(AValue: TInkScrollBarStyle);
    procedure SetColorScheme(AValue: TInkColorScheme);
    function GetActiveColorScheme: TInkColorScheme;
    { read the document again with the styles judged afresh, keeping the
      scroll where it was }
    procedure Reread;
    procedure CMColorChanged(var Message: TLMessage); message CM_COLORCHANGED;
  private
    FSource, FLocation, FTitle, FHoverLink: string;
    FHoverBlock, FHoverLinkIndex: Integer;
    FClickedLink: TInkLinkInfo;
    FOnLinkActivate: TInkLinkActivateEvent;
    FImageFit: TInkImageFit;
    FHistory: TStringList;
    FHistoryIndex: Integer;
    FTextFormat: TInkTextFormat;
    FStyleSheet: TStringList;
    FMarkdownRawHTML, FMarkdownInlineHTML: Boolean;
    FLayoutDirty: Boolean;
    FContentHeight, FColumnLeft: Integer;
    FOnLinkClick: TInkPageLinkEvent;
    FOnResource: TInkPageResourceEvent;
    FOnHighlightCode: TInkHighlightEvent;
    FHighlightCode: Boolean;
    FCodeHeader: Boolean;
    FCodeFoldLines: Integer;
    FCodeActions: TStringList;
    FOnCodeAction: TInkCodeActionEvent;
    FCodeHotBlock, FCodeHotButton: Integer;
    FCodeTimer: TTimer;
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
    function StepChar(const P: TInkPagePosition; ADelta: Integer): TInkPagePosition;
    function CaretLineHeight(const P: TInkPagePosition): Integer;
    procedure ExtendByKey(Key: Word);
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
    procedure SetMarkdownInlineHTML(AValue: Boolean);
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
    FLayoutBase, FLayoutWidth, FLayoutFrom: Integer;
    FBodyText, FCodeBack: TColor;
    FColumnWidth: Integer;
    procedure SetHighlightCode(AValue: Boolean);
    procedure SetCodeHeader(AValue: Boolean);
    procedure SetCodeFoldLines(AValue: Integer);
    function GetCodeActions: TStrings;
    procedure SetCodeActions(AValue: TStrings);
    procedure CodeActionsChanged(Sender: TObject);
    procedure CodeTimerTick(Sender: TObject);
    procedure CodeHeadFont(ACanvas: TCanvas);
    procedure PaintCodeHead(ACanvas: TCanvas; Index: Integer; B: TInkPageBlock; const R: TRect);
    function CodeButtonAt(X,Y: Integer; out ABlock, AButton: Integer): Boolean;
    procedure PaintBlock(ACanvas: TCanvas; I: Integer; ASelected: Boolean;
      const SelFrom, SelTo: TInkPagePosition);
    procedure PressCodeButton(ABlock, AButton: Integer);
    { a code block's markup: the host's coloring, or the page's own }
    function CodeMarkup(const ACode, ALanguage: string): string;
    procedure ClearItems;
    { no items, no styles, no selection: what Parse starts from }
    procedure BeginDocument;
    { a line of markup, laid out as StyleBlock says }
    procedure AddBlock(B: TInkPageBlock);
    { a document, styled with the styler as it stands and laid out from its
      tree; AOwns frees it with the section }
    function AddSection(ADoc: TInkDocument; AOwns: Boolean): TInkTreeSection;
    { the styler the documents are styled with, set to the control's colors
      and font, with no sheets of any page in it }
    procedure ResetStyler;
    property Styler: TInkStyler read FStyler;
    { the look a Markdown document gets, as GitHub gives it: quotes with a
      bar, code on a shade, tables ruled - in the control's colors }
    function MarkdownSheet: string;
    { what ImageFit asks of every picture }
    function ImageFitSheet: string;
    { what goes between block I-1 and block I when they are copied: a tab
      between two cells of a row, else a line end }
    function BlockJoint(I: Integer): string;
    { the control's font in pixels: what medium means, and a memo's lines }
    function ControlFontPixels: Integer;
    function ItemCount: Integer;
    function PageItem(Index: Integer): TObject;
    { items from AFrom on freed and forgotten - how a memo replaces its
      growing last entry without touching the rest }
    procedure TruncateItems(AFrom: Integer);
    { items from Index on are laid out again when next needed; 0 for all }
    procedure InvalidateLayout(FromItem: Integer = 0);
    { the item block ABlock belongs to, and everything after it }
    procedure InvalidateBlock(ABlock: Integer);
    procedure Layout;
    { where the items come from: the page reads Source; a memo, its Lines }
    procedure Parse; virtual;
    { the column the items are laid out in, in client coordinates }
    procedure LayoutColumn(out ALeft, AWidth: Integer); virtual;
    { a line's font, colors, padding and gaps, before it is measured }
    procedure StyleBlock(B: TInkPageBlock); virtual;
    { a document's gaps, inset and band }
    procedure StyleSection(S: TInkTreeSection); virtual;
    function Options: THTMLOptions; virtual;
    procedure FindAnimations;
    function BlockOptions(Index: Integer): THTMLOptions; virtual;
    function HitLink(X,Y: Integer): string;
    function HitTestLink(X,Y: Integer; out ABlock: Integer; out AHit: THTMLHitInfo): Boolean;
    { a link was clicked }
    procedure LinkClicked(const Link: TInkLinkInfo); virtual;
    { the pointer moved onto another link, or off one (ABlock -1) }
    procedure HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo); virtual;
    { the copy menu's name for the block under the pointer, and the text
      its item copies - a memo answers for the whole entry }
    function CopyBlockCaption(AIndex: Integer): string; virtual;
    function MenuBlockText(AIndex: Integer): string; virtual;
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
    procedure KeepPainting;
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
    { Replaces what is inside the element whose id attribute is AID with
      AHTML and reads the page again, keeping the scroll where it was - so
      a status page can change one line cheaply, without rebuilding its
      whole source.  True when the element was found.  HTML sources only;
      history is left alone. }
    function SetInnerHTML(const AID, AHTML: string): Boolean;
    { The page as the tree a browser builds from it, HTML or Markdown alike.
      A program may read it and change it - add, remove, set text and
      attributes - and then calls DocumentChanged to see the result.  It
      belongs to the page: a new page frees it. }
    property Document: TInkDocument read FDocument;
    { Document was changed: show it, keeping the scroll where it was.  The
      nodes held stay valid; Source becomes the document's HTML. }
    procedure DocumentChanged;
    { An element's computed style - the cascade a browser runs, with the
      page's sheets, the host's StyleSheet and the browser's defaults, at
      the page's width.  nil for anything not an element of Document. }
    function ComputedStyle(ANode: TInkNode): TInkStyle;
    { the rules that apply to an element, weakest first, as an inspector
      shows them; the caller frees the list }
    function ExplainStyle(ANode: TInkNode): TStringList;
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
    { the buttons on code block ABlock's header, in page coordinates, right
      to left; none when it has no header }
    function CodeButtons(ABlock: Integer): TInkCodeButtons;
    { shows only code block ABlock's first CodeFoldLines lines, or all }
    procedure FoldCode(ABlock: Integer; AFolded: Boolean);
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
    { whether anything on the page is moving.  A page of still pictures
      stops the twenty-millisecond tick altogether rather than waking up to
      look at every block fifty times a second. }
    function Animating: Boolean;
    { how far down the page is scrolled, in pixels }
    property ScrollY: Integer read GetScrollY;
    { The page's own scrollbar, drawn by LazInk and colored from the page's
      CSS: scrollbar-color (thumb, then track) and scrollbar-width (auto,
      thin or none), read from html or :root, falling back to body.  Without
      them the track is the page background and the thumb sits halfway
      between that and the text color. }
    property ScrollBar: TInkScrollBar read FScroll;
    { what icsAuto came to, for a host that wants to match it }
    property ActiveColorScheme: TInkColorScheme read GetActiveColorScheme;
    { re-judge the color scheme (after InkAppColorScheme or a theme change)
      and read the document again if the answer moved }
    procedure RecheckColorScheme;
  protected
    property Source: string read FSource write SetSource;
    { CSS applied to every page before the page's own styles - how a program
      dresses a Markdown document, which has no stylesheet, in its theme.
      A page's own rules win over these where both say something. }
    property StyleSheet: TStrings read GetStyleSheet write SetStyleSheet;
    { HTML written inside a Markdown source is drawn as HTML, not shown as
      text.  Only for documents you trust. }
    property MarkdownRawHTML: Boolean read FMarkdownRawHTML write SetMarkdownRawHTML default False;
    { The middle ground: only well-formed inline tags named on
      InkMarkdownInlineTags (<kbd>, <sub>, <br>...) are drawn, keeping only
      class and title; a /tiles <folder> placeholder, a block tag or a
      script stays visible text.  MarkdownRawHTML wins when both are set. }
    property MarkdownInlineHTML: Boolean read FMarkdownInlineHTML write SetMarkdownInlineHTML default False;
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
    { A header on each code block, as code viewers draw one: the language
      and how many lines on the left; Copy, CodeActions and, for a long
      block, Show all / Show less on the right. }
    property CodeHeader: Boolean read FCodeHeader write SetCodeHeader default True;
    { a code block longer than this many lines starts folded to them, with
      Show all on its header; 0 never folds }
    property CodeFoldLines: Integer read FCodeFoldLines write SetCodeFoldLines default 0;
    { the captions of buttons every code block's header gets beside Copy;
      OnCodeAction says which was pressed, on which block }
    property CodeActions: TStrings read GetCodeActions write SetCodeActions;
    property OnCodeAction: TInkCodeActionEvent read FOnCodeAction write FOnCodeAction;
    { drag the page with the left button - or a finger - to scroll it; a
      press that moves less than a few pixels is still a click }
    property DragScroll: Boolean read FDragScroll write FDragScroll default True;
    { issNone hides the scrollbar whatever the stylesheet says; issAuto
      leaves it to the stylesheet's scrollbar-width (none, thin, auto) }
    property ScrollBars: TInkScrollBarStyle read FScrollBars write SetScrollBars default issAuto;
    { What @media (prefers-color-scheme) queries answer to.  icsAuto follows
      InkAppColorScheme when the program set it, else the control's own
      background: light when its luminance is at least half.  No built-in
      palette: the scheme only chooses between the rules the page and the
      host wrote. }
    property ColorScheme: TInkColorScheme read FColorScheme write SetColorScheme default icsAuto;
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
    property MarkdownInlineHTML;
    property OnLinkClick;
    property OnLinkActivate;
    property ImageFit;
    property OnResource;
    property HighlightCode;
    property OnHighlightCode;
    property CodeHeader;
    property CodeFoldLines;
    property CodeActions;
    property OnCodeAction;
    property DragScroll;
    property FlickScroll;
    property MouseDrag;
    property ScrollBars;
    property ColorScheme;
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
var
  { The application's say on light or dark, for every control whose
    ColorScheme is icsAuto: a program with its own themes sets it once
    (and calls InkColorSchemeChanged when windows are open).  On icsAuto a
    control falls back to its own background's luminance. }
  InkAppColorScheme: TInkColorScheme = icsAuto;
{ a hit link's href as written: entities read, and the renderer's stand-in
  for an ampersand turned back into one }
function LinkHref(const AHit: THTMLHitInfo): string;
{ Tell every LazInk page on every open form that the application's color
  scheme changed (after setting InkAppColorScheme, or when the program's
  own theme flips): each control whose ColorScheme is icsAuto re-checks,
  and reads its document again only if its answer moved.  Nothing keeps a
  list of instances. }
procedure InkColorSchemeChanged;
{ a computed color as a TColor, its opacity mixed into what is behind it }
function InkToColor(C: TInkRGBA; ABehind: TColor): TColor;

implementation
uses Math, StrUtils, URIParser, LCLType, LCLIntf, LazUTF8, Forms, Clipbrd;

{ every LazInk page on every form re-checks its color scheme - see the
  interface declaration }
procedure SchemeWalk(C: TControl);
var I: Integer;
begin
  if C is TInkCustomPage then TInkCustomPage(C).RecheckColorScheme;
  if C is TWinControl then
    for I := 0 to TWinControl(C).ControlCount-1 do
      SchemeWalk(TWinControl(C).Controls[I]);
end;
procedure InkColorSchemeChanged;
var I: Integer;
begin
  for I := 0 to Screen.FormCount-1 do SchemeWalk(Screen.Forms[I]);
end;

function LinkHref(const AHit: THTMLHitInfo): string;
begin
  Result := StringReplace(HTMLUnescape(AHit.LinkName),#1,'&',[rfReplaceAll]);
end;
{ A CSS font stack, resolved to one face this machine actually has.
  "Helvetica Neue", Arial, sans-serif tries each in turn and falls back to
  what the generic name means here; '' means "whatever the control is set
  to", which is what a page that names no family gets. }
function InkResolveFace(const AStack: string): string;
  function Have(const AName: string): Boolean;
  begin
    Result := (AName<>'') and (Screen.Fonts.IndexOf(AName)>=0);
  end;
  function FirstOf(const ANames: array of string): string;
  var K: Integer;
  begin
    for K := 0 to High(ANames) do
      if Have(ANames[K]) then Exit(ANames[K]);
    Result := '';
  end;
var Names: TStringList; I: Integer; N: string;
begin
  Result := '';
  if Trim(AStack)='' then Exit;
  Names := TStringList.Create;
  try
    Names.Delimiter := ','; Names.StrictDelimiter := True;
    Names.DelimitedText := AStack;
    for I := 0 to Names.Count-1 do
    begin
      N := Trim(Names[I]);
      { a family may be quoted, and CSS allows either quote }
      if (Length(N)>=2) and ((N[1]='"') or (N[1]='''')) and (N[Length(N)]=N[1]) then
        N := Copy(N,2,Length(N)-2);
      N := Trim(N);
      if N='' then Continue;
      if Have(N) then Exit(N);
      { the generic families, as this machine spells them }
      case LowerCase(N) of
        'monospace','ui-monospace':
          begin
            Result := FirstOf(['DejaVu Sans Mono','Liberation Mono','Noto Sans Mono',
              'Consolas','Menlo','Courier New']);
            if Result='' then Result := InkMonoFace;
            Exit;
          end;
        'serif':
          Exit(FirstOf(['DejaVu Serif','Liberation Serif','Noto Serif',
            'Times New Roman','Georgia','Serif']));
        'sans-serif','ui-sans-serif','system-ui':
          { the control's own font, left alone.  It is the widgetset's
            default, which is what the platform resolves a generic sans to -
            naming a face here instead would be this machine's guess against
            the system's answer, and on this one that came out eleven per
            cent wider than the browser. }
          Exit('');
        'cursive','fantasy': Exit('');
      end;
    end;
  finally Names.Free end;
end;
{ CSS text-transform, over markup: the words change case, the tags and the
  entities between them do not. }
function Transformed(const AMarkup, AKind: string): string;
var P,Start: Integer; Piece: string; Fresh: Boolean;
begin
  Result := '';
  Fresh := True;
  P := 1;
  while P<=Length(AMarkup) do
  begin
    if AMarkup[P]='<' then
    begin
      Start := P;
      while (P<=Length(AMarkup)) and (AMarkup[P]<>'>') do Inc(P);
      if P<=Length(AMarkup) then Inc(P);
      Result := Result+Copy(AMarkup,Start,P-Start);
      Continue;
    end;
    if AMarkup[P]='&' then
    begin
      Start := P;
      while (P<=Length(AMarkup)) and (AMarkup[P]<>';') and (P-Start<12) do Inc(P);
      if (P<=Length(AMarkup)) and (AMarkup[P]=';') then Inc(P);
      Result := Result+Copy(AMarkup,Start,P-Start);
      Fresh := False;
      Continue;
    end;
    Start := P;
    while (P<=Length(AMarkup)) and not (AMarkup[P] in ['<','&']) do Inc(P);
    Piece := Copy(AMarkup,Start,P-Start);
    if AKind='uppercase' then Result := Result+UTF8UpperCase(Piece)
    else if AKind='lowercase' then Result := Result+UTF8LowerCase(Piece)
    else
    begin
      { capitalize: the first letter of every word }
      for Start := 1 to Length(Piece) do
      begin
        if Piece[Start] in [' ',#9,#10,#13,'-','(','"'] then Fresh := True
        else if Fresh then
        begin
          Piece[Start] := UpCase(Piece[Start]); Fresh := False;
        end;
      end;
      Result := Result+Piece;
    end;
  end;
end;
function IsHeadingTag(const Tag: string): Boolean;
begin
  Result := (Length(Tag)=2) and (Tag[1]='h') and (Tag[2] in ['1'..'6']);
end;
function MixColor(A, B: TColor; Amount: Double): TColor;
begin
  A := ColorToRGB(A); B := ColorToRGB(B);
  Result := RGBToColor(Round(Red(A)+(Red(B)-Red(A))*Amount),
    Round(Green(A)+(Green(B)-Green(A))*Amount),Round(Blue(A)+(Blue(B)-Blue(A))*Amount));
end;
{ a CSS number, which has a full stop whatever the locale says }
function CSSFloat(const S: string; ADefault: Double): Double;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Result := StrToFloatDef(Trim(S), ADefault, FS);
end;
{ a color from InkStyle, as a TColor - its opacity mixed into what is behind }
function InkToColor(C: TInkRGBA; ABehind: TColor): TColor;
var A: Integer;
begin
  A := C shr 24;
  Result := TColor(C and $FFFFFF);
  if A < 255 then Result := MixColor(Result, ABehind, 1 - A / 255);
end;

{ how many lines a block of code is }
function CodeLineCount(const ACode: string): Integer;
var I: Integer;
begin
  Result := 1;
  for I := 1 to Length(ACode) do if ACode[I]=#10 then Inc(Result);
end;

{ the first N lines of a code block's markup, cut at the Nth line break }
function FirstCodeLines(const S: string; N: Integer): string;
var P, Count: Integer;
begin
  Count := 0; P := 1;
  while P<=Length(S) do
  begin
    if (S[P]=#10) or ((S[P]='<') and (LowerCase(Copy(S,P,4))='<br>')) then
    begin
      Inc(Count);
      if Count=N then Exit(Copy(S,1,P-1));
    end;
    Inc(P);
  end;
  Result := S;
end;

function ColorToHTMLHex(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x',[Red(C),Green(C),Blue(C)]);
end;

function ColorAttr(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x',[Red(C),Green(C),Blue(C)]);
end;
constructor TInkPageBlock.Create;
begin
  inherited; Picture := TPicture.Create;
  FoldHead := -1;
  { a fresh block carries no color anywhere: zeroed fields would read as
    clBlack, and a descendant's StyleBlock may not touch every one of them }
  BackColor := clNone;
end;
destructor TInkPageBlock.Destroy;
begin WebP.Free; Animation.Free; Picture.Free; inherited end;
destructor TInkTreeSection.Destroy;
begin
  Layout.Free;
  if OwnsDoc then Doc.Free;
  inherited;
end;
constructor TInkCustomPage.Create(AOwner: TComponent);
begin
  inherited; Width := 640; Height := 480; TabStop := True;
  FHoverBlock := -1; FHighlightCode := True;
  FBlocks := TList.Create; FItems := TList.Create; FAnimated := TList.Create;
  FImageCache := TStringList.Create; FImageCache.OwnsObjects := True;
  FImageCache.CaseSensitive := True; FImageCache.Sorted := True;
  FRenderCache := THTMLLayoutCache.Create;
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
  FCodeHeader := True; FCodeHotBlock := -1; FCodeHotButton := -1;
  FCodeActions := TStringList.Create; FCodeActions.OnChange := @CodeActionsChanged;
  FCodeTimer := TTimer.Create(Self); FCodeTimer.Enabled := False;
  FCodeTimer.OnTimer := @CodeTimerTick;
  Cursor := crIBeam;
  Color := clWindow; Font.Color := clWindowText; Font.Size := 11;
end;
destructor TInkCustomPage.Destroy;
begin
  FTimer.Enabled := False; FFlickTimer.Enabled := False; FAutoScroll.Enabled := False;
  ClearItems; FItems.Free; FBlocks.Free; FAnimated.Free; FHistory.Free;
  FCodeTimer.Enabled := False; FCodeActions.OnChange := nil; FCodeActions.Free;
  FStyleSheet.OnChange := nil; FStyleSheet.Free;
  FreeAndNil(FRenderCache);
  FreeAndNil(FTreeMeasure);
  FreeAndNil(FStyler);
  FreeAndNil(FDocument);
  FreeAndNil(FImageCache);
  inherited;
end;
procedure TInkCustomPage.BeginDocument;
begin
  ClearItems; FTitle := ''; FHoverLink := ''; FHoverBlock := -1;
  FSchemeApplied := GetActiveColorScheme;
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
  var V: string; C: TInkRGBA;
  begin
    Result := ADefault;
    if PageStyle(False)=nil then Exit;
    V := Trim(PageStyle(False).Custom(AVar));
    if (V<>'') and InkParseColor(V,C,GetActiveColorScheme=icsDark) then Result := InkToColor(C,FCanvasBack);
  end;
begin
  Result := '';
  { a host with a real highlighter answers first }
  if Assigned(FOnHighlightCode) then FOnHighlightCode(Self,ACode,ALanguage,Result);
  if (Result<>'') or not FHighlightCode then Exit;
  Colors := InkCodeColors(FCanvasBack);
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
procedure TInkCustomPage.ClearItems;
var I: Integer;
begin
  if FRenderCache<>nil then FRenderCache.Clear;
  if FAnimated<>nil then FAnimated.Clear;
  FTimer.Enabled := False;
  { the documents' elements are forgotten, not touched: some are about to go }
  if FStyler<>nil then FStyler.Release(False);
  FStyled := False;
  for I := 0 to FItems.Count-1 do
    if TObject(FItems[I]) is TInkTreeSection then TObject(FItems[I]).Free;
  for I := 0 to FBlocks.Count-1 do TObject(FBlocks[I]).Free;
  FItems.Clear; FBlocks.Clear;
  FPageSection := nil;
  SetLength(FTreePaint,0);
end;
procedure TInkCustomPage.TruncateItems(AFrom: Integer);
var I,K: Integer; It: TObject;
begin
  if AFrom>=FItems.Count then Exit;
  if FRenderCache<>nil then FRenderCache.Clear;
  SetLength(FTreePaint,0);
  It := TObject(FItems[AFrom]);
  if It is TInkTreeSection then K := TInkTreeSection(It).BlockFrom else K := TInkPageBlock(It).Index;
  if FAnimated<>nil then
    for I := FAnimated.Count-1 downto 0 do
      if TInkPageBlock(FAnimated[I]).Index>=K then FAnimated.Delete(I);
  { the styles of the documents going, while their elements are still there }
  for I := AFrom to FItems.Count-1 do
    if (FStyler<>nil) and (TObject(FItems[I]) is TInkTreeSection) then
    begin
      FStyler.ReleaseTo(TInkTreeSection(FItems[I]).StyleMark);
      Break;
    end;
  for I := FItems.Count-1 downto AFrom do
  begin
    if TObject(FItems[I]) is TInkTreeSection then TObject(FItems[I]).Free;
    FItems.Delete(I);
  end;
  for I := FBlocks.Count-1 downto K do
  begin
    TObject(FBlocks[I]).Free;
    FBlocks.Delete(I);
  end;
  { nothing may keep pointing past the end }
  if FHoverBlock>=FBlocks.Count then FHoverBlock := -1;
  if FRunBlock<>nil then FRunBlock := nil;
  FSelAnchor := Clamp(FSelAnchor); FSelCaret := Clamp(FSelCaret);
  InvalidateLayout(AFrom);
end;
function TInkCustomPage.FoldOpen(Index: Integer): Boolean;
var B: TInkPageBlock; S: TInkTreeSection;
begin
  B := TInkPageBlock(FBlocks[Index]);
  S := TInkTreeSection(B.Section);
  Result := (S<>nil) and (B.FoldHead>=0) and (B.FoldHead<Length(S.Folds)) and
    S.Folds[B.FoldHead].HasAttribute('open');
end;
procedure TInkCustomPage.ToggleFold(Index: Integer);
begin
  if (Index<0) or (Index>=FBlocks.Count) then Exit;
  TreeToggleFold(Index);
end;
procedure TInkCustomPage.AddBlock(B: TInkPageBlock);
begin
  B.Index := FBlocks.Count; B.Entry := FItems.Count; B.Section := nil;
  FBlocks.Add(B); FItems.Add(B);
end;
function TInkCustomPage.ItemCount: Integer;
begin Result := FItems.Count end;
function TInkCustomPage.PageItem(Index: Integer): TObject;
begin Result := TObject(FItems[Index]) end;
procedure TInkCustomPage.InvalidateLayout(FromItem: Integer);
begin
  if FRenderCache<>nil then FRenderCache.Clear;
  if not FLayoutDirty or (FromItem<FLayoutFrom) then FLayoutFrom := Max(0,FromItem);
  FLayoutDirty := True;
  Invalidate;
end;
procedure TInkCustomPage.InvalidateBlock(ABlock: Integer);
var B: TInkPageBlock;
begin
  if (ABlock<0) or (ABlock>=FBlocks.Count) then begin InvalidateLayout(0); Exit end;
  B := TInkPageBlock(FBlocks[ABlock]);
  if B.Section<>nil then InvalidateLayout(TInkTreeSection(B.Section).Item)
  else InvalidateLayout(B.Entry);
end;
function TInkCustomPage.BlockOptions(Index: Integer): THTMLOptions;
var B: TInkPageBlock;
begin
  Result := Options;
  B := TInkPageBlock(FBlocks[Index]);
  Result.LineHeight := B.LineHeight;
  Result.NoWrap := B.NoWrap;
  { a link in the tree layout wears what its CSS says, underline and all }
  if B.Tree then
  begin
    Result.LinkKeepsColor := True; Result.LinkUnderline := False; Result.CSSLines := True;
  end;
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
  if FStyler<>nil then Reread;
end;
function TInkCustomPage.MarkdownSheet: string;
var Paper, Ink: TColor;
begin
  Paper := Color; if Paper=clDefault then Paper := clWindow;
  Ink := Font.Color; if Ink=clDefault then Ink := clWindowText;
  Result :=
    'blockquote { margin: 0 0 1em; padding: 0 1em; border-left: 0.25em solid '+
      ColorToHTMLHex(MixColor(Ink,Paper,0.6))+'; color: '+ColorToHTMLHex(MixColor(Ink,Paper,0.3))+' } '+
    'pre { background: '+ColorToHTMLHex(HTMLShadeColor(Paper,7))+'; padding: 1em; border-radius: 6px } '+
    'code { background: '+ColorToHTMLHex(HTMLShadeColor(Paper,7))+'; padding: 0.2em 0.4em; border-radius: 6px } '+
    'pre code { background: transparent; padding: 0 } '+
    'table { border-collapse: collapse } '+
    'th, td { border: 1px solid '+ColorToHTMLHex(MixColor(Ink,Paper,0.75))+'; padding: 6px 13px } '+
    'hr { height: 0.25em; padding: 0; margin: 24px 0; border: 0; background: currentcolor; color: '+
      ColorToHTMLHex(MixColor(Ink,Paper,0.85))+' } ';
end;
function TInkCustomPage.ImageFitSheet: string;
begin
  case FImageFit of
    iifWidth: Result := 'img { width: 100%; height: auto }';
    { the picture's size is worked out to fit the window as it is measured }
    iifWindow: Result := 'body { margin: 8px } img { display: block; margin: 0 auto }';
  else
    { never past its column }
    Result := 'img { max-width: 100% }';
  end;
end;
function CellOf(B: TInkPageBlock): TInkBox;
var X: TInkBox;
begin
  Result := nil;
  if not B.Tree or (B.TreeBox=nil) then Exit;
  X := TInkBox(B.TreeBox);
  while X<>nil do
  begin
    if not X.Anon and (X.Style.Keyword('display')='table-cell') then Exit(X);
    X := X.Parent;
  end;
end;
function TInkCustomPage.BlockJoint(I: Integer): string;
var A, C: TInkBox;
begin
  Result := LineEnding;
  if (I<=0) or (I>=FBlocks.Count) then Exit;
  A := CellOf(TInkPageBlock(FBlocks[I-1])); C := CellOf(TInkPageBlock(FBlocks[I]));
  if (A<>nil) and (C<>nil) and (A<>C) and (A.Parent=C.Parent) then Result := #9;
end;
procedure TInkCustomPage.HoverChanged(ABlock: Integer; const AHit: THTMLHitInfo);
begin
end;
function TInkCustomPage.CopyBlockCaption(AIndex: Integer): string;
begin Result := SInkCopyParagraph end;
procedure TInkCustomPage.Animate(Sender: TObject);
var I: Integer; B: TInkPageBlock; R: TRect;
begin
  if not Visible then Exit;
  for I := 0 to FAnimated.Count-1 do
  begin
    B := TInkPageBlock(FAnimated[I]);
    if Assigned(B.WebP) and (B.Bounds.Bottom>=FScroll.Position) and
      (B.Bounds.Top<=FScroll.Position+ClientHeight) and B.WebP.Advance then
    begin
      R := B.ImageRect; OffsetRect(R,0,-FScroll.Position);
      if HandleAllocated then LCLIntf.InvalidateRect(Handle,@R,False);
    end;
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
procedure TInkCustomPage.SetMarkdownInlineHTML(AValue: Boolean);
begin
  if FMarkdownInlineHTML=AValue then Exit;
  FMarkdownInlineHTML := AValue;
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
function TInkCustomPage.SetInnerHTML(const AID, AHTML: string): Boolean;
var N: TInkNode;
begin
  Result := False;
  if (FTextFormat<>itfHTML) or (FDocument=nil) then Exit;
  N := FDocument.GetElementById(AID);
  if (N=nil) or InkIsVoidElement(N.Name) then Exit;
  N.InnerHTML := AHTML;
  DocumentChanged;
  Result := True;
end;
function TInkCustomPage.FetchSheet(const URL: string): string;
begin
  try Result := ReadText(URL) except on E: EReadError do Result := '' end;
end;
function TInkCustomPage.ComputedStyle(ANode: TInkNode): TInkStyle;
begin
  Result := nil;
  if (FDocument=nil) or (ANode=nil) then Exit;
  if not FStyled then
  begin
    if FStyler=nil then
    begin
      FStyler := TInkStyler.Create;
      FStyler.OnFetch := @FetchSheet;
    end;
    FStyler.Clear;
    if ClientWidth>0 then FStyler.Media.Width := ClientWidth else FStyler.Media.Width := 1024;
    if ClientHeight>0 then FStyler.Media.Height := ClientHeight else FStyler.Media.Height := 768;
    FStyler.Media.Dark := GetActiveColorScheme=icsDark;
    { the page's colors stand for the system ones a page names }
    FStyler.CanvasColor := Cardinal(ColorToRGB(Color)) or $FF000000;
    FStyler.CanvasTextColor := Cardinal(ColorToRGB(Font.Color)) or $FF000000;
    if FStyleSheet.Count>0 then FStyler.AddSheet(FStyleSheet.Text,FLocation);
    FStyler.AddDocumentSheets(FDocument,FLocation);
    FStyler.Compute(FDocument);
    FStyled := True;
  end;
  Result := FStyler.StyleOf(ANode);
end;
function TInkCustomPage.ExplainStyle(ANode: TInkNode): TStringList;
begin
  if ComputedStyle(ANode)<>nil then Result := FStyler.Explain(ANode)
  else Result := TStringList.Create;
end;
procedure TInkCustomPage.DocumentChanged;
begin
  if FDocument=nil then Exit;
  FSource := InkSerializeHTML(FDocument);
  FTextFormat := itfHTML;
  FKeepDocument := True;
  Reread;
end;
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
      (Ext='.bmp') or (Ext='.ico') or (Ext='.webp') then
      { a picture on its own is a page with just the picture, as in a
        browser }
      NewSource := '<html><head><title>'+HTMLEscape(Copy(PageURL,LastDelimiter('/',PageURL)+1,MaxInt))+
        '</title></head><body><img src="'+
        StringReplace(HTMLEscape(PageURL),'"','&quot;',[rfReplaceAll])+'" alt=""></body></html>'
    else
      NewSource := InkDecodeHTML(ReadText(PageURL));
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

function TInkCustomPage.MenuBlockText(AIndex: Integer): string;
begin
  Result := TidyCopy(BlockText(AIndex));
end;

function TInkCustomPage.PlainText: string;
var I: Integer; B: TInkPageBlock;
begin
  Result := '';
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if I>0 then Result := Result + BlockJoint(I);
    if B.Marker<>'' then Result := Result + B.Marker + ' ';
    Result := Result + TidyCopy(HTMLPlainText(B.Source));
  end;
  if FBlocks.Count>0 then Result := Result + LineEnding;
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
{ B.ImageSrc decoded into B: a still picture from the cache when it was
  decoded before, an animated GIF or WebP with a decoder of its own }
procedure TInkCustomPage.LoadPicture(B: TInkPageBlock);
var I: Integer; ImageData: TMemoryStream; ImageHeader: RawByteString; Cached: TPicture;
begin
  { a picture used again is decoded once: the same file twenty times on a
    page, or the page read again after DocumentChanged }
  I := FImageCache.IndexOf(B.ImageSrc);
  if I>=0 then begin B.Picture.Assign(TPicture(FImageCache.Objects[I])); Exit end;
  ImageData := TMemoryStream.Create;
  try
    try
      if ReadResource(B.ImageSrc,ImageData) then
      begin
        SetLength(ImageHeader, Min(12, ImageData.Size));
        ImageData.Position := 0;
        if ImageHeader <> '' then ImageData.ReadBuffer(ImageHeader[1], Length(ImageHeader));
        ImageData.Position := 0;
        if InkIsWebP(ImageHeader) then
        begin
          B.WebP := TInkWebP.Create(ImageData);
          if B.WebP.Decoded then B.Picture.Assign(B.WebP.Bitmap)
          else FreeAndNil(B.WebP);
        end
        else B.Picture.LoadFromStream(ImageData);
        if B.Picture.Graphic is TGIFImage then
        begin
          B.Animation := TInkGIF.Create(ImageData);
          B.Picture.Assign(B.Animation.Bitmap);
        end;
      end;
    except on E: Exception do B.Picture.Clear end;
  finally ImageData.Free end;
  { a still picture only: a moving one keeps its own frame }
  if (B.Picture.Graphic<>nil) and (B.WebP=nil) and (B.Animation=nil) then
  begin
    Cached := TPicture.Create;
    Cached.Assign(B.Picture);
    FImageCache.AddObject(B.ImageSrc,Cached);
  end;
end;
procedure TInkCustomPage.Parse;
var S: string; I: Integer;
begin
  BeginDocument;
  if FImageCacheFor<>FLocation then
  begin
    FImageCache.Clear; FImageCacheFor := FLocation;
  end;
  if FTextFormat=itfMarkdown then
  begin
    if FMarkdownRawHTML then S := MarkdownToHTML(FSource,[imoRawHTML])
    else if FMarkdownInlineHTML then S := MarkdownToHTML(FSource,[imoInlineHTML])
    else S := MarkdownToHTML(FSource);
  end
  else if FTextFormat=itfPlain then
    { the text as written, one line per line; runs of spaces still collapse
      the way a page's text does }
    S := '<html><body>'+StringReplace(StringReplace(HTMLEscape(FSource),
      #13,'',[rfReplaceAll]),#10,'<br>',[rfReplaceAll])+'</body></html>'
  else S := FSource;
  { the tree a browser would build - which is where implied ends,
    misnested tags and stray table text get mended.  The styles go with the
    tree they were worked out for; a tree its program changed may have lost
    nodes, which are not touched again }
  if FStyler<>nil then FStyler.Release(not FKeepDocument);
  FStyled := False;
  if FKeepDocument and (FDocument<>nil) then FKeepDocument := False
  else
  begin
    FreeAndNil(FDocument);
    FDocument := InkParseHTML(S);
  end;
  TreeStyle(TreeViewWidth);
  FCanvasBack := TreeCanvasBack;
  FPageSection := AddSection(FDocument,False);
  FTitle := FDocument.Title;
  if FTitle='' then
    for I := 0 to FBlocks.Count-1 do
      if IsHeadingTag(TInkPageBlock(FBlocks[I]).Tag) and (TInkPageBlock(FBlocks[I]).Source<>'') then
      begin
        FTitle := Trim(HTMLPlainText(TInkPageBlock(FBlocks[I]).Source));
        Break;
      end;
  FindAnimations;
  FScroll.Position := 0; InvalidateLayout(0);
end;
function TInkCustomPage.Animating: Boolean;
begin Result := FTimer.Enabled end;
procedure TInkCustomPage.FindAnimations;
var I: Integer; B: TInkPageBlock;
begin
  FAnimated.Clear;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    if Assigned(B.WebP) or Assigned(B.Animation) then FAnimated.Add(B);
  end;
  { a page of still pictures has no reason to wake up fifty times a second }
  FTimer.Enabled := FAnimated.Count>0;
end;
function TInkCustomPage.Options: THTMLOptions;
var Link: TColor;
begin
  Result := DefaultHTMLOptions;
  { a link is a blue that reads on its background: dark blue on a light
    page, light blue on a dark one.  A document's links wear their CSS. }
  if HTMLContrastColor(FCanvasBack)=clWhite then
    Link := RGBToColor($58,$A6,$FF)
  else
    Link := RGBToColor($09,$69,$DA);
  Result.LinkColor := Link;
  Result.LinkUnderline := True;
end;
procedure TInkCustomPage.BlockFont(ACanvas: TCanvas; B: TInkPageBlock);
begin
  ACanvas.Font.Assign(Font); HTMLFontSize(ACanvas,B.PointSize); ACanvas.Font.Color := B.TextColor;
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
  Track := ColorToRGB(FCanvasBack);
  TextColor := ColorToRGB(Font.Color);
  if PageStyle(True)<>nil then TextColor := ColorToRGB(InkToColor(PageStyle(True).Color('color'),Track));
  Thumb := RGBToColor((Red(Track)+Red(TextColor)) div 2,
    (Green(Track)+Green(TextColor)) div 2,(Blue(Track)+Blue(TextColor)) div 2);
  { Root declarations take priority. Body is a native-viewer convenience
    fallback, not browser viewport propagation. }
  Colors := PageValue('scrollbar-color');
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
  SizeValue := LowerCase(PageValue('scrollbar-width'));
  NewWidth := Scale96ToFont(18);
  if SizeValue='thin' then NewWidth := Scale96ToFont(10)
  else if SizeValue='none' then NewWidth := 0;
  if FScrollBars=issNone then NewWidth := 0;
  FScroll.Visible := NewWidth>0;
  FScroll.Width := NewWidth;
end;
procedure TInkCustomPage.SetScrollBars(AValue: TInkScrollBarStyle);
begin
  if FScrollBars=AValue then Exit;
  FScrollBars := AValue;
  StyleScrollBar;
  InvalidateLayout(0);
end;
function TInkCustomPage.GetActiveColorScheme: TInkColorScheme;
var C: TColor; L: Integer;
begin
  Result := FColorScheme;
  if Result<>icsAuto then Exit;
  { the application's say first, then the control's own background: light
    when its luminance is at least half.  No widgetset is asked anything -
    a dark desktop theme reaches here as a dark clWindow. }
  if InkAppColorScheme<>icsAuto then Exit(InkAppColorScheme);
  C := Color;
  if C=clDefault then C := clWindow;
  C := ColorToRGB(C);
  L := (299*Red(C)+587*Green(C)+114*Blue(C)) div 1000;
  if L>=128 then Result := icsLight else Result := icsDark;
end;
procedure TInkCustomPage.Reread;
var Keep: Integer;
begin
  Keep := ScrollY;
  Parse; Layout;
  FScroll.Position := Keep;
end;
procedure TInkCustomPage.SetColorScheme(AValue: TInkColorScheme);
begin
  if FColorScheme=AValue then Exit;
  FColorScheme := AValue;
  if (FSource<>'') and (GetActiveColorScheme<>FSchemeApplied) then Reread;
end;
procedure TInkCustomPage.RecheckColorScheme;
begin
  if (FSource<>'') and (GetActiveColorScheme<>FSchemeApplied) then Reread;
end;
procedure TInkCustomPage.CMColorChanged(var Message: TLMessage);
begin
  inherited;
  { the background is the canvas the documents are styled against, and on
    icsAuto it decides the scheme too: they are read again }
  if FStyler<>nil then Reread;
end;
procedure TInkCustomPage.LayoutColumn(out ALeft, AWidth: Integer);
begin
  ALeft := 0;
  AWidth := TreeViewWidth;
end;
procedure TInkCustomPage.StyleBlock(B: TInkPageBlock);
var C: TColor;
begin
  B.PointSize := -Max(1,FLayoutBase);
  C := Font.Color;
  if C=clDefault then C := clWindowText;
  B.TextColor := C;
end;
procedure TInkCustomPage.StyleSection(S: TInkTreeSection);
begin
end;
{ a line of markup at Y, wrapped to the column }
procedure TInkCustomPage.LayLine(B: TInkPageBlock; ALeft, AWidth: Integer;
  var Y, Pending: Integer; var O: THTMLOptions);
var TextW: Integer; Sz: TSize;
begin
  B.RunsReady := False;
  StyleBlock(B);
  { margins collapse: the larger of the two, not both }
  Inc(Y,Max(Pending,B.GapBefore)); Pending := 0;
  BlockFont(Canvas,B);
  O.LineHeight := B.LineHeight;
  O.NoWrap := B.NoWrap;
  B.MarkerWidth := 0; B.CodeHead := 0;
  TextW := Max(20,AWidth-B.Indent-B.Padding*2);
  if B.NoWrap then B.Wrapped := B.Source
  else B.Wrapped := HTMLWordWrap(Canvas,B.Source,TextW,O.SuperSubScriptRatio,O.Scale);
  Sz := HTMLTextExtentOpt(Canvas,Rect(0,0,TextW,0),[],B.Wrapped,O);
  B.Bounds := Rect(ALeft+B.Indent,Y,ALeft+AWidth,Y+Sz.cy+B.Padding*2);
  B.TextBounds := Rect(B.Bounds.Left+B.Padding,B.Bounds.Top+B.Padding,
    B.Bounds.Right-B.Padding,B.Bounds.Bottom-B.Padding);
  B.ImageRect := B.Bounds;
  Inc(Y,Sz.cy+B.Padding*2); Pending := B.GapAfter;
end;
procedure TInkCustomPage.Layout;
var I,Y,W,ColLeft,Start,Pending: Integer; O: THTMLOptions; It: TObject;
begin
  if not FLayoutDirty then Exit;
  W := TreeViewWidth;
  { a width across one of the page's @media queries styles it again }
  if (FPageSection<>nil) and (FStyler<>nil) and (FStyler.MediaKey(W)<>FTreeKey) then
  begin
    Parse;
  end;
  FLayoutDirty := False;
  StyleScrollBar;
  LayoutColumn(ColLeft,W);
  FLayoutBase := ControlFontPixels;
  { the shades a code block's header takes from the page }
  FBodyText := Font.Color;
  FCodeBack := HTMLShadeColor(FCanvasBack,7);
  { only the items from FLayoutFrom on, unless the column changed }
  Start := FLayoutFrom;
  if (W<>FColumnWidth) or (ColLeft<>FColumnLeft) or (FLayoutWidth<>ClientWidth) then Start := 0;
  Start := Min(Start,FItems.Count);
  FLayoutFrom := MaxInt;
  FColumnLeft := ColLeft; FColumnWidth := W; FLayoutWidth := ClientWidth;
  Pending := 0;
  Y := 0;
  if Start>0 then
  begin
    It := TObject(FItems[Start-1]);
    if It is TInkTreeSection then
    begin
      Y := TInkTreeSection(It).Top+TInkTreeSection(It).Height;
      Pending := TInkTreeSection(It).GapAfter;
    end
    else
    begin
      Y := TInkPageBlock(It).Bounds.Bottom;
      Pending := TInkPageBlock(It).GapAfter;
    end;
  end;
  O := Options;
  for I := Start to FItems.Count-1 do
  begin
    It := TObject(FItems[I]);
    if It is TInkTreeSection then LaySection(TInkTreeSection(It),ColLeft,W,Y,Pending)
    else LayLine(TInkPageBlock(It),ColLeft,W,Y,Pending,O);
  end;
  { the last item's own bottom margin still ends the page }
  Inc(Y,Pending);
  FContentHeight := Y;
  FScroll.SetParams(Min(FScroll.Position,Max(0,Y-ClientHeight)),0,Max(ClientHeight,Y),Max(1,ClientHeight));
  TreePaintOrder;
end;
{ ---------------------------------------------------------- code blocks }

const
  CODE_COPIED_MS = 1500;

procedure TInkCustomPage.SetCodeHeader(AValue: Boolean);
begin
  if FCodeHeader=AValue then Exit;
  FCodeHeader := AValue; InvalidateLayout(0); Invalidate;
end;

procedure TInkCustomPage.SetCodeFoldLines(AValue: Integer);
var I: Integer;
begin
  AValue := Max(0,AValue);
  if FCodeFoldLines=AValue then Exit;
  FCodeFoldLines := AValue;
  { every block decides again under the new rule }
  for I := 0 to FBlocks.Count-1 do TInkPageBlock(FBlocks[I]).CodeFoldSet := False;
  InvalidateLayout(0); Invalidate;
end;

function TInkCustomPage.GetCodeActions: TStrings;
begin Result := FCodeActions end;

procedure TInkCustomPage.SetCodeActions(AValue: TStrings);
begin FCodeActions.Assign(AValue) end;

procedure TInkCustomPage.CodeActionsChanged(Sender: TObject);
begin Invalidate end;

{ "Copied" has had its moment: back to "Copy" }
procedure TInkCustomPage.CodeTimerTick(Sender: TObject);
begin FCodeTimer.Enabled := False; Invalidate end;

{ the header's words: the control's own font, a little smaller than the page }
procedure TInkCustomPage.CodeHeadFont(ACanvas: TCanvas);
begin
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Height := -Max(8,Round(Max(8,FLayoutBase)*0.85));
  ACanvas.Font.Style := [];
end;

function TInkCustomPage.CodeButtons(ABlock: Integer): TInkCodeButtons;
var B: TInkPageBlock; X, Gap, PadX, I, CopyW: Integer;
  procedure Add(AKind, AAction: Integer; const ACaption: string; AWidth: Integer);
  var W: Integer;
  begin
    W := AWidth+PadX*2;
    Dec(X,W);
    SetLength(Result,Length(Result)+1);
    Result[High(Result)].Kind := AKind;
    Result[High(Result)].Action := AAction;
    Result[High(Result)].Caption := ACaption;
    Result[High(Result)].R := Rect(X,B.Bounds.Top+Gap,X+W,B.Bounds.Top+B.CodeHead-Gap);
    Dec(X,Gap);
  end;
begin
  Result := nil;
  Layout;
  if (ABlock<0) or (ABlock>=FBlocks.Count) then Exit;
  B := TInkPageBlock(FBlocks[ABlock]);
  if B.CodeHead<=0 then Exit;
  CodeHeadFont(Canvas);
  Gap := Max(2,B.CodeHead div 7);
  PadX := Max(4,Canvas.TextWidth('n'));
  X := B.Bounds.Right-Gap;
  { right to left: Copy, which keeps its width when it says Copied, then
    the host's buttons, then the fold }
  CopyW := Max(Canvas.TextWidth('Copy'),Canvas.TextWidth('Copied'));
  if (B.CodeCopiedAt>0) and (GetTickCount64-B.CodeCopiedAt<CODE_COPIED_MS) then
    Add(2,-1,'Copied',CopyW)
  else
    Add(2,-1,'Copy',CopyW);
  for I := FCodeActions.Count-1 downto 0 do
    Add(1,I,FCodeActions[I],Canvas.TextWidth(FCodeActions[I]));
  if (FCodeFoldLines>0) and (B.CodeLines>FCodeFoldLines) then
    if B.CodeFolded then
      Add(0,-1,Format('Show all %d lines',[B.CodeLines]),
        Canvas.TextWidth(Format('Show all %d lines',[B.CodeLines])))
    else
      Add(0,-1,'Show less',Canvas.TextWidth('Show less'));
end;

procedure TInkCustomPage.FoldCode(ABlock: Integer; AFolded: Boolean);
var B: TInkPageBlock;
begin
  if (ABlock<0) or (ABlock>=FBlocks.Count) then Exit;
  B := TInkPageBlock(FBlocks[ABlock]);
  if B.Code='' then Exit;
  B.CodeFolded := AFolded; B.CodeFoldSet := True;
  InvalidateBlock(ABlock); Invalidate;
end;

function TInkCustomPage.CodeButtonAt(X,Y: Integer; out ABlock, AButton: Integer): Boolean;
var I, K: Integer; Btns: TInkCodeButtons; P: TPoint;
begin
  Result := False; ABlock := -1; AButton := -1;
  if not FCodeHeader then Exit;
  I := BlockAt(X,Y);
  if (I<0) or (TInkPageBlock(FBlocks[I]).CodeHead<=0) then Exit;
  Btns := CodeButtons(I);
  P := Point(X,Y+FScroll.Position);
  for K := 0 to High(Btns) do
    if PtInRect(Btns[K].R,P) then
    begin
      ABlock := I; AButton := K;
      Exit(True);
    end;
end;

procedure TInkCustomPage.PressCodeButton(ABlock, AButton: Integer);
var Btns: TInkCodeButtons; B: TInkPageBlock;
begin
  Btns := CodeButtons(ABlock);
  if (AButton<0) or (AButton>High(Btns)) then Exit;
  B := TInkPageBlock(FBlocks[ABlock]);
  case Btns[AButton].Kind of
    0: FoldCode(ABlock,not B.CodeFolded);
    1: if Assigned(FOnCodeAction) then
         FOnCodeAction(Self,ABlock,FCodeActions[Btns[AButton].Action],B.Code,B.CodeLanguage);
    2: begin
         Clipboard.AsText := B.Code;
         B.CodeCopiedAt := GetTickCount64;
         FCodeTimer.Enabled := False;
         FCodeTimer.Interval := CODE_COPIED_MS+50;
         FCodeTimer.Enabled := True;
         Invalidate;
       end;
  end;
end;

{ A code block's header: a shade apart from the code, its language and
  size on the left, its buttons on the right - the hot one lit. }
procedure TInkCustomPage.PaintCodeHead(ACanvas: TCanvas; Index: Integer; B: TInkPageBlock;
  const R: TRect);
var H, BR: TRect; Btns: TInkCodeButtons; I, TY: Integer; HeadBack, HeadFore: TColor; Lang: string;
  Hot: Boolean;
begin
  Btns := CodeButtons(Index);
  H := Rect(R.Left,R.Top,R.Right,R.Top+B.CodeHead);
  HeadBack := B.BackColor; if HeadBack=clNone then HeadBack := FCodeBack;
  HeadFore := B.TextColor; if HeadFore=clNone then HeadFore := FBodyText;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := MixColor(HeadBack,HeadFore,0.07);
  ACanvas.FillRect(H);
  CodeHeadFont(ACanvas);
  TY := H.Top+(B.CodeHead-ACanvas.TextHeight('Ag')) div 2;
  ACanvas.Brush.Style := bsClear;
  Lang := B.CodeLanguage;
  if Lang='' then Lang := 'code';
  if B.CodeLines=1 then Lang := Lang+'  -  1 line'
  else Lang := Lang+'  -  '+IntToStr(B.CodeLines)+' lines';
  ACanvas.Font.Color := MixColor(HeadFore,HeadBack,0.45);
  ACanvas.TextOut(H.Left+Max(B.Padding,Scale96ToFont(8)),TY,Lang);
  for I := 0 to High(Btns) do
  begin
    BR := Btns[I].R; OffsetRect(BR,0,-FScroll.Position);
    Hot := (Index=FCodeHotBlock) and (I=FCodeHotButton);
    if Hot then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := MixColor(HeadBack,HeadFore,0.2);
      ACanvas.FillRect(BR);
      ACanvas.Brush.Style := bsClear;
      ACanvas.Font.Color := HeadFore;
    end
    else
      ACanvas.Font.Color := MixColor(HeadFore,HeadBack,0.25);
    ACanvas.TextOut(BR.Left+(BR.Right-BR.Left-ACanvas.TextWidth(Btns[I].Caption)) div 2,
      TY,Btns[I].Caption);
  end;
  ACanvas.Brush.Style := bsClear;
end;

{ the first block that can show with the page scrolled to ATop: blocks are
  laid out top to bottom, so a binary search finds it - and one before it,
  whose band or quote bar may reach down into view }
procedure TInkCustomPage.Paint;
begin RenderTo(Canvas); FLastPaint := GetTickCount64 end;
{ one block: its band, then its words, marker, picture, selection and
  code header }
procedure TInkCustomPage.PaintBlock(ACanvas: TCanvas; I: Integer; ASelected: Boolean;
  const SelFrom, SelTo: TInkPagePosition);
var B: TInkPageBlock; R,TR,Clip: TRect; O: THTMLOptions;
begin
  B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
  BlockFont(ACanvas,B);
  if B.BackColor<>clNone then
  begin
    ACanvas.Brush.Color := B.BackColor; ACanvas.Brush.Style := bsSolid;
    ACanvas.FillRect(R);
  end;
  ACanvas.Brush.Style := bsClear;
  if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) then
  begin
    R := B.ImageRect; OffsetRect(R,0,-FScroll.Position);
    if Assigned(B.WebP) then ACanvas.StretchDraw(R,B.WebP.Bitmap)
    else ACanvas.StretchDraw(R,B.Picture.Graphic);
    Exit;
  end;
  TR := B.TextBounds; OffsetRect(TR,0,-FScroll.Position);
  { the marker on the first line's baseline: drawn with the block's own
    line height, as its words are }
  O := BlockOptions(I);
  if (B.Marker<>'') and not (B.Tree and TreePaintMarker(ACanvas,B,TR)) then
    HTMLDrawOpt(ACanvas,Rect(TR.Left-B.MarkerWidth,TR.Top,TR.Left,TR.Bottom),[],
      HTMLEscape(B.Marker),O,FRenderCache);
  { nothing that draws text depends on what the last thing to draw left
    behind: the marker's own draw is a draw like any other }
  ACanvas.Brush.Style := bsClear;
  if B.NoWrap or FPaintClipped then
  begin
    { a long line of code is cut off at the block's edge, not wrapped; and
      a block in a box that clips is cut at that too.  Set on the canvas,
      not saved and restored: GTK3's RestoreDC fails once the fonts have
      changed in between }
    if B.NoWrap then Clip := R else Clip := Rect(-MaxInt div 2,-MaxInt div 2,MaxInt div 2,MaxInt div 2);
    if FPaintClipped then IntersectRect(Clip,Clip,FPaintClip);
    ACanvas.ClipRect := Clip; ACanvas.Clipping := True;
    try
      HTMLDrawOpt(ACanvas,TR,[],B.Wrapped,O,FRenderCache);
      if ASelected and (I>=SelFrom.Block) and (I<=SelTo.Block) then
        PaintSelection(ACanvas,I,B,SelFrom,SelTo);
    finally ACanvas.Clipping := False end;
  end
  else
  begin
    HTMLDrawOpt(ACanvas,TR,[],B.Wrapped,O,FRenderCache);
    if ASelected and (I>=SelFrom.Block) and (I<=SelTo.Block) then
      PaintSelection(ACanvas,I,B,SelFrom,SelTo);
  end;
  if B.CodeHead>0 then PaintCodeHead(ACanvas,I,B,R);
end;
procedure TInkCustomPage.RenderTo(ACanvas: TCanvas);
begin
  TreeRender(ACanvas);
end;
procedure TInkCustomPage.Resize;
begin
  inherited;
  { a picture fitted to the window is measured again at the new size }
  if (FImageFit=iifWindow) and (FPageSection<>nil) then Reread
  else InvalidateLayout(0);
  PlaceFindBar;
end;
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
    AHit := HTMLHitTest(Canvas,R,B.Wrapped,BlockOptions(I),X,Y,FRenderCache);
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
var B, CI: Integer; Hit: THTMLHitInfo; Info: TInkLinkInfo; Blk: TInkPageBlock;
begin
  if CanFocus then SetFocus;
  if CodeButtonAt(X,Y,B,CI) then
  begin
    PressCodeButton(B,CI);
    Exit;
  end;
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
var P, WordFrom, WordTo: TInkPagePosition; Now_: QWord; Near: Boolean; CB, CI: Integer;
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
  { a code block's own button is pressed, not selected through; a finger's
    tap reaches it through ClickAt }
  if not InkMouseIsTouch and CodeButtonAt(X,Y,CB,CI) then
  begin
    PressCodeButton(CB,CI);
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
var I,Fold,CB,CI: Integer; B: TInkPageBlock; OnText: Boolean; R: TRect; Tip: string;
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
  { a code block's button lights under the pointer }
  if CodeButtonAt(X,Y,CB,CI) then
  begin
    if (CB<>FCodeHotBlock) or (CI<>FCodeHotButton) then
    begin
      FCodeHotBlock := CB; FCodeHotButton := CI; Invalidate;
    end;
    Cursor := crHandPoint;
    Exit;
  end
  else if FCodeHotBlock>=0 then
  begin
    FCodeHotBlock := -1; FCodeHotButton := -1; Invalidate;
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
    FontName := AFont.Name; FontStyle := AFont.Style;
    { pixels when the font carries them, points otherwise - the same
      convention the renderer and TFont itself use }
    if AFont.Height<>0 then FontSize := AFont.Height else FontSize := AFont.Size;
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
  { the options it is drawn with, so the runs are where the words are }
  O := BlockOptions(B.Index);
  O.OnRun := @CollectRun; O.RunPart := 0;
  FRunBlock := B;
  try
    { the same layout the block is drawn with, measured instead of painted }
    HTMLMeasureAndHit(Canvas,B.TextBounds,B.Wrapped,O,-1,-1,W,H,Hit,FRenderCache);
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
  HTMLFontSize(ACanvas,R.FontSize);
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
begin
  Layout;
  Result := TreeBlockAt(X,Y+FScroll.Position,False);
end;

function TInkCustomPage.PositionAt(X,Y: Integer): TInkPagePosition;
var I,K,DocY,Best,BestDY,BestDX,DY,DX,Prev,W,Len: Integer; B: TInkPageBlock; R: TInkPageRun;
begin
  Layout;
  Result.Block := 0; Result.Offset := 0;
  if FBlocks.Count=0 then Exit;
  DocY := Y+FScroll.Position;
  { the block, or the one after the gap the point is in }
  I := Max(0,TreeBlockAt(X,DocY,True));
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

function TInkCustomPage.StepChar(const P: TInkPagePosition; ADelta: Integer): TInkPagePosition;
var Words: string;
begin
  Result := Clamp(P);
  Words := BlockText(Result.Block);
  if ADelta>0 then
  begin
    if Result.Offset<Length(Words) then
      Inc(Result.Offset,Max(1,UTF8CodepointSize(@Words[Result.Offset+1])))
    else if Result.Block<FBlocks.Count-1 then
    begin Inc(Result.Block); Result.Offset := 0 end;
  end
  else
  begin
    if Result.Offset>0 then
    begin
      Dec(Result.Offset);
      while (Result.Offset>0) and ((Ord(Words[Result.Offset+1]) and $C0)=$80) do Dec(Result.Offset);
    end
    else if Result.Block>0 then
    begin Dec(Result.Block); Result.Offset := Length(BlockText(Result.Block)) end;
  end;
end;

function TInkCustomPage.CaretLineHeight(const P: TInkPagePosition): Integer;
var B: TInkPageBlock; K,Found: Integer;
begin
  B := TInkPageBlock(FBlocks[P.Block]);
  PrepareRuns(B);
  Found := -1;
  for K := 0 to B.RunCount-1 do
  begin
    if B.Runs[K].Start>P.Offset then Break;
    Found := K;
    if P.Offset<B.Runs[K].Start+Length(B.Runs[K].Text) then Break;
  end;
  if Found>=0 then Result := B.Runs[Found].LineHeight
  else Result := Max(12,B.Bounds.Bottom-B.Bounds.Top);
end;

{ Shift with an arrow extends the selection from its caret end, the way a
  browser's find-and-select does: by a character sideways, by a line up and
  down, to the line's ends with Home and End, by a page with PgUp and PgDn.
  There is no blinking caret; the selection's moving end is the caret. }
procedure TInkCustomPage.ExtendByKey(Key: Word);
var P,P2: TInkPagePosition; Pt: TPoint; LH: Integer; B: TInkPageBlock; K,Found,A,Z: Integer;
begin
  Layout;
  if FBlocks.Count=0 then Exit;
  P := Clamp(FSelCaret);
  case Key of
    VK_LEFT: P := StepChar(P,-1);
    VK_RIGHT: P := StepChar(P,1);
    VK_HOME, VK_END:
      begin
        B := TInkPageBlock(FBlocks[P.Block]);
        PrepareRuns(B);
        Found := -1;
        for K := 0 to B.RunCount-1 do
        begin
          if B.Runs[K].Start>P.Offset then Break;
          Found := K;
          if P.Offset<B.Runs[K].Start+Length(B.Runs[K].Text) then Break;
        end;
        if Found<0 then
        begin
          if Key=VK_HOME then P.Offset := 0 else P.Offset := Length(B.Words);
        end
        else
        begin
          A := Found; Z := Found;
          while (A>0) and (B.Runs[A-1].Line=B.Runs[Found].Line) and
            (B.Runs[A-1].Part=B.Runs[Found].Part) do Dec(A);
          while (Z<B.RunCount-1) and (B.Runs[Z+1].Line=B.Runs[Found].Line) and
            (B.Runs[Z+1].Part=B.Runs[Found].Part) do Inc(Z);
          if Key=VK_HOME then P.Offset := B.Runs[A].Start
          else P.Offset := B.Runs[Z].Start+Length(B.Runs[Z].Text);
        end;
      end;
  else
    begin
      Pt := PositionPoint(P);
      LH := CaretLineHeight(P);
      case Key of
        VK_UP: Pt.Y := Pt.Y-2;
        VK_DOWN: Pt.Y := Pt.Y+LH+1;
        VK_PRIOR: Pt.Y := Pt.Y-Max(LH+1,ClientHeight-LH);
        VK_NEXT: Pt.Y := Pt.Y+Max(LH+1,ClientHeight-LH);
      end;
      P2 := PositionAt(Pt.X,Pt.Y);
      { a line move that went nowhere was at the edge of its block: step
        over the gap to the neighbor }
      if (ComparePositions(P2,P)=0) and (Key=VK_UP) and (P.Block>0) then
        P2 := PositionAt(Pt.X,TInkPageBlock(FBlocks[P.Block-1]).Bounds.Bottom-1-FScroll.Position)
      else if (ComparePositions(P2,P)=0) and (Key=VK_DOWN) and (P.Block<FBlocks.Count-1) then
        P2 := PositionAt(Pt.X,TInkPageBlock(FBlocks[P.Block+1]).Bounds.Top+1-FScroll.Position);
      P := P2;
    end;
  end;
  FSelCaret := Clamp(P);
  SelectionChanged;
  ScrollIntoView(FSelCaret);
  if HasSelection then
    { X11's other clipboard: what is selected is ready for a middle click }
    Clipboard(ctPrimarySelection).AsText := SelectedText;
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
      if I>SelFrom.Block then Result := Result+BlockJoint(I);
      Continue;
    end;
    Part := TidyCopy(Copy(B.Words,A+1,Z-A));
    if (A=0) and (B.Marker<>'') then Part := B.Marker+' '+Part;
    if I>SelFrom.Block then Result := Result+BlockJoint(I);
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
var PageBack: TColor; PS: TInkStyle;
begin
  PageBack := FCanvasBack;
  if FSelectionColor<>clDefault then Result := FSelectionColor
  else Result := MixColor(PageBack,clHighlight,0.45);
  { a page's ::selection rule }
  if (FStyler<>nil) and (FDocument<>nil) and (FDocument.Body<>nil) and
    (FStyler.StyleOf(FDocument.Body)<>nil) then
  begin
    PS := FStyler.PseudoStyleOf(FDocument.Body,'selection');
    if (PS<>nil) and ((PS.Color('background-color') shr 24)>0) then
      Result := InkToColor(PS.Color('background-color'),PageBack);
  end;
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
    Texts.Block := MenuBlockText(I);
    Texts.BlockCaption := CopyBlockCaption(I);
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
  { forty pixels a notch, and a fast wheel's fractions in proportion }
  FScroll.Position := EnsureRange(FScroll.Position+InkWheelPixels(WheelDelta,40,FWheelRest),
    0,Max(0,FContentHeight-ClientHeight));
  KeepPainting;
  Result := True;
end;
{ GTK draws only once input stops, and a wheel spun hard sends events for a
  second or more: meanwhile, a frame at least every 33 ms }
procedure TInkCustomPage.KeepPainting;
begin
  if GetTickCount64-FLastPaint>=33 then Update;
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
  if (Shift*[ssAlt,ssCtrl,ssShift]=[ssShift]) and
    (Key in [VK_LEFT,VK_RIGHT,VK_UP,VK_DOWN,VK_HOME,VK_END,VK_PRIOR,VK_NEXT]) then
  begin
    ExtendByKey(Key);
    Key := 0; Exit;
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
  { a block's size is negative when it is pixels; either way its magnitude
    is the line's scale }
  PlaceBottom := P.Y+Max(Abs(B.PointSize)*2,16);
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
  PageBack := FCanvasBack;
  Fore := Font.Color;
  if PageStyle(True)<>nil then Fore := InkToColor(PageStyle(True).Color('color'),PageBack);
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

{$I inkpagetree.inc}

end.
