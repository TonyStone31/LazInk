{ LazInk renderer prototype.

  This unit is an isolated, from-scratch experiment for the renderer described
  in docs/RENDERER_SPEC.md.  It intentionally has no dependency on InkHtml,
  inktables.inc, or any LazInk control and is not part of lazink.lpk.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors

  The design is deliberately data-first:
    source -> lexical tokens -> styled runs -> cached line boxes -> paint.
  A layout is immutable while it is painted, so scrolling never reparses or
  remeasures the source.  This is prototype plumbing, not a compatibility
  wrapper for the existing renderer.
}
unit InkRenderNext;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList, Types, Math;

type
  TInkNextTokenKind = (ntText, ntOpen, ntClose, ntBreak, ntRule);
  TInkNextAlign = (naLeft, naCenter, naRight);
  TInkNextScript = (nsNormal, nsSuper, nsSub);

  TInkNextToken = record
    Kind: TInkNextTokenKind;
    Name: string;
    Value: string;
    Attributes: TStringList;
    SelfClosing: Boolean;
  end;

  TInkNextStyle = record
    Face: string;
    Size: Integer;
    Color, BackColor: TColor;
    Styles: TFontStyles;
    Script: TInkNextScript;
    LinkIndex: Integer;
    LinkName: string;
    Align: TInkNextAlign;
    Indent: Integer;
  end;

  TInkNextRun = record
    Text: string;
    Style: TInkNextStyle;
    Bounds: TRect;
    Line: Integer;
    Part: Integer;
    IsImage: Boolean;
    ImageIndex: Integer;
    Control: Byte; { 0=text, 1=table, 2=row, 3=cell, 4/5/6=closes }
  end;

  TInkNextLine = record
    Bounds: TRect;
    FirstRun, RunCount: Integer;
    Align: TInkNextAlign;
    Part: Integer;
  end;

  TInkNextHit = record
    OnLink: Boolean;
    LinkIndex: Integer;
    LinkName, LinkText: string;
    RunIndex: Integer;
    CharacterOffset: Integer;
  end;

  TInkNextOptions = record
    BaseFont: TFont;
    Images: TCustomImageList;
    Width: Integer;
    Scale: Integer;
    LineSpacing: Integer;
    Borders: TRect;
    LinkColor, LinkBackColor: TColor;
    LinkUnderline: Boolean;
    HoverIndex: Integer;
    HoverColor, HoverBackColor: TColor;
    HoverUnderline: Boolean;
  end;

  TInkNextLayout = class
  private
    FRuns: array of TInkNextRun;
    FLines: array of TInkNextLine;
    FSize: TSize;
    FSourceHash: Cardinal;
    FWidth, FScale: Integer;
  public
    procedure Clear;
    function RunCount: Integer;
    function LineCount: Integer;
    function RunAt(Index: Integer): TInkNextRun;
    function LineAt(Index: Integer): TInkNextLine;
    property Size: TSize read FSize;
    property SourceHash: Cardinal read FSourceHash;
    property Width: Integer read FWidth;
  end;

  TInkNextRenderer = class
  private
    FTokens: array of TInkNextToken;
    FStyled: array of TInkNextRun;
    FLayout: TInkNextLayout;
    FSourceHash: Cardinal;
    FLayoutKey: Cardinal;
    FStyleKey: Cardinal;
    FMetricKeys, FMetricHeights: TStringList;
    FNextLink: Integer;
    function HashSource(const S: string): Cardinal;
    function HashOptions(const Options: TInkNextOptions): Cardinal;
    function IsKnownTag(const N: string): Boolean;
    function IsStyleTag(const N: string): Boolean;
    function BaseStyle(const Options: TInkNextOptions): TInkNextStyle;
    function StyleFor(const Stack: array of TInkNextStyle): TInkNextStyle;
    procedure AddToken(AKind: TInkNextTokenKind; const Name, Value: string;
      ASelfClosing: Boolean; const Attrs: TStringList);
    procedure BuildStyles(const Options: TInkNextOptions);
    procedure AddStyledText(const Text: string; const Style: TInkNextStyle;
      APart: Integer);
    function MeasureRun(const Canvas: TCanvas; const Run: TInkNextRun): TSize;
    function MetricHeight(const Canvas: TCanvas; const Run: TInkNextRun): Integer;
    function IsCJK(C: Cardinal): Boolean;
    function CodepointAt(const S: string; P: Integer; out Bytes: Integer): Cardinal;
    procedure LayoutTable(const Canvas: TCanvas; const Options: TInkNextOptions;
      AStart, AEnd: Integer; var X, Y, Line: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Tokenize(const Source: string);
    function Layout(const Canvas: TCanvas; const Options: TInkNextOptions): TInkNextLayout;
    procedure Paint(Canvas: TCanvas; const Bounds: TRect; const Options: TInkNextOptions);
    function HitTest(const Canvas: TCanvas; X, Y: Integer): TInkNextHit;
    property CachedLayout: TInkNextLayout read FLayout;
  end;

implementation

function Lower(const S: string): string;
begin Result := LowerCase(Trim(S)) end;

function InkNextColor(const S: string; Default: TColor): TColor;
var V, Hex: string; N: LongInt;
begin
  V := Lower(S);
  if (V = '') or (V = 'none') or (V = 'transparent') then Exit(Default);
  if V[1] = '#' then
  begin
    Hex := Copy(V, 2, MaxInt);
    if Length(Hex) = 3 then Hex := Hex[1]+Hex[1]+Hex[2]+Hex[2]+Hex[3]+Hex[3];
    if TryStrToInt('$'+Hex, N) then Exit(RGBToColor((N shr 16) and $ff,
      (N shr 8) and $ff, N and $ff));
  end;
  Result := StringToColorDef(S, Default);
end;

function InkNextAttr(const Attrs: TStringList; const Name: string): string;
begin Result := Attrs.Values[Lower(Name)] end;

function InkNextStyleBits(const Styles: TFontStyles): Integer;
begin
  Result := 0;
  if fsBold in Styles then Inc(Result, 1);
  if fsItalic in Styles then Inc(Result, 2);
  if fsUnderline in Styles then Inc(Result, 4);
  if fsStrikeOut in Styles then Inc(Result, 8);
end;

function InkNextDecodeText(const S: string): string;
var I: Integer; T: string;
begin
  { The document layer owns full entity handling. These three escapes are
    sufficient for the renderer's deliberately small markup contract. }
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      T := LowerCase(Copy(S, I, 4));
      if T = '&lt;' then begin Result := Result + '<'; Inc(I, 4); Continue end;
      if T = '&gt;' then begin Result := Result + '>'; Inc(I, 4); Continue end;
      T := LowerCase(Copy(S, I, 5));
      if T = '&amp;' then begin Result := Result + '&'; Inc(I, 5); Continue end;
    end;
    Result := Result + S[I]; Inc(I);
  end;
end;

function InkNextText(const S: string): string;
var I: Integer;
begin
  Result := InkNextDecodeText(S);
  I := 1;
  while I <= Length(Result) do
    if Result[I] in [#10, #13] then Delete(Result, I, 1) else Inc(I);
end;

procedure TInkNextLayout.Clear;
begin
  SetLength(FRuns, 0); SetLength(FLines, 0); FSize := Types.Size(0, 0);
  FSourceHash := 0; FWidth := -1; FScale := 100;
end;

function TInkNextLayout.RunCount: Integer;
begin Result := Length(FRuns) end;

function TInkNextLayout.LineCount: Integer;
begin Result := Length(FLines) end;

function TInkNextLayout.RunAt(Index: Integer): TInkNextRun;
begin
  if (Index < 0) or (Index >= Length(FRuns)) then
    raise ERangeError.CreateFmt('Run index %d is outside the layout', [Index]);
  Result := FRuns[Index];
end;

function TInkNextLayout.LineAt(Index: Integer): TInkNextLine;
begin
  if (Index < 0) or (Index >= Length(FLines)) then
    raise ERangeError.CreateFmt('Line index %d is outside the layout', [Index]);
  Result := FLines[Index];
end;

constructor TInkNextRenderer.Create;
begin
  inherited Create;
  FLayout := TInkNextLayout.Create;
  FMetricKeys := TStringList.Create;
  FMetricHeights := TStringList.Create;
end;

destructor TInkNextRenderer.Destroy;
var I: Integer;
begin
  for I := 0 to High(FTokens) do FTokens[I].Attributes.Free;
  FLayout.Free;
  FMetricKeys.Free; FMetricHeights.Free;
  inherited Destroy;
end;

function TInkNextRenderer.HashSource(const S: string): Cardinal;
var I: Integer;
begin
  Result := 2166136261;
  for I := 1 to Length(S) do Result := (Result xor Ord(S[I])) * 16777619;
end;

function TInkNextRenderer.IsKnownTag(const N: string): Boolean;
begin
  Result := (N = 'b') or (N = 'i') or (N = 'u') or (N = 's') or
    (N = 'sup') or (N = 'sub') or (N = 'font') or (N = 'a') or
    (N = 'br') or (N = 'hr') or (N = 'p') or (N = 'center') or
    (N = 'right') or (N = 'left') or (N = 'ind') or (N = 'img') or
    (N = 'table') or (N = 'tr') or (N = 'td') or (N = 'th');
end;

function TInkNextRenderer.IsStyleTag(const N: string): Boolean;
begin
  Result := (N = 'b') or (N = 'i') or (N = 'u') or (N = 's') or
    (N = 'sup') or (N = 'sub') or (N = 'font') or (N = 'a') or
    (N = 'center') or (N = 'right') or (N = 'left') or (N = 'ind') or
    (N = 'td') or (N = 'th');
end;

procedure TInkNextRenderer.AddToken(AKind: TInkNextTokenKind;
  const Name, Value: string; ASelfClosing: Boolean; const Attrs: TStringList);
var N: Integer;
begin
  N := Length(FTokens); SetLength(FTokens, N+1);
  FTokens[N].Kind := AKind; FTokens[N].Name := Name;
  FTokens[N].Value := Value; FTokens[N].SelfClosing := ASelfClosing;
  FTokens[N].Attributes := TStringList.Create;
  FTokens[N].Attributes.CaseSensitive := False;
  FTokens[N].Attributes.Assign(Attrs);
end;

procedure TInkNextRenderer.Tokenize(const Source: string);
var P, Q, Start, N: Integer; Raw, Name, Key, Val: string;
  Closing, SelfClosing: Boolean; Attrs: TStringList; Quote: Char;
begin
  FSourceHash := HashSource(Source);
  FLayout.Clear; FStyleKey := 0; FLayoutKey := 0;
  for N := 0 to High(FTokens) do FTokens[N].Attributes.Free;
  SetLength(FTokens, 0); P := 1; Attrs := TStringList.Create;
  try
    while P <= Length(Source) do
    begin
      if Source[P] <> '<' then
      begin
        Start := P; while (P <= Length(Source)) and (Source[P] <> '<') do Inc(P);
        AddToken(ntText, '', InkNextText(Copy(Source, Start, P-Start)), False, Attrs); Continue;
      end;
      Q := P+1; while (Q <= Length(Source)) and (Source[Q] <> '>') do Inc(Q);
      if Q > Length(Source) then
      begin
        AddToken(ntText, '', InkNextText(Copy(Source, P, MaxInt)), False, Attrs); Break;
      end;
      Raw := Copy(Source, P+1, Q-P-1); P := Q+1;
      Closing := False; SelfClosing := False; Raw := Trim(Raw);
      if (Raw <> '') and (Raw[1] = '/') then begin Closing := True; Delete(Raw,1,1); Raw := Trim(Raw) end;
      if (Raw <> '') and (Raw[Length(Raw)] = '/') then begin SelfClosing := True; Delete(Raw,Length(Raw),1); Raw := Trim(Raw) end;
      Q := 1; while (Q <= Length(Raw)) and not (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
      Name := Lower(Copy(Raw,1,Q-1));
      if not IsKnownTag(Name) then Continue;
      Attrs.Clear;
      while Q <= Length(Raw) do
      begin
        while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
        Start := Q; while (Q <= Length(Raw)) and not (Raw[Q] in ['=',' ',#9,#10,#13]) do Inc(Q);
        Key := Lower(Copy(Raw,Start,Q-Start)); if Key='' then Break;
        while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
        Val := '';
        if (Q <= Length(Raw)) and (Raw[Q] = '=') then
        begin
          Inc(Q); while (Q <= Length(Raw)) and (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
          Quote := #0; if (Q <= Length(Raw)) and (Raw[Q] in ['"', '''']) then begin Quote := Raw[Q]; Inc(Q) end;
          Start := Q;
          if Quote <> #0 then while (Q <= Length(Raw)) and (Raw[Q] <> Quote) do Inc(Q)
          else while (Q <= Length(Raw)) and not (Raw[Q] in [' ',#9,#10,#13]) do Inc(Q);
          Val := Copy(Raw,Start,Q-Start); if Quote <> #0 then Inc(Q);
        end;
        Attrs.Values[Key] := Val;
      end;
      if Name = 'br' then AddToken(ntBreak,Name,'',SelfClosing,Attrs)
      else if Name = 'hr' then AddToken(ntRule,Name,'',SelfClosing,Attrs)
      else if Closing then AddToken(ntClose,Name,'',SelfClosing,Attrs)
      else AddToken(ntOpen,Name,'',SelfClosing,Attrs);
    end;
  finally Attrs.Free end;
end;

function TInkNextRenderer.HashOptions(const Options: TInkNextOptions): Cardinal;
var S: string; StyleBits: Integer;
begin
  StyleBits := 0;
  if fsBold in Options.BaseFont.Style then Inc(StyleBits, 1);
  if fsItalic in Options.BaseFont.Style then Inc(StyleBits, 2);
  if fsUnderline in Options.BaseFont.Style then Inc(StyleBits, 4);
  if fsStrikeOut in Options.BaseFont.Style then Inc(StyleBits, 8);
  S := Options.BaseFont.Name + '|' + IntToStr(Options.BaseFont.Size) + '|' +
    IntToStr(Options.BaseFont.Color) + '|' + IntToStr(StyleBits) +
    '|' + IntToStr(Options.Scale) + '|' + IntToStr(Options.LineSpacing) +
    '|' + IntToStr(Options.Borders.Left) + '|' + IntToStr(Options.Borders.Top) +
    '|' + IntToStr(Options.Borders.Right) + '|' + IntToStr(Options.Borders.Bottom);
  Result := HashSource(S);
end;

function TInkNextRenderer.BaseStyle(const Options: TInkNextOptions): TInkNextStyle;
begin
  Result.Face := Options.BaseFont.Name;
  Result.Size := Options.BaseFont.Size; if Result.Size <= 0 then Result.Size := 10;
  if Options.Scale > 0 then Result.Size := Max(1, Round(Result.Size * Options.Scale / 100));
  Result.Color := Options.BaseFont.Color; Result.BackColor := clNone;
  Result.Styles := Options.BaseFont.Style; Result.Script := nsNormal;
  Result.LinkIndex := 0; Result.LinkName := '';
  Result.Align := naLeft; Result.Indent := 0;
end;

function TInkNextRenderer.StyleFor(const Stack: array of TInkNextStyle): TInkNextStyle;
var I: Integer;
begin
  Result.Face := ''; Result.Size := 10;
  Result.Color := clWindowText; Result.BackColor := clNone; Result.Align := naLeft;
  Result.Styles := []; Result.Script := nsNormal; Result.LinkIndex := 0;
  Result.LinkName := ''; Result.Indent := 0;
  for I := 0 to High(Stack) do
  begin
    if Stack[I].Face <> '' then Result.Face := Stack[I].Face;
    if Stack[I].Size > 0 then Result.Size := Stack[I].Size;
    if Stack[I].Color <> clDefault then Result.Color := Stack[I].Color;
    if Stack[I].BackColor <> clNone then Result.BackColor := Stack[I].BackColor;
    Result.Styles := Result.Styles + Stack[I].Styles;
    if Stack[I].Script <> nsNormal then Result.Script := Stack[I].Script;
    if Stack[I].LinkIndex > 0 then begin Result.LinkIndex := Stack[I].LinkIndex; Result.LinkName := Stack[I].LinkName end;
    if Stack[I].Align <> naLeft then Result.Align := Stack[I].Align;
    if Stack[I].Indent <> 0 then Result.Indent := Stack[I].Indent;
  end;
end;

procedure TInkNextRenderer.AddStyledText(const Text: string;
  const Style: TInkNextStyle; APart: Integer);
var N: Integer;
begin
  if Text = '' then Exit; N := Length(FStyled); SetLength(FStyled,N+1);
  FStyled[N].Text := Text; FStyled[N].Style := Style; FStyled[N].Part := APart;
  FStyled[N].Line := -1; FStyled[N].IsImage := False; FStyled[N].ImageIndex := -1;
  FStyled[N].Control := 0;
end;

procedure TInkNextRenderer.BuildStyles(const Options: TInkNextOptions);
var Stack: array of TInkNextStyle; StackNames: array of string;
  Base, S: TInkNextStyle; I,N,Part,K: Integer; T: TInkNextToken;
  procedure Push(const V: TInkNextStyle; const TagName: string);
  begin
    K := Length(Stack); SetLength(Stack,K+1); SetLength(StackNames,K+1);
    Stack[K] := V; StackNames[K] := TagName;
  end;
  procedure PopMatching(const TagName: string);
  var M: Integer;
  begin
    for M := High(StackNames) downto 1 do
      if StackNames[M] = TagName then
      begin
        SetLength(Stack,M); SetLength(StackNames,M); Exit;
      end;
  end;
  procedure AddControl(Kind: Byte);
  var Z: Integer;
  begin
    Z := Length(FStyled); SetLength(FStyled, Z+1);
    FStyled[Z].Text := ''; FStyled[Z].Style := StyleFor(Stack);
    FStyled[Z].Part := Part; FStyled[Z].Line := -1;
    FStyled[Z].IsImage := False; FStyled[Z].ImageIndex := -1;
    FStyled[Z].Control := Kind;
  end;
begin
  SetLength(FStyled,0); FNextLink := 0; Part := 0; Base := BaseStyle(Options);
  SetLength(Stack, 1); SetLength(StackNames, 1); Stack[0] := Base; StackNames[0] := '';
  for I := 0 to High(FTokens) do
  begin
    T := FTokens[I]; S := StyleFor(Stack);
    case T.Kind of
      ntText: AddStyledText(T.Value,S,Part);
      ntBreak: begin AddStyledText(#10,S,Part); Inc(Part) end;
      ntRule: begin AddStyledText(#9,S,Part); Inc(Part) end;
      ntOpen:
        begin
          S := StyleFor(Stack); N := 0;
          if T.Name='b' then S.Styles := S.Styles+[fsBold]
          else if T.Name='i' then S.Styles := S.Styles+[fsItalic]
          else if T.Name='u' then S.Styles := S.Styles+[fsUnderline]
          else if T.Name='s' then S.Styles := S.Styles+[fsStrikeOut]
          else if T.Name='sup' then S.Script := nsSuper
          else if T.Name='sub' then S.Script := nsSub
          else if T.Name='center' then S.Align := naCenter
          else if T.Name='right' then S.Align := naRight
          else if T.Name='left' then S.Align := naLeft
          else if T.Name='ind' then S.Indent := StrToIntDef(InkNextAttr(T.Attributes,'n'),0)
          else if T.Name='font' then
          begin
            S.Face := InkNextAttr(T.Attributes,'face');
            N := StrToIntDef(InkNextAttr(T.Attributes,'size'),0); if N>0 then S.Size := N;
            S.Color := InkNextColor(InkNextAttr(T.Attributes,'color'),S.Color);
            S.BackColor := InkNextColor(InkNextAttr(T.Attributes,'bgcolor'),S.BackColor);
          end
          else if T.Name='a' then begin Inc(FNextLink); S.LinkIndex := FNextLink; S.LinkName := InkNextAttr(T.Attributes,'href') end
          else if T.Name='img' then begin AddStyledText(#1,S,Part); N := Length(FStyled)-1; FStyled[N].IsImage := True; FStyled[N].ImageIndex := StrToIntDef(InkNextAttr(T.Attributes,'src'),-1) end
          else if T.Name='table' then AddControl(1)
          else if T.Name='tr' then AddControl(2)
          else if (T.Name='td') or (T.Name='th') then
          begin
            if T.Name='th' then S.Styles := S.Styles+[fsBold];
            AddControl(3);
          end;
          if IsStyleTag(T.Name) and not T.SelfClosing then Push(S,T.Name)
          else if T.Name='p' then
          begin
            if Length(FStyled)>0 then begin AddStyledText(#10,S,Part); AddStyledText(#10,S,Part); Inc(Part) end;
          end;
        end;
      ntClose:
        begin
          PopMatching(T.Name);
          if (T.Name='table') then AddControl(6)
          else if T.Name='tr' then AddControl(5)
          else if (T.Name='td') or (T.Name='th') then AddControl(4);
          { </p> is intentionally inert; the opening paragraph tag owns the break. }
        end;
    end;
  end;
end;

function TInkNextRenderer.CodepointAt(const S: string; P: Integer; out Bytes: Integer): Cardinal;
var B: Byte;
begin
  Bytes := 1; Result := 0; if (P<1) or (P>Length(S)) then Exit; B := Ord(S[P]);
  if B<$80 then Result:=B else if (B and $E0)=$C0 then begin Bytes:=2; Result:=((B and $1F) shl 6) or (Ord(S[P+1]) and $3F) end
  else if (B and $F0)=$E0 then begin Bytes:=3; Result:=((B and $0F) shl 12) or ((Ord(S[P+1]) and $3F) shl 6) or (Ord(S[P+2]) and $3F) end
  else if (B and $F8)=$F0 then begin Bytes:=4; Result:=((B and 7) shl 18) or ((Ord(S[P+1]) and $3F) shl 12) or ((Ord(S[P+2]) and $3F) shl 6) or (Ord(S[P+3]) and $3F) end
  else Result:=B;
end;

function TInkNextRenderer.IsCJK(C: Cardinal): Boolean;
begin Result := ((C>=$2E80) and (C<=$A4CF)) or ((C>=$AC00) and (C<=$D7A3)) or ((C>=$F900) and (C<=$FAFF)) or ((C>=$20000) and (C<=$2FA1F)) end;

function TInkNextRenderer.MeasureRun(const Canvas: TCanvas; const Run: TInkNextRun): TSize;
var Old: TFont; S: string;
begin
  Old := TFont.Create; Old.Assign(Canvas.Font); Canvas.Font.Name := Run.Style.Face;
  Canvas.Font.Size := Run.Style.Size; Canvas.Font.Style := Run.Style.Styles; S := Run.Text;
  if Run.Style.Script<>nsNormal then Canvas.Font.Size := Max(1,Round(Canvas.Font.Size*0.7));
  Result := Types.Size(Canvas.TextWidth(S),MetricHeight(Canvas,Run));
  Canvas.Font.Assign(Old); Old.Free;
end;

function TInkNextRenderer.MetricHeight(const Canvas: TCanvas;
  const Run: TInkNextRun): Integer;
var Key, V: string; N: Integer; Old: TFont;
begin
  Key := Run.Style.Face + #1 + IntToStr(Run.Style.Size) + #1 +
    IntToStr(InkNextStyleBits(Run.Style.Styles)) + #1 + IntToStr(Integer(Run.Style.Script));
  N := FMetricKeys.IndexOf(Key);
  if N >= 0 then Exit(StrToIntDef(FMetricHeights[N], Canvas.TextHeight('Tg')));
  Old := TFont.Create; Old.Assign(Canvas.Font);
  Canvas.Font.Name := Run.Style.Face; Canvas.Font.Size := Run.Style.Size;
  Canvas.Font.Style := Run.Style.Styles;
  if Run.Style.Script<>nsNormal then Canvas.Font.Size := Max(1,Round(Canvas.Font.Size*0.7));
  V := IntToStr(Canvas.TextHeight('Tg'));
  FMetricKeys.Add(Key); FMetricHeights.Add(V); Result := StrToInt(V);
  Canvas.Font.Assign(Old); Old.Free;
end;

procedure TInkNextRenderer.LayoutTable(const Canvas: TCanvas;
  const Options: TInkNextOptions; AStart, AEnd: Integer; var X, Y, Line: Integer);
type
  TCell = record StartRun, EndRun, Row, Col: Integer end;
var
  Cells: array of TCell;
  I, J, Row, Col, Rows, Cols, CellIndex, TableWidth, CellWidth,
    Pad, SX, SY, W, H, RunIndex, FirstRun: Integer;
  RowHeights, ColWidths: array of Integer;
  R: TInkNextRun; Sz: TSize; L: TInkNextLine;
  InCell: Boolean;
  procedure AddLine(First, Count, Top, Height, Part: Integer);
  begin
    if Count <= 0 then Exit;
    L.Bounds := Rect(0, Top, Options.Width, Top+Height); L.FirstRun := First;
    L.RunCount := Count; L.Align := FLayout.FRuns[First].Style.Align; L.Part := Part;
    SetLength(FLayout.FLines, Length(FLayout.FLines)+1);
    FLayout.FLines[High(FLayout.FLines)] := L;
  end;
begin
  { First collect the table's cells from structural markers. The renderer does
    not need to retain a DOM: a compact range list is enough for layout. }
  SetLength(Cells, 0);
  Row := -1; Col := 0; Rows := 0; Cols := 0; InCell := False;
  for I := AStart+1 to AEnd-1 do
  begin
    case FStyled[I].Control of
      2: begin Inc(Row); Col := 0; Rows := Max(Rows, Row+1) end;
      3: if not InCell then
         begin
           InCell := True; CellIndex := Length(Cells); SetLength(Cells,CellIndex+1);
           Cells[CellIndex].StartRun := I+1; Cells[CellIndex].EndRun := I;
           Cells[CellIndex].Row := Max(0,Row); Cells[CellIndex].Col := Col;
           Cols := Max(Cols, Col+1);
         end;
      4: if InCell then begin Cells[CellIndex].EndRun := I-1; InCell := False; Inc(Col) end;
    end;
  end;
  if InCell then Cells[CellIndex].EndRun := AEnd-1;
  if (Rows=0) or (Cols=0) then Exit;
  SetLength(RowHeights,Rows); SetLength(ColWidths,Cols);
  Pad := 6; TableWidth := Max(1,Options.Width-Options.Borders.Left-Options.Borders.Right);
  for I := 0 to High(Cells) do
  begin
    W := 0; H := 0;
    for J := Cells[I].StartRun to Cells[I].EndRun do
      if (J>=0) and (J<Length(FStyled)) and (FStyled[J].Control=0) then
      begin
        Sz := MeasureRun(Canvas,FStyled[J]); Inc(W,Sz.cx); H := Max(H,Sz.cy);
      end;
    ColWidths[Cells[I].Col] := Max(ColWidths[Cells[I].Col],W+Pad*2);
    RowHeights[Cells[I].Row] := Max(RowHeights[Cells[I].Row],H+Pad*2);
  end;
  for I := 0 to Cols-1 do if ColWidths[I]=0 then ColWidths[I] := Pad*2+12;
  for I := 0 to Rows-1 do if RowHeights[I]=0 then RowHeights[I] := Pad*2+Canvas.TextHeight('Tg');
  W := 0; for I := 0 to Cols-1 do Inc(W,ColWidths[I]);
  if W > TableWidth then
    for I := 0 to Cols-1 do ColWidths[I] := Max(Pad*2+12, ColWidths[I]*TableWidth div W)
  else if W < TableWidth then
    for I := 0 to Cols-1 do Inc(ColWidths[I], (TableWidth-W) div Cols);
  SX := Options.Borders.Left; SY := Y;
  for I := 0 to High(Cells) do
  begin
    X := SX; for J := 0 to Cells[I].Col-1 do Inc(X,ColWidths[J]);
    Y := SY; for J := 0 to Cells[I].Row-1 do Inc(Y,RowHeights[J]);
    CellWidth := ColWidths[Cells[I].Col]-Pad*2; FirstRun := Length(FLayout.FRuns);
    for RunIndex := Cells[I].StartRun to Cells[I].EndRun do
    begin
      if (RunIndex<0) or (RunIndex>=Length(FStyled)) or
        (FStyled[RunIndex].Control<>0) then Continue;
      R := FStyled[RunIndex]; Sz := MeasureRun(Canvas,R);
      { A cell's line boxes are intentionally independent from surrounding
        lines. The later wrapping pass can split these runs without touching
        the table's row geometry. }
      R.Bounds := Rect(X+Pad,Y+Pad,X+Pad+Min(CellWidth,Sz.cx),Y+Pad+Sz.cy);
      R.Line := Length(FLayout.FLines); R.Part := Cells[I].Row*1000+Cells[I].Col;
      SetLength(FLayout.FRuns,Length(FLayout.FRuns)+1);
      FLayout.FRuns[High(FLayout.FRuns)] := R;
    end;
    AddLine(FirstRun,Length(FLayout.FRuns)-FirstRun,Y,RowHeights[Cells[I].Row],Cells[I].Row*1000+Cells[I].Col);
  end;
  Y := SY; for I := 0 to Rows-1 do Inc(Y,RowHeights[I]); X := SX+TableWidth; Inc(Line);
end;

function TInkNextRenderer.Layout(const Canvas: TCanvas; const Options: TInkNextOptions): TInkNextLayout;
var I,J,D,P,Line,First,Count,X,Y,MaxLineH,Avail,W: Integer; R: TInkNextRun; Sz: TSize; Text,Atom: string; Start,Bytes: Integer; C: Cardinal; L: TInkNextLine;
  procedure FinishLine;
  var K,Shift: Integer;
  begin
    if Count=0 then Exit; L.Bounds:=Rect(0,Y,Avail,Y+MaxLineH); L.FirstRun:=First; L.RunCount:=Count; L.Align:=FLayout.FRuns[First].Style.Align; L.Part:=FLayout.FRuns[First].Part;
    if L.Align=naCenter then Shift:=(Avail-(X-Options.Borders.Left)) div 2 else if L.Align=naRight then Shift:=Avail-(X-Options.Borders.Left) else Shift:=0;
    for K:=First to First+Count-1 do begin Inc(FLayout.FRuns[K].Bounds.Left,Shift); Inc(FLayout.FRuns[K].Bounds.Right,Shift); FLayout.FRuns[K].Line:=Line end;
    SetLength(FLayout.FLines,Length(FLayout.FLines)+1); FLayout.FLines[High(FLayout.FLines)]:=L; Inc(Line); Inc(Y,MaxLineH+Options.LineSpacing); X:=Options.Borders.Left; First:=Length(FLayout.FRuns); Count:=0; MaxLineH:=Canvas.TextHeight('Tg');
  end;
begin
  FLayoutKey := FSourceHash xor HashOptions(Options) xor Cardinal(Options.Width);
  if (FLayout.SourceHash=FLayoutKey) and (FLayout.Width=Options.Width) and
    (FLayout.FScale=Options.Scale) then Exit(FLayout);
  if FStyleKey<>HashOptions(Options) then
  begin
    BuildStyles(Options);
    FStyleKey := HashOptions(Options);
  end;
  FLayout.Clear; FLayout.FSourceHash:=FLayoutKey; FLayout.FWidth:=Options.Width; FLayout.FScale:=Options.Scale;
  Avail:=Options.Width-Options.Borders.Left-Options.Borders.Right; if Avail<1 then Avail:=1; X:=Options.Borders.Left; Y:=Options.Borders.Top; First:=0; Count:=0; Line:=0; MaxLineH:=Canvas.TextHeight('Tg');
  I := 0;
  while I <= High(FStyled) do
  begin
    R:=FStyled[I];
    if R.Control=1 then
    begin
      J := I+1; D := 1;
      while (J<=High(FStyled)) and (D>0) do
      begin
        if FStyled[J].Control=1 then Inc(D)
        else if FStyled[J].Control=6 then Dec(D);
        if D>0 then Inc(J);
      end;
      if J<=High(FStyled) then LayoutTable(Canvas,Options,I,J,X,Y,Line);
      I := J+1; Continue;
    end;
    if R.Control<>0 then begin Inc(I); Continue end;
    if R.IsImage then begin Sz:=Types.Size(16,16); Text:=#1 end else Text:=R.Text;
    P:=1;
    while P<=Length(Text) do
    begin
      if Text[P]=#10 then begin Inc(P); FinishLine; Continue end;
      Start:=P;
      if Text[P] in [' ',#9] then
        while (P<=Length(Text)) and (Text[P] in [' ',#9]) do Inc(P)
      else
        while (P<=Length(Text)) and not (Text[P] in [' ',#9,#10]) do
        begin C:=CodepointAt(Text,P,Bytes); Inc(P,Bytes); if IsCJK(C) then Break end;
      Atom:=Copy(Text,Start,P-Start); R.Text:=Atom;
      Sz:=MeasureRun(Canvas,R); W:=Sz.cx; if (Count>0) and (X+W>Options.Width-Options.Borders.Right) and (Atom[1]<>' ') and (Atom[1]<>#9) then FinishLine;
      R.Bounds:=Rect(X,Y,X+W,Y+Sz.cy); if Count=0 then First:=Length(FLayout.FRuns); SetLength(FLayout.FRuns,Length(FLayout.FRuns)+1); FLayout.FRuns[High(FLayout.FRuns)]:=R; Inc(Count); Inc(X,W); MaxLineH:=Max(MaxLineH,Sz.cy);
    end;
    Inc(I);
  end;
  FinishLine; FLayout.FSize:=Types.Size(Options.Width,Y+Options.Borders.Bottom); Result:=FLayout;
end;

procedure TInkNextRenderer.Paint(Canvas: TCanvas; const Bounds: TRect; const Options: TInkNextOptions);
var I,J: Integer; L: TInkNextLine; R: TInkNextRun; Clip: TRect; C,BG: TColor;
  OldFont: TFont; OldBrushStyle: TBrushStyle; OldBrushColor: TColor;
begin
  Layout(Canvas,Options); Clip:=Bounds; IntersectRect(Clip,Clip,Canvas.ClipRect);
  OldFont:=TFont.Create; OldFont.Assign(Canvas.Font); OldBrushStyle:=Canvas.Brush.Style; OldBrushColor:=Canvas.Brush.Color;
  try
    for I:=0 to High(FLayout.FLines) do begin L:=FLayout.FLines[I]; if (L.Bounds.Bottom<Clip.Top) or (L.Bounds.Top>Clip.Bottom) then Continue;
      for J:=L.FirstRun to L.FirstRun+L.RunCount-1 do begin
        R:=FLayout.FRuns[J];
        if (R.Bounds.Right<Clip.Left) or (R.Bounds.Left>Clip.Right) then Continue;
        Canvas.Font.Name:=R.Style.Face; Canvas.Font.Size:=R.Style.Size; Canvas.Font.Style:=R.Style.Styles;
        C:=R.Style.Color; BG:=R.Style.BackColor;
        if R.Style.LinkIndex>0 then begin C:=Options.LinkColor; if Options.LinkUnderline then Canvas.Font.Style:=Canvas.Font.Style+[fsUnderline]; if R.Style.LinkIndex=Options.HoverIndex then begin C:=Options.HoverColor; BG:=Options.HoverBackColor; if Options.HoverUnderline then Canvas.Font.Style:=Canvas.Font.Style+[fsUnderline] end end;
        Canvas.Font.Color:=C;
        if BG<>clNone then begin Canvas.Brush.Style:=bsSolid; Canvas.Brush.Color:=BG; Canvas.FillRect(R.Bounds) end;
        if R.IsImage and (Options.Images<>nil) and (R.ImageIndex>=0) and (R.ImageIndex<Options.Images.Count) then
          Options.Images.Draw(Canvas,R.Bounds.Left,R.Bounds.Top,R.ImageIndex)
        else if not R.IsImage then Canvas.TextOut(R.Bounds.Left,R.Bounds.Top,R.Text);
      end;
    end;
  finally Canvas.Font.Assign(OldFont); Canvas.Brush.Style:=OldBrushStyle; Canvas.Brush.Color:=OldBrushColor; OldFont.Free end;
end;

function TInkNextRenderer.HitTest(const Canvas: TCanvas; X, Y: Integer): TInkNextHit;
var I: Integer; R: TInkNextRun; P: Integer; W: Integer; F: TFont;
begin
  Result.OnLink := False; Result.LinkIndex := 0; Result.LinkName := '';
  Result.LinkText := ''; Result.RunIndex := -1; Result.CharacterOffset := 0;
  if FLayout=nil then Exit; F:=TFont.Create; try
    for I:=0 to High(FLayout.FRuns) do begin R:=FLayout.FRuns[I]; if not PtInRect(R.Bounds,Point(X,Y)) or (R.Style.LinkIndex=0) then Continue;
      Result.OnLink:=True; Result.LinkIndex:=R.Style.LinkIndex; Result.LinkName:=R.Style.LinkName; Result.RunIndex:=I; Result.CharacterOffset:=0; W:=R.Bounds.Left;
      F.Assign(Canvas.Font); Canvas.Font.Name:=R.Style.Face; Canvas.Font.Size:=R.Style.Size; for P:=1 to Length(R.Text) do begin if W+Canvas.TextWidth(Copy(R.Text,1,P))>X then Break; Result.CharacterOffset:=P end;
      Exit;
    end;
  finally Canvas.Font.Assign(F); F.Free end;
end;

end.
