{ InkStyle - CSS for a document tree: the cascade a browser runs, giving
  every element its computed style.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors

  What it reads: selectors with every combinator, attribute selectors,
  :nth-child and friends, :not, :is, :where and :has; the cascade's order
  (the browser's sheet, the page's old presentational attributes, the
  page's sheets, the style attribute, !important); inheritance and the
  CSS-wide keywords; custom properties and var(); shorthands taken apart;
  @media, @supports, @import, @layer and nested rules.  What it gives: for
  each element, every property's computed value, with font sizes, weights
  and inherited lengths already in pixels and the rest resolvable through
  the style (Px, Color).

  Needs no widgetset.  A color is TInkRGBA: TColor's bytes in the low
  three, opacity in the top one. }
unit InkStyle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, InkDOM;

type
  TInkRGBA = Cardinal;

  TInkStyleOrigin = (isoUserAgent, isoAuthor);

  { what @media queries are judged against }
  TInkMedia = record
    Width, Height: Integer;
    Dark: Boolean;
    Print: Boolean;
    { set by Compute from the document: the old page rules apply }
    Quirks: Boolean;
  end;

  TInkStyler = class;

  { One element's computed style.  Elements that would compute the same
    share one. }
  TInkStyle = class
  private
    FValues: array of string;
    FCustom: TStringList;
    FOwnsCustom: Boolean;
    FStyler: TInkStyler;
  public
    { the element's font size and the root's, in pixels }
    FontSize, RootFontSize: Double;
    destructor Destroy; override;
    { a property's computed value as text; '' for one LazInk does not know }
    function Value(const AProp: string): string;
    { the same, lowercased and trimmed - for keywords }
    function Keyword(const AProp: string): string;
    { a length property in pixels; a percentage of APercentOf; ADefault for
      auto, none, normal or anything that is not a length }
    function Px(const AProp: string; APercentOf: Double = 0; ADefault: Double = 0): Double;
    { any length text in pixels, the same way }
    function Length(const AValue: string; APercentOf: Double = 0; ADefault: Double = 0): Double;
    { a color property; currentcolor is the element's color }
    function Color(const AProp: string): TInkRGBA;
    { a custom property's value, '' when not set }
    function Custom(const AName: string): string;
  end;

  { the text of a stylesheet at URL, for <link> and @import; '' when it
    cannot be had }
  TInkStyleFetch = function(const URL: string): string of object;

  TInkStyler = class
  private
    FRules: TFPObjectList;
    FRefs: TFPObjectList;
    FById, FByClass, FByTag: TFPHashList;
    FUniversal, FPseudoRefs: TFPList;
    FMediaTexts: TStringList;
    FMediaOK: array of Boolean;
    FStyles: TFPObjectList;
    FShare: TFPObjectHashTable;
    FInfos: TFPList;
    FHintRules: TFPObjectHashTable;
    FOrder: Integer;
    FUAOrder: Integer;
    { cascade layers: the one being read, every name in the order first
      seen, and a count for the nameless ones }
    FLayer: string;
    FLayerNames: TStringList;
    { custom properties registered with @property: name=initial value, and
      in Objects whether they inherit }
    FRegistered: TStringList;
    FAnonLayers: Integer;
    FRoot: TInkNode;
    FRootFont: Double;
    FImportDepth: Integer;
    procedure RegisterLayer(const AName: string);
    function SubLayer(const AName: string): string;
    procedure RankLayers;
    procedure AddRule(const ASelectors: string; const ADecls: string;
      AOrigin: TInkStyleOrigin; const AMedia: array of Integer; const ABase: string);
    procedure ParseSheet(const CSS: string; AOrigin: TInkStyleOrigin;
      const AMedia: array of Integer; const ABase: string; const AParentSel: string = '');
    function MediaIndex(const AText: string): Integer;
    procedure EvaluateMedia;
    procedure Index(ARef: TObject);
    procedure BuildInfos(ARoot: TInkNode);
    function ComputeOne(AInfo: Pointer): TInkStyle;
    function Resolve(const ASpec: array of string; ASpecCustom: TStringList;
      AParent: TInkStyle; AIsRoot: Boolean): TInkStyle;
    function HintDecls(N: TInkNode): TObject;
  public
    Media: TInkMedia;
    OnFetch: TInkStyleFetch;
    { :target, :hover and :focus - the element each means, or none }
    TargetId: string;
    Hover, Focus: TInkNode;
    { what the system colors are: the page's background and text, links }
    CanvasColor, CanvasTextColor, LinkColor, VisitedColor: TInkRGBA;
    constructor Create;
    destructor Destroy; override;
    { the page's sheets go; the browser's own stays }
    procedure Clear;
    procedure AddSheet(const CSS: string; const BaseURL: string = '');
    { every <style> and <link rel=stylesheet> in the document, in order }
    procedure AddDocumentSheets(ADoc: TInkDocument; const BaseURL: string);
    { computes every element under ARoot; StyleOf answers after }
    procedure Compute(ARoot: TInkNode);
    { what Compute hung on the tree is taken off it again; with
      ATouchNodes off, only forgotten - for a tree that may have lost nodes
      since, as a document changed by its program has }
    procedure Release(ATouchNodes: Boolean = True);
    function StyleOf(N: TInkNode): TInkStyle;
    { a ::before / ::after / ::marker style, or nil when no rule asks }
    function PseudoStyleOf(N: TInkNode; const APseudo: string): TInkStyle;
    function RuleCount: Integer;
    { the rules that match N, weakest first, as "selector { declarations }"
      - what a browser's inspector shows; after Compute }
    function Explain(N: TInkNode): TStringList;
    { how many distinct computed styles the last Compute made }
    function StyleCount: Integer;
  end;

{ #rgb, #rrggbb, rgb(), hsl(), a name, transparent - False when not a color }
function InkParseColor(const S: string; out C: TInkRGBA; ADark: Boolean = False): Boolean;
{ whether N matches a selector list - False for one that does not parse }
function InkMatches(N: TInkNode; const ASelector: string): Boolean;
{ whether a selector list parses - a rule with one that does not is dropped }
function InkSelectorValid(const ASelector: string): Boolean;
function InkQuerySelector(ARoot: TInkNode; const ASelector: string): TInkNode;
function InkQuerySelectorAll(ARoot: TInkNode; const ASelector: string): TInkNodeArray;
{ a property's index in the computed style, -1 for one not known }
function InkPropertyIndex(const AName: string): Integer;

implementation

uses Math, StrUtils, URIParser;

{$I inkua.inc}

{ ------------------------------------------------------------ properties }

type
  TPropDef = record
    N: string;
    Inh: Boolean;
    Init: string;
  end;

const
  PropDefs: array[0..131] of TPropDef = (
    (N:'accent-color';Inh:True;Init:'auto'),
    (N:'align-content';Inh:False;Init:'normal'),
    (N:'align-items';Inh:False;Init:'normal'),
    (N:'align-self';Inh:False;Init:'auto'),
    (N:'aspect-ratio';Inh:False;Init:'auto'),
    (N:'background-attachment';Inh:False;Init:'scroll'),
    (N:'background-clip';Inh:False;Init:'border-box'),
    (N:'background-color';Inh:False;Init:'transparent'),
    (N:'background-image';Inh:False;Init:'none'),
    (N:'background-origin';Inh:False;Init:'padding-box'),
    (N:'background-position';Inh:False;Init:'0% 0%'),
    (N:'background-repeat';Inh:False;Init:'repeat'),
    (N:'background-size';Inh:False;Init:'auto'),
    (N:'border-bottom-color';Inh:False;Init:'currentcolor'),
    (N:'border-bottom-left-radius';Inh:False;Init:'0'),
    (N:'border-bottom-right-radius';Inh:False;Init:'0'),
    (N:'border-bottom-style';Inh:False;Init:'none'),
    (N:'border-bottom-width';Inh:False;Init:'medium'),
    (N:'border-collapse';Inh:True;Init:'separate'),
    (N:'border-left-color';Inh:False;Init:'currentcolor'),
    (N:'border-left-style';Inh:False;Init:'none'),
    (N:'border-left-width';Inh:False;Init:'medium'),
    (N:'border-right-color';Inh:False;Init:'currentcolor'),
    (N:'border-right-style';Inh:False;Init:'none'),
    (N:'border-right-width';Inh:False;Init:'medium'),
    (N:'border-spacing';Inh:True;Init:'0'),
    (N:'border-top-color';Inh:False;Init:'currentcolor'),
    (N:'border-top-left-radius';Inh:False;Init:'0'),
    (N:'border-top-right-radius';Inh:False;Init:'0'),
    (N:'border-top-style';Inh:False;Init:'none'),
    (N:'border-top-width';Inh:False;Init:'medium'),
    (N:'bottom';Inh:False;Init:'auto'),
    (N:'box-shadow';Inh:False;Init:'none'),
    (N:'box-sizing';Inh:False;Init:'content-box'),
    (N:'caption-side';Inh:True;Init:'top'),
    (N:'clear';Inh:False;Init:'none'),
    (N:'color';Inh:True;Init:'canvastext'),
    (N:'color-scheme';Inh:True;Init:'normal'),
    (N:'column-count';Inh:False;Init:'auto'),
    (N:'column-gap';Inh:False;Init:'normal'),
    (N:'column-width';Inh:False;Init:'auto'),
    (N:'content';Inh:False;Init:'normal'),
    (N:'counter-increment';Inh:False;Init:'none'),
    (N:'counter-reset';Inh:False;Init:'none'),
    (N:'counter-set';Inh:False;Init:'none'),
    (N:'cursor';Inh:True;Init:'auto'),
    (N:'direction';Inh:True;Init:'ltr'),
    (N:'display';Inh:False;Init:'inline'),
    (N:'empty-cells';Inh:True;Init:'show'),
    (N:'filter';Inh:False;Init:'none'),
    (N:'flex-basis';Inh:False;Init:'auto'),
    (N:'flex-direction';Inh:False;Init:'row'),
    (N:'flex-grow';Inh:False;Init:'0'),
    (N:'flex-shrink';Inh:False;Init:'1'),
    (N:'flex-wrap';Inh:False;Init:'nowrap'),
    (N:'float';Inh:False;Init:'none'),
    (N:'font-family';Inh:True;Init:''),
    (N:'font-size';Inh:True;Init:'medium'),
    (N:'font-stretch';Inh:True;Init:'normal'),
    (N:'font-style';Inh:True;Init:'normal'),
    (N:'font-variant';Inh:True;Init:'normal'),
    (N:'font-weight';Inh:True;Init:'400'),
    (N:'grid-auto-columns';Inh:False;Init:'auto'),
    (N:'grid-auto-flow';Inh:False;Init:'row'),
    (N:'grid-auto-rows';Inh:False;Init:'auto'),
    (N:'grid-column-end';Inh:False;Init:'auto'),
    (N:'grid-column-start';Inh:False;Init:'auto'),
    (N:'grid-row-end';Inh:False;Init:'auto'),
    (N:'grid-row-start';Inh:False;Init:'auto'),
    (N:'grid-template-areas';Inh:False;Init:'none'),
    (N:'grid-template-columns';Inh:False;Init:'none'),
    (N:'grid-template-rows';Inh:False;Init:'none'),
    (N:'height';Inh:False;Init:'auto'),
    (N:'hyphens';Inh:True;Init:'manual'),
    (N:'justify-content';Inh:False;Init:'normal'),
    (N:'justify-items';Inh:False;Init:'legacy'),
    (N:'justify-self';Inh:False;Init:'auto'),
    (N:'left';Inh:False;Init:'auto'),
    (N:'letter-spacing';Inh:True;Init:'normal'),
    (N:'line-height';Inh:True;Init:'normal'),
    (N:'list-style-image';Inh:True;Init:'none'),
    (N:'list-style-position';Inh:True;Init:'outside'),
    (N:'list-style-type';Inh:True;Init:'disc'),
    (N:'margin-bottom';Inh:False;Init:'0'),
    (N:'margin-left';Inh:False;Init:'0'),
    (N:'margin-right';Inh:False;Init:'0'),
    (N:'margin-top';Inh:False;Init:'0'),
    (N:'max-height';Inh:False;Init:'none'),
    (N:'max-width';Inh:False;Init:'none'),
    (N:'min-height';Inh:False;Init:'auto'),
    (N:'min-width';Inh:False;Init:'auto'),
    (N:'object-fit';Inh:False;Init:'fill'),
    (N:'object-position';Inh:False;Init:'50% 50%'),
    (N:'opacity';Inh:False;Init:'1'),
    (N:'order';Inh:False;Init:'0'),
    (N:'outline-color';Inh:False;Init:'currentcolor'),
    (N:'outline-offset';Inh:False;Init:'0'),
    (N:'outline-style';Inh:False;Init:'none'),
    (N:'outline-width';Inh:False;Init:'medium'),
    (N:'overflow-wrap';Inh:True;Init:'normal'),
    (N:'overflow-x';Inh:False;Init:'visible'),
    (N:'overflow-y';Inh:False;Init:'visible'),
    (N:'padding-bottom';Inh:False;Init:'0'),
    (N:'padding-left';Inh:False;Init:'0'),
    (N:'padding-right';Inh:False;Init:'0'),
    (N:'padding-top';Inh:False;Init:'0'),
    (N:'pointer-events';Inh:True;Init:'auto'),
    (N:'position';Inh:False;Init:'static'),
    (N:'quotes';Inh:True;Init:'auto'),
    (N:'right';Inh:False;Init:'auto'),
    (N:'row-gap';Inh:False;Init:'normal'),
    (N:'tab-size';Inh:True;Init:'8'),
    (N:'table-layout';Inh:False;Init:'auto'),
    (N:'text-align';Inh:True;Init:'start'),
    (N:'text-decoration-color';Inh:False;Init:'currentcolor'),
    (N:'text-decoration-line';Inh:False;Init:'none'),
    (N:'text-decoration-style';Inh:False;Init:'solid'),
    (N:'text-indent';Inh:True;Init:'0'),
    (N:'text-overflow';Inh:False;Init:'clip'),
    (N:'text-shadow';Inh:True;Init:'none'),
    (N:'text-transform';Inh:True;Init:'none'),
    (N:'text-underline-offset';Inh:True;Init:'auto'),
    (N:'top';Inh:False;Init:'auto'),
    (N:'transform';Inh:False;Init:'none'),
    (N:'user-select';Inh:False;Init:'auto'),
    (N:'vertical-align';Inh:False;Init:'baseline'),
    (N:'visibility';Inh:True;Init:'visible'),
    (N:'white-space';Inh:True;Init:'normal'),
    (N:'width';Inh:False;Init:'auto'),
    (N:'word-break';Inh:True;Init:'normal'),
    (N:'word-spacing';Inh:True;Init:'normal'),
    (N:'z-index';Inh:False;Init:'auto'));

var
  PropIndex: TStringList = nil;
  { numbers in CSS are written with a point, whatever the machine's locale }
  CSSFormat: TFormatSettings;
  PDisplay, PFloat, PPosition, PFontSize, PFontWeight, PLineHeight, PColor: Integer;

procedure BuildProps;
var I: Integer;
begin
  PropIndex := TStringList.Create;
  PropIndex.CaseSensitive := True;
  for I := 0 to High(PropDefs) do PropIndex.AddObject(PropDefs[I].N, TObject(PtrInt(I)));
  PropIndex.Sorted := True;
  PDisplay := InkPropertyIndex('display');
  PFloat := InkPropertyIndex('float');
  PPosition := InkPropertyIndex('position');
  PFontSize := InkPropertyIndex('font-size');
  PFontWeight := InkPropertyIndex('font-weight');
  PLineHeight := InkPropertyIndex('line-height');
  PColor := InkPropertyIndex('color');
end;

function InkPropertyIndex(const AName: string): Integer;
var I: Integer;
begin
  if PropIndex = nil then BuildProps;
  if PropIndex.Find(AName, I) then Result := PtrInt(PropIndex.Objects[I]) else Result := -1;
end;

function PropCount: Integer; inline;
begin
  Result := System.Length(PropDefs);
end;

{ ---------------------------------------------------------------- text }

function LowTrim(const S: string): string;
begin
  Result := LowerCase(Trim(S));
end;

function IsSpace(C: Char): Boolean; inline;
begin
  Result := C in [' ', #9, #10, #12, #13];
end;

{ the CSS's comments taken out, strings left alone }
function StripComments(const S: string): string;
var P, Start: Integer; Q: Char;
begin
  if Pos('/*', S) = 0 then Exit(S);
  Result := ''; P := 1; Start := 1;
  while P <= System.Length(S) do
  begin
    if S[P] in ['"', ''''] then
    begin
      Q := S[P]; Inc(P);
      while (P <= System.Length(S)) and (S[P] <> Q) do
      begin
        if S[P] = '\' then Inc(P);
        Inc(P);
      end;
      Inc(P);
      Continue;
    end;
    if (S[P] = '/') and (P < System.Length(S)) and (S[P + 1] = '*') then
    begin
      Result := Result + Copy(S, Start, P - Start) + ' ';
      P := PosEx('*/', S, P + 2);
      if P = 0 then begin Start := System.Length(S) + 1; Break end;
      Inc(P, 2); Start := P;
      Continue;
    end;
    Inc(P);
  end;
  Result := Result + Copy(S, Start, MaxInt);
end;

{ the parts of S separated by ADelim at the top level - not inside
  brackets or strings }
function SplitTop(const S: string; ADelim: Char): TStringArray;
var P, Start, Depth, N: Integer; Q: Char;
begin
  Result := nil; N := 0; Depth := 0; Start := 1; P := 1;
  while P <= System.Length(S) do
  begin
    case S[P] of
      '"', '''':
        begin
          Q := S[P]; Inc(P);
          while (P <= System.Length(S)) and (S[P] <> Q) do
          begin
            if S[P] = '\' then Inc(P);
            Inc(P);
          end;
        end;
      '(', '[', '{': Inc(Depth);
      ')', ']', '}': if Depth > 0 then Dec(Depth);
      '\': Inc(P);
    else
      if (S[P] = ADelim) and (Depth = 0) then
      begin
        SetLength(Result, N + 1); Result[N] := Copy(S, Start, P - Start); Inc(N);
        Start := P + 1;
      end;
    end;
    Inc(P);
  end;
  SetLength(Result, N + 1); Result[N] := Copy(S, Start, MaxInt);
end;

{ a value's words at the top level, split on white space }
function Words(const S: string): TStringArray;
var P, Start, Depth, N: Integer; Q: Char;
begin
  Result := nil; N := 0; Depth := 0; P := 1;
  while P <= System.Length(S) do
  begin
    while (P <= System.Length(S)) and IsSpace(S[P]) do Inc(P);
    if P > System.Length(S) then Break;
    Start := P;
    while (P <= System.Length(S)) and ((Depth > 0) or not IsSpace(S[P])) do
    begin
      case S[P] of
        '(': Inc(Depth);
        ')': if Depth > 0 then Dec(Depth);
        '"', '''':
          begin
            Q := S[P]; Inc(P);
            while (P <= System.Length(S)) and (S[P] <> Q) do Inc(P);
          end;
      end;
      Inc(P);
    end;
    SetLength(Result, N + 1); Result[N] := Copy(S, Start, P - Start); Inc(N);
  end;
end;

{ -------------------------------------------------------------- colors }

const
  ColorNames: array[0..147] of record N: string; V: Cardinal; end = (
    (N:'aliceblue';V:$f0f8ff),(N:'antiquewhite';V:$faebd7),(N:'aqua';V:$00ffff),
    (N:'aquamarine';V:$7fffd4),(N:'azure';V:$f0ffff),(N:'beige';V:$f5f5dc),
    (N:'bisque';V:$ffe4c4),(N:'black';V:$000000),(N:'blanchedalmond';V:$ffebcd),
    (N:'blue';V:$0000ff),(N:'blueviolet';V:$8a2be2),(N:'brown';V:$a52a2a),
    (N:'burlywood';V:$deb887),(N:'cadetblue';V:$5f9ea0),(N:'chartreuse';V:$7fff00),
    (N:'chocolate';V:$d2691e),(N:'coral';V:$ff7f50),(N:'cornflowerblue';V:$6495ed),
    (N:'cornsilk';V:$fff8dc),(N:'crimson';V:$dc143c),(N:'cyan';V:$00ffff),
    (N:'darkblue';V:$00008b),(N:'darkcyan';V:$008b8b),(N:'darkgoldenrod';V:$b8860b),
    (N:'darkgray';V:$a9a9a9),(N:'darkgreen';V:$006400),(N:'darkgrey';V:$a9a9a9),
    (N:'darkkhaki';V:$bdb76b),(N:'darkmagenta';V:$8b008b),(N:'darkolivegreen';V:$556b2f),
    (N:'darkorange';V:$ff8c00),(N:'darkorchid';V:$9932cc),(N:'darkred';V:$8b0000),
    (N:'darksalmon';V:$e9967a),(N:'darkseagreen';V:$8fbc8f),(N:'darkslateblue';V:$483d8b),
    (N:'darkslategray';V:$2f4f4f),(N:'darkslategrey';V:$2f4f4f),(N:'darkturquoise';V:$00ced1),
    (N:'darkviolet';V:$9400d3),(N:'deeppink';V:$ff1493),(N:'deepskyblue';V:$00bfff),
    (N:'dimgray';V:$696969),(N:'dimgrey';V:$696969),(N:'dodgerblue';V:$1e90ff),
    (N:'firebrick';V:$b22222),(N:'floralwhite';V:$fffaf0),(N:'forestgreen';V:$228b22),
    (N:'fuchsia';V:$ff00ff),(N:'gainsboro';V:$dcdcdc),(N:'ghostwhite';V:$f8f8ff),
    (N:'gold';V:$ffd700),(N:'goldenrod';V:$daa520),(N:'gray';V:$808080),
    (N:'green';V:$008000),(N:'greenyellow';V:$adff2f),(N:'grey';V:$808080),
    (N:'honeydew';V:$f0fff0),(N:'hotpink';V:$ff69b4),(N:'indianred';V:$cd5c5c),
    (N:'indigo';V:$4b0082),(N:'ivory';V:$fffff0),(N:'khaki';V:$f0e68c),
    (N:'lavender';V:$e6e6fa),(N:'lavenderblush';V:$fff0f5),(N:'lawngreen';V:$7cfc00),
    (N:'lemonchiffon';V:$fffacd),(N:'lightblue';V:$add8e6),(N:'lightcoral';V:$f08080),
    (N:'lightcyan';V:$e0ffff),(N:'lightgoldenrodyellow';V:$fafad2),(N:'lightgray';V:$d3d3d3),
    (N:'lightgreen';V:$90ee90),(N:'lightgrey';V:$d3d3d3),(N:'lightpink';V:$ffb6c1),
    (N:'lightsalmon';V:$ffa07a),(N:'lightseagreen';V:$20b2aa),(N:'lightskyblue';V:$87cefa),
    (N:'lightslategray';V:$778899),(N:'lightslategrey';V:$778899),(N:'lightsteelblue';V:$b0c4de),
    (N:'lightyellow';V:$ffffe0),(N:'lime';V:$00ff00),(N:'limegreen';V:$32cd32),
    (N:'linen';V:$faf0e6),(N:'magenta';V:$ff00ff),(N:'maroon';V:$800000),
    (N:'mediumaquamarine';V:$66cdaa),(N:'mediumblue';V:$0000cd),(N:'mediumorchid';V:$ba55d3),
    (N:'mediumpurple';V:$9370db),(N:'mediumseagreen';V:$3cb371),(N:'mediumslateblue';V:$7b68ee),
    (N:'mediumspringgreen';V:$00fa9a),(N:'mediumturquoise';V:$48d1cc),(N:'mediumvioletred';V:$c71585),
    (N:'midnightblue';V:$191970),(N:'mintcream';V:$f5fffa),(N:'mistyrose';V:$ffe4e1),
    (N:'moccasin';V:$ffe4b5),(N:'navajowhite';V:$ffdead),(N:'navy';V:$000080),
    (N:'oldlace';V:$fdf5e6),(N:'olive';V:$808000),(N:'olivedrab';V:$6b8e23),
    (N:'orange';V:$ffa500),(N:'orangered';V:$ff4500),(N:'orchid';V:$da70d6),
    (N:'palegoldenrod';V:$eee8aa),(N:'palegreen';V:$98fb98),(N:'paleturquoise';V:$afeeee),
    (N:'palevioletred';V:$db7093),(N:'papayawhip';V:$ffefd5),(N:'peachpuff';V:$ffdab9),
    (N:'peru';V:$cd853f),(N:'pink';V:$ffc0cb),(N:'plum';V:$dda0dd),
    (N:'powderblue';V:$b0e0e6),(N:'purple';V:$800080),(N:'rebeccapurple';V:$663399),
    (N:'red';V:$ff0000),(N:'rosybrown';V:$bc8f8f),(N:'royalblue';V:$4169e1),
    (N:'saddlebrown';V:$8b4513),(N:'salmon';V:$fa8072),(N:'sandybrown';V:$f4a460),
    (N:'seagreen';V:$2e8b57),(N:'seashell';V:$fff5ee),(N:'sienna';V:$a0522d),
    (N:'silver';V:$c0c0c0),(N:'skyblue';V:$87ceeb),(N:'slateblue';V:$6a5acd),
    (N:'slategray';V:$708090),(N:'slategrey';V:$708090),(N:'snow';V:$fffafa),
    (N:'springgreen';V:$00ff7f),(N:'steelblue';V:$4682b4),(N:'tan';V:$d2b48c),
    (N:'teal';V:$008080),(N:'thistle';V:$d8bfd8),(N:'tomato';V:$ff6347),
    (N:'turquoise';V:$40e0d0),(N:'violet';V:$ee82ee),(N:'wheat';V:$f5deb3),
    (N:'white';V:$ffffff),(N:'whitesmoke';V:$f5f5f5),(N:'yellow';V:$ffff00),
    (N:'yellowgreen';V:$9acd32));

{ $RRGGBB as written, and an opacity 0..255, as TInkRGBA }
function RGBA(RGB: Cardinal; A: Integer): TInkRGBA;
begin
  Result := ((RGB shr 16) and $FF) or (RGB and $FF00) or ((RGB and $FF) shl 16) or
    (Cardinal(EnsureRange(A, 0, 255)) shl 24);
end;

function Channel(const S: string; AScale: Double): Double;
var V: string; F: Double;
begin
  V := Trim(S);
  if (V <> '') and (V[System.Length(V)] = '%') then
  begin
    if not TryStrToFloat(Copy(V, 1, System.Length(V) - 1), F, CSSFormat) then F := 0;
    Result := F * AScale / 100;
  end
  else
  begin
    if LowerCase(V) = 'none' then Exit(0);
    if not TryStrToFloat(V, F, CSSFormat) then F := 0;
    Result := F;
  end;
end;

function HueToRGB(P, Q, T: Double): Double;
begin
  if T < 0 then T := T + 1;
  if T > 1 then T := T - 1;
  if T < 1/6 then Exit(P + (Q - P) * 6 * T);
  if T < 1/2 then Exit(Q);
  if T < 2/3 then Exit(P + (Q - P) * (2/3 - T) * 6);
  Result := P;
end;

{ oklab() and oklch(): OKLab to linear sRGB, then the sRGB curve }
function OKColor(APolar: Boolean; const AInner: string; out C: TInkRGBA): Boolean;
var Inner: string; Parts: TStringArray; L, A, B, H, Ch, AL, L_, M_, S_, R, G, Bl, Alpha: Double;
  function Gamma(X: Double): Integer;
  begin
    X := EnsureRange(X, 0, 1);
    if X <= 0.0031308 then X := 12.92 * X else X := 1.055 * Power(X, 1 / 2.4) - 0.055;
    Result := EnsureRange(Round(X * 255), 0, 255);
  end;
begin
  Result := False; C := 0;
  Inner := StringReplace(StringReplace(AInner, ',', ' ', [rfReplaceAll]), '/', ' ', [rfReplaceAll]);
  Parts := Words(Inner);
  if System.Length(Parts) < 3 then Exit;
  if Pos('%', Parts[0]) > 0 then L := Channel(Parts[0], 1) else L := Channel(Parts[0], 1);
  Alpha := 1;
  if System.Length(Parts) >= 4 then Alpha := Channel(Parts[3], 1);
  if APolar then
  begin
    Ch := Channel(Parts[1], 0.4);
    H := Channel(StringReplace(Parts[2], 'deg', '', []), 1) * Pi / 180;
    A := Ch * Cos(H); B := Ch * Sin(H);
  end
  else
  begin
    A := Channel(Parts[1], 0.4); B := Channel(Parts[2], 0.4);
  end;
  AL := L;
  L_ := AL + 0.3963377774 * A + 0.2158037573 * B;
  M_ := AL - 0.1055613458 * A - 0.0638541728 * B;
  S_ := AL - 0.0894841775 * A - 1.2914855480 * B;
  L_ := L_ * L_ * L_; M_ := M_ * M_ * M_; S_ := S_ * S_ * S_;
  R := 4.0767416621 * L_ - 3.3077115913 * M_ + 0.2309699292 * S_;
  G := -1.2684380046 * L_ + 2.6097574011 * M_ - 0.3413193965 * S_;
  Bl := -0.0041960863 * L_ - 0.7034186147 * M_ + 1.7076147010 * S_;
  C := Cardinal(Gamma(R)) or (Cardinal(Gamma(G)) shl 8) or (Cardinal(Gamma(Bl)) shl 16) or
    (Cardinal(EnsureRange(Round(Alpha * 255), 0, 255)) shl 24);
  Result := True;
end;

{ lab() and lch(): CIE Lab under the D50 white, to XYZ, adapted to D65,
  then to sRGB }
function LabColor(APolar: Boolean; const AInner: string; out C: TInkRGBA): Boolean;
const
  Eps = 216 / 24389; Kappa = 24389 / 27;
var Inner: string; Parts: TStringArray; L, A, B, H, Ch, Fx, Fy, Fz, X, Y, Z, X2, Y2, Z2,
  R, G, Bl, Alpha: Double;
  function Gamma(V: Double): Integer;
  begin
    V := EnsureRange(V, 0, 1);
    if V <= 0.0031308 then V := 12.92 * V else V := 1.055 * Power(V, 1 / 2.4) - 0.055;
    Result := EnsureRange(Round(V * 255), 0, 255);
  end;
  function Cube(T: Double): Double;
  begin
    if T * T * T > Eps then Result := T * T * T else Result := (116 * T - 16) / Kappa;
  end;
begin
  Result := False; C := 0;
  Inner := StringReplace(StringReplace(AInner, ',', ' ', [rfReplaceAll]), '/', ' ', [rfReplaceAll]);
  Parts := Words(Inner);
  if System.Length(Parts) < 3 then Exit;
  L := Channel(Parts[0], 100);
  Alpha := 1;
  if System.Length(Parts) >= 4 then Alpha := Channel(Parts[3], 1);
  if APolar then
  begin
    Ch := Channel(Parts[1], 150);
    H := Channel(StringReplace(Parts[2], 'deg', '', []), 1) * Pi / 180;
    A := Ch * Cos(H); B := Ch * Sin(H);
  end
  else
  begin
    A := Channel(Parts[1], 125); B := Channel(Parts[2], 125);
  end;
  Fy := (L + 16) / 116; Fx := Fy + A / 500; Fz := Fy - B / 200;
  X := Cube(Fx) * 0.96422;
  if L > Kappa * Eps then Y := Fy * Fy * Fy else Y := L / Kappa;
  Z := Cube(Fz) * 0.82521;
  X2 := 0.9554734527042182 * X - 0.023098536874261423 * Y + 0.0632593086610217 * Z;
  Y2 := -0.028369706963208136 * X + 1.0099954580058226 * Y + 0.021041398966943008 * Z;
  Z2 := 0.012314001688319899 * X - 0.020507696433477912 * Y + 1.3303659366080753 * Z;
  R := 3.2409699419045226 * X2 - 1.537383177570094 * Y2 - 0.4986107602930034 * Z2;
  G := -0.9692436362808796 * X2 + 1.8759675015077202 * Y2 + 0.04155505740717559 * Z2;
  Bl := 0.05563007969699366 * X2 - 0.20397695888897652 * Y2 + 1.0569715142428786 * Z2;
  C := Cardinal(Gamma(R)) or (Cardinal(Gamma(G)) shl 8) or (Cardinal(Gamma(Bl)) shl 16) or
    (Cardinal(EnsureRange(Round(Alpha * 255), 0, 255)) shl 24);
  Result := True;
end;

{ color-mix(in srgb, red 30%, blue): mixed channel by channel }
function MixColors(const AInner: string; out C: TInkRGBA; ADark: Boolean): Boolean;
var Parts, W: TStringArray; Cols: array[0..1] of TInkRGBA; Pct: array[0..1] of Double;
  Given: array[0..1] of Boolean; I, K: Integer; Spec: string; Sum, A, T: Double; Ch: array[0..3] of Double;
begin
  Result := False; C := 0;
  Parts := SplitTop(AInner, ',');
  if System.Length(Parts) <> 3 then Exit;
  for I := 0 to 1 do
  begin
    Spec := Trim(Parts[I + 1]); Given[I] := False; Pct[I] := 0;
    W := Words(Spec);
    if System.Length(W) = 0 then Exit;
    if (System.Length(W) > 1) and (W[High(W)] <> '') and (W[High(W)][System.Length(W[High(W)])] = '%') then
    begin
      Pct[I] := StrToFloatDef(Copy(W[High(W)], 1, System.Length(W[High(W)]) - 1), 50, CSSFormat);
      Given[I] := True;
      Spec := Trim(Copy(Spec, 1, System.Length(Spec) - System.Length(W[High(W)])));
    end;
    if not InkParseColor(Spec, Cols[I], ADark) then Exit;
  end;
  if not Given[0] and not Given[1] then begin Pct[0] := 50; Pct[1] := 50 end
  else if not Given[0] then Pct[0] := 100 - Pct[1]
  else if not Given[1] then Pct[1] := 100 - Pct[0];
  Sum := Pct[0] + Pct[1];
  if Sum <= 0 then Exit;
  { premultiplied by opacity, as the standard mixes }
  A := (Cols[0] shr 24) / 255 * Pct[0] / Sum + (Cols[1] shr 24) / 255 * Pct[1] / Sum;
  for K := 0 to 2 do
  begin
    T := ((Cols[0] shr (8 * K)) and $FF) * (Cols[0] shr 24) / 255 * Pct[0] / Sum +
      ((Cols[1] shr (8 * K)) and $FF) * (Cols[1] shr 24) / 255 * Pct[1] / Sum;
    if A > 0 then Ch[K] := T / A else Ch[K] := 0;
  end;
  if Sum < 100 then A := A * Sum / 100;
  C := Cardinal(EnsureRange(Round(Ch[0]), 0, 255)) or (Cardinal(EnsureRange(Round(Ch[1]), 0, 255)) shl 8) or
    (Cardinal(EnsureRange(Round(Ch[2]), 0, 255)) shl 16) or (Cardinal(EnsureRange(Round(A * 255), 0, 255)) shl 24);
  Result := True;
end;

function InkParseColor(const S: string; out C: TInkRGBA; ADark: Boolean): Boolean;
var V, Inner, Fn: string; Parts: TStringArray; N: LongInt; I: Integer;
  R, G, B, A, H, Sat, L, Q, P: Double;
begin
  Result := False; C := 0;
  V := LowTrim(S);
  if V = '' then Exit;
  if V = 'transparent' then begin C := 0; Exit(True) end;
  if V[1] = '#' then
  begin
    Inner := Copy(V, 2, MaxInt);
    for I := 1 to System.Length(Inner) do
      if not (Inner[I] in ['0'..'9', 'a'..'f']) then Exit;
    case System.Length(Inner) of
      3: Inner := Inner[1] + Inner[1] + Inner[2] + Inner[2] + Inner[3] + Inner[3] + 'ff';
      4: Inner := Inner[1] + Inner[1] + Inner[2] + Inner[2] + Inner[3] + Inner[3] + Inner[4] + Inner[4];
      6: Inner := Inner + 'ff';
      8: ;
    else
      Exit;
    end;
    N := StrToInt('$' + Copy(Inner, 1, 6));
    C := RGBA(N, StrToInt('$' + Copy(Inner, 7, 2)));
    Exit(True);
  end;
  I := Pos('(', V);
  if (I > 0) and (V[System.Length(V)] = ')') then
  begin
    Fn := Copy(V, 1, I - 1);
    Inner := Copy(V, I + 1, System.Length(V) - I - 1);
    if Fn = 'light-dark' then
    begin
      Parts := SplitTop(Inner, ',');
      if System.Length(Parts) <> 2 then Exit;
      if ADark then Exit(InkParseColor(Parts[1], C, ADark)) else Exit(InkParseColor(Parts[0], C, ADark));
    end;
    if Fn = 'color-mix' then Exit(MixColors(Inner, C, ADark));
    if (Fn = 'oklch') or (Fn = 'oklab') then Exit(OKColor(Fn = 'oklch', Inner, C));
    if (Fn = 'lch') or (Fn = 'lab') then Exit(LabColor(Fn = 'lch', Inner, C));
    Inner := StringReplace(Inner, ',', ' ', [rfReplaceAll]);
    Inner := StringReplace(Inner, '/', ' ', [rfReplaceAll]);
    Parts := Words(Inner);
    if System.Length(Parts) < 3 then Exit;
    A := 1;
    if System.Length(Parts) >= 4 then A := Channel(Parts[3], 1);
    if (Fn = 'rgb') or (Fn = 'rgba') then
    begin
      R := Channel(Parts[0], 255); G := Channel(Parts[1], 255); B := Channel(Parts[2], 255);
    end
    else if (Fn = 'hsl') or (Fn = 'hsla') then
    begin
      Inner := Parts[0];
      if Copy(Inner, System.Length(Inner) - 2, 3) = 'deg' then Inner := Copy(Inner, 1, System.Length(Inner) - 3);
      if Copy(Inner, System.Length(Inner) - 3, 4) = 'turn' then
        H := Channel(Copy(Inner, 1, System.Length(Inner) - 4), 1) * 360
      else if Copy(Inner, System.Length(Inner) - 2, 3) = 'rad' then
        H := Channel(Copy(Inner, 1, System.Length(Inner) - 3), 1) * 180 / Pi
      else H := Channel(Inner, 1);
      H := H - Floor(H / 360) * 360;
      Sat := EnsureRange(Channel(Parts[1], 100) / 100, 0, 1);
      L := EnsureRange(Channel(Parts[2], 100) / 100, 0, 1);
      if Sat = 0 then begin R := L; G := L; B := L end
      else
      begin
        if L < 0.5 then Q := L * (1 + Sat) else Q := L + Sat - L * Sat;
        P := 2 * L - Q;
        R := HueToRGB(P, Q, H / 360 + 1/3);
        G := HueToRGB(P, Q, H / 360);
        B := HueToRGB(P, Q, H / 360 - 1/3);
      end;
      R := R * 255; G := G * 255; B := B * 255;
    end
    else Exit;
    C := Cardinal(EnsureRange(Round(R), 0, 255)) or (Cardinal(EnsureRange(Round(G), 0, 255)) shl 8) or
      (Cardinal(EnsureRange(Round(B), 0, 255)) shl 16) or
      (Cardinal(EnsureRange(Round(A * 255), 0, 255)) shl 24);
    Exit(True);
  end;
  for I := 0 to High(ColorNames) do
    if ColorNames[I].N = V then
    begin
      C := RGBA(ColorNames[I].V, 255);
      Exit(True);
    end;
  { the system colors, for the scheme the page is shown in }
  case V of
    'canvas', 'window', 'background': if ADark then C := RGBA($121212, 255) else C := RGBA($FFFFFF, 255);
    'canvastext', 'windowtext', 'menutext', 'captiontext', 'infotext':
      if ADark then C := RGBA($FFFFFF, 255) else C := RGBA($000000, 255);
    'linktext': if ADark then C := RGBA($9E9EFF, 255) else C := RGBA($0000EE, 255);
    'visitedtext': if ADark then C := RGBA($D0ADF0, 255) else C := RGBA($551A8B, 255);
    'activetext': C := RGBA($FF0000, 255);
    'buttonface', 'buttonhighlight', 'threedface', 'threedlightshadow':
      if ADark then C := RGBA($6B6B6B, 255) else C := RGBA($EFEFEF, 255);
    'buttontext': if ADark then C := RGBA($FFFFFF, 255) else C := RGBA($000000, 255);
    'buttonborder', 'buttonshadow', 'threedshadow', 'threeddarkshadow': C := RGBA($767676, 255);
    'field': if ADark then C := RGBA($3B3B3B, 255) else C := RGBA($FFFFFF, 255);
    'fieldtext': if ADark then C := RGBA($FFFFFF, 255) else C := RGBA($000000, 255);
    'highlight', 'selecteditem', 'accentcolor': C := RGBA($3390FF, 255);
    'highlighttext', 'selecteditemtext', 'accentcolortext': C := RGBA($FFFFFF, 255);
    'graytext': C := RGBA($808080, 255);
    'mark': C := RGBA($FFFF00, 255);
    'marktext': C := RGBA($000000, 255);
  else
    Exit;
  end;
  Result := True;
end;

{ ------------------------------------------------------------- lengths }

type
  { what a length is measured against }
  TLengthContext = record
    Font, Root, VW, VH, Percent: Double;
  end;

  TCalc = class
    S: string;
    P: Integer;
    Ctx: TLengthContext;
    OK: Boolean;
    function Expr: Double;
    function Term: Double;
    function Factor: Double;
    procedure SkipSpace;
  end;

function UnitPx(const U: string; const Ctx: TLengthContext; out F: Double): Boolean;
begin
  Result := True;
  case U of
    '', 'px': F := 1;
    'em': F := Ctx.Font;
    'rem': F := Ctx.Root;
    'ex', 'ch': F := Ctx.Font / 2;
    '%': F := Ctx.Percent / 100;
    'pt': F := 96 / 72;
    'pc': F := 16;
    'in': F := 96;
    'cm': F := 96 / 2.54;
    'mm': F := 96 / 25.4;
    'q': F := 96 / 101.6;
    'vw', 'svw', 'lvw', 'dvw': F := Ctx.VW / 100;
    'vh', 'svh', 'lvh', 'dvh': F := Ctx.VH / 100;
    'vmin': F := Min(Ctx.VW, Ctx.VH) / 100;
    'vmax': F := Max(Ctx.VW, Ctx.VH) / 100;
    'lh': F := Ctx.Font * 1.2;
    'rlh': F := Ctx.Root * 1.2;
  else
    Result := False;
  end;
end;

procedure TCalc.SkipSpace;
begin
  while (P <= System.Length(S)) and IsSpace(S[P]) do Inc(P);
end;

function TCalc.Expr: Double;
begin
  Result := Term;
  while OK do
  begin
    SkipSpace;
    if (P <= System.Length(S)) and (S[P] = '+') then begin Inc(P); Result := Result + Term end
    else if (P <= System.Length(S)) and (S[P] = '-') then begin Inc(P); Result := Result - Term end
    else Break;
  end;
end;

function TCalc.Term: Double;
var D: Double;
begin
  Result := Factor;
  while OK do
  begin
    SkipSpace;
    if (P <= System.Length(S)) and (S[P] = '*') then begin Inc(P); Result := Result * Factor end
    else if (P <= System.Length(S)) and (S[P] = '/') then
    begin
      Inc(P); D := Factor;
      if D = 0 then begin OK := False; Exit(0) end;
      Result := Result / D;
    end
    else Break;
  end;
end;

function TCalc.Factor: Double;
var Start: Integer; Name, U: string; F: Double; Args: array of Double; N: Integer;
begin
  Result := 0;
  SkipSpace;
  if P > System.Length(S) then begin OK := False; Exit end;
  if S[P] = '(' then
  begin
    Inc(P); Result := Expr; SkipSpace;
    if (P <= System.Length(S)) and (S[P] = ')') then Inc(P) else OK := False;
    Exit;
  end;
  if S[P] in ['a'..'z', 'A'..'Z'] then
  begin
    Start := P;
    while (P <= System.Length(S)) and (S[P] in ['a'..'z', 'A'..'Z', '-']) do Inc(P);
    Name := LowerCase(Copy(S, Start, P - Start));
    if (P > System.Length(S)) or (S[P] <> '(') then begin OK := False; Exit end;
    Inc(P);
    Args := nil; N := 0;
    repeat
      SetLength(Args, N + 1); Args[N] := Expr; Inc(N);
      SkipSpace;
      if (P <= System.Length(S)) and (S[P] = ',') then Inc(P) else Break;
    until not OK;
    SkipSpace;
    if (P <= System.Length(S)) and (S[P] = ')') then Inc(P) else OK := False;
    if not OK then Exit;
    case Name of
      'calc': Result := Args[0];
      'min': begin Result := Args[0]; for Start := 1 to N - 1 do Result := Min(Result, Args[Start]) end;
      'max': begin Result := Args[0]; for Start := 1 to N - 1 do Result := Max(Result, Args[Start]) end;
      'clamp': if N = 3 then Result := Max(Args[0], Min(Args[1], Args[2])) else OK := False;
    else
      OK := False;
    end;
    Exit;
  end;
  Start := P;
  if S[P] in ['+', '-'] then Inc(P);
  while (P <= System.Length(S)) and (S[P] in ['0'..'9', '.']) do Inc(P);
  if (P <= System.Length(S)) and (S[P] in ['e', 'E']) and (P < System.Length(S)) and
    (S[P + 1] in ['0'..'9', '+', '-']) then
  begin
    Inc(P, 2);
    while (P <= System.Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;
  if not TryStrToFloat(Copy(S, Start, P - Start), F, CSSFormat) then begin OK := False; Exit end;
  Start := P;
  while (P <= System.Length(S)) and (S[P] in ['a'..'z', 'A'..'Z', '%']) do Inc(P);
  U := LowerCase(Copy(S, Start, P - Start));
  if not UnitPx(U, Ctx, Result) then begin OK := False; Exit end;
  Result := F * Result;
end;

{ a length or calc() in pixels; False for anything else }
function EvalLength(const S: string; const Ctx: TLengthContext; out V: Double): Boolean;
var C: TCalc;
begin
  V := 0;
  if Trim(S) = '' then Exit(False);
  C := TCalc.Create;
  try
    C.S := Trim(S); C.P := 1; C.Ctx := Ctx; C.OK := True;
    V := C.Expr;
    C.SkipSpace;
    Result := C.OK and (C.P > System.Length(C.S));
  finally C.Free end;
end;

{ ------------------------------------------------------------ selectors }

type
  TCombinator = (cbNone, cbDescendant, cbChild, cbNext, cbSubsequent);
  TAttrOp = (aoExists, aoEquals, aoIncludes, aoDash, aoPrefix, aoSuffix, aoSubstring);
  TPseudoKind = (pkNthChild, pkNthLastChild, pkNthOfType, pkNthLastOfType,
    pkNot, pkIs, pkHas, pkRoot, pkEmpty, pkLink, pkNever, pkHover, pkActive,
    pkFocus, pkFocusWithin, pkTarget, pkChecked, pkDisabled, pkEnabled, pkLang,
    pkScope, pkAnchor, pkAlways, pkRequired, pkOptional, pkReadOnly, pkReadWrite,
    pkPlaceholderShown, pkOpen);

  TSel = class;
  TSelList = array of TSel;

  TAttrTest = record
    Name, Value: string;
    Op: TAttrOp;
    CaseI: Boolean;
  end;

  TPseudo = record
    Kind: TPseudoKind;
    A, B: Integer;
    Arg: string;
    Sub: TSelList;
  end;

  TCompound = record
    Tag, Id: string;
    Classes: array of string;
    Attrs: array of TAttrTest;
    Pseudos: array of TPseudo;
    { how this compound stands to the one before it }
    Comb: TCombinator;
  end;

  TSel = class
    C: array of TCompound;
    Spec: Cardinal;
    PseudoElement: string;
    { a :has() argument: how its first compound stands to the anchor }
    Leading: TCombinator;
    destructor Destroy; override;
  end;

  ESelector = class(Exception);

  { what Compute knows about each element, kept on Node.Info }
  PInfo = ^TInfo;
  TInfo = record
    Node: TInkNode;
    Parent: PInfo;
    Id: string;
    Classes: array of string;
    Index, Count, TypeIndex, TypeCount: Integer;
    Style: TInkStyle;
  end;

procedure FreeList(var L: TSelList);
var I: Integer;
begin
  for I := 0 to High(L) do L[I].Free;
  L := nil;
end;

destructor TSel.Destroy;
var I, K: Integer;
begin
  for I := 0 to High(C) do
    for K := 0 to High(C[I].Pseudos) do FreeList(C[I].Pseudos[K].Sub);
  inherited Destroy;
end;

type
  TSelParser = class
    S: string;
    P: Integer;
    function AtEnd: Boolean;
    procedure SkipSpace;
    function Ident: string;
    function StringOrIdent: string;
    function List(ARelative, AForgiving: Boolean): TSelList;
    function Complex(ARelative: Boolean): TSel;
    procedure Compound(var ACmp: TCompound; ASel: TSel);
    procedure Pseudo(var ACmp: TCompound; ASel: TSel);
    procedure Nth(const AText: string; out A, B: Integer);
  end;

function TSelParser.AtEnd: Boolean;
begin
  Result := P > System.Length(S);
end;

procedure TSelParser.SkipSpace;
begin
  while (P <= System.Length(S)) and IsSpace(S[P]) do Inc(P);
end;

{ an identifier, its escapes undone }
function TSelParser.Ident: string;
var Hex: string; K: Integer;
begin
  Result := '';
  while P <= System.Length(S) do
  begin
    if S[P] = '\' then
    begin
      Inc(P);
      if P > System.Length(S) then Break;
      if S[P] in ['0'..'9', 'a'..'f', 'A'..'F'] then
      begin
        Hex := '';
        while (P <= System.Length(S)) and (System.Length(Hex) < 6) and
          (S[P] in ['0'..'9', 'a'..'f', 'A'..'F']) do begin Hex := Hex + S[P]; Inc(P) end;
        if (P <= System.Length(S)) and IsSpace(S[P]) then Inc(P);
        K := StrToInt('$' + Hex);
        Result := Result + InkCodepointToUTF8(K);
      end
      else begin Result := Result + S[P]; Inc(P) end;
      Continue;
    end;
    if (S[P] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) or (Ord(S[P]) >= 128) then
    begin
      Result := Result + S[P]; Inc(P);
    end
    else Break;
  end;
end;

function TSelParser.StringOrIdent: string;
var Q: Char;
begin
  SkipSpace;
  if (P <= System.Length(S)) and (S[P] in ['"', '''']) then
  begin
    Q := S[P]; Inc(P); Result := '';
    while (P <= System.Length(S)) and (S[P] <> Q) do
    begin
      if (S[P] = '\') and (P < System.Length(S)) then Inc(P);
      Result := Result + S[P]; Inc(P);
    end;
    Inc(P);
  end
  else Result := Ident;
end;

procedure TSelParser.Nth(const AText: string; out A, B: Integer);
var T: string; N: Integer;
begin
  T := LowerCase(StringReplace(Trim(AText), ' ', '', [rfReplaceAll]));
  if T = 'odd' then begin A := 2; B := 1; Exit end;
  if T = 'even' then begin A := 2; B := 0; Exit end;
  N := Pos('n', T);
  if N = 0 then
  begin
    A := 0;
    if not TryStrToInt(T, B) then raise ESelector.Create('nth');
    Exit;
  end;
  case Copy(T, 1, N - 1) of
    '', '+': A := 1;
    '-': A := -1;
  else
    if not TryStrToInt(Copy(T, 1, N - 1), A) then raise ESelector.Create('nth');
  end;
  T := Copy(T, N + 1, MaxInt);
  if T = '' then B := 0
  else
  begin
    if T[1] = '+' then Delete(T, 1, 1);
    if not TryStrToInt(T, B) then raise ESelector.Create('nth');
  end;
end;

{ the text up to the bracket that closes the one just opened }
function ArgumentText(const S: string; var P: Integer): string;
var Depth, Start: Integer; Q: Char;
begin
  Depth := 1; Start := P;
  while (P <= System.Length(S)) and (Depth > 0) do
  begin
    case S[P] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      '"', '''':
        begin
          Q := S[P]; Inc(P);
          while (P <= System.Length(S)) and (S[P] <> Q) do Inc(P);
        end;
      '\': Inc(P);
    end;
    Inc(P);
  end;
  if Depth > 0 then raise ESelector.Create('bracket');
  Result := Copy(S, Start, P - Start - 1);
end;

function ParseSelectorList(const AText: string; ARelative, AForgiving: Boolean): TSelList; forward;

procedure TSelParser.Pseudo(var ACmp: TCompound; ASel: TSel);
var Name, Arg: string; Ps: TPseudo; K, OfAt: Integer; IsElement: Boolean;
begin
  { P is past the colon }
  IsElement := (P <= System.Length(S)) and (S[P] = ':');
  if IsElement then Inc(P);
  Name := LowerCase(Ident);
  if Name = '' then raise ESelector.Create('pseudo');
  if IsElement or (Name = 'before') or (Name = 'after') or (Name = 'first-line') or
    (Name = 'first-letter') then
  begin
    if (P <= System.Length(S)) and (S[P] = '(') then
    begin
      Inc(P); ArgumentText(S, P);
    end;
    { Chromium takes any -webkit- pseudo-element, so a list naming one
      still applies }
    if not ((Name = 'before') or (Name = 'after') or (Name = 'marker') or
      (Name = 'first-line') or (Name = 'first-letter') or (Name = 'placeholder') or
      (Name = 'selection') or (Name = 'backdrop') or (Name = 'file-selector-button') or
      (Name = 'details-content') or (Name = 'part') or (Name = 'slotted') or
      (Name = 'cue') or (Name = 'target-text') or (Name = 'spelling-error') or
      (Name = 'grammar-error') or (Copy(Name, 1, 15) = 'view-transition') or
      (Copy(Name, 1, 8) = '-webkit-')) then
      raise ESelector.Create('pseudo-element');
    ASel.PseudoElement := Name;
    Exit;
  end;
  Ps := Default(TPseudo);
  if (P <= System.Length(S)) and (S[P] = '(') then
  begin
    Inc(P);
    Arg := ArgumentText(S, P);
    case Name of
      'not', 'is', 'where', 'matches', 'any':
        begin
          if Name = 'not' then Ps.Kind := pkNot else Ps.Kind := pkIs;
          Ps.Sub := ParseSelectorList(Arg, False, Name <> 'not');
          if Name = 'where' then Ps.Arg := 'where';
        end;
      'has':
        begin
          Ps.Kind := pkHas;
          Ps.Sub := ParseSelectorList(Arg, True, False);
        end;
      'nth-child', 'nth-last-child', 'nth-of-type', 'nth-last-of-type':
        begin
          case Name of
            'nth-child': Ps.Kind := pkNthChild;
            'nth-last-child': Ps.Kind := pkNthLastChild;
            'nth-of-type': Ps.Kind := pkNthOfType;
          else
            Ps.Kind := pkNthLastOfType;
          end;
          OfAt := Pos(' of ', LowerCase(Arg));
          if (OfAt > 0) and (Ps.Kind in [pkNthChild, pkNthLastChild]) then
          begin
            Ps.Sub := ParseSelectorList(Copy(Arg, OfAt + 4, MaxInt), False, False);
            Arg := Copy(Arg, 1, OfAt - 1);
          end;
          Nth(Arg, Ps.A, Ps.B);
        end;
      'lang':
        begin
          { a list of languages, any of which will do }
          Ps.Kind := pkLang;
          Ps.Arg := ',' + LowerCase(StringReplace(StringReplace(StringReplace(Arg, '"', '', [rfReplaceAll]),
            '''', '', [rfReplaceAll]), ' ', '', [rfReplaceAll])) + ',';
        end;
      'dir':
        if LowTrim(Arg) = 'ltr' then Ps.Kind := pkAlways else Ps.Kind := pkNever;
      'host', 'host-context', 'state', 'highlight', 'active-view-transition-type':
        Ps.Kind := pkNever;
    else
      raise ESelector.Create('pseudo-class');
    end;
  end
  else
    case Name of
      'first-child': begin Ps.Kind := pkNthChild; Ps.A := 0; Ps.B := 1 end;
      'last-child': begin Ps.Kind := pkNthLastChild; Ps.A := 0; Ps.B := 1 end;
      'only-child':
        begin
          Ps.Kind := pkNthChild; Ps.A := 0; Ps.B := 1;
          K := System.Length(ACmp.Pseudos); SetLength(ACmp.Pseudos, K + 1); ACmp.Pseudos[K] := Ps;
          Ps.Kind := pkNthLastChild;
        end;
      'first-of-type': begin Ps.Kind := pkNthOfType; Ps.A := 0; Ps.B := 1 end;
      'last-of-type': begin Ps.Kind := pkNthLastOfType; Ps.A := 0; Ps.B := 1 end;
      'only-of-type':
        begin
          Ps.Kind := pkNthOfType; Ps.A := 0; Ps.B := 1;
          K := System.Length(ACmp.Pseudos); SetLength(ACmp.Pseudos, K + 1); ACmp.Pseudos[K] := Ps;
          Ps.Kind := pkNthLastOfType;
        end;
      'root': Ps.Kind := pkRoot;
      'empty': Ps.Kind := pkEmpty;
      'link', 'any-link': Ps.Kind := pkLink;
      'visited', 'local-link', 'indeterminate', 'invalid', 'user-invalid',
      'autofill', 'fullscreen', 'modal', 'popover-open', 'paused', 'playing',
      'picture-in-picture', 'target-within', 'blank', 'user-valid', 'current',
      'past', 'future', 'focus-visible-within', 'muted', 'volume-locked',
      'seeking', 'buffering', 'stalled':
        Ps.Kind := pkNever;
      'hover': Ps.Kind := pkHover;
      'active': Ps.Kind := pkActive;
      'focus', 'focus-visible': Ps.Kind := pkFocus;
      'focus-within': Ps.Kind := pkFocusWithin;
      'target': Ps.Kind := pkTarget;
      'checked', 'default': Ps.Kind := pkChecked;
      'disabled': Ps.Kind := pkDisabled;
      'enabled': Ps.Kind := pkEnabled;
      'required': Ps.Kind := pkRequired;
      'optional': Ps.Kind := pkOptional;
      'read-only': Ps.Kind := pkReadOnly;
      'read-write': Ps.Kind := pkReadWrite;
      'placeholder-shown': Ps.Kind := pkPlaceholderShown;
      'open': Ps.Kind := pkOpen;
      'scope': Ps.Kind := pkScope;
      'host': Ps.Kind := pkNever;
      'defined', 'valid', 'in-range': Ps.Kind := pkAlways;
      'out-of-range': Ps.Kind := pkNever;
    else
      raise ESelector.Create('pseudo-class');
    end;
  K := System.Length(ACmp.Pseudos); SetLength(ACmp.Pseudos, K + 1); ACmp.Pseudos[K] := Ps;
end;

procedure TSelParser.Compound(var ACmp: TCompound; ASel: TSel);
var Any: Boolean; At: TAttrTest; K: Integer; Op: string;
begin
  Any := False;
  if (P <= System.Length(S)) and (S[P] = '*') then begin ACmp.Tag := '*'; Inc(P); Any := True end
  else if (P <= System.Length(S)) and ((S[P] in ['a'..'z', 'A'..'Z', '_', '\']) or (Ord(S[P]) >= 128)) then
  begin
    ACmp.Tag := LowerCase(Ident); Any := True;
  end;
  if (P <= System.Length(S)) and (S[P] = '|') then
  begin
    { a namespace prefix: *|x and |x read as x }
    Inc(P); ACmp.Tag := '';
    if (P <= System.Length(S)) and (S[P] = '*') then Inc(P) else ACmp.Tag := LowerCase(Ident);
  end;
  while P <= System.Length(S) do
  begin
    if ASel.PseudoElement <> '' then
    begin
      { only user-action pseudo-classes may follow a pseudo-element }
      if S[P] <> ':' then Break;
    end;
    case S[P] of
      '#':
        begin
          Inc(P); ACmp.Id := Ident;
          if ACmp.Id = '' then raise ESelector.Create('id');
        end;
      '.':
        begin
          Inc(P);
          K := System.Length(ACmp.Classes); SetLength(ACmp.Classes, K + 1);
          ACmp.Classes[K] := Ident;
          if ACmp.Classes[K] = '' then raise ESelector.Create('class');
        end;
      '[':
        begin
          Inc(P); SkipSpace;
          At := Default(TAttrTest);
          At.Name := LowerCase(Ident);
          if (P <= System.Length(S)) and (S[P] = '|') and (P < System.Length(S)) and (S[P + 1] <> '=') then
          begin
            Inc(P); At.Name := LowerCase(Ident);
          end;
          if At.Name = '' then raise ESelector.Create('attribute');
          SkipSpace;
          At.Op := aoExists;
          if (P <= System.Length(S)) and (S[P] <> ']') then
          begin
            if S[P] = '=' then begin Op := '='; Inc(P) end
            else
            begin
              Op := Copy(S, P, 2); Inc(P, 2);
            end;
            case Op of
              '=': At.Op := aoEquals;
              '~=': At.Op := aoIncludes;
              '|=': At.Op := aoDash;
              '^=': At.Op := aoPrefix;
              '$=': At.Op := aoSuffix;
              '*=': At.Op := aoSubstring;
            else
              raise ESelector.Create('attribute operator');
            end;
            At.Value := StringOrIdent;
            SkipSpace;
            if (P <= System.Length(S)) and (S[P] in ['i', 'I', 's', 'S']) then
            begin
              At.CaseI := S[P] in ['i', 'I']; Inc(P); SkipSpace;
            end;
            { these attributes compare without case in HTML }
            if (At.Name = 'type') or (At.Name = 'lang') or (At.Name = 'dir') or
              (At.Name = 'align') or (At.Name = 'valign') then At.CaseI := True;
            if At.CaseI then At.Value := LowerCase(At.Value);
          end;
          if (P > System.Length(S)) or (S[P] <> ']') then raise ESelector.Create('attribute end');
          Inc(P);
          K := System.Length(ACmp.Attrs); SetLength(ACmp.Attrs, K + 1); ACmp.Attrs[K] := At;
        end;
      ':':
        begin
          Inc(P); Pseudo(ACmp, ASel);
        end;
    else
      Break;
    end;
    Any := True;
  end;
  if not Any then raise ESelector.Create('empty compound');
end;

function Specificity(ASel: TSel): Cardinal; forward;

function TSelParser.Complex(ARelative: Boolean): TSel;
var N: Integer; Comb: TCombinator; HadSpace: Boolean;
begin
  Result := TSel.Create;
  try
    SkipSpace;
    Comb := cbNone;
    if ARelative then
    begin
      Result.Leading := cbDescendant;
      if (P <= System.Length(S)) and (S[P] in ['>', '+', '~']) then
      begin
        case S[P] of
          '>': Result.Leading := cbChild;
          '+': Result.Leading := cbNext;
          '~': Result.Leading := cbSubsequent;
        end;
        Inc(P); SkipSpace;
      end;
    end;
    N := 0;
    repeat
      SetLength(Result.C, N + 1);
      Result.C[N] := Default(TCompound);
      Result.C[N].Comb := Comb;
      Compound(Result.C[N], Result);
      Inc(N);
      HadSpace := (P <= System.Length(S)) and IsSpace(S[P]);
      SkipSpace;
      if AtEnd or (S[P] = ',') or (S[P] = ')') then Break;
      if Result.PseudoElement <> '' then raise ESelector.Create('after a pseudo-element');
      case S[P] of
        '>': begin Comb := cbChild; Inc(P); SkipSpace end;
        '+': begin Comb := cbNext; Inc(P); SkipSpace end;
        '~': begin Comb := cbSubsequent; Inc(P); SkipSpace end;
      else
        if HadSpace then Comb := cbDescendant
        else raise ESelector.Create('unexpected');
      end;
    until False;
    Result.Spec := Specificity(Result);
  except
    Result.Free;
    raise;
  end;
end;

function TSelParser.List(ARelative, AForgiving: Boolean): TSelList;
var Parts: TStringArray; I, N: Integer; Sub: TSelParser; Sel: TSel;
begin
  Result := nil; N := 0;
  Parts := SplitTop(S, ',');
  for I := 0 to High(Parts) do
  begin
    Sub := TSelParser.Create;
    try
      Sub.S := Parts[I]; Sub.P := 1;
      try
        Sel := Sub.Complex(ARelative);
        Sub.SkipSpace;
        if not Sub.AtEnd then begin Sel.Free; raise ESelector.Create('trailing') end;
        SetLength(Result, N + 1); Result[N] := Sel; Inc(N);
      except
        on E: ESelector do
          if not AForgiving then
          begin
            FreeList(Result);
            raise;
          end;
      end;
    finally Sub.Free end;
  end;
end;

function ParseSelectorList(const AText: string; ARelative, AForgiving: Boolean): TSelList;
var Parser: TSelParser;
begin
  if Trim(AText) = '' then
  begin
    if AForgiving then Exit(nil);
    raise ESelector.Create('empty');
  end;
  Parser := TSelParser.Create;
  try
    Parser.S := AText; Parser.P := 1;
    Result := Parser.List(ARelative, AForgiving);
  finally Parser.Free end;
end;

function Specificity(ASel: TSel): Cardinal;
var I, K, L: Integer; A, B, C: Cardinal; Best, S: Cardinal;
begin
  A := 0; B := 0; C := 0;
  for I := 0 to High(ASel.C) do
    with ASel.C[I] do
    begin
      if Id <> '' then Inc(A);
      Inc(B, System.Length(Classes) + System.Length(Attrs));
      if (Tag <> '') and (Tag <> '*') then Inc(C);
      for K := 0 to High(Pseudos) do
        case Pseudos[K].Kind of
          pkNot, pkIs, pkHas:
            if Pseudos[K].Arg <> 'where' then
            begin
              Best := 0;
              for L := 0 to High(Pseudos[K].Sub) do
              begin
                S := Pseudos[K].Sub[L].Spec;
                if S > Best then Best := S;
              end;
              Inc(A, Best shr 16); Inc(B, (Best shr 8) and $FF); Inc(C, Best and $FF);
            end;
          pkNthChild, pkNthLastChild:
            begin
              Inc(B);
              Best := 0;
              for L := 0 to High(Pseudos[K].Sub) do
              begin
                S := Pseudos[K].Sub[L].Spec;
                if S > Best then Best := S;
              end;
              Inc(A, Best shr 16); Inc(B, (Best shr 8) and $FF); Inc(C, Best and $FF);
            end;
        else
          Inc(B);
        end;
    end;
  if ASel.PseudoElement <> '' then Inc(C);
  Result := (Min(A, 255) shl 16) or (Min(B, 255) shl 8) or Min(C, 255);
end;

{ ------------------------------------------------------------- matching }

type
  TMatcher = record
    Styler: TInkStyler;
    Scope: TInkNode;
    Anchor: TInkNode;
  end;

function ParentElement(N: TInkNode): TInkNode; inline;
begin
  Result := N.Parent;
  if (Result <> nil) and (Result.Kind <> inkElement) then Result := nil;
end;

function PrevElement(N: TInkNode): TInkNode; inline;
begin
  Result := N.PreviousSibling;
  while (Result <> nil) and (Result.Kind <> inkElement) do Result := Result.PreviousSibling;
end;

function NextElement(N: TInkNode): TInkNode; inline;
begin
  Result := N.NextSibling;
  while (Result <> nil) and (Result.Kind <> inkElement) do Result := Result.NextSibling;
end;

function InfoOf(N: TInkNode): PInfo; inline;
begin
  Result := PInfo(N.Info);
end;

function NodeHasClass(N: TInkNode; const AClass: string): Boolean;
var I: PInfo; K: Integer;
begin
  I := InfoOf(N);
  if I = nil then Exit(N.HasClass(AClass));
  for K := 0 to High(I^.Classes) do
    if I^.Classes[K] = AClass then Exit(True);
  Result := False;
end;

function NodeId(N: TInkNode): string; inline;
begin
  if N.Info <> nil then Result := InfoOf(N)^.Id else Result := N.GetAttribute('id');
end;

{ where N stands among its parent's elements: 1-based from the start and
  from the end, all of them or only those of its own tag }
procedure Position(N: TInkNode; OfType: Boolean; out FromStart, FromEnd: Integer);
var I: PInfo; S: TInkNode;
begin
  I := InfoOf(N);
  if I <> nil then
  begin
    if OfType then
    begin
      FromStart := I^.TypeIndex; FromEnd := I^.TypeCount - I^.TypeIndex + 1;
    end
    else
    begin
      FromStart := I^.Index; FromEnd := I^.Count - I^.Index + 1;
    end;
    Exit;
  end;
  FromStart := 1; S := PrevElement(N);
  while S <> nil do
  begin
    if not OfType or SameText(S.Name, N.Name) then Inc(FromStart);
    S := PrevElement(S);
  end;
  FromEnd := 1; S := NextElement(N);
  while S <> nil do
  begin
    if not OfType or SameText(S.Name, N.Name) then Inc(FromEnd);
    S := NextElement(S);
  end;
end;

function NthMatches(A, B, I: Integer): Boolean;
begin
  if A = 0 then Exit(I = B);
  Result := ((I - B) mod A = 0) and ((I - B) div A >= 0);
end;

function MatchList(const M: TMatcher; const L: TSelList; N: TInkNode): Boolean; forward;
function MatchSel(const M: TMatcher; S: TSel; Idx: Integer; N: TInkNode): Boolean; forward;

function IsFormControl(N: TInkNode): Boolean;
begin
  Result := (N.Name = 'input') or (N.Name = 'button') or (N.Name = 'select') or
    (N.Name = 'textarea') or (N.Name = 'option') or (N.Name = 'optgroup') or
    (N.Name = 'fieldset');
end;

function HasMatch(const M: TMatcher; const L: TSelList; N: TInkNode): Boolean;
var K: Integer; S: TSel; Inner: TMatcher; X, Stop: TInkNode;
begin
  Result := False;
  for K := 0 to High(L) do
  begin
    S := L[K];
    Inner := M; Inner.Anchor := N;
    { the candidates: what is under N, or under N's parent after N; the
      match itself checks how each stands to N }
    if S.Leading in [cbDescendant, cbChild] then
    begin
      Stop := N; X := N.NextInTree(N);
    end
    else
    begin
      Stop := N.Parent; X := N.NextSibling;
    end;
    while X <> nil do
    begin
      if (X.Kind = inkElement) and MatchSel(Inner, S, High(S.C), X) then Exit(True);
      X := X.NextInTree(Stop);
    end;
  end;
end;

function MatchPseudo(const M: TMatcher; const Ps: TPseudo; N: TInkNode): Boolean;
var FromStart, FromEnd: Integer; S: TInkNode; V: string;
begin
  case Ps.Kind of
    pkNthChild, pkNthLastChild:
      begin
        if System.Length(Ps.Sub) > 0 then
        begin
          if not MatchList(M, Ps.Sub, N) then Exit(False);
          { counted among the siblings that match the of-selector }
          FromStart := 1; S := PrevElement(N);
          while S <> nil do begin if MatchList(M, Ps.Sub, S) then Inc(FromStart); S := PrevElement(S) end;
          FromEnd := 1; S := NextElement(N);
          while S <> nil do begin if MatchList(M, Ps.Sub, S) then Inc(FromEnd); S := NextElement(S) end;
        end
        else Position(N, False, FromStart, FromEnd);
        if Ps.Kind = pkNthChild then Result := NthMatches(Ps.A, Ps.B, FromStart)
        else Result := NthMatches(Ps.A, Ps.B, FromEnd);
      end;
    pkNthOfType, pkNthLastOfType:
      begin
        Position(N, True, FromStart, FromEnd);
        if Ps.Kind = pkNthOfType then Result := NthMatches(Ps.A, Ps.B, FromStart)
        else Result := NthMatches(Ps.A, Ps.B, FromEnd);
      end;
    pkNot: Result := not MatchList(M, Ps.Sub, N);
    pkIs: Result := MatchList(M, Ps.Sub, N);
    pkHas: Result := HasMatch(M, Ps.Sub, N);
    pkRoot: Result := (N.Parent <> nil) and (N.Parent.Kind = inkDocument);
    pkEmpty:
      begin
        S := N.FirstChild;
        while S <> nil do
        begin
          if (S.Kind = inkElement) or ((S.Kind = inkText) and (S.Data <> '')) then Exit(False);
          S := S.NextSibling;
        end;
        Result := True;
      end;
    pkLink: Result := ((N.Name = 'a') or (N.Name = 'area')) and N.HasAttribute('href');
    pkNever: Result := False;
    pkAlways: Result := True;
    pkHover, pkActive:
      begin
        S := nil;
        if (M.Styler <> nil) and (Ps.Kind = pkHover) then S := M.Styler.Hover;
        while S <> nil do
        begin
          if S = N then Exit(True);
          S := S.Parent;
        end;
        Result := False;
      end;
    pkFocus: Result := (M.Styler <> nil) and (M.Styler.Focus = N);
    pkFocusWithin:
      begin
        S := nil;
        if M.Styler <> nil then S := M.Styler.Focus;
        while S <> nil do
        begin
          if S = N then Exit(True);
          S := S.Parent;
        end;
        Result := False;
      end;
    pkTarget: Result := (M.Styler <> nil) and (M.Styler.TargetId <> '') and (NodeId(N) = M.Styler.TargetId);
    pkChecked:
      Result := ((N.Name = 'input') and N.HasAttribute('checked')) or
        ((N.Name = 'option') and N.HasAttribute('selected'));
    pkDisabled: Result := IsFormControl(N) and N.HasAttribute('disabled');
    pkEnabled: Result := IsFormControl(N) and not N.HasAttribute('disabled');
    pkRequired: Result := IsFormControl(N) and N.HasAttribute('required');
    pkOptional: Result := IsFormControl(N) and not N.HasAttribute('required');
    pkReadOnly, pkReadWrite:
      begin
        Result := (((N.Name = 'input') or (N.Name = 'textarea')) and not N.HasAttribute('readonly') and
          not N.HasAttribute('disabled')) or N.HasAttribute('contenteditable');
        if Ps.Kind = pkReadOnly then Result := not Result;
      end;
    pkPlaceholderShown:
      Result := ((N.Name = 'input') or (N.Name = 'textarea')) and N.HasAttribute('placeholder') and
        (N.GetAttribute('value') = '');
    pkOpen: Result := ((N.Name = 'details') or (N.Name = 'dialog')) and N.HasAttribute('open');
    pkLang:
      begin
        S := N;
        while (S <> nil) and (S.Kind = inkElement) do
        begin
          if S.HasAttribute('lang') then
          begin
            V := LowerCase(S.GetAttribute('lang'));
            if Pos(',' + V + ',', Ps.Arg) > 0 then Exit(True);
            while Pos('-', V) > 0 do
            begin
              V := Copy(V, 1, LastDelimiter('-', V) - 1);
              if Pos(',' + V + ',', Ps.Arg) > 0 then Exit(True);
            end;
            Exit(False);
          end;
          S := S.Parent;
        end;
        Result := False;
      end;
    pkScope: Result := (M.Scope <> nil) and (N = M.Scope) or
      ((M.Scope = nil) and (N.Parent <> nil) and (N.Parent.Kind = inkDocument));
    pkAnchor: Result := N = M.Anchor;
  else
    Result := False;
  end;
end;

function MatchCompound(const M: TMatcher; const C: TCompound; N: TInkNode): Boolean;
var K: Integer; V, W: string;
begin
  Result := False;
  if (C.Tag <> '') and (C.Tag <> '*') then
    if (C.Tag <> N.Name) and not ((N.Namespace <> insHTML) and SameText(C.Tag, N.Name)) then Exit;
  if (C.Id <> '') and (NodeId(N) <> C.Id) then Exit;
  for K := 0 to High(C.Classes) do
    if not NodeHasClass(N, C.Classes[K]) then Exit;
  for K := 0 to High(C.Attrs) do
    with C.Attrs[K] do
    begin
      if not N.HasAttribute(Name) then Exit;
      if Op = aoExists then Continue;
      V := N.GetAttribute(Name);
      if CaseI then V := LowerCase(V);
      case Op of
        aoEquals: if V <> Value then Exit;
        aoIncludes:
          begin
            if (Value = '') or (Pos(' ', Value) > 0) then Exit;
            W := ' ' + StringReplace(StringReplace(V, #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]) + ' ';
            if Pos(' ' + Value + ' ', W) = 0 then Exit;
          end;
        aoDash: if (V <> Value) and (Copy(V, 1, System.Length(Value) + 1) <> Value + '-') then Exit;
        aoPrefix: if (Value = '') or (Copy(V, 1, System.Length(Value)) <> Value) then Exit;
        aoSuffix:
          if (Value = '') or (System.Length(V) < System.Length(Value)) or
            (Copy(V, System.Length(V) - System.Length(Value) + 1, MaxInt) <> Value) then Exit;
        aoSubstring: if (Value = '') or (Pos(Value, V) = 0) then Exit;
      end;
    end;
  for K := 0 to High(C.Pseudos) do
    if not MatchPseudo(M, C.Pseudos[K], N) then Exit;
  Result := True;
end;

{ compound Idx of S matches N, and the compounds before it stand to N as
  their combinators say }
function MatchSel(const M: TMatcher; S: TSel; Idx: Integer; N: TInkNode): Boolean;
var P: TInkNode;
begin
  if not MatchCompound(M, S.C[Idx], N) then Exit(False);
  if Idx = 0 then
  begin
    { a :has() argument's first compound stands to the anchor }
    if M.Anchor = nil then Exit(True);
    case S.Leading of
      cbNone: Exit(True);
      cbChild: Exit(N.Parent = M.Anchor);
      cbDescendant:
        begin
          P := N.Parent;
          while P <> nil do begin if P = M.Anchor then Exit(True); P := P.Parent end;
          Exit(False);
        end;
      cbNext: Exit(PrevElement(N) = M.Anchor);
      cbSubsequent:
        begin
          P := PrevElement(N);
          while P <> nil do begin if P = M.Anchor then Exit(True); P := PrevElement(P) end;
          Exit(False);
        end;
    end;
  end;
  case S.C[Idx].Comb of
    cbChild:
      begin
        P := ParentElement(N);
        Result := (P <> nil) and MatchSel(M, S, Idx - 1, P);
      end;
    cbDescendant:
      begin
        P := ParentElement(N);
        while P <> nil do
        begin
          if MatchSel(M, S, Idx - 1, P) then Exit(True);
          P := ParentElement(P);
        end;
        Result := False;
      end;
    cbNext:
      begin
        P := PrevElement(N);
        Result := (P <> nil) and MatchSel(M, S, Idx - 1, P);
      end;
    cbSubsequent:
      begin
        P := PrevElement(N);
        while P <> nil do
        begin
          if MatchSel(M, S, Idx - 1, P) then Exit(True);
          P := PrevElement(P);
        end;
        Result := False;
      end;
  else
    Result := False;
  end;
end;

function MatchList(const M: TMatcher; const L: TSelList; N: TInkNode): Boolean;
var K: Integer; Plain: TMatcher;
begin
  { an argument list is matched as selectors of its own, anchored nowhere }
  Plain := M; Plain.Anchor := nil;
  for K := 0 to High(L) do
    if (L[K].PseudoElement = '') and MatchSel(Plain, L[K], High(L[K].C), N) then Exit(True);
  Result := False;
end;

function InkMatches(N: TInkNode; const ASelector: string): Boolean;
var L: TSelList; M: TMatcher;
begin
  Result := False;
  if (N = nil) or (N.Kind <> inkElement) then Exit;
  try
    L := ParseSelectorList(ASelector, False, False);
  except
    on ESelector do Exit;
  end;
  try
    M := Default(TMatcher);
    Result := MatchList(M, L, N);
  finally FreeList(L) end;
end;

function InkSelectorValid(const ASelector: string): Boolean;
var L: TSelList;
begin
  try
    L := ParseSelectorList(ASelector, False, False);
    FreeList(L);
    Result := True;
  except
    on ESelector do Result := False;
  end;
end;

function InkQuerySelectorAll(ARoot: TInkNode; const ASelector: string): TInkNodeArray;
var L: TSelList; M: TMatcher; N: TInkNode; Count: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  try
    L := ParseSelectorList(ASelector, False, False);
  except
    on ESelector do Exit;
  end;
  try
    M := Default(TMatcher);
    if ARoot.Kind = inkElement then M.Scope := ARoot;
    Count := 0;
    N := ARoot.NextInTree(ARoot);
    while N <> nil do
    begin
      if (N.Kind = inkElement) and MatchList(M, L, N) then
      begin
        if Count = System.Length(Result) then SetLength(Result, Count * 2 + 8);
        Result[Count] := N; Inc(Count);
      end;
      N := N.NextInTree(ARoot);
    end;
    SetLength(Result, Count);
  finally FreeList(L) end;
end;

function InkQuerySelector(ARoot: TInkNode; const ASelector: string): TInkNode;
var All: TInkNodeArray;
begin
  All := InkQuerySelectorAll(ARoot, ASelector);
  if System.Length(All) > 0 then Result := All[0] else Result := nil;
end;

{ ---------------------------------------------------------- declarations }

type
  TDecl = record
    { a property's index; -1 a custom property; -2 a shorthand whose value
      waits on var() and is taken apart after }
    Prop: Integer;
    Name, Value: string;
    Important: Boolean;
  end;
  TDeclArray = array of TDecl;

  TRule = class
    Sels: TSelList;
    Text: string;
    { its cascade layer's full name ('' outside every layer), and where
      that layer stands - set by Compute }
    Layer: string;
    Rank: Integer;
    Decls: TDeclArray;
    Origin: TInkStyleOrigin;
    Order: Integer;
    Media: array of Integer;
    destructor Destroy; override;
  end;

  TRef = class
    Rule: TRule;
    Sel: TSel;
  end;

  THints = class
    Decls: TDeclArray;
  end;

destructor TRule.Destroy;
begin
  FreeList(Sels);
  inherited Destroy;
end;

procedure AddDecl(var D: TDeclArray; AProp: Integer; const AName, AValue: string; AImportant: Boolean);
var K: Integer;
begin
  K := System.Length(D); SetLength(D, K + 1);
  D[K].Prop := AProp; D[K].Name := AName; D[K].Value := AValue; D[K].Important := AImportant;
end;

procedure Longhand(var D: TDeclArray; const AName, AValue: string; AImportant: Boolean);
var I: Integer;
begin
  I := InkPropertyIndex(AName);
  if I >= 0 then AddDecl(D, I, AName, Trim(AValue), AImportant);
end;

function IsCSSWide(const V: string): Boolean;
var L: string;
begin
  L := LowTrim(V);
  Result := (L = 'inherit') or (L = 'initial') or (L = 'unset') or (L = 'revert') or (L = 'revert-layer');
end;

function IsLengthWord(const W: string): Boolean;
var L: string; C: Char;
begin
  L := LowerCase(W);
  if (L = 'thin') or (L = 'medium') or (L = 'thick') or (L = '0') or (L = 'auto') then Exit(True);
  if (Copy(L, 1, 5) = 'calc(') or (Copy(L, 1, 4) = 'min(') or (Copy(L, 1, 4) = 'max(') or
    (Copy(L, 1, 6) = 'clamp(') then Exit(True);
  if L = '' then Exit(False);
  C := L[1];
  Result := (C in ['0'..'9', '.']) or ((C in ['+', '-']) and (System.Length(L) > 1) and (L[2] in ['0'..'9', '.']));
end;

function IsColorWord(const W: string): Boolean;
var C: TInkRGBA; L: string;
begin
  L := LowerCase(W);
  Result := InkParseColor(W, C) or (L = 'currentcolor') or (Copy(L, 1, 4) = 'var(') or
    (Copy(L, 1, 10) = 'color-mix(') or (Copy(L, 1, 4) = 'lab(') or (Copy(L, 1, 6) = 'oklch(') or
    (Copy(L, 1, 6) = 'oklab(') or (Copy(L, 1, 4) = 'lch(') or (Copy(L, 1, 4) = 'hwb(');
end;

const
  BorderStyles: array[0..9] of string = ('none', 'hidden', 'dotted', 'dashed', 'solid',
    'double', 'groove', 'ridge', 'inset', 'outset');

function IsBorderStyle(const W: string): Boolean;
var I: Integer; L: string;
begin
  L := LowerCase(W);
  for I := 0 to High(BorderStyles) do
    if BorderStyles[I] = L then Exit(True);
  Result := False;
end;

{ the CSS way of writing four sides: one value for all, two for vertical
  and horizontal, three for top, sides, bottom, four in clock order }
procedure FourSides(var D: TDeclArray; const APre, APost, AValue: string; AImp: Boolean);
var W: TStringArray; T, R, B, L: string;
begin
  W := Words(AValue);
  case System.Length(W) of
    1: begin T := W[0]; R := T; B := T; L := T end;
    2: begin T := W[0]; R := W[1]; B := T; L := R end;
    3: begin T := W[0]; R := W[1]; B := W[2]; L := R end;
    4: begin T := W[0]; R := W[1]; B := W[2]; L := W[3] end;
  else
    Exit;
  end;
  Longhand(D, APre + 'top' + APost, T, AImp);
  Longhand(D, APre + 'right' + APost, R, AImp);
  Longhand(D, APre + 'bottom' + APost, B, AImp);
  Longhand(D, APre + 'left' + APost, L, AImp);
end;

procedure BorderSide(var D: TDeclArray; const ASide, AValue: string; AImp: Boolean);
var W: TStringArray; I: Integer; Wid, Sty, Col: string;
begin
  Wid := 'medium'; Sty := 'none'; Col := 'currentcolor';
  W := Words(AValue);
  for I := 0 to High(W) do
    if IsBorderStyle(W[I]) then Sty := W[I]
    else if IsLengthWord(W[I]) then Wid := W[I]
    else Col := W[I];
  Longhand(D, 'border-' + ASide + '-width', Wid, AImp);
  Longhand(D, 'border-' + ASide + '-style', Sty, AImp);
  Longhand(D, 'border-' + ASide + '-color', Col, AImp);
end;

{ the longhands a shorthand stands for }
function ShorthandParts(const AName: string): TStringArray;
  function Sides(const APre, APost: string): TStringArray;
  begin
    Result := nil;
    SetLength(Result, 4);
    Result[0] := APre + 'top' + APost; Result[1] := APre + 'right' + APost;
    Result[2] := APre + 'bottom' + APost; Result[3] := APre + 'left' + APost;
  end;
  function Three(const ASide: string): TStringArray;
  begin
    Result := nil;
    SetLength(Result, 3);
    Result[0] := 'border-' + ASide + '-width'; Result[1] := 'border-' + ASide + '-style';
    Result[2] := 'border-' + ASide + '-color';
  end;
  function Join(const A, B: TStringArray): TStringArray;
  var I: Integer;
  begin
    Result := nil;
    SetLength(Result, System.Length(A) + System.Length(B));
    for I := 0 to High(A) do Result[I] := A[I];
    for I := 0 to High(B) do Result[System.Length(A) + I] := B[I];
  end;
  function Of_(const Names: array of string): TStringArray;
  var I: Integer;
  begin
    Result := nil;
    SetLength(Result, System.Length(Names));
    for I := 0 to High(Names) do Result[I] := Names[I];
  end;
begin
  case AName of
    'margin', 'padding': Result := Sides(AName + '-', '');
    'inset': Result := Sides('', '');
    'border-width': Result := Sides('border-', '-width');
    'border-style': Result := Sides('border-', '-style');
    'border-color': Result := Sides('border-', '-color');
    'border': Result := Join(Join(Three('top'), Three('right')), Join(Three('bottom'), Three('left')));
    'border-top', 'border-right', 'border-bottom', 'border-left': Result := Three(Copy(AName, 8, MaxInt));
    'border-inline': Result := Join(Three('left'), Three('right'));
    'border-block': Result := Join(Three('top'), Three('bottom'));
    'border-radius': Result := Of_(['border-top-left-radius', 'border-top-right-radius',
      'border-bottom-right-radius', 'border-bottom-left-radius']);
    'background': Result := Of_(['background-color', 'background-image', 'background-repeat',
      'background-position', 'background-size']);
    'font': Result := Of_(['font-style', 'font-variant', 'font-weight', 'font-stretch',
      'font-size', 'line-height', 'font-family']);
    'list-style': Result := Of_(['list-style-type', 'list-style-position', 'list-style-image']);
    'flex': Result := Of_(['flex-grow', 'flex-shrink', 'flex-basis']);
    'flex-flow': Result := Of_(['flex-direction', 'flex-wrap']);
    'gap', 'grid-gap': Result := Of_(['row-gap', 'column-gap']);
    'overflow': Result := Of_(['overflow-x', 'overflow-y']);
    'text-decoration': Result := Of_(['text-decoration-line', 'text-decoration-style', 'text-decoration-color']);
    'outline': Result := Of_(['outline-width', 'outline-style', 'outline-color']);
    'grid-row': Result := Of_(['grid-row-start', 'grid-row-end']);
    'grid-column': Result := Of_(['grid-column-start', 'grid-column-end']);
    'grid-area': Result := Of_(['grid-row-start', 'grid-column-start', 'grid-row-end', 'grid-column-end']);
    'grid-template': Result := Of_(['grid-template-rows', 'grid-template-columns']);
    'place-items': Result := Of_(['align-items', 'justify-items']);
    'place-content': Result := Of_(['align-content', 'justify-content']);
    'place-self': Result := Of_(['align-self', 'justify-self']);
    'margin-inline', 'padding-inline': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'left',
      Copy(AName, 1, Pos('-', AName)) + 'right']);
    'margin-block', 'padding-block': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'top',
      Copy(AName, 1, Pos('-', AName)) + 'bottom']);
    'columns': Result := Of_(['column-width', 'column-count']);
    'border-inline-width', 'border-inline-style', 'border-inline-color':
      Result := Of_(['border-left' + Copy(AName, 14, MaxInt), 'border-right' + Copy(AName, 14, MaxInt)]);
    'border-block-width', 'border-block-style', 'border-block-color':
      Result := Of_(['border-top' + Copy(AName, 13, MaxInt), 'border-bottom' + Copy(AName, 13, MaxInt)]);
    'border-inline-start-width', 'border-inline-start-style', 'border-inline-start-color':
      Result := Of_(['border-left' + Copy(AName, 20, MaxInt)]);
    'border-inline-end-width', 'border-inline-end-style', 'border-inline-end-color':
      Result := Of_(['border-right' + Copy(AName, 18, MaxInt)]);
    'border-block-start-width', 'border-block-start-style', 'border-block-start-color':
      Result := Of_(['border-top' + Copy(AName, 19, MaxInt)]);
    'border-block-end-width', 'border-block-end-style', 'border-block-end-color':
      Result := Of_(['border-bottom' + Copy(AName, 17, MaxInt)]);
    'border-inline-start': Result := Three('left');
    'border-inline-end': Result := Three('right');
    'border-block-start': Result := Three('top');
    'border-block-end': Result := Three('bottom');
    'margin-inline-start', 'padding-inline-start': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'left']);
    'margin-inline-end', 'padding-inline-end': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'right']);
    'margin-block-start', 'padding-block-start': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'top']);
    'margin-block-end', 'padding-block-end': Result := Of_([Copy(AName, 1, Pos('-', AName)) + 'bottom']);
    'inset-inline-start': Result := Of_(['left']);
    'inset-inline-end': Result := Of_(['right']);
    'inset-block-start': Result := Of_(['top']);
    'inset-block-end': Result := Of_(['bottom']);
    'inline-size': Result := Of_(['width']);
    'block-size': Result := Of_(['height']);
    'min-inline-size': Result := Of_(['min-width']);
    'max-inline-size': Result := Of_(['max-width']);
    'min-block-size': Result := Of_(['min-height']);
    'max-block-size': Result := Of_(['max-height']);
    'text-wrap', 'text-wrap-mode': Result := Of_(['white-space']);
    'word-wrap': Result := Of_(['overflow-wrap']);
  else
    Result := nil;
  end;
end;

{ every longhand a shorthand sets, with its value; False when AName is not
  a shorthand }
function Expand(var D: TDeclArray; const AName, AValue: string; AImp: Boolean): Boolean;
var W: TStringArray; V, L, Size, Lh, Fam: string; I, K: Integer; Sides: array[0..3] of string;
  Seen: Boolean;
begin
  Result := True;
  V := Trim(AValue);
  if IsCSSWide(V) then
  begin
    { inherit and its kin go to every part }
    W := ShorthandParts(AName);
    if System.Length(W) = 0 then Exit(False);
    for I := 0 to High(W) do Longhand(D, W[I], V, AImp);
    Exit;
  end;
  W := Words(V);
  case AName of
    'margin': FourSides(D, 'margin-', '', V, AImp);
    'padding': FourSides(D, 'padding-', '', V, AImp);
    'inset': FourSides(D, '', '', V, AImp);
    'border-width': FourSides(D, 'border-', '-width', V, AImp);
    'border-style': FourSides(D, 'border-', '-style', V, AImp);
    'border-color': FourSides(D, 'border-', '-color', V, AImp);
    'border':
      begin
        BorderSide(D, 'top', V, AImp); BorderSide(D, 'right', V, AImp);
        BorderSide(D, 'bottom', V, AImp); BorderSide(D, 'left', V, AImp);
      end;
    'border-top', 'border-right', 'border-bottom', 'border-left':
      BorderSide(D, Copy(AName, 8, MaxInt), V, AImp);
    'border-inline':
      begin BorderSide(D, 'left', V, AImp); BorderSide(D, 'right', V, AImp) end;
    'border-block':
      begin BorderSide(D, 'top', V, AImp); BorderSide(D, 'bottom', V, AImp) end;
    'border-inline-width', 'border-inline-style', 'border-inline-color',
    'border-block-width', 'border-block-style', 'border-block-color':
      begin
        { a pair of sides: one value for both, or start then end }
        L := Copy(AName, System.Length(AName) - 5, 6);
        if L[1] <> '-' then L := '-' + L;
        if Pos('inline', AName) > 0 then begin Sides[0] := 'left'; Sides[1] := 'right' end
        else begin Sides[0] := 'top'; Sides[1] := 'bottom' end;
        if System.Length(W) = 0 then Exit;
        Longhand(D, 'border-' + Sides[0] + L, W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, 'border-' + Sides[1] + L, W[1], AImp)
        else Longhand(D, 'border-' + Sides[1] + L, W[0], AImp);
      end;
    'border-inline-start-width', 'border-inline-start-style', 'border-inline-start-color':
      Longhand(D, 'border-left' + Copy(AName, 20, MaxInt), V, AImp);
    'border-inline-end-width', 'border-inline-end-style', 'border-inline-end-color':
      Longhand(D, 'border-right' + Copy(AName, 18, MaxInt), V, AImp);
    'border-block-start-width', 'border-block-start-style', 'border-block-start-color':
      Longhand(D, 'border-top' + Copy(AName, 19, MaxInt), V, AImp);
    'border-block-end-width', 'border-block-end-style', 'border-block-end-color':
      Longhand(D, 'border-bottom' + Copy(AName, 17, MaxInt), V, AImp);
    'border-inline-start': BorderSide(D, 'left', V, AImp);
    'border-inline-end': BorderSide(D, 'right', V, AImp);
    'border-block-start': BorderSide(D, 'top', V, AImp);
    'border-block-end': BorderSide(D, 'bottom', V, AImp);
    'border-radius':
      begin
        { the horizontal radii only: an elliptical corner draws round }
        I := Pos('/', V);
        if I > 0 then V := Trim(Copy(V, 1, I - 1));
        W := Words(V);
        case System.Length(W) of
          1: begin Sides[0] := W[0]; Sides[1] := W[0]; Sides[2] := W[0]; Sides[3] := W[0] end;
          2: begin Sides[0] := W[0]; Sides[1] := W[1]; Sides[2] := W[0]; Sides[3] := W[1] end;
          3: begin Sides[0] := W[0]; Sides[1] := W[1]; Sides[2] := W[2]; Sides[3] := W[1] end;
          4: begin Sides[0] := W[0]; Sides[1] := W[1]; Sides[2] := W[2]; Sides[3] := W[3] end;
        else
          Exit;
        end;
        Longhand(D, 'border-top-left-radius', Sides[0], AImp);
        Longhand(D, 'border-top-right-radius', Sides[1], AImp);
        Longhand(D, 'border-bottom-right-radius', Sides[2], AImp);
        Longhand(D, 'border-bottom-left-radius', Sides[3], AImp);
      end;
    'margin-inline', 'padding-inline':
      begin
        L := Copy(AName, 1, Pos('-', AName));
        if System.Length(W) = 0 then Exit;
        Longhand(D, L + 'left', W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, L + 'right', W[1], AImp)
        else Longhand(D, L + 'right', W[0], AImp);
      end;
    'margin-block', 'padding-block':
      begin
        L := Copy(AName, 1, Pos('-', AName));
        if System.Length(W) = 0 then Exit;
        Longhand(D, L + 'top', W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, L + 'bottom', W[1], AImp)
        else Longhand(D, L + 'bottom', W[0], AImp);
      end;
    'margin-inline-start', 'padding-inline-start': Longhand(D, Copy(AName, 1, Pos('-', AName)) + 'left', V, AImp);
    'margin-inline-end', 'padding-inline-end': Longhand(D, Copy(AName, 1, Pos('-', AName)) + 'right', V, AImp);
    'margin-block-start', 'padding-block-start': Longhand(D, Copy(AName, 1, Pos('-', AName)) + 'top', V, AImp);
    'margin-block-end', 'padding-block-end': Longhand(D, Copy(AName, 1, Pos('-', AName)) + 'bottom', V, AImp);
    'inset-inline-start': Longhand(D, 'left', V, AImp);
    'inset-inline-end': Longhand(D, 'right', V, AImp);
    'inset-block-start': Longhand(D, 'top', V, AImp);
    'inset-block-end': Longhand(D, 'bottom', V, AImp);
    'inline-size': Longhand(D, 'width', V, AImp);
    'block-size': Longhand(D, 'height', V, AImp);
    'min-inline-size': Longhand(D, 'min-width', V, AImp);
    'max-inline-size': Longhand(D, 'max-width', V, AImp);
    'min-block-size': Longhand(D, 'min-height', V, AImp);
    'max-block-size': Longhand(D, 'max-height', V, AImp);
    'background':
      begin
        { the color, and the picture; where and how it repeats rides along }
        Sides[0] := 'transparent'; Sides[1] := 'none'; Sides[2] := 'repeat'; Sides[3] := '';
        { several layers: the last one carries the color }
        if System.Length(SplitTop(V, ',')) > 1 then
        begin
          W := Words(SplitTop(V, ',')[High(SplitTop(V, ','))]);
          for I := 0 to High(SplitTop(V, ',')) - 1 do
            if Pos('(', SplitTop(V, ',')[I]) > 0 then
            begin
              Sides[1] := Trim(SplitTop(V, ',')[I]);
              Break;
            end;
        end;
        for I := 0 to High(W) do
        begin
          L := LowerCase(W[I]);
          if (Copy(L, 1, 4) = 'url(') or (Pos('gradient(', L) > 0) or (Copy(L, 1, 10) = 'image-set(') then
            Sides[1] := W[I]
          else if (L = 'repeat') or (L = 'no-repeat') or (L = 'repeat-x') or (L = 'repeat-y') or
            (L = 'space') or (L = 'round') then Sides[2] := W[I]
          else if IsColorWord(W[I]) and (L <> 'none') then Sides[0] := W[I]
          else if L <> 'none' then Sides[3] := Trim(Sides[3] + ' ' + W[I]);
        end;
        Longhand(D, 'background-color', Sides[0], AImp);
        Longhand(D, 'background-image', Sides[1], AImp);
        Longhand(D, 'background-repeat', Sides[2], AImp);
        if Sides[3] <> '' then
        begin
          I := Pos('/', Sides[3]);
          if I > 0 then
          begin
            Longhand(D, 'background-position', Copy(Sides[3], 1, I - 1), AImp);
            Longhand(D, 'background-size', Copy(Sides[3], I + 1, MaxInt), AImp);
          end
          else Longhand(D, 'background-position', Sides[3], AImp);
        end
        else Longhand(D, 'background-position', '0% 0%', AImp);
      end;
    'font':
      begin
        L := LowerCase(V);
        if (L = 'caption') or (L = 'icon') or (L = 'menu') or (L = 'message-box') or
          (L = 'small-caption') or (L = 'status-bar') then
        begin
          Longhand(D, 'font-family', 'system-ui', AImp); Exit;
        end;
        Longhand(D, 'font-style', 'normal', AImp);
        Longhand(D, 'font-variant', 'normal', AImp);
        Longhand(D, 'font-weight', 'normal', AImp);
        Longhand(D, 'font-stretch', 'normal', AImp);
        Longhand(D, 'line-height', 'normal', AImp);
        Size := ''; Lh := ''; Fam := '';
        I := 0;
        while I <= High(W) do
        begin
          L := LowerCase(W[I]);
          if Size = '' then
          begin
            if (L = 'italic') or (L = 'oblique') then Longhand(D, 'font-style', L, AImp)
            else if L = 'small-caps' then Longhand(D, 'font-variant', L, AImp)
            else if (L = 'bold') or (L = 'bolder') or (L = 'lighter') or
              ((System.Length(L) = 3) and (L[1] in ['1'..'9']) and (L[2] = '0') and (L[3] = '0')) then
              Longhand(D, 'font-weight', L, AImp)
            else if (Pos('condensed', L) > 0) or (Pos('expanded', L) > 0) then
              Longhand(D, 'font-stretch', L, AImp)
            else if L = 'normal' then
            else
            begin
              K := Pos('/', W[I]);
              if K > 0 then
              begin
                Size := Copy(W[I], 1, K - 1); Lh := Copy(W[I], K + 1, MaxInt);
                if (Lh = '') and (I < High(W)) then begin Inc(I); Lh := W[I] end;
              end
              else
              begin
                Size := W[I];
                if (I < High(W)) and (Copy(W[I + 1], 1, 1) = '/') then
                begin
                  Inc(I); Lh := Copy(W[I], 2, MaxInt);
                  if (Lh = '') and (I < High(W)) then begin Inc(I); Lh := W[I] end;
                end;
              end;
            end;
          end
          else Fam := Trim(Fam + ' ' + W[I]);
          Inc(I);
        end;
        if (Size = '') or (Fam = '') then Exit;
        Longhand(D, 'font-size', Size, AImp);
        if Lh <> '' then Longhand(D, 'line-height', Lh, AImp);
        Longhand(D, 'font-family', Fam, AImp);
      end;
    'list-style':
      begin
        Seen := False;
        for I := 0 to High(W) do
        begin
          L := LowerCase(W[I]);
          if (L = 'inside') or (L = 'outside') then Longhand(D, 'list-style-position', L, AImp)
          else if Copy(L, 1, 4) = 'url(' then Longhand(D, 'list-style-image', W[I], AImp)
          else if L = 'none' then
          begin
            Longhand(D, 'list-style-type', 'none', AImp); Seen := True;
          end
          else begin Longhand(D, 'list-style-type', W[I], AImp); Seen := True end;
        end;
        if not Seen then Longhand(D, 'list-style-type', 'disc', AImp);
      end;
    'flex':
      begin
        L := LowerCase(V);
        if L = 'none' then begin Sides[0] := '0'; Sides[1] := '0'; Sides[2] := 'auto' end
        else if L = 'auto' then begin Sides[0] := '1'; Sides[1] := '1'; Sides[2] := 'auto' end
        else
        begin
          Sides[0] := '1'; Sides[1] := '1'; Sides[2] := '0%';
          K := 0;
          for I := 0 to High(W) do
            if (W[I] <> '') and (W[I][1] in ['0'..'9', '.']) and
              (StrToFloatDef(W[I], -1, CSSFormat) >= 0) and (K < 2) then
            begin
              Sides[K] := W[I]; Inc(K);
            end
            else Sides[2] := W[I];
        end;
        Longhand(D, 'flex-grow', Sides[0], AImp);
        Longhand(D, 'flex-shrink', Sides[1], AImp);
        Longhand(D, 'flex-basis', Sides[2], AImp);
      end;
    'flex-flow':
      for I := 0 to High(W) do
        if Pos('wrap', LowerCase(W[I])) > 0 then Longhand(D, 'flex-wrap', W[I], AImp)
        else Longhand(D, 'flex-direction', W[I], AImp);
    'gap', 'grid-gap':
      if System.Length(W) > 0 then
      begin
        Longhand(D, 'row-gap', W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, 'column-gap', W[1], AImp)
        else Longhand(D, 'column-gap', W[0], AImp);
      end;
    'grid-row-gap': Longhand(D, 'row-gap', V, AImp);
    'grid-column-gap': Longhand(D, 'column-gap', V, AImp);
    'overflow':
      if System.Length(W) > 0 then
      begin
        Longhand(D, 'overflow-x', W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, 'overflow-y', W[1], AImp)
        else Longhand(D, 'overflow-y', W[0], AImp);
      end;
    'text-decoration':
      begin
        Sides[0] := ''; Sides[1] := 'solid'; Sides[2] := 'currentcolor';
        for I := 0 to High(W) do
        begin
          L := LowerCase(W[I]);
          if (L = 'underline') or (L = 'overline') or (L = 'line-through') or (L = 'blink') or
            (L = 'none') then Sides[0] := Trim(Sides[0] + ' ' + L)
          else if (L = 'solid') or (L = 'double') or (L = 'dotted') or (L = 'dashed') or
            (L = 'wavy') then Sides[1] := L
          else if IsColorWord(W[I]) then Sides[2] := W[I];
        end;
        if Sides[0] = '' then Sides[0] := 'none';
        Longhand(D, 'text-decoration-line', Sides[0], AImp);
        Longhand(D, 'text-decoration-style', Sides[1], AImp);
        Longhand(D, 'text-decoration-color', Sides[2], AImp);
      end;
    'outline':
      begin
        Sides[0] := 'medium'; Sides[1] := 'none'; Sides[2] := 'currentcolor';
        for I := 0 to High(W) do
          if IsBorderStyle(W[I]) or (LowerCase(W[I]) = 'auto') then Sides[1] := W[I]
          else if IsLengthWord(W[I]) then Sides[0] := W[I]
          else Sides[2] := W[I];
        Longhand(D, 'outline-width', Sides[0], AImp);
        Longhand(D, 'outline-style', Sides[1], AImp);
        Longhand(D, 'outline-color', Sides[2], AImp);
      end;
    'grid-row', 'grid-column':
      begin
        I := Pos('/', V);
        if I > 0 then
        begin
          Longhand(D, AName + '-start', Copy(V, 1, I - 1), AImp);
          Longhand(D, AName + '-end', Copy(V, I + 1, MaxInt), AImp);
        end
        else
        begin
          Longhand(D, AName + '-start', V, AImp);
          if Copy(LowTrim(V), 1, 4) = 'span' then Longhand(D, AName + '-end', 'auto', AImp)
          else Longhand(D, AName + '-end', 'auto', AImp);
        end;
      end;
    'grid-area':
      begin
        W := SplitTop(V, '/');
        for I := 0 to High(W) do W[I] := Trim(W[I]);
        Longhand(D, 'grid-row-start', W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, 'grid-column-start', W[1], AImp);
        if System.Length(W) > 2 then Longhand(D, 'grid-row-end', W[2], AImp);
        if System.Length(W) > 3 then Longhand(D, 'grid-column-end', W[3], AImp);
      end;
    'place-items', 'place-content', 'place-self':
      if System.Length(W) > 0 then
      begin
        L := Copy(AName, 7, MaxInt);
        Longhand(D, 'align-' + L, W[0], AImp);
        if System.Length(W) > 1 then Longhand(D, 'justify-' + L, W[1], AImp)
        else Longhand(D, 'justify-' + L, W[0], AImp);
      end;
    'columns':
      for I := 0 to High(W) do
        if IsLengthWord(W[I]) and not (W[I][1] in ['0'..'9']) or (Pos('px', W[I]) > 0) or
          (Pos('em', W[I]) > 0) then Longhand(D, 'column-width', W[I], AImp)
        else Longhand(D, 'column-count', W[I], AImp);
    'word-wrap': Longhand(D, 'overflow-wrap', V, AImp);
    'text-wrap', 'text-wrap-mode':
      { the newer way of saying white-space: nowrap }
      if Pos('nowrap', LowerCase(V)) > 0 then Longhand(D, 'white-space', 'nowrap', AImp);
    'grid-template':
      begin
        I := Pos('/', V);
        if I > 0 then
        begin
          Longhand(D, 'grid-template-rows', Copy(V, 1, I - 1), AImp);
          Longhand(D, 'grid-template-columns', Copy(V, I + 1, MaxInt), AImp);
        end;
      end;
  else
    Result := False;
  end;
end;

{ every url() made absolute against the sheet it was written in }
function AbsoluteURLs(const V, ABase: string): string;
var P, Q, E: Integer; Inner, Abs_: string; Qc: Char;
begin
  if (ABase = '') or (Pos('url(', LowerCase(V)) = 0) then Exit(V);
  Result := ''; P := 1;
  while True do
  begin
    Q := PosEx('url(', LowerCase(V), P);
    if Q = 0 then Break;
    E := PosEx(')', V, Q);
    if E = 0 then Break;
    Inner := Trim(Copy(V, Q + 4, E - Q - 4));
    if (Inner <> '') and (Inner[1] in ['"', '''']) then
    begin
      Qc := Inner[1];
      Inner := Copy(Inner, 2, MaxInt);
      if (Inner <> '') and (Inner[System.Length(Inner)] = Qc) then SetLength(Inner, System.Length(Inner) - 1);
    end;
    if (Copy(LowerCase(Inner), 1, 5) = 'data:') or not ResolveRelativeURI(ABase, Inner, Abs_) then Abs_ := Inner;
    Result := Result + Copy(V, P, Q - P) + 'url("' + Abs_ + '")';
    P := E + 1;
  end;
  Result := Result + Copy(V, P, MaxInt);
end;

{ "color: red; margin: 0 !important" as declarations }
function ParseDecls(const AText, ABase: string): TDeclArray;
var Parts: TStringArray; I, Colon, K: Integer; Name, V, L: string; Imp: Boolean;
begin
  Result := nil;
  Parts := SplitTop(AText, ';');
  for I := 0 to High(Parts) do
  begin
    Colon := Pos(':', Parts[I]);
    if Colon = 0 then Continue;
    Name := Trim(Copy(Parts[I], 1, Colon - 1));
    V := Trim(Copy(Parts[I], Colon + 1, MaxInt));
    if Name = '' then Continue;
    if Copy(Name, 1, 2) <> '--' then Name := LowerCase(Name);
    Imp := False;
    K := LastDelimiter('!', V);
    if K > 0 then
    begin
      L := LowTrim(Copy(V, K + 1, MaxInt));
      if L = 'important' then
      begin
        Imp := True; V := Trim(Copy(V, 1, K - 1));
      end;
    end;
    if Copy(Name, 1, 2) = '--' then
    begin
      AddDecl(Result, -1, Name, V, Imp);
      Continue;
    end;
    if V = '' then Continue;
    V := AbsoluteURLs(V, ABase);
    if Pos('var(', LowerCase(V)) > 0 then
    begin
      { a shorthand waits until its var() is known }
      if InkPropertyIndex(Name) >= 0 then AddDecl(Result, InkPropertyIndex(Name), Name, V, Imp)
      else AddDecl(Result, -2, Name, V, Imp);
      Continue;
    end;
    if InkPropertyIndex(Name) >= 0 then AddDecl(Result, InkPropertyIndex(Name), Name, V, Imp)
    else Expand(Result, Name, V, Imp);
  end;
end;

{ ------------------------------------------------------------- the style }

destructor TInkStyle.Destroy;
begin
  if FOwnsCustom then FCustom.Free;
  inherited Destroy;
end;

function TInkStyle.Value(const AProp: string): string;
var I: Integer;
begin
  I := InkPropertyIndex(AProp);
  if I >= 0 then Result := FValues[I] else Result := '';
end;

function TInkStyle.Keyword(const AProp: string): string;
begin
  Result := LowTrim(Value(AProp));
end;

function TInkStyle.Length(const AValue: string; APercentOf: Double; ADefault: Double): Double;
var Ctx: TLengthContext; L: string;
begin
  L := LowTrim(AValue);
  if (L = 'thin') then Exit(1);
  if (L = 'medium') then Exit(3);
  if (L = 'thick') then Exit(5);
  Ctx.Font := FontSize; Ctx.Root := RootFontSize;
  Ctx.VW := 1024; Ctx.VH := 768;
  if FStyler <> nil then
  begin
    Ctx.VW := FStyler.Media.Width; Ctx.VH := FStyler.Media.Height;
  end;
  Ctx.Percent := APercentOf;
  if not EvalLength(L, Ctx, Result) then Result := ADefault;
end;

function TInkStyle.Px(const AProp: string; APercentOf: Double; ADefault: Double): Double;
var V: string;
begin
  V := Keyword(AProp);
  { a border that is not drawn has no width }
  if (Copy(AProp, 1, 7) = 'border-') and (Copy(AProp, System.Length(AProp) - 5, 6) = '-width') then
  begin
    if (Keyword(Copy(AProp, 1, System.Length(AProp) - 6) + '-style') = 'none') or
      (Keyword(Copy(AProp, 1, System.Length(AProp) - 6) + '-style') = 'hidden') then Exit(0);
  end;
  if (AProp = 'outline-width') and (Keyword('outline-style') = 'none') then Exit(0);
  Result := Length(V, APercentOf, ADefault);
end;

function TInkStyle.Color(const AProp: string): TInkRGBA;
var V: string; Dark: Boolean;
begin
  V := Keyword(AProp);
  Dark := (FStyler <> nil) and FStyler.Media.Dark;
  if (V = 'currentcolor') and (AProp <> 'color') then V := Keyword('color');
  if FStyler <> nil then
    case V of
      'canvas': Exit(FStyler.CanvasColor);
      'canvastext': Exit(FStyler.CanvasTextColor);
      'linktext': Exit(FStyler.LinkColor);
      'visitedtext': Exit(FStyler.VisitedColor);
    end;
  if not InkParseColor(V, Result, Dark) then
  begin
    if AProp = 'color' then InkParseColor('canvastext', Result, Dark) else Result := 0;
    if (AProp = 'color') and (FStyler <> nil) then Result := FStyler.CanvasTextColor;
  end;
end;

function TInkStyle.Custom(const AName: string): string;
var I: Integer;
begin
  Result := '';
  if FCustom = nil then Exit;
  I := FCustom.IndexOfName(AName);
  if I >= 0 then Result := FCustom.ValueFromIndex[I];
end;

{ ------------------------------------------------------------ the styler }

constructor TInkStyler.Create;
begin
  inherited Create;
  FRules := TFPObjectList.Create(True);
  FRefs := TFPObjectList.Create(True);
  FById := TFPHashList.Create;
  FByClass := TFPHashList.Create;
  FByTag := TFPHashList.Create;
  FUniversal := TFPList.Create;
  FPseudoRefs := TFPList.Create;
  FMediaTexts := TStringList.Create;
  FStyles := TFPObjectList.Create(True);
  FShare := TFPObjectHashTable.Create(False);
  FInfos := TFPList.Create;
  FHintRules := TFPObjectHashTable.Create(True);
  FLayerNames := TStringList.Create;
  FRegistered := TStringList.Create;
  Media.Width := 1024; Media.Height := 768;
  CanvasColor := RGBA($FFFFFF, 255); CanvasTextColor := RGBA($000000, 255);
  LinkColor := RGBA($0000EE, 255); VisitedColor := RGBA($551A8B, 255);
  ParseSheet(InkUserAgentCSS, isoUserAgent, [], '');
  FUAOrder := FOrder;
end;

destructor TInkStyler.Destroy;
var I: Integer;
begin
  Release;
  for I := 0 to FById.Count - 1 do TFPList(FById[I]).Free;
  for I := 0 to FByClass.Count - 1 do TFPList(FByClass[I]).Free;
  for I := 0 to FByTag.Count - 1 do TFPList(FByTag[I]).Free;
  FById.Free; FByClass.Free; FByTag.Free;
  FUniversal.Free; FPseudoRefs.Free;
  FRefs.Free; FRules.Free;
  FMediaTexts.Free;
  FStyles.Free; FShare.Free; FInfos.Free; FHintRules.Free; FLayerNames.Free; FRegistered.Free;
  inherited Destroy;
end;

procedure TInkStyler.Clear;
var I: Integer;
begin
  Release;
  { the browser's rules are the first ones; the page's go, and the buckets
    are filled again from what is left }
  for I := 0 to FById.Count - 1 do TFPList(FById[I]).Free;
  for I := 0 to FByClass.Count - 1 do TFPList(FByClass[I]).Free;
  for I := 0 to FByTag.Count - 1 do TFPList(FByTag[I]).Free;
  FById.Clear; FByClass.Clear; FByTag.Clear; FUniversal.Clear; FPseudoRefs.Clear;
  for I := FRefs.Count - 1 downto 0 do
    if TRef(FRefs[I]).Rule.Origin = isoAuthor then FRefs.Delete(I);
  for I := FRules.Count - 1 downto 0 do
    if TRule(FRules[I]).Origin = isoAuthor then FRules.Delete(I);
  for I := 0 to FRefs.Count - 1 do Index(FRefs[I]);
  FMediaTexts.Clear;
  FLayerNames.Clear; FLayer := ''; FAnonLayers := 0; FRegistered.Clear;
  FOrder := FUAOrder;
end;

function TInkStyler.RuleCount: Integer;
begin
  Result := FRules.Count;
end;

function TInkStyler.StyleCount: Integer;
begin
  Result := FStyles.Count;
end;

function TInkStyler.MediaIndex(const AText: string): Integer;
begin
  Result := FMediaTexts.IndexOf(AText);
  if Result < 0 then Result := FMediaTexts.Add(AText);
end;

procedure Bucket(AMap: TFPHashList; const AKey: string; ARef: TObject);
var L: TFPList;
begin
  L := TFPList(AMap.Find(AKey));
  if L = nil then
  begin
    L := TFPList.Create;
    AMap.Add(AKey, L);
  end;
  L.Add(ARef);
end;

{ a selector goes in one bucket, by the most telling part of its last
  compound, so an element looks only at rules that could be its }
procedure TInkStyler.Index(ARef: TObject);
var S: TSel;
begin
  S := TRef(ARef).Sel;
  if S.PseudoElement <> '' then begin FPseudoRefs.Add(ARef); Exit end;
  with S.C[High(S.C)] do
    if Id <> '' then Bucket(FById, Id, ARef)
    else if System.Length(Classes) > 0 then Bucket(FByClass, Classes[0], ARef)
    else if (Tag <> '') and (Tag <> '*') then Bucket(FByTag, Tag, ARef)
    else FUniversal.Add(ARef);
end;

procedure TInkStyler.AddRule(const ASelectors: string; const ADecls: string;
  AOrigin: TInkStyleOrigin; const AMedia: array of Integer; const ABase: string);
var R: TRule; Ref: TRef; I: Integer;
begin
  R := TRule.Create;
  try
    R.Sels := ParseSelectorList(ASelectors, False, False);
  except
    on ESelector do
    begin
      { a selector list with one bad selector is dropped whole }
      R.Free;
      Exit;
    end;
  end;
  R.Decls := ParseDecls(ADecls, ABase);
  if System.Length(R.Decls) = 0 then begin R.Free; Exit end;
  R.Origin := AOrigin;
  R.Text := ASelectors;
  R.Layer := FLayer;
  R.Order := FOrder; Inc(FOrder);
  SetLength(R.Media, System.Length(AMedia));
  for I := 0 to High(AMedia) do R.Media[I] := AMedia[I];
  FRules.Add(R);
  for I := 0 to High(R.Sels) do
  begin
    Ref := TRef.Create;
    Ref.Rule := R; Ref.Sel := R.Sels[I];
    FRefs.Add(Ref);
    Index(Ref);
  end;
end;

{ an @supports condition: a property LazInk reads, with any value; not, and,
  or, and selector() }
function Supports(const ACond: string): Boolean;
var C, Inner, Name: string; P, Depth, Start: Integer; Parts: array of string; Ops: array of string;
  I, Colon: Integer; Sub: TSelList;
begin
  C := Trim(ACond);
  if C = '' then Exit(False);
  if LowerCase(Copy(C, 1, 4)) = 'not ' then Exit(not Supports(Copy(C, 5, MaxInt)));
  { the parts joined at the top level by and / or }
  Parts := nil; Ops := nil; P := 1; Depth := 0; Start := 1;
  while P <= System.Length(C) do
  begin
    if C[P] = '(' then Inc(Depth) else if C[P] = ')' then Dec(Depth)
    else if (Depth = 0) and (IsSpace(C[P])) then
    begin
      if LowerCase(Copy(C, P + 1, 4)) = 'and ' then
      begin
        SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, P - Start);
        SetLength(Ops, System.Length(Ops) + 1); Ops[High(Ops)] := 'and';
        Inc(P, 4); Start := P + 1;
      end
      else if LowerCase(Copy(C, P + 1, 3)) = 'or ' then
      begin
        SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, P - Start);
        SetLength(Ops, System.Length(Ops) + 1); Ops[High(Ops)] := 'or';
        Inc(P, 3); Start := P + 1;
      end;
    end;
    Inc(P);
  end;
  if System.Length(Parts) > 0 then
  begin
    SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, MaxInt);
    Result := Supports(Parts[0]);
    for I := 0 to High(Ops) do
      if Ops[I] = 'and' then Result := Result and Supports(Parts[I + 1])
      else Result := Result or Supports(Parts[I + 1]);
    Exit;
  end;
  if LowerCase(Copy(C, 1, 9)) = 'selector(' then
  begin
    Inner := Copy(C, 10, System.Length(C) - 10);
    try
      Sub := ParseSelectorList(Inner, False, False);
      FreeList(Sub);
      Exit(True);
    except
      on ESelector do Exit(False);
    end;
  end;
  if (C[1] = '(') and (C[System.Length(C)] = ')') then
  begin
    Inner := Trim(Copy(C, 2, System.Length(C) - 2));
    Colon := Pos(':', Inner);
    if (Colon > 0) and (Pos('(', Copy(Inner, 1, Colon)) = 0) then
    begin
      { a page's @supports branches are written for a current browser: a
        declaration is taken as supported unless it is another engine's }
      Name := LowTrim(Copy(Inner, 1, Colon - 1));
      Exit((Name <> '') and (Copy(Name, 1, 5) <> '-moz-') and (Copy(Name, 1, 4) <> '-ms-') and
        (Copy(Name, 1, 3) <> '-o-'));
    end;
    Exit(Supports(Inner));
  end;
  Result := False;
end;

{ a layer's full name, parents first - a.b - registered with them }
procedure TInkStyler.RegisterLayer(const AName: string);
var P: Integer;
begin
  if AName = '' then Exit;
  P := LastDelimiter('.', AName);
  if P > 0 then RegisterLayer(Copy(AName, 1, P - 1));
  if FLayerNames.IndexOf(AName) < 0 then FLayerNames.Add(AName);
end;

{ the full name of a layer named inside the one being read; '' names a
  layer of its own that nothing else can name }
function TInkStyler.SubLayer(const AName: string): string;
var N: string;
begin
  N := Trim(AName);
  if N = '' then
  begin
    Inc(FAnonLayers); N := '#' + IntToStr(FAnonLayers);
  end;
  if FLayer <> '' then Result := FLayer + '.' + N else Result := N;
  RegisterLayer(Result);
end;

{ every layer's place: a layer's sublayers before its own rules, layers in
  the order first named, and what is in no layer after them all - which is
  how a later layer beats an earlier one, and plain CSS beats every layer }
procedure TInkStyler.RankLayers;
var Order: TStringList; I: Integer; R: TRule;

  procedure Visit(const AParent: string);
  var K, P: Integer; Name, Parent: string;
  begin
    for K := 0 to FLayerNames.Count - 1 do
    begin
      Name := FLayerNames[K];
      P := LastDelimiter('.', Name);
      if P > 0 then Parent := Copy(Name, 1, P - 1) else Parent := '';
      if Parent <> AParent then Continue;
      Visit(Name);
      Order.Add(Name);
    end;
  end;

begin
  Order := TStringList.Create;
  try
    Visit('');
    Order.Add('');
    for I := 0 to FRules.Count - 1 do
    begin
      R := TRule(FRules[I]);
      R.Rank := Order.IndexOf(R.Layer);
    end;
  finally Order.Free end;
end;

procedure TInkStyler.ParseSheet(const CSS: string; AOrigin: TInkStyleOrigin;
  const AMedia: array of Integer; const ABase: string; const AParentSel: string);
var S, Prelude, Body, Kw, Url, Fetched, ImpBase, Sel, Decls, Item, SavedLayer, Lay: string;
  P, Q, Depth, I, K, Start, BodyStart: Integer; Qc: Char;
  Inner: array of Integer;
  Parts: TStringArray;

  { the text of a block whose { is at P, P left past its } }
  function ReadBlock: string;
  var D: Integer; Q2: Char;
  begin
    D := 1; Inc(P); BodyStart := P;
    while (P <= System.Length(S)) and (D > 0) do
    begin
      case S[P] of
        '{': Inc(D);
        '}': Dec(D);
        '"', '''':
          begin
            Q2 := S[P]; Inc(P);
            while (P <= System.Length(S)) and (S[P] <> Q2) do
            begin
              if S[P] = '\' then Inc(P);
              Inc(P);
            end;
          end;
        '\': Inc(P);
      end;
      Inc(P);
    end;
    if D > 0 then Result := Copy(S, BodyStart, MaxInt)
    else Result := Copy(S, BodyStart, P - BodyStart - 1);
  end;

  procedure WithMedia(const AText: string);
  var N, J: Integer;
  begin
    N := System.Length(AMedia);
    SetLength(Inner, N + 1);
    for J := 0 to N - 1 do Inner[J] := AMedia[J];
    Inner[N] := MediaIndex(LowTrim(AText));
  end;

  procedure SameMedia;
  var J: Integer;
  begin
    SetLength(Inner, System.Length(AMedia));
    for J := 0 to High(AMedia) do Inner[J] := AMedia[J];
  end;

  { a selector inside another rule: & is the outer one, and without one the
    outer is its ancestor }
  function Nested(const ASel: string): string;
  var Parts2: TStringArray; J: Integer; T: string;
  begin
    if AParentSel = '' then Exit(ASel);
    Result := '';
    Parts2 := SplitTop(ASel, ',');
    for J := 0 to High(Parts2) do
    begin
      T := Trim(Parts2[J]);
      if Pos('&', T) > 0 then T := StringReplace(T, '&', ':is(' + AParentSel + ')', [rfReplaceAll])
      else T := ':is(' + AParentSel + ') ' + T;
      if Result <> '' then Result := Result + ', ';
      Result := Result + T;
    end;
  end;

begin
  S := StripComments(CSS);
  P := 1;
  while P <= System.Length(S) do
  begin
    while (P <= System.Length(S)) and (IsSpace(S[P]) or (S[P] = ';')) do Inc(P);
    if P > System.Length(S) then Break;
    if Copy(S, P, 4) = '<!--' then begin Inc(P, 4); Continue end;
    if Copy(S, P, 3) = '-->' then begin Inc(P, 3); Continue end;
    { the prelude, up to its block or its semicolon }
    Start := P; Depth := 0;
    while P <= System.Length(S) do
    begin
      case S[P] of
        '(', '[': Inc(Depth);
        ')', ']': if Depth > 0 then Dec(Depth);
        '"', '''':
          begin
            Qc := S[P]; Inc(P);
            while (P <= System.Length(S)) and (S[P] <> Qc) do
            begin
              if S[P] = '\' then Inc(P);
              Inc(P);
            end;
          end;
        '\': Inc(P);
      end;
      if (Depth = 0) and (P <= System.Length(S)) and (S[P] in ['{', ';', '}']) then Break;
      Inc(P);
    end;
    Prelude := Trim(Copy(S, Start, P - Start));
    if P > System.Length(S) then Break;
    if S[P] = '}' then begin Inc(P); Continue end;
    if S[P] = ';' then
    begin
      Inc(P);
      if LowerCase(Copy(Prelude, 1, 7)) = '@layer ' then
      begin
        { @layer a, b; - the order the layers stand in, named before use }
        Parts := SplitTop(Copy(Prelude, 8, MaxInt), ',');
        for K := 0 to High(Parts) do
          if Trim(Parts[K]) <> '' then SubLayer(Parts[K]);
        Continue;
      end;
      if LowerCase(Copy(Prelude, 1, 7)) = '@import' then
      begin
        Item := Trim(Copy(Prelude, 8, MaxInt));
        Url := '';
        if LowerCase(Copy(Item, 1, 4)) = 'url(' then
        begin
          Q := Pos(')', Item);
          Url := Trim(Copy(Item, 5, Q - 5)); Item := Trim(Copy(Item, Q + 1, MaxInt));
        end
        else if (Item <> '') and (Item[1] in ['"', '''']) then
        begin
          Q := PosEx(Item[1], Item, 2);
          Url := Copy(Item, 1, Q); Item := Trim(Copy(Item, Q + 1, MaxInt));
        end;
        if (Url <> '') and (Url[1] in ['"', '''']) then Url := Copy(Url, 2, System.Length(Url) - 2);
        if not ResolveRelativeURI(ABase, Url, ImpBase) then ImpBase := Url;
        { layer or layer(name) puts the whole sheet in a layer }
        Lay := #0;
        if LowerCase(Copy(Item, 1, 6)) = 'layer(' then
        begin
          Q := 7; Lay := Trim(ArgumentText(Item, Q));
          Item := Trim(Copy(Item, Q, MaxInt));
        end
        else if (LowerCase(Copy(Item, 1, 5)) = 'layer') and
          ((System.Length(Item) = 5) or IsSpace(Item[6])) then
        begin
          Lay := ''; Item := Trim(Copy(Item, 6, MaxInt));
        end;
        if LowerCase(Copy(Item, 1, 9)) = 'supports(' then
        begin
          Q := 10; Kw := ArgumentText(Item, Q);
          if not Supports('(' + Kw + ')') then Continue;
          Item := Trim(Copy(Item, Q, MaxInt));
        end;
        if Assigned(OnFetch) and (FImportDepth < 8) then
        begin
          Fetched := OnFetch(ImpBase);
          if Fetched <> '' then
          begin
            if Item <> '' then WithMedia(Item) else SameMedia;
            Inc(FImportDepth);
            SavedLayer := FLayer;
            if Lay <> #0 then FLayer := SubLayer(Lay);
            try ParseSheet(Fetched, AOrigin, Inner, ImpBase)
            finally Dec(FImportDepth); FLayer := SavedLayer end;
          end;
        end;
      end;
      Continue;
    end;
    { a block }
    Body := ReadBlock;
    if (Prelude <> '') and (Prelude[1] = '@') then
    begin
      Q := 2;
      while (Q <= System.Length(Prelude)) and (Prelude[Q] in ['a'..'z', 'A'..'Z', '-']) do Inc(Q);
      Kw := LowerCase(Copy(Prelude, 2, Q - 2));
      Item := Trim(Copy(Prelude, Q, MaxInt));
      case Kw of
        'media':
          begin
            WithMedia(Item);
            ParseSheet(Body, AOrigin, Inner, ABase, AParentSel);
          end;
        'supports':
          if Supports(Item) then
          begin
            SameMedia;
            ParseSheet(Body, AOrigin, Inner, ABase, AParentSel);
          end;
        'layer':
          begin
            SameMedia;
            SavedLayer := FLayer;
            FLayer := SubLayer(Item);
            try ParseSheet(Body, AOrigin, Inner, ABase, AParentSel)
            finally FLayer := SavedLayer end;
          end;
        'scope':
          begin
            SameMedia;
            ParseSheet(Body, AOrigin, Inner, ABase, AParentSel);
          end;
        'property':
          if Copy(Item, 1, 2) = '--' then
          begin
            { a registered custom property: its starting value, and
              whether a child takes its parent's }
            Kw := '';
            Url := 'true';
            Parts := SplitTop(Body, ';');
            for K := 0 to High(Parts) do
            begin
              Q := Pos(':', Parts[K]);
              if Q = 0 then Continue;
              Decls := LowTrim(Copy(Parts[K], 1, Q - 1));
              if Decls = 'initial-value' then Kw := Trim(Copy(Parts[K], Q + 1, MaxInt))
              else if Decls = 'inherits' then Url := LowTrim(Copy(Parts[K], Q + 1, MaxInt));
            end;
            Q := FRegistered.IndexOfName(Item);
            if Q < 0 then Q := FRegistered.Add(Item + '=' + Kw)
            else FRegistered[Q] := Item + '=' + Kw;
            FRegistered.Objects[Q] := TObject(PtrInt(Ord(Url <> 'false')));
          end;
      end;
      Continue;
    end;
    if Prelude = '' then Continue;
    Sel := Nested(Prelude);
    { declarations, and rules nested in them }
    Decls := '';
    Parts := nil;
    K := 1; Start := 1; Depth := 0;
    while K <= System.Length(Body) do
    begin
      case Body[K] of
        '(', '[': Inc(Depth);
        ')', ']': if Depth > 0 then Dec(Depth);
        '"', '''':
          begin
            Qc := Body[K]; Inc(K);
            while (K <= System.Length(Body)) and (Body[K] <> Qc) do
            begin
              if Body[K] = '\' then Inc(K);
              Inc(K);
            end;
          end;
        ';': if Depth = 0 then
             begin
               Decls := Decls + Copy(Body, Start, K - Start + 1);
               Start := K + 1;
             end;
        '{':
          if Depth = 0 then
          begin
            { a nested rule: its prelude is what came since the last ; }
            Item := Trim(Copy(Body, Start, K - Start));
            Q := K; Depth := 1; Inc(K);
            while (K <= System.Length(Body)) and (Depth > 0) do
            begin
              if Body[K] = '{' then Inc(Depth) else if Body[K] = '}' then Dec(Depth);
              Inc(K);
            end;
            Depth := 0;
            if (Item <> '') and (Item[1] = '@') then
              ParseSheet('@' + Copy(Item, 2, MaxInt) + '{' + Sel + '{' +
                Copy(Body, Q + 1, K - Q - 2) + '}}', AOrigin, AMedia, ABase)
            else
              ParseSheet(Item + '{' + Copy(Body, Q + 1, K - Q - 2) + '}', AOrigin, AMedia, ABase, Sel);
            Start := K;
            Continue;
          end;
      end;
      Inc(K);
    end;
    Decls := Decls + Copy(Body, Start, MaxInt);
    AddRule(Sel, Decls, AOrigin, AMedia, ABase);
  end;
end;

procedure TInkStyler.AddSheet(const CSS: string; const BaseURL: string);
begin
  Release;
  ParseSheet(CSS, isoAuthor, [], BaseURL);
end;

procedure TInkStyler.AddDocumentSheets(ADoc: TInkDocument; const BaseURL: string);
var N: TInkNode; Base, Href, Abs_, Text: string; MediaAttr: string; M: array of Integer;
begin
  Base := BaseURL;
  N := ADoc.NextInTree(ADoc);
  while N <> nil do
  begin
    { what a <template> holds is inert - a shadow root's sheet styles only
      its own component }
    if N.IsElement('template') then
    begin
      while (N <> nil) and (N.NextSibling = nil) and (N <> ADoc) do N := N.Parent;
      if (N = nil) or (N = ADoc) then Break;
      N := N.NextSibling;
      Continue;
    end;
    if N.Kind = inkElement then
    begin
      if (N.Name = 'base') and N.HasAttribute('href') then
      begin
        if ResolveRelativeURI(BaseURL, N.GetAttribute('href'), Abs_) then Base := Abs_;
      end
      else if (N.Name = 'style') and (N.Namespace = insHTML) then
      begin
        MediaAttr := LowTrim(N.GetAttribute('media'));
        if (MediaAttr = '') or (MediaAttr = 'all') then
          ParseSheet(N.TextContent, isoAuthor, [], Base)
        else
        begin
          SetLength(M, 1); M[0] := MediaIndex(MediaAttr);
          ParseSheet(N.TextContent, isoAuthor, M, Base);
        end;
      end
      else if (N.Name = 'link') and Assigned(OnFetch) and
        (Pos(' stylesheet ', ' ' + LowerCase(N.GetAttribute('rel')) + ' ') > 0) and
        (Pos('alternate', LowerCase(N.GetAttribute('rel'))) = 0) and
        not N.HasAttribute('disabled') then
      begin
        Href := N.GetAttribute('href');
        if not ResolveRelativeURI(Base, Href, Abs_) then Abs_ := Href;
        Text := OnFetch(Abs_);
        if Text <> '' then
        begin
          MediaAttr := LowTrim(N.GetAttribute('media'));
          if (MediaAttr = '') or (MediaAttr = 'all') then ParseSheet(Text, isoAuthor, [], Abs_)
          else
          begin
            SetLength(M, 1); M[0] := MediaIndex(MediaAttr);
            ParseSheet(Text, isoAuthor, M, Abs_);
          end;
        end;
      end;
    end;
    N := N.NextInTree(ADoc);
  end;
  Release;
end;

{ ---------------------------------------------------------------- @media }

function MediaFeature(const AFeature: string; const M: TInkMedia): Boolean;
var F, Name, V, Op: string; Colon, K: Integer; Want, Have: Double; Ctx: TLengthContext;

  function Len(const S: string; out D: Double): Boolean;
  begin
    Ctx.Font := 16; Ctx.Root := 16; Ctx.VW := M.Width; Ctx.VH := M.Height; Ctx.Percent := 0;
    Result := EvalLength(S, Ctx, D);
  end;

  function Compare(const AName, AOp, AValue: string; Reversed: Boolean): Boolean;
  var X, Y: Double; O: string;
  begin
    O := AOp;
    if Reversed then
      case O of
        '<': O := '>'; '>': O := '<'; '<=': O := '>='; '>=': O := '<=';
      end;
    if (AName = 'width') then X := M.Width
    else if AName = 'height' then X := M.Height
    else if AName = 'aspect-ratio' then X := M.Width / Max(1, M.Height)
    else if AName = 'resolution' then X := 1
    else Exit(False);
    if AName = 'aspect-ratio' then
    begin
      K := Pos('/', AValue);
      if K > 0 then Y := StrToFloatDef(Trim(Copy(AValue, 1, K - 1)), 1, CSSFormat) /
        Max(0.001, StrToFloatDef(Trim(Copy(AValue, K + 1, MaxInt)), 1, CSSFormat))
      else Y := StrToFloatDef(AValue, 1, CSSFormat);
    end
    else if AName = 'resolution' then
      Y := StrToFloatDef(StringReplace(StringReplace(AValue, 'dppx', '', []), 'x', '', []), 1,
        CSSFormat)
    else if not Len(AValue, Y) then Exit(False);
    case O of
      '<': Result := X < Y;
      '<=': Result := X <= Y;
      '>': Result := X > Y;
      '>=': Result := X >= Y;
      '=': Result := Abs(X - Y) < 0.01;
    else
      Result := False;
    end;
  end;

  { the range syntax: width >= 600px, 400px < width <= 800px, a calc() on
    either side }
  function Range(const S: string): Boolean;
  var Toks: array of string; I, Depth, Start: Integer; T: string;
    procedure Push(const AText: string);
    begin
      if Trim(AText) = '' then Exit;
      SetLength(Toks, System.Length(Toks) + 1); Toks[High(Toks)] := Trim(AText);
    end;
  begin
    Toks := nil; I := 1; Depth := 0; Start := 1;
    while I <= System.Length(S) do
    begin
      if S[I] = '(' then Inc(Depth) else if S[I] = ')' then Dec(Depth)
      else if (Depth = 0) and (S[I] in ['<', '>', '=']) then
      begin
        Push(Copy(S, Start, I - Start));
        T := S[I];
        if (I < System.Length(S)) and (S[I + 1] = '=') then begin T := T + '='; Inc(I) end;
        Push(T);
        Start := I + 1;
      end;
      Inc(I);
    end;
    Push(Copy(S, Start, MaxInt));
    if System.Length(Toks) = 3 then
    begin
      if Toks[0][1] in ['a'..'z'] then Exit(Compare(Toks[0], Toks[1], Toks[2], False))
      else Exit(Compare(Toks[2], Toks[1], Toks[0], True));
    end;
    if System.Length(Toks) = 5 then
      Exit(Compare(Toks[2], Toks[1], Toks[0], True) and Compare(Toks[2], Toks[3], Toks[4], False));
    Result := False;
  end;

begin
  F := LowTrim(AFeature);
  if (Pos('<', F) > 0) or (Pos('>', F) > 0) or ((Pos('=', F) > 0) and (Pos(':', F) = 0)) then
    Exit(Range(F));
  Colon := Pos(':', F);
  if Colon = 0 then
  begin
    Name := F; V := '';
  end
  else
  begin
    Name := Trim(Copy(F, 1, Colon - 1)); V := Trim(Copy(F, Colon + 1, MaxInt));
  end;
  Op := '=';
  if Copy(Name, 1, 4) = 'min-' then begin Op := '>='; Delete(Name, 1, 4) end
  else if Copy(Name, 1, 4) = 'max-' then begin Op := '<='; Delete(Name, 1, 4) end;
  if Copy(Name, 1, 8) = '-webkit-' then Delete(Name, 1, 8);
  if (Copy(Name, 1, 4) = 'min-') then begin Op := '>='; Delete(Name, 1, 4) end
  else if (Copy(Name, 1, 4) = 'max-') then begin Op := '<='; Delete(Name, 1, 4) end;
  case Name of
    'width', 'height', 'aspect-ratio', 'resolution':
      begin
        if V = '' then Exit((Name <> 'width') or (M.Width > 0));
        Exit(Compare(Name, Op, V, False));
      end;
    'device-pixel-ratio':
      begin
        Want := StrToFloatDef(V, 1, CSSFormat); Have := 1;
        if Op = '>=' then Exit(Have >= Want);
        if Op = '<=' then Exit(Have <= Want);
        Exit(Have = Want);
      end;
    'device-width': Exit(Compare('width', Op, V, False));
    'device-height': Exit(Compare('height', Op, V, False));
    'orientation':
      if V = 'landscape' then Exit(M.Width >= M.Height) else Exit(M.Height > M.Width);
    'prefers-color-scheme':
      if V = 'dark' then Exit(M.Dark) else Exit(not M.Dark);
    'prefers-reduced-motion', 'prefers-reduced-transparency', 'prefers-reduced-data',
    'prefers-contrast':
      Exit((V = 'no-preference') or (V = ''));
    'hover', 'any-hover': Exit((V = '') or (V = 'hover'));
    'pointer', 'any-pointer': Exit((V = '') or (V = 'fine'));
    'color': Exit(True);
    'color-gamut': Exit(V = 'srgb');
    'monochrome', 'grid': Exit((V = '0') and (Op <> '>='));
    'scripting': Exit(V = 'none');
    '-ink-quirks': Exit(M.Quirks);
    'display-mode': Exit(V = 'browser');
    'forced-colors', 'inverted-colors': Exit(V = 'none');
    'dynamic-range', 'video-dynamic-range': Exit(V = 'standard');
    'update': Exit(V = 'fast');
    'overflow-block': Exit(V = 'scroll');
    'overflow-inline': Exit(V = 'scroll');
  end;
  Result := False;
end;

function MediaCondition(const ACond: string; const M: TInkMedia): Boolean; forward;

{ one query of a comma list: [not|only] type [and condition], or a condition }
function MediaQuery(const AQuery: string; const M: TInkMedia): Boolean;
var Q, T: string; Neg: Boolean; K: Integer;
begin
  Q := LowTrim(AQuery);
  if Q = '' then Exit(True);
  Neg := False;
  if Copy(Q, 1, 4) = 'not ' then
  begin
    Neg := True; Q := Trim(Copy(Q, 5, MaxInt));
  end
  else if Copy(Q, 1, 5) = 'only ' then Q := Trim(Copy(Q, 6, MaxInt));
  if Q[1] <> '(' then
  begin
    K := Pos(' ', Q);
    if K = 0 then begin T := Q; Q := '' end
    else begin T := Copy(Q, 1, K - 1); Q := Trim(Copy(Q, K + 1, MaxInt)) end;
    case T of
      'all': Result := True;
      'screen': Result := not M.Print;
      'print': Result := M.Print;
    else
      Result := False;
    end;
    if Result and (Q <> '') then
    begin
      if Copy(Q, 1, 4) = 'and ' then Result := MediaCondition(Copy(Q, 5, MaxInt), M)
      else Result := False;
    end;
  end
  else Result := MediaCondition(Q, M);
  if Neg then Result := not Result;
end;

function MediaCondition(const ACond: string; const M: TInkMedia): Boolean;
var C: string; P, Depth, Start: Integer; Parts: array of string; Ops: array of string; I: Integer;
begin
  C := Trim(ACond);
  if C = '' then Exit(True);
  if Copy(C, 1, 4) = 'not ' then Exit(not MediaCondition(Copy(C, 5, MaxInt), M));
  Parts := nil; Ops := nil; P := 1; Depth := 0; Start := 1;
  while P <= System.Length(C) do
  begin
    if C[P] = '(' then Inc(Depth) else if C[P] = ')' then Dec(Depth)
    else if (Depth = 0) and IsSpace(C[P]) then
    begin
      if Copy(C, P + 1, 4) = 'and ' then
      begin
        SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, P - Start);
        SetLength(Ops, System.Length(Ops) + 1); Ops[High(Ops)] := 'and';
        Inc(P, 4); Start := P + 1;
      end
      else if Copy(C, P + 1, 3) = 'or ' then
      begin
        SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, P - Start);
        SetLength(Ops, System.Length(Ops) + 1); Ops[High(Ops)] := 'or';
        Inc(P, 3); Start := P + 1;
      end;
    end;
    Inc(P);
  end;
  if System.Length(Parts) > 0 then
  begin
    SetLength(Parts, System.Length(Parts) + 1); Parts[High(Parts)] := Copy(C, Start, MaxInt);
    Result := MediaCondition(Parts[0], M);
    for I := 0 to High(Ops) do
      if Ops[I] = 'and' then Result := Result and MediaCondition(Parts[I + 1], M)
      else Result := Result or MediaCondition(Parts[I + 1], M);
    Exit;
  end;
  if (C[1] = '(') and (C[System.Length(C)] = ')') then
  begin
    C := Trim(Copy(C, 2, System.Length(C) - 2));
    if (C <> '') and ((C[1] = '(') or (Copy(C, 1, 4) = 'not ')) then Exit(MediaCondition(C, M));
    Exit(MediaFeature(C, M));
  end;
  Result := False;
end;

function MediaList(const AText: string; const M: TInkMedia): Boolean;
var Q: TStringArray; I: Integer;
begin
  Q := SplitTop(AText, ',');
  for I := 0 to High(Q) do
    if MediaQuery(Q[I], M) then Exit(True);
  Result := False;
end;

procedure TInkStyler.EvaluateMedia;
var I: Integer;
begin
  SetLength(FMediaOK, FMediaTexts.Count);
  for I := 0 to FMediaTexts.Count - 1 do FMediaOK[I] := MediaList(FMediaTexts[I], Media);
end;

{ ------------------------------------------------------------- computing }

procedure TInkStyler.Release(ATouchNodes: Boolean);
var I: Integer;
begin
  for I := 0 to FInfos.Count - 1 do
  begin
    if ATouchNodes and (PInfo(FInfos[I])^.Node <> nil) then PInfo(FInfos[I])^.Node.Info := nil;
    Dispose(PInfo(FInfos[I]));
  end;
  FInfos.Clear;
  FShare.Clear;
  FStyles.Clear;
  FRoot := nil;
end;

procedure TInkStyler.BuildInfos(ARoot: TInkNode);
var N, C: TInkNode; Info, CI: PInfo; Cls: string; P, Q, K, Count: Integer;
  Kids: array of PInfo; Names: TStringList; Idx: Integer;
begin
  Names := TStringList.Create;
  try
    Names.Sorted := True; Names.CaseSensitive := True;
    N := ARoot;
    while N <> nil do
    begin
      if N.Kind = inkElement then
      begin
        New(Info);
        Info^ := Default(TInfo);
        Info^.Node := N;
        if (N.Parent <> nil) and (N.Parent.Info <> nil) and (N.Parent.Kind = inkElement) then
          Info^.Parent := PInfo(N.Parent.Info);
        Info^.Id := N.GetAttribute('id');
        Cls := N.GetAttribute('class');
        P := 1; Count := 0;
        while P <= System.Length(Cls) do
        begin
          while (P <= System.Length(Cls)) and IsSpace(Cls[P]) do Inc(P);
          Q := P;
          while (Q <= System.Length(Cls)) and not IsSpace(Cls[Q]) do Inc(Q);
          if Q > P then
          begin
            SetLength(Info^.Classes, Count + 1); Info^.Classes[Count] := Copy(Cls, P, Q - P); Inc(Count);
          end;
          P := Q;
        end;
        N.Info := Info;
        FInfos.Add(Info);
      end;
      N := N.NextInTree(ARoot);
    end;
    { where each element stands among its siblings }
    for K := 0 to FInfos.Count - 1 do
    begin
      Info := PInfo(FInfos[K]);
      if Info^.Node.FirstChild = nil then Continue;
      Kids := nil; Names.Clear;
      C := Info^.Node.FirstChild;
      while C <> nil do
      begin
        if (C.Kind = inkElement) and (C.Info <> nil) then
        begin
          CI := PInfo(C.Info);
          SetLength(Kids, System.Length(Kids) + 1); Kids[High(Kids)] := CI;
          CI^.Index := System.Length(Kids);
          if Names.Find(C.Name, Idx) then
          begin
            Names.Objects[Idx] := TObject(PtrInt(Names.Objects[Idx]) + 1);
          end
          else Idx := Names.AddObject(C.Name, TObject(PtrInt(1)));
          CI^.TypeIndex := PtrInt(Names.Objects[Idx]);
        end;
        C := C.NextSibling;
      end;
      for Count := 0 to High(Kids) do
      begin
        Kids[Count]^.Count := System.Length(Kids);
        Names.Find(Kids[Count]^.Node.Name, Idx);
        Kids[Count]^.TypeCount := PtrInt(Names.Objects[Idx]);
      end;
    end;
    { the root's own position: it is the only element of the document }
    if (ARoot.Kind = inkDocument) or (ARoot.Parent = nil) then
      for K := 0 to FInfos.Count - 1 do
        if PInfo(FInfos[K])^.Index = 0 then
        begin
          PInfo(FInfos[K])^.Index := 1; PInfo(FInfos[K])^.Count := 1;
          PInfo(FInfos[K])^.TypeIndex := 1; PInfo(FInfos[K])^.TypeCount := 1;
        end;
  finally Names.Free end;
end;

type
  TMatched = record
    Rule: TRule;
    Spec: Cardinal;
  end;
  TMatchedArray = array of TMatched;

procedure Consider(const M: TMatcher; AList: TFPList; N: TInkNode; const AMediaOK: array of Boolean;
  var AOut: TMatchedArray; var ACount: Integer);
var I, K: Integer; Ref: TRef; Ok: Boolean;
begin
  if AList = nil then Exit;
  for I := 0 to AList.Count - 1 do
  begin
    Ref := TRef(AList[I]);
    Ok := True;
    for K := 0 to High(Ref.Rule.Media) do
      if not AMediaOK[Ref.Rule.Media[K]] then begin Ok := False; Break end;
    if not Ok then Continue;
    if not MatchSel(M, Ref.Sel, High(Ref.Sel.C), N) then Continue;
    { the same rule matched by another of its selectors: the stronger counts }
    for K := 0 to ACount - 1 do
      if AOut[K].Rule = Ref.Rule then
      begin
        if Ref.Sel.Spec > AOut[K].Spec then AOut[K].Spec := Ref.Sel.Spec;
        Ok := False; Break;
      end;
    if not Ok then Continue;
    if ACount = System.Length(AOut) then SetLength(AOut, ACount * 2 + 8);
    AOut[ACount].Rule := Ref.Rule; AOut[ACount].Spec := Ref.Sel.Spec;
    Inc(ACount);
  end;
end;

{ whether A comes after B in the cascade - wins over it: its layer, then
  specificity, then where written.  For !important the layers turn round. }
function Later(const A, B: TMatched; AImportant: Boolean): Boolean; inline;
begin
  if A.Rule.Rank <> B.Rule.Rank then
  begin
    if AImportant then Exit(A.Rule.Rank < B.Rule.Rank);
    Exit(A.Rule.Rank > B.Rule.Rank);
  end;
  if A.Spec <> B.Spec then Exit(A.Spec > B.Spec);
  Result := A.Rule.Order > B.Rule.Order;
end;

{ weakest first, in the cascade's order }
procedure SortMatched(var A: TMatchedArray; ACount: Integer; AImportant: Boolean = False);
var I, J: Integer; T: TMatched;
begin
  for I := 1 to ACount - 1 do
  begin
    T := A[I]; J := I - 1;
    while (J >= 0) and Later(A[J], T, AImportant) do
    begin
      A[J + 1] := A[J]; Dec(J);
    end;
    A[J + 1] := T;
  end;
end;

{ the old presentational attributes - bgcolor, <font>, align, width,
  cellpadding - as the declarations a browser makes of them }
function LegacyColor(const V: string): string;
var C: TInkRGBA; T: string; I: Integer;
begin
  T := Trim(V);
  if InkParseColor(T, C) then Exit(T);
  if (T <> '') and (T[1] <> '#') then
  begin
    for I := 1 to System.Length(T) do
      if not (T[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit('');
    if (System.Length(T) = 3) or (System.Length(T) = 6) then Exit('#' + T);
  end;
  Result := '';
end;

function LegacyLength(const V: string): string;
var T: string; I: Integer;
begin
  T := Trim(V);
  I := 1;
  while (I <= System.Length(T)) and (T[I] in ['0'..'9', '.']) do Inc(I);
  if I = 1 then Exit('');
  if (I <= System.Length(T)) and (T[I] = '%') then Exit(Copy(T, 1, I));
  Result := Copy(T, 1, I - 1) + 'px';
end;

function HintText(N: TInkNode): string;
var T, V, A: string; P: TInkNode; K: Integer;
  procedure Add(const S: string);
  begin
    Result := Result + S + ';';
  end;
  function Has(const AName: string): Boolean;
  begin
    Result := N.HasAttribute(AName);
  end;
begin
  Result := '';
  if N.Namespace <> insHTML then Exit;
  T := N.Name;
  if Has('bgcolor') and (LegacyColor(N.GetAttribute('bgcolor')) <> '') and
    ((T = 'body') or (T = 'table') or (T = 'tr') or (T = 'td') or (T = 'th') or
     (T = 'thead') or (T = 'tbody') or (T = 'tfoot')) then
    Add('background-color:' + LegacyColor(N.GetAttribute('bgcolor')));
  if Has('background') and ((T = 'body') or (T = 'table') or (T = 'td') or (T = 'th')) then
    Add('background-image:url("' + N.GetAttribute('background') + '")');
  if T = 'body' then
  begin
    if LegacyColor(N.GetAttribute('text')) <> '' then Add('color:' + LegacyColor(N.GetAttribute('text')));
    V := LegacyLength(N.GetAttribute('marginwidth'));
    if V = '' then V := LegacyLength(N.GetAttribute('leftmargin'));
    if V <> '' then Add('margin-left:' + V + ';margin-right:' + V);
    V := LegacyLength(N.GetAttribute('marginheight'));
    if V = '' then V := LegacyLength(N.GetAttribute('topmargin'));
    if V <> '' then Add('margin-top:' + V + ';margin-bottom:' + V);
  end;
  if T = 'font' then
  begin
    if LegacyColor(N.GetAttribute('color')) <> '' then Add('color:' + LegacyColor(N.GetAttribute('color')));
    if Has('face') then Add('font-family:' + N.GetAttribute('face'));
    if Has('size') then
    begin
      V := Trim(N.GetAttribute('size')); K := 3;
      if (V <> '') and (V[1] in ['+', '-']) then K := 3 + StrToIntDef(V, 0)
      else K := StrToIntDef(V, 3);
      case EnsureRange(K, 1, 7) of
        1: Add('font-size:x-small');
        2: Add('font-size:small');
        3: Add('font-size:medium');
        4: Add('font-size:large');
        5: Add('font-size:x-large');
        6: Add('font-size:xx-large');
        7: Add('font-size:xxx-large');
      end;
    end;
  end;
  A := LowerCase(Trim(N.GetAttribute('align')));
  if A <> '' then
  begin
    if (T = 'p') or (T = 'div') or (T = 'h1') or (T = 'h2') or (T = 'h3') or (T = 'h4') or
      (T = 'h5') or (T = 'h6') or (T = 'caption') or (T = 'legend') or (T = 'td') or
      (T = 'th') or (T = 'tr') or (T = 'thead') or (T = 'tbody') or (T = 'tfoot') then
    begin
      if (A = 'center') or (A = 'middle') then Add('text-align:center')
      else if (A = 'left') or (A = 'right') or (A = 'justify') then Add('text-align:' + A);
    end
    else if (T = 'table') or (T = 'hr') then
    begin
      if A = 'center' then Add('margin-left:auto;margin-right:auto')
      else if (A = 'left') and (T = 'table') then Add('float:left')
      else if (A = 'right') and (T = 'table') then Add('float:right')
      else if A = 'left' then Add('margin-right:auto;margin-left:0')
      else if A = 'right' then Add('margin-left:auto;margin-right:0');
    end
    else if (T = 'img') or (T = 'object') or (T = 'embed') or (T = 'iframe') or (T = 'input') then
    begin
      if (A = 'left') or (A = 'right') then Add('float:' + A)
      else if (A = 'middle') or (A = 'absmiddle') or (A = 'center') then Add('vertical-align:middle')
      else if (A = 'top') or (A = 'texttop') then Add('vertical-align:top')
      else if (A = 'bottom') or (A = 'baseline') or (A = 'absbottom') then Add('vertical-align:baseline');
    end;
  end;
  V := LowerCase(Trim(N.GetAttribute('valign')));
  if (V <> '') and ((T = 'td') or (T = 'th') or (T = 'tr') or (T = 'thead') or (T = 'tbody') or (T = 'tfoot') or (T = 'col')) then
    if (V = 'top') or (V = 'middle') or (V = 'bottom') or (V = 'baseline') then Add('vertical-align:' + V);
  if (T = 'table') or (T = 'td') or (T = 'th') or (T = 'img') or (T = 'col') or (T = 'hr') or
    (T = 'iframe') or (T = 'embed') or (T = 'object') or (T = 'video') or (T = 'canvas') or
    (T = 'pre') or (T = 'colgroup') then
  begin
    V := LegacyLength(N.GetAttribute('width'));
    if (V <> '') and (V <> '0px') then Add('width:' + V);
  end;
  if (T = 'table') or (T = 'td') or (T = 'th') or (T = 'tr') or (T = 'img') or (T = 'iframe') or
    (T = 'embed') or (T = 'object') or (T = 'video') or (T = 'canvas') then
  begin
    V := LegacyLength(N.GetAttribute('height'));
    if (V <> '') and (V <> '0px') then Add('height:' + V);
  end;
  if ((T = 'td') or (T = 'th')) and Has('nowrap') then Add('white-space:nowrap');
  if T = 'table' then
  begin
    if Has('border') then
    begin
      V := LegacyLength(N.GetAttribute('border'));
      if (V = '') and (Trim(N.GetAttribute('border')) = '') then V := '1px';
      if (V <> '') and (V <> '0px') then Add('border:' + V + ' outset gray');
    end;
    if Has('cellspacing') and (LegacyLength(N.GetAttribute('cellspacing')) <> '') then
      Add('border-spacing:' + LegacyLength(N.GetAttribute('cellspacing')));
    if LegacyColor(N.GetAttribute('bordercolor')) <> '' then
      Add('border-color:' + LegacyColor(N.GetAttribute('bordercolor')));
  end;
  if (T = 'td') or (T = 'th') then
  begin
    { the table's cellpadding and border reach its cells }
    P := N.Parent;
    while (P <> nil) and (P.Name <> 'table') do P := P.Parent;
    if P <> nil then
    begin
      if P.HasAttribute('cellpadding') and (LegacyLength(P.GetAttribute('cellpadding')) <> '') then
        Add('padding:' + LegacyLength(P.GetAttribute('cellpadding')));
      if P.HasAttribute('border') and (LegacyLength(P.GetAttribute('border')) <> '0px') then
        Add('border:1px inset gray');
      if P.HasAttribute('rules') and (LowTrim(P.GetAttribute('rules')) = 'all') then
        Add('border:1px solid gray');
    end;
  end;
  if T = 'img' then
  begin
    V := LegacyLength(N.GetAttribute('border'));
    if V <> '' then Add('border:' + V + ' solid');
    V := LegacyLength(N.GetAttribute('hspace'));
    if V <> '' then Add('margin-left:' + V + ';margin-right:' + V);
    V := LegacyLength(N.GetAttribute('vspace'));
    if V <> '' then Add('margin-top:' + V + ';margin-bottom:' + V);
  end;
  if T = 'hr' then
  begin
    V := LegacyLength(N.GetAttribute('size'));
    if V <> '' then Add('height:' + V);
    if LegacyColor(N.GetAttribute('color')) <> '' then
      Add('color:' + LegacyColor(N.GetAttribute('color')) + ';background-color:' +
        LegacyColor(N.GetAttribute('color')) + ';border-style:solid');
    if Has('noshade') then Add('border-style:solid;background-color:gray;color:gray');
  end;
  if ((T = 'ol') or (T = 'ul') or (T = 'li')) and Has('type') then
  begin
    V := Trim(N.GetAttribute('type'));
    case V of
      '1': Add('list-style-type:decimal');
      'a': Add('list-style-type:lower-alpha');
      'A': Add('list-style-type:upper-alpha');
      'i': Add('list-style-type:lower-roman');
      'I': Add('list-style-type:upper-roman');
    else
      V := LowerCase(V);
      if (V = 'disc') or (V = 'circle') or (V = 'square') or (V = 'none') then Add('list-style-type:' + V);
    end;
  end;
  if Has('dir') and ((LowTrim(N.GetAttribute('dir')) = 'rtl') or (LowTrim(N.GetAttribute('dir')) = 'ltr')) then
    Add('direction:' + LowTrim(N.GetAttribute('dir')));
end;

function TInkStyler.HintDecls(N: TInkNode): TObject;
var T: string; H: THints;
begin
  T := HintText(N);
  if T = '' then Exit(nil);
  H := THints(FHintRules.Items[T]);
  if H = nil then
  begin
    H := THints.Create;
    H.Decls := ParseDecls(T, '');
    FHintRules.Add(T, H);
  end;
  Result := H;
end;

{ ---------------------------------------------------- computed values }

const
  FontSizeKeywords: array[0..7] of record N: string; Px: Double; end = (
    (N:'xx-small';Px:9),(N:'x-small';Px:10),(N:'small';Px:13),(N:'medium';Px:16),
    (N:'large';Px:18),(N:'x-large';Px:24),(N:'xx-large';Px:32),(N:'xxx-large';Px:48));

function FormatPx(V: Double): string;
begin
  Result := FloatToStrF(V, ffGeneral, 7, 0, CSSFormat) + 'px';
end;

{ var() replaced by what the custom properties say, or its fallback; False
  when neither - the declaration is then invalid.  A custom property set to
  nothing at all is set: it puts nothing in, which old light/dark toggles
  rely on. }
function SubstituteOK(const V: string; ACustom: TStringList; ADepth: Integer; out AResult: string): Boolean;
var P, Q, Depth, Comma, I, Rounds: Integer; Name, Fallback, Rep, Done: string; HasFallback, Found: Boolean;
begin
  AResult := V; Result := False;
  if ADepth > 16 then Exit;
  Rounds := 0;
  P := Pos('var(', LowerCase(AResult));
  while P > 0 do
  begin
    Q := P + 4; Depth := 1; Comma := 0;
    while (Q <= System.Length(AResult)) and (Depth > 0) do
    begin
      if AResult[Q] = '(' then Inc(Depth)
      else if AResult[Q] = ')' then Dec(Depth)
      else if (AResult[Q] = ',') and (Depth = 1) and (Comma = 0) then Comma := Q;
      Inc(Q);
    end;
    if Depth > 0 then Exit;
    HasFallback := Comma > 0;
    if HasFallback then
    begin
      Name := Trim(Copy(AResult, P + 4, Comma - P - 4));
      Fallback := Trim(Copy(AResult, Comma + 1, Q - Comma - 2));
    end
    else Name := Trim(Copy(AResult, P + 4, Q - P - 5));
    Found := False; Rep := '';
    if ACustom <> nil then
    begin
      I := ACustom.IndexOfName(Name);
      if I >= 0 then begin Rep := ACustom.ValueFromIndex[I]; Found := LowTrim(Rep) <> 'initial' end;
    end;
    if Found then
    begin
      Found := SubstituteOK(Rep, ACustom, ADepth + 1, Done);
      Rep := Done;
    end;
    if not Found then
    begin
      if not HasFallback then Exit;
      if not SubstituteOK(Fallback, ACustom, ADepth + 1, Done) then Exit;
      Rep := Done;
    end;
    AResult := Copy(AResult, 1, P - 1) + Rep + Copy(AResult, Q, MaxInt);
    Inc(Rounds);
    if Rounds > 256 then Exit;
    P := Pos('var(', LowerCase(AResult));
  end;
  Result := True;
end;

function Substitute(const V: string; ACustom: TStringList; ADepth: Integer): string;
begin
  if not SubstituteOK(V, ACustom, ADepth, Result) then Result := '';
end;

{ whether a value has a length or a percentage in it, or only numbers }
function HasUnit(const S: string): Boolean;
var I: Integer;
begin
  for I := 1 to System.Length(S) - 1 do
    if (S[I] in ['0'..'9', '.']) and (S[I + 1] in ['a'..'z', 'A'..'Z', '%']) then Exit(True);
  Result := False;
end;

function Blockify(const D: string): string;
begin
  case D of
    'inline', 'inline-block', 'run-in', 'table-row-group', 'table-column',
    'table-column-group', 'table-header-group', 'table-footer-group', 'table-row',
    'table-cell', 'table-caption': Result := 'block';
    'inline-table': Result := 'table';
    'inline-flex': Result := 'flex';
    'inline-grid': Result := 'grid';
  else
    Result := D;
  end;
end;

function TInkStyler.Resolve(const ASpec: array of string; ASpecCustom: TStringList;
  AParent: TInkStyle; AIsRoot: Boolean): TInkStyle;
var I, K: Integer; V, L, Name: string; ParentFont, F: Double; Ctx: TLengthContext;
  Parts: TDeclArray; Inh: Boolean;

  function InheritOf(AIndex: Integer): string;
  begin
    if AParent <> nil then Result := AParent.FValues[AIndex] else Result := PropDefs[AIndex].Init;
  end;

begin
  Result := TInkStyle.Create;
  Result.FStyler := Self;
  SetLength(Result.FValues, PropCount);
  { custom properties first: everything else may use them }
  if ((ASpecCustom = nil) or (ASpecCustom.Count = 0)) and (FRegistered.Count = 0) then
  begin
    if AParent <> nil then Result.FCustom := AParent.FCustom;
  end
  else
  begin
    Result.FCustom := TStringList.Create;
    Result.FOwnsCustom := True;
    if (AParent <> nil) and (AParent.FCustom <> nil) then Result.FCustom.Assign(AParent.FCustom);
    { a registered property that does not inherit starts afresh }
    for I := 0 to FRegistered.Count - 1 do
      if PtrInt(FRegistered.Objects[I]) = 0 then
      begin
        K := Result.FCustom.IndexOfName(FRegistered.Names[I]);
        if K >= 0 then Result.FCustom.Delete(K);
      end;
    if ASpecCustom <> nil then
    for I := 0 to ASpecCustom.Count - 1 do
    begin
      Name := ASpecCustom.Names[I];
      V := ASpecCustom.ValueFromIndex[I];
      Inh := True;
      if IsCSSWide(V) then
      begin
        { inherit keeps the parent's, which is there already; the rest unset it }
        Inh := LowTrim(V) = 'inherit';
        if Inh then Continue;
      end;
      K := Result.FCustom.IndexOfName(Name);
      if not Inh then
      begin
        if K >= 0 then Result.FCustom.Delete(K);
      end
      else if K >= 0 then Result.FCustom[K] := Name + '=' + V
      else Result.FCustom.Add(Name + '=' + V);
    end;
    { and one that is set nowhere has its registered starting value }
    for I := 0 to FRegistered.Count - 1 do
      if (FRegistered.ValueFromIndex[I] <> '') and (Result.FCustom.IndexOfName(FRegistered.Names[I]) < 0) then
        Result.FCustom.Add(FRegistered[I]);
    { and their own var()s }
    for I := Result.FCustom.Count - 1 downto 0 do
      if Pos('var(', LowerCase(Result.FCustom.ValueFromIndex[I])) > 0 then
      begin
        if SubstituteOK(Result.FCustom.ValueFromIndex[I], Result.FCustom, 0, V) then
          Result.FCustom[I] := Result.FCustom.Names[I] + '=' + V
        else Result.FCustom[I] := Result.FCustom.Names[I] + '=initial';
      end;
  end;
  { the specified values, var() done and shorthands that waited taken apart }
  Parts := nil;
  for I := 0 to PropCount - 1 do Result.FValues[I] := ASpec[I];
  for I := 0 to PropCount - 1 do
  begin
    V := Result.FValues[I];
    if V = '' then Continue;
    if V[1] = #1 then
    begin
      { a shorthand with var(): the part this longhand is }
      K := Pos(#1, Copy(V, 2, MaxInt));
      Name := Copy(V, 2, K - 1);
      L := Substitute(Copy(V, K + 2, MaxInt), Result.FCustom, 0);
      V := 'unset';
      if L <> '' then
      begin
        Parts := nil;
        Expand(Parts, Name, L, False);
        for K := 0 to High(Parts) do
          if Parts[K].Prop = I then V := Parts[K].Value;
      end;
    end
    else if Pos('var(', LowerCase(V)) > 0 then
    begin
      V := Substitute(V, Result.FCustom, 0);
      if V = '' then V := 'unset';
    end;
    Result.FValues[I] := V;
  end;
  { font size first: ems everywhere else are of it }
  if AParent <> nil then ParentFont := AParent.FontSize else ParentFont := 16;
  if AParent <> nil then Result.RootFontSize := AParent.RootFontSize else Result.RootFontSize := 16;
  V := LowTrim(Result.FValues[PFontSize]);
  F := ParentFont;
  if (V = '') or (V = 'inherit') or (V = 'unset') or (V = 'revert') then F := ParentFont
  else if V = 'initial' then F := 16
  else if V = 'smaller' then F := ParentFont / 1.2
  else if V = 'larger' then F := ParentFont * 1.2
  else
  begin
    K := -1;
    for I := 0 to High(FontSizeKeywords) do
      if FontSizeKeywords[I].N = V then K := I;
    if K >= 0 then F := FontSizeKeywords[K].Px
    else
    begin
      Ctx.Font := ParentFont; Ctx.Root := Result.RootFontSize; Ctx.Percent := ParentFont;
      Ctx.VW := Media.Width; Ctx.VH := Media.Height;
      if AIsRoot then Ctx.Root := ParentFont;
      if not EvalLength(V, Ctx, F) then F := ParentFont;
    end;
  end;
  Result.FontSize := Max(0, F);
  if AIsRoot then Result.RootFontSize := Result.FontSize;
  Result.FValues[PFontSize] := FormatPx(Result.FontSize);
  Ctx.Font := Result.FontSize; Ctx.Root := Result.RootFontSize;
  Ctx.VW := Media.Width; Ctx.VH := Media.Height; Ctx.Percent := 0;
  { every other property: specified, inherited or initial }
  for I := 0 to PropCount - 1 do
  begin
    if I = PFontSize then Continue;
    V := Result.FValues[I];
    Inh := PropDefs[I].Inh;
    L := LowTrim(V);
    if V = '' then
    begin
      if Inh then V := InheritOf(I) else V := PropDefs[I].Init;
    end
    else if L = 'inherit' then V := InheritOf(I)
    else if L = 'initial' then V := PropDefs[I].Init
    else if (L = 'unset') or (L = 'revert') or (L = 'revert-layer') then
    begin
      if Inh then V := InheritOf(I) else V := PropDefs[I].Init;
    end
    else if (I = PColor) and (L = 'currentcolor') then V := InheritOf(I)
    else if I = PFontWeight then
    begin
      if AParent <> nil then F := StrToFloatDef(AParent.FValues[I], 400, CSSFormat) else F := 400;
      case L of
        'normal': V := '400';
        'bold': V := '700';
        'bolder': if F < 350 then V := '400' else if F < 550 then V := '700' else V := '900';
        'lighter': if F < 550 then V := '100' else if F < 750 then V := '400' else V := '700';
      end;
    end
    else if I = PLineHeight then
    begin
      { a length with ems is fixed here; a plain number inherits as a factor }
      if (L <> 'normal') and (Pos('%', L) + Pos('em', L) + Pos('calc', L) + Pos('ex', L) + Pos('ch', L) > 0) then
      begin
        Ctx.Percent := Result.FontSize;
        if EvalLength(L, Ctx, F) then
        begin
          if HasUnit(L) then V := FormatPx(F)
          else V := FloatToStrF(F, ffGeneral, 7, 0, CSSFormat);
        end;
        Ctx.Percent := 0;
      end;
    end
    else if Inh and ((PropDefs[I].N = 'letter-spacing') or (PropDefs[I].N = 'word-spacing') or
      (PropDefs[I].N = 'text-indent') or (PropDefs[I].N = 'border-spacing')) and
      (Pos('%', L) = 0) and (L <> 'normal') then
    begin
      { an inherited length is inherited as pixels, not as ems to redo }
      Parts := nil;
      if (Pos('em', L) > 0) or (Pos('ex', L) > 0) or (Pos('ch', L) > 0) or (Pos('calc', L) > 0) or
        (Pos('vw', L) > 0) or (Pos('vh', L) > 0) then
      begin
        if Pos(' ', L) = 0 then
        begin
          if EvalLength(L, Ctx, F) then V := FormatPx(F);
        end;
      end;
    end;
    Result.FValues[I] := V;
  end;
  { floats, absolutes, the root, and the items of a flex or grid are blocks }
  L := LowTrim(Result.FValues[PDisplay]);
  if (AParent <> nil) and ((AParent.Keyword('display') = 'flex') or (AParent.Keyword('display') = 'inline-flex') or
    (AParent.Keyword('display') = 'grid') or (AParent.Keyword('display') = 'inline-grid')) and
    (L <> 'contents') and (L <> 'none') then
    Result.FValues[PDisplay] := Blockify(L)
  else if AIsRoot or (LowTrim(Result.FValues[PFloat]) <> 'none') or
    (LowTrim(Result.FValues[PPosition]) = 'absolute') or (LowTrim(Result.FValues[PPosition]) = 'fixed') then
    Result.FValues[PDisplay] := Blockify(L);
  if (LowTrim(Result.FValues[PPosition]) = 'absolute') or (LowTrim(Result.FValues[PPosition]) = 'fixed') then
    Result.FValues[PFloat] := 'none';
  { overflow scrolls on one axis: visible on the other becomes auto, clip
    hidden }
  I := InkPropertyIndex('overflow-x'); K := InkPropertyIndex('overflow-y');
  L := LowTrim(Result.FValues[I]); V := LowTrim(Result.FValues[K]);
  if ((L = 'visible') or (L = 'clip')) and not ((V = 'visible') or (V = 'clip')) then
  begin
    if L = 'visible' then Result.FValues[I] := 'auto' else Result.FValues[I] := 'hidden';
  end
  else if ((V = 'visible') or (V = 'clip')) and not ((L = 'visible') or (L = 'clip')) then
  begin
    if V = 'visible' then Result.FValues[K] := 'auto' else Result.FValues[K] := 'hidden';
  end;
end;

procedure Apply(var ASpec: array of string; ACustom: TStringList; const D: TDeclArray;
  AImportant: Boolean);
var K, I, J: Integer; Names: TStringArray;
begin
  for K := 0 to High(D) do
  begin
    if D[K].Important <> AImportant then Continue;
    if D[K].Prop >= 0 then ASpec[D[K].Prop] := D[K].Value
    else if D[K].Prop = -1 then
    begin
      I := ACustom.IndexOfName(D[K].Name);
      if I >= 0 then ACustom[I] := D[K].Name + '=' + D[K].Value
      else ACustom.Add(D[K].Name + '=' + D[K].Value);
    end
    else
    begin
      { a shorthand waiting on var(): each longhand it would set is marked }
      Names := ShorthandParts(D[K].Name);
      for J := 0 to High(Names) do
      begin
        I := InkPropertyIndex(Names[J]);
        if I >= 0 then ASpec[I] := #1 + D[K].Name + #1 + D[K].Value;
      end;
    end;
  end;
end;

function TInkStyler.ComputeOne(AInfo: Pointer): TInkStyle;
var Info: PInfo; N: TInkNode; M: TMatcher; Matched, Imp: TMatchedArray; Count, I: Integer;
  Key, Inline_: string; Hints: THints; Spec: array of string; Custom: TStringList;
  Parent: TInkStyle; InlineDecls: TDeclArray; Shared: TObject; L: TFPList;
begin
  Info := PInfo(AInfo);
  N := Info^.Node;
  M := Default(TMatcher); M.Styler := Self;
  Matched := nil; Count := 0;
  Consider(M, FUniversal, N, FMediaOK, Matched, Count);
  Consider(M, TFPList(FByTag.Find(N.Name)), N, FMediaOK, Matched, Count);
  if (N.Namespace <> insHTML) and (LowerCase(N.Name) <> N.Name) then
    Consider(M, TFPList(FByTag.Find(LowerCase(N.Name))), N, FMediaOK, Matched, Count);
  if Info^.Id <> '' then Consider(M, TFPList(FById.Find(Info^.Id)), N, FMediaOK, Matched, Count);
  for I := 0 to High(Info^.Classes) do
  begin
    L := TFPList(FByClass.Find(Info^.Classes[I]));
    if L <> nil then Consider(M, L, N, FMediaOK, Matched, Count);
  end;
  SortMatched(Matched, Count);
  Inline_ := N.GetAttribute('style');
  Hints := THints(HintDecls(N));
  if Info^.Parent <> nil then Parent := Info^.Parent^.Style else Parent := nil;
  { an element that matched the same rules under the same parent style
    computes the same: share it }
  Key := HexStr(PtrUInt(Parent), 16) + '|' + HexStr(PtrUInt(Hints), 16) + '|' + Inline_ + '|';
  for I := 0 to Count - 1 do Key := Key + IntToStr(Matched[I].Rule.Order) + ',';
  if Info^.Parent = nil then Key := Key + 'root';
  Shared := FShare.Items[Key];
  if Shared <> nil then Exit(TInkStyle(Shared));
  SetLength(Spec, PropCount);
  Custom := TStringList.Create;
  try
    InlineDecls := nil;
    if Inline_ <> '' then InlineDecls := ParseDecls(Inline_, '');
    { lowest first: the browser, the old attributes, the page, style="";
      then !important the other way round }
    for I := 0 to Count - 1 do
      if Matched[I].Rule.Origin = isoUserAgent then Apply(Spec, Custom, Matched[I].Rule.Decls, False);
    if Hints <> nil then Apply(Spec, Custom, Hints.Decls, False);
    for I := 0 to Count - 1 do
      if Matched[I].Rule.Origin = isoAuthor then Apply(Spec, Custom, Matched[I].Rule.Decls, False);
    Apply(Spec, Custom, InlineDecls, False);
    Imp := Copy(Matched, 0, Count);
    SortMatched(Imp, Count, True);
    for I := 0 to Count - 1 do
      if Imp[I].Rule.Origin = isoAuthor then Apply(Spec, Custom, Imp[I].Rule.Decls, True);
    Apply(Spec, Custom, InlineDecls, True);
    for I := 0 to Count - 1 do
      if Imp[I].Rule.Origin = isoUserAgent then Apply(Spec, Custom, Imp[I].Rule.Decls, True);
    Result := Resolve(Spec, Custom, Parent, Info^.Parent = nil);
  finally Custom.Free end;
  FStyles.Add(Result);
  FShare.Add(Key, Result);
end;

procedure TInkStyler.Compute(ARoot: TInkNode);
var I: Integer;
begin
  Release;
  if ARoot = nil then Exit;
  FRoot := ARoot;
  Media.Quirks := (ARoot is TInkDocument) and TInkDocument(ARoot).Quirks;
  EvaluateMedia;
  RankLayers;
  BuildInfos(ARoot);
  for I := 0 to FInfos.Count - 1 do
    PInfo(FInfos[I])^.Style := ComputeOne(FInfos[I]);
end;

function TInkStyler.Explain(N: TInkNode): TStringList;
var Info: PInfo; M: TMatcher; Matched: TMatchedArray; Count, I, K: Integer; S, Org: string;
  L: TFPList;
begin
  Result := TStringList.Create;
  if (N = nil) or (N.Info = nil) then Exit;
  Info := PInfo(N.Info);
  M := Default(TMatcher); M.Styler := Self;
  Matched := nil; Count := 0;
  Consider(M, FUniversal, N, FMediaOK, Matched, Count);
  Consider(M, TFPList(FByTag.Find(N.Name)), N, FMediaOK, Matched, Count);
  if Info^.Id <> '' then Consider(M, TFPList(FById.Find(Info^.Id)), N, FMediaOK, Matched, Count);
  for I := 0 to High(Info^.Classes) do
  begin
    L := TFPList(FByClass.Find(Info^.Classes[I]));
    if L <> nil then Consider(M, L, N, FMediaOK, Matched, Count);
  end;
  SortMatched(Matched, Count);
  for I := 0 to Count - 1 do
  begin
    if Matched[I].Rule.Origin = isoUserAgent then Org := 'browser' else Org := 'page';
    S := '';
    for K := 0 to High(Matched[I].Rule.Decls) do
    begin
      S := S + Matched[I].Rule.Decls[K].Name + ': ' + Matched[I].Rule.Decls[K].Value;
      if Matched[I].Rule.Decls[K].Important then S := S + ' !important';
      S := S + '; ';
    end;
    if Matched[I].Rule.Layer <> '' then Org := Org + ' @layer ' + Matched[I].Rule.Layer;
    Result.Add(Format('%s %d,%d,%d  %s { %s}', [Org, Matched[I].Spec shr 16, (Matched[I].Spec shr 8) and $FF,
      Matched[I].Spec and $FF, Matched[I].Rule.Text, S]));
  end;
  if HintText(N) <> '' then Result.Add('attributes { ' + HintText(N) + ' }');
  if N.GetAttribute('style') <> '' then Result.Add('style="' + N.GetAttribute('style') + '"');
end;

function TInkStyler.StyleOf(N: TInkNode): TInkStyle;
begin
  if (N = nil) or (N.Info = nil) or (N.Kind <> inkElement) then Exit(nil);
  Result := PInfo(N.Info)^.Style;
end;

function TInkStyler.PseudoStyleOf(N: TInkNode; const APseudo: string): TInkStyle;
var M: TMatcher; I, K, Count: Integer; Ref: TRef; Matched: TMatchedArray; Ok: Boolean;
  Spec: array of string; Custom: TStringList;
begin
  Result := nil;
  if (N = nil) or (N.Info = nil) then Exit;
  M := Default(TMatcher); M.Styler := Self;
  Matched := nil; Count := 0;
  for I := 0 to FPseudoRefs.Count - 1 do
  begin
    Ref := TRef(FPseudoRefs[I]);
    if Ref.Sel.PseudoElement <> APseudo then Continue;
    Ok := True;
    for K := 0 to High(Ref.Rule.Media) do
      if not FMediaOK[Ref.Rule.Media[K]] then Ok := False;
    if not Ok or not MatchSel(M, Ref.Sel, High(Ref.Sel.C), N) then Continue;
    if Count = System.Length(Matched) then SetLength(Matched, Count * 2 + 4);
    Matched[Count].Rule := Ref.Rule; Matched[Count].Spec := Ref.Sel.Spec; Inc(Count);
  end;
  if Count = 0 then Exit;
  SortMatched(Matched, Count);
  SetLength(Spec, PropCount);
  Custom := TStringList.Create;
  try
    for I := 0 to Count - 1 do
      if Matched[I].Rule.Origin = isoUserAgent then Apply(Spec, Custom, Matched[I].Rule.Decls, False);
    for I := 0 to Count - 1 do
      if Matched[I].Rule.Origin = isoAuthor then Apply(Spec, Custom, Matched[I].Rule.Decls, False);
    SortMatched(Matched, Count, True);
    for I := 0 to Count - 1 do
      if Matched[I].Rule.Origin = isoAuthor then Apply(Spec, Custom, Matched[I].Rule.Decls, True);
    Result := Resolve(Spec, Custom, StyleOf(N), False);
  finally Custom.Free end;
  FStyles.Add(Result);
end;

initialization
  CSSFormat := DefaultFormatSettings;
  CSSFormat.DecimalSeparator := '.';
  CSSFormat.ThousandSeparator := #0;
finalization
  PropIndex.Free;
end.
