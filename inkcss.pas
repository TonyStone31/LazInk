{ A deliberately small stylesheet reader for native help pages. MIT. }
unit InkCSS;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Types;
type
  { Where an element sits: its ancestors, outermost first, each written
    "tag.class.class" - "table.cards td".  With one, selectors like
    "table.cards small" or "nav > a" match; without, only simple ones. }
  TInkCSSContext = string;
  { One rule's declarations, and the width it applies at: an @media
    (min-width) / (max-width) block, or always.  Media the reader cannot
    judge - print, color schemes - never apply. }
  TInkRule = class(TStringList)
  public
    MinWidth, MaxWidth: Integer;
    Never: Boolean;
    function Applies(AWidth: Integer): Boolean;
  end;

  TInkStyleSheet = class
  private
    FRules, FVars, FConditions: TStringList;
    FMediaWidth: Integer;
    { the @media block being read }
    FMin, FMax: Integer;
    FNever, FInMedia: Boolean;
    procedure ReadMedia(const Condition, Body: string);
  public
    function Resolve(const S: string): string;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(const CSS: string);
    function Value(const Tag, Classes, Prop, Fallback: string;
      const Context: TInkCSSContext = ''): string;
    function Color(const Tag, Classes, Prop: string; Fallback: TColor;
      const Context: TInkCSSContext = ''): TColor;
    function Pixels(const Tag, Classes, Prop: string; Fallback: Integer;
      const Context: TInkCSSContext = ''): Integer;
    { padding or margin: the shorthand's one to four values, then the
      -top/-right/-bottom/-left longhands over them; Left, Top, Right,
      Bottom in pixels, Fallback where nothing is said }
    function Box(const Tag, Classes, Prop: string; const Fallback: TRect;
      const Context: TInkCSSContext = ''): TRect;
    { a border: its color (clNone for "none"), and whether one was given at
      all; Sides says which of top, right, bottom, left have one ('trbl') }
    function Border(const Tag, Classes: string; out AColor: TColor;
      out Sides: string; const Context: TInkCSSContext = ''): Boolean;
    { a property of one selector exactly as written - '::selection' }
    function RuleValue(const Selector, Prop, Fallback: string): string;
    { The width, in pixels, @media width queries are judged against - the
      page's own width.  1024 until a page says otherwise. }
    property MediaWidth: Integer read FMediaWidth write FMediaWidth;
    { which of the sheet's width queries hold at AWidth, as a string that
      changes when any of them does - '' when there are none }
    function MediaState(AWidth: Integer): string;
  end;
{ One declaration out of a style attribute - StyleValue('color: red; margin: 0',
  'color') is 'red' - trimmed, with its case kept.  The last of a repeated
  property wins, as in a stylesheet.  '' when it is not there. }
function StyleValue(const AStyle, AProp: string): string;
{ #rgb, #rrggbb, rgb()/rgba(), a color name, "none"/"transparent" (clNone),
  or Fallback }
function CSSColor(const S: string; Fallback: TColor): TColor;
{ a length in pixels: "12px", "12", "-10px", "1em" (16 px), or Fallback }
function CSSPixels(const S: string; Fallback: Integer): Integer;

implementation
uses InkDraw, Math;

function TInkRule.Applies(AWidth: Integer): Boolean;
begin
  Result := not Never and ((MinWidth <= 0) or (AWidth >= MinWidth)) and
    ((MaxWidth <= 0) or (AWidth <= MaxWidth));
end;

function StyleValue(const AStyle, AProp: string): string;
var P,Start,Depth,Colon: Integer; Decl,Name,Wanted: string;
begin
  Result := ''; Wanted := LowerCase(Trim(AProp));
  Start := 1; Depth := 0;
  for P := 1 to Length(AStyle)+1 do
  begin
    if P<=Length(AStyle) then
    begin
      if AStyle[P]='(' then Inc(Depth)
      else if AStyle[P]=')' then Dec(Depth);
      { a semicolon inside rgb(...) or url(...) does not end a declaration }
      if (AStyle[P]<>';') or (Depth>0) then Continue;
    end;
    Decl := Copy(AStyle,Start,P-Start); Start := P+1;
    Colon := Pos(':',Decl);
    if Colon=0 then Continue;
    Name := LowerCase(Trim(Copy(Decl,1,Colon-1)));
    { the last one written wins, as a stylesheet's declarations do }
    if Name=Wanted then Result := Trim(Copy(Decl,Colon+1,MaxInt));
  end;
end;

function CSSColor(const S: string; Fallback: TColor): TColor;
var V, Inner: string; Parts: TStringList; R,G,B: Integer;
begin
  V := LowerCase(Trim(S));
  if V='' then Exit(Fallback);
  if (V='none') or (V='transparent') then Exit(clNone);
  if (Copy(V,1,4)='rgb(') or (Copy(V,1,5)='rgba(') then
  begin
    Result := Fallback;
    if V[Length(V)]<>')' then Exit;
    Inner := Copy(V,Pos('(',V)+1,Length(V)-Pos('(',V)-1);
    Inner := StringReplace(Inner,',',' ',[rfReplaceAll]);
    Inner := StringReplace(Inner,'/',' ',[rfReplaceAll]);
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
      Parts.DelimitedText := Inner;
      if Parts.Count<3 then Exit;
      R := StrToIntDef(Parts[0],-1); G := StrToIntDef(Parts[1],-1); B := StrToIntDef(Parts[2],-1);
      if (R<0) or (G<0) or (B<0) or (R>255) or (G>255) or (B>255) then Exit;
      Result := RGBToColor(R,G,B);
    finally Parts.Free end;
    Exit;
  end;
  if (Length(V)=4) and (V[1]='#') then V := '#'+V[2]+V[2]+V[3]+V[3]+V[4]+V[4];
  Result := HTMLStringToColor(V,Fallback);
end;

function CSSPixels(const S: string; Fallback: Integer): Integer;
var V: string; F: Double; Mult: Double;
begin
  V := LowerCase(Trim(S));
  Mult := 1;
  if Copy(V,Length(V)-1,2)='px' then SetLength(V,Length(V)-2)
  else if (Copy(V,Length(V)-2,3)='rem') then begin SetLength(V,Length(V)-3); Mult := 16 end
  else if Copy(V,Length(V)-1,2)='em' then begin SetLength(V,Length(V)-2); Mult := 16 end;
  if not TryStrToFloat(V,F,DefaultFormatSettings) then
  begin
    V := StringReplace(V,'.',DefaultFormatSettings.DecimalSeparator,[]);
    if not TryStrToFloat(V,F) then Exit(Fallback);
  end;
  Result := Round(F*Mult);
end;

{ "td.empty" against a tag and its classes; Score is the selector's weight }
function MatchSimple(const Sel, Tag, Classes: string; out Score: Integer): Boolean;
var Parts: TStringList; T: string; I: Integer;
begin
  Result := False; Score := 0;
  if Sel='' then Exit;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True; Parts.Delimiter := '.';
    Parts.DelimitedText := Sel;
    T := Parts[0];
    if (T<>'') and (T<>'*') then
    begin
      if T<>Tag then Exit;
      Inc(Score);
    end;
    for I := 1 to Parts.Count-1 do
    begin
      if Parts[I]='' then Continue;
      if Pos(' '+Parts[I]+' ',' '+Classes+' ')=0 then Exit;
      Inc(Score,10);
    end;
    Result := True;
  finally Parts.Free end;
end;
constructor TInkStyleSheet.Create;
begin
  inherited;
  FRules := TStringList.Create; FVars := TStringList.Create;
  FConditions := TStringList.Create; FConditions.Sorted := True; FConditions.Duplicates := dupIgnore;
  FMediaWidth := 1024;
end;
destructor TInkStyleSheet.Destroy;
begin Clear; FRules.Free; FVars.Free; FConditions.Free; inherited end;
{ "(max-width: 600px)", "screen and (min-width:40em)", "print" }
procedure TInkStyleSheet.ReadMedia(const Condition, Body: string);
var C, Feature: string; P, Q: Integer; OldMin, OldMax: Integer; OldNever, OldIn: Boolean;
begin
  OldMin := FMin; OldMax := FMax; OldNever := FNever; OldIn := FInMedia;
  try
    FInMedia := True;
    C := LowerCase(Condition);
    if (Pos('print',C)>0) and (Pos('screen',C)=0) then FNever := True;
    if Pos(' not ',' '+C)>0 then FNever := True;
    P := Pos('(',C);
    while P>0 do
    begin
      Q := Pos(')',C);
      if Q<P then Break;
      Feature := StringReplace(Copy(C,P+1,Q-P-1),' ','',[rfReplaceAll]);
      Delete(C,1,Q);
      if Copy(Feature,1,10)='max-width:' then FMax := CSSPixels(Copy(Feature,11,MaxInt),0)
      else if Copy(Feature,1,10)='min-width:' then FMin := CSSPixels(Copy(Feature,11,MaxInt),0)
      else FNever := True;          // a feature this reader cannot judge
      P := Pos('(',C);
    end;
    if not FNever then FConditions.Add(IntToStr(FMin)+':'+IntToStr(FMax));
    Add(Body);
  finally
    FMin := OldMin; FMax := OldMax; FNever := OldNever; FInMedia := OldIn;
  end;
end;
function TInkStyleSheet.MediaState(AWidth: Integer): string;
var I, K: Integer; Cond: string;
begin
  Result := '';
  for I := 0 to FConditions.Count-1 do
  begin
    Cond := FConditions[I];
    K := Pos(':',Cond);
    if ((StrToIntDef(Copy(Cond,1,K-1),0)<=0) or (AWidth>=StrToIntDef(Copy(Cond,1,K-1),0))) and
      ((StrToIntDef(Copy(Cond,K+1,MaxInt),0)<=0) or (AWidth<=StrToIntDef(Copy(Cond,K+1,MaxInt),0))) then
      Result := Result+'1'
    else Result := Result+'0';
  end;
end;
procedure TInkStyleSheet.Clear;
var I: Integer;
begin
  for I := 0 to FRules.Count-1 do FRules.Objects[I].Free;
  FRules.Clear; FVars.Clear; FConditions.Clear;
end;
procedure TInkStyleSheet.Add(const CSS: string);
var S, Selector, Body, Pair, Name: string; P,Q,Depth,I: Integer; Props, Selectors: TStringList;
  Rule: TInkRule;
begin
  S := CSS;
  P := Pos('/*',S);
  while P > 0 do
  begin
    Q := Pos('*/',Copy(S,P+2,MaxInt));
    if Q = 0 then Delete(S,P,MaxInt) else Delete(S,P,Q+3);
    P := Pos('/*',S);
  end;
  while Pos('{',S)>0 do
  begin
    P := Pos('{',S); Selector := Trim(Copy(S,1,P-1)); Q := P+1; Depth := 1;
    while (Q <= Length(S)) and (Depth > 0) do
    begin
      if S[Q]='{' then Inc(Depth) else if S[Q]='}' then Dec(Depth);
      Inc(Q);
    end;
    Body := Copy(S,P+1,Q-P-2); Delete(S,1,Q-1);
    if LowerCase(Copy(Selector,1,6))='@media' then
    begin
      ReadMedia(Copy(Selector,7,MaxInt),Body);
      Continue;
    end;
    if (Selector='') or (Selector[1]='@') then Continue;
    Props := TStringList.Create;
    try
      while Body <> '' do
      begin
        P := Pos(';',Body); if P=0 then P := Length(Body)+1;
        Pair := Trim(Copy(Body,1,P-1)); Delete(Body,1,P);
        P := Pos(':',Pair); if P=0 then Continue;
        Name := LowerCase(Trim(Copy(Pair,1,P-1)));
        Props.Values[Name] := Trim(Copy(Pair,P+1,MaxInt));
        if (Selector=':root') and (Copy(Name,1,2)='--') and not FInMedia then
          FVars.Values[Name] := Props.Values[Name];
      end;
      Selectors := TStringList.Create;
      try
        Selectors.StrictDelimiter := True; Selectors.Delimiter := ','; Selectors.DelimitedText := Selector;
        for I := 0 to Selectors.Count-1 do
        begin
          Rule := TInkRule.Create;
          Rule.Assign(Props);
          Rule.MinWidth := FMin; Rule.MaxWidth := FMax; Rule.Never := FNever;
          FRules.AddObject(Trim(Selectors[I]),Rule);
        end;
      finally Selectors.Free end;
    finally Props.Free end;
  end;
end;
function TInkStyleSheet.Resolve(const S: string): string;
var I,P,Q,Depth,Comma: Integer; Expr,Replacement: string;
begin
  Result := Trim(S);
  for I := 1 to 32 do
  begin
    P := Pos('var(',Result); if P=0 then Exit;
    Q := P+4; Depth := 1;
    while (Q<=Length(Result)) and (Depth>0) do
    begin
      if Result[Q]='(' then Inc(Depth) else if Result[Q]=')' then Dec(Depth);
      Inc(Q);
    end;
    if Depth<>0 then Exit('');
    Expr := Copy(Result,P+4,Q-P-5); Comma := Pos(',',Expr);
    if Comma>0 then
    begin
      Replacement := FVars.Values[LowerCase(Trim(Copy(Expr,1,Comma-1)))];
      if Replacement='' then Replacement := Trim(Copy(Expr,Comma+1,MaxInt));
    end
    else Replacement := FVars.Values[LowerCase(Trim(Expr))];
    if Replacement='' then Exit('');
    Delete(Result,P,Q-P); Insert(Replacement,Result,P);
  end;
  { Cyclic custom properties invalidate the value, rather than looping. }
  if Pos('var(',Result)>0 then Result := '';
end;
function TInkStyleSheet.Value(const Tag, Classes, Prop, Fallback: string;
  const Context: TInkCSSContext): string;
var I,K,J,Score,Part,Best: Integer; Sel,V,Tok,TokTag,TokClasses: string;
  Parts, Ancestors: TStringList; Matched: Boolean;
begin
  Result := Fallback; Best := -1;
  Parts := TStringList.Create;
  Ancestors := TStringList.Create;
  try
    Ancestors.Delimiter := ' '; Ancestors.StrictDelimiter := False;
    Ancestors.DelimitedText := Context;
    for I := 0 to FRules.Count-1 do
    begin
      Sel := FRules[I]; Score := 0;
      if Sel=':root' then
      begin
        if Tag<>'html' then Continue;
        Sel := 'html'; Score := 10;
      end;
      if Pos(':',Sel)>0 then Continue;
      if not TInkRule(FRules.Objects[I]).Applies(FMediaWidth) then Continue;
      Sel := StringReplace(Sel,'>',' ',[rfReplaceAll]);
      Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
      Parts.DelimitedText := Sel;
      if Parts.Count=0 then Continue;
      if not MatchSimple(Parts[Parts.Count-1],Tag,Classes,Part) then Continue;
      Inc(Score,Part);
      { the rest, right to left, each somewhere further out than the last }
      Matched := True;
      K := Ancestors.Count-1;
      for J := Parts.Count-2 downto 0 do
      begin
        Matched := False;
        while K>=0 do
        begin
          Tok := Ancestors[K]; Dec(K);
          TokTag := Tok; TokClasses := '';
          if Pos('.',Tok)>0 then
          begin
            TokTag := Copy(Tok,1,Pos('.',Tok)-1);
            TokClasses := StringReplace(Copy(Tok,Pos('.',Tok)+1,MaxInt),'.',' ',[rfReplaceAll]);
          end;
          if MatchSimple(Parts[J],TokTag,TokClasses,Part) then
          begin
            Inc(Score,Part);
            Matched := True;
            Break;
          end;
        end;
        if not Matched then Break;
      end;
      if not Matched then Continue;
      V := TStringList(FRules.Objects[I]).Values[Prop];
      { a value whose var() cannot be resolved is invalid, and an invalid
        declaration is dropped - it does not wipe out one that was valid }
      if V<>'' then V := Resolve(V);
      if (V<>'') and (Score>=Best) then begin Result := V; Best := Score end;
    end;
  finally
    Parts.Free;
    Ancestors.Free;
  end;
end;
function TInkStyleSheet.RuleValue(const Selector, Prop, Fallback: string): string;
var I: Integer; V: string;
begin
  Result := Fallback;
  for I := 0 to FRules.Count-1 do
    if SameText(FRules[I],Selector) and TInkRule(FRules.Objects[I]).Applies(FMediaWidth) then
    begin
      V := TStringList(FRules.Objects[I]).Values[Prop];
      if V<>'' then V := Resolve(V);
      if V<>'' then Result := V;
    end;
end;
function TInkStyleSheet.Color(const Tag, Classes, Prop: string; Fallback: TColor;
  const Context: TInkCSSContext): TColor;
begin Result := CSSColor(Value(Tag,Classes,Prop,'',Context),Fallback) end;
function TInkStyleSheet.Pixels(const Tag, Classes, Prop: string; Fallback: Integer;
  const Context: TInkCSSContext): Integer;
begin Result := CSSPixels(Value(Tag,Classes,Prop,'',Context),Fallback) end;
function TInkStyleSheet.Box(const Tag, Classes, Prop: string; const Fallback: TRect;
  const Context: TInkCSSContext): TRect;
var Parts: TStringList; V: string; N: array[0..3] of Integer; I: Integer;
begin
  Result := Fallback;
  V := Value(Tag,Classes,Prop,'',Context);
  if V<>'' then
  begin
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
      Parts.DelimitedText := V;
      if (Parts.Count>=1) and (Parts.Count<=4) then
      begin
        for I := 0 to Parts.Count-1 do N[I] := CSSPixels(Parts[I],0);
        case Parts.Count of
          1: Result := Rect(N[0],N[0],N[0],N[0]);
          2: Result := Rect(N[1],N[0],N[1],N[0]);
          3: Result := Rect(N[1],N[0],N[1],N[2]);
        else
          Result := Rect(N[3],N[0],N[1],N[2]);
        end;
      end;
    finally Parts.Free end;
  end;
  Result.Top := Pixels(Tag,Classes,Prop+'-top',Result.Top,Context);
  Result.Right := Pixels(Tag,Classes,Prop+'-right',Result.Right,Context);
  Result.Bottom := Pixels(Tag,Classes,Prop+'-bottom',Result.Bottom,Context);
  Result.Left := Pixels(Tag,Classes,Prop+'-left',Result.Left,Context);
end;
function TInkStyleSheet.Border(const Tag, Classes: string; out AColor: TColor;
  out Sides: string; const Context: TInkCSSContext): Boolean;
const
  Names: array[0..3] of string = ('top','right','bottom','left');
  Letters: array[0..3] of Char = ('t','r','b','l');
var V: string; I: Integer; C: TColor;

  { "1px solid #ccc" - the color is the part that reads as one; "none" or a
    zero width is no border }
  function ColorOf(const Spec: string; out Col: TColor): Boolean;
  var Parts: TStringList; K: Integer; Low: string;
  begin
    Result := False; Col := clNone;
    Low := LowerCase(Trim(Spec));
    if Low='' then Exit;
    Result := True;
    if (Low='none') or (Low='0') or (Pos('none',Low)>0) or (Pos('hidden',Low)>0) then Exit;
    Col := clDefault;
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ' '; Parts.StrictDelimiter := False;
      Parts.DelimitedText := Spec;
      for K := 0 to Parts.Count-1 do
        if (CSSColor(Parts[K],clNone)<>clNone) and (CSSPixels(Parts[K],-1)=-1) then
          Col := CSSColor(Parts[K],clDefault);
    finally Parts.Free end;
  end;

begin
  Result := False; AColor := clDefault; Sides := '';
  V := Value(Tag,Classes,'border','',Context);
  if V<>'' then
  begin
    Result := True;
    if ColorOf(V,C) then AColor := C;
    if C<>clNone then Sides := 'trbl';
  end;
  V := Value(Tag,Classes,'border-color','',Context);
  if V<>'' then AColor := CSSColor(V,AColor);
  for I := 0 to 3 do
  begin
    V := Value(Tag,Classes,'border-'+Names[I],'',Context);
    if V='' then Continue;
    Result := True;
    ColorOf(V,C);
    if C=clNone then Sides := StringReplace(Sides,Letters[I],'',[])
    else
    begin
      if Pos(Letters[I],Sides)=0 then Sides := Sides+Letters[I];
      if C<>clDefault then AColor := C;
    end;
  end;
  if Result and (Sides='') then AColor := clNone;
end;
end.
