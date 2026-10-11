{ InkLayout - CSS boxes for a document tree, laid out the way a browser lays
  them out.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors

  The tree of boxes is built from a TInkDocument and the computed styles of
  InkStyle: block boxes, runs of inline content, pictures, flex and grid
  containers, tables with their rows and cells.  Layout gives every box its
  place: normal flow with margin collapsing, widths and heights with their
  minimums, maximums, percentages and box-sizing, floats, relative and
  absolute positioning, flex, grid (with named areas), and tables with
  automatic column widths.

  Text is not laid out here.  A run of inline content is a box whose height
  at a given width - and whose narrowest and widest widths - the host
  measures (TInkLayoutMeasure); LazInk's page hands that to its own inline
  renderer.  So this unit needs no widgetset, and is tested in a console
  program with a pretend measurer. }
unit InkLayout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, InkDOM, InkStyle;

type
  TInkBoxKind = (
    ibkBlock,     { a block container of other boxes }
    ibkText,      { a block whose content is inline: one run of text }
    ibkImage,     { a picture, or anything else drawn from outside }
    ibkFlex,      { a flex container }
    ibkGrid,      { a grid container }
    ibkTable,     { a table: its rows, and a caption }
    ibkRow,       { a table row }
    ibkCell);     { a table cell: a block container }

  TInkEdges = record
    Left, Top, Right, Bottom: Integer;
  end;

  TInkBox = class
  private
    FKids: TFPList;
    FMinW, FMaxW: Integer;
    FWidthsKnown: Boolean;
    function GetKid(I: Integer): TInkBox;
  public
    Kind: TInkBoxKind;
    { the element it is made from; nil for an anonymous box }
    Node: TInkNode;
    { a box with no style of its own: a run of text, or a table part
      filled in around stray cells.  A ::before or ::after box has no node
      but is not anonymous: PseudoOf is its element, Pseudo which one. }
    Anon: Boolean;
    PseudoOf: TInkNode;
    Pseudo: string;
    { the element's ::before and ::after that stay among its words }
    InlineBefore, InlineAfter: Boolean;
    Style: TInkStyle;
    Parent: TInkBox;
    { a text box: the element and text nodes of its run, in order.  Each
      starts the run at its own level - the host walks into elements. }
    Inline: TInkNodeArray;
    { a list item's marker, on the first text box inside the item, and
      whether it stands inside the text rather than out in the margin }
    Marker: string;
    MarkerInside: Boolean;
    { what the host keeps for the box - the page's block for a text box -
      and a number of its own }
    Data: TObject;
    Tag: PtrInt;
    { where the box ended up: its border box, page pixels }
    X, Y, W, H: Integer;
    Margin, Border, Padding: TInkEdges;
    { out of the flow }
    Floating, Absolute: Boolean;
    { a table cell's spans }
    ColSpan, RowSpan: Integer;
    { where an absolute box would have been, had it been in the flow }
    StaticX, StaticY: Integer;
    { a text box: where its words go - the content box, unless a float
      beside it takes some of the width or pushes the first line down }
    TextX, TextY, TextW: Integer;
    constructor Create(AKind: TInkBoxKind; ANode: TInkNode; AStyle: TInkStyle);
    destructor Destroy; override;
    procedure Add(ABox: TInkBox);
    function Count: Integer;
    property Kids[I: Integer]: TInkBox read GetKid; default;
    { the content box, page pixels }
    function ContentX: Integer;
    function ContentY: Integer;
    function ContentW: Integer;
    function ContentH: Integer;
    { the padding box: what a background fills inside the borders }
    function PaddingRect: TRect;
    function BorderRect: TRect;
    { moves the box and everything in it }
    procedure Shift(DX, DY: Integer);
  end;

  { What the host knows that the layout does not: how tall a run of text is
    at a width, how narrow and how wide it can be, and how big a picture
    is.  Widths include nothing of the box's own edges. }
  TInkLayoutMeasure = class
  public
    function TextHeight(ABox: TInkBox; AWidth: Integer): Integer; virtual; abstract;
    procedure TextWidths(ABox: TInkBox; out AMin, AMax: Integer); virtual; abstract;
    { 0, 0 when there is no picture to measure }
    procedure ImageSize(ABox: TInkBox; out AWidth, AHeight: Integer); virtual; abstract;
  end;

  TInkLayout = class
  private
    FRoot: TInkBox;
    FStyler: TInkStyler;
    FMeasure: TInkLayoutMeasure;
    FViewW, FViewH: Integer;
    FAbsolutes: TFPList;
    FHeight: Integer;
    procedure Build(ADoc: TInkDocument);
    function MakeBox(N: TInkNode; AParent: TInkBox): TInkBox;
    procedure AddPseudo(ABox: TInkBox; N: TInkNode; const APseudo: string);
    procedure BuildChildren(AOwner: TInkBox; AFrom: TInkNode);
    procedure AddInline(AOwner: TInkBox; var ARun: TInkBox; N: TInkNode);
    procedure FinishRun(AOwner: TInkBox; var ARun: TInkBox);
    procedure Markers(ABox: TInkBox);
  public
    constructor Create(AStyler: TInkStyler; AMeasure: TInkLayoutMeasure);
    destructor Destroy; override;
    { the boxes for a styled document - ADoc must have been through
      AStyler.Compute }
    procedure BuildFrom(ADoc: TInkDocument);
    { lays everything out for a viewport of this size }
    procedure Run(AViewWidth, AViewHeight: Integer);
    { every box, in tree order, to ACallback - for the host to find its own }
    property Root: TInkBox read FRoot;
    { how tall the page is, every box included }
    property Height: Integer read FHeight;
  end;

{ a list marker's text for a list-style-type and a number: "3.", "c.", "•" }
function InkListMarker(const AType: string; ANumber: Integer): string;

implementation

{ ------------------------------------------------------------- the box }

constructor TInkBox.Create(AKind: TInkBoxKind; ANode: TInkNode; AStyle: TInkStyle);
begin
  inherited Create;
  Kind := AKind; Node := ANode; Style := AStyle;
  Anon := ANode = nil;
  FKids := TFPList.Create;
  ColSpan := 1; RowSpan := 1;
end;

destructor TInkBox.Destroy;
var I: Integer;
begin
  for I := 0 to FKids.Count - 1 do TInkBox(FKids[I]).Free;
  FKids.Free;
  inherited Destroy;
end;

function TInkBox.GetKid(I: Integer): TInkBox;
begin
  Result := TInkBox(FKids[I]);
end;

procedure TInkBox.Add(ABox: TInkBox);
begin
  ABox.Parent := Self;
  FKids.Add(ABox);
end;

function TInkBox.Count: Integer;
begin
  Result := FKids.Count;
end;

function TInkBox.ContentX: Integer;
begin
  Result := X + Border.Left + Padding.Left;
end;

function TInkBox.ContentY: Integer;
begin
  Result := Y + Border.Top + Padding.Top;
end;

function TInkBox.ContentW: Integer;
begin
  Result := Max(0, W - Border.Left - Border.Right - Padding.Left - Padding.Right);
end;

function TInkBox.ContentH: Integer;
begin
  Result := Max(0, H - Border.Top - Border.Bottom - Padding.Top - Padding.Bottom);
end;

function TInkBox.PaddingRect: TRect;
begin
  Result := Rect(X + Border.Left, Y + Border.Top, X + W - Border.Right, Y + H - Border.Bottom);
end;

function TInkBox.BorderRect: TRect;
begin
  Result := Rect(X, Y, X + W, Y + H);
end;

procedure TInkBox.Shift(DX, DY: Integer);
var I: Integer;
begin
  if (DX = 0) and (DY = 0) then Exit;
  Inc(X, DX); Inc(Y, DY);
  Inc(StaticX, DX); Inc(StaticY, DY);
  Inc(TextX, DX); Inc(TextY, DY);
  for I := 0 to FKids.Count - 1 do TInkBox(FKids[I]).Shift(DX, DY);
end;

{ ------------------------------------------------------------- markers }

function Roman(N: Integer): string;
const
  V: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  S: array[0..12] of string = ('m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i');
var I: Integer;
begin
  Result := '';
  if (N <= 0) or (N >= 4000) then Exit(IntToStr(N));
  for I := 0 to 12 do
    while N >= V[I] do begin Result := Result + S[I]; Dec(N, V[I]) end;
end;

function Alpha(N: Integer): string;
begin
  Result := '';
  if N <= 0 then Exit(IntToStr(N));
  while N > 0 do
  begin
    Dec(N);
    Result := Chr(Ord('a') + N mod 26) + Result;
    N := N div 26;
  end;
end;

function InkListMarker(const AType: string; ANumber: Integer): string;
begin
  case LowerCase(Trim(AType)) of
    'none', '': Result := '';
    'disc': Result := '•';
    'circle': Result := '◦';
    'square': Result := '▪';
    'disclosure-open': Result := '▾';
    'disclosure-closed': Result := '▸';
    'decimal': Result := IntToStr(ANumber) + '.';
    'decimal-leading-zero': Result := Format('%.2d.', [ANumber]);
    'lower-alpha', 'lower-latin': Result := Alpha(ANumber) + '.';
    'upper-alpha', 'upper-latin': Result := UpperCase(Alpha(ANumber)) + '.';
    'lower-roman': Result := Roman(ANumber) + '.';
    'upper-roman': Result := UpperCase(Roman(ANumber)) + '.';
    'lower-greek': Result := InkCodepointToUTF8($3B1 + ((ANumber - 1) mod 24)) + '.';
  else
    { a quoted string is the marker itself }
    if (AType <> '') and (AType[1] in ['"', '''']) then Result := Copy(AType, 2, Length(AType) - 2)
    else Result := '•';
  end;
end;

{ ------------------------------------------------------ building boxes }

function Disp(S: TInkStyle): string; inline;
begin
  Result := S.Keyword('display');
end;

function IsInlineLevel(const D: string): Boolean;
begin
  Result := (D = 'inline') or (D = 'inline-block') or (D = 'ruby') or (D = 'ruby-text') or
    (D = 'inline-flex') or (D = 'inline-grid') or (D = 'inline-table');
end;

constructor TInkLayout.Create(AStyler: TInkStyler; AMeasure: TInkLayoutMeasure);
begin
  inherited Create;
  FStyler := AStyler; FMeasure := AMeasure;
  FAbsolutes := TFPList.Create;
end;

destructor TInkLayout.Destroy;
begin
  FRoot.Free;
  FAbsolutes.Free;
  inherited Destroy;
end;

procedure TInkLayout.BuildFrom(ADoc: TInkDocument);
begin
  FreeAndNil(FRoot);
  Build(ADoc);
end;

procedure TInkLayout.Build(ADoc: TInkDocument);
var Html: TInkNode;
begin
  Html := ADoc.DocumentElement;
  if (Html = nil) or (FStyler.StyleOf(Html) = nil) then Exit;
  FRoot := MakeBox(Html, nil);
  if FRoot <> nil then Markers(FRoot);
end;

{ the box an element makes, with its content; nil for one that makes none }
function FirstChildNamed(N: TInkNode; const AName: string): TInkNode;
begin
  Result := N.FirstElementChild;
  while (Result <> nil) and (Result.Name <> AName) do Result := Result.NextElementSibling;
end;

{ drawn from outside the text: a picture, a drawing, a frame }
function IsReplaced(N: TInkNode): Boolean;
begin
  Result := (N.Name = 'img') or (N.Name = 'video') or (N.Name = 'canvas') or
    (N.Name = 'iframe') or (N.Name = 'embed') or (N.Name = 'object') or
    ((N.Namespace = insSVG) and (N.Name = 'svg'));
end;

{ what a row holds that is not a cell goes into a cell made for it, as a
  browser does: cells made display: block stack in one cell }
procedure CellsOfRow(ARow: TInkBox);
var I, J: Integer; K, Cell: TInkBox; Kids: TFPList; Blank: Boolean;
begin
  Kids := TFPList.Create;
  try
    Cell := nil;
    for I := 0 to ARow.Count - 1 do
    begin
      K := ARow[I];
      Blank := K.Anon and (K.Kind = ibkText);
      if Blank then
        for J := 0 to High(K.Inline) do
          if (K.Inline[J].Kind <> inkText) or (Trim(K.Inline[J].Data) <> '') then Blank := False;
      if (K.Kind = ibkCell) or K.Absolute or Blank then
      begin
        Cell := nil;
        Kids.Add(K);
        Continue;
      end;
      if Cell = nil then
      begin
        Cell := TInkBox.Create(ibkCell, nil, ARow.Style);
        Cell.Parent := ARow; Cell.ColSpan := 1; Cell.RowSpan := 1;
        Kids.Add(Cell);
      end;
      Cell.FKids.Add(K);
      K.Parent := Cell;
    end;
    ARow.FKids.Assign(Kids);
  finally Kids.Free end;
end;

function TInkLayout.MakeBox(N: TInkNode; AParent: TInkBox): TInkBox;
var S: TInkStyle; D: string; K: TInkBoxKind;
begin
  Result := nil;
  S := FStyler.StyleOf(N);
  if S = nil then Exit;
  D := Disp(S);
  if D = 'none' then Exit;
  if IsReplaced(N) then
  begin
    Result := TInkBox.Create(ibkImage, N, S);
    Result.Floating := S.Keyword('float') <> 'none';
    Result.Absolute := (S.Keyword('position') = 'absolute') or (S.Keyword('position') = 'fixed');
    Exit;
  end;
  case D of
    'flex', 'inline-flex': K := ibkFlex;
    'grid', 'inline-grid': K := ibkGrid;
    'table', 'inline-table': K := ibkTable;
    'table-row': K := ibkRow;
    'table-cell': K := ibkCell;
  else
    K := ibkBlock;
  end;
  Result := TInkBox.Create(K, N, S);
  Result.Parent := AParent;
  Result.Floating := S.Keyword('float') <> 'none';
  Result.Absolute := (S.Keyword('position') = 'absolute') or (S.Keyword('position') = 'fixed');
  if K = ibkCell then
  begin
    Result.ColSpan := Max(1, StrToIntDef(N.GetAttribute('colspan'), 1));
    Result.RowSpan := Max(1, StrToIntDef(N.GetAttribute('rowspan'), 1));
  end;
  BuildChildren(Result, N);
  AddPseudo(Result, N, 'before');
  AddPseudo(Result, N, 'after');
  if K = ibkRow then CellsOfRow(Result);
  { a block holding nothing but one run of text is that run }
  if (K = ibkBlock) and (Result.Count = 1) and (Result[0].Kind = ibkText) and
    (Result[0].Anon) then
  begin
    Result.Kind := ibkText;
    Result.Inline := Result[0].Inline;
    Result.InlineBefore := Result[0].InlineBefore;
    Result.InlineAfter := Result[0].InlineAfter;
    Result[0].Free;
    Result.FKids.Clear;
  end
  else if (K in [ibkBlock, ibkCell]) and (Result.Count = 0) and (N.Name = 'li') then
    { an empty item still has its marker's line }
    Result.Kind := ibkText;
end;

{ an element's ::before or ::after.  In its element's words it joins the
  run of text at that end; where there is none, or where it is a box of its
  own - a flex or grid item, a block, a float - it gets a box }
procedure TInkLayout.AddPseudo(ABox: TInkBox; N: TInkNode; const APseudo: string);
var PS: TInkStyle; C, D: string; P, Joined: TInkBox; Boxed: Boolean;
begin
  if ABox.Kind in [ibkImage, ibkTable, ibkRow] then Exit;
  PS := FStyler.PseudoStyleOf(N, APseudo);
  if PS = nil then Exit;
  D := Disp(PS);
  if D = 'none' then Exit;
  C := LowerCase(Trim(PS.Value('content')));
  if (C = '') or (C = 'none') or (C = 'normal') then Exit;
  Boxed := (ABox.Kind in [ibkFlex, ibkGrid]) or not IsInlineLevel(D) or
    (PS.Keyword('float') <> 'none') or (PS.Keyword('position') = 'absolute') or
    (PS.Keyword('position') = 'fixed');
  if not Boxed then
  begin
    Joined := nil;
    if ABox.Count > 0 then
      if APseudo = 'before' then Joined := ABox[0] else Joined := ABox[ABox.Count - 1];
    if (Joined <> nil) and Joined.Anon and (Joined.Kind = ibkText) then
    begin
      if APseudo = 'before' then Joined.InlineBefore := True else Joined.InlineAfter := True;
      Exit;
    end;
  end;
  if (C = '""') or (C = '''''') then P := TInkBox.Create(ibkBlock, nil, PS)
  else P := TInkBox.Create(ibkText, nil, PS);
  P.Anon := False; P.PseudoOf := N; P.Pseudo := APseudo; P.Parent := ABox;
  P.Floating := PS.Keyword('float') <> 'none';
  P.Absolute := (PS.Keyword('position') = 'absolute') or (PS.Keyword('position') = 'fixed');
  if APseudo = 'before' then ABox.FKids.Insert(0, P) else ABox.FKids.Add(P);
end;

procedure TInkLayout.FinishRun(AOwner: TInkBox; var ARun: TInkBox);
var I: Integer; Visible: Boolean; N: TInkNode; T: string; K: Integer;
begin
  if ARun = nil then Exit;
  { a run of nothing but white space between blocks is not a line }
  Visible := False;
  for I := 0 to High(ARun.Inline) do
  begin
    N := ARun.Inline[I];
    if N.Kind = inkElement then begin Visible := True; Break end;
    T := N.Data;
    for K := 1 to Length(T) do
      if not (T[K] in [' ', #9, #10, #12, #13]) then begin Visible := True; Break end;
    if Visible then Break;
    { white space that is kept is content }
    if (FStyler.StyleOf(N.Parent) <> nil) and
      (Pos('pre', FStyler.StyleOf(N.Parent).Keyword('white-space')) > 0) and (T <> '') then
    begin
      Visible := True; Break;
    end;
  end;
  if Visible then AOwner.Add(ARun) else ARun.Free;
  ARun := nil;
end;

{ an inline-level node joins the run being gathered; a block inside an
  inline ends the run and stands on its own }
procedure TInkLayout.AddInline(AOwner: TInkBox; var ARun: TInkBox; N: TInkNode);
var K: Integer;
begin
  if ARun = nil then
  begin
    ARun := TInkBox.Create(ibkText, nil, AOwner.Style);
    ARun.Parent := AOwner;
  end;
  K := Length(ARun.Inline);
  SetLength(ARun.Inline, K + 1);
  ARun.Inline[K] := N;
end;

{ whether an inline element holds a block somewhere inside, which a run
  cannot carry }
function HoldsBlock(AStyler: TInkStyler; N: TInkNode): Boolean;
var C: TInkNode; S: TInkStyle; D: string;
begin
  C := N.FirstChild;
  while C <> nil do
  begin
    if C.Kind = inkElement then
    begin
      S := AStyler.StyleOf(C);
      if S <> nil then
      begin
        D := S.Keyword('display');
        if (D <> 'none') and not IsInlineLevel(D) and (D <> 'contents') then Exit(True);
        if (C.Name = 'img') and (D <> 'none') then Exit(True);
        if (D <> 'none') and HoldsBlock(AStyler, C) then Exit(True);
      end;
    end;
    C := C.NextSibling;
  end;
  Result := False;
end;

procedure TInkLayout.BuildChildren(AOwner: TInkBox; AFrom: TInkNode);
var C: TInkNode; S: TInkStyle; D: string; Words_, B: TInkBox; InFlex: Boolean;
begin
  Words_ := nil;
  InFlex := AOwner.Kind in [ibkFlex, ibkGrid];
  C := AFrom.FirstChild;
  while C <> nil do
  begin
    case C.Kind of
      inkText:
        if InFlex then
        begin
          { text straight inside a flex or grid container is an item of its own }
          AddInline(AOwner, Words_, C);
          FinishRun(AOwner, Words_);
        end
        else AddInline(AOwner, Words_, C);
      inkElement:
        begin
          S := FStyler.StyleOf(C);
          if S = nil then begin C := C.NextSibling; Continue end;
          D := Disp(S);
          if D = 'none' then
          else if D = 'contents' then
          begin
            FinishRun(AOwner, Words_);
            BuildChildren(AOwner, C);
          end
          else if (C.Name = 'details') and not C.HasAttribute('open') and
            (AFrom.Name <> 'details') then
          begin
            { a shut <details> shows its summary only }
            FinishRun(AOwner, Words_);
            B := MakeBox(C, AOwner);
            if B <> nil then AOwner.Add(B);
          end
          else if (AFrom.Name = 'details') and not AFrom.HasAttribute('open') and
            not ((C.Name = 'summary') and (C = FirstChildNamed(AFrom, 'summary'))) then
          else if InFlex then
          begin
            FinishRun(AOwner, Words_);
            B := MakeBox(C, AOwner);
            if B <> nil then AOwner.Add(B);
          end
          else if IsInlineLevel(D) and not IsReplaced(C) and (S.Keyword('float') = 'none') and
            (S.Keyword('position') <> 'absolute') and (S.Keyword('position') <> 'fixed') then
          begin
            if HoldsBlock(FStyler, C) then
            begin
              { an inline holding a block or a picture: its pieces stand at the
                run's level, and the text in them still wears its style }
              FinishRun(AOwner, Words_);
              BuildChildren(AOwner, C);
            end
            else AddInline(AOwner, Words_, C);
          end
          else
          begin
            FinishRun(AOwner, Words_);
            B := MakeBox(C, AOwner);
            if B <> nil then AOwner.Add(B);
          end;
        end;
    end;
    C := C.NextSibling;
  end;
  FinishRun(AOwner, Words_);
end;

{ list items' markers, numbered the way their list counts }
procedure TInkLayout.Markers(ABox: TInkBox);
var I, Num, Step: Integer; K: TInkBox; S: TInkStyle;

  { the first line inside an item - not inside a list, a table or a flex or
    grid of its own, whose lines are theirs }
  function FirstText(B: TInkBox): TInkBox;
  var J: Integer;
  begin
    if B.Kind = ibkText then Exit(B);
    if B.Kind <> ibkBlock then Exit(nil);
    if (B.Node <> nil) and ((B.Node.Name = 'ul') or (B.Node.Name = 'ol') or (B.Node.Name = 'menu')) then
      Exit(nil);
    for J := 0 to B.Count - 1 do
    begin
      if B[J].Floating or B[J].Absolute then Continue;
      Exit(FirstText(B[J]));
    end;
    Result := nil;
  end;

  procedure Mark(Item: TInkBox; AText: string);
  var T, Empty: TInkBox;
  begin
    if AText = '' then Exit;
    T := FirstText(Item);
    if T = nil then
    begin
      { nothing to hang it on: an empty line of its own at the top }
      Empty := TInkBox.Create(ibkText, nil, Item.Style);
      Empty.Parent := Item;
      Item.FKids.Insert(0, Empty);
      T := Empty;
    end;
    T.Marker := AText;
    T.MarkerInside := Item.Style.Keyword('list-style-position') = 'inside';
  end;

begin
  Num := 1; Step := 1;
  if (ABox.Node <> nil) and (ABox.Node.Name = 'ol') then
  begin
    if ABox.Node.HasAttribute('reversed') then
    begin
      Step := -1; Num := 0;
      for I := 0 to ABox.Count - 1 do
        if ABox[I].Style.Keyword('display') = 'list-item' then Inc(Num);
    end;
    if ABox.Node.HasAttribute('start') then Num := StrToIntDef(ABox.Node.GetAttribute('start'), Num);
  end;
  for I := 0 to ABox.Count - 1 do
  begin
    K := ABox[I];
    S := K.Style;
    if (K.Node <> nil) and (S.Keyword('display') = 'list-item') then
    begin
      if K.Node.HasAttribute('value') then Num := StrToIntDef(K.Node.GetAttribute('value'), Num);
      Mark(K, InkListMarker(S.Value('list-style-type'), Num));
      Inc(Num, Step);
    end;
    Markers(K);
  end;
end;

{ --------------------------------------------------------------- sizes }

type
  { a run of collapsing margins: the largest positive and the most
    negative, which add up to the gap }
  TCollapse = record
    Pos, Neg: Integer;
  end;

  { the floats of one block formatting context, in page pixels }
  TFloats = class
    Rects: array of TRect;
    Lefts: array of Boolean;
    procedure Add(const R: TRect; ALeft: Boolean);
    { the room between the floats over [Y1, Y2), inside [ALeft, ARight) }
    procedure Room(Y1, Y2, ALeft, ARight: Integer; out L, R: Integer);
    function Bottom(ALeft, ARight: Boolean): Integer;
    { the lowest float bottom below Y, or Y itself when none }
    function NextBottom(Y: Integer): Integer;
  end;

procedure TFloats.Add(const R: TRect; ALeft: Boolean);
var K: Integer;
begin
  K := Length(Rects);
  SetLength(Rects, K + 1); SetLength(Lefts, K + 1);
  Rects[K] := R; Lefts[K] := ALeft;
end;

procedure TFloats.Room(Y1, Y2, ALeft, ARight: Integer; out L, R: Integer);
var I: Integer;
begin
  L := ALeft; R := ARight;
  if Y2 <= Y1 then Y2 := Y1 + 1;
  for I := 0 to High(Rects) do
    if (Rects[I].Top < Y2) and (Rects[I].Bottom > Y1) then
    begin
      if Lefts[I] then L := Max(L, Rects[I].Right)
      else R := Min(R, Rects[I].Left);
    end;
end;

function TFloats.Bottom(ALeft, ARight: Boolean): Integer;
var I: Integer;
begin
  Result := Low(Integer);
  for I := 0 to High(Rects) do
    if (Lefts[I] and ALeft) or (not Lefts[I] and ARight) then
      Result := Max(Result, Rects[I].Bottom);
end;

function TFloats.NextBottom(Y: Integer): Integer;
var I: Integer;
begin
  Result := MaxInt;
  for I := 0 to High(Rects) do
    if (Rects[I].Bottom > Y) and (Rects[I].Bottom < Result) then Result := Rects[I].Bottom;
  if Result = MaxInt then Result := Y;
end;

procedure Gather(var C: TCollapse; V: Integer); inline;
begin
  if V > 0 then C.Pos := Max(C.Pos, V) else C.Neg := Min(C.Neg, V);
end;

function GapOf(const C: TCollapse): Integer; inline;
begin
  Result := C.Pos + C.Neg;
end;

{ a length property in whole pixels; ADefault for auto, none, normal and
  anything else that is not a length }
function Len(S: TInkStyle; const AProp: string; APercentOf: Double; ADefault: Integer): Integer;
var V: string;
begin
  V := S.Keyword(AProp);
  if (V = '') or (V = 'auto') or (V = 'none') or (V = 'normal') or (V = 'fit-content') or
    (V = 'min-content') or (V = 'max-content') then Exit(ADefault);
  if (Pos('%', V) > 0) and (APercentOf < 0) then Exit(ADefault);
  Result := Round(S.Length(V, Max(0, APercentOf), ADefault));
end;

function IsAuto(S: TInkStyle; const AProp: string): Boolean; inline;
var V: string;
begin
  V := S.Keyword(AProp);
  Result := (V = 'auto') or (V = '');
end;

procedure Edges(B: TInkBox; ACBW: Integer);
var S: TInkStyle;
begin
  S := B.Style;
  if B.Anon then
  begin
    { an anonymous box has none of its own }
    B.Margin := Default(TInkEdges); B.Border := Default(TInkEdges); B.Padding := Default(TInkEdges);
    Exit;
  end;
  B.Margin.Left := Len(S, 'margin-left', ACBW, 0);
  B.Margin.Right := Len(S, 'margin-right', ACBW, 0);
  B.Margin.Top := Len(S, 'margin-top', ACBW, 0);
  B.Margin.Bottom := Len(S, 'margin-bottom', ACBW, 0);
  B.Border.Left := Round(S.Px('border-left-width'));
  B.Border.Right := Round(S.Px('border-right-width'));
  B.Border.Top := Round(S.Px('border-top-width'));
  B.Border.Bottom := Round(S.Px('border-bottom-width'));
  B.Padding.Left := Max(0, Len(S, 'padding-left', ACBW, 0));
  B.Padding.Right := Max(0, Len(S, 'padding-right', ACBW, 0));
  B.Padding.Top := Max(0, Len(S, 'padding-top', ACBW, 0));
  B.Padding.Bottom := Max(0, Len(S, 'padding-bottom', ACBW, 0));
end;

function EdgesH(B: TInkBox): Integer; inline;
begin
  Result := B.Border.Left + B.Border.Right + B.Padding.Left + B.Padding.Right;
end;

function EdgesV(B: TInkBox): Integer; inline;
begin
  Result := B.Border.Top + B.Border.Bottom + B.Padding.Top + B.Padding.Bottom;
end;

function BorderBoxSizing(B: TInkBox): Boolean; inline;
begin
  Result := (not B.Anon) and (B.Style.Keyword('box-sizing') = 'border-box');
end;

{ a width property as a border-box width, -1 for auto }
function SpecW(B: TInkBox; const AProp: string; ACBW: Integer): Integer;
begin
  if B.Anon then Exit(-1);
  Result := Len(B.Style, AProp, ACBW, -1);
  if Result < 0 then Exit(-1);
  if not BorderBoxSizing(B) then Inc(Result, EdgesH(B));
end;

function SpecH(B: TInkBox; const AProp: string; ACBH: Integer): Integer;
begin
  if B.Anon then Exit(-1);
  Result := Len(B.Style, AProp, ACBH, -1);
  if Result < 0 then Exit(-1);
  if not BorderBoxSizing(B) then Inc(Result, EdgesV(B));
end;

{ a border-box width kept within min-width and max-width }
function ClampW(B: TInkBox; AW, ACBW: Integer): Integer;
var V: Integer;
begin
  Result := AW;
  V := SpecW(B, 'max-width', ACBW);
  if (V >= 0) and (Result > V) then Result := V;
  V := SpecW(B, 'min-width', ACBW);
  if (V >= 0) and (Result < V) then Result := V;
  Result := Max(Result, EdgesH(B));
end;

function ClampH(B: TInkBox; AH, ACBH: Integer): Integer;
var V: Integer;
begin
  Result := AH;
  V := SpecH(B, 'max-height', ACBH);
  if (V >= 0) and (Result > V) then Result := V;
  V := SpecH(B, 'min-height', ACBH);
  if (V >= 0) and (Result < V) then Result := V;
  Result := Max(Result, EdgesV(B));
end;

{ whether a box starts a new block formatting context: its floats are its
  own, and its margins do not collapse through it }
function IsBFC(B: TInkBox): Boolean;
var O, D: string;
begin
  if (B.Parent = nil) or B.Floating or B.Absolute then Exit(True);
  if B.Kind in [ibkFlex, ibkGrid, ibkTable, ibkCell, ibkImage] then Exit(True);
  if B.Parent.Kind in [ibkFlex, ibkGrid] then Exit(True);
  if B.Anon then Exit(False);
  O := B.Style.Keyword('overflow-x');
  D := B.Style.Keyword('display');
  Result := ((O <> 'visible') and (O <> 'clip')) or (D = 'flow-root') or (D = 'inline-block');
end;

function InFlow(B: TInkBox): Boolean; inline;
begin
  Result := not B.Floating and not B.Absolute;
end;

function FirstInFlow(B: TInkBox): TInkBox;
var I: Integer;
begin
  for I := 0 to B.Count - 1 do
    if InFlow(B[I]) then Exit(B[I]);
  Result := nil;
end;

function LastInFlow(B: TInkBox): TInkBox;
var I: Integer;
begin
  for I := B.Count - 1 downto 0 do
    if InFlow(B[I]) then Exit(B[I]);
  Result := nil;
end;

function TopCollapses(B: TInkBox): Boolean;
begin
  Result := (B.Kind = ibkBlock) and not IsBFC(B) and (B.Border.Top = 0) and
    (B.Padding.Top = 0) and (FirstInFlow(B) <> nil);
end;

function BottomCollapses(B: TInkBox): Boolean;
begin
  Result := (B.Kind = ibkBlock) and not IsBFC(B) and (B.Border.Bottom = 0) and
    (B.Padding.Bottom = 0) and IsAuto(B.Style, 'height') and (LastInFlow(B) <> nil) and
    ((B.Anon) or (Len(B.Style, 'min-height', 0, 0) <= 0));
end;

{ the margins that end up above a box: its own, with its first child's
  when they meet }
procedure TopMargins(B: TInkBox; ACBW: Integer; var C: TCollapse);
var F: TInkBox;
begin
  Edges(B, ACBW);
  Gather(C, B.Margin.Top);
  if TopCollapses(B) then
  begin
    F := FirstInFlow(B);
    TopMargins(F, Max(0, ACBW - EdgesH(B)), C);
  end;
end;

procedure BottomMargins(B: TInkBox; var C: TCollapse);
var L: TInkBox;
begin
  Gather(C, B.Margin.Bottom);
  if BottomCollapses(B) then
  begin
    L := LastInFlow(B);
    BottomMargins(L, C);
  end;
end;

{ --------------------------------------------------------------- the flow }

type
  TFlow = class
    Layout: TInkLayout;
    Measure: TInkLayoutMeasure;
    ViewW, ViewH: Integer;
    Absolutes: TFPList;
    procedure Widths(B: TInkBox; out AMin, AMax: Integer);
    { the same from the content alone, whatever width the box asks for -
      what the flex minimum and a table column go by }
    procedure ContentWidths(B: TInkBox; out AMin, AMax: Integer);
    function ShrinkToFit(B: TInkBox; AAvail: Integer): Integer;
    procedure LayBox(B: TInkBox; AX, AY, ACBW, ACBH: Integer; AFloats: TFloats;
      AForceW: Integer = -1; AShrink: Boolean = False);
    function FlowKids(B: TInkBox; AFloats: TFloats): Integer;
    procedure LayFloat(K: TInkBox; AContainer: TInkBox; AY: Integer; AFloats: TFloats);
    function LayFlex(B: TInkBox): Integer;
    function LayGrid(B: TInkBox): Integer;
    function LayTable(B: TInkBox; AForceW: Integer; ACBW: Integer): Integer;
    procedure TableWidth(B: TInkBox; AAvail: Integer; out AW: Integer; ACBW: Integer);
    procedure Relative(B: TInkBox; ACBW: Integer);
    procedure LayAbsolute(B: TInkBox);
  end;

{ the narrowest and widest a box can be, border box, without its margins }
procedure TFlow.Widths(B: TInkBox; out AMin, AMax: Integer);
var Spec: Integer;
begin
  ContentWidths(B, AMin, AMax);
  { a width the box asks for in pixels is the width }
  Spec := SpecW(B, 'width', -1);
  if (Spec >= 0) and (B.Kind <> ibkImage) then
  begin
    AMin := Max(EdgesH(B), Spec); AMax := AMin;
  end;
end;

procedure TFlow.ContentWidths(B: TInkBox; out AMin, AMax: Integer);
var I, KMin, KMax, M, Gap, IW, IH, Sum, SumMin, Spec: Integer; K: TInkBox; Wrap, Row: Boolean;
begin
  if B.FWidthsKnown then begin AMin := B.FMinW; AMax := B.FMaxW; Exit end;
  Edges(B, 0);
  AMin := 0; AMax := 0;
  case B.Kind of
    ibkText:
      Measure.TextWidths(B, AMin, AMax);
    ibkImage:
      begin
        Measure.ImageSize(B, IW, IH);
        Spec := Len(B.Style, 'width', -1, -1);
        if Spec >= 0 then IW := Spec
        else if (Len(B.Style, 'height', -1, -1) >= 0) and (IH > 0) then
          IW := Round(IW * Len(B.Style, 'height', -1, -1) / IH);
        { a picture that may shrink with its column has no width of its own
          it insists on }
        if Pos('%', B.Style.Keyword('max-width')) > 0 then AMin := 0 else AMin := IW;
        AMax := IW;
      end;
    ibkFlex:
      begin
        Row := Pos('column', B.Style.Keyword('flex-direction')) = 0;
        Wrap := B.Style.Keyword('flex-wrap') <> 'nowrap';
        Gap := Len(B.Style, 'column-gap', -1, 0);
        Sum := 0; SumMin := 0; M := 0;
        for I := 0 to B.Count - 1 do
        begin
          K := B[I];
          if K.Absolute then Continue;
          Widths(K, KMin, KMax);
          Edges(K, 0);
          Inc(KMin, Max(0, K.Margin.Left) + Max(0, K.Margin.Right));
          Inc(KMax, Max(0, K.Margin.Left) + Max(0, K.Margin.Right));
          if Row then
          begin
            if Sum > 0 then Inc(Sum, Gap);
            Inc(Sum, KMax); Inc(SumMin, KMin); M := Max(M, KMin);
          end
          else begin Sum := Max(Sum, KMax); M := Max(M, KMin); SumMin := M end;
        end;
        AMax := Sum;
        if Row and not Wrap then AMin := SumMin else AMin := M;
      end;
    ibkTable, ibkRow:
      begin
        { the widest row: a light version of what layout works out }
        Gap := 0;
        if (B.Kind = ibkTable) and (B.Style.Keyword('border-collapse') <> 'collapse') then
          Gap := Len(B.Style, 'border-spacing', -1, 0);
        for I := 0 to B.Count - 1 do
        begin
          Widths(B[I], KMin, KMax);
          AMin := Max(AMin, KMin); AMax := Max(AMax, KMax);
        end;
        if B.Kind = ibkRow then
        begin
          AMin := 0; AMax := 0;
          for I := 0 to B.Count - 1 do
          begin
            Widths(B[I], KMin, KMax);
            Inc(AMin, KMin); Inc(AMax, KMax);
          end;
        end;
        Inc(AMin, 2 * Gap); Inc(AMax, 2 * Gap);
      end;
  else
    { a block, a cell, a grid: the widest of what it holds }
    begin
      Sum := 0;
      for I := 0 to B.Count - 1 do
      begin
        K := B[I];
        if K.Absolute then Continue;
        Widths(K, KMin, KMax);
        Edges(K, 0);
        M := Max(0, K.Margin.Left) + Max(0, K.Margin.Right);
        if B.Kind = ibkGrid then
        begin
          Inc(Sum, KMax + M);
          AMin := Max(AMin, KMin + M);
        end
        else
        begin
          AMin := Max(AMin, KMin + M);
          AMax := Max(AMax, KMax + M);
        end;
      end;
      if B.Kind = ibkGrid then AMax := Max(AMax, Sum);
    end;
  end;
  Edges(B, 0);
  if B.Kind <> ibkTable then
  begin
    Inc(AMin, EdgesH(B)); Inc(AMax, EdgesH(B));
  end;
  AMax := Max(AMax, AMin);
  B.FMinW := AMin; B.FMaxW := AMax; B.FWidthsKnown := True;
end;

{ as wide as the content, no wider than the room, no narrower than its
  narrowest - how floats, absolutes and inline blocks are sized }
function TFlow.ShrinkToFit(B: TInkBox; AAvail: Integer): Integer;
var MinW, MaxW: Integer;
begin
  Widths(B, MinW, MaxW);
  Result := Min(Max(MinW, AAvail), MaxW);
end;

procedure TFlow.LayFloat(K: TInkBox; AContainer: TInkBox; AY: Integer; AFloats: TFloats);
var Y, L, R, OuterW, OuterH, CX, CW, NewX: Integer; Own: TFloats; Left: Boolean;
begin
  CX := AContainer.ContentX; CW := AContainer.ContentW;
  Own := TFloats.Create;
  try
    LayBox(K, 0, 0, CW, -1, Own, -1, True);
  finally Own.Free end;
  OuterW := K.W + K.Margin.Left + K.Margin.Right;
  OuterH := K.H + K.Margin.Top + K.Margin.Bottom;
  Left := K.Style.Keyword('float') <> 'right';
  Y := AY;
  { down past the floats until it fits beside them }
  repeat
    AFloats.Room(Y, Y + Max(1, OuterH), CX, CX + CW, L, R);
    if (R - L >= OuterW) or (AFloats.NextBottom(Y) = Y) then Break;
    Y := AFloats.NextBottom(Y);
  until False;
  if Left then NewX := L + K.Margin.Left else NewX := R - K.Margin.Right - K.W;
  K.Shift(NewX - K.X, Y + K.Margin.Top - K.Y);
  AFloats.Add(Rect(K.X - K.Margin.Left, Y, K.X + K.W + K.Margin.Right, Y + OuterH), Left);
end;

{ the in-flow children of a block, one under another, with their margins
  collapsing; the height they take }
function TFlow.FlowKids(B: TInkBox; AFloats: TFloats): Integer;
var I, Y, CW, CX, ClearY: Integer; K: TInkBox; Pending, Top: TCollapse; First, Absorb: Boolean;
  Clear: string;
begin
  CX := B.ContentX; CW := B.ContentW;
  Y := B.ContentY;
  Pending := Default(TCollapse);
  First := True;
  Absorb := TopCollapses(B);
  for I := 0 to B.Count - 1 do
  begin
    K := B[I];
    if K.Absolute then
    begin
      K.StaticX := CX; K.StaticY := Y + GapOf(Pending);
      Absolutes.Add(K);
      Continue;
    end;
    if K.Floating then
    begin
      LayFloat(K, B, Y + GapOf(Pending), AFloats);
      Continue;
    end;
    Top := Pending;
    if First and Absorb then
      Top := Default(TCollapse)
    else TopMargins(K, CW, Top);
    { clearance: below the floats it names }
    Clear := '';
    if not K.Anon then Clear := K.Style.Keyword('clear');
    if (Clear = 'left') or (Clear = 'right') or (Clear = 'both') or (Clear = 'inline-start') or
      (Clear = 'inline-end') then
    begin
      ClearY := AFloats.Bottom((Clear = 'left') or (Clear = 'both') or (Clear = 'inline-start'),
        (Clear = 'right') or (Clear = 'both') or (Clear = 'inline-end'));
      if ClearY > Y + GapOf(Top) then
      begin
        Y := ClearY; Top := Default(TCollapse);
        Edges(K, CW);
      end;
    end;
    if First and Absorb then Edges(K, CW);
    LayBox(K, CX, Y + GapOf(Top), CW, B.ContentH, AFloats);
    Y := K.Y + K.H;
    { a relative shift moves what is drawn, not where the next box goes }
    Relative(K, CW);
    Pending := Default(TCollapse);
    BottomMargins(K, Pending);
    First := False;
  end;
  if not BottomCollapses(B) then Inc(Y, GapOf(Pending));
  Result := Y - B.ContentY;
end;

procedure TFlow.Relative(B: TInkBox; ACBW: Integer);
var DX, DY: Integer;
begin
  if (B.Anon) or (B.Style.Keyword('position') <> 'relative') and
    (B.Style.Keyword('position') <> 'sticky') then Exit;
  DX := 0; DY := 0;
  if not IsAuto(B.Style, 'left') then DX := Len(B.Style, 'left', ACBW, 0)
  else if not IsAuto(B.Style, 'right') then DX := -Len(B.Style, 'right', ACBW, 0);
  if not IsAuto(B.Style, 'top') then DY := Len(B.Style, 'top', -1, 0)
  else if not IsAuto(B.Style, 'bottom') then DY := -Len(B.Style, 'bottom', -1, 0);
  if B.Style.Keyword('position') = 'sticky' then begin DX := 0; DY := 0 end;
  B.Shift(DX, DY);
end;

{ a box at (AX, AY), the top of its border box, in a containing block
  ACBW wide; its own floats in AFloats unless it starts its own context }
procedure TFlow.LayBox(B: TInkBox; AX, AY, ACBW, ACBH: Integer; AFloats: TFloats;
  AForceW: Integer; AShrink: Boolean);
var W, H, Avail, ContentH, SH, IW, IH, AutoL, AutoR, L, R, MinT: Integer; Own: TFloats;
  Ratio: Double; MarginAutoL, MarginAutoR: Boolean; TA: string;
begin
  B.FWidthsKnown := False;
  Edges(B, ACBW);
  MarginAutoL := (not B.Anon) and IsAuto(B.Style, 'margin-left');
  MarginAutoR := (not B.Anon) and IsAuto(B.Style, 'margin-right');
  Avail := ACBW - B.Margin.Left - B.Margin.Right;
  { the width }
  if AForceW >= 0 then W := AForceW
  else
  begin
    W := SpecW(B, 'width', ACBW);
    if B.Kind = ibkImage then W := -2
    else if B.Kind = ibkTable then W := -3
    else if W < 0 then
    begin
      if AShrink or B.Floating or B.Absolute then W := ShrinkToFit(B, Avail)
      else W := Avail;
    end;
  end;
  if B.Kind = ibkImage then
  begin
    Measure.ImageSize(B, IW, IH);
    W := SpecW(B, 'width', ACBW);
    H := SpecH(B, 'height', ACBH);
    Ratio := 0;
    if (IW > 0) and (IH > 0) then Ratio := IW / IH;
    if (W < 0) and (H < 0) then begin W := IW + EdgesH(B); H := IH + EdgesV(B) end
    else if (W >= 0) and (H < 0) then
    begin
      if Ratio > 0 then H := Round((W - EdgesH(B)) / Ratio) + EdgesV(B) else H := EdgesV(B);
    end
    else if (W < 0) and (H >= 0) then
      W := Round((H - EdgesV(B)) * Ratio) + EdgesH(B);
    { max-width, the way "img { max-width: 100% }" keeps a picture in its
      column, and the shape kept when the height was left alone }
    IW := ClampW(B, W, ACBW);
    if (IW <> W) and IsAuto(B.Style, 'height') and (Ratio > 0) then
      H := Round((IW - EdgesH(B)) / Ratio) + EdgesV(B);
    W := IW;
    H := ClampH(B, H, ACBH);
  end
  else if B.Kind = ibkTable then
  begin
    { a percentage is of the containing block; the room is what the
      margins leave }
    if AForceW >= 0 then W := AForceW else TableWidth(B, Avail, W, ACBW);
  end
  else W := ClampW(B, W, ACBW);
  { inside the old <center>, a block narrower than its room is centred as
    if its margins were auto, the way WebKit treats -webkit-center }
  if not B.Anon and not MarginAutoL and not MarginAutoR and (B.Parent <> nil) then
  begin
    TA := B.Parent.Style.Keyword('text-align');
    if TA = '-webkit-center' then begin MarginAutoL := True; MarginAutoR := True end
    else if TA = '-webkit-right' then MarginAutoL := True;
  end;
  { auto margins center a box with a width }
  if (not B.Anon) and not B.Floating and not B.Absolute and (Avail > W) and
    (MarginAutoL or MarginAutoR) and (AForceW < 0) then
  begin
    AutoL := 0; AutoR := 0;
    if MarginAutoL and MarginAutoR then
    begin
      AutoL := (ACBW - W - B.Margin.Left - B.Margin.Right) div 2;
      AutoR := AutoL;
    end
    else if MarginAutoL then AutoL := ACBW - W - B.Margin.Left - B.Margin.Right
    else AutoR := ACBW - W - B.Margin.Left - B.Margin.Right;
    Inc(B.Margin.Left, Max(0, AutoL)); Inc(B.Margin.Right, Max(0, AutoR));
  end;
  B.X := AX + B.Margin.Left;
  B.Y := AY;
  B.W := Max(0, W);
  B.H := 0;
  if B.Kind = ibkImage then
  begin
    B.H := H;
    Exit;
  end;
  { a context of its own keeps its floats in }
  Own := nil;
  if IsBFC(B) or (AFloats = nil) then Own := TFloats.Create;
  try
    if Own <> nil then AFloats := Own;
    SH := SpecH(B, 'height', ACBH);
    case B.Kind of
      ibkText:
        begin
          B.TextX := B.ContentX; B.TextY := B.ContentY; B.TextW := B.ContentW;
          AFloats.Room(B.ContentY, B.ContentY + 1, B.ContentX, B.ContentX + B.ContentW, L, R);
          { beside a float the words have the room it leaves; with too
            little room they start below it }
          MinT := 0;
          if R - L < B.ContentW then
          begin
            if R - L < Min(B.ContentW, 60) then
            begin
              MinT := AFloats.NextBottom(B.ContentY) - B.ContentY;
              AFloats.Room(B.ContentY + MinT, B.ContentY + MinT + 1, B.ContentX,
                B.ContentX + B.ContentW, L, R);
            end;
            B.TextX := L; B.TextW := Max(1, R - L); B.TextY := B.ContentY + MinT;
          end;
          ContentH := MinT + Measure.TextHeight(B, B.TextW);
        end;
      ibkFlex: ContentH := LayFlex(B);
      ibkGrid: ContentH := LayGrid(B);
      ibkTable: ContentH := LayTable(B, B.W, ACBW);
      ibkRow:
        ContentH := 0;
    else
      ContentH := FlowKids(B, AFloats);
    end;
    { a context of its own grows to hold its floats }
    if (Own <> nil) and (Length(Own.Rects) > 0) then
      ContentH := Max(ContentH, Own.Bottom(True, True) - B.ContentY);
    if (SH >= 0) and (B.Kind <> ibkTable) and
      ((Pos(B.Style.Keyword('overflow-y'), 'auto scroll') = 0) or (B.Anon)) then
      B.H := ClampH(B, SH, ACBH)
    else B.H := ClampH(B, ContentH + EdgesV(B), ACBH);
  finally Own.Free end;
end;

{ ---------------------------------------------------------------- flex }

type
  TFlexItem = record
    Box: TInkBox;
    Base, Main, MinMain, MaxMain, Grow, Shrink: Double;
    Outer: Integer;
    Order: Integer;
  end;

function TFlow.LayFlex(B: TInkBox): Integer;
var Items: array of TFlexItem; I, J, N, First_, Last_, LineH, Y, CW, Gap, RowGap, Used, X,
  KMin, KMax, Free_, AutoCount, Cross, CH: Integer; Row, Wrap, Reverse, Definite: Boolean;
  Basis, Justify, Align, Sp: string; T: TFlexItem; Total, Share, Lead, Between: Double;
  K: TInkBox; Sum: Double;

  procedure Order_;
  var A, Z: Integer; Tmp: TFlexItem;
  begin
    for A := 1 to N - 1 do
    begin
      Tmp := Items[A]; Z := A - 1;
      while (Z >= 0) and (Items[Z].Order > Tmp.Order) do begin Items[Z + 1] := Items[Z]; Dec(Z) end;
      Items[Z + 1] := Tmp;
    end;
  end;

  { the standard's way of sharing out free room: grow or shrink the items
    that may, and an item that hits its minimum or maximum is frozen there
    while the rest share what is left }
  procedure Resolve(A, Z, AUsed: Integer);
  var Q, Round_: Integer; Frozen: array of Boolean; Free2, Tot, Want: Double; Growing, Any: Boolean;
  begin
    SetLength(Frozen, Z - A + 1);
    Growing := CW - AUsed > 0;
    for Q := A to Z do
    begin
      Items[Q].Main := Items[Q].Base;
      Frozen[Q - A] := (Growing and (Items[Q].Grow = 0)) or (not Growing and (Items[Q].Shrink = 0));
    end;
    for Round_ := 1 to Z - A + 2 do
    begin
      { the room left with frozen items where they are, the others at
        their base }
      Free2 := CW - Gap * (Z - A);
      Tot := 0;
      for Q := A to Z do
      begin
        Free2 := Free2 - Items[Q].Box.Margin.Left - Items[Q].Box.Margin.Right;
        if Frozen[Q - A] then Free2 := Free2 - Items[Q].Main
        else
        begin
          Free2 := Free2 - Items[Q].Base;
          if Growing then Tot := Tot + Items[Q].Grow else Tot := Tot + Items[Q].Shrink * Items[Q].Base;
        end;
      end;
      if (Tot <= 0) or (Growing and (Free2 <= 0)) or (not Growing and (Free2 >= 0)) then Break;
      Any := False;
      for Q := A to Z do
        if not Frozen[Q - A] then
        begin
          if Growing then Want := Items[Q].Base + Free2 * Items[Q].Grow / Tot
          else Want := Items[Q].Base + Free2 * Items[Q].Shrink * Items[Q].Base / Tot;
          if Want < Items[Q].MinMain then begin Want := Items[Q].MinMain; Frozen[Q - A] := True; Any := True end
          else if Want > Items[Q].MaxMain then begin Want := Items[Q].MaxMain; Frozen[Q - A] := True; Any := True end;
          Items[Q].Main := Want;
        end;
      if not Any then Break;
    end;
    for Q := A to Z do
      Items[Q].Main := Max(Items[Q].MinMain, Min(Items[Q].MaxMain, Items[Q].Main));
  end;

  function AlignOf(AItem: TInkBox): string;
  begin
    Result := '';
    if not AItem.Anon then Result := AItem.Style.Keyword('align-self');
    if (Result = '') or (Result = 'auto') then Result := B.Style.Keyword('align-items');
    if (Result = 'normal') or (Result = '') then Result := 'stretch';
  end;

begin
  CW := B.ContentW;
  Row := Pos('column', B.Style.Keyword('flex-direction')) = 0;
  Reverse := Pos('reverse', B.Style.Keyword('flex-direction')) > 0;
  Wrap := B.Style.Keyword('flex-wrap') <> 'nowrap';
  Gap := Len(B.Style, 'column-gap', CW, 0);
  RowGap := Len(B.Style, 'row-gap', CW, 0);
  Justify := B.Style.Keyword('justify-content');
  Items := nil; N := 0;
  for I := 0 to B.Count - 1 do
  begin
    K := B[I];
    if K.Absolute then
    begin
      K.StaticX := B.ContentX; K.StaticY := B.ContentY;
      Absolutes.Add(K);
      Continue;
    end;
    SetLength(Items, N + 1);
    Items[N] := Default(TFlexItem);
    Items[N].Box := K;
    Items[N].Order := 0;
    if not K.Anon then Items[N].Order := StrToIntDef(K.Style.Keyword('order'), 0);
    Inc(N);
  end;
  Order_;
  if Reverse then
    for I := 0 to N div 2 - 1 do
    begin
      T := Items[I]; Items[I] := Items[N - 1 - I]; Items[N - 1 - I] := T;
    end;
  if not Row then
  begin
    { a column: one under another, as wide as the container unless they
      align elsewhere }
    Y := B.ContentY;
    Definite := SpecH(B, 'height', -1) >= 0;
    for I := 0 to N - 1 do
    begin
      K := Items[I].Box;
      Edges(K, CW);
      Align := AlignOf(K);
      if (Align = 'stretch') and IsAuto(K.Style, 'width') then
        LayBox(K, B.ContentX, Y + K.Margin.Top, CW, -1, nil, CW - K.Margin.Left - K.Margin.Right)
      else
      begin
        LayBox(K, B.ContentX, Y + K.Margin.Top, CW, -1, nil, -1, True);
        if (Align = 'center') or (Align = 'end') or (Align = 'flex-end') then
        begin
          Free_ := CW - K.W - K.Margin.Left - K.Margin.Right;
          if Align = 'center' then K.Shift(Free_ div 2, 0) else K.Shift(Free_, 0);
        end;
      end;
      Relative(K, CW);
      Y := K.Y + K.H + K.Margin.Bottom;
      if I < N - 1 then Inc(Y, RowGap);
    end;
    Result := Y - B.ContentY;
    { the free room of a container with a height goes where justify says }
    if Definite and (N > 0) then
    begin
      Free_ := SpecH(B, 'height', -1) - EdgesV(B) - Result;
      if Free_ > 0 then
      begin
        Sum := 0;
        for I := 0 to N - 1 do
          if not Items[I].Box.Anon then
            Sum := Sum + StrToFloatDef(Items[I].Box.Style.Keyword('flex-grow'), 0);
        if Sum > 0 then
        begin
          Lead := 0;
          for I := 0 to N - 1 do
          begin
            K := Items[I].Box;
            K.Shift(0, Round(Lead));
            if not K.Anon then
            begin
              Share := Free_ * StrToFloatDef(K.Style.Keyword('flex-grow'), 0) / Sum;
              Inc(K.H, Round(Share)); Lead := Lead + Share;
            end;
          end;
        end
        else if (Justify = 'center') or (Justify = 'end') or (Justify = 'flex-end') then
          for I := 0 to N - 1 do
            if Justify = 'center' then Items[I].Box.Shift(0, Free_ div 2)
            else Items[I].Box.Shift(0, Free_);
      end;
    end;
    Exit;
  end;
  { a row: each item's base width }
  for I := 0 to N - 1 do
  begin
    K := Items[I].Box;
    Edges(K, CW);
    Basis := '';
    if not K.Anon then Basis := K.Style.Keyword('flex-basis');
    ContentWidths(K, KMin, KMax);
    Items[I].Base := -1;
    if (Basis <> '') and (Basis <> 'auto') and (Basis <> 'content') then
    begin
      Items[I].Base := Len(K.Style, 'flex-basis', CW, -1);
      if (Items[I].Base >= 0) and not BorderBoxSizing(K) then
        Items[I].Base := Items[I].Base + EdgesH(K);
    end;
    if Items[I].Base < 0 then Items[I].Base := SpecW(K, 'width', CW);
    if Items[I].Base < 0 then Items[I].Base := KMax;
    Items[I].MinMain := SpecW(K, 'min-width', CW);
    if Items[I].MinMain < 0 then
    begin
      { the automatic minimum: no narrower than its content's narrowest -
        unless it scrolls or hides what does not fit }
      if (not K.Anon) and (Pos(K.Style.Keyword('overflow-x'), 'visible clip') > 0) then
        Items[I].MinMain := Min(KMin, Items[I].Base)
      else Items[I].MinMain := EdgesH(K);
    end;
    Items[I].MaxMain := SpecW(K, 'max-width', CW);
    if Items[I].MaxMain < 0 then Items[I].MaxMain := MaxInt;
    Items[I].Grow := 0; Items[I].Shrink := 1;
    if not K.Anon then
    begin
      Items[I].Grow := StrToFloatDef(K.Style.Keyword('flex-grow'), 0);
      Items[I].Shrink := StrToFloatDef(K.Style.Keyword('flex-shrink'), 1);
    end;
    Items[I].Main := Max(Items[I].MinMain, Min(Items[I].MaxMain, Items[I].Base));
    Items[I].Outer := Round(Items[I].Main) + K.Margin.Left + K.Margin.Right;
  end;
  Y := B.ContentY;
  First_ := 0;
  while First_ < N do
  begin
    { a line: as many as fit, or all of them when it does not wrap }
    Last_ := First_; Used := Items[First_].Outer;
    if Wrap then
      while (Last_ + 1 < N) and (Used + Gap + Items[Last_ + 1].Outer <= CW) do
      begin
        Inc(Last_); Inc(Used, Gap + Items[Last_].Outer);
      end
    else
    begin
      Last_ := N - 1; Used := 0;
      for I := First_ to Last_ do
      begin
        Inc(Used, Items[I].Outer);
        if I > First_ then Inc(Used, Gap);
      end;
    end;
    Resolve(First_, Last_, Used);
    { the room still free after growing, and the auto margins that take it }
    Used := 0; AutoCount := 0;
    for I := First_ to Last_ do
    begin
      K := Items[I].Box;
      Inc(Used, Round(Items[I].Main) + K.Margin.Left + K.Margin.Right);
      if I > First_ then Inc(Used, Gap);
      if not K.Anon then
      begin
        if IsAuto(K.Style, 'margin-left') then Inc(AutoCount);
        if IsAuto(K.Style, 'margin-right') then Inc(AutoCount);
      end;
    end;
    Free_ := Max(0, CW - Used);
    Lead := 0; Between := 0;
    if (AutoCount = 0) and (Free_ > 0) then
    begin
      Sp := Justify;
      J := Last_ - First_ + 1;
      if (Sp = 'center') then Lead := Free_ / 2
      else if (Sp = 'end') or (Sp = 'flex-end') or (Sp = 'right') then Lead := Free_
      else if (Sp = 'space-between') and (J > 1) then Between := Free_ / (J - 1)
      else if Sp = 'space-around' then begin Between := Free_ / J; Lead := Between / 2 end
      else if Sp = 'space-evenly' then begin Between := Free_ / (J + 1); Lead := Between end;
    end;
    { each item at its width, and the line as tall as the tallest }
    LineH := 0;
    Sum := B.ContentX + Lead;
    for I := First_ to Last_ do
    begin
      K := Items[I].Box;
      if (AutoCount > 0) and (not K.Anon) and IsAuto(K.Style, 'margin-left') then
        Sum := Sum + Free_ / AutoCount;
      LayBox(K, Round(Sum), Y + K.Margin.Top, CW, -1, nil, Round(Items[I].Main));
      Sum := Sum + Items[I].Main + K.Margin.Left + K.Margin.Right + Gap + Between;
      if (AutoCount > 0) and (not K.Anon) and IsAuto(K.Style, 'margin-right') then
        Sum := Sum + Free_ / AutoCount;
      LineH := Max(LineH, K.H + K.Margin.Top + K.Margin.Bottom);
    end;
    if (not Wrap) and (SpecH(B, 'height', -1) >= 0) then
      LineH := Max(LineH, SpecH(B, 'height', -1) - EdgesV(B));
    { across the line: stretched, or where align puts it }
    for I := First_ to Last_ do
    begin
      K := Items[I].Box;
      Align := AlignOf(K);
      Cross := LineH - K.H - K.Margin.Top - K.Margin.Bottom;
      if Cross > 0 then
      begin
        if (Align = 'stretch') and ((K.Anon) or IsAuto(K.Style, 'height')) then
        begin
          CH := K.H;
          K.H := ClampH(K, LineH - K.Margin.Top - K.Margin.Bottom, -1);
          if (K.Kind = ibkText) and (K.H > CH) then ;
        end
        else if Align = 'center' then K.Shift(0, Cross div 2)
        else if (Align = 'end') or (Align = 'flex-end') or (Align = 'self-end') then K.Shift(0, Cross);
      end;
      Relative(K, CW);
    end;
    Inc(Y, LineH);
    First_ := Last_ + 1;
    if First_ < N then Inc(Y, RowGap);
  end;
  Result := Y - B.ContentY;
end;

{ ---------------------------------------------------------------- grid }

type
  TTrackKind = (tkFixed, tkFr, tkAuto);
  TTrack = record
    Kind: TTrackKind;
    Size, Fr, MinSize: Double;
    { minmax(min, length): starts at its minimum and grows toward Size
      with what the other tracks' minimums leave }
    Grows: Boolean;
    { auto and minmax tracks: grown to their content }
    Used: Double;
  end;
  TTracks = array of TTrack;

  TGridItem = record
    Box: TInkBox;
    Row, Col, RowSpan, ColSpan: Integer;
  end;

  TArea = record
    Name: string;
    Row1, Col1, Row2, Col2: Integer;
  end;

{ the words of a track list, brackets kept whole: "repeat(3, 1fr)" is one }
function TrackWords(const S: string): TStringArray;
var P, Start, Depth, N: Integer;
begin
  Result := nil; N := 0; P := 1;
  while P <= Length(S) do
  begin
    while (P <= Length(S)) and (S[P] in [' ', #9, #10, #13]) do Inc(P);
    if P > Length(S) then Break;
    Start := P; Depth := 0;
    if S[P] = '[' then
    begin
      { line names are only names }
      while (P <= Length(S)) and (S[P] <> ']') do Inc(P);
      Inc(P);
      Continue;
    end;
    while (P <= Length(S)) and ((Depth > 0) or not (S[P] in [' ', #9, #10, #13])) do
    begin
      if S[P] = '(' then Inc(Depth) else if S[P] = ')' then Dec(Depth);
      Inc(P);
    end;
    SetLength(Result, N + 1); Result[N] := Copy(S, Start, P - Start); Inc(N);
  end;
end;

function ParseTrack(S: TInkStyle; const W: string; ACW: Integer): TTrack;
var L, A, B_: string; K: Integer;
begin
  Result := Default(TTrack);
  L := LowerCase(Trim(W));
  if Copy(L, 1, 7) = 'minmax(' then
  begin
    K := Pos(',', L);
    A := Trim(Copy(L, 8, K - 8)); B_ := Trim(Copy(L, K + 1, Length(L) - K - 1));
    Result := ParseTrack(S, B_, ACW);
    if (A <> 'auto') and (A <> 'min-content') and (A <> 'max-content') then
      Result.MinSize := Max(0, S.Length(A, ACW, 0));
    if Result.Kind = tkFixed then
    begin
      Result.Size := Max(Result.Size, Result.MinSize);
      Result.Grows := Result.MinSize < Result.Size;
    end;
    Exit;
  end;
  if Copy(L, 1, 12) = 'fit-content(' then begin Result.Kind := tkAuto; Exit end;
  if (L <> '') and (L[Length(L)] = 'r') and (Copy(L, Length(L) - 1, 2) = 'fr') then
  begin
    Result.Kind := tkFr;
    Result.Fr := StrToFloatDef(Copy(L, 1, Length(L) - 2), 1, DefaultFormatSettings);
    if Pos('.', L) > 0 then
      Result.Fr := StrToFloatDef(StringReplace(Copy(L, 1, Length(L) - 2), '.',
        DefaultFormatSettings.DecimalSeparator, []), 1);
    Exit;
  end;
  if (L = 'auto') or (L = 'min-content') or (L = 'max-content') then
  begin
    Result.Kind := tkAuto; Exit;
  end;
  Result.Kind := tkFixed;
  Result.Size := Max(0, S.Length(L, ACW, 0));
end;

{ grid-template-columns as tracks, repeat() unrolled - auto-fill making as
  many as fit }
function ParseTracks(S: TInkStyle; const AProp: string; ACW, AGap, AItems: Integer): TTracks;
var Words, Inner: TStringArray; I, J, K, N, Times: Integer; L, Arg, Head: string;
  T: TTrack; Each: Double; Fit: Boolean;
  procedure Push(const AT: TTrack);
  begin
    SetLength(Result, N + 1); Result[N] := AT; Inc(N);
  end;
begin
  Result := nil; N := 0;
  L := S.Value(AProp);
  if (LowerCase(Trim(L)) = 'none') or (Trim(L) = '') or (Pos('subgrid', LowerCase(L)) > 0) or
    (Pos('masonry', LowerCase(L)) > 0) then Exit;
  Words := TrackWords(L);
  for I := 0 to High(Words) do
  begin
    if LowerCase(Copy(Words[I], 1, 7)) = 'repeat(' then
    begin
      Arg := Copy(Words[I], 8, Length(Words[I]) - 8);
      K := Pos(',', Arg);
      Head := LowerCase(Trim(Copy(Arg, 1, K - 1)));
      Inner := TrackWords(Trim(Copy(Arg, K + 1, MaxInt)));
      if (Head = 'auto-fill') or (Head = 'auto-fit') then
      begin
        { as many as fit at their smallest }
        Each := 0;
        for J := 0 to High(Inner) do
        begin
          T := ParseTrack(S, Inner[J], ACW);
          if T.Kind = tkFixed then Each := Each + T.Size else Each := Each + Max(T.MinSize, 1);
        end;
        Each := Each + AGap * Length(Inner);
        Times := Max(1, Trunc((ACW + AGap) / Max(1, Each)));
        Fit := Head = 'auto-fit';
        { auto-fit lets the empty ones go, so the items stretch }
        if Fit and (AItems > 0) then Times := Max(1, Min(Times, AItems));
      end
      else Times := Max(1, StrToIntDef(Head, 1));
      for K := 1 to Times do
        for J := 0 to High(Inner) do
        begin
          T := ParseTrack(S, Inner[J], ACW);
          { a minmax(200px, 1fr) repeated to fill is that 1fr, at least 200 }
          Push(T);
        end;
    end
    else Push(ParseTrack(S, Words[I], ACW));
  end;
end;

procedure ParseAreas(S: TInkStyle; out AAreas: array of TArea; out ACount, ARows, ACols: Integer);
var V: string; Rows: TStringList; P, Q, R, C, I: Integer; Cells: TStringArray; Found: Boolean;
  Tmp: array of TArea;
begin
  ACount := 0; ARows := 0; ACols := 0;
  V := S.Value('grid-template-areas');
  if (V = '') or (LowerCase(Trim(V)) = 'none') then Exit;
  Rows := TStringList.Create;
  try
    P := 1;
    while P <= Length(V) do
    begin
      if V[P] in ['"', ''''] then
      begin
        Q := P + 1;
        while (Q <= Length(V)) and (V[Q] <> V[P]) do Inc(Q);
        Rows.Add(Copy(V, P + 1, Q - P - 1));
        P := Q;
      end;
      Inc(P);
    end;
    ARows := Rows.Count;
    Tmp := nil;
    for R := 0 to Rows.Count - 1 do
    begin
      Cells := Rows[R].Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      ACols := Max(ACols, Length(Cells));
      for C := 0 to High(Cells) do
      begin
        if Copy(Cells[C], 1, 1) = '.' then Continue;
        Found := False;
        for I := 0 to High(Tmp) do
          if Tmp[I].Name = Cells[C] then
          begin
            Tmp[I].Row2 := Max(Tmp[I].Row2, R + 2); Tmp[I].Col2 := Max(Tmp[I].Col2, C + 2);
            Tmp[I].Row1 := Min(Tmp[I].Row1, R + 1); Tmp[I].Col1 := Min(Tmp[I].Col1, C + 1);
            Found := True;
          end;
        if not Found then
        begin
          SetLength(Tmp, Length(Tmp) + 1);
          Tmp[High(Tmp)].Name := Cells[C];
          Tmp[High(Tmp)].Row1 := R + 1; Tmp[High(Tmp)].Col1 := C + 1;
          Tmp[High(Tmp)].Row2 := R + 2; Tmp[High(Tmp)].Col2 := C + 2;
        end;
      end;
    end;
    for I := 0 to Min(High(Tmp), High(AAreas)) do AAreas[I] := Tmp[I];
    ACount := Min(Length(Tmp), Length(AAreas));
  finally Rows.Free end;
end;

function TFlow.LayGrid(B: TInkBox): Integer;
var Cols, Rows: TTracks; Items: array of TGridItem; I, J, K, N, CW, CGap, RGap, NCols, NRows, R, C,
  Need, KMin, KMax, X, Y, AreaW, AreaH, AreaCount, ARows, ACols: Integer;
  Taken: array of array of Boolean; Free_, FrSum, Fixed, Span, Grow, Spare: Double;
  ColX, RowY: array of Integer; Areas: array[0..63] of TArea; S: TInkStyle; Placed: Boolean;
  Align, Justify, V: string; Box: TInkBox; Dense, ColumnFlow: Boolean;

  { a line or span from grid-row-start / -end and the like }
  procedure Line(const AStart, AEnd: string; ACount: Integer; out APos, ASpan: Integer; ARow: Boolean);
  var A, Z: string; I1, I2, A_: Integer;
    function Num(const T: string; out V: Integer): Boolean;
    begin
      Result := TryStrToInt(T, V);
      if Result and (V < 0) then V := ACount + 2 + V;
    end;
    function AreaLine(const T: string; AStartSide: Boolean; out V: Integer): Boolean;
    var Q: Integer; Nm: string;
    begin
      Result := False; Nm := T;
      if Copy(Nm, Length(Nm) - 5, 6) = '-start' then Nm := Copy(Nm, 1, Length(Nm) - 6)
      else if Copy(Nm, Length(Nm) - 3, 4) = '-end' then begin Nm := Copy(Nm, 1, Length(Nm) - 4); AStartSide := False end;
      for Q := 0 to AreaCount - 1 do
        if Areas[Q].Name = Nm then
        begin
          if ARow then begin if AStartSide then V := Areas[Q].Row1 else V := Areas[Q].Row2 end
          else begin if AStartSide then V := Areas[Q].Col1 else V := Areas[Q].Col2 end;
          Exit(True);
        end;
    end;
  begin
    A := LowerCase(Trim(AStart)); Z := LowerCase(Trim(AEnd));
    APos := 0; ASpan := 1;
    if Copy(A, 1, 5) = 'span ' then
    begin
      ASpan := Max(1, StrToIntDef(Trim(Copy(A, 6, MaxInt)), 1)); A := 'auto';
    end;
    if Num(A, I1) then APos := I1
    else if (A <> 'auto') and (A <> '') and AreaLine(A, True, I1) then APos := I1;
    if Copy(Z, 1, 5) = 'span ' then ASpan := Max(1, StrToIntDef(Trim(Copy(Z, 6, MaxInt)), 1))
    else if Num(Z, I2) then
    begin
      if APos > 0 then ASpan := Max(1, I2 - APos)
      else begin ASpan := 1; APos := Max(1, I2 - 1) end;
    end
    else if (Z <> 'auto') and (Z <> '') and AreaLine(Z, False, I2) then
    begin
      if APos > 0 then ASpan := Max(1, I2 - APos);
    end
    else if (A <> 'auto') and (A <> '') and not TryStrToInt(A, A_) and AreaLine(A, False, I2) and (APos > 0) then
      ASpan := Max(1, I2 - APos);
  end;

  function IsFree(AR, AC, ARS, ACS: Integer): Boolean;
  var R2, C2: Integer;
  begin
    if AC + ACS - 1 > NCols then Exit(False);
    for R2 := AR to AR + ARS - 1 do
      for C2 := AC to AC + ACS - 1 do
        if (R2 <= High(Taken)) and Taken[R2][C2] then Exit(False);
    Result := True;
  end;

  procedure Take(AR, AC, ARS, ACS: Integer);
  var R2, C2: Integer;
  begin
    while High(Taken) < AR + ARS do
    begin
      SetLength(Taken, Length(Taken) + 1);
      SetLength(Taken[High(Taken)], NCols + 2);
    end;
    for R2 := AR to AR + ARS - 1 do
      for C2 := AC to AC + ACS - 1 do Taken[R2][C2] := True;
  end;

begin
  S := B.Style;
  CW := B.ContentW;
  CGap := Len(S, 'column-gap', CW, 0);
  RGap := Len(S, 'row-gap', CW, 0);
  Items := nil; N := 0;
  for I := 0 to B.Count - 1 do
  begin
    if B[I].Absolute then
    begin
      B[I].StaticX := B.ContentX; B[I].StaticY := B.ContentY;
      Absolutes.Add(B[I]);
      Continue;
    end;
    SetLength(Items, N + 1);
    Items[N].Box := B[I]; Inc(N);
  end;
  Cols := ParseTracks(S, 'grid-template-columns', CW, CGap, N);
  Rows := ParseTracks(S, 'grid-template-rows', -1, RGap, 0);
  ParseAreas(S, Areas, AreaCount, ARows, ACols);
  NCols := Max(Length(Cols), ACols);
  ColumnFlow := Pos('column', S.Keyword('grid-auto-flow')) > 0;
  Dense := Pos('dense', S.Keyword('grid-auto-flow')) > 0;
  { where each item goes: what it names first, then the free cells in turn }
  for I := 0 to N - 1 do
  begin
    Box := Items[I].Box;
    if not Box.Anon then
    begin
      V := Box.Style.Keyword('grid-row-start');
      if (AreaCount > 0) and (V <> 'auto') and (Box.Style.Keyword('grid-column-start') = 'auto') and
        (Box.Style.Keyword('grid-row-end') = 'auto') then
      begin
        { grid-area: name sets all four to the name }
        Line(V, V + '-end', NRows, Items[I].Row, Items[I].RowSpan, True);
        Line(V, V + '-end', NCols, Items[I].Col, Items[I].ColSpan, False);
      end
      else
      begin
        Line(V, Box.Style.Keyword('grid-row-end'), Max(Length(Rows), ARows), Items[I].Row, Items[I].RowSpan, True);
        Line(Box.Style.Keyword('grid-column-start'), Box.Style.Keyword('grid-column-end'),
          NCols, Items[I].Col, Items[I].ColSpan, False);
      end;
    end
    else
    begin
      Items[I].Row := 0; Items[I].Col := 0; Items[I].RowSpan := 1; Items[I].ColSpan := 1;
    end;
    if Items[I].Col > 0 then NCols := Max(NCols, Items[I].Col + Items[I].ColSpan - 1);
    NCols := Max(NCols, Items[I].ColSpan);
  end;
  NCols := Max(1, NCols);
  while Length(Cols) < NCols do
  begin
    SetLength(Cols, Length(Cols) + 1);
    Cols[High(Cols)] := ParseTrack(S, S.Value('grid-auto-columns'), CW);
  end;
  Taken := nil;
  for I := 0 to N - 1 do
    if (Items[I].Row > 0) and (Items[I].Col > 0) then
      Take(Items[I].Row, Items[I].Col, Items[I].RowSpan, Items[I].ColSpan);
  R := 1; C := 1;
  for I := 0 to N - 1 do
  begin
    if (Items[I].Row > 0) and (Items[I].Col > 0) then Continue;
    if Dense then begin R := 1; C := 1 end;
    Placed := False;
    if Items[I].Row > 0 then
    begin
      { a row named, the column found }
      C := 1;
      while not IsFree(Items[I].Row, C, Items[I].RowSpan, Items[I].ColSpan) and (C <= NCols) do Inc(C);
      if C > NCols then C := 1;
      Items[I].Col := C;
      Placed := True;
    end
    else if Items[I].Col > 0 then
    begin
      R := 1;
      while not IsFree(R, Items[I].Col, Items[I].RowSpan, Items[I].ColSpan) do Inc(R);
      Items[I].Row := R;
      Placed := True;
    end;
    if not Placed then
    begin
      repeat
        if IsFree(R, C, Items[I].RowSpan, Items[I].ColSpan) then Break;
        Inc(C);
        if C + Items[I].ColSpan - 1 > NCols then begin C := 1; Inc(R) end;
      until False;
      Items[I].Row := R; Items[I].Col := C;
    end;
    Take(Items[I].Row, Items[I].Col, Items[I].RowSpan, Items[I].ColSpan);
    if not Placed then
    begin
      Inc(C, Items[I].ColSpan);
      if C > NCols then begin C := 1; Inc(R) end;
    end;
  end;
  if ColumnFlow then ;
  NRows := Max(Length(Rows), ARows);
  for I := 0 to N - 1 do NRows := Max(NRows, Items[I].Row + Items[I].RowSpan - 1);
  while Length(Rows) < NRows do
  begin
    SetLength(Rows, Length(Rows) + 1);
    Rows[High(Rows)] := ParseTrack(S, S.Value('grid-auto-rows'), -1);
  end;
  { the columns: fixed ones as they are, auto ones as wide as their
    content, and what is left shared out by fr }
  for J := 0 to NCols - 1 do
    if Cols[J].Grows then Cols[J].Used := Cols[J].MinSize
    else Cols[J].Used := Max(Cols[J].MinSize, Cols[J].Size);
  for I := 0 to N - 1 do
    if Items[I].ColSpan = 1 then
    begin
      J := Items[I].Col - 1;
      if Cols[J].Kind = tkAuto then
      begin
        Widths(Items[I].Box, KMin, KMax);
        Edges(Items[I].Box, CW);
        Cols[J].Used := Max(Cols[J].Used, KMax + Items[I].Box.Margin.Left + Items[I].Box.Margin.Right);
      end;
    end;
  Fixed := CGap * (NCols - 1); FrSum := 0;
  for J := 0 to NCols - 1 do
    if Cols[J].Kind = tkFr then FrSum := FrSum + Cols[J].Fr
    else Fixed := Fixed + Cols[J].Used;
  Free_ := CW - Fixed;
  { what the minimums leave goes first to the tracks that may grow, evenly,
    each up to its limit; fr tracks share what is left after that }
  Spare := Free_;
  for J := 0 to NCols - 1 do if Cols[J].Kind = tkFr then Spare := Spare - Cols[J].MinSize;
  while Spare > 0.5 do
  begin
    K := 0;
    for J := 0 to NCols - 1 do if Cols[J].Grows and (Cols[J].Used < Cols[J].Size) then Inc(K);
    if K = 0 then Break;
    Grow := Spare / K;
    for J := 0 to NCols - 1 do
      if Cols[J].Grows and (Cols[J].Used < Cols[J].Size) then
      begin
        Span := Min(Grow, Cols[J].Size - Cols[J].Used);
        Cols[J].Used := Cols[J].Used + Span;
        Spare := Spare - Span; Free_ := Free_ - Span;
      end;
  end;
  if FrSum > 0 then
  begin
    for J := 0 to NCols - 1 do
      if Cols[J].Kind = tkFr then Cols[J].Used := Max(Cols[J].MinSize, Max(0, Free_) * Cols[J].Fr / FrSum);
  end
  else if Free_ > 0 then
  begin
    { auto columns stretch into what is left }
    K := 0;
    for J := 0 to NCols - 1 do if Cols[J].Kind = tkAuto then Inc(K);
    if (K > 0) and (Pos(S.Keyword('justify-content'), 'normal stretch') > 0) then
      for J := 0 to NCols - 1 do
        if Cols[J].Kind = tkAuto then Cols[J].Used := Cols[J].Used + Free_ / K;
  end
  else if Free_ < 0 then
  begin
    { too wide: the auto columns give way first }
    Need := -Round(Free_); Grow := 0;
    for J := 0 to NCols - 1 do if Cols[J].Kind = tkAuto then Grow := Grow + Cols[J].Used;
    if Grow > 0 then
      for J := 0 to NCols - 1 do
        if Cols[J].Kind = tkAuto then Cols[J].Used := Max(0, Cols[J].Used - Need * Cols[J].Used / Grow);
  end;
  SetLength(ColX, NCols + 1);
  ColX[0] := B.ContentX;
  for J := 0 to NCols - 1 do ColX[J + 1] := ColX[J] + Round(Cols[J].Used) + CGap;
  { each item at its area's width; rows as tall as their tallest }
  for J := 0 to NRows - 1 do Rows[J].Used := Rows[J].Size;
  for I := 0 to N - 1 do
  begin
    Box := Items[I].Box;
    AreaW := ColX[Items[I].Col - 1 + Items[I].ColSpan] - ColX[Items[I].Col - 1] - CGap;
    Edges(Box, AreaW);
    Justify := '';
    if not Box.Anon then Justify := Box.Style.Keyword('justify-self');
    if (Justify = '') or (Justify = 'auto') then Justify := S.Keyword('justify-items');
    if (Justify = 'normal') or (Justify = 'legacy') or (Justify = '') then Justify := 'stretch';
    if (Justify = 'stretch') and ((Box.Anon) or IsAuto(Box.Style, 'width')) and (Box.Kind <> ibkImage) then
      LayBox(Box, ColX[Items[I].Col - 1], 0, AreaW, -1, nil, AreaW - Box.Margin.Left - Box.Margin.Right)
    else
    begin
      LayBox(Box, ColX[Items[I].Col - 1], 0, AreaW, -1, nil, -1, True);
      if (Justify = 'center') or (Justify = 'end') or (Justify = 'right') then
      begin
        K := AreaW - Box.W - Box.Margin.Left - Box.Margin.Right;
        if Justify = 'center' then Box.Shift(K div 2, 0) else Box.Shift(K, 0);
      end;
    end;
    if (Items[I].RowSpan = 1) and (Rows[Items[I].Row - 1].Kind <> tkFixed) then
      Rows[Items[I].Row - 1].Used := Max(Rows[Items[I].Row - 1].Used,
        Box.H + Box.Margin.Top + Box.Margin.Bottom);
  end;
  { an item across several rows makes the last of them tall enough }
  for I := 0 to N - 1 do
    if Items[I].RowSpan > 1 then
    begin
      Box := Items[I].Box;
      Span := RGap * (Items[I].RowSpan - 1);
      for J := Items[I].Row - 1 to Items[I].Row + Items[I].RowSpan - 2 do Span := Span + Rows[J].Used;
      Need := Box.H + Box.Margin.Top + Box.Margin.Bottom - Round(Span);
      if Need > 0 then
        Rows[Items[I].Row + Items[I].RowSpan - 2].Used := Rows[Items[I].Row + Items[I].RowSpan - 2].Used + Need;
    end;
  SetLength(RowY, NRows + 1);
  RowY[0] := B.ContentY;
  for J := 0 to NRows - 1 do RowY[J + 1] := RowY[J] + Round(Rows[J].Used) + RGap;
  for I := 0 to N - 1 do
  begin
    Box := Items[I].Box;
    Y := RowY[Items[I].Row - 1];
    AreaH := RowY[Items[I].Row - 1 + Items[I].RowSpan] - Y - RGap;
    Box.Shift(0, Y + Box.Margin.Top - Box.Y);
    Align := '';
    if not Box.Anon then Align := Box.Style.Keyword('align-self');
    if (Align = '') or (Align = 'auto') then Align := S.Keyword('align-items');
    if (Align = 'normal') or (Align = '') then Align := 'stretch';
    K := AreaH - Box.H - Box.Margin.Top - Box.Margin.Bottom;
    if K > 0 then
    begin
      if (Align = 'stretch') and ((Box.Anon) or IsAuto(Box.Style, 'height')) and (Box.Kind <> ibkImage) then
        Box.H := Box.H + K
      else if Align = 'center' then Box.Shift(0, K div 2)
      else if (Align = 'end') or (Align = 'flex-end') then Box.Shift(0, K);
    end;
    Relative(Box, AreaW);
  end;
  Result := Max(0, RowY[NRows] - RGap - B.ContentY);
  if NRows = 0 then Result := 0;
  X := 0; if X <> 0 then ;
end;

{ --------------------------------------------------------------- tables }

type
  TCellAt = record
    Box: TInkBox;
    Row, Col: Integer;
  end;

{ the rows of a table, through its row groups, and the groups themselves }
procedure TableRows(B: TInkBox; ARows, AGroups, ACaptions: TFPList);
var I: Integer; K: TInkBox;
begin
  for I := 0 to B.Count - 1 do
  begin
    K := B[I];
    if K.Kind = ibkRow then ARows.Add(K)
    else if (not K.Anon) and (K.Style.Keyword('display') = 'table-caption') then ACaptions.Add(K)
    else if (not K.Anon) and (Pos('table-', K.Style.Keyword('display')) = 1) and
      (Pos('group', K.Style.Keyword('display')) > 0) then
    begin
      if Pos('column', K.Style.Keyword('display')) = 0 then
      begin
        AGroups.Add(K);
        TableRows(K, ARows, nil, ACaptions);
      end;
    end
    else if K.Kind = ibkCell then
      { a cell outside any row: a row of its own }
      ARows.Add(K);
  end;
end;

procedure Spacing(B: TInkBox; out AH, AV: Integer);
var W: TStringArray; V: string;
begin
  AH := 0; AV := 0;
  if B.Style.Keyword('border-collapse') = 'collapse' then Exit;
  V := B.Style.Keyword('border-spacing');
  W := V.Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(W) = 0 then Exit;
  AH := Round(B.Style.Length(W[0], 0, 0));
  if Length(W) > 1 then AV := Round(B.Style.Length(W[1], 0, 0)) else AV := AH;
end;

type
  TTableGrid = record
    Cells: array of TCellAt;
    NRows, NCols: Integer;
  end;

procedure GridOf(ARows: TFPList; out G: TTableGrid);
var R, I, C, K, N, RS, CS, Z: Integer; Row, Cell: TInkBox; Taken: array of array of Boolean;
  procedure Grow(ARow, ACol: Integer);
  var Q: Integer;
  begin
    while Length(Taken) <= ARow do SetLength(Taken, Length(Taken) + 1);
    for Q := 0 to High(Taken) do
      if Length(Taken[Q]) <= ACol then SetLength(Taken[Q], ACol + 1);
  end;
begin
  G.Cells := nil; G.NRows := ARows.Count; G.NCols := 0; N := 0;
  Taken := nil;
  for R := 0 to ARows.Count - 1 do
  begin
    Row := TInkBox(ARows[R]);
    C := 0;
    for I := 0 to Row.Count - 1 do
    begin
      Cell := Row[I];
      if Row.Kind = ibkCell then Cell := Row;
      Grow(R, C);
      while (C < Length(Taken[R])) and Taken[R][C] do begin Inc(C); Grow(R, C) end;
      RS := Min(Cell.RowSpan, ARows.Count - R); CS := Cell.ColSpan;
      if RS < 1 then RS := 1;
      for K := R to R + RS - 1 do
        for Z := C to C + CS - 1 do
        begin
          Grow(K, Z);
          Taken[K][Z] := True;
        end;
      SetLength(G.Cells, N + 1);
      G.Cells[N].Box := Cell; G.Cells[N].Row := R; G.Cells[N].Col := C; Inc(N);
      Cell.RowSpan := RS;
      Inc(C, CS);
      G.NCols := Max(G.NCols, C);
      if Row.Kind = ibkCell then Break;
    end;
  end;
end;

{ the columns' narrowest and widest, from the cells over them }
procedure ColumnWidths(F: TFlow; const G: TTableGrid; ACBW: Integer;
  var AMin, AMax: array of Integer; var APercent: array of Double; var AFixed: array of Boolean);
var I, J, KMin, KMax, SumMin, SumMax, CS, Spec: Integer; Cell: TInkBox; P: string;
begin
  for J := 0 to G.NCols - 1 do
  begin
    AMin[J] := 0; AMax[J] := 0; APercent[J] := 0; AFixed[J] := False;
  end;
  { single cells first, then the spanning ones share out what they need }
  for CS := 1 to 2 do
    for I := 0 to High(G.Cells) do
    begin
      Cell := G.Cells[I].Box;
      if (CS = 1) <> (Cell.ColSpan = 1) then Continue;
      F.ContentWidths(Cell, KMin, KMax);
      P := Cell.Style.Keyword('width');
      if (not Cell.Anon) and (Pos('%', P) > 0) and (Cell.ColSpan = 1) then
        APercent[G.Cells[I].Col] := Max(APercent[G.Cells[I].Col], Cell.Style.Length(P, 100, 0));
      if CS = 1 then
      begin
        J := G.Cells[I].Col;
        Spec := SpecW(Cell, 'width', -1);
        if Spec >= 0 then begin KMax := Max(KMin, Spec); AFixed[J] := True end;
        AMin[J] := Max(AMin[J], KMin); AMax[J] := Max(AMax[J], KMax);
      end
      else
      begin
        SumMin := 0; SumMax := 0;
        for J := G.Cells[I].Col to Min(G.NCols, G.Cells[I].Col + Cell.ColSpan) - 1 do
        begin
          Inc(SumMin, AMin[J]); Inc(SumMax, AMax[J]);
        end;
        if KMin > SumMin then
          for J := G.Cells[I].Col to Min(G.NCols, G.Cells[I].Col + Cell.ColSpan) - 1 do
            Inc(AMin[J], (KMin - SumMin) div Cell.ColSpan);
        if KMax > SumMax then
          for J := G.Cells[I].Col to Min(G.NCols, G.Cells[I].Col + Cell.ColSpan) - 1 do
            Inc(AMax[J], (KMax - SumMax) div Cell.ColSpan);
      end;
    end;
  for J := 0 to G.NCols - 1 do AMax[J] := Max(AMax[J], AMin[J]);
  if ACBW = 0 then ;
end;

procedure TFlow.TableWidth(B: TInkBox; AAvail: Integer; out AW: Integer; ACBW: Integer);
var Rows, Groups, Caps: TFPList; G: TTableGrid; MinC, MaxC: array of Integer; Pct: array of Double;
  Fixed: array of Boolean;
  J, SH, SV, SumMin, SumMax, Spec: Integer;
begin
  Rows := TFPList.Create; Groups := TFPList.Create; Caps := TFPList.Create;
  try
    TableRows(B, Rows, Groups, Caps);
    GridOf(Rows, G);
    SetLength(MinC, G.NCols); SetLength(MaxC, G.NCols); SetLength(Pct, G.NCols); SetLength(Fixed, G.NCols);
    ColumnWidths(Self, G, ACBW, MinC, MaxC, Pct, Fixed);
    Spacing(B, SH, SV);
    SumMin := SH * (G.NCols + 1); SumMax := SumMin;
    for J := 0 to G.NCols - 1 do begin Inc(SumMin, MinC[J]); Inc(SumMax, MaxC[J]) end;
    Inc(SumMin, EdgesH(B)); Inc(SumMax, EdgesH(B));
    Spec := Len(B.Style, 'width', ACBW, -1);
    if Spec >= 0 then
    begin
      if not BorderBoxSizing(B) then Inc(Spec, EdgesH(B));
      { a fixed table is as wide as it says, whatever its cells hold }
      if B.Style.Keyword('table-layout') = 'fixed' then AW := Spec
      else AW := Max(Spec, SumMin);
    end
    else AW := Max(SumMin, Min(AAvail, SumMax));
    AW := ClampW(B, AW, ACBW);
  finally Rows.Free; Groups.Free; Caps.Free end;
end;

function TFlow.LayTable(B: TInkBox; AForceW: Integer; ACBW: Integer): Integer;
var Rows, Groups, Caps: TFPList; G: TTableGrid; MinC, MaxC, ColW, ColX, RowH, RowY: array of Integer;
  Pct: array of Double; I, J, SH, SV, CW, SumMin, SumMax, Extra, W, X, Y, R, CellH, Need, Off,
  ContentH, Bottom, AutoMax, AutoN: Integer; Cell, Row, Cap: TInkBox; VA, Side: string; Total: Double;
  Fixed: array of Boolean;
begin
  CW := B.ContentW;
  Rows := TFPList.Create; Groups := TFPList.Create; Caps := TFPList.Create;
  try
    TableRows(B, Rows, Groups, Caps);
    GridOf(Rows, G);
    SetLength(MinC, G.NCols); SetLength(MaxC, G.NCols); SetLength(Pct, G.NCols);
    SetLength(ColW, G.NCols); SetLength(Fixed, G.NCols);
    ColumnWidths(Self, G, ACBW, MinC, MaxC, Pct, Fixed);
    Spacing(B, SH, SV);
    SumMin := 0; SumMax := 0;
    for J := 0 to G.NCols - 1 do begin Inc(SumMin, MinC[J]); Inc(SumMax, MaxC[J]) end;
    W := CW - SH * (G.NCols + 1);
    if (B.Style.Keyword('table-layout') = 'fixed') and (Len(B.Style, 'width', ACBW, -1) >= 0) then
    begin
      { a fixed table: the first row's widths, and the rest shared evenly -
        what the cells hold has no say }
      for J := 0 to G.NCols - 1 do ColW[J] := -1;
      for I := 0 to High(G.Cells) do
        if (G.Cells[I].Row = 0) and (G.Cells[I].Box.ColSpan = 1) and not G.Cells[I].Box.Anon then
        begin
          { a percentage is a share of the table; a length is the cell's }
          if Pos('%', G.Cells[I].Box.Style.Keyword('width')) > 0 then
            ColW[G.Cells[I].Col] := Round(G.Cells[I].Box.Style.Length(G.Cells[I].Box.Style.Keyword('width'), W, 0))
          else ColW[G.Cells[I].Col] := SpecW(G.Cells[I].Box, 'width', W);
        end;
      Extra := W; AutoN := 0;
      for J := 0 to G.NCols - 1 do
        if ColW[J] >= 0 then Dec(Extra, ColW[J]) else Inc(AutoN);
      for J := 0 to G.NCols - 1 do
        if (ColW[J] < 0) or (AutoN = 0) then
        begin
          { what is left over, or short, shared evenly - the pixels a
            division leaves go to the first columns }
          if AutoN = 0 then
          begin
            Inc(ColW[J], Extra div G.NCols);
            if J < Extra mod G.NCols then Inc(ColW[J]);
          end
          else
          begin
            ColW[J] := Max(0, Extra div AutoN);
            if J < Extra mod AutoN then Inc(ColW[J]);
          end;
        end;
    end
    else
    begin
    { percentages first, then the rest by how much more each could take }
    for J := 0 to G.NCols - 1 do
      if Pct[J] > 0 then ColW[J] := Max(MinC[J], Round(W * Pct[J] / 100)) else ColW[J] := -1;
    Extra := W;
    for J := 0 to G.NCols - 1 do if ColW[J] >= 0 then Dec(Extra, ColW[J]);
    SumMin := 0; SumMax := 0; AutoMax := 0; AutoN := 0;
    for J := 0 to G.NCols - 1 do
      if ColW[J] < 0 then
      begin
        Inc(SumMin, MinC[J]); Inc(SumMax, MaxC[J]);
        if not Fixed[J] then begin Inc(AutoMax, MaxC[J]); Inc(AutoN) end;
      end;
    for J := 0 to G.NCols - 1 do
      if ColW[J] < 0 then
      begin
        if Extra >= SumMax then
        begin
          { room to spare: each its widest, and the rest to the columns
            without a width of their own, by their widest }
          if AutoN > 0 then
          begin
            if Fixed[J] then ColW[J] := MaxC[J]
            else if AutoMax > 0 then ColW[J] := MaxC[J] + Round((Extra - SumMax) * MaxC[J] / AutoMax)
            else ColW[J] := (Extra - SumMax) div AutoN;
          end
          else if SumMax > 0 then ColW[J] := MaxC[J] + Round((Extra - SumMax) * MaxC[J] / SumMax)
          else ColW[J] := (Extra) div Max(1, G.NCols);
        end
        else if Extra > SumMin then
        begin
          Total := SumMax - SumMin;
          if Total > 0 then ColW[J] := MinC[J] + Round((Extra - SumMin) * (MaxC[J] - MinC[J]) / Total)
          else ColW[J] := MinC[J];
        end
        else ColW[J] := MinC[J];
      end;
    end;
    SetLength(ColX, G.NCols + 1);
    ColX[0] := B.ContentX + SH;
    for J := 0 to G.NCols - 1 do ColX[J + 1] := ColX[J] + ColW[J] + SH;
    { captions above, by default }
    Y := B.ContentY;
    for I := 0 to Caps.Count - 1 do
    begin
      Cap := TInkBox(Caps[I]);
      Side := Cap.Style.Keyword('caption-side');
      if Side = 'bottom' then Continue;
      LayBox(Cap, B.ContentX, Y, CW, -1, nil, CW);
      Y := Cap.Y + Cap.H;
    end;
    Inc(Y, SV);
    { the cells at their columns' widths; rows as tall as their tallest }
    SetLength(RowH, G.NRows); SetLength(RowY, G.NRows + 1);
    for R := 0 to G.NRows - 1 do RowH[R] := 0;
    for I := 0 to High(G.Cells) do
    begin
      Cell := G.Cells[I].Box;
      J := Min(G.NCols, G.Cells[I].Col + Cell.ColSpan);
      W := ColX[J] - ColX[G.Cells[I].Col] - SH;
      LayBox(Cell, ColX[G.Cells[I].Col], 0, W, -1, nil, W);
      if Cell.RowSpan = 1 then
      begin
        Row := TInkBox(Rows[G.Cells[I].Row]);
        Need := Cell.H;
        if (not Row.Anon) and (Len(Row.Style, 'height', -1, -1) > Need) then Need := Len(Row.Style, 'height', -1, -1);
        RowH[G.Cells[I].Row] := Max(RowH[G.Cells[I].Row], Need);
      end;
    end;
    for I := 0 to High(G.Cells) do
    begin
      Cell := G.Cells[I].Box;
      if Cell.RowSpan > 1 then
      begin
        Need := Cell.H - SV * (Cell.RowSpan - 1);
        for R := G.Cells[I].Row to G.Cells[I].Row + Cell.RowSpan - 1 do Dec(Need, RowH[R]);
        if Need > 0 then Inc(RowH[G.Cells[I].Row + Cell.RowSpan - 1], Need);
      end;
    end;
    for R := 0 to G.NRows - 1 do
    begin
      RowY[R] := Y;
      Inc(Y, RowH[R] + SV);
    end;
    RowY[G.NRows] := Y;
    { each cell to its row and its height, its content where
      vertical-align puts it }
    for I := 0 to High(G.Cells) do
    begin
      Cell := G.Cells[I].Box;
      R := G.Cells[I].Row;
      CellH := RowY[R + Cell.RowSpan] - RowY[R] - SV;
      ContentH := Cell.H;
      Cell.Shift(0, RowY[R] - Cell.Y);
      Cell.H := CellH;
      VA := Cell.Style.Keyword('vertical-align');
      Off := CellH - ContentH;
      if Off > 0 then
      begin
        if VA = 'middle' then Off := Off div 2
        else if VA <> 'bottom' then Off := 0;
        if Off > 0 then
          for J := 0 to Cell.Count - 1 do Cell[J].Shift(0, Off);
        if (Off > 0) and (Cell.Kind = ibkText) then Inc(Cell.TextY, Off);
      end;
    end;
    { rows and their groups cover their cells }
    for R := 0 to Rows.Count - 1 do
    begin
      Row := TInkBox(Rows[R]);
      if Row.Kind = ibkCell then Continue;
      Edges(Row, CW);
      Row.X := B.ContentX + SH; Row.W := ColX[G.NCols] - SH - Row.X;
      Row.Y := RowY[R]; Row.H := RowH[R];
    end;
    for I := 0 to Groups.Count - 1 do
    begin
      Row := TInkBox(Groups[I]);
      Edges(Row, CW);
      Row.X := B.ContentX; Row.W := CW;
      Row.Y := MaxInt; Bottom := Low(Integer);
      for J := 0 to Row.Count - 1 do
      begin
        Row.Y := Min(Row.Y, Row[J].Y);
        Bottom := Max(Bottom, Row[J].Y + Row[J].H);
      end;
      if Row.Y = MaxInt then begin Row.Y := B.ContentY; Bottom := Row.Y end;
      Row.H := Bottom - Row.Y;
    end;
    for I := 0 to Caps.Count - 1 do
    begin
      Cap := TInkBox(Caps[I]);
      if Cap.Style.Keyword('caption-side') <> 'bottom' then Continue;
      LayBox(Cap, B.ContentX, Y, CW, -1, nil, CW);
      Y := Cap.Y + Cap.H;
    end;
    Result := Y - B.ContentY;
    X := 0; if X <> 0 then ;
  finally Rows.Free; Groups.Free; Caps.Free end;
end;

{ ------------------------------------------------------------ absolutes }

procedure TFlow.LayAbsolute(B: TInkBox);
var CB: TInkBox; R: TRect; L, Rt, T, Bt, W, H, Avail, SH: Integer; Fixed: Boolean;
begin
  Fixed := B.Style.Keyword('position') = 'fixed';
  CB := B.Parent;
  while (CB <> nil) and not Fixed and ((CB.Anon) or (CB.Style.Keyword('position') = 'static')) do
    CB := CB.Parent;
  if Fixed or (CB = nil) then R := Rect(0, 0, ViewW, ViewH)
  else R := CB.PaddingRect;
  Edges(B, R.Right - R.Left);
  L := Len(B.Style, 'left', R.Right - R.Left, Low(Integer));
  Rt := Len(B.Style, 'right', R.Right - R.Left, Low(Integer));
  T := Len(B.Style, 'top', R.Bottom - R.Top, Low(Integer));
  Bt := Len(B.Style, 'bottom', R.Bottom - R.Top, Low(Integer));
  W := SpecW(B, 'width', R.Right - R.Left);
  if (W < 0) and (L <> Low(Integer)) and (Rt <> Low(Integer)) then
    W := R.Right - R.Left - L - Rt - B.Margin.Left - B.Margin.Right;
  Avail := R.Right - R.Left - B.Margin.Left - B.Margin.Right;
  if L <> Low(Integer) then Dec(Avail, L);
  if Rt <> Low(Integer) then Dec(Avail, Rt);
  if W < 0 then W := ShrinkToFit(B, Max(0, Avail));
  LayBox(B, 0, 0, R.Right - R.Left, R.Bottom - R.Top, nil, Max(0, W));
  { a height from top and bottom together }
  SH := SpecH(B, 'height', R.Bottom - R.Top);
  if (SH < 0) and (T <> Low(Integer)) and (Bt <> Low(Integer)) then
  begin
    H := R.Bottom - R.Top - T - Bt - B.Margin.Top - B.Margin.Bottom;
    if H > B.H then B.H := H;
  end;
  if L <> Low(Integer) then W := R.Left + L + B.Margin.Left
  else if Rt <> Low(Integer) then W := R.Right - Rt - B.Margin.Right - B.W
  else W := B.StaticX + B.Margin.Left;
  if T <> Low(Integer) then H := R.Top + T + B.Margin.Top
  else if Bt <> Low(Integer) then H := R.Bottom - Bt - B.Margin.Bottom - B.H
  else H := B.StaticY + B.Margin.Top;
  B.Shift(W - B.X, H - B.Y);
end;

{ --------------------------------------------------------------- running }

procedure TInkLayout.Run(AViewWidth, AViewHeight: Integer);
var F: TFlow; Floats: TFloats; I: Integer; C: TCollapse;

  procedure Lowest(B: TInkBox);
  var J: Integer;
  begin
    FHeight := Max(FHeight, B.Y + B.H);
    for J := 0 to B.Count - 1 do Lowest(B[J]);
  end;

begin
  FViewW := AViewWidth; FViewH := AViewHeight;
  FHeight := 0;
  FAbsolutes.Clear;
  if FRoot = nil then Exit;
  F := TFlow.Create;
  Floats := TFloats.Create;
  try
    F.Layout := Self; F.Measure := FMeasure;
    F.ViewW := AViewWidth; F.ViewH := AViewHeight;
    F.Absolutes := FAbsolutes;
    { the root's own margins, and its first child's when they meet }
    C := Default(TCollapse);
    TopMargins(FRoot, AViewWidth, C);
    F.LayBox(FRoot, 0, GapOf(C), AViewWidth, AViewHeight, Floats);
    { the root is at least as tall as the window, as the canvas is }
    { absolutes, outermost first: theirs may be inside them }
    I := 0;
    while I < FAbsolutes.Count do
    begin
      F.LayAbsolute(TInkBox(FAbsolutes[I]));
      Inc(I);
    end;
    C := Default(TCollapse);
    BottomMargins(FRoot, C);
    FHeight := FRoot.Y + FRoot.H + GapOf(C);
    Lowest(FRoot);
  finally Floats.Free; F.Free end;
end;

end.
