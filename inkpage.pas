{ Native scrolling HTML help viewer; no browser engine. Component code: MIT. }
unit InkPage;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, StdCtrls, Graphics, Types, Menus, InkHtml, InkMarkdown, InkCSS, InkGIF, ExtCtrls, InkScrollBar, InkTouch, InkCopyMenu, InkEdit;
type
  TInkPageLinkEvent = procedure(Sender: TObject; const URL: string) of object;
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
  TInkPageBlock = class
  public
    Source, Wrapped, Tag, CSSClass: string;
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
    { the block, and the part of it the words are drawn in; page coordinates }
    Bounds, TextBounds: TRect;
    Indent, PointSize, Padding, GapBefore, GapAfter, MarkerWidth: Integer;
    { code: whitespace kept, the fixed face, never wrapped - a long line is
      cut off at the block's edge }
    Pre: Boolean;
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
  TInkPage = class(TCustomControl)
  private
    FBlocks: TList;
    FStyles: TInkStyleSheet;
    FScroll: TInkScrollBar;
    FTimer: TTimer;
    procedure Animate(Sender: TObject);
  private
    FSource, FLocation, FTitle, FHoverLink: string;
    FHistory: TStringList;
    FHistoryIndex: Integer;
    FTextFormat: TInkTextFormat;
    FStyleSheet: TStringList;
    FMarkdownRawHTML: Boolean;
    FLayoutDirty: Boolean;
    FContentHeight, FColumnLeft: Integer;
    FOnLinkClick: TInkPageLinkEvent;
    FOnResource: TInkPageResourceEvent;
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
    procedure ClearBlocks;
    procedure Parse;
    procedure Layout;
    procedure StyleScrollBar;
    procedure ScrollChanged(Sender: TObject);
    procedure SetTextFormat(AValue: TInkTextFormat);
    procedure SetSource(const AValue: string);
    function ReadResource(const URL: string; Destination: TStream): Boolean;
    function ReadText(const URL: string): string;
    procedure Navigate(const URL: string; AddHistory: Boolean);
    function HitLink(X,Y: Integer): string;
    function Options: THTMLOptions;
    procedure BlockFont(ACanvas: TCanvas; B: TInkPageBlock);
  protected
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
    { Through the pages visited by links and LoadFromFile / LoadFromURL.
      The mouse's back and forward buttons, Alt+Left / Alt+Right and a
      keyboard's Back / Forward keys do the same. }
    procedure Back;
    procedure Forward;
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
    { The page's own scrollbar, drawn by LazInk and coloured from the page's
      CSS: scrollbar-color (thumb, then track) and scrollbar-width (auto,
      thin or none), read from html or :root, falling back to body.  Without
      them the track is the page background and the thumb sits halfway
      between that and the text colour. }
    property ScrollBar: TInkScrollBar read FScroll;
  published
    property Source: string read FSource write SetSource;
    property TextFormat: TInkTextFormat read FTextFormat write SetTextFormat default itfHTML;
    { CSS applied to every page before the page's own styles - how a program
      dresses a Markdown document, which has no stylesheet, in its theme.
      A page's own rules win over these where both say something. }
    property StyleSheet: TStrings read GetStyleSheet write SetStyleSheet;
    { HTML written inside a Markdown source is drawn as HTML, not shown as
      text.  Only for documents you trust. }
    property MarkdownRawHTML: Boolean read FMarkdownRawHTML write SetMarkdownRawHTML default False;
    property OnLinkClick: TInkPageLinkEvent read FOnLinkClick write FOnLinkClick;
    property OnResource: TInkPageResourceEvent read FOnResource write FOnResource;
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
    property PopupMenu;
    property Align; property Anchors; property Color; property Font;
    property ParentFont; property TabStop; property TabOrder; property Visible;
  end;
implementation
uses Math, URIParser, LCLType, LCLIntf, LazUTF8, Forms, Clipbrd;

type
  { a list, a quote or a definition the parser is inside }
  TPageContainer = record
    Kind: Char;
    Counter: Integer;
    Style: string;
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
function TextMarkup(const S: string; Collapse: Boolean = True): string;
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
  Result := HTMLEscape(T);
  if not Collapse then Result := StringReplace(Result,#10,'<br>',[rfReplaceAll]);
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
begin inherited; Picture := TPicture.Create end;
destructor TInkPageBlock.Destroy;
begin Animation.Free; Picture.Free; inherited end;
constructor TInkPage.Create(AOwner: TComponent);
begin
  inherited; Width := 640; Height := 480; TabStop := True;
  FBlocks := TList.Create; FStyles := TInkStyleSheet.Create;
  FStyleSheet := TStringList.Create; FStyleSheet.OnChange := @StyleSheetChanged;
  FHistory := TStringList.Create; FHistoryIndex := -1;
  FScroll := TInkScrollBar.Create(Self); FScroll.Parent := Self;
  FScroll.Align := alRight; FScroll.Width := 18;
  FScroll.OnChange := @ScrollChanged; FLayoutDirty := True;
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
destructor TInkPage.Destroy;
begin
  FTimer.Enabled := False; FFlickTimer.Enabled := False; FAutoScroll.Enabled := False; ClearBlocks; FBlocks.Free; FStyles.Free; FHistory.Free;
  FStyleSheet.OnChange := nil; FStyleSheet.Free;
  inherited;
end;
procedure TInkPage.ClearBlocks;
var I: Integer;
begin for I := 0 to FBlocks.Count-1 do TObject(FBlocks[I]).Free; FBlocks.Clear end;
procedure TInkPage.Animate(Sender: TObject);
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
procedure TInkPage.ScrollChanged(Sender: TObject);
begin Invalidate end;
procedure TInkPage.SetTextFormat(AValue: TInkTextFormat);
begin if FTextFormat=AValue then Exit; FTextFormat := AValue; Parse end;
procedure TInkPage.SetSource(const AValue: string);
begin FSource := AValue; Parse end;
function TInkPage.GetStyleSheet: TStrings;
begin Result := FStyleSheet end;
procedure TInkPage.SetStyleSheet(AValue: TStrings);
begin FStyleSheet.Assign(AValue) end;
procedure TInkPage.StyleSheetChanged(Sender: TObject);
begin Parse end;
procedure TInkPage.SetMarkdownRawHTML(AValue: Boolean);
begin
  if FMarkdownRawHTML=AValue then Exit;
  FMarkdownRawHTML := AValue;
  if FTextFormat=itfMarkdown then Parse;
end;
function TInkPage.ResolveURL(const Reference: string): string;
begin
  if not ResolveRelativeURI(FLocation,Reference,Result) then Result := Reference;
end;
function TInkPage.ReadResource(const URL: string; Destination: TStream): Boolean;
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
function TInkPage.ReadText(const URL: string): string;
var S: TStringStream;
begin
  S := TStringStream.Create('');
  try
    if not ReadResource(URL,S) then raise EReadError.Create('Cannot load '+URL);
    Result := S.DataString;
  finally S.Free end;
end;
procedure TInkPage.LoadHTML(const HTML: string; const BaseURL: string);
begin FLocation := BaseURL; FSource := HTML; FTextFormat := itfHTML; Parse; Navigated end;
procedure TInkPage.LoadMarkdown(const Markdown: string; const BaseURL: string);
begin FLocation := BaseURL; FSource := Markdown; FTextFormat := itfMarkdown; Parse; Navigated end;
procedure TInkPage.Navigated;
begin
  if Assigned(FOnNavigate) then FOnNavigate(Self);
end;
function TInkPage.GetCanGoBack: Boolean;
begin Result := FHistoryIndex>0 end;
function TInkPage.GetCanGoForward: Boolean;
begin Result := FHistoryIndex+1<FHistory.Count end;
procedure TInkPage.LoadFromFile(const FileName: string);
begin Navigate(FilenameToURI(ExpandFileName(FileName)),True) end;
procedure TInkPage.LoadFromURL(const URL: string);
begin Navigate(ResolveURL(URL),True) end;
procedure TInkPage.Navigate(const URL: string; AddHistory: Boolean);
var P: Integer; PageURL,Anchor,NewSource,Ext: string;
begin
  PageURL := URL; Anchor := ''; P := Pos('#',PageURL);
  if P>0 then begin Anchor := Copy(PageURL,P+1,MaxInt); Delete(PageURL,P,MaxInt) end;
  if PageURL<>FLocation then
  begin
    NewSource := ReadText(PageURL);
    FLocation := PageURL; FSource := NewSource;
    { a .md file is Markdown, whatever the page before it was }
    Ext := LowerCase(ExtractFileExt(PageURL));
    if (Ext='.md') or (Ext='.markdown') then FTextFormat := itfMarkdown
    else if (Ext='.html') or (Ext='.htm') then FTextFormat := itfHTML;
    Parse;
  end;
  if Anchor<>'' then JumpToAnchor(Anchor) else FScroll.Position := 0;
  if AddHistory then
  begin
    while FHistory.Count>FHistoryIndex+1 do FHistory.Delete(FHistory.Count-1);
    FHistory.Add(URL); FHistoryIndex := FHistory.Count-1;
  end;
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

function TInkPage.PlainText: string;
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
function TInkPage.ImageCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FBlocks.Count-1 do
    if TInkPageBlock(FBlocks[I]).Picture.Graphic<>nil then Inc(Result);
end;
function TInkPage.BlockCount: Integer;
begin Result := FBlocks.Count end;
function TInkPage.Block(Index: Integer): TInkPageBlock;
begin Layout; Result := TInkPageBlock(FBlocks[Index]) end;
procedure TInkPage.Back;
begin
  if FHistoryIndex<=0 then Exit;
  Dec(FHistoryIndex);
  Navigate(FHistory[FHistoryIndex],False);
end;
procedure TInkPage.Forward;
begin
  if FHistoryIndex+1>=FHistory.Count then Exit;
  Inc(FHistoryIndex);
  Navigate(FHistory[FHistoryIndex],False);
end;
procedure TInkPage.Parse;
var
  S, Raw, Element, Cls, Buffer, BlockTag, BlockClass, PendingAnchor, PendingMarker,
    Prefix, URL, Nest, Box, Kind: string;
  P,Q,I,Level,TableDepth,SkipDepth,PreDepth,Depth: Integer;
  Closing: Boolean;
  B: TInkPageBlock;
  ImageData: TMemoryStream;
  Containers: array of TPageContainer;
  CodeBack, PageBack: TColor;
  procedure Flush;
  var Text: string;
  begin
    Text := Buffer;
    if BlockTag='pre' then
    begin
      { the line break that ends the last line of code is not another line }
      Text := TrimRight(Text);
      while Copy(Text,Length(Text)-3,4)='<br>' do Text := TrimRight(Copy(Text,1,Length(Text)-4));
    end
    else Text := Trim(Text);
    { an id with nothing yet to show waits for the block that has }
    if Text='' then begin Buffer := ''; Exit end;
    B := TInkPageBlock.Create;
    B.Source := Text; B.Tag := BlockTag; B.CSSClass := BlockClass;
    B.Anchor := PendingAnchor; B.Nest := Nest; B.Pre := BlockTag='pre';
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
  function CellAlign: string;
  var A: string;
  begin
    A := LowerCase(Attribute(Raw,'align'));
    if A='' then
    begin
      A := LowerCase(StringReplace(Attribute(Raw,'style'),' ','',[rfReplaceAll]));
      if Pos('text-align:center',A)>0 then A := 'center'
      else if Pos('text-align:right',A)>0 then A := 'right';
    end;
    if A='center' then Result := '<center>'
    else if A='right' then Result := '<right>'
    else Result := '';
  end;
  function InlineTag: string;
  var BG, FG: string; C: TColor;
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
      if Closing then Exit('</a>');
      if Attribute(Raw,'href')='' then Exit;
      Result := StringReplace(HTMLEscape(Attribute(Raw,'href')),'"','&quot;',[rfReplaceAll]);
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
    if Element='mark' then
    begin
      if Closing then Exit('</font>');
      Exit('<font bgcolor="'+ColorAttr(FStyles.Color('mark',Cls,'background',RGBToColor($FF,$F3,$A0)))+'">');
    end;
    if Element='font' then Exit(Raw);
  end;
begin
  if FBlocks=nil then Exit;
  ClearBlocks; FStyles.Clear; FTitle := ''; FHoverLink := '';
  FSelecting := False;
  if HasSelection then
  begin
    FSelAnchor.Block := 0; FSelAnchor.Offset := 0; FSelCaret := FSelAnchor;
    if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
  end;
  if FTextFormat=itfMarkdown then
  begin
    if FMarkdownRawHTML then S := MarkdownToHTML(FSource,[imoRawHTML])
    else S := MarkdownToHTML(FSource);
  end
  else S := FSource;
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
  { code with no background of its own gets a shade of the page's, so it
    still reads as code }
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  CodeBack := HTMLShadeColor(PageBack,7);
  P := 1; Buffer := ''; BlockTag := 'p'; BlockClass := ''; Nest := '';
  PendingAnchor := ''; PendingMarker := ''; TableDepth := 0; SkipDepth := 0; PreDepth := 0;
  SetLength(Containers,0);
  while P<=Length(S) do
  begin
    if S[P]<>'<' then
    begin
      Q := P; while (P<=Length(S)) and (S[P]<>'<') do Inc(P);
      if SkipDepth=0 then Buffer := Buffer+TextMarkup(Copy(S,Q,P-Q),PreDepth=0);
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
    if (Element='head') or (Element='script') or (Element='style') then
    begin
      if Closing then SkipDepth := Max(0,SkipDepth-1) else Inc(SkipDepth);
      Continue;
    end;
    if SkipDepth>0 then Continue;
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
      else begin Flush; BlockTag := 'table'; BlockClass := Cls; Inc(TableDepth); Buffer := '<table>' end;
      Continue;
    end;
    if TableDepth>0 then
    begin
      if (Element='tr') or (Element='td') or (Element='th') then
      begin
        if Closing then Buffer := Buffer+'</'+Element+'>'
        else if Element='tr' then Buffer := Buffer+'<tr>'
        else Buffer := Buffer+'<'+Element+'>'+CellAlign;
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
      if (P<=Length(S)) and (S[P]=#10) then Inc(P);
      Continue;
    end;
    if PreDepth>0 then
    begin
      Buffer := Buffer+InlineTag;
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
      if B.Picture.Graphic=nil then B.Source := '[Image: '+HTMLEscape(B.Source)+']';
      FBlocks.Add(B); Continue;
    end;
    if (Element='p') or (Element='div') or (Element='header') or (Element='footer') or
      (Element='nav') or (Element='figure') or (Element='figcaption') or (Element='li') or
      (Element='section') or (Element='article') or (Element='main') or (Element='aside') or
      (Element='address') or (Element='details') or (Element='summary') or (Element='dt') or
      IsHeadingTag(Element) then
    begin
      Flush;
      if Closing then begin BlockTag := ContainerTag; BlockClass := '' end
      else
      begin
        BlockTag := Element; BlockClass := Cls;
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
  Flush;
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
  FScroll.Position := 0; FLayoutDirty := True; Invalidate;
end;
function TInkPage.Options: THTMLOptions;
var Link: TColor;
begin
  Result := DefaultHTMLOptions;
  { without a colour from the page, a link is a blue that reads on its
    background: dark blue on a light page, light blue on a dark one }
  if HTMLContrastColor(FStyles.Color('body','','background',
    FStyles.Color('body','','background-color',Color)))=clWhite then
    Link := RGBToColor($58,$A6,$FF)
  else
    Link := RGBToColor($09,$69,$DA);
  Result.LinkColor := FStyles.Color('a','','color',Link);
  Result.LinkUnderline := True;
end;
procedure TInkPage.BlockFont(ACanvas: TCanvas; B: TInkPageBlock);
begin
  ACanvas.Font.Assign(Font); ACanvas.Font.Size := B.PointSize; ACanvas.Font.Color := B.TextColor;
  if B.Bold then ACanvas.Font.Style := ACanvas.Font.Style+[fsBold];
  if B.FaceName<>'' then ACanvas.Font.Name := B.FaceName;
end;
procedure TInkPage.StyleScrollBar;
var Track,Thumb,TextColor,C1,C2: TColor; Colors,SizeValue: string;
  Tokens: TStringList; P,Q,Depth,NewWidth: Integer;
  { #rgb, #rrggbb, a colour name, currentcolor, or rgb()/rgba() with the
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
procedure TInkPage.Layout;
var I,J,X,Y,W,BlockLeft,MaxWidth,ImageH,K,Base,ListW,QuoteW,TextW,Thick: Integer;
  BorderSpec: string; B: TInkPageBlock; Sz: TSize; O: THTMLOptions;
  BodyText, PageBack, QuoteText, BarColor, CodeBack: TColor;
  function Defaulted(const Prop: string; Fallback: Integer): Integer;
  begin
    Result := Max(0,FStyles.Pixels(B.Tag,B.CSSClass,Prop,Fallback));
  end;
begin
  if not FLayoutDirty then Exit;
  FLayoutDirty := False; Y := 24;
  MaxWidth := FStyles.Pixels('div','wrap','max-width',820);
  StyleScrollBar;
  W := Max(40,Min(ClientWidth-FScroll.Width-40,MaxWidth));
  BlockLeft := Max(20,(ClientWidth-FScroll.Width-W) div 2);
  FColumnLeft := BlockLeft;
  O := Options;
  Base := Font.Size;
  if Base<=0 then Base := 11;
  { a list's indent is room for its markers; a quote's, room for its bar }
  Canvas.Font.Assign(Font); Canvas.Font.Size := Base;
  ListW := Max(Scale96ToFont(24),Canvas.TextWidth('00. '));
  QuoteW := Scale96ToFont(18);
  BodyText := FStyles.Color('body','','color',Font.Color);
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  QuoteText := FStyles.Color('blockquote','','color',MixColor(BodyText,PageBack,0.3));
  BarColor := FStyles.Color('blockquote','','border-color',MixColor(BodyText,PageBack,0.6));
  CodeBack := FStyles.Color('code','','background',
    FStyles.Color('code','','background-color',HTMLShadeColor(PageBack,7)));
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    B.RunsReady := False;
    X := 0; SetLength(B.Bars,0);
    for J := 1 to Length(B.Nest) do
      if B.Nest[J]='q' then
      begin
        SetLength(B.Bars,Length(B.Bars)+1); B.Bars[High(B.Bars)] := X; Inc(X,QuoteW);
      end
      else Inc(X,ListW);
    B.Indent := X;
    B.PointSize := Base;
    if B.Tag='h1' then B.PointSize := Round(Base*1.9)
    else if B.Tag='h2' then B.PointSize := Round(Base*1.36)
    else if B.Tag='h3' then B.PointSize := Round(Base*1.15)
    else if (B.Tag='h5') or (B.Tag='h6') then B.PointSize := Max(1,Round(Base*0.9));
    B.PointSize := Max(1,FStyles.Pixels(B.Tag,B.CSSClass,'font-size',B.PointSize*4 div 3)*3 div 4);
    B.Bold := IsHeadingTag(B.Tag) or (B.Tag='dt') or (B.Tag='summary');
    if B.Pre then B.FaceName := InkMonoFace else B.FaceName := '';
    if Length(B.Bars)>0 then
      B.TextColor := FStyles.Color(B.Tag,B.CSSClass,'color',QuoteText)
    else
      B.TextColor := FStyles.Color(B.Tag,B.CSSClass,'color',BodyText);
    if B.Pre then B.Padding := Defaulted('padding',10)
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
    begin
      B.BorderColor := HTMLStringToColor(FStyles.Resolve(BorderSpec),clNone);
    end;
    Inc(Y,B.GapBefore);
    B.BackColor := FStyles.Color(B.Tag,B.CSSClass,'background',
      FStyles.Color(B.Tag,B.CSSClass,'background-color',clNone));
    if B.Pre and (B.BackColor=clNone) then B.BackColor := CodeBack;
    B.BarColor := BarColor;
    BlockFont(Canvas,B);
    B.MarkerWidth := 0;
    if B.Tag='hr' then
    begin
      { a rule: its colour from color, border-color or background, in
        that order, and a line two pixels thick }
      B.BarColor := FStyles.Color('hr',B.CSSClass,'color',
        FStyles.Color('hr',B.CSSClass,'border-color',
        FStyles.Color('hr',B.CSSClass,'background',MixColor(BodyText,PageBack,0.7))));
      Thick := Max(1,Scale96ToFont(2));
      Sz.cx := W-B.Indent; Sz.cy := Thick;
      B.Wrapped := '';
    end
    else if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) then
    begin
      TextW := W-B.Indent;
      ImageH := Max(1,Round(B.Picture.Height * Min(TextW,B.Picture.Width)/B.Picture.Width));
      Sz.cx := Min(TextW,B.Picture.Width); Sz.cy := ImageH;
      B.Wrapped := '';
    end
    else
    begin
      if B.Marker<>'' then
        B.MarkerWidth := Canvas.TextWidth(B.Marker+' ');
      TextW := Max(20,W-B.Indent-B.Padding*2);
      if B.Pre then
      begin
        B.Wrapped := B.Source;
        Sz := HTMLTextExtentOpt(Canvas,Rect(0,0,TextW,0),[],B.Wrapped,O);
      end
      else
      begin
        B.Wrapped := HTMLWordWrap(Canvas,B.Source,TextW,0.7);
        Sz := HTMLTextExtentOpt(Canvas,Rect(0,0,TextW,0),[],B.Wrapped,O);
      end;
    end;
    B.Bounds := Rect(BlockLeft+B.Indent,Y,BlockLeft+W,Y+Sz.cy+B.Padding*2);
    B.TextBounds := Rect(B.Bounds.Left+B.Padding,B.Bounds.Top+B.Padding,
      B.Bounds.Right-B.Padding,B.Bounds.Bottom-B.Padding);
    Inc(Y,Sz.cy+B.Padding*2+B.GapAfter);
  end;
  FContentHeight := Y;
  FScroll.SetParams(Min(FScroll.Position,Max(0,Y-ClientHeight)),0,Max(ClientHeight,Y),Max(1,ClientHeight));
end;
procedure TInkPage.Paint;
begin RenderTo(Canvas) end;
procedure TInkPage.RenderTo(ACanvas: TCanvas);
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
      R.Right := R.Left+Min(R.Right-R.Left,B.Picture.Width); Dec(R.Bottom,B.Padding*2);
      ACanvas.StretchDraw(R,B.Picture.Graphic);
      Continue;
    end;
    TR := B.TextBounds; OffsetRect(TR,0,-FScroll.Position);
    if B.Marker<>'' then
      HTMLDrawOpt(ACanvas,Rect(TR.Left-B.MarkerWidth,TR.Top,TR.Left,TR.Bottom),[],
        HTMLEscape(B.Marker),O);
    if B.Pre then
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
procedure TInkPage.Resize;
begin inherited; FLayoutDirty := True; PlaceFindBar; Invalidate end;
procedure TInkPage.FontChanged(Sender: TObject);
begin inherited; FLayoutDirty := True; Invalidate end;
function TInkPage.HitLink(X,Y: Integer): string;
var I: Integer; B: TInkPageBlock; R: TRect; Hit: THTMLHitInfo;
begin
  Result := ''; Layout;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
    if not PtInRect(R,Point(X,Y)) or (B.Wrapped='') then Continue;
    BlockFont(Canvas,B);
    R := B.TextBounds; OffsetRect(R,0,-FScroll.Position);
    Hit := HTMLHitTest(Canvas,R,B.Wrapped,Options,X,Y);
    if Hit.OnLink then Exit(ResolveURL(HTMLUnescape(Hit.LinkName)));
  end;
end;
function TInkPage.GetScrollY: Integer;
begin
  Result := FScroll.Position;
end;

procedure TInkPage.CreateWnd;
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

procedure TInkPage.GrabBegin(X,Y: Integer; Finger: Boolean; Time: QWord);
begin
  StopFlick;
  FGrab := True; FDragged := False; FGrabFinger := Finger;
  FGrabY := Y; FGrabAt := FScroll.Position;
  FSampleCount := 0;
  GrabMove(X,Y,Time);
end;

procedure TInkPage.GrabMove(X,Y: Integer; Time: QWord);
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

procedure TInkPage.GrabEnd(X,Y: Integer; Time: QWord);
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

procedure TInkPage.ClickAt(X,Y: Integer);
var URL: string;
begin
  if CanFocus then SetFocus;
  URL := HitLink(X,Y); if URL='' then Exit;
  if Assigned(FOnLinkClick) then FOnLinkClick(Self,URL) else LoadFromURL(URL);
end;

procedure TInkPage.StopFlick;
begin
  FVelocity := 0;
  FFlickTimer.Enabled := False;
end;

function TInkPage.GetFlicking: Boolean;
begin
  Result := FVelocity<>0;
end;

procedure TInkPage.FlickStep(Milliseconds: Integer);
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

procedure TInkPage.FlickTimer(Sender: TObject);
var Now_: QWord;
begin
  Now_ := GetTickCount64;
  FlickStep(Min(100,Integer(Now_-FFlickLast)));
  FFlickLast := Now_;
end;

procedure TInkPage.Touch(Phase: TInkTouchPhase; X,Y: Integer);
begin
  TouchAt(Phase,X,Y,GetTickCount64);
end;

procedure TInkPage.TouchAt(Phase: TInkTouchPhase; X,Y: Integer; Time: QWord);
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

procedure TInkPage.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var P, WordFrom, WordTo: TInkPagePosition;
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
  if ssTriple in Shift then
  begin
    FSelectUnit := 2; FSelMoved := True;
    FUnitFrom.Block := P.Block; FUnitFrom.Offset := 0;
    FUnitTo.Block := P.Block; FUnitTo.Offset := MaxInt;
    Select(FUnitFrom,FUnitTo);
  end
  else if ssDouble in Shift then
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

procedure TInkPage.MouseMove(Shift: TShiftState; X,Y: Integer);
var I: Integer; B: TInkPageBlock; OnText: Boolean; R: TRect;
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
  FHoverLink := HitLink(X,Y);
  if FHoverLink<>'' then Cursor := crHandPoint
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

procedure TInkPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
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

procedure TInkPage.AutoScrollTimer(Sender: TObject);
var Delta: Integer;
begin
  if not FSelecting then begin FAutoScroll.Enabled := False; Exit end;
  if FDragY<0 then Delta := Max(-60,FDragY) div 2 - 4
  else if FDragY>=ClientHeight then Delta := Min(60,FDragY-ClientHeight) div 2 + 4
  else Exit;
  FScroll.Position := EnsureRange(FScroll.Position+Delta,0,Max(0,FContentHeight-ClientHeight));
  ExtendTo(PositionAt(FDragX,EnsureRange(FDragY,0,ClientHeight-1)));
end;

procedure TInkPage.CollectRun(const AText: string; ALeft, ATop, AWidth, AHeight,
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

procedure TInkPage.PrepareRuns(B: TInkPageBlock);
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
    HTMLDrawTextEx3(Canvas,B.TextBounds,[],B.Wrapped,O,htmlHyperLink,-1,-1,W,H,Hit);
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

procedure TInkPage.RunFont(ACanvas: TCanvas; const R: TInkPageRun);
begin
  ACanvas.Font.Name := R.FontName;
  ACanvas.Font.Size := R.FontSize;
  ACanvas.Font.Style := R.FontStyle;
end;

function TInkPage.RunX(const R: TInkPageRun; Offset: Integer): Integer;
var K: Integer;
begin
  K := EnsureRange(Offset-R.Start,0,Length(R.Text));
  if K=0 then Exit(R.Left);
  if K=Length(R.Text) then Exit(R.Left+R.Width);
  RunFont(Canvas,R);
  Result := R.Left+Canvas.TextWidth(Copy(R.Text,1,K));
end;

function TInkPage.BlockAt(X,Y: Integer): Integer;
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

function TInkPage.PositionAt(X,Y: Integer): TInkPagePosition;
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

function TInkPage.PositionPoint(const APosition: TInkPagePosition): TPoint;
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

function TInkPage.BlockText(Index: Integer): string;
begin
  PrepareRuns(TInkPageBlock(FBlocks[Index]));
  Result := TInkPageBlock(FBlocks[Index]).Words;
end;

function TInkPage.Clamp(const P: TInkPagePosition): TInkPagePosition;
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

function TInkPage.WordAt(const P: TInkPagePosition; out AFrom, ATo: TInkPagePosition): Boolean;
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

procedure TInkPage.ExtendTo(const P: TInkPagePosition);
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

procedure TInkPage.SelectionChanged;
begin
  Invalidate;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TInkPage.Select(const AFrom, ATo: TInkPagePosition);
begin
  FSelAnchor := Clamp(AFrom); FSelCaret := Clamp(ATo);
  SelectionChanged;
end;

procedure TInkPage.SelectAll;
begin
  FSelAnchor.Block := 0; FSelAnchor.Offset := 0;
  FSelCaret.Block := Max(0,FBlocks.Count-1); FSelCaret.Offset := MaxInt;
  SelectionChanged;
end;

procedure TInkPage.DoSelectAll(Sender: TObject);
begin
  SelectAll;
end;

procedure TInkPage.ClearSelection;
begin
  if not HasSelection then Exit;
  FSelAnchor := FSelCaret;
  SelectionChanged;
end;

function TInkPage.HasSelection: Boolean;
begin
  Result := (FBlocks<>nil) and (FBlocks.Count>0) and
    (ComparePositions(FSelAnchor,FSelCaret)<>0);
end;

function TInkPage.GetSelectionStart: TInkPagePosition;
begin
  if ComparePositions(FSelAnchor,FSelCaret)<=0 then Result := FSelAnchor else Result := FSelCaret;
end;

function TInkPage.GetSelectionEnd: TInkPagePosition;
begin
  if ComparePositions(FSelAnchor,FSelCaret)<=0 then Result := FSelCaret else Result := FSelAnchor;
end;

function TInkPage.SelectedText: string;
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

function TInkPage.SelectedHTML: string;
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

procedure TInkPage.CopyToClipboard;
begin
  if HasSelection then InkCopyText(SelectedText,SelectedHTML);
end;

function TInkPage.SelectionBackground: TColor;
var PageBack: TColor;
begin
  PageBack := FStyles.Color('body','','background',FStyles.Color('body','','background-color',Color));
  if FSelectionColor<>clDefault then Result := FSelectionColor
  else Result := MixColor(PageBack,clHighlight,0.45);
  Result := HTMLStringToColor(FStyles.RuleValue('::selection','background',
    FStyles.RuleValue('::selection','background-color','')),Result);
end;

procedure TInkPage.SetSelectionColor(AValue: TColor);
begin
  if FSelectionColor=AValue then Exit;
  FSelectionColor := AValue;
  Invalidate;
end;

procedure TInkPage.PaintSelection(ACanvas: TCanvas; Index: Integer; B: TInkPageBlock;
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

function TInkPage.BuildCopyMenu(X,Y: Integer): TPopupMenu;
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
    if (Texts.Block<>'') and (B.Marker<>'') then Texts.Block := B.Marker+' '+Texts.Block;
  end;
  Texts.Link := HitLink(X,Y);
  Texts.All := TrimRight(PlainText);
  Texts.SelectAll := @DoSelectAll;
  FCopyMenuHost.Build(Self,Texts,X,Y,FOnCopyMenu);
  Result := FCopyMenuHost.Menu;
end;

procedure TInkPage.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
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

function TInkPage.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FScroll.Position := EnsureRange(FScroll.Position-WheelDelta div 3,0,Max(0,FContentHeight-ClientHeight));
  Result := True;
end;
procedure TInkPage.KeyDown(var Key: Word; Shift: TShiftState);
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
procedure TInkPage.ScrollTo(Y: Integer);
begin
  Layout; FScroll.Position := EnsureRange(Y,0,Max(0,FContentHeight-ClientHeight));
end;
procedure TInkPage.JumpToAnchor(const Anchor: string);
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

function TInkPage.SearchWords(Index: Integer; AOptions: TInkFindOptions): string;
var Lower: string;
begin
  Result := BlockText(Index);
  if ifoMatchCase in AOptions then Exit;
  { UTF-8 lower case, unless it would change where the characters are }
  Lower := UTF8LowerCase(Result);
  if Length(Lower)=Length(Result) then Result := Lower else Result := LowerCase(Result);
end;

function TInkPage.FindFrom(const AText: string; AOptions: TInkFindOptions;
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

function TInkPage.SelectMatch(const AText: string; AOptions: TInkFindOptions;
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

function TInkPage.FindStart(AOptions: TInkFindOptions): TInkPagePosition;
begin
  if HasSelection then Exit(SelectionStart);
  { nothing selected: from what is on screen }
  if ifoBackwards in AOptions then Result := PositionAt(ClientWidth,ClientHeight-1)
  else Result := PositionAt(0,0);
end;

function TInkPage.Find(const AText: string; AOptions: TInkFindOptions): Boolean;
var From: TInkPagePosition;
begin
  From := FindStart(AOptions);
  { the next match begins after the current one does; the one before,
    before it }
  if HasSelection and not (ifoBackwards in AOptions) then Inc(From.Offset);
  Result := SelectMatch(AText,AOptions,From);
end;

function TInkPage.FindCount(const AText: string; AOptions: TInkFindOptions;
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

procedure TInkPage.ScrollIntoView(const APosition: TInkPagePosition);
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

function TInkPage.GetFindBarVisible: Boolean;
begin
  Result := Assigned(FFindEdit) and FFindEdit.Visible;
end;

function TInkPage.FindBarRect: TRect;
var W, H: Integer;
begin
  H := Scale96ToFont(34);
  W := Min(Scale96ToFont(360),ClientWidth-FScroll.Width-8);
  Result := Rect(ClientWidth-FScroll.Width-W-6,4,ClientWidth-FScroll.Width-6,4+H);
end;

{ 0 previous, 1 next, 2 close }
function TInkPage.FindButtonRect(Index: Integer): TRect;
var Bar: TRect; S: Integer;
begin
  Bar := FindBarRect;
  S := Bar.Bottom-Bar.Top-8;
  Result := Rect(Bar.Right-4-(3-Index)*S,Bar.Top+4,Bar.Right-4-(2-Index)*S,Bar.Bottom-4);
end;

procedure TInkPage.PlaceFindBar;
var Bar: TRect;
begin
  if not Assigned(FFindEdit) then Exit;
  Bar := FindBarRect;
  { the edit, then the count, then the three buttons }
  FFindEdit.SetBounds(Bar.Left+6,Bar.Top+5,
    Max(40,FindButtonRect(0).Left-Bar.Left-6-Scale96ToFont(64)),Bar.Bottom-Bar.Top-10);
end;

procedure TInkPage.ShowFindBar;
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

procedure TInkPage.HideFindBar;
begin
  if not FindBarVisible then Exit;
  FFindEdit.Visible := False;
  if CanFocus then SetFocus;
  Invalidate;
end;

procedure TInkPage.FindEditChange(Sender: TObject);
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

procedure TInkPage.FindEditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
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

procedure TInkPage.PaintFindBar(ACanvas: TCanvas);
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
