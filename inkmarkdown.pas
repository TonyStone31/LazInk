{ LazInk Markdown subset converter. Component code: MIT. }
unit InkMarkdown;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
type TInkTextFormat = (itfHTML, itfMarkdown);
function MarkdownToInk(const S: string): string;
function InkToHTML(const S: string; AFormat: TInkTextFormat): string;
implementation
function Escape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;
function Inline(const S: string): string;
var P, Q, N, E: Integer; Mark, Tag, Body: string;
begin
  Result := ''; P := 1;
  while P <= Length(S) do
  begin
    if (S[P] = '\') and (P < Length(S)) then
    begin Inc(P); Result := Result + Escape(S[P]); Inc(P); Continue end;
    if S[P] = '[' then
    begin
      Q := P + 1;
      while (Q <= Length(S)) and (S[Q] <> ']') do Inc(Q);
      if (Q < Length(S)) and (S[Q+1] = '(') then
      begin
        E := Q + 2;
        while (E <= Length(S)) and (S[E] <> ')') do Inc(E);
        if E <= Length(S) then
        begin
          Result := Result + '<a href="' + Escape(Copy(S,Q+2,E-Q-2)) + '">' +
            Inline(Copy(S,P+1,Q-P-1)) + '</a>';
          P := E+1; Continue;
        end;
      end;
    end;
    Mark := ''; Tag := '';
    if S[P] = '`' then begin Mark := '`'; Tag := 'font face="monospace"' end
    else if Copy(S,P,2) = '**' then begin Mark := '**'; Tag := 'b' end
    else if Copy(S,P,2) = '~~' then begin Mark := '~~'; Tag := 's' end
    else if S[P] = '*' then begin Mark := '*'; Tag := 'i' end;
    if Mark <> '' then
    begin
      N := Length(Mark); Q := Pos(Mark, Copy(S,P+N,MaxInt));
      if Q > 0 then
      begin
        Body := Copy(S,P+N,Q-1);
        if Mark = '`' then Body := Escape(Body) else Body := Inline(Body);
        Result := Result + '<' + Tag + '>' + Body;
        if Mark = '`' then Tag := 'font';
        Result := Result + '</' + Tag + '>';
        Inc(P, Q-1+2*N); Continue;
      end;
    end;
    Result := Result + Escape(S[P]); Inc(P);
  end;
end;
procedure Cells(const S: string; A: TStrings);
var T, Cell: string; P: Integer; Code: Boolean;
begin
  A.Clear; T := Trim(S);
  if (T <> '') and (T[1] = '|') then Delete(T,1,1);
  if (T <> '') and (T[Length(T)] = '|') and
    ((Length(T) < 2) or (T[Length(T)-1] <> '\')) then Delete(T,Length(T),1);
  Cell := ''; Code := False; P := 1;
  while P <= Length(T) do
  begin
    if (T[P] = '\') and (P < Length(T)) then
    begin Cell := Cell + T[P] + T[P+1]; Inc(P,2); Continue end;
    if T[P] = '`' then Code := not Code;
    if (T[P] = '|') and not Code then begin A.Add(Trim(Cell)); Cell := '' end
    else Cell := Cell + T[P];
    Inc(P);
  end;
  A.Add(Trim(Cell));
end;
function Divider(const S: string; A: TStrings): Boolean;
var I, J, N: Integer; T: string;
begin
  Cells(S,A); Result := False;
  for I := 0 to A.Count-1 do
  begin
    T := A[I]; N := 0;
    if (T <> '') and (T[1] = ':') then Delete(T,1,1);
    if (T <> '') and (T[Length(T)] = ':') then Delete(T,Length(T),1);
    for J := 1 to Length(T) do if T[J] = '-' then Inc(N) else Exit;
    if N < 3 then Exit;
  end;
  Result := A.Count > 0;
end;
function MarkdownToInk(const S: string): string;
var L, A: TStringList; I, J, H: Integer; T, Tag: string; Fence, Table: Boolean;
begin
  Result := ''; L := TStringList.Create; A := TStringList.Create;
  try
    L.Text := S; I := 0; Fence := False; Table := False;
    while I < L.Count do
    begin
      T := Trim(L[I]);
      if Copy(T,1,3) = '```' then
      begin
        if Fence then Result := Result + '</font><br>'
        else Result := Result + '<font face="monospace">';
        Fence := not Fence; Inc(I); Continue;
      end;
      if Fence then Result := Result + Escape(L[I]) + '<br>'
      else if (I+1 < L.Count) and (Pos('|',T) > 0) and Divider(L[I+1],A) then
      begin
        Result := Result + '<table>'; Table := True;
        Cells(T,A); Result := Result + '<tr>';
        for J := 0 to A.Count-1 do Result := Result + '<th>' + Inline(A[J]) + '</th>';
        Result := Result + '</tr>'; Inc(I);
      end
      else if Table and (Pos('|',T) > 0) then
      begin
        Cells(T,A); Result := Result + '<tr>';
        for J := 0 to A.Count-1 do Result := Result + '<td>' + Inline(A[J]) + '</td>';
        Result := Result + '</tr>';
      end
      else
      begin
        if Table then begin Result := Result + '</table>'; Table := False end;
        H := 0; while (H < Length(T)) and (T[H+1] = '#') do Inc(H);
        if (H in [1..6]) and (H < Length(T)) and (T[H+1] = ' ') then
        begin
          Tag := IntToStr(22-H*2);
          Result := Result + '<font size="'+Tag+'"><b>'+Inline(Trim(Copy(T,H+2,MaxInt)))+'</b></font><br>';
        end
        else if (Copy(T,1,2) = '- ') or (Copy(T,1,2) = '* ') or (Copy(T,1,2) = '+ ') then
          Result := Result + '• ' + Inline(Copy(T,3,MaxInt)) + '<br>'
        else Result := Result + Inline(T) + '<br>';
      end;
      Inc(I);
    end;
    if Table then Result := Result + '</table>';
    if Fence then Result := Result + '</font>';
  finally A.Free; L.Free end;
end;
function InkToHTML(const S: string; AFormat: TInkTextFormat): string;
begin
  if AFormat = itfMarkdown then Result := MarkdownToInk(S) else Result := S;
end;
end.
