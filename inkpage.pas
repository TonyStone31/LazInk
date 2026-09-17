{ Native scrolling HTML help viewer; no browser engine. Component code: MIT. }
unit InkPage;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, StdCtrls, Graphics, Types, InkHtml, InkMarkdown, InkCSS, InkGIF, ExtCtrls, InkScrollBar;
type
  TInkPageLinkEvent = procedure(Sender: TObject; const URL: string) of object;
  { Applications may supply remote/cached content here. Return True on success. }
  TInkPageResourceEvent = procedure(Sender: TObject; const URL: string;
    Destination: TStream; var Handled: Boolean) of object;
  TInkPageBlock = class
  public
    Source, Wrapped, Anchor, Tag, CSSClass: string;
    Picture: TPicture;
    Animation: TInkGIF;
    Bounds: TRect;
    Indent, PointSize, Padding, GapBefore, GapAfter: Integer;
    BorderColor: TColor;
    TextColor, BackColor: TColor;
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
    FLayoutDirty: Boolean;
    FContentHeight: Integer;
    FOnLinkClick: TInkPageLinkEvent;
    FOnResource: TInkPageResourceEvent;
    { dragging the page, which is how a finger scrolls: on Windows a touch
      screen delivers a finger as a mouse press, moves and a release, and a
      page with only a wheel and a scrollbar cannot be moved by one }
    FDragScroll, FGrab, FDragged: Boolean;
    FGrabY, FGrabAt: Integer;
    function GetScrollY: Integer;
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
  protected
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
    procedure RenderTo(ACanvas: TCanvas);
    function PlainText: string;
    function ImageCount: Integer;
    procedure Back;
    procedure Forward;
    procedure ScrollTo(Y: Integer);
    procedure JumpToAnchor(const Anchor: string);
    function ResolveURL(const Reference: string): string;
    property Location: string read FLocation;
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
    property OnLinkClick: TInkPageLinkEvent read FOnLinkClick write FOnLinkClick;
    property OnResource: TInkPageResourceEvent read FOnResource write FOnResource;
    { drag the page with the left button - or a finger - to scroll it; a
      press that moves less than a few pixels is still a click }
    property DragScroll: Boolean read FDragScroll write FDragScroll default True;
    property Align; property Anchors; property Color; property Font;
    property ParentFont; property TabStop; property TabOrder; property Visible;
  end;
implementation
uses Math, URIParser, LCLType, LazUTF8, Forms;

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
function TagName(const Tag: string): string;
var P,Q: Integer;
begin
  P := 2; if (P<=Length(Tag)) and (Tag[P]='/') then Inc(P);
  Q := P; while (P<=Length(Tag)) and (Tag[P] in ['a'..'z','A'..'Z','0'..'9']) do Inc(P);
  Result := LowerCase(Copy(Tag,Q,P-Q));
end;
function TextMarkup(const S: string): string;
var P,Q,N: Integer; E,T: string; Space: Boolean;
begin
  T := ''; P := 1; Space := False;
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
        else if E='uarr' then E := '↑'
        else if E='darr' then E := '↓'
        else if E='larr' then E := '←'
        else if E='rarr' then E := '→'
        else if E='ndash' then E := '–'
        else if E='mdash' then E := '—'
        else if E='hellip' then E := '…'
        else E := HTMLUnescape('&'+E+';');
        T := T + E; P := Q+1; Space := False; Continue;
      end;
    end;
    if S[P] in [' ',#9,#10,#13] then
    begin if not Space then T := T+' '; Space := True end
    else begin T := T+S[P]; Space := False end;
    Inc(P);
  end;
  Result := HTMLEscape(T);
end;
constructor TInkPageBlock.Create;
begin inherited; Picture := TPicture.Create end;
destructor TInkPageBlock.Destroy;
begin Animation.Free; Picture.Free; inherited end;
constructor TInkPage.Create(AOwner: TComponent);
begin
  inherited; Width := 640; Height := 480; TabStop := True;
  FBlocks := TList.Create; FStyles := TInkStyleSheet.Create;
  FHistory := TStringList.Create; FHistoryIndex := -1;
  FScroll := TInkScrollBar.Create(Self); FScroll.Parent := Self;
  FScroll.Align := alRight; FScroll.Width := 18;
  FScroll.OnChange := @ScrollChanged; FLayoutDirty := True;
  FTimer := TTimer.Create(Self); FTimer.Interval := 20; FTimer.OnTimer := @Animate;
  FDragScroll := True;
  Color := clWindow; Font.Color := clWindowText; Font.Size := 11;
end;
destructor TInkPage.Destroy;
begin FTimer.Enabled := False; ClearBlocks; FBlocks.Free; FStyles.Free; FHistory.Free; inherited end;
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
begin FLocation := BaseURL; FSource := HTML; Parse end;
procedure TInkPage.LoadFromFile(const FileName: string);
begin Navigate(FilenameToURI(ExpandFileName(FileName)),True) end;
procedure TInkPage.LoadFromURL(const URL: string);
begin Navigate(ResolveURL(URL),True) end;
procedure TInkPage.Navigate(const URL: string; AddHistory: Boolean);
var P: Integer; PageURL,Anchor,NewSource: string;
begin
  PageURL := URL; Anchor := ''; P := Pos('#',PageURL);
  if P>0 then begin Anchor := Copy(PageURL,P+1,MaxInt); Delete(PageURL,P,MaxInt) end;
  if PageURL<>FLocation then
  begin
    NewSource := ReadText(PageURL);
    FLocation := PageURL; FSource := NewSource; Parse;
  end;
  if Anchor<>'' then JumpToAnchor(Anchor) else FScroll.Position := 0;
  if AddHistory then
  begin
    while FHistory.Count>FHistoryIndex+1 do FHistory.Delete(FHistory.Count-1);
    FHistory.Add(URL); FHistoryIndex := FHistory.Count-1;
  end;
end;
function TInkPage.PlainText: string;
var I: Integer;
begin
  Result := '';
  for I := 0 to FBlocks.Count-1 do
    Result := Result + HTMLPlainText(TInkPageBlock(FBlocks[I]).Source) + LineEnding;
end;
function TInkPage.ImageCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FBlocks.Count-1 do
    if TInkPageBlock(FBlocks[I]).Picture.Graphic<>nil then Inc(Result);
end;
procedure TInkPage.Back;
begin if FHistoryIndex>0 then begin Navigate(FHistory[FHistoryIndex-1],False); Dec(FHistoryIndex) end end;
procedure TInkPage.Forward;
begin if FHistoryIndex+1<FHistory.Count then begin Navigate(FHistory[FHistoryIndex+1],False); Inc(FHistoryIndex) end end;
procedure TInkPage.Parse;
var
  S, Raw, Element, Cls, Buffer, BlockTag, BlockClass, PendingAnchor, Prefix, URL: string;
  P,Q,I,Level,TableDepth,SkipDepth: Integer;
  Closing: Boolean;
  B: TInkPageBlock;
  ImageData: TMemoryStream;
  Lists: array of Integer;
  procedure Flush;
  begin
    if (Trim(Buffer)='') and (PendingAnchor='') then Exit;
    B := TInkPageBlock.Create;
    B.Source := Trim(Buffer); B.Tag := BlockTag; B.CSSClass := BlockClass;
    B.Anchor := PendingAnchor; B.Indent := Length(Lists)*18;
    FBlocks.Add(B); Buffer := ''; PendingAnchor := '';
  end;
  function InlineTag: string;
  var Target, BG: string; C: TColor;
  begin
    Result := '';
    if Closing then Prefix := '/' else Prefix := '';
    if (Element='b') or (Element='strong') then Exit('<'+Prefix+'b>');
    if (Element='i') or (Element='em') then Exit('<'+Prefix+'i>');
    if (Element='u') or (Element='s') or (Element='sup') or (Element='sub') then Exit('<'+Prefix+Element+'>');
    if Element='br' then Exit('<br>');
    if Element='a' then
    begin
      if Closing then Exit('</a>');
      Target := StringReplace(HTMLEscape(Attribute(Raw,'href')),'"','&quot;',[rfReplaceAll]);
      Exit('<a href="'+Target+'">');
    end;
    if (Element='code') or (Element='kbd') then
    begin
      if Closing then Exit('</font>');
      BG := ''; C := FStyles.Color(Element,Cls,'background',clNone);
      if C<>clNone then
      begin
        C := ColorToRGB(C);
        BG := Format(' bgcolor="#%.2x%.2x%.2x"',[Red(C),Green(C),Blue(C)]);
      end;
      Exit('<font face="monospace"'+BG+'>');
    end;
    if Element='font' then Exit(Raw);
  end;
begin
  if FBlocks=nil then Exit;
  ClearBlocks; FStyles.Clear; FTitle := ''; FHoverLink := ''; Cursor := crDefault;
  S := InkToHTML(FSource,FTextFormat);
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
  P := 1; Buffer := ''; BlockTag := 'p'; BlockClass := '';
  PendingAnchor := ''; TableDepth := 0; SkipDepth := 0; SetLength(Lists,0);
  while P<=Length(S) do
  begin
    if S[P]<>'<' then
    begin
      Q := P; while (P<=Length(S)) and (S[P]<>'<') do Inc(P);
      if SkipDepth=0 then Buffer := Buffer+TextMarkup(Copy(S,Q,P-Q));
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
    if not Closing and (Attribute(Raw,'id')<>'') then
    begin Flush; PendingAnchor := Attribute(Raw,'id') end;
    if Element='table' then
    begin
      if Closing then
      begin
        Buffer := Buffer+'</table>'; Dec(TableDepth);
        if TableDepth=0 then begin Flush; BlockTag := 'p'; BlockClass := '' end;
      end
      else begin Flush; BlockTag := 'table'; BlockClass := Cls; Inc(TableDepth); Buffer := '<table>' end;
      Continue;
    end;
    if TableDepth>0 then
    begin
      if (Element='tr') or (Element='td') or (Element='th') then
      begin
        if Closing then Prefix := '/' else Prefix := '';
        Buffer := Buffer+'<'+Prefix+Element+'>';
      end
      else if (Element='p') and Closing then Buffer := Buffer+'<br>'
      else Buffer := Buffer+InlineTag;
      Continue;
    end;
    if (Element='ul') or (Element='ol') then
    begin
      Flush;
      if Closing then begin if Length(Lists)>0 then SetLength(Lists,Length(Lists)-1) end
      else begin Level := Length(Lists); SetLength(Lists,Level+1); if Element='ol' then Lists[Level] := 1 else Lists[Level] := 0 end;
      Continue;
    end;
    if Element='img' then
    begin
      Flush; B := TInkPageBlock.Create; B.Tag := 'img'; B.Source := Attribute(Raw,'alt');
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
      ((Length(Element)=2) and (Element[1]='h') and (Element[2] in ['1'..'6'])) then
    begin
      Flush;
      if Closing then begin BlockTag := 'p'; BlockClass := '' end
      else
      begin
        BlockTag := Element; BlockClass := Cls;
        if Element='li' then
        begin
          Level := High(Lists);
          if (Level>=0) and (Lists[Level]>0) then begin Buffer := IntToStr(Lists[Level])+'. '; Inc(Lists[Level]) end
          else Buffer := '• ';
        end;
      end;
      Continue;
    end;
    Buffer := Buffer+InlineTag;
  end;
  Flush; FScroll.Position := 0; FLayoutDirty := True; Invalidate;
end;
function TInkPage.Options: THTMLOptions;
begin
  Result := DefaultHTMLOptions;
  Result.LinkColor := FStyles.Color('a','','color',clBlue);
  Result.LinkUnderline := True;
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
var I,Y,W,BlockLeft,MaxWidth,ImageH,K: Integer; BorderSpec: string; B: TInkPageBlock; Sz: TSize; O: THTMLOptions;
begin
  if not FLayoutDirty then Exit;
  FLayoutDirty := False; Y := 24;
  MaxWidth := FStyles.Pixels('div','wrap','max-width',820);
  StyleScrollBar;
  W := Max(40,Min(ClientWidth-FScroll.Width-40,MaxWidth));
  BlockLeft := Max(20,(ClientWidth-FScroll.Width-W) div 2);
  O := Options;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    B.PointSize := Font.Size;
    if B.PointSize<=0 then B.PointSize := 11;
    if B.Tag='h1' then B.PointSize := 21 else if B.Tag='h2' then B.PointSize := 15;
    B.PointSize := Max(1,FStyles.Pixels(B.Tag,B.CSSClass,'font-size',B.PointSize*4 div 3)*3 div 4);
    B.TextColor := FStyles.Color(B.Tag,B.CSSClass,'color',FStyles.Color('body','','color',Font.Color));
    B.Padding := Max(0,FStyles.Pixels(B.Tag,B.CSSClass,'padding',6));
    B.GapBefore := Max(0,FStyles.Pixels(B.Tag,B.CSSClass,'margin-top',0));
    B.GapAfter := Max(0,FStyles.Pixels(B.Tag,B.CSSClass,'margin-bottom',12));
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
    B.BackColor := FStyles.Color(B.Tag,B.CSSClass,'background',clNone);
    Canvas.Font.Assign(Font); Canvas.Font.Size := B.PointSize; Canvas.Font.Color := B.TextColor;
    if Copy(B.Tag,1,1)='h' then Canvas.Font.Style := Canvas.Font.Style+[fsBold];
    if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) then
    begin
      ImageH := Max(1,Round(B.Picture.Height * Min(W,B.Picture.Width)/B.Picture.Width));
      Sz.cx := Min(W,B.Picture.Width); Sz.cy := ImageH;
      B.Wrapped := '';
    end
    else
    begin
      B.Wrapped := HTMLWordWrap(Canvas,B.Source,Max(20,W-B.Indent-B.Padding*2),0.7);
      Sz := HTMLTextExtentOpt(Canvas,Rect(0,0,Max(20,W-B.Indent-B.Padding*2),0),[],B.Wrapped,O);
    end;
    B.Bounds := Rect(BlockLeft+B.Indent,Y,BlockLeft+W,Y+Sz.cy+B.Padding*2);
    Inc(Y,Sz.cy+B.Padding*2+B.GapAfter);
  end;
  FContentHeight := Y;
  FScroll.SetParams(Min(FScroll.Position,Max(0,Y-ClientHeight)),0,Max(ClientHeight,Y),Max(1,ClientHeight));
end;
procedure TInkPage.Paint;
begin RenderTo(Canvas) end;
procedure TInkPage.RenderTo(ACanvas: TCanvas);
var I: Integer; B: TInkPageBlock; R: TRect; O: THTMLOptions;
begin
  Layout;
  ACanvas.Brush.Color := FStyles.Color('body','','background',Color); ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(ClientRect); O := Options;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
    if (R.Bottom<0) or (R.Top>ClientHeight) then Continue;
    ACanvas.Font.Assign(Font); ACanvas.Font.Size := B.PointSize; ACanvas.Font.Color := B.TextColor;
    if Copy(B.Tag,1,1)='h' then ACanvas.Font.Style := ACanvas.Font.Style+[fsBold];
    if B.BackColor<>clNone then begin ACanvas.Brush.Color := B.BackColor; ACanvas.Brush.Style := bsSolid; ACanvas.FillRect(R) end;
    ACanvas.Brush.Style := bsClear;
    if B.BorderColor<>clNone then begin ACanvas.Pen.Color := B.BorderColor; ACanvas.Rectangle(R) end;
    if (B.Picture.Graphic<>nil) and (B.Picture.Width>0) then
    begin
      R.Right := R.Left+Min(R.Right-R.Left,B.Picture.Width); Dec(R.Bottom,B.Padding*2);
      ACanvas.StretchDraw(R,B.Picture.Graphic);
    end
    else begin Inc(R.Left,B.Padding); Inc(R.Top,B.Padding); Dec(R.Right,B.Padding); HTMLDrawOpt(ACanvas,R,[],B.Wrapped,O) end;
  end;
  if FScroll.Visible then
    FScroll.RenderTo(ACanvas,Rect(ClientWidth-FScroll.Width,0,ClientWidth,ClientHeight));
end;
procedure TInkPage.Resize;
begin inherited; FLayoutDirty := True; Invalidate end;
procedure TInkPage.FontChanged(Sender: TObject);
begin inherited; FLayoutDirty := True; Invalidate end;
function TInkPage.HitLink(X,Y: Integer): string;
var I: Integer; B: TInkPageBlock; R: TRect; Hit: THTMLHitInfo;
begin
  Result := ''; Layout;
  for I := 0 to FBlocks.Count-1 do
  begin
    B := TInkPageBlock(FBlocks[I]); R := B.Bounds; OffsetRect(R,0,-FScroll.Position);
    if not PtInRect(R,Point(X,Y)) then Continue;
    Canvas.Font.Assign(Font); Canvas.Font.Size := B.PointSize; Canvas.Font.Color := B.TextColor;
    if Copy(B.Tag,1,1)='h' then Canvas.Font.Style := Canvas.Font.Style+[fsBold];
    Inc(R.Left,B.Padding); Inc(R.Top,B.Padding); Dec(R.Right,B.Padding);
    Hit := HTMLHitTest(Canvas,R,B.Wrapped,Options,X,Y);
    if Hit.OnLink then Exit(ResolveURL(HTMLUnescape(Hit.LinkName)));
  end;
end;
function TInkPage.GetScrollY: Integer;
begin
  Result := FScroll.Position;
end;

procedure TInkPage.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if (Button<>mbLeft) or not FDragScroll then Exit;
  FGrab := True; FDragged := False; FGrabY := Y; FGrabAt := FScroll.Position;
end;

procedure TInkPage.MouseMove(Shift: TShiftState; X,Y: Integer);
const
  { A press that wanders less than this is still a click.  Wider than a
    mouse needs, because a fingertip rolls a little as it taps, and a tap on
    a link that scrolled the page by three pixels instead would read as the
    link being dead. }
  SLOP = 8;
begin
  inherited;
  if FGrab and (FDragged or (Abs(Y-FGrabY)>SLOP)) then
  begin
    { the page follows the finger: drag down and the words come down }
    FDragged := True;
    FScroll.Position := EnsureRange(FGrabAt-(Y-FGrabY),0,Max(0,FContentHeight-ClientHeight));
    Exit;
  end;
  FHoverLink := HitLink(X,Y);
  if FHoverLink<>'' then Cursor := crHandPoint else Cursor := crDefault;
end;

procedure TInkPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var URL: string; WasDrag: Boolean;
begin
  inherited;
  if Button<>mbLeft then Exit;
  WasDrag := FDragged; FGrab := False; FDragged := False;
  SetFocus;
  { a drag that happened to end over a link was a scroll, not a click }
  if WasDrag then Exit;
  URL := HitLink(X,Y); if URL='' then Exit;
  if Assigned(FOnLinkClick) then FOnLinkClick(Self,URL) else LoadFromURL(URL);
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
    if B.Anchor=Anchor then begin FScroll.Position := Min(B.Bounds.Top,Max(0,FContentHeight-ClientHeight)); Exit end;
  end;
end;
end.
