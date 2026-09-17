{ A deliberately small stylesheet reader for native help pages. MIT. }
unit InkCSS;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics;
type
  TInkStyleSheet = class
  private
    FRules, FVars: TStringList;
  public
    function Resolve(const S: string): string;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(const CSS: string);
    function Value(const Tag, Classes, Prop, Fallback: string): string;
    function Color(const Tag, Classes, Prop: string; Fallback: TColor): TColor;
    function Pixels(const Tag, Classes, Prop: string; Fallback: Integer): Integer;
  end;
implementation
uses InkHtml;
constructor TInkStyleSheet.Create;
begin inherited; FRules := TStringList.Create; FVars := TStringList.Create end;
destructor TInkStyleSheet.Destroy;
begin Clear; FRules.Free; FVars.Free; inherited end;
procedure TInkStyleSheet.Clear;
var I: Integer;
begin
  for I := 0 to FRules.Count-1 do FRules.Objects[I].Free;
  FRules.Clear; FVars.Clear;
end;
procedure TInkStyleSheet.Add(const CSS: string);
var S, Selector, Body, Pair, Name: string; P,Q,Depth,I: Integer; Props, Selectors: TStringList;
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
        if (Selector=':root') and (Copy(Name,1,2)='--') then FVars.Values[Name] := Props.Values[Name];
      end;
      Selectors := TStringList.Create;
      try
        Selectors.StrictDelimiter := True; Selectors.Delimiter := ','; Selectors.DelimitedText := Selector;
        for I := 0 to Selectors.Count-1 do
        begin
          FRules.AddObject(Trim(Selectors[I]),TStringList.Create);
          TStringList(FRules.Objects[FRules.Count-1]).Assign(Props);
        end;
      finally Selectors.Free end;
    finally Props.Free end;
  end;
end;
function TInkStyleSheet.Resolve(const S: string): string;
var I: Integer;
begin
  Result := Trim(S);
  for I := 1 to 8 do
    if (Copy(Result,1,4)='var(') and (Result[Length(Result)]=')') then
      Result := FVars.Values[Trim(Copy(Result,5,Length(Result)-5))]
    else Break;
end;
function TInkStyleSheet.Value(const Tag, Classes, Prop, Fallback: string): string;
var I,P,Score,Best: Integer; Sel,T,C,V: string;
begin
  Result := Fallback; Best := -1;
  for I := 0 to FRules.Count-1 do
  begin
    Sel := FRules[I]; Score := 0;
    if (Pos(' ',Sel)>0) or (Pos(':',Sel)>0) or (Pos('>',Sel)>0) then Continue;
    P := Pos('.',Sel); T := Sel; C := '';
    if P>0 then begin T := Copy(Sel,1,P-1); C := Copy(Sel,P+1,MaxInt); Inc(Score,10) end;
    if (T<>'') and (T<>'*') then begin if T<>Tag then Continue; Inc(Score) end;
    if (C<>'') and (Pos(' '+C+' ',' '+Classes+' ')=0) then Continue;
    V := TStringList(FRules.Objects[I]).Values[Prop];
    if (V<>'') and (Score>=Best) then begin Result := Resolve(V); Best := Score end;
  end;
end;
function TInkStyleSheet.Color(const Tag, Classes, Prop: string; Fallback: TColor): TColor;
begin Result := HTMLStringToColor(Value(Tag,Classes,Prop,''),Fallback) end;
function TInkStyleSheet.Pixels(const Tag, Classes, Prop: string; Fallback: Integer): Integer;
var S: string;
begin
  S := Value(Tag,Classes,Prop,'');
  if Copy(S,Length(S)-1,2)='px' then Delete(S,Length(S)-1,2);
  Result := StrToIntDef(S,Fallback);
end;
end.
