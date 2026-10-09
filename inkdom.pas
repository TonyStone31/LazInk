{ InkDOM - an HTML document as a tree: the parser that builds it the way a
  browser does, and the calls a program uses to read and change it.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors

  The parser follows the HTML standard's tree construction closely enough
  that tag soup comes out as a browser would build it: implied <html>,
  <head>, <body> and <tbody>, paragraphs and list items closed by what
  follows them, misnested formatting repaired (the adoption agency),
  stray content in a table moved before it, raw text in <script> and
  <style>.  No scripting, ever: <noscript> is read as ordinary content. }
unit InkDOM;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TInkNodeKind = (inkDocument, inkElement, inkText, inkComment, inkDoctype);
  TInkNamespace = (insHTML, insSVG, insMathML);

  TInkNode = class;
  TInkNodeArray = array of TInkNode;

  TInkAttribute = record
    Name, Value: string;
  end;

  TInkNode = class
  private
    FKind: TInkNodeKind;
    FName: string;
    FData: string;
    FNamespace: TInkNamespace;
    FParent, FFirstChild, FLastChild, FNext, FPrev: TInkNode;
    FAttrs: array of TInkAttribute;
    function AttrIndex(const AName: string): Integer;
    function GetTextContent: string;
    procedure SetTextContent(const AValue: string);
    function GetInnerHTML: string;
    procedure SetInnerHTML(const AValue: string);
  public
    constructor Create(AKind: TInkNodeKind; const AName: string = '';
      ANamespace: TInkNamespace = insHTML);
    { frees the whole subtree, and takes the node out of its parent first }
    destructor Destroy; override;
    function AppendChild(ANode: TInkNode): TInkNode;
    { ARef nil appends }
    function InsertBefore(ANode, ARef: TInkNode): TInkNode;
    { takes the node out of its parent without freeing it }
    procedure Remove;
    procedure RemoveChildren;
    function ChildCount: Integer;
    function IsElement(const ATag: string): Boolean;
    function FirstElementChild: TInkNode;
    function NextElementSibling: TInkNode;
    function GetAttribute(const AName: string): string;
    function HasAttribute(const AName: string): Boolean;
    procedure SetAttribute(const AName, AValue: string);
    procedure RemoveAttribute(const AName: string);
    function AttributeCount: Integer;
    function AttributeName(I: Integer): string;
    function AttributeValue(I: Integer): string;
    function Id: string;
    function HasClass(const AClass: string): Boolean;
    function Clone(ADeep: Boolean): TInkNode;
    { the first element in the subtree, this node included, with this id }
    function GetElementById(const AId: string): TInkNode;
    { every element in the subtree under this node with this tag, '*' for all,
      in document order }
    function GetElementsByTagName(const ATag: string): TInkNodeArray;
    { the next node in document order, staying inside ARoot when given }
    function NextInTree(ARoot: TInkNode = nil): TInkNode;
    function OuterHTML: string;
    property Kind: TInkNodeKind read FKind;
    { an element's tag, lowercase for HTML; '#text', '#comment', the
      doctype's name, '#document' }
    property Name: string read FName;
    { a text node's text, a comment's words, a doctype's public id }
    property Data: string read FData write FData;
    property Namespace: TInkNamespace read FNamespace;
    property Parent: TInkNode read FParent;
    property FirstChild: TInkNode read FFirstChild;
    property LastChild: TInkNode read FLastChild;
    property NextSibling: TInkNode read FNext;
    property PreviousSibling: TInkNode read FPrev;
    property TextContent: string read GetTextContent write SetTextContent;
    property InnerHTML: string read GetInnerHTML write SetInnerHTML;
  end;

  TInkDocument = class(TInkNode)
  private
    FQuirks: Boolean;
  public
    constructor Create;
    function DocumentElement: TInkNode;
    function Head: TInkNode;
    function Body: TInkNode;
    { the <title>'s text, its white space collapsed }
    function Title: string;
    { no doctype, or an old one: a browser lays such a page out in quirks
      mode, and so will we where it matters }
    property Quirks: Boolean read FQuirks write FQuirks;
  end;

{ A whole document; never fails, whatever the input. }
function InkParseHTML(const AHTML: string): TInkDocument;
{ Children for AContext, parsed as its innerHTML would be, appended to it. }
procedure InkParseFragment(const AHTML: string; AContext: TInkNode);
{ The node and its subtree as HTML, the way a browser serializes it; a
  document gives its whole source. }
function InkSerializeHTML(ANode: TInkNode): string;
{ The bytes of a page as UTF-8: a byte order mark, then a <meta> charset in
  the first kilobyte, then a check that the bytes are UTF-8 at all - old
  help files that are not are Windows-1252. }
function InkDecodeHTML(const ABytes: RawByteString): string;
{ A character reference's name without & and ; - 'eacute' - as UTF-8, or ''
  when it is not one. }
function InkEntity(const AName: string): string;
function InkCodepointToUTF8(C: Cardinal): string;
function InkIsVoidElement(const ATag: string): Boolean;

implementation

uses StrUtils, LConvEncoding;

{ ---------------------------------------------------------------- text }

function InkCodepointToUTF8(C: Cardinal): string;
begin
  if C < $80 then Result := Chr(C)
  else if C < $800 then
    Result := Chr($C0 or (C shr 6)) + Chr($80 or (C and $3F))
  else if C < $10000 then
    Result := Chr($E0 or (C shr 12)) + Chr($80 or ((C shr 6) and $3F)) +
      Chr($80 or (C and $3F))
  else
    Result := Chr($F0 or (C shr 18)) + Chr($80 or ((C shr 12) and $3F)) +
      Chr($80 or ((C shr 6) and $3F)) + Chr($80 or (C and $3F));
end;

const
  { what bytes $80..$9F mean in Windows-1252, which is also what a numeric
    reference in that range means; 0 where the code page has nothing }
  Win1252: array[$80..$9F] of Word = (
    $20AC, 0, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, 0, $017D, 0,
    0, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, 0, $017E, $0178);

type
  TNamedChar = record N, V: string; L: Boolean; end;

{$I inkentities.inc}

{ the entry for a name, by binary search of the sorted table, or -1 }
function FindEntity(const AName: string): Integer;
var Lo, Hi, Mid, C: Integer;
begin
  Lo := 0; Hi := EntityCount - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(Entities[Mid].N, AName);
    if C = 0 then Exit(Mid);
    if C < 0 then Lo := Mid + 1 else Hi := Mid - 1;
  end;
  Result := -1;
end;

function InkEntity(const AName: string): string;
var I: Integer;
begin
  I := FindEntity(AName);
  if I >= 0 then Result := Entities[I].V else Result := '';
end;

function NumericChar(N: Int64): string;
begin
  if (N = 0) or (N > $10FFFF) or ((N >= $D800) and (N <= $DFFF)) then
    Exit(InkCodepointToUTF8($FFFD));
  if (N >= $80) and (N <= $9F) and (Win1252[N] <> 0) then N := Win1252[N];
  Result := InkCodepointToUTF8(N);
end;

{ Reads one character reference starting at S[P] = '&'.  On success Result
  is the text it stands for and P is past it; otherwise Result is '' and P
  is unchanged.  In an attribute, a name without its semicolon followed by
  a letter, digit or = is not a reference (href="?a=1&copy=2"). }
function ReadReference(const S: string; var P: Integer; InAttribute: Boolean): string;
var Q, Start, Len, I: Integer; N: Int64; Hex: Boolean; Name: string;
begin
  Result := '';
  Q := P + 1;
  if Q > Length(S) then Exit;
  if S[Q] = '#' then
  begin
    Inc(Q);
    Hex := (Q <= Length(S)) and (S[Q] in ['x','X']);
    if Hex then Inc(Q);
    Start := Q; N := 0;
    while (Q <= Length(S)) and
      ((S[Q] in ['0'..'9']) or (Hex and (S[Q] in ['a'..'f','A'..'F']))) do
    begin
      if N <= $10FFFF then
      begin
        if Hex then N := N*16 + StrToInt('$'+S[Q]) else N := N*10 + Ord(S[Q]) - 48;
      end;
      Inc(Q);
    end;
    if Q = Start then Exit;
    if (Q <= Length(S)) and (S[Q] = ';') then Inc(Q);
    Result := NumericChar(N);
    P := Q;
    Exit;
  end;
  Start := Q;
  while (Q <= Length(S)) and (Q - Start < 32) and (S[Q] in ['a'..'z','A'..'Z','0'..'9']) do Inc(Q);
  if Q = Start then Exit;
  Name := Copy(S, Start, Q - Start);
  if (Q <= Length(S)) and (S[Q] = ';') then
  begin
    I := FindEntity(Name);
    if I >= 0 then
    begin
      Result := Entities[I].V;
      P := Q + 1;
      Exit;
    end;
  end;
  { no semicolon: the longest legacy name the letters begin with }
  for Len := Length(Name) downto 2 do
  begin
    I := FindEntity(Copy(Name, 1, Len));
    if (I >= 0) and Entities[I].L then
    begin
      if InAttribute and (Start + Len <= Length(S)) and
        (S[Start + Len] in ['a'..'z','A'..'Z','0'..'9','=']) then Exit;
      Result := Entities[I].V;
      P := Start + Len;
      Exit;
    end;
  end;
end;

function DecodeReferences(const S: string; InAttribute: Boolean): string;
var P, Start: Integer; R: string;
begin
  if Pos('&', S) = 0 then Exit(S);
  Result := ''; P := 1; Start := 1;
  while P <= Length(S) do
  begin
    if S[P] = '&' then
    begin
      Result := Result + Copy(S, Start, P - Start);
      Start := P;
      R := ReadReference(S, P, InAttribute);
      if R <> '' then begin Result := Result + R; Start := P; Continue end;
      P := Start;
    end;
    Inc(P);
  end;
  Result := Result + Copy(S, Start, MaxInt);
end;

{ ------------------------------------------------------------- the node }

constructor TInkNode.Create(AKind: TInkNodeKind; const AName: string;
  ANamespace: TInkNamespace);
begin
  inherited Create;
  FKind := AKind;
  FNamespace := ANamespace;
  case AKind of
    inkText: FName := '#text';
    inkComment: FName := '#comment';
    inkDocument: FName := '#document';
  else
    FName := AName;
  end;
end;

destructor TInkNode.Destroy;
begin
  RemoveChildren;
  Remove;
  inherited Destroy;
end;

procedure TInkNode.RemoveChildren;
begin
  while FFirstChild <> nil do FFirstChild.Free;
end;

procedure TInkNode.Remove;
begin
  if FParent = nil then Exit;
  if FPrev <> nil then FPrev.FNext := FNext else FParent.FFirstChild := FNext;
  if FNext <> nil then FNext.FPrev := FPrev else FParent.FLastChild := FPrev;
  FParent := nil; FPrev := nil; FNext := nil;
end;

function TInkNode.InsertBefore(ANode, ARef: TInkNode): TInkNode;
begin
  Result := ANode;
  if ANode = nil then Exit;
  if (ARef <> nil) and (ARef.FParent <> Self) then
    raise EInvalidOperation.Create('InsertBefore: the reference is not a child');
  ANode.Remove;
  ANode.FParent := Self;
  if ARef = nil then
  begin
    ANode.FPrev := FLastChild;
    if FLastChild <> nil then FLastChild.FNext := ANode else FFirstChild := ANode;
    FLastChild := ANode;
  end
  else
  begin
    ANode.FNext := ARef;
    ANode.FPrev := ARef.FPrev;
    if ARef.FPrev <> nil then ARef.FPrev.FNext := ANode else FFirstChild := ANode;
    ARef.FPrev := ANode;
  end;
end;

function TInkNode.AppendChild(ANode: TInkNode): TInkNode;
begin
  Result := InsertBefore(ANode, nil);
end;

function TInkNode.ChildCount: Integer;
var N: TInkNode;
begin
  Result := 0; N := FFirstChild;
  while N <> nil do begin Inc(Result); N := N.FNext end;
end;

function TInkNode.IsElement(const ATag: string): Boolean;
begin
  Result := (FKind = inkElement) and (FName = ATag);
end;

function TInkNode.FirstElementChild: TInkNode;
begin
  Result := FFirstChild;
  while (Result <> nil) and (Result.FKind <> inkElement) do Result := Result.FNext;
end;

function TInkNode.NextElementSibling: TInkNode;
begin
  Result := FNext;
  while (Result <> nil) and (Result.FKind <> inkElement) do Result := Result.FNext;
end;

function TInkNode.AttrIndex(const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to High(FAttrs) do
    if FAttrs[I].Name = AName then Exit(I);
  Result := -1;
end;

function TInkNode.GetAttribute(const AName: string): string;
var I: Integer;
begin
  I := AttrIndex(LowerCase(AName));
  if I < 0 then I := AttrIndex(AName);
  if I >= 0 then Result := FAttrs[I].Value else Result := '';
end;

function TInkNode.HasAttribute(const AName: string): Boolean;
begin
  Result := (AttrIndex(LowerCase(AName)) >= 0) or (AttrIndex(AName) >= 0);
end;

procedure TInkNode.SetAttribute(const AName, AValue: string);
var I: Integer; N: string;
begin
  if FNamespace = insHTML then N := LowerCase(AName) else N := AName;
  I := AttrIndex(N);
  if I < 0 then
  begin
    I := Length(FAttrs); SetLength(FAttrs, I + 1);
    FAttrs[I].Name := N;
  end;
  FAttrs[I].Value := AValue;
end;

procedure TInkNode.RemoveAttribute(const AName: string);
var I, K: Integer;
begin
  I := AttrIndex(LowerCase(AName));
  if I < 0 then I := AttrIndex(AName);
  if I < 0 then Exit;
  for K := I to High(FAttrs) - 1 do FAttrs[K] := FAttrs[K + 1];
  SetLength(FAttrs, Length(FAttrs) - 1);
end;

function TInkNode.AttributeCount: Integer;
begin Result := Length(FAttrs) end;

function TInkNode.AttributeName(I: Integer): string;
begin Result := FAttrs[I].Name end;

function TInkNode.AttributeValue(I: Integer): string;
begin Result := FAttrs[I].Value end;

function TInkNode.Id: string;
begin Result := GetAttribute('id') end;

function TInkNode.HasClass(const AClass: string): Boolean;
var S: string; P, Q: Integer;
begin
  Result := False;
  if AClass = '' then Exit;
  S := GetAttribute('class');
  P := 1;
  while P <= Length(S) do
  begin
    while (P <= Length(S)) and (S[P] in [' ',#9,#10,#12,#13]) do Inc(P);
    Q := P;
    while (Q <= Length(S)) and not (S[Q] in [' ',#9,#10,#12,#13]) do Inc(Q);
    if (Q > P) and (Copy(S, P, Q - P) = AClass) then Exit(True);
    P := Q;
  end;
end;

function TInkNode.Clone(ADeep: Boolean): TInkNode;
var C: TInkNode;
begin
  if FKind = inkDocument then
  begin
    Result := TInkDocument.Create;
    TInkDocument(Result).FQuirks := TInkDocument(Self).FQuirks;
  end
  else Result := TInkNode.Create(FKind, FName, FNamespace);
  Result.FData := FData;
  Result.FAttrs := Copy(FAttrs);
  if ADeep then
  begin
    C := FFirstChild;
    while C <> nil do
    begin
      Result.AppendChild(C.Clone(True));
      C := C.FNext;
    end;
  end;
end;

function TInkNode.NextInTree(ARoot: TInkNode): TInkNode;
var N: TInkNode;
begin
  if FFirstChild <> nil then Exit(FFirstChild);
  N := Self;
  while N <> nil do
  begin
    if N = ARoot then Exit(nil);
    if N.FNext <> nil then Exit(N.FNext);
    N := N.FParent;
  end;
  Result := nil;
end;

function TInkNode.GetElementById(const AId: string): TInkNode;
begin
  Result := Self;
  while Result <> nil do
  begin
    if (Result.FKind = inkElement) and (Result.GetAttribute('id') = AId) then Exit;
    Result := Result.NextInTree(Self);
  end;
end;

function TInkNode.GetElementsByTagName(const ATag: string): TInkNodeArray;
var N: TInkNode; Count: Integer; T: string;
begin
  Result := nil; Count := 0; T := LowerCase(ATag);
  N := NextInTree(Self);
  while N <> nil do
  begin
    if (N.FKind = inkElement) and ((T = '*') or (LowerCase(N.FName) = T)) then
    begin
      if Count = Length(Result) then SetLength(Result, Count * 2 + 8);
      Result[Count] := N; Inc(Count);
    end;
    N := N.NextInTree(Self);
  end;
  SetLength(Result, Count);
end;

function TInkNode.GetTextContent: string;
var N: TInkNode;
begin
  if FKind in [inkText, inkComment] then Exit(FData);
  Result := '';
  N := NextInTree(Self);
  while N <> nil do
  begin
    if N.FKind = inkText then Result := Result + N.FData;
    N := N.NextInTree(Self);
  end;
end;

procedure TInkNode.SetTextContent(const AValue: string);
var T: TInkNode;
begin
  if FKind in [inkText, inkComment] then begin FData := AValue; Exit end;
  RemoveChildren;
  if AValue = '' then Exit;
  T := TInkNode.Create(inkText);
  T.FData := AValue;
  AppendChild(T);
end;

function TInkNode.GetInnerHTML: string;
var N: TInkNode;
begin
  Result := '';
  N := FFirstChild;
  while N <> nil do
  begin
    Result := Result + InkSerializeHTML(N);
    N := N.FNext;
  end;
end;

procedure TInkNode.SetInnerHTML(const AValue: string);
begin
  RemoveChildren;
  InkParseFragment(AValue, Self);
end;

function TInkNode.OuterHTML: string;
begin
  Result := InkSerializeHTML(Self);
end;

constructor TInkDocument.Create;
begin
  inherited Create(inkDocument);
end;

function TInkDocument.DocumentElement: TInkNode;
begin
  Result := FirstElementChild;
end;

function ChildElement(AParent: TInkNode; const ATag: string): TInkNode;
begin
  Result := nil;
  if AParent = nil then Exit;
  Result := AParent.FirstElementChild;
  while (Result <> nil) and (Result.Name <> ATag) do Result := Result.NextElementSibling;
end;

function TInkDocument.Head: TInkNode;
begin
  Result := ChildElement(DocumentElement, 'head');
end;

function TInkDocument.Body: TInkNode;
begin
  Result := ChildElement(DocumentElement, 'body');
end;

function TInkDocument.Title: string;
var T: TInkNodeArray; S: string; I: Integer; Space: Boolean;
begin
  Result := '';
  T := GetElementsByTagName('title');
  if Length(T) = 0 then Exit;
  S := T[0].TextContent; Space := False;
  for I := 1 to Length(S) do
    if S[I] in [' ',#9,#10,#12,#13] then
    begin
      if not Space then Result := Result + ' ';
      Space := True;
    end
    else begin Result := Result + S[I]; Space := False end;
  Result := Trim(Result);
end;

{ ---------------------------------------------------------- tag groups }

function InList(const ATag: string; const AList: array of string): Boolean;
var I: Integer;
begin
  for I := 0 to High(AList) do
    if AList[I] = ATag then Exit(True);
  Result := False;
end;

function InkIsVoidElement(const ATag: string): Boolean;
begin
  Result := InList(ATag, ['area','base','basefont','bgsound','br','col','embed',
    'frame','hr','image','img','input','keygen','link','meta','param','source',
    'track','wbr']);
end;

function IsHeading(const T: string): Boolean;
begin
  Result := (Length(T) = 2) and (T[1] = 'h') and (T[2] in ['1'..'6']);
end;

function IsFormatting(const T: string): Boolean;
begin
  Result := InList(T, ['a','b','big','code','em','font','i','nobr','s','small',
    'strike','strong','tt','u']);
end;

function IsSpecial(N: TInkNode): Boolean;
begin
  if N.Namespace = insSVG then
    Exit(InList(N.Name, ['foreignObject','desc','title']));
  if N.Namespace = insMathML then
    Exit(InList(N.Name, ['mi','mo','mn','ms','mtext','annotation-xml']));
  Result := IsHeading(N.Name) or InList(N.Name, ['address','applet','area',
    'article','aside','base','basefont','bgsound','blockquote','body','br',
    'button','caption','center','col','colgroup','dd','details','dir','div',
    'dl','dt','embed','fieldset','figcaption','figure','footer','form','frame',
    'frameset','head','header','hgroup','hr','html','iframe','img','input',
    'keygen','li','link','listing','main','marquee','menu','meta','nav',
    'noembed','noframes','noscript','object','ol','p','param','plaintext',
    'pre','script','search','section','select','source','style','summary',
    'table','tbody','td','template','textarea','tfoot','th','thead','title',
    'tr','track','ul','wbr','xmp']);
end;

{ the block elements a start tag closes an open <p> for }
function ClosesP(const T: string): Boolean;
begin
  Result := InList(T, ['address','article','aside','blockquote','center',
    'details','dialog','dir','div','dl','fieldset','figcaption','figure',
    'footer','header','hgroup','main','menu','nav','ol','p','search','section',
    'summary','ul']);
end;

function ImpliedEnd(const T: string): Boolean;
begin
  Result := InList(T, ['dd','dt','li','optgroup','option','p','rb','rp','rt','rtc']);
end;

const
  { the tags whose start, inside <svg> or <math>, ends the drawing: a page
    that forgot to close one still shows its words }
  BreakoutTags: array[0..43] of string = ('b','big','blockquote','body','br',
    'center','code','dd','div','dl','dt','em','embed','h1','h2','h3','h4','h5',
    'h6','head','hr','i','img','li','listing','menu','meta','nobr','ol','p',
    'pre','ruby','s','small','span','strong','strike','sub','sup','table',
    'tt','u','ul','var');

  { SVG keeps its camelCase; the tokenizer lowered it }
  SVGTags: array[0..36] of string = ('altGlyph','altGlyphDef','altGlyphItem',
    'animateColor','animateMotion','animateTransform','clipPath','feBlend',
    'feColorMatrix','feComponentTransfer','feComposite','feConvolveMatrix',
    'feDiffuseLighting','feDisplacementMap','feDistantLight','feDropShadow',
    'feFlood','feFuncA','feFuncB','feFuncG','feFuncR','feGaussianBlur',
    'feImage','feMerge','feMergeNode','feMorphology','feOffset','fePointLight',
    'feSpecularLighting','feSpotLight','feTile','feTurbulence','foreignObject',
    'glyphRef','linearGradient','radialGradient','textPath');
  SVGAttrs: array[0..57] of string = ('attributeName','attributeType',
    'baseFrequency','baseProfile','calcMode','clipPathUnits','diffuseConstant',
    'edgeMode','filterUnits','glyphRef','gradientTransform','gradientUnits',
    'kernelMatrix','kernelUnitLength','keyPoints','keySplines','keyTimes',
    'lengthAdjust','limitingConeAngle','markerHeight','markerUnits',
    'markerWidth','maskContentUnits','maskUnits','numOctaves','pathLength',
    'patternContentUnits','patternTransform','patternUnits','pointsAtX',
    'pointsAtY','pointsAtZ','preserveAlpha','preserveAspectRatio',
    'primitiveUnits','refX','refY','repeatCount','repeatDur',
    'requiredExtensions','requiredFeatures','specularConstant',
    'specularExponent','spreadMethod','startOffset','stdDeviation',
    'stitchTiles','surfaceScale','systemLanguage','tableValues','targetX',
    'targetY','textLength','viewBox','viewTarget','xChannelSelector',
    'yChannelSelector','zoomAndPan');

function SVGCase(const ALower: string; const ANames: array of string): string;
var I: Integer;
begin
  for I := 0 to High(ANames) do
    if LowerCase(ANames[I]) = ALower then Exit(ANames[I]);
  Result := ALower;
end;

{ ------------------------------------------------------------ tokenizer }

type
  TTokKind = (tkNone, tkStart, tkEnd, tkText, tkComment, tkDoctype, tkEOF);
  TTokState = (tsData, tsRCData, tsRawText, tsPlainText);

  TToken = record
    Kind: TTokKind;
    Name, Data: string;
    { a doctype's public and system ids, and whether it had them }
    PublicId, SystemId: string;
    HasPublic, HasSystem: Boolean;
    SelfClosing: Boolean;
    Attrs: array of TInkAttribute;
  end;

  TMode = (imInitial, imBeforeHtml, imBeforeHead, imInHead, imAfterHead,
    imInBody, imText, imInTable, imInCaption, imInColumnGroup, imInTableBody,
    imInRow, imInCell, imInSelect, imInSelectInTable, imAfterBody,
    imAfterAfterBody, imInHeadNoscript, imInFrameset, imAfterFrameset,
    imAfterAfterFrameset, imInTemplate);

  TParser = class
  private
    S, SLow: string;
    P: Integer;
    State: TTokState;
    { the end tag that ends raw text, and whether the tree builder is in
      foreign content (CDATA sections are text there) }
    RawEnd: string;
    Doc: TInkDocument;
    Stack: TFPList;           { open elements, html first }
    Formatting: TFPList;      { active formatting elements; nil is a marker }
    Mode, OriginalMode: TMode;
    HeadEl, FormEl: TInkNode;
    FosterParenting: Boolean;
    SkipNewline: Boolean;
    { whether a <frameset> may still replace the body: nothing has been
      shown yet }
    FramesetOK: Boolean;
    TemplateModes: array of TMode;
    FragmentContext: TInkNode;
    { tokenizer }
    function NextToken: TToken;
    function ScriptEnd: Integer;
    procedure ReadTag(var T: TToken);
    procedure ReadDoctype(var T: TToken);
    { tree }
    function Current: TInkNode;
    function AdjustedCurrent: TInkNode;
    function StackIndex(N: TInkNode): Integer;
    function InScope(const ATag: string; const AExtra: array of string;
      ATableOnly: Boolean = False): Boolean;
    function InButtonScope(const ATag: string): Boolean;
    function InListScope(const ATag: string): Boolean;
    function InTableScope(const ATag: string): Boolean;
    function HeadingInScope: Boolean;
    function Pop: TInkNode;
    procedure PopUntil(const ATag: string);
    procedure PopUntilAny(const ATags: array of string);
    procedure GenerateImpliedEnd(const AExcept: string = '');
    procedure CloseP;
    procedure ClearToContext(const ATags: array of string);
    procedure ResetMode;
    function CreateElement(const T: TToken; ANs: TInkNamespace): TInkNode;
    procedure InsertNode(N: TInkNode);
    function Insert(const T: TToken; ANs: TInkNamespace = insHTML): TInkNode;
    function InsertTag(const ATag: string): TInkNode;
    procedure InsertText(const AText: string);
    procedure InsertComment(const AText: string; AParent: TInkNode = nil);
    procedure PushFormatting(N: TInkNode);
    procedure ReconstructFormatting;
    procedure ClearFormattingToMarker;
    procedure RemoveFormatting(N: TInkNode);
    function AdoptionAgency(const ATag: string): Boolean;
    procedure AnyOtherEnd(const ATag: string);
    procedure StartRaw(const T: TToken; AState: TTokState);
    { the modes }
    procedure Process(var T: TToken);
    procedure InHead(var T: TToken; out Reprocess: Boolean);
    procedure InBody(var T: TToken);
    procedure InBodyStart(var T: TToken);
    procedure InBodyEnd(var T: TToken);
    procedure InTable(var T: TToken; out Reprocess: Boolean);
    procedure InForeign(var T: TToken; out Reprocess: Boolean);
    function UseForeign(const T: TToken): Boolean;
    procedure CloseCell;
    { <template>: its own stack of modes, one per template open }
    procedure StartTemplate(const T: TToken);
    procedure EndTemplate;
    function TemplateOpen: Boolean;
  public
    constructor Create(const AHTML: string);
    destructor Destroy; override;
    procedure Run;
  end;

function IsSpaceChar(C: Char): Boolean; inline;
begin
  Result := C in [' ', #9, #10, #12, #13];
end;

function AllSpace(const S: string): Boolean;
var I: Integer;
begin
  for I := 1 to Length(S) do
    if not IsSpaceChar(S[I]) then Exit(False);
  Result := True;
end;

function SpaceOnly(const S: string): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if IsSpaceChar(S[I]) then Result := Result + S[I];
end;

{ the leading run of white space, and the rest }
procedure SplitSpace(const S: string; out ASpace, ARest: string);
var I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and IsSpaceChar(S[I]) do Inc(I);
  ASpace := Copy(S, 1, I - 1);
  ARest := Copy(S, I, MaxInt);
end;

function AttrOf(const T: TToken; const AName: string): string;
var I: Integer;
begin
  for I := 0 to High(T.Attrs) do
    if T.Attrs[I].Name = AName then Exit(T.Attrs[I].Value);
  Result := '';
end;

{ whether a doctype puts the page in quirks mode, by the standard's list }
function DoctypeQuirks(const T: TToken): Boolean;
const
  Prefixes: array[0..54] of string = (
    '+//silmaril//dtd html pro v0r11 19970101//',
    '-//as//dtd html 3.0 aswedit + extensions//',
    '-//advasoft ltd//dtd html 3.0 aswedit + extensions//',
    '-//ietf//dtd html 2.0 level 1//', '-//ietf//dtd html 2.0 level 2//',
    '-//ietf//dtd html 2.0 strict level 1//', '-//ietf//dtd html 2.0 strict level 2//',
    '-//ietf//dtd html 2.0 strict//', '-//ietf//dtd html 2.0//',
    '-//ietf//dtd html 2.1e//', '-//ietf//dtd html 3.0//',
    '-//ietf//dtd html 3.2 final//', '-//ietf//dtd html 3.2//', '-//ietf//dtd html 3//',
    '-//ietf//dtd html level 0//', '-//ietf//dtd html level 1//',
    '-//ietf//dtd html level 2//', '-//ietf//dtd html level 3//',
    '-//ietf//dtd html strict level 0//', '-//ietf//dtd html strict level 1//',
    '-//ietf//dtd html strict level 2//', '-//ietf//dtd html strict level 3//',
    '-//ietf//dtd html strict//', '-//ietf//dtd html//',
    '-//metrius//dtd metrius presentational//',
    '-//microsoft//dtd internet explorer 2.0 html strict//',
    '-//microsoft//dtd internet explorer 2.0 html//',
    '-//microsoft//dtd internet explorer 2.0 tables//',
    '-//microsoft//dtd internet explorer 3.0 html strict//',
    '-//microsoft//dtd internet explorer 3.0 html//',
    '-//microsoft//dtd internet explorer 3.0 tables//',
    '-//netscape comm. corp.//dtd html//', '-//netscape comm. corp.//dtd strict html//',
    '-//o''reilly and associates//dtd html 2.0//',
    '-//o''reilly and associates//dtd html extended 1.0//',
    '-//o''reilly and associates//dtd html extended relaxed 1.0//',
    '-//sq//dtd html 2.0 hotmetal + extensions//',
    '-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//',
    '-//softquad//dtd hotmetal pro 4.0::19970916::extensions to html 4.0//',
    '-//spyglass//dtd html 2.0 extended//',
    '-//sun microsystems corp.//dtd hotjava html//',
    '-//sun microsystems corp.//dtd hotjava strict html//',
    '-//w3c//dtd html 3 1995-03-24//', '-//w3c//dtd html 3.2 draft//',
    '-//w3c//dtd html 3.2 final//', '-//w3c//dtd html 3.2//',
    '-//w3c//dtd html 3.2s draft//', '-//w3c//dtd html 4.0 frameset//',
    '-//w3c//dtd html 4.0 transitional//', '-//w3c//dtd html experimental 19960712//',
    '-//w3c//dtd html experimental 970421//', '-//w3c//dtd w3 html//',
    '-//w3o//dtd w3 html 3.0//', '-//webtechs//dtd mozilla html 2.0//',
    '-//webtechs//dtd mozilla html//');
var Pub, Sys: string; I: Integer;
begin
  Pub := LowerCase(T.PublicId); Sys := LowerCase(T.SystemId);
  if (T.Name <> 'html') or (Pub = '-//w3o//dtd w3 html strict 3.0//en//') or
    (Pub = '-/w3c/dtd html 4.0 transitional/en') or (Pub = 'html') or
    (Sys = 'http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd') then Exit(True);
  for I := 0 to High(Prefixes) do
    if Copy(Pub, 1, Length(Prefixes[I])) = Prefixes[I] then Exit(True);
  Result := not T.HasSystem and
    ((Copy(Pub, 1, 32) = '-//w3c//dtd html 4.01 frameset//') or
     (Copy(Pub, 1, 36) = '-//w3c//dtd html 4.01 transitional//'));
end;

constructor TParser.Create(const AHTML: string);
var I, J: Integer;
begin
  inherited Create;
  { the input stream is preprocessed: CR LF and lone CR become LF, and NUL
    is dropped }
  SetLength(S, Length(AHTML));
  J := 0; I := 1;
  while I <= Length(AHTML) do
  begin
    if AHTML[I] = #13 then
    begin
      Inc(J); S[J] := #10;
      if (I < Length(AHTML)) and (AHTML[I + 1] = #10) then Inc(I);
    end
    else if AHTML[I] <> #0 then begin Inc(J); S[J] := AHTML[I] end;
    Inc(I);
  end;
  SetLength(S, J);
  { a byte order mark is not text }
  if Copy(S, 1, 3) = #$EF#$BB#$BF then Delete(S, 1, 3);
  SLow := LowerCase(S);
  P := 1;
  Stack := TFPList.Create;
  Formatting := TFPList.Create;
  Doc := TInkDocument.Create;
  Mode := imInitial;
  FramesetOK := True;
end;

destructor TParser.Destroy;
begin
  Stack.Free;
  Formatting.Free;
  inherited Destroy;
end;

{ ------------------------------------------------------------ tokenizing }

procedure TParser.ReadDoctype(var T: TToken);
var Q: Integer; Body, Low, Rest: string;

  function Quoted(var R: string; out V: string): Boolean;
  var K: Integer; Qc: Char;
  begin
    R := TrimLeft(R); V := '';
    Result := (R <> '') and (R[1] in ['"', '''']);
    if not Result then Exit;
    Qc := R[1];
    K := Pos(Qc, Copy(R, 2, MaxInt));
    if K = 0 then begin V := Copy(R, 2, MaxInt); R := '' end
    else begin V := Copy(R, 2, K - 1); R := Copy(R, K + 2, MaxInt) end;
  end;

begin
  { P is past '<!doctype' }
  Q := P;
  while (Q <= Length(S)) and (S[Q] <> '>') do Inc(Q);
  Body := Trim(Copy(S, P, Q - P));
  P := Q + 1;
  T.Kind := tkDoctype;
  Q := 1;
  while (Q <= Length(Body)) and not IsSpaceChar(Body[Q]) do Inc(Q);
  T.Name := LowerCase(Copy(Body, 1, Q - 1));
  Rest := Copy(Body, Q, MaxInt);
  Low := LowerCase(TrimLeft(Rest));
  if Copy(Low, 1, 6) = 'public' then
  begin
    Rest := Copy(TrimLeft(Rest), 7, MaxInt);
    T.HasPublic := Quoted(Rest, T.PublicId);
    T.HasSystem := Quoted(Rest, T.SystemId);
  end
  else if Copy(Low, 1, 6) = 'system' then
  begin
    Rest := Copy(TrimLeft(Rest), 7, MaxInt);
    T.HasSystem := Quoted(Rest, T.SystemId);
  end;
end;

procedure TParser.ReadTag(var T: TToken);
var Q, N: Integer; AName, AValue: string; Qc: Char; Dup: Boolean;
begin
  { P is on the first letter of the name }
  Q := P;
  while (Q <= Length(S)) and not (IsSpaceChar(S[Q]) or (S[Q] in ['/', '>'])) do Inc(Q);
  T.Name := LowerCase(Copy(S, P, Q - P));
  P := Q;
  while P <= Length(S) do
  begin
    while (P <= Length(S)) and IsSpaceChar(S[P]) do Inc(P);
    if P > Length(S) then Break;
    if S[P] = '>' then begin Inc(P); Exit end;
    if S[P] = '/' then
    begin
      Inc(P);
      if (P <= Length(S)) and (S[P] = '>') then
      begin
        T.SelfClosing := True; Inc(P); Exit;
      end;
      Continue;
    end;
    { an attribute's name; its first character may be anything but space,
      / or >, an = included }
    Q := P + 1;
    while (Q <= Length(S)) and not (IsSpaceChar(S[Q]) or (S[Q] in ['/', '>', '='])) do Inc(Q);
    AName := LowerCase(Copy(S, P, Q - P));
    P := Q;
    while (P <= Length(S)) and IsSpaceChar(S[P]) do Inc(P);
    AValue := '';
    if (P <= Length(S)) and (S[P] = '=') then
    begin
      Inc(P);
      while (P <= Length(S)) and IsSpaceChar(S[P]) do Inc(P);
      if (P <= Length(S)) and (S[P] in ['"', '''']) then
      begin
        Qc := S[P]; Inc(P); Q := P;
        while (Q <= Length(S)) and (S[Q] <> Qc) do Inc(Q);
        AValue := DecodeReferences(Copy(S, P, Q - P), True);
        P := Q + 1;
      end
      else
      begin
        Q := P;
        while (Q <= Length(S)) and not (IsSpaceChar(S[Q]) or (S[Q] = '>')) do Inc(Q);
        AValue := DecodeReferences(Copy(S, P, Q - P), True);
        P := Q;
      end;
    end;
    { the first of a repeated attribute wins }
    Dup := False;
    for N := 0 to High(T.Attrs) do
      if T.Attrs[N].Name = AName then begin Dup := True; Break end;
    if not Dup and (AName <> '') then
    begin
      N := Length(T.Attrs); SetLength(T.Attrs, N + 1);
      T.Attrs[N].Name := AName; T.Attrs[N].Value := AValue;
    end;
  end;
  { the input ended inside the tag: the tag is dropped }
  T.Kind := tkEOF;
end;

{ Where a script's text ends: its </script>, except that inside <!-- -->
  a <script> starts a second level where a </script> only ends that level -
  how old pages wrote document.write('<script>..</script>'). }
function TParser.ScriptEnd: Integer;
var Q, Level, EscStart: Integer;

  function At(const W: string): Boolean;
  var E: Integer;
  begin
    Result := False;
    if Copy(SLow, Q, Length(W)) <> W then Exit;
    if W[Length(W)] in ['-', '>'] then Exit(True);
    E := Q + Length(W);
    Result := (E <= Length(S)) and (IsSpaceChar(S[E]) or (S[E] in ['/', '>']));
  end;

begin
  Q := P; Level := 0; EscStart := 0;
  while Q <= Length(S) do
  begin
    if S[Q] = '<' then
    begin
      if (Level = 0) and At('<!--') then
      begin
        Level := 1; EscStart := Q + 2; Inc(Q, 4); Continue;
      end;
      if (Level < 2) and At('</script') then Exit(Q);
      if (Level = 1) and At('<script') then begin Level := 2; Inc(Q, 7); Continue end;
      if (Level = 2) and At('</script') then begin Level := 1; Inc(Q, 8); Continue end;
    end
    else if (S[Q] = '>') and (Level > 0) and (Q - 2 >= EscStart) and
      (S[Q - 1] = '-') and (S[Q - 2] = '-') then Level := 0;
    Inc(Q);
  end;
  Result := Length(S) + 1;
end;

function TParser.NextToken: TToken;
var Q, K: Integer;
begin
  Result := Default(TToken);
  if P > Length(S) then begin Result.Kind := tkEOF; Exit end;
  case State of
    tsPlainText:
      begin
        Result.Kind := tkText; Result.Data := Copy(S, P, MaxInt);
        P := Length(S) + 1; Exit;
      end;
    tsRCData, tsRawText:
      begin
        { text up to the end tag that closes the element }
        if RawEnd = 'script' then K := ScriptEnd
        else
        begin
          Q := P;
          repeat
            K := PosEx('</' + RawEnd, SLow, Q);
            if K = 0 then Break;
            Q := K + 2 + Length(RawEnd);
            if (Q > Length(S)) or IsSpaceChar(S[Q]) or (S[Q] in ['/', '>']) then Break;
            K := 0;
          until False;
          if K = 0 then K := Length(S) + 1;
        end;
        if K > P then
        begin
          Result.Kind := tkText;
          Result.Data := Copy(S, P, K - P);
          if State = tsRCData then Result.Data := DecodeReferences(Result.Data, False);
          P := K;
          Exit;
        end;
        State := tsData;
        if P > Length(S) then begin Result.Kind := tkEOF; Exit end;
      end;
  end;
  if S[P] <> '<' then
  begin
    Q := P;
    while (Q <= Length(S)) and (S[Q] <> '<') do Inc(Q);
    Result.Kind := tkText;
    Result.Data := DecodeReferences(Copy(S, P, Q - P), False);
    P := Q;
    Exit;
  end;
  { a tag, a comment, a doctype, or a '<' that is only text }
  if P = Length(S) then
  begin
    Result.Kind := tkText; Result.Data := '<'; Inc(P); Exit;
  end;
  case S[P + 1] of
    'a'..'z', 'A'..'Z':
      begin
        Result.Kind := tkStart;
        Inc(P);
        ReadTag(Result);
      end;
    '/':
      begin
        if (P + 2 <= Length(S)) and (S[P + 2] in ['a'..'z', 'A'..'Z']) then
        begin
          Result.Kind := tkEnd;
          Inc(P, 2);
          ReadTag(Result);
          if Result.Kind <> tkEOF then Result.Kind := tkEnd;
          Result.Attrs := nil; Result.SelfClosing := False;
        end
        else if (P + 2 <= Length(S)) and (S[P + 2] = '>') then
        begin
          { '</>' is nothing at all }
          Inc(P, 3);
          Result := NextToken;
        end
        else
        begin
          { anything else after '</' is a bogus comment up to '>' }
          Q := PosEx('>', S, P + 2);
          if Q = 0 then Q := Length(S) + 1;
          Result.Kind := tkComment; Result.Data := Copy(S, P + 2, Q - P - 2);
          P := Q + 1;
        end;
      end;
    '!':
      begin
        if Copy(S, P, 4) = '<!--' then
        begin
          { '<!-->' and '<!--->' are empty comments }
          if Copy(S, P + 4, 1) = '>' then begin Result.Kind := tkComment; P := P + 5; Exit end;
          if Copy(S, P + 4, 2) = '->' then begin Result.Kind := tkComment; P := P + 6; Exit end;
          Q := PosEx('-->', S, P + 4);
          K := PosEx('--!>', S, P + 4);
          if (K > 0) and ((Q = 0) or (K < Q)) then
          begin
            Result.Kind := tkComment; Result.Data := Copy(S, P + 4, K - P - 4);
            P := K + 4; Exit;
          end;
          Result.Kind := tkComment;
          if Q = 0 then
          begin
            Result.Data := Copy(S, P + 4, MaxInt); P := Length(S) + 1;
          end
          else
          begin
            Result.Data := Copy(S, P + 4, Q - P - 4); P := Q + 3;
          end;
          Exit;
        end;
        if LowerCase(Copy(S, P + 2, 7)) = 'doctype' then
        begin
          P := P + 9;
          ReadDoctype(Result);
          Exit;
        end;
        if (Copy(S, P + 2, 7) = '[CDATA[') and (AdjustedCurrent <> nil) and
          (AdjustedCurrent.Namespace <> insHTML) then
        begin
          Q := PosEx(']]>', S, P + 9);
          if Q = 0 then Q := Length(S) + 1;
          Result.Kind := tkText; Result.Data := Copy(S, P + 9, Q - P - 9);
          P := Q + 3; Exit;
        end;
        Q := PosEx('>', S, P + 2);
        if Q = 0 then Q := Length(S) + 1;
        Result.Kind := tkComment; Result.Data := Copy(S, P + 2, Q - P - 2);
        P := Q + 1;
      end;
    '?':
      begin
        Q := PosEx('>', S, P + 1);
        if Q = 0 then Q := Length(S) + 1;
        Result.Kind := tkComment; Result.Data := Copy(S, P + 1, Q - P - 1);
        P := Q + 1;
      end;
  else
    Result.Kind := tkText; Result.Data := '<'; Inc(P);
  end;
end;

{ ------------------------------------------------------------- the tree }

function TParser.Current: TInkNode;
begin
  if Stack.Count = 0 then Result := nil
  else Result := TInkNode(Stack[Stack.Count - 1]);
end;

function TParser.AdjustedCurrent: TInkNode;
begin
  if (FragmentContext <> nil) and (Stack.Count = 1) then Result := FragmentContext
  else Result := Current;
end;

function TParser.StackIndex(N: TInkNode): Integer;
begin
  Result := Stack.IndexOf(N);
end;

function TParser.InScope(const ATag: string; const AExtra: array of string;
  ATableOnly: Boolean): Boolean;
var I: Integer; N: TInkNode;
begin
  for I := Stack.Count - 1 downto 0 do
  begin
    N := TInkNode(Stack[I]);
    if (N.Namespace = insHTML) and (N.Name = ATag) then Exit(True);
    if ATableOnly then
    begin
      if (N.Namespace = insHTML) and InList(N.Name, ['html', 'table', 'template']) then
        Exit(False);
      Continue;
    end;
    if N.Namespace = insHTML then
    begin
      if InList(N.Name, ['applet','caption','html','table','td','th','marquee',
        'object','template']) then Exit(False);
      if InList(N.Name, AExtra) then Exit(False);
    end
    else if IsSpecial(N) then Exit(False);
  end;
  Result := False;
end;

function TParser.InButtonScope(const ATag: string): Boolean;
begin Result := InScope(ATag, ['button']) end;

function TParser.InListScope(const ATag: string): Boolean;
begin Result := InScope(ATag, ['ol', 'ul']) end;

function TParser.InTableScope(const ATag: string): Boolean;
begin Result := InScope(ATag, [], True) end;

function TParser.HeadingInScope: Boolean;
begin
  Result := InScope('h1', []) or InScope('h2', []) or InScope('h3', []) or
    InScope('h4', []) or InScope('h5', []) or InScope('h6', []);
end;

function TParser.Pop: TInkNode;
begin
  Result := Current;
  if Stack.Count > 0 then Stack.Delete(Stack.Count - 1);
end;

procedure TParser.PopUntil(const ATag: string);
var N: TInkNode;
begin
  while Stack.Count > 0 do
  begin
    N := Pop;
    if (N.Namespace = insHTML) and (N.Name = ATag) then Exit;
  end;
end;

procedure TParser.PopUntilAny(const ATags: array of string);
var N: TInkNode;
begin
  while Stack.Count > 0 do
  begin
    N := Pop;
    if (N.Namespace = insHTML) and InList(N.Name, ATags) then Exit;
  end;
end;

procedure TParser.GenerateImpliedEnd(const AExcept: string);
begin
  while (Current <> nil) and (Current.Namespace = insHTML) and
    ImpliedEnd(Current.Name) and (Current.Name <> AExcept) do Pop;
end;

procedure TParser.CloseP;
begin
  if not InButtonScope('p') then Exit;
  GenerateImpliedEnd('p');
  PopUntil('p');
end;

procedure TParser.ClearToContext(const ATags: array of string);
begin
  while (Current <> nil) and not ((Current.Namespace = insHTML) and
    (InList(Current.Name, ATags) or (Current.Name = 'html') or
     (Current.Name = 'template'))) do Pop;
end;

procedure TParser.ResetMode;
var I: Integer; N: TInkNode; Last: Boolean;
begin
  for I := Stack.Count - 1 downto 0 do
  begin
    N := TInkNode(Stack[I]);
    Last := I = 0;
    if Last and (FragmentContext <> nil) then N := FragmentContext;
    if N.Name = 'select' then begin Mode := imInSelect; Exit end;
    if ((N.Name = 'td') or (N.Name = 'th')) and not Last then begin Mode := imInCell; Exit end;
    if N.Name = 'tr' then begin Mode := imInRow; Exit end;
    if InList(N.Name, ['tbody', 'thead', 'tfoot']) then begin Mode := imInTableBody; Exit end;
    if N.Name = 'caption' then begin Mode := imInCaption; Exit end;
    if N.Name = 'colgroup' then begin Mode := imInColumnGroup; Exit end;
    if N.Name = 'table' then begin Mode := imInTable; Exit end;
    if (N.Name = 'body') or (N.Name = 'td') or (N.Name = 'th') then begin Mode := imInBody; Exit end;
    if N.Name = 'frameset' then begin Mode := imInFrameset; Exit end;
    if N.Name = 'template' then
    begin
      if Length(TemplateModes) > 0 then Mode := TemplateModes[High(TemplateModes)]
      else Mode := imInBody;
      Exit;
    end;
    if (N.Name = 'head') and not Last then begin Mode := imInHead; Exit end;
    if N.Name = 'html' then
    begin
      if HeadEl = nil then Mode := imBeforeHead else Mode := imAfterHead;
      Exit;
    end;
    if Last then begin Mode := imInBody; Exit end;
  end;
  Mode := imInBody;
end;

function TParser.CreateElement(const T: TToken; ANs: TInkNamespace): TInkNode;
var I: Integer; AName: string;
begin
  AName := T.Name;
  if ANs = insSVG then AName := SVGCase(AName, SVGTags);
  Result := TInkNode.Create(inkElement, AName, ANs);
  SetLength(Result.FAttrs, Length(T.Attrs));
  for I := 0 to High(T.Attrs) do
  begin
    Result.FAttrs[I] := T.Attrs[I];
    if ANs = insSVG then Result.FAttrs[I].Name := SVGCase(T.Attrs[I].Name, SVGAttrs)
    else if (ANs = insMathML) and (T.Attrs[I].Name = 'definitionurl') then
      Result.FAttrs[I].Name := 'definitionURL';
  end;
end;

{ Puts N where the next node goes: at the end of the current node, or - when
  stray content inside a table is being moved out of it - just before the
  table. }
procedure TParser.InsertNode(N: TInkNode);
var Target, Table, Parent: TInkNode; I: Integer;
begin
  Target := Current;
  if Target = nil then begin Doc.AppendChild(N); Exit end;
  if FosterParenting and (Target.Namespace = insHTML) and
    InList(Target.Name, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
  begin
    Table := nil;
    for I := Stack.Count - 1 downto 0 do
      if TInkNode(Stack[I]).IsElement('table') then begin Table := TInkNode(Stack[I]); Break end;
    if Table = nil then begin TInkNode(Stack[0]).AppendChild(N); Exit end;
    Parent := Table.Parent;
    if Parent <> nil then
    begin
      { text merges with text already standing before the table }
      if (N.Kind = inkText) and (Table.PreviousSibling <> nil) and
        (Table.PreviousSibling.Kind = inkText) then
      begin
        Table.PreviousSibling.FData := Table.PreviousSibling.FData + N.FData;
        N.Free;
        Exit;
      end;
      Parent.InsertBefore(N, Table);
    end
    else TInkNode(Stack[StackIndex(Table) - 1]).AppendChild(N);
    Exit;
  end;
  if (N.Kind = inkText) and (Target.LastChild <> nil) and
    (Target.LastChild.Kind = inkText) then
  begin
    Target.LastChild.FData := Target.LastChild.FData + N.FData;
    N.Free;
    Exit;
  end;
  Target.AppendChild(N);
end;

function TParser.Insert(const T: TToken; ANs: TInkNamespace): TInkNode;
begin
  Result := CreateElement(T, ANs);
  InsertNode(Result);
  Stack.Add(Result);
end;

function TParser.InsertTag(const ATag: string): TInkNode;
var T: TToken;
begin
  T := Default(TToken);
  T.Kind := tkStart; T.Name := ATag;
  Result := Insert(T);
end;

procedure TParser.InsertText(const AText: string);
var N: TInkNode;
begin
  if AText = '' then Exit;
  N := TInkNode.Create(inkText);
  N.FData := AText;
  InsertNode(N);
end;

procedure TParser.InsertComment(const AText: string; AParent: TInkNode);
var N: TInkNode;
begin
  N := TInkNode.Create(inkComment);
  N.FData := AText;
  if AParent <> nil then AParent.AppendChild(N) else InsertNode(N);
end;

function SameAttributes(A, B: TInkNode): Boolean;
var I: Integer;
begin
  if A.AttributeCount <> B.AttributeCount then Exit(False);
  for I := 0 to A.AttributeCount - 1 do
    if B.GetAttribute(A.AttributeName(I)) <> A.AttributeValue(I) then Exit(False);
  Result := True;
end;

procedure TParser.PushFormatting(N: TInkNode);
var I, Same, Earliest: Integer; E: TInkNode;
begin
  { no more than three alike in a row: <b><b><b><b> reopens three }
  Same := 0; Earliest := -1;
  for I := Formatting.Count - 1 downto 0 do
  begin
    E := TInkNode(Formatting[I]);
    if E = nil then Break;
    if (E.Name = N.Name) and (E.Namespace = N.Namespace) and SameAttributes(E, N) then
    begin
      Inc(Same); Earliest := I;
    end;
  end;
  if Same >= 3 then Formatting.Delete(Earliest);
  Formatting.Add(N);
end;

procedure TParser.ClearFormattingToMarker;
begin
  while Formatting.Count > 0 do
  begin
    if Formatting[Formatting.Count - 1] = nil then
    begin
      Formatting.Delete(Formatting.Count - 1);
      Exit;
    end;
    Formatting.Delete(Formatting.Count - 1);
  end;
end;

procedure TParser.RemoveFormatting(N: TInkNode);
var I: Integer;
begin
  I := Formatting.IndexOf(N);
  if I >= 0 then Formatting.Delete(I);
end;

{ Formatting elements a block closed while they were open are opened again
  for what follows: <p><b>one<p>two - both paragraphs are bold. }
procedure TParser.ReconstructFormatting;
var I, J: Integer; N, C: TInkNode;
begin
  if Formatting.Count = 0 then Exit;
  N := TInkNode(Formatting[Formatting.Count - 1]);
  if (N = nil) or (StackIndex(N) >= 0) then Exit;
  I := Formatting.Count - 1;
  while (I > 0) and (Formatting[I - 1] <> nil) and
    (StackIndex(TInkNode(Formatting[I - 1])) < 0) do Dec(I);
  for J := I to Formatting.Count - 1 do
  begin
    C := TInkNode(Formatting[J]).Clone(False);
    InsertNode(C);
    Stack.Add(C);
    Formatting[J] := C;
  end;
end;

{ The standard's adoption agency: an end tag for a formatting element that
  is not the current node - <b>one<i>two</b>three</i> - closes it where it
  stands and carries the elements inside it over.  False when the end tag
  is to be handled as any other. }
function TParser.AdoptionAgency(const ATag: string): Boolean;
var Outer, Inner, I, FEIndex, Bookmark, NodeIndex: Integer;
  FE, FurthestBlock, Common, Node, LastNode, NewEl, C: TInkNode;
begin
  Result := True;
  if (Current <> nil) and (Current.Namespace = insHTML) and (Current.Name = ATag) and
    (Formatting.IndexOf(Current) < 0) then
  begin
    Pop;
    Exit;
  end;
  for Outer := 1 to 8 do
  begin
    FE := nil;
    for I := Formatting.Count - 1 downto 0 do
    begin
      if Formatting[I] = nil then Break;
      if TInkNode(Formatting[I]).Name = ATag then begin FE := TInkNode(Formatting[I]); Break end;
    end;
    if FE = nil then Exit(False);
    FEIndex := StackIndex(FE);
    if FEIndex < 0 then begin RemoveFormatting(FE); Exit end;
    if not InScope(ATag, []) then Exit;
    FurthestBlock := nil;
    for I := FEIndex + 1 to Stack.Count - 1 do
      if IsSpecial(TInkNode(Stack[I])) then begin FurthestBlock := TInkNode(Stack[I]); Break end;
    if FurthestBlock = nil then
    begin
      while Stack.Count > FEIndex do Pop;
      RemoveFormatting(FE);
      Exit;
    end;
    Common := TInkNode(Stack[FEIndex - 1]);
    Bookmark := Formatting.IndexOf(FE);
    Node := FurthestBlock; LastNode := FurthestBlock;
    NodeIndex := StackIndex(FurthestBlock);
    Inner := 0;
    while True do
    begin
      Inc(Inner);
      Dec(NodeIndex);
      Node := TInkNode(Stack[NodeIndex]);
      if Node = FE then Break;
      if (Inner > 3) and (Formatting.IndexOf(Node) >= 0) then
      begin
        if Formatting.IndexOf(Node) < Bookmark then Dec(Bookmark);
        RemoveFormatting(Node);
      end;
      if Formatting.IndexOf(Node) < 0 then
      begin
        Stack.Delete(NodeIndex);
        Continue;
      end;
      NewEl := Node.Clone(False);
      Formatting[Formatting.IndexOf(Node)] := NewEl;
      Stack[NodeIndex] := NewEl;
      Node := NewEl;
      if LastNode = FurthestBlock then Bookmark := Formatting.IndexOf(NewEl) + 1;
      Node.AppendChild(LastNode);
      LastNode := Node;
    end;
    { the last node goes where the common ancestor takes children }
    LastNode.Remove;
    if (Common.Namespace = insHTML) and
      InList(Common.Name, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
    begin
      Stack.Add(Common);
      FosterParenting := True;
      InsertNode(LastNode);
      FosterParenting := False;
      Stack.Delete(Stack.Count - 1);
    end
    else Common.AppendChild(LastNode);
    NewEl := FE.Clone(False);
    while FurthestBlock.FirstChild <> nil do
    begin
      C := FurthestBlock.FirstChild;
      NewEl.AppendChild(C);
    end;
    FurthestBlock.AppendChild(NewEl);
    I := Formatting.IndexOf(FE);
    if I < Bookmark then Dec(Bookmark);
    Formatting.Delete(I);
    if Bookmark > Formatting.Count then Bookmark := Formatting.Count;
    Formatting.Insert(Bookmark, NewEl);
    Stack.Delete(StackIndex(FE));
    Stack.Insert(StackIndex(FurthestBlock) + 1, NewEl);
  end;
end;

procedure TParser.AnyOtherEnd(const ATag: string);
var I: Integer; N: TInkNode;
begin
  for I := Stack.Count - 1 downto 0 do
  begin
    N := TInkNode(Stack[I]);
    if (N.Namespace = insHTML) and (N.Name = ATag) then
    begin
      GenerateImpliedEnd(ATag);
      while Stack.Count > I do Pop;
      Exit;
    end;
    if IsSpecial(N) then Exit;
  end;
end;

procedure TParser.StartRaw(const T: TToken; AState: TTokState);
begin
  Insert(T);
  State := AState;
  RawEnd := T.Name;
  OriginalMode := Mode;
  Mode := imText;
end;

{ ------------------------------------------------------------ the modes }

procedure TParser.InHead(var T: TToken; out Reprocess: Boolean);
var Sp, Rest: string;
begin
  Reprocess := False;
  case T.Kind of
    tkText:
      begin
        SplitSpace(T.Data, Sp, Rest);
        InsertText(Sp);
        if Rest = '' then Exit;
        T.Data := Rest;
      end;
    tkComment: begin InsertComment(T.Data); Exit end;
    tkDoctype: Exit;
    tkStart:
      begin
        if InList(T.Name, ['base','basefont','bgsound','link','meta']) then
        begin
          Insert(T); Pop; Exit;
        end;
        if T.Name = 'title' then begin StartRaw(T, tsRCData); Exit end;
        if InList(T.Name, ['noframes', 'style']) then begin StartRaw(T, tsRawText); Exit end;
        if T.Name = 'script' then begin StartRaw(T, tsRawText); Exit end;
        if T.Name = 'head' then Exit;
        { never any script here, so what a page says to do without it goes
          in the head too: <noscript><link rel=stylesheet ...> }
        if T.Name = 'noscript' then begin Insert(T); Mode := imInHeadNoscript; Exit end;
        if T.Name = 'template' then begin StartTemplate(T); Exit end;
      end;
    tkEnd:
      begin
        if T.Name = 'template' then begin EndTemplate; Exit end;
        if T.Name = 'head' then
        begin
          Pop; Mode := imAfterHead; Exit;
        end;
        if not InList(T.Name, ['body', 'html', 'br']) then Exit;
      end;
  end;
  { anything else ends the head }
  Pop;
  Mode := imAfterHead;
  Reprocess := True;
end;

procedure TParser.InBody(var T: TToken);
begin
  case T.Kind of
    tkText:
      begin
        { the line break straight after <pre> is not part of it }
        if SkipNewline and (T.Data <> '') and (T.Data[1] = #10) then Delete(T.Data, 1, 1);
        SkipNewline := False;
        ReconstructFormatting;
        InsertText(T.Data);
        if not AllSpace(T.Data) then FramesetOK := False;
      end;
    tkComment: InsertComment(T.Data);
    tkDoctype: ;
    tkStart: InBodyStart(T);
    tkEnd: InBodyEnd(T);
  end;
end;

procedure TParser.InBodyStart(var T: TToken);
var N, B: TInkNode; I, K: Integer;
begin
  if T.Name = 'html' then
  begin
    N := TInkNode(Stack[0]);
    for I := 0 to High(T.Attrs) do
      if not N.HasAttribute(T.Attrs[I].Name) then N.SetAttribute(T.Attrs[I].Name, T.Attrs[I].Value);
    Exit;
  end;
  if InList(T.Name, ['base','basefont','bgsound','link','meta']) then
  begin
    Insert(T); Pop; Exit;
  end;
  if T.Name = 'title' then begin StartRaw(T, tsRCData); Exit end;
  if InList(T.Name, ['noframes', 'style', 'script']) then begin StartRaw(T, tsRawText); Exit end;
  if T.Name = 'template' then begin StartTemplate(T); Exit end;
  if T.Name = 'body' then
  begin
    if (Stack.Count > 1) and TInkNode(Stack[1]).IsElement('body') then
    begin
      FramesetOK := False;
      B := TInkNode(Stack[1]);
      for I := 0 to High(T.Attrs) do
        if not B.HasAttribute(T.Attrs[I].Name) then B.SetAttribute(T.Attrs[I].Name, T.Attrs[I].Value);
    end;
    Exit;
  end;
  if T.Name = 'frameset' then
  begin
    if (Stack.Count < 2) or not TInkNode(Stack[1]).IsElement('body') or not FramesetOK then Exit;
    TInkNode(Stack[1]).Free;
    while Stack.Count > 1 do Pop;
    Insert(T);
    Mode := imInFrameset;
    Exit;
  end;
  if T.Name = 'head' then Exit;
  if InList(T.Name, ['pre','listing','li','dd','dt','button','applet','marquee',
    'object','table','area','br','embed','img','keygen','wbr','hr','textarea',
    'xmp','iframe','select']) or
    ((T.Name = 'input') and not SameText(AttrOf(T, 'type'), 'hidden')) then
    FramesetOK := False;
  if ClosesP(T.Name) then
  begin
    CloseP; Insert(T); Exit;
  end;
  if IsHeading(T.Name) then
  begin
    CloseP;
    if (Current <> nil) and IsHeading(Current.Name) then Pop;
    Insert(T); Exit;
  end;
  if (T.Name = 'pre') or (T.Name = 'listing') then
  begin
    CloseP; Insert(T); SkipNewline := True; Exit;
  end;
  if T.Name = 'form' then
  begin
    if FormEl <> nil then Exit;
    CloseP; FormEl := Insert(T); Exit;
  end;
  if (T.Name = 'li') or (T.Name = 'dd') or (T.Name = 'dt') then
  begin
    for I := Stack.Count - 1 downto 0 do
    begin
      N := TInkNode(Stack[I]);
      if (T.Name = 'li') and N.IsElement('li') then
      begin
        GenerateImpliedEnd('li'); PopUntil('li'); Break;
      end;
      if (T.Name <> 'li') and (N.IsElement('dd') or N.IsElement('dt')) then
      begin
        GenerateImpliedEnd(N.Name); PopUntil(N.Name); Break;
      end;
      if IsSpecial(N) and not InList(N.Name, ['address', 'div', 'p']) then Break;
    end;
    CloseP; Insert(T); Exit;
  end;
  if T.Name = 'plaintext' then
  begin
    CloseP; Insert(T); State := tsPlainText; Exit;
  end;
  if T.Name = 'button' then
  begin
    if InScope('button', []) then
    begin
      GenerateImpliedEnd; PopUntil('button');
    end;
    ReconstructFormatting; Insert(T); Exit;
  end;
  if T.Name = 'a' then
  begin
    for I := Formatting.Count - 1 downto 0 do
    begin
      if Formatting[I] = nil then Break;
      if TInkNode(Formatting[I]).Name = 'a' then
      begin
        { an <a> inside an open <a>: the first one ends here }
        N := TInkNode(Formatting[I]);
        AdoptionAgency('a');
        RemoveFormatting(N);
        K := StackIndex(N);
        if K >= 0 then Stack.Delete(K);
        Break;
      end;
    end;
    ReconstructFormatting;
    PushFormatting(Insert(T));
    Exit;
  end;
  if T.Name = 'nobr' then
  begin
    ReconstructFormatting;
    if InScope('nobr', []) then
    begin
      AdoptionAgency('nobr');
      ReconstructFormatting;
    end;
    PushFormatting(Insert(T));
    Exit;
  end;
  if IsFormatting(T.Name) then
  begin
    ReconstructFormatting;
    PushFormatting(Insert(T));
    Exit;
  end;
  if InList(T.Name, ['applet', 'marquee', 'object']) then
  begin
    ReconstructFormatting; Insert(T); Formatting.Add(nil); Exit;
  end;
  if T.Name = 'table' then
  begin
    if not Doc.Quirks then CloseP;
    Insert(T); Mode := imInTable; Exit;
  end;
  if T.Name = 'image' then T.Name := 'img';
  if InList(T.Name, ['area','br','embed','img','keygen','wbr','input']) then
  begin
    ReconstructFormatting; Insert(T); Pop; Exit;
  end;
  if InList(T.Name, ['param', 'source', 'track']) then
  begin
    Insert(T); Pop; Exit;
  end;
  if T.Name = 'hr' then
  begin
    CloseP; Insert(T); Pop; Exit;
  end;
  if T.Name = 'textarea' then
  begin
    StartRaw(T, tsRCData); SkipNewline := True; Exit;
  end;
  if T.Name = 'xmp' then
  begin
    CloseP; ReconstructFormatting; StartRaw(T, tsRawText); Exit;
  end;
  if (T.Name = 'iframe') or (T.Name = 'noembed') then
  begin
    StartRaw(T, tsRawText); Exit;
  end;
  if T.Name = 'select' then
  begin
    ReconstructFormatting; Insert(T);
    if Mode in [imInTable, imInCaption, imInTableBody, imInRow, imInCell] then
      Mode := imInSelectInTable
    else Mode := imInSelect;
    Exit;
  end;
  if (T.Name = 'optgroup') or (T.Name = 'option') then
  begin
    if (Current <> nil) and Current.IsElement('option') then Pop;
    ReconstructFormatting; Insert(T); Exit;
  end;
  if (T.Name = 'rb') or (T.Name = 'rtc') then
  begin
    if InScope('ruby', []) then GenerateImpliedEnd;
    Insert(T); Exit;
  end;
  if (T.Name = 'rp') or (T.Name = 'rt') then
  begin
    if InScope('ruby', []) then GenerateImpliedEnd('rtc');
    Insert(T); Exit;
  end;
  if T.Name = 'svg' then
  begin
    ReconstructFormatting; Insert(T, insSVG);
    if T.SelfClosing then Pop;
    Exit;
  end;
  if T.Name = 'math' then
  begin
    ReconstructFormatting; Insert(T, insMathML);
    if T.SelfClosing then Pop;
    Exit;
  end;
  if InList(T.Name, ['caption','col','colgroup','frame','tbody','td','tfoot',
    'th','thead','tr']) then Exit;
  ReconstructFormatting;
  Insert(T);
end;

procedure TParser.InBodyEnd(var T: TToken);
var N: TInkNode;
begin
  if T.Name = 'template' then begin EndTemplate; Exit end;
  if (T.Name = 'body') or (T.Name = 'html') then
  begin
    if InScope('body', []) then Mode := imAfterBody;
    Exit;
  end;
  if InList(T.Name, ['address','article','aside','blockquote','button','center',
    'details','dialog','dir','div','dl','fieldset','figcaption','figure',
    'footer','header','hgroup','listing','main','menu','nav','ol','pre',
    'search','section','summary','ul']) then
  begin
    if not InScope(T.Name, []) then Exit;
    GenerateImpliedEnd;
    PopUntil(T.Name);
    Exit;
  end;
  if T.Name = 'form' then
  begin
    N := FormEl; FormEl := nil;
    if (N = nil) or (StackIndex(N) < 0) then Exit;
    GenerateImpliedEnd;
    Stack.Delete(StackIndex(N));
    Exit;
  end;
  if T.Name = 'p' then
  begin
    if not InButtonScope('p') then InsertTag('p');
    CloseP;
    Exit;
  end;
  if T.Name = 'li' then
  begin
    if not InListScope('li') then Exit;
    GenerateImpliedEnd('li'); PopUntil('li');
    Exit;
  end;
  if (T.Name = 'dd') or (T.Name = 'dt') then
  begin
    if not InScope(T.Name, []) then Exit;
    GenerateImpliedEnd(T.Name); PopUntil(T.Name);
    Exit;
  end;
  if IsHeading(T.Name) then
  begin
    if not HeadingInScope then Exit;
    GenerateImpliedEnd;
    PopUntilAny(['h1','h2','h3','h4','h5','h6']);
    Exit;
  end;
  if IsFormatting(T.Name) then
  begin
    if not AdoptionAgency(T.Name) then AnyOtherEnd(T.Name);
    Exit;
  end;
  if InList(T.Name, ['applet', 'marquee', 'object']) then
  begin
    if not InScope(T.Name, []) then Exit;
    GenerateImpliedEnd; PopUntil(T.Name); ClearFormattingToMarker;
    Exit;
  end;
  if T.Name = 'br' then
  begin
    T.Kind := tkStart; T.Attrs := nil;
    ReconstructFormatting; Insert(T); Pop;
    Exit;
  end;
  AnyOtherEnd(T.Name);
end;

procedure TParser.InTable(var T: TToken; out Reprocess: Boolean);
var I: Integer; Hidden: Boolean;
begin
  Reprocess := False;
  case T.Kind of
    tkText:
      if AllSpace(T.Data) and (Current <> nil) and
        InList(Current.Name, ['table','tbody','tfoot','thead','tr']) then
      begin
        InsertText(T.Data); Exit;
      end;
    tkComment: begin InsertComment(T.Data); Exit end;
    tkDoctype: Exit;
    tkStart:
      begin
        if T.Name = 'caption' then
        begin
          ClearToContext(['table']); Formatting.Add(nil);
          Insert(T); Mode := imInCaption; Exit;
        end;
        if T.Name = 'colgroup' then
        begin
          ClearToContext(['table']); Insert(T); Mode := imInColumnGroup; Exit;
        end;
        if T.Name = 'col' then
        begin
          ClearToContext(['table']); InsertTag('colgroup'); Mode := imInColumnGroup;
          Reprocess := True; Exit;
        end;
        if InList(T.Name, ['tbody', 'tfoot', 'thead']) then
        begin
          ClearToContext(['table']); Insert(T); Mode := imInTableBody; Exit;
        end;
        if InList(T.Name, ['td', 'th', 'tr']) then
        begin
          ClearToContext(['table']); InsertTag('tbody'); Mode := imInTableBody;
          Reprocess := True; Exit;
        end;
        if T.Name = 'table' then
        begin
          if not InTableScope('table') then Exit;
          PopUntil('table'); ResetMode; Reprocess := True; Exit;
        end;
        if InList(T.Name, ['style', 'script', 'template']) then
        begin
          if T.Name = 'template' then StartTemplate(T) else StartRaw(T, tsRawText);
          Exit;
        end;
        if T.Name = 'input' then
        begin
          Hidden := False;
          for I := 0 to High(T.Attrs) do
            if (T.Attrs[I].Name = 'type') and SameText(T.Attrs[I].Value, 'hidden') then Hidden := True;
          if Hidden then begin Insert(T); Pop; Exit end;
        end;
        if T.Name = 'form' then
        begin
          if FormEl = nil then begin FormEl := Insert(T); Pop end;
          Exit;
        end;
      end;
    tkEnd:
      begin
        if T.Name = 'table' then
        begin
          if not InTableScope('table') then Exit;
          PopUntil('table'); ResetMode; Exit;
        end;
        if T.Name = 'template' then begin EndTemplate; Exit end;
        if InList(T.Name, ['body','caption','col','colgroup','html','tbody','td',
          'tfoot','th','thead','tr']) then Exit;
      end;
  end;
  { anything else is body content, moved out in front of the table }
  FosterParenting := True;
  try
    InBody(T);
  finally
    FosterParenting := False;
  end;
end;

procedure TParser.CloseCell;
begin
  GenerateImpliedEnd;
  PopUntilAny(['td', 'th']);
  ClearFormattingToMarker;
  Mode := imInRow;
end;

function TParser.TemplateOpen: Boolean;
var I: Integer;
begin
  for I := Stack.Count - 1 downto 0 do
    if TInkNode(Stack[I]).IsElement('template') then Exit(True);
  Result := False;
end;

procedure TParser.StartTemplate(const T: TToken);
begin
  Insert(T);
  Formatting.Add(nil);
  FramesetOK := False;
  Mode := imInTemplate;
  SetLength(TemplateModes, Length(TemplateModes) + 1);
  TemplateModes[High(TemplateModes)] := imInTemplate;
end;

procedure TParser.EndTemplate;
begin
  if not TemplateOpen then Exit;
  while (Current <> nil) and (Current.Namespace = insHTML) and
    (ImpliedEnd(Current.Name) or InList(Current.Name, ['caption','colgroup',
      'tbody','td','tfoot','th','thead','tr'])) do Pop;
  PopUntil('template');
  ClearFormattingToMarker;
  if Length(TemplateModes) > 0 then SetLength(TemplateModes, Length(TemplateModes) - 1);
  ResetMode;
end;

function TParser.UseForeign(const T: TToken): Boolean;
var N: TInkNode;
begin
  N := AdjustedCurrent;
  Result := False;
  if (N = nil) or (N.Namespace = insHTML) or (T.Kind = tkEOF) then Exit;
  { the places inside a drawing where HTML is read again }
  if (N.Namespace = insSVG) and InList(N.Name, ['foreignObject', 'desc', 'title']) and
    (T.Kind in [tkStart, tkText]) then Exit;
  if (N.Namespace = insMathML) and InList(N.Name, ['mi','mo','mn','ms','mtext']) and
    ((T.Kind = tkText) or ((T.Kind = tkStart) and (T.Name <> 'mglyph') and
      (T.Name <> 'malignmark'))) then Exit;
  if (N.Namespace = insMathML) and (N.Name = 'annotation-xml') and
    (T.Kind in [tkStart, tkText]) and
    (SameText(N.GetAttribute('encoding'), 'text/html') or
     SameText(N.GetAttribute('encoding'), 'application/xhtml+xml')) then Exit;
  if (N.Namespace = insMathML) and (N.Name = 'annotation-xml') and
    (T.Kind = tkStart) and (T.Name = 'svg') then Exit;
  Result := True;
end;

procedure TParser.InForeign(var T: TToken; out Reprocess: Boolean);
var I: Integer; N: TInkNode; IsFontBreak: Boolean;
begin
  Reprocess := False;
  case T.Kind of
    tkText:
      begin
        InsertText(T.Data);
        if not AllSpace(T.Data) then FramesetOK := False;
      end;
    tkComment: InsertComment(T.Data);
    tkStart:
      begin
        IsFontBreak := False;
        if T.Name = 'font' then
          for I := 0 to High(T.Attrs) do
            if InList(T.Attrs[I].Name, ['color', 'face', 'size']) then IsFontBreak := True;
        if InList(T.Name, BreakoutTags) or IsFontBreak then
        begin
          { the drawing was never closed: back out to HTML }
          while (Current <> nil) and (Current.Namespace <> insHTML) and
            not ((Current.Namespace = insSVG) and
              InList(Current.Name, ['foreignObject', 'desc', 'title'])) do Pop;
          Reprocess := True;
          Exit;
        end;
        Insert(T, AdjustedCurrent.Namespace);
        if T.SelfClosing then Pop;
      end;
    tkEnd:
      begin
        for I := Stack.Count - 1 downto 1 do
        begin
          N := TInkNode(Stack[I]);
          if N.Namespace = insHTML then
          begin
            { an HTML element: the end tag is the HTML mode's to handle }
            Reprocess := True;
            Exit;
          end;
          if LowerCase(N.Name) = T.Name then
          begin
            while Stack.Count > I do Pop;
            Exit;
          end;
        end;
      end;
  end;
end;

procedure TParser.Process(var T: TToken);
var Again: Boolean; Sp, Rest: string; N: TInkNode;
begin
  { only the token straight after <pre> or <textarea> can lose a newline }
  if T.Kind <> tkText then SkipNewline := False;
  repeat
    Again := False;
    if UseForeign(T) then
    begin
      InForeign(T, Again);
      if not Again then Exit;
      { back out of the drawing: the mode handles it }
      Again := False;
    end;
    case Mode of
      imInitial:
        begin
          if (T.Kind = tkText) then
          begin
            SplitSpace(T.Data, Sp, Rest);
            if Rest = '' then Exit;
            T.Data := Rest;
          end;
          if T.Kind = tkComment then begin InsertComment(T.Data, Doc); Exit end;
          if T.Kind = tkDoctype then
          begin
            N := TInkNode.Create(inkDoctype, T.Name);
            if T.HasPublic or T.HasSystem then
            begin
              N.SetAttribute('publicid', T.PublicId);
              N.SetAttribute('systemid', T.SystemId);
            end;
            Doc.AppendChild(N);
            Doc.Quirks := DoctypeQuirks(T);
            Mode := imBeforeHtml;
            Exit;
          end;
          Doc.Quirks := True;
          Mode := imBeforeHtml;
          Again := True;
        end;
      imBeforeHtml:
        begin
          if T.Kind = tkDoctype then Exit;
          if T.Kind = tkComment then begin InsertComment(T.Data, Doc); Exit end;
          if T.Kind = tkText then
          begin
            SplitSpace(T.Data, Sp, Rest);
            if Rest = '' then Exit;
            T.Data := Rest;
          end;
          if (T.Kind = tkStart) and (T.Name = 'html') then
          begin
            Insert(T); Mode := imBeforeHead; Exit;
          end;
          if (T.Kind = tkEnd) and not InList(T.Name, ['head','body','html','br']) then Exit;
          InsertTag('html'); Mode := imBeforeHead; Again := True;
        end;
      imBeforeHead:
        begin
          if T.Kind = tkText then
          begin
            SplitSpace(T.Data, Sp, Rest);
            if Rest = '' then Exit;
            T.Data := Rest;
          end;
          if T.Kind = tkComment then begin InsertComment(T.Data); Exit end;
          if T.Kind = tkDoctype then Exit;
          if (T.Kind = tkStart) and (T.Name = 'html') then begin InBodyStart(T); Exit end;
          if (T.Kind = tkStart) and (T.Name = 'head') then
          begin
            HeadEl := Insert(T); Mode := imInHead; Exit;
          end;
          if (T.Kind = tkEnd) and not InList(T.Name, ['head','body','html','br']) then Exit;
          HeadEl := InsertTag('head'); Mode := imInHead; Again := True;
        end;
      imInHead:
        InHead(T, Again);
      imAfterHead:
        begin
          if T.Kind = tkText then
          begin
            SplitSpace(T.Data, Sp, Rest);
            InsertText(Sp);
            if Rest = '' then Exit;
            T.Data := Rest;
          end;
          if T.Kind = tkComment then begin InsertComment(T.Data); Exit end;
          if T.Kind = tkDoctype then Exit;
          if T.Kind = tkStart then
          begin
            if T.Name = 'html' then begin InBodyStart(T); Exit end;
            if T.Name = 'body' then begin Insert(T); FramesetOK := False; Mode := imInBody; Exit end;
            if T.Name = 'frameset' then begin Insert(T); Mode := imInFrameset; Exit end;
            if InList(T.Name, ['base','basefont','bgsound','link','meta','noframes',
              'script','style','template','title']) then
            begin
              { late head content still belongs to the head }
              Stack.Add(HeadEl);
              InHead(T, Again);
              Stack.Remove(HeadEl);
              Exit;
            end;
            if T.Name = 'head' then Exit;
          end;
          if (T.Kind = tkEnd) and not InList(T.Name, ['body','html','br']) then Exit;
          InsertTag('body'); Mode := imInBody; Again := True;
        end;
      imInBody:
        InBody(T);
      imText:
        begin
          if T.Kind = tkText then
          begin
            if SkipNewline then
            begin
              SkipNewline := False;
              if (T.Data <> '') and (T.Data[1] = #10) then Delete(T.Data, 1, 1);
            end;
            InsertText(T.Data);
            Exit;
          end;
          { the end tag, or the end of the input }
          Pop;
          State := tsData;
          Mode := OriginalMode;
          if T.Kind = tkEOF then Again := True;
        end;
      imInTable:
        InTable(T, Again);
      imInCaption:
        begin
          if ((T.Kind = tkEnd) and (T.Name = 'caption')) or
            ((T.Kind = tkStart) and InList(T.Name, ['caption','col','colgroup',
              'tbody','td','tfoot','th','thead','tr'])) or
            ((T.Kind = tkEnd) and (T.Name = 'table')) then
          begin
            if not InTableScope('caption') then Exit;
            GenerateImpliedEnd; PopUntil('caption'); ClearFormattingToMarker;
            Mode := imInTable;
            Again := not ((T.Kind = tkEnd) and (T.Name = 'caption'));
            Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['body','col','colgroup','html',
            'tbody','td','tfoot','th','thead','tr']) then Exit;
          InBody(T);
        end;
      imInColumnGroup:
        begin
          if (T.Kind = tkText) then
          begin
            SplitSpace(T.Data, Sp, Rest);
            InsertText(Sp);
            if Rest = '' then Exit;
            T.Data := Rest;
          end
          else if T.Kind = tkComment then begin InsertComment(T.Data); Exit end
          else if (T.Kind = tkStart) and (T.Name = 'col') then begin Insert(T); Pop; Exit end
          else if (T.Kind = tkEnd) and (T.Name = 'colgroup') then
          begin
            if (Current <> nil) and Current.IsElement('colgroup') then
            begin
              Pop; Mode := imInTable;
            end;
            Exit;
          end
          else if (T.Kind = tkEnd) and (T.Name = 'col') then Exit;
          if (Current <> nil) and Current.IsElement('colgroup') then
          begin
            Pop; Mode := imInTable; Again := True;
          end;
        end;
      imInTableBody:
        begin
          if (T.Kind = tkStart) and (T.Name = 'tr') then
          begin
            ClearToContext(['tbody','tfoot','thead']); Insert(T); Mode := imInRow; Exit;
          end;
          if (T.Kind = tkStart) and ((T.Name = 'th') or (T.Name = 'td')) then
          begin
            ClearToContext(['tbody','tfoot','thead']); InsertTag('tr');
            Mode := imInRow; Again := True; Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['tbody','tfoot','thead']) then
          begin
            if not InTableScope(T.Name) then Exit;
            ClearToContext(['tbody','tfoot','thead']); Pop; Mode := imInTable; Exit;
          end;
          if ((T.Kind = tkStart) and InList(T.Name, ['caption','col','colgroup',
            'tbody','tfoot','thead'])) or ((T.Kind = tkEnd) and (T.Name = 'table')) then
          begin
            if not (InTableScope('tbody') or InTableScope('thead') or InTableScope('tfoot')) then Exit;
            ClearToContext(['tbody','tfoot','thead']); Pop; Mode := imInTable;
            Again := True; Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['body','caption','col','colgroup',
            'html','td','th','tr']) then Exit;
          InTable(T, Again);
        end;
      imInRow:
        begin
          if (T.Kind = tkStart) and ((T.Name = 'th') or (T.Name = 'td')) then
          begin
            ClearToContext(['tr']); Insert(T); Mode := imInCell; Formatting.Add(nil);
            Exit;
          end;
          if (T.Kind = tkEnd) and (T.Name = 'tr') then
          begin
            if not InTableScope('tr') then Exit;
            ClearToContext(['tr']); Pop; Mode := imInTableBody; Exit;
          end;
          if ((T.Kind = tkStart) and InList(T.Name, ['caption','col','colgroup',
            'tbody','tfoot','thead','tr'])) or ((T.Kind = tkEnd) and (T.Name = 'table')) then
          begin
            if not InTableScope('tr') then Exit;
            ClearToContext(['tr']); Pop; Mode := imInTableBody;
            Again := True; Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['tbody','tfoot','thead']) then
          begin
            if not InTableScope(T.Name) or not InTableScope('tr') then Exit;
            ClearToContext(['tr']); Pop; Mode := imInTableBody;
            Again := True; Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['body','caption','col','colgroup',
            'html','td','th']) then Exit;
          InTable(T, Again);
        end;
      imInCell:
        begin
          if (T.Kind = tkEnd) and ((T.Name = 'td') or (T.Name = 'th')) then
          begin
            if not InTableScope(T.Name) then Exit;
            CloseCell;
            Exit;
          end;
          if (T.Kind = tkStart) and InList(T.Name, ['caption','col','colgroup',
            'tbody','td','tfoot','th','thead','tr']) then
          begin
            if not (InTableScope('td') or InTableScope('th')) then Exit;
            CloseCell; Again := True; Continue;
          end;
          if (T.Kind = tkEnd) and InList(T.Name, ['body','caption','col','colgroup','html']) then Exit;
          if (T.Kind = tkEnd) and InList(T.Name, ['table','tbody','tfoot','thead','tr']) then
          begin
            if not InTableScope(T.Name) then Exit;
            CloseCell; Again := True; Continue;
          end;
          InBody(T);
        end;
      imInSelect, imInSelectInTable:
        begin
          if (Mode = imInSelectInTable) and (((T.Kind = tkStart) or (T.Kind = tkEnd)) and
            InList(T.Name, ['caption','table','tbody','tfoot','thead','tr','td','th'])) then
          begin
            if (T.Kind = tkEnd) and not InTableScope(T.Name) then Exit;
            PopUntil('select'); ResetMode; Again := True; Continue;
          end;
          case T.Kind of
            tkText: InsertText(T.Data);
            tkComment: InsertComment(T.Data);
            tkStart:
              if T.Name = 'option' then
              begin
                if (Current <> nil) and Current.IsElement('option') then Pop;
                Insert(T);
              end
              else if T.Name = 'optgroup' then
              begin
                if (Current <> nil) and Current.IsElement('option') then Pop;
                if (Current <> nil) and Current.IsElement('optgroup') then Pop;
                Insert(T);
              end
              else if T.Name = 'hr' then
              begin
                if (Current <> nil) and Current.IsElement('option') then Pop;
                if (Current <> nil) and Current.IsElement('optgroup') then Pop;
                Insert(T); Pop;
              end
              else if (T.Name = 'select') then
              begin
                if InScope('select', [], True) then begin PopUntil('select'); ResetMode end;
              end
              else if InList(T.Name, ['input', 'keygen', 'textarea']) then
              begin
                if not InScope('select', [], True) then Exit;
                PopUntil('select'); ResetMode; Again := True; Continue;
              end
              else if InList(T.Name, ['script', 'style']) then StartRaw(T, tsRawText);
            tkEnd:
              if T.Name = 'optgroup' then
              begin
                if (Current <> nil) and Current.IsElement('option') and (Stack.Count > 1) and
                  TInkNode(Stack[Stack.Count - 2]).IsElement('optgroup') then Pop;
                if (Current <> nil) and Current.IsElement('optgroup') then Pop;
              end
              else if T.Name = 'option' then
              begin
                if (Current <> nil) and Current.IsElement('option') then Pop;
              end
              else if T.Name = 'select' then
              begin
                if InScope('select', [], True) then begin PopUntil('select'); ResetMode end;
              end;
          end;
        end;
      imInTemplate:
        begin
          case T.Kind of
            tkText, tkComment, tkDoctype: InBody(T);
            tkStart:
              if InList(T.Name, ['base','basefont','bgsound','link','meta',
                'noframes','script','style','template','title']) then InHead(T, Again)
              else
              begin
                if InList(T.Name, ['caption','colgroup','tbody','tfoot','thead']) then Mode := imInTable
                else if T.Name = 'col' then Mode := imInColumnGroup
                else if T.Name = 'tr' then Mode := imInTableBody
                else if (T.Name = 'td') or (T.Name = 'th') then Mode := imInRow
                else Mode := imInBody;
                TemplateModes[High(TemplateModes)] := Mode;
                Again := True;
              end;
            tkEnd:
              if T.Name = 'template' then EndTemplate;
            tkEOF:
              if TemplateOpen then
              begin
                PopUntil('template');
                ClearFormattingToMarker;
                SetLength(TemplateModes, Length(TemplateModes) - 1);
                ResetMode;
                Again := True;
              end;
          end;
        end;
      imInHeadNoscript:
        begin
          if (T.Kind = tkEnd) and (T.Name = 'noscript') then
          begin
            Pop; Mode := imInHead; Exit;
          end;
          if (T.Kind = tkComment) or ((T.Kind = tkText) and AllSpace(T.Data)) or
            ((T.Kind = tkStart) and InList(T.Name, ['basefont','bgsound','link',
              'meta','noframes','style'])) then
          begin
            InHead(T, Again);
            Exit;
          end;
          if (T.Kind = tkDoctype) or ((T.Kind = tkStart) and InList(T.Name, ['head', 'noscript'])) or
            ((T.Kind = tkEnd) and (T.Name <> 'br')) then Exit;
          { anything else ends the noscript, and then the head }
          Pop; Mode := imInHead; Again := True;
        end;
      imInFrameset, imAfterFrameset, imAfterAfterFrameset:
        begin
          case T.Kind of
            tkText:
              begin
                { only the white space between frames is kept }
                Rest := SpaceOnly(T.Data);
                if Mode = imAfterAfterFrameset then
                begin
                  if Rest <> '' then begin T.Data := Rest; InBody(T) end;
                end
                else InsertText(Rest);
              end;
            tkComment:
              if Mode = imAfterAfterFrameset then InsertComment(T.Data, Doc)
              else InsertComment(T.Data);
            tkStart:
              if T.Name = 'html' then InBodyStart(T)
              else if T.Name = 'noframes' then StartRaw(T, tsRawText)
              else if Mode = imInFrameset then
              begin
                if T.Name = 'frameset' then Insert(T)
                else if T.Name = 'frame' then begin Insert(T); Pop end;
              end;
            tkEnd:
              if (Mode = imInFrameset) and (T.Name = 'frameset') then
              begin
                if (Current <> nil) and not Current.IsElement('html') then Pop;
                if (FragmentContext = nil) and (Current <> nil) and not Current.IsElement('frameset') then
                  Mode := imAfterFrameset;
              end
              else if (Mode = imAfterFrameset) and (T.Name = 'html') then
                Mode := imAfterAfterFrameset;
          end;
        end;
      imAfterBody, imAfterAfterBody:
        begin
          if T.Kind = tkComment then
          begin
            if Mode = imAfterBody then InsertComment(T.Data, TInkNode(Stack[0]))
            else InsertComment(T.Data, Doc);
            Exit;
          end;
          if T.Kind = tkDoctype then Exit;
          if (T.Kind = tkText) and AllSpace(T.Data) then begin InBody(T); Exit end;
          if (T.Kind = tkEnd) and (T.Name = 'html') then
          begin
            Mode := imAfterAfterBody; Exit;
          end;
          if T.Kind = tkEOF then Exit;
          { content after </body> or </html> is still the body's }
          Mode := imInBody; Again := True;
        end;
    end;
  until not Again;
end;

procedure TParser.Run;
var T: TToken;
begin
  repeat
    T := NextToken;
    Process(T);
  until T.Kind = tkEOF;
  { whatever went wrong, a document has its three elements }
  if Doc.DocumentElement = nil then Doc.AppendChild(TInkNode.Create(inkElement, 'html'));
  if Doc.Head = nil then
    Doc.DocumentElement.InsertBefore(TInkNode.Create(inkElement, 'head'),
      Doc.DocumentElement.FirstChild);
  if (Doc.Body = nil) and (ChildElement(Doc.DocumentElement, 'frameset') = nil) then
    Doc.DocumentElement.AppendChild(TInkNode.Create(inkElement, 'body'));
end;

function InkParseHTML(const AHTML: string): TInkDocument;
var Parser: TParser;
begin
  Parser := TParser.Create(AHTML);
  try
    try
      Parser.Run;
    except
      { a parser bug must never take the page down with it: what was built
        so far is the document }
    end;
    Result := Parser.Doc;
  finally
    Parser.Free;
  end;
end;

procedure InkParseFragment(const AHTML: string; AContext: TInkNode);
var Parser: TParser; Root, N: TInkNode; T: TToken; Ctx: string;
begin
  Parser := TParser.Create(AHTML);
  try
    Root := TInkNode.Create(inkElement, 'html');
    Parser.Doc.AppendChild(Root);
    Parser.Stack.Add(Root);
    Parser.FragmentContext := AContext;
    Ctx := AContext.Name;
    if AContext.Namespace = insHTML then
    begin
      if (Ctx = 'title') or (Ctx = 'textarea') then
      begin
        Parser.State := tsRCData; Parser.RawEnd := Ctx;
      end
      else if InList(Ctx, ['style','xmp','iframe','noembed','noframes','script']) then
      begin
        Parser.State := tsRawText; Parser.RawEnd := Ctx;
      end
      else if Ctx = 'plaintext' then Parser.State := tsPlainText;
    end;
    Parser.ResetMode;
    if Parser.State <> tsData then
    begin
      { the whole of it is text }
      repeat
        T := Parser.NextToken;
        if T.Kind = tkText then Parser.InsertText(T.Data);
      until T.Kind = tkEOF;
    end
    else
      try
        repeat
          T := Parser.NextToken;
          Parser.Process(T);
        until T.Kind = tkEOF;
      except
      end;
    while Root.FirstChild <> nil do
    begin
      N := Root.FirstChild;
      AContext.AppendChild(N);
    end;
  finally
    Parser.Doc.Free;
    Parser.Free;
  end;
end;

{ --------------------------------------------------------- serializing }

function EscapeText(const S: string; InAttribute: Boolean): string;
var I, Start: Integer; R: string;
begin
  Result := ''; Start := 1; I := 1;
  while I <= Length(S) do
  begin
    R := '';
    case S[I] of
      '&': R := '&amp;';
      '"': if InAttribute then R := '&quot;';
      '<': if not InAttribute then R := '&lt;';
      '>': if not InAttribute then R := '&gt;';
      #$C2: if (I < Length(S)) and (S[I + 1] = #$A0) then R := '&nbsp;';
    end;
    if R <> '' then
    begin
      Result := Result + Copy(S, Start, I - Start) + R;
      if S[I] = #$C2 then Inc(I);
      Start := I + 1;
    end;
    Inc(I);
  end;
  if Start = 1 then Result := S
  else Result := Result + Copy(S, Start, MaxInt);
end;

procedure Serialize(N: TInkNode; var Out_: string);
var C: TInkNode; I: Integer; Raw: Boolean;
begin
  case N.Kind of
    inkDocument:
      begin
        C := N.FirstChild;
        while C <> nil do begin Serialize(C, Out_); C := C.NextSibling end;
      end;
    inkDoctype: Out_ := Out_ + '<!DOCTYPE ' + N.Name + '>';
    inkComment: Out_ := Out_ + '<!--' + N.Data + '-->';
    inkText:
      begin
        Raw := (N.Parent <> nil) and (N.Parent.Namespace = insHTML) and
          InList(N.Parent.Name, ['style','script','xmp','iframe','noembed',
            'noframes','plaintext']);
        if Raw then Out_ := Out_ + N.Data
        else Out_ := Out_ + EscapeText(N.Data, False);
      end;
    inkElement:
      begin
        Out_ := Out_ + '<' + N.Name;
        for I := 0 to High(N.FAttrs) do
          Out_ := Out_ + ' ' + N.FAttrs[I].Name + '="' + EscapeText(N.FAttrs[I].Value, True) + '"';
        Out_ := Out_ + '>';
        if (N.Namespace = insHTML) and InkIsVoidElement(N.Name) then Exit;
        { a newline that opens a <pre> would be eaten by the next parser }
        if (N.Namespace = insHTML) and InList(N.Name, ['pre', 'textarea', 'listing']) and
          (N.FirstChild <> nil) and (N.FirstChild.Kind = inkText) and
          (N.FirstChild.Data <> '') and (N.FirstChild.Data[1] = #10) then
          Out_ := Out_ + #10;
        C := N.FirstChild;
        while C <> nil do begin Serialize(C, Out_); C := C.NextSibling end;
        Out_ := Out_ + '</' + N.Name + '>';
      end;
  end;
end;

function InkSerializeHTML(ANode: TInkNode): string;
begin
  Result := '';
  if ANode <> nil then Serialize(ANode, Result);
end;

{ ------------------------------------------------------------ encoding }

function IsValidUTF8(const S: RawByteString): Boolean;
var I, N, K: Integer; B: Byte;
begin
  I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then begin Inc(I); Continue end;
    if (B and $E0) = $C0 then N := 1
    else if (B and $F0) = $E0 then N := 2
    else if (B and $F8) = $F0 then N := 3
    else Exit(False);
    if I + N > Length(S) then Exit(False);
    for K := 1 to N do
      if (Ord(S[I + K]) and $C0) <> $80 then Exit(False);
    Inc(I, N + 1);
  end;
  Result := True;
end;

function FromWin1252(const S: RawByteString): string;
var I: Integer; B: Byte;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then Result := Result + Chr(B)
    else if (B <= $9F) and (Win1252[B] <> 0) then Result := Result + InkCodepointToUTF8(Win1252[B])
    else Result := Result + InkCodepointToUTF8(B);
  end;
end;

function FromUTF16(const S: RawByteString; BigEndian: Boolean): string;
var I: Integer; W: UnicodeString;
begin
  SetLength(W, Length(S) div 2);
  for I := 1 to Length(W) do
    if BigEndian then W[I] := WideChar(Ord(S[2*I - 1]) shl 8 or Ord(S[2*I]))
    else W[I] := WideChar(Ord(S[2*I]) shl 8 or Ord(S[2*I - 1]));
  Result := UTF8Encode(W);
end;

{ the charset a <meta> in the first kilobyte names, lowercase, or '' }
function MetaCharset(const S: RawByteString): string;
var Head: string; P, Q: Integer;
begin
  Result := '';
  Head := LowerCase(Copy(S, 1, 1024));
  P := Pos('charset', Head);
  while P > 0 do
  begin
    Q := P + 7;
    while (Q <= Length(Head)) and (Head[Q] in [' ', #9, #10, #13]) do Inc(Q);
    if (Q <= Length(Head)) and (Head[Q] = '=') then
    begin
      Inc(Q);
      while (Q <= Length(Head)) and (Head[Q] in [' ', #9, #10, #13, '"', '''']) do Inc(Q);
      P := Q;
      while (Q <= Length(Head)) and (Head[Q] in ['a'..'z', '0'..'9', '-', '_', ':', '.']) do Inc(Q);
      Result := Copy(Head, P, Q - P);
      if Result <> '' then Exit;
    end;
    P := PosEx('charset', Head, P + 7);
  end;
end;

function InkDecodeHTML(const ABytes: RawByteString): string;
var Charset, Enc: string;
begin
  if Copy(ABytes, 1, 3) = #$EF#$BB#$BF then Exit(Copy(ABytes, 4, MaxInt));
  if Copy(ABytes, 1, 2) = #$FF#$FE then Exit(FromUTF16(Copy(ABytes, 3, MaxInt), False));
  if Copy(ABytes, 1, 2) = #$FE#$FF then Exit(FromUTF16(Copy(ABytes, 3, MaxInt), True));
  Charset := MetaCharset(ABytes);
  if (Charset = '') or (Charset = 'utf-8') or (Charset = 'utf8') then
  begin
    { a page that says nothing, or says UTF-8 and is not, is the code page
      old Windows help was written in }
    if IsValidUTF8(ABytes) then Exit(ABytes);
    Exit(FromWin1252(ABytes));
  end;
  if (Charset = 'windows-1252') or (Charset = 'iso-8859-1') or (Charset = 'latin1') or
    (Charset = 'us-ascii') or (Charset = 'ascii') or (Charset = 'cp1252') then
    Exit(FromWin1252(ABytes));
  { the rest through LazUtils' converters, which name them their own way }
  Enc := StringReplace(Charset, '-', '', [rfReplaceAll]);
  if Copy(Enc, 1, 7) = 'windows' then Enc := 'cp' + Copy(Enc, 8, MaxInt);
  if Enc = 'shiftjis' then Enc := 'cp932'
  else if (Enc = 'gb2312') or (Enc = 'gbk') then Enc := 'cp936'
  else if Enc = 'big5' then Enc := 'cp950'
  else if Enc = 'euckr' then Enc := 'cp949'
  ;
  Result := ConvertEncoding(ABytes, Enc, EncodingUTF8);
  if (Result = ABytes) and not IsValidUTF8(ABytes) then Result := FromWin1252(ABytes);
end;

end.
