{ LazInk Markdown converter.  SPDX-License-Identifier: 0BSD

  Markdown is read in one place, here, and turned into HTML.
  MarkdownToHTML writes real block elements - headings, paragraphs, lists,
  code blocks, quotes, tables - for TInkPage and for anything else that reads
  HTML.  MarkdownToInk flattens that same HTML into the inline markup the
  label, memo and list box renderer draws, so a new Markdown feature is added
  once and every control gets it.

  Read: GitHub-flavored Markdown, the parts real documents use - ATX and
  setext headings (with GitHub's anchors), paragraphs joined across wrapped
  lines, hard breaks, bullet and numbered lists with wrapped and lazy
  continuation lines and nesting by indentation, task lists, fenced code
  (the language kept as class="language-x") and indented code, blockquotes
  and GitHub's "> [!NOTE]" alerts, horizontal rules, pipe tables with their
  alignment, * _ ** __ *** and ~~ emphasis, code spans, inline, reference
  and angle-bracket links, bare http(s):// and www. links, images, entities
  and backslash escapes.  HTML comments are dropped.  Other raw HTML is shown
  as text unless imoRawHTML is given.

  Not CommonMark-complete, on purpose: emphasis follows simpler rules than
  the specification's delimiter algorithm, a link reference definition has
  to fit on one line, and footnotes are not read. }
unit InkMarkdown;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
type
  TInkTextFormat = (itfHTML, itfMarkdown);
  TInkMarkdownOption = (
    { pass HTML written in the Markdown through, instead of showing it as
      text - only for documents you trust }
    imoRawHTML);
  TInkMarkdownOptions = set of TInkMarkdownOption;

{ Markdown to HTML with block elements. }
function MarkdownToHTML(const S: string; Options: TInkMarkdownOptions = []): string;
{ Markdown to the inline markup TInkLabel, TInkMemo and TInkListBox draw. }
function MarkdownToInk(const S: string; Options: TInkMarkdownOptions = []): string;
{ HTML, as MarkdownToHTML writes it, flattened to that inline markup. }
function HTMLToInk(const S: string): string;
{ What a control draws for Source in the given format. }
function InkToHTML(const S: string; AFormat: TInkTextFormat): string;
{ A heading's text as GitHub makes an anchor of it:
  "Complete help pages" -> "complete-help-pages". }
function MarkdownSlug(const Text: string): string;
{ The fixed-width face code is drawn in on this platform. }
function InkMonoFace: string;

implementation

const
  LF = #10;
  BULLET = #$E2#$80#$A2;       // •
  BOX_EMPTY = #$E2#$98#$90;    // ☐
  BOX_TICKED = #$E2#$98#$91;   // ☑
  QUOTE_BAR = #$E2#$94#$82;    // │

function InkMonoFace: string;
begin
  {$IFDEF WINDOWS}
  Result := 'Consolas';
  {$ELSE}
  {$IFDEF DARWIN}
  Result := 'Menlo';
  {$ELSE}
  Result := 'Monospace';
  {$ENDIF}
  {$ENDIF}
end;

{ --- characters ------------------------------------------------------- }

function CharAt(const S: string; P: Integer): Char;
begin
  if (P < 1) or (P > Length(S)) then Result := ' ' else Result := S[P];
end;

function IsSpace(C: Char): Boolean;
begin
  Result := C in [' ', #9, #10, #13];
end;

{ letters and digits, and every byte of a non-ASCII character - enough to
  tell snake_case from _emphasis_ }
function IsWordChar(C: Char): Boolean;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9']) or (Ord(C) >= $80);
end;

function IsPunct(C: Char): Boolean;
begin
  Result := C in ['!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+', ',',
    '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^', '_',
    '`', '{', '|', '}', '~'];
end;

function Escape(const S: string): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
    else
      Result := Result + S[I];
    end;
end;

{ Length of a well-formed entity reference starting at P - &amp; &#169;
  &#xA9; - or 0. }
function EntityAt(const S: string; P: Integer): Integer;
var Q, First: Integer;
begin
  Result := 0;
  if CharAt(S, P) <> '&' then Exit;
  Q := P + 1;
  if CharAt(S, Q) = '#' then
  begin
    Inc(Q);
    if CharAt(S, Q) in ['x', 'X'] then
    begin
      Inc(Q); First := Q;
      while (Q <= Length(S)) and (S[Q] in ['0'..'9', 'a'..'f', 'A'..'F']) and (Q - First < 6) do Inc(Q);
    end
    else
    begin
      First := Q;
      while (Q <= Length(S)) and (S[Q] in ['0'..'9']) and (Q - First < 7) do Inc(Q);
    end;
  end
  else
  begin
    First := Q;
    while (Q <= Length(S)) and (S[Q] in ['a'..'z', 'A'..'Z', '0'..'9']) and (Q - First < 32) do Inc(Q);
    if not (CharAt(S, First) in ['a'..'z', 'A'..'Z']) then Exit;
  end;
  if (Q > First) and (CharAt(S, Q) = ';') then Result := Q - P + 1;
end;

{ Text for HTML, leaving entity references the writer typed alone. }
function EscapeText(const S: string): string;
var I, N: Integer;
begin
  Result := ''; I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      N := EntityAt(S, I);
      if N > 0 then begin Result := Result + Copy(S, I, N); Inc(I, N); Continue end;
    end;
    Result := Result + Escape(S[I]);
    Inc(I);
  end;
end;

{ Backslash escapes taken out, as in a link destination or a code fence's
  language. }
function Unbackslash(const S: string): string;
var I: Integer;
begin
  Result := ''; I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and IsPunct(CharAt(S, I + 1)) then Inc(I);
    Result := Result + S[I];
    Inc(I);
  end;
end;

function RunLength(const S: string; P: Integer; C: Char): Integer;
begin
  Result := 0;
  while (P + Result <= Length(S)) and (S[P + Result] = C) do Inc(Result);
end;

{ P is on a run of backticks: where the code span it opens ends, or just past
  the run when nothing closes it. }
function SkipCodeSpan(const S: string; P: Integer): Integer;
var N, Q, M: Integer;
begin
  N := RunLength(S, P, '`');
  Q := P + N;
  while Q <= Length(S) do
  begin
    if S[Q] = '`' then
    begin
      M := RunLength(S, Q, '`');
      if M = N then Exit(Q + M);
      Inc(Q, M);
    end
    else Inc(Q);
  end;
  Result := P + N;
end;

function MarkdownSlug(const Text: string): string;
var I: Integer; C: Char;
begin
  Result := '';
  for I := 1 to Length(Text) do
  begin
    C := Text[I];
    if C in ['A'..'Z'] then Result := Result + Chr(Ord(C) + 32)
    else if (C in ['a'..'z', '0'..'9', '-', '_']) or (Ord(C) >= $80) then Result := Result + C
    else if C = ' ' then Result := Result + '-';
  end;
end;

{ --- lines ------------------------------------------------------------ }

function ExpandTabs(const L: string): string;
var I: Integer;
begin
  if Pos(#9, L) = 0 then Exit(L);
  Result := '';
  for I := 1 to Length(L) do
    if L[I] = #9 then
      repeat Result := Result + ' ' until Length(Result) mod 4 = 0
    else
      Result := Result + L[I];
end;

function LeadSpaces(const L: string): Integer;
begin
  Result := 0;
  while (Result < Length(L)) and (L[Result + 1] = ' ') do Inc(Result);
end;

function IsBlank(const L: string): Boolean;
begin
  Result := Trim(L) = '';
end;

function Unindent(const L: string; N: Integer): string;
var K: Integer;
begin
  K := 0;
  while (K < N) and (K < Length(L)) and (L[K + 1] = ' ') do Inc(K);
  Result := Copy(L, K + 1, MaxInt);
end;

function IsRule(const L: string): Boolean;
var T: string; I, N: Integer; C: Char;
begin
  Result := False;
  if LeadSpaces(L) > 3 then Exit;
  T := Trim(L);
  if T = '' then Exit;
  C := T[1];
  if not (C in ['-', '*', '_']) then Exit;
  N := 0;
  for I := 1 to Length(T) do
    if T[I] = C then Inc(N)
    else if T[I] <> ' ' then Exit;
  Result := N >= 3;
end;

function IsHeading(const L: string; out Level: Integer; out Text: string): Boolean;
var T: string; K: Integer;
begin
  Result := False; Level := 0; Text := '';
  if LeadSpaces(L) > 3 then Exit;
  T := Trim(L);
  while (Level < Length(T)) and (T[Level + 1] = '#') do Inc(Level);
  if (Level < 1) or (Level > 6) then Exit;
  if (Length(T) > Level) and (T[Level + 1] <> ' ') then Exit;
  Text := Trim(Copy(T, Level + 1, MaxInt));
  { a closing run of #'s is decoration, when a space sets it apart }
  K := Length(Text);
  while (K > 0) and (Text[K] = '#') do Dec(K);
  if (K = 0) then Text := ''
  else if (K < Length(Text)) and (Text[K] = ' ') then Text := TrimRight(Copy(Text, 1, K));
  Result := True;
end;

{ 1 for a === underline, 2 for ---, 0 for neither }
function UnderlineLevel(const L: string): Integer;
var T: string; I: Integer;
begin
  Result := 0;
  if LeadSpaces(L) > 3 then Exit;
  T := Trim(L);
  if T = '' then Exit;
  for I := 1 to Length(T) do if T[I] <> T[1] then Exit;
  if T[1] = '=' then Result := 1 else if T[1] = '-' then Result := 2;
end;

function IsFence(const L: string; out C: Char; out N, Indent: Integer; out Info: string): Boolean;
var T: string; K: Integer;
begin
  Result := False; C := #0; N := 0; Info := '';
  Indent := LeadSpaces(L);
  if Indent > 3 then Exit;
  T := Copy(L, Indent + 1, MaxInt);
  if T = '' then Exit;
  C := T[1];
  if not (C in ['`', '~']) then Exit;
  N := RunLength(T, 1, C);
  if N < 3 then Exit;
  Info := Trim(Copy(T, N + 1, MaxInt));
  if (C = '`') and (Pos('`', Info) > 0) then Exit;
  K := Pos(' ', Info);
  if K > 0 then Info := Copy(Info, 1, K - 1);
  Info := Unbackslash(Info);
  Result := True;
end;

function IsFenceEnd(const L: string; C: Char; N: Integer): Boolean;
var T: string; M: Integer;
begin
  Result := False;
  if LeadSpaces(L) > 3 then Exit;
  T := Trim(L);
  M := RunLength(T, 1, C);
  Result := (M >= N) and (M = Length(T));
end;

function IsQuote(const L: string; out Rest: string): Boolean;
var K: Integer;
begin
  K := LeadSpaces(L);
  Result := (K <= 3) and (CharAt(L, K + 1) = '>');
  Rest := '';
  if not Result then Exit;
  Rest := Copy(L, K + 2, MaxInt);
  if CharAt(Rest, 1) = ' ' then Delete(Rest, 1, 1);
end;

function IsCommentStart(const L: string): Boolean;
begin
  Result := (LeadSpaces(L) <= 3) and (Copy(TrimLeft(L), 1, 4) = '<!--');
end;

function IsHTMLStart(const L: string): Boolean;
var T: string;
begin
  T := TrimLeft(L);
  Result := (LeadSpaces(L) <= 3) and (CharAt(T, 1) = '<') and
    ((CharAt(T, 2) in ['a'..'z', 'A'..'Z', '!', '?']) or
     ((CharAt(T, 2) = '/') and (CharAt(T, 3) in ['a'..'z', 'A'..'Z'])));
end;

type
  TListMark = record
    Ordered, Empty: Boolean;
    Ch: Char;           // the bullet, or the . or ) after a number
    Start: Integer;
    Content: Integer;   // columns taken by the marker and its spaces
  end;

function IsListItem(const L: string; out M: TListMark): Boolean;
var Ind, P, W, N: Integer;
begin
  Result := False;
  FillChar(M, SizeOf(M), 0);
  Ind := LeadSpaces(L);
  if Ind > 3 then Exit;
  P := Ind + 1;
  if CharAt(L, P) in ['-', '*', '+'] then
  begin
    M.Ch := L[P]; W := 1;
  end
  else
  begin
    W := 0;
    while (W < 9) and (CharAt(L, P + W) in ['0'..'9']) do Inc(W);
    if (W = 0) or not (CharAt(L, P + W) in ['.', ')']) then Exit;
    M.Ordered := True;
    M.Start := StrToIntDef(Copy(L, P, W), 1);
    M.Ch := L[P + W];
    Inc(W);
  end;
  if P + W <= Length(L) then
    if L[P + W] <> ' ' then Exit;
  N := 0;
  while CharAt(L, P + W + N) = ' ' do
  begin
    if P + W + N > Length(L) then Break;
    Inc(N);
  end;
  M.Empty := Trim(Copy(L, P + W, MaxInt)) = '';
  if M.Empty or (N > 4) then M.Content := Ind + W + 1
  else M.Content := Ind + W + N;
  Result := True;
end;

procedure SplitCells(const S: string; A: TStrings);
var T, Cell: string; P: Integer; Code: Boolean;
begin
  A.Clear; T := Trim(S);
  if (T <> '') and (T[1] = '|') then Delete(T, 1, 1);
  if (T <> '') and (T[Length(T)] = '|') and
    ((Length(T) < 2) or (T[Length(T) - 1] <> '\')) then Delete(T, Length(T), 1);
  Cell := ''; Code := False; P := 1;
  while P <= Length(T) do
  begin
    if (T[P] = '\') and (P < Length(T)) then
    begin Cell := Cell + T[P] + T[P + 1]; Inc(P, 2); Continue end;
    if T[P] = '`' then Code := not Code;
    if (T[P] = '|') and not Code then begin A.Add(Trim(Cell)); Cell := '' end
    else Cell := Cell + T[P];
    Inc(P);
  end;
  A.Add(Trim(Cell));
end;

{ The row under a table's header: cells of dashes, with a colon at either
  end for the alignment.  Aligns gets '', 'left', 'center' or 'right'. }
function IsDelimiterRow(const S: string; Aligns: TStrings): Boolean;
var I, J: Integer; T, A: string; L, R: Boolean;
  Cells: TStringList;
begin
  Result := False;
  Aligns.Clear;
  if Pos('|', S) = 0 then Exit;
  Cells := TStringList.Create;
  try
    SplitCells(S, Cells);
    for I := 0 to Cells.Count - 1 do
    begin
      T := Cells[I];
      L := (T <> '') and (T[1] = ':');
      if L then Delete(T, 1, 1);
      R := (T <> '') and (T[Length(T)] = ':');
      if R then Delete(T, Length(T), 1);
      if T = '' then Exit;
      for J := 1 to Length(T) do if T[J] <> '-' then Exit;
      if L and R then A := 'center' else if R then A := 'right'
      else if L then A := 'left' else A := '';
      Aligns.Add(A);
    end;
    Result := Aligns.Count > 0;
  finally Cells.Free end;
end;

{ --- the converter ---------------------------------------------------- }

type
  TMarkdown = class
  private
    FOptions: TInkMarkdownOptions;
    FRefs: TStringList;     // label=destination#1title
    FSlugs: TStringList;
    function StartsBlock(const L: string): Boolean;
    function IsTable(Lines: TStrings; I: Integer; Aligns: TStrings): Boolean;
    procedure ReadDefinitions(Lines: TStrings);
    function Lookup(const ALabel: string; out Dest, Title: string): Boolean;
    function Blocks(Lines: TStrings; Tight: Boolean): string;
    function Inline(const S: string; Links: Boolean = True): string;
    function TryAngle(const S: string; P: Integer; var Output: string): Integer;
    function TryLink(const S: string; P: Integer; Image: Boolean; var Output: string): Integer;
    function TryEmphasis(const S: string; P: Integer; Links: Boolean; var Output: string): Integer;
    function TryBareURL(const S: string; P: Integer; var Output: string): Integer;
  public
    constructor Create(AOptions: TInkMarkdownOptions);
    destructor Destroy; override;
    function Convert(const S: string): string;
  end;

constructor TMarkdown.Create(AOptions: TInkMarkdownOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FRefs := TStringList.Create;
  FSlugs := TStringList.Create;
  FSlugs.Sorted := True;
end;

destructor TMarkdown.Destroy;
begin
  FRefs.Free;
  FSlugs.Free;
  inherited;
end;

function NormalLabel(const S: string): string;
var I: Integer; Space: Boolean;
begin
  Result := ''; Space := False;
  for I := 1 to Length(S) do
    if IsSpace(S[I]) then Space := Result <> ''
    else
    begin
      if Space then Result := Result + ' ';
      Space := False;
      Result := Result + LowerCase(S[I]);
    end;
end;

function TMarkdown.Lookup(const ALabel: string; out Dest, Title: string): Boolean;
var V: string; K: Integer;
begin
  Dest := ''; Title := '';
  K := FRefs.IndexOfName(NormalLabel(ALabel));
  Result := (K >= 0) and (NormalLabel(ALabel) <> '');
  if not Result then Exit;
  V := FRefs.ValueFromIndex[K];
  K := Pos(#1, V);
  Dest := Copy(V, 1, K - 1);
  Title := Copy(V, K + 1, MaxInt);
end;

{ "[label]: destination "title"" lines, on their own, outside code.  They are
  read first, because a link may come before its definition, and then
  blanked out. }
procedure TMarkdown.ReadDefinitions(Lines: TStrings);
var I, P, Q: Integer; L, T, Name, Dest, Title: string;
  C: Char; N, Ind: Integer; Info: string;
  PrevBlank: Boolean;

  function Closer(Opener: Char): Char;
  begin
    if Opener = '(' then Result := ')' else Result := Opener;
  end;

begin
  PrevBlank := True;
  I := 0;
  while I < Lines.Count do
  begin
    L := Lines[I];
    if IsFence(L, C, N, Ind, Info) then
    begin
      Inc(I);
      while (I < Lines.Count) and not IsFenceEnd(Lines[I], C, N) do Inc(I);
      Inc(I); PrevBlank := False; Continue;
    end;
    T := Trim(L);
    if PrevBlank and (LeadSpaces(L) <= 3) and (CharAt(T, 1) = '[') then
    begin
      P := Pos(']:', T);
      if (P > 2) and (Pos(']', Copy(T, 2, P - 2)) = 0) then
      begin
        Name := NormalLabel(Copy(T, 2, P - 2));
        T := Trim(Copy(T, P + 2, MaxInt));
        Dest := ''; Title := '';
        if CharAt(T, 1) = '<' then
        begin
          Q := Pos('>', T);
          if Q > 0 then begin Dest := Copy(T, 2, Q - 2); T := Trim(Copy(T, Q + 1, MaxInt)) end
          else T := '';
        end
        else
        begin
          Q := 1;
          while (Q <= Length(T)) and not IsSpace(T[Q]) do Inc(Q);
          Dest := Copy(T, 1, Q - 1);
          T := Trim(Copy(T, Q, MaxInt));
        end;
        if (Length(T) >= 2) and (T[1] in ['"', '''', '(']) and
          (T[Length(T)] = Closer(T[1])) then
        begin
          Title := Copy(T, 2, Length(T) - 2);
          T := '';
        end;
        if (Name <> '') and (Dest <> '') and (T = '') then
        begin
          if FRefs.IndexOfName(Name) < 0 then
            FRefs.Add(Name + '=' + Unbackslash(Dest) + #1 + Unbackslash(Title));
          Lines[I] := '';
          Inc(I);
          Continue;       // PrevBlank stays: definitions may follow each other
        end;
      end;
    end;
    PrevBlank := IsBlank(L);
    Inc(I);
  end;
end;

function TMarkdown.StartsBlock(const L: string): Boolean;
var C: Char; N, Ind, Lv: Integer; Info, T: string; M: TListMark;
begin
  Result := IsFence(L, C, N, Ind, Info) or IsHeading(L, Lv, T) or IsRule(L) or
    IsQuote(L, T) or IsCommentStart(L) or
    (IsListItem(L, M) and not M.Empty and (not M.Ordered or (M.Start = 1))) or
    ((imoRawHTML in FOptions) and IsHTMLStart(L));
end;

function TMarkdown.IsTable(Lines: TStrings; I: Integer; Aligns: TStrings): Boolean;
var Head: TStringList;
begin
  Result := False;
  if (I + 1 >= Lines.Count) or (Pos('|', Lines[I]) = 0) then Exit;
  if LeadSpaces(Lines[I]) > 3 then Exit;
  if not IsDelimiterRow(Lines[I + 1], Aligns) then Exit;
  Head := TStringList.Create;
  try
    SplitCells(Lines[I], Head);
    Result := Head.Count = Aligns.Count;
  finally Head.Free end;
end;

{ A blank line between two of these lines' blocks - not one inside a code
  fence, and not one at either end. }
function HasBlankBetween(Lines: TStrings): Boolean;
var I, N, Ind: Integer; C: Char; Info: string;
begin
  Result := False;
  I := 0;
  while I < Lines.Count do
  begin
    if IsFence(Lines[I], C, N, Ind, Info) then
    begin
      Inc(I);
      while (I < Lines.Count) and not IsFenceEnd(Lines[I], C, N) do Inc(I);
    end
    else if (I > 0) and (I < Lines.Count - 1) and IsBlank(Lines[I]) then
      Exit(True);
    Inc(I);
  end;
end;

{ Is a fenced block still open at the end of these lines?  A line after it is
  then code, not a lazy continuation of a paragraph. }
function FenceOpen(Lines: TStrings): Boolean;
var I, N, Ind: Integer; C: Char; Info: string;
begin
  Result := False;
  I := 0;
  while I < Lines.Count do
  begin
    if IsFence(Lines[I], C, N, Ind, Info) then
    begin
      Inc(I);
      while (I < Lines.Count) and not IsFenceEnd(Lines[I], C, N) do Inc(I);
      if I >= Lines.Count then Exit(True);
    end;
    Inc(I);
  end;
end;

function TMarkdown.Blocks(Lines: TStrings; Tight: Boolean): string;
var
  I, J, N, Ind, Level: Integer;
  L, T, Info, Code, Box, Alert: string;
  C: Char;
  Para, Sub, Cells, Aligns, ItemList: TStringList;
  M, M2: TListMark;
  Loose, Trailing, More: Boolean;

  procedure Emit(const X: string);
  begin
    Result := Result + X + LF;
  end;

  procedure Heading(ALevel: Integer; const AText: string);
  var Base, Slug: string; K: Integer;
  begin
    Base := MarkdownSlug(StringReplace(StringReplace(StringReplace(
      AText, '`', '', [rfReplaceAll]), '*', '', [rfReplaceAll]), '~', '', [rfReplaceAll]));
    Slug := Base; K := 0;
    while FSlugs.IndexOf(Slug) >= 0 do
    begin
      Inc(K); Slug := Base + '-' + IntToStr(K);
    end;
    FSlugs.Add(Slug);
    Emit('<h' + IntToStr(ALevel) + ' id="' + Escape(Slug) + '">' + Inline(AText) +
      '</h' + IntToStr(ALevel) + '>');
  end;

  procedure FlushPara;
  var K: Integer; Txt: string;
  begin
    if Para.Count = 0 then Exit;
    Txt := '';
    for K := 0 to Para.Count - 1 do
    begin
      if K > 0 then Txt := Txt + LF;
      Txt := Txt + TrimLeft(Para[K]);
    end;
    Txt := TrimRight(Txt);
    if Tight then Emit(Inline(Txt))
    else Emit('<p>' + Inline(Txt) + '</p>');
    Para.Clear;
  end;

  function AlignAttr(K: Integer): string;
  begin
    Result := '';
    if (K < Aligns.Count) and (Aligns[K] <> '') then
      Result := ' align="' + Aligns[K] + '"';
  end;

  function Row(const Line, CellTag: string): string;
  var K: Integer;
  begin
    SplitCells(Line, Cells);
    Result := '<tr>';
    for K := 0 to Aligns.Count - 1 do
    begin
      Result := Result + '<' + CellTag + AlignAttr(K) + '>';
      if K < Cells.Count then Result := Result + Inline(Cells[K]);
      Result := Result + '</' + CellTag + '>';
    end;
    Result := Result + '</tr>';
  end;

begin
  Result := '';
  Para := TStringList.Create;
  Sub := TStringList.Create;
  Cells := TStringList.Create;
  Aligns := TStringList.Create;
  ItemList := TStringList.Create;
  try
    I := 0;
    while I < Lines.Count do
    begin
      L := Lines[I];
      if IsBlank(L) then
      begin
        FlushPara; Inc(I); Continue;
      end;

      Ind := LeadSpaces(L);
      if Ind >= 4 then
      begin
        if Para.Count > 0 then
        begin
          Para.Add(L); Inc(I); Continue;        // a wrapped line, indented
        end;
        { indented code: runs over blank lines, but the blank lines after
          its last line are not part of it }
        J := I;
        while (J < Lines.Count) and (IsBlank(Lines[J]) or (LeadSpaces(Lines[J]) >= 4)) do Inc(J);
        while IsBlank(Lines[J - 1]) do Dec(J);
        Code := '';
        while I < J do
        begin
          Code := Code + Escape(Unindent(Lines[I], 4)) + LF;
          Inc(I);
        end;
        Emit('<pre><code>' + Code + '</code></pre>');
        Continue;
      end;

      if IsFence(L, C, N, Ind, Info) then
      begin
        FlushPara;
        Inc(I);
        Code := '';
        while (I < Lines.Count) and not IsFenceEnd(Lines[I], C, N) do
        begin
          Code := Code + Escape(Unindent(Lines[I], Ind)) + LF;
          Inc(I);
        end;
        Inc(I);                                 // the closing fence
        if Info <> '' then Info := ' class="language-' + Escape(Info) + '"';
        Emit('<pre><code' + Info + '>' + Code + '</code></pre>');
        Continue;
      end;

      if IsCommentStart(L) then
      begin
        FlushPara;
        T := Copy(TrimLeft(L), 5, MaxInt);
        while (Pos('-->', T) = 0) and (I + 1 < Lines.Count) do
        begin
          Inc(I); T := Lines[I];
        end;
        Inc(I);
        Continue;
      end;

      if IsHeading(L, Level, T) then
      begin
        FlushPara;
        Heading(Level, T);
        Inc(I); Continue;
      end;

      if (Para.Count > 0) and (UnderlineLevel(L) > 0) then
      begin
        T := '';
        for J := 0 to Para.Count - 1 do
        begin
          if J > 0 then T := T + ' ';
          T := T + Trim(Para[J]);
        end;
        Para.Clear;
        Heading(UnderlineLevel(L), T);
        Inc(I); Continue;
      end;

      if IsRule(L) then
      begin
        FlushPara;
        Emit('<hr>');
        Inc(I); Continue;
      end;

      if IsQuote(L, T) then
      begin
        FlushPara;
        Sub.Clear;
        while I < Lines.Count do
        begin
          L := Lines[I];
          if IsQuote(L, T) then Sub.Add(T)
          else if not IsBlank(L) and (Sub.Count > 0) and not IsBlank(Sub[Sub.Count - 1]) and
            not StartsBlock(L) and not FenceOpen(Sub) then Sub.Add(L)
          else Break;
          Inc(I);
        end;
        { GitHub's alerts: "> [!NOTE]" on a line of its own }
        Alert := '';
        T := UpperCase(Trim(Sub[0]));
        if (T = '[!NOTE]') or (T = '[!TIP]') or (T = '[!IMPORTANT]') or
          (T = '[!WARNING]') or (T = '[!CAUTION]') then
        begin
          Alert := Copy(T, 3, Length(T) - 3);
          Sub.Delete(0);
          Alert := UpperCase(Alert[1]) + LowerCase(Copy(Alert, 2, MaxInt));
        end;
        if Alert <> '' then
          Emit('<blockquote class="markdown-alert markdown-alert-' + LowerCase(Alert) +
            '">' + LF + '<p class="markdown-alert-title"><strong>' + Alert +
            '</strong></p>' + LF + Blocks(Sub, False) + '</blockquote>')
        else
          Emit('<blockquote>' + LF + Blocks(Sub, False) + '</blockquote>');
        Continue;
      end;

      if IsListItem(L, M) and ((Para.Count = 0) or
        (not M.Empty and (not M.Ordered or (M.Start = 1)))) then
      begin
        FlushPara;
        Loose := False;
        ItemList.Clear;
        repeat
          Sub.Clear;
          Sub.Add(Copy(L, M.Content + 1, MaxInt));
          Inc(I);
          while I < Lines.Count do
          begin
            L := Lines[I];
            if IsBlank(L) then Sub.Add('')
            else if LeadSpaces(L) >= M.Content then Sub.Add(Copy(L, M.Content + 1, MaxInt))
            { a wrapped line that was not indented still belongs to the
              paragraph it continues }
            else if not IsBlank(Sub[Sub.Count - 1]) and not StartsBlock(L) and
              not IsListItem(L, M2) and not FenceOpen(Sub) then Sub.Add(TrimLeft(L))
            else Break;
            Inc(I);
          end;
          Trailing := False;
          while (Sub.Count > 1) and IsBlank(Sub[Sub.Count - 1]) do
          begin
            Sub.Delete(Sub.Count - 1);
            Trailing := True;
          end;
          { the item's first line may have been blank: its content starts
            on the next }
          if (Sub.Count > 1) and IsBlank(Sub[0]) then Sub.Delete(0);
          if HasBlankBetween(Sub) then Loose := True;
          More := (I < Lines.Count) and not IsRule(Lines[I]) and
            IsListItem(Lines[I], M2) and (M2.Ordered = M.Ordered) and (M2.Ch = M.Ch);
          if Trailing and More then Loose := True;
          { a task: "[ ]" or "[x]" and a space before the words }
          Box := '';
          T := Sub[0];
          if (Length(T) >= 3) and (T[1] = '[') and (T[3] = ']') and
            (T[2] in [' ', 'x', 'X']) and ((Length(T) = 3) or (T[4] = ' ')) then
          begin
            if T[2] = ' ' then Box := '<input type="checkbox" disabled="">'
            else Box := '<input type="checkbox" disabled="" checked="">';
            Sub[0] := Copy(T, 5, MaxInt);
          end;
          ItemList.Add(Box + #1 + Sub.Text);
          if More then
          begin
            L := Lines[I];
            M.Content := M2.Content;
            M.Empty := M2.Empty;
          end;
        until not More;
        { the items are only turned into HTML now, when it is known whether
          the list as a whole is tight }
        T := '';
        for J := 0 to ItemList.Count - 1 do
        begin
          Code := ItemList[J];
          N := Pos(#1, Code);
          Box := Copy(Code, 1, N - 1);
          Sub.Text := Copy(Code, N + 1, MaxInt);
          if Box <> '' then
            T := T + '<li class="task-list-item">' + Box + ' '
          else
            T := T + '<li>';
          T := T + TrimRight(Blocks(Sub, not Loose)) + '</li>' + LF;
        end;
        if M.Ordered then
        begin
          if M.Start <> 1 then Emit('<ol start="' + IntToStr(M.Start) + '">' + LF + T + '</ol>')
          else Emit('<ol>' + LF + T + '</ol>');
        end
        else Emit('<ul>' + LF + T + '</ul>');
        Continue;
      end;

      if IsTable(Lines, I, Aligns) then
      begin
        FlushPara;
        T := '<table>' + LF + '<thead>' + Row(L, 'th') + '</thead>' + LF;
        Inc(I, 2);
        Code := '';
        while (I < Lines.Count) and not IsBlank(Lines[I]) and not StartsBlock(Lines[I]) do
        begin
          Code := Code + Row(Lines[I], 'td') + LF;
          Inc(I);
        end;
        if Code <> '' then T := T + '<tbody>' + LF + Code + '</tbody>' + LF;
        Emit(T + '</table>');
        Continue;
      end;

      if (imoRawHTML in FOptions) and (Para.Count = 0) and IsHTMLStart(L) then
      begin
        while (I < Lines.Count) and not IsBlank(Lines[I]) do
        begin
          Emit(Lines[I]);
          Inc(I);
        end;
        Continue;
      end;

      Para.Add(L);
      Inc(I);
    end;
    FlushPara;
  finally
    Para.Free; Sub.Free; Cells.Free; Aligns.Free; ItemList.Free;
  end;
end;

function TMarkdown.Inline(const S: string; Links: Boolean): string;
var P, N, K: Integer; C: Char; Part: string;
begin
  Result := '';
  P := 1;
  while P <= Length(S) do
  begin
    C := S[P];
    Part := '';
    N := 0;
    case C of
      '\':
        if CharAt(S, P + 1) = LF then
        begin
          Part := '<br>' + LF; N := 2;
        end
        else if (P < Length(S)) and IsPunct(S[P + 1]) then
        begin
          Part := Escape(S[P + 1]); N := 2;
        end;
      '`':
        begin
          K := SkipCodeSpan(S, P);
          N := RunLength(S, P, '`');
          if K > P + N then
          begin
            Part := Copy(S, P + N, K - P - 2 * N);
            Part := StringReplace(Part, LF, ' ', [rfReplaceAll]);
            if (Length(Part) >= 2) and (Part[1] = ' ') and (Part[Length(Part)] = ' ') and
              (Trim(Part) <> '') then Part := Copy(Part, 2, Length(Part) - 2);
            Part := '<code>' + Escape(Part) + '</code>';
            N := K - P;
          end
          else
            Part := Copy(S, P, N);
        end;
      '<':
        N := TryAngle(S, P, Part);
      '!':
        if CharAt(S, P + 1) = '[' then
        begin
          N := TryLink(S, P + 1, True, Part);
          if N > 0 then Inc(N);
        end;
      '[':
        if Links then N := TryLink(S, P, False, Part);
      '*', '_', '~':
        N := TryEmphasis(S, P, Links, Part);
      '&':
        begin
          N := EntityAt(S, P);
          if N > 0 then Part := Copy(S, P, N);
        end;
      'h', 'w', 'H', 'W':
        if Links and ((P = 1) or (S[P - 1] in [' ', LF, '(', '*', '_', '~'])) then
          N := TryBareURL(S, P, Part);
      LF:
        begin
          { two spaces before the end of a line break it }
          K := Length(Result);
          while (K > 0) and (Result[K] = ' ') do Dec(K);
          if Length(Result) - K >= 2 then Part := '<br>' + LF else Part := LF;
          SetLength(Result, K);
          N := 1;
        end;
    end;
    if N > 0 then
    begin
      Result := Result + Part;
      Inc(P, N);
    end
    else
    begin
      Result := Result + Escape(C);
      Inc(P);
    end;
  end;
end;

{ <https://...>, <someone@example.com>, a comment, or - when trusted - a
  tag. }
function TMarkdown.TryAngle(const S: string; P: Integer; var Output: string): Integer;
var Q, K: Integer; Body: string; IsMail: Boolean;
begin
  Result := 0;
  if Copy(S, P, 4) = '<!--' then
  begin
    K := Pos('-->', Copy(S, P + 4, MaxInt));
    if K > 0 then
    begin
      Output := '';
      Result := K + 6;
    end;
    Exit;
  end;
  Q := P + 1;
  while (Q <= Length(S)) and not (S[Q] in ['>', '<', ' ', LF]) do Inc(Q);
  if CharAt(S, Q) = '>' then
  begin
    Body := Copy(S, P + 1, Q - P - 1);
    K := Pos(':', Body);
    IsMail := (Pos('@', Body) > 1) and (K = 0);
    if ((K > 2) and (Body[1] in ['a'..'z', 'A'..'Z'])) or IsMail then
    begin
      if IsMail then
        Output := '<a href="mailto:' + EscapeText(Body) + '">' + Escape(Body) + '</a>'
      else
        Output := '<a href="' + EscapeText(Body) + '">' + Escape(Body) + '</a>';
      Exit(Q - P + 1);
    end;
  end;
  if (imoRawHTML in FOptions) and
    ((CharAt(S, P + 1) in ['a'..'z', 'A'..'Z']) or
     ((CharAt(S, P + 1) = '/') and (CharAt(S, P + 2) in ['a'..'z', 'A'..'Z']))) then
  begin
    Q := P + 1;
    while (Q <= Length(S)) and (S[Q] <> '>') do Inc(Q);
    if Q <= Length(S) then
    begin
      Output := Copy(S, P, Q - P + 1);
      Result := Q - P + 1;
    end;
  end;
end;

{ [text](destination "title"), [text][label], [label][] and [label]; with
  Image, the same after a "!".  P is on the "[". }
function TMarkdown.TryLink(const S: string; P: Integer; Image: Boolean; var Output: string): Integer;
var Q, E, K, Depth: Integer; Text, Dest, Title: string; Found: Boolean;
  Closer: Char;
begin
  Result := 0;
  Q := P + 1; Depth := 1;
  while Q <= Length(S) do
  begin
    case S[Q] of
      '\': Inc(Q);
      '`': begin Q := SkipCodeSpan(S, Q); Continue end;
      '[': Inc(Depth);
      ']':
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
    end;
    Inc(Q);
  end;
  if Q > Length(S) then Exit;
  Text := Copy(S, P + 1, Q - P - 1);
  Found := False;
  Dest := ''; Title := '';
  E := Q + 1;
  if CharAt(S, E) = '(' then
  begin
    K := E + 1;
    while (K <= Length(S)) and IsSpace(S[K]) do Inc(K);
    if CharAt(S, K) = '<' then
    begin
      Inc(K);
      while (K <= Length(S)) and not (S[K] in ['>', LF]) do
      begin
        Dest := Dest + S[K]; Inc(K);
      end;
      if CharAt(S, K) = '>' then Inc(K) else K := Length(S) + 1;
    end
    else
    begin
      Depth := 0;
      while (K <= Length(S)) and not IsSpace(S[K]) do
      begin
        if (S[K] = '\') and (K < Length(S)) then
        begin
          Dest := Dest + S[K]; Inc(K);
        end
        else if S[K] = '(' then Inc(Depth)
        else if S[K] = ')' then
        begin
          if Depth = 0 then Break;
          Dec(Depth);
        end;
        Dest := Dest + S[K];
        Inc(K);
      end;
    end;
    while (K <= Length(S)) and IsSpace(S[K]) do Inc(K);
    if (K <= Length(S)) and (S[K] in ['"', '''', '(']) then
    begin
      if S[K] = '(' then Closer := ')' else Closer := S[K];
      Inc(K);
      while (K <= Length(S)) and (S[K] <> Closer) do
      begin
        if (S[K] = '\') and (K < Length(S)) then
        begin
          Title := Title + S[K]; Inc(K);
        end;
        Title := Title + S[K];
        Inc(K);
      end;
      Inc(K);
      while (K <= Length(S)) and IsSpace(S[K]) do Inc(K);
    end;
    if CharAt(S, K) = ')' then
    begin
      Found := True;
      Dest := Unbackslash(Dest);
      Title := Unbackslash(Title);
      Result := K + 1 - P;
    end
    else
    begin
      Dest := ''; Title := '';
    end;
  end;
  if not Found and (CharAt(S, E) = '[') then
  begin
    K := E + 1;
    while (K <= Length(S)) and not (S[K] in ['[', ']']) do Inc(K);
    if CharAt(S, K) <> ']' then Exit;
    if K = E + 1 then Found := Lookup(Text, Dest, Title)
    else Found := Lookup(Copy(S, E + 1, K - E - 1), Dest, Title);
    if not Found then Exit;
    Result := K + 1 - P;
  end;
  if not Found then
  begin
    Found := Lookup(Text, Dest, Title);
    if not Found then Exit;
    Result := Q + 1 - P;
  end;
  if Title <> '' then Title := ' title="' + EscapeText(Title) + '"';
  if Image then
    Output := '<img src="' + EscapeText(Dest) + '" alt="' +
      Escape(Trim(StringReplace(StringReplace(Text, '*', '', [rfReplaceAll]),
        '`', '', [rfReplaceAll]))) + '"' + Title + '>'
  else
    Output := '<a href="' + EscapeText(Dest) + '"' + Title + '>' +
      Inline(Text, False) + '</a>';
end;

{ *em* _em_ **strong** __strong__ ***both*** ~~struck~~.  An opener must be
  followed by something other than a space, a closer preceded by one, and an
  underscore may not sit inside a word - snake_case stays as typed. }
function TMarkdown.TryEmphasis(const S: string; P: Integer; Links: Boolean; var Output: string): Integer;
var C: Char; N, Q, M: Integer; Open, Close: string;
begin
  Result := 0;
  C := S[P];
  N := RunLength(S, P, C);
  if C = '~' then
  begin
    if N <> 2 then Exit;
  end
  else if N > 3 then Exit;
  if IsSpace(CharAt(S, P + N)) then Exit;
  if (C = '_') and IsWordChar(CharAt(S, P - 1)) then Exit;
  Q := P + N;
  while Q <= Length(S) do
  begin
    if S[Q] = '`' then
    begin
      Q := SkipCodeSpan(S, Q);
      Continue;
    end;
    if S[Q] = '\' then
    begin
      Inc(Q, 2);
      Continue;
    end;
    if S[Q] = C then
    begin
      M := RunLength(S, Q, C);
      if (M = N) and not IsSpace(CharAt(S, Q - 1)) and
        ((C <> '_') or not IsWordChar(CharAt(S, Q + M))) then
      begin
        if C = '~' then begin Open := '<del>'; Close := '</del>' end
        else case N of
          1: begin Open := '<em>'; Close := '</em>' end;
          2: begin Open := '<strong>'; Close := '</strong>' end;
        else
          Open := '<strong><em>'; Close := '</em></strong>';
        end;
        Output := Open + Inline(Copy(S, P + N, Q - P - N), Links) + Close;
        Exit(Q + M - P);
      end;
      Inc(Q, M);
      Continue;
    end;
    Inc(Q);
  end;
end;

{ http://, https:// and www. addresses in running text, the way GitHub
  links them.  Trailing punctuation belongs to the sentence, and so does a
  closing bracket the address did not open. }
function TMarkdown.TryBareURL(const S: string; P: Integer; var Output: string): Integer;
var Q, Opened, K: Integer; URL, Href: string;
begin
  Result := 0;
  if SameText(Copy(S, P, 8), 'https://') then K := 8
  else if SameText(Copy(S, P, 7), 'http://') then K := 7
  else if SameText(Copy(S, P, 4), 'www.') then K := 4
  else Exit;
  Q := P + K;
  while (Q <= Length(S)) and not IsSpace(S[Q]) and (S[Q] <> '<') do Inc(Q);
  URL := Copy(S, P, Q - P);
  while (URL <> '') and (URL[Length(URL)] in ['.', ',', ':', ';', '!', '?', '"', '''', '*', '_', '~']) do
    SetLength(URL, Length(URL) - 1);
  Opened := 0;
  for Q := 1 to Length(URL) do
    if URL[Q] = '(' then Inc(Opened) else if URL[Q] = ')' then Dec(Opened);
  while (Opened < 0) and (URL <> '') and (URL[Length(URL)] = ')') do
  begin
    SetLength(URL, Length(URL) - 1);
    Inc(Opened);
  end;
  if Length(URL) <= K then Exit;
  if (K = 4) and (Pos('.', Copy(URL, 5, MaxInt)) = 0) then Exit;
  Href := URL;
  if K = 4 then Href := 'http://' + URL;
  Output := '<a href="' + EscapeText(Href) + '">' + EscapeText(URL) + '</a>';
  Result := Length(URL);
end;

function TMarkdown.Convert(const S: string): string;
var Lines: TStringList; I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := S;
    for I := 0 to Lines.Count - 1 do Lines[I] := ExpandTabs(Lines[I]);
    ReadDefinitions(Lines);
    Result := Blocks(Lines, False);
  finally Lines.Free end;
end;

function MarkdownToHTML(const S: string; Options: TInkMarkdownOptions): string;
var M: TMarkdown;
begin
  M := TMarkdown.Create(Options);
  try Result := M.Convert(S) finally M.Free end;
end;

{ --- flattening, for the inline renderer -------------------------------- }

{ Whether the tag carries the attribute, and its value - '' for a bare
  attribute such as checked. }
function FindAttr(const Tag, Name: string; out Value: string): Boolean;
var P, Q: Integer; Key: string; Quote: Char;
begin
  Result := False;
  Value := '';
  P := 2;
  while (P <= Length(Tag)) and not IsSpace(Tag[P]) and (Tag[P] <> '>') do Inc(P);
  while P <= Length(Tag) do
  begin
    while (P <= Length(Tag)) and (IsSpace(Tag[P]) or (Tag[P] in ['>', '/'])) do Inc(P);
    Q := P;
    while (P <= Length(Tag)) and not (Tag[P] in ['=', '>']) and not IsSpace(Tag[P]) do Inc(P);
    Key := LowerCase(Copy(Tag, Q, P - Q));
    while (P <= Length(Tag)) and IsSpace(Tag[P]) do Inc(P);
    if CharAt(Tag, P) <> '=' then
    begin
      if (Key = Name) and (Key <> '') then Exit(True);
      Continue;
    end;
    Inc(P);
    while (P <= Length(Tag)) and IsSpace(Tag[P]) do Inc(P);
    Quote := #0;
    if CharAt(Tag, P) in ['"', ''''] then begin Quote := Tag[P]; Inc(P) end;
    Q := P;
    if Quote <> #0 then
      while (P <= Length(Tag)) and (Tag[P] <> Quote) do Inc(P)
    else
      while (P <= Length(Tag)) and not IsSpace(Tag[P]) and (Tag[P] <> '>') do Inc(P);
    if Key = Name then
    begin
      Value := Copy(Tag, Q, P - Q);
      Exit(True);
    end;
    if Quote <> #0 then Inc(P);
  end;
end;

function AttrValue(const Tag, Name: string): string;
begin
  FindAttr(Tag, Name, Result);
end;

function HasAttr(const Tag, Name: string): Boolean;
var Value: string;
begin
  Result := FindAttr(Tag, Name, Value);
end;

function CodepointToUTF8(N: Cardinal): string;
begin
  if N < $80 then Result := Chr(N)
  else if N < $800 then Result := Chr($C0 or (N shr 6)) + Chr($80 or (N and $3F))
  else if N < $10000 then Result := Chr($E0 or (N shr 12)) +
    Chr($80 or ((N shr 6) and $3F)) + Chr($80 or (N and $3F))
  else Result := Chr($F0 or (N shr 18)) + Chr($80 or ((N shr 12) and $3F)) +
    Chr($80 or ((N shr 6) and $3F)) + Chr($80 or (N and $3F));
end;

{ An entity the inline renderer cannot read, as the character it stands for.
  The ones it does read, and the ones that keep markup apart from text
  (&amp; &lt; &gt; &quot;), are left as they are. }
function DecodeEntity(const E: string): string;
const
  Names: array[0..17] of string = ('nbsp', 'ndash', 'mdash', 'hellip', 'lsquo',
    'rsquo', 'ldquo', 'rdquo', 'larr', 'rarr', 'uarr', 'darr', 'times', 'middot',
    'bull', 'laquo', 'raquo', 'deg');
  Codes: array[0..17] of Cardinal = ($A0, $2013, $2014, $2026, $2018, $2019,
    $201C, $201D, $2190, $2192, $2191, $2193, $D7, $B7, $2022, $AB, $BB, $B0);
var Body: string; N: Int64; I: Integer;
begin
  Result := E;
  Body := Copy(E, 2, Length(E) - 2);
  if (Body <> '') and (Body[1] = '#') then
  begin
    if (Length(Body) > 1) and (Body[2] in ['x', 'X']) then
      N := StrToInt64Def('$' + Copy(Body, 3, MaxInt), -1)
    else
      N := StrToInt64Def(Copy(Body, 2, MaxInt), -1);
    if (N <= 0) or (N > $10FFFF) or ((N >= $D800) and (N <= $DFFF)) then Exit('');
    if N in [Ord('&'), Ord('<'), Ord('>'), Ord('"')] then Exit;
    Exit(CodepointToUTF8(N));
  end;
  for I := 0 to High(Names) do
    if Body = Names[I] then
    begin
      if Body = 'nbsp' then Exit(' ');
      Exit(CodepointToUTF8(Codes[I]));
    end;
end;

function HTMLToInk(const S: string): string;
var
  P, Q, K, Quotes, SkipDepth: Integer;
  Tag, Name, Text, Marker: string;
  Closing, AtLineStart, Gapped, InPre, InTable, InHeading, ItemFresh: Boolean;
  PreBreaks: Integer;
  Lists: array of Integer;     // the next number, or -1 for bullets
  Output: string;

  procedure Put(const X: string);
  begin
    Output := Output + X;
  end;

  { what starts every drawn line: indentation for a nested list, the bars
    of the quotes it is in, and a list item's marker once }
  procedure LineStart;
  var I: Integer;
  begin
    if not AtLineStart then Exit;
    AtLineStart := False;
    Gapped := False;
    if InTable then Exit;
    if Length(Lists) > 1 then Put('<ind="' + IntToStr((Length(Lists) - 1) * 20) + '">');
    for I := 1 to Quotes do Put('<font color="clGray">' + QUOTE_BAR + '</font> ');
    if Marker <> '' then
    begin
      Put(Marker);
      Marker := '';
    end;
  end;

  procedure EndLine;
  begin
    if AtLineStart then Exit;
    while (Output <> '') and (Output[Length(Output)] = ' ') do
      SetLength(Output, Length(Output) - 1);
    Put('<br>');
    AtLineStart := True;
  end;

  { a blank line before a block, unless something already made one }
  procedure Gap;
  begin
    EndLine;
    if (Output <> '') and not Gapped then
    begin
      Put('<br>');
      Gapped := True;
    end;
  end;

  procedure AddText(const T: string);
  var I, N: Integer; Chunk: string;
  begin
    if T = '' then Exit;
    Chunk := '';
    I := 1;
    while I <= Length(T) do
    begin
      if T[I] = '&' then
      begin
        N := EntityAt(T, I);
        if N > 0 then
        begin
          Chunk := Chunk + DecodeEntity(Copy(T, I, N));
          Inc(I, N);
          Continue;
        end;
        Chunk := Chunk + '&amp;';
      end
      else Chunk := Chunk + T[I];
      Inc(I);
    end;
    if InPre then
    begin
      I := 1;
      while I <= Length(Chunk) do
      begin
        if Chunk[I] = #13 then
        else if Chunk[I] = LF then Inc(PreBreaks)
        else
        begin
          while PreBreaks > 0 do
          begin
            AtLineStart := False;
            EndLine;
            Dec(PreBreaks);
          end;
          LineStart;
          Put(Chunk[I]);
        end;
        Inc(I);
      end;
      Exit;
    end;
    { between a table's cells, white space is nothing }
    if InTable and (Trim(Chunk) = '') then Exit;
    { outside <pre>, white space is one space, and none at a line's start }
    I := 1;
    while I <= Length(Chunk) do
    begin
      if IsSpace(Chunk[I]) then
      begin
        while (I <= Length(Chunk)) and IsSpace(Chunk[I]) do Inc(I);
        if not AtLineStart and (Output <> '') and (Output[Length(Output)] <> ' ') then Put(' ');
        Continue;
      end;
      LineStart;
      Put(Chunk[I]);
      Inc(I);
    end;
  end;

  procedure OpenList(Ordered: Boolean);
  begin
    if Length(Lists) = 0 then Gap else EndLine;
    SetLength(Lists, Length(Lists) + 1);
    if Ordered then Lists[High(Lists)] := StrToIntDef(AttrValue(Tag, 'start'), 1)
    else Lists[High(Lists)] := -1;
  end;

  function CellAlign: string;
  var A: string;
  begin
    A := LowerCase(AttrValue(Tag, 'align'));
    if A = '' then
    begin
      A := LowerCase(StringReplace(AttrValue(Tag, 'style'), ' ', '', [rfReplaceAll]));
      if Pos('text-align:center', A) > 0 then A := 'center'
      else if Pos('text-align:right', A) > 0 then A := 'right';
    end;
    if A = 'center' then Result := '<center>'
    else if A = 'right' then Result := '<right>'
    else Result := '';
  end;

begin
  Output := '';
  AtLineStart := True; Gapped := False; InPre := False; InTable := False;
  InHeading := False; ItemFresh := False;
  Quotes := 0; SkipDepth := 0; PreBreaks := 0; Marker := '';
  SetLength(Lists, 0);
  P := 1;
  while P <= Length(S) do
  begin
    if S[P] <> '<' then
    begin
      Q := P;
      while (P <= Length(S)) and (S[P] <> '<') do Inc(P);
      if SkipDepth = 0 then AddText(Copy(S, Q, P - Q));
      Continue;
    end;
    if Copy(S, P, 4) = '<!--' then
    begin
      K := Pos('-->', Copy(S, P + 4, MaxInt));
      if K = 0 then Break;
      Inc(P, K + 6);
      Continue;
    end;
    Q := P;
    while (Q <= Length(S)) and (S[Q] <> '>') do Inc(Q);
    Tag := Copy(S, P, Q - P + 1);
    P := Q + 1;
    Closing := CharAt(Tag, 2) = '/';
    K := 2;
    if Closing then K := 3;
    Name := '';
    while (K <= Length(Tag)) and (Tag[K] in ['a'..'z', 'A'..'Z', '0'..'9']) do
    begin
      Name := Name + LowerCase(Tag[K]);
      Inc(K);
    end;
    if (Name = 'head') or (Name = 'script') or (Name = 'style') or (Name = 'title') then
    begin
      if Closing then SkipDepth := SkipDepth - 1 else Inc(SkipDepth);
      if SkipDepth < 0 then SkipDepth := 0;
      Continue;
    end;
    if SkipDepth > 0 then Continue;

    if InTable and not ((Name = 'table') and Closing) then
    begin
      if (Name = 'tr') or (Name = 'thead') or (Name = 'tbody') then
      begin
        if Closing then Put('</' + Name + '>') else Put('<' + Name + '>');
        Continue;
      end;
      if (Name = 'td') or (Name = 'th') then
      begin
        if Closing then Put('</' + Name + '>') else Put('<' + Name + '>' + CellAlign);
        Continue;
      end;
      if (Name = 'br') or ((Name = 'p') and Closing) then
      begin
        Put('<br>');
        Continue;
      end;
    end;

    if (Length(Name) = 2) and (Name[1] = 'h') and (Name[2] in ['1'..'6']) then
    begin
      if Closing then
      begin
        Put('</b></font>');
        InHeading := False;
        EndLine;
      end
      else
      begin
        Gap;
        LineStart;
        Put('<font size="' + IntToStr(22 - 2 * (Ord(Name[2]) - Ord('0'))) + '"><b>');
        InHeading := True;
      end;
    end
    else if Name = 'p' then
    begin
      if Closing then EndLine
      else if ItemFresh then ItemFresh := False
      else Gap;
    end
    else if (Name = 'div') or (Name = 'section') or (Name = 'article') or
      (Name = 'header') or (Name = 'footer') or (Name = 'nav') or
      (Name = 'figure') or (Name = 'figcaption') or (Name = 'dl') then
      EndLine
    else if Name = 'pre' then
    begin
      if Closing then
      begin
        Put('</font>');
        InPre := False;
        PreBreaks := 0;
        EndLine;
      end
      else
      begin
        if ItemFresh then ItemFresh := False else Gap;
        LineStart;
        Put('<font face="' + InkMonoFace + '">');
        InPre := True;
        PreBreaks := 0;
        { a line break straight after <pre> is not content }
        if (P <= Length(S)) and (S[P] = LF) then Inc(P);
      end;
    end
    else if Name = 'blockquote' then
    begin
      if Closing then
      begin
        if Quotes > 0 then Dec(Quotes);
        EndLine;
      end
      else
      begin
        Gap;
        Inc(Quotes);
      end;
    end
    else if (Name = 'ul') or (Name = 'ol') then
    begin
      if Closing then
      begin
        if Length(Lists) > 0 then SetLength(Lists, Length(Lists) - 1);
        EndLine;
      end
      else OpenList(Name = 'ol');
    end
    else if Name = 'li' then
    begin
      if Closing then
      begin
        EndLine;
        ItemFresh := False;
      end
      else
      begin
        EndLine;
        Marker := BULLET + ' ';
        if (Length(Lists) > 0) and (Lists[High(Lists)] >= 0) then
        begin
          Marker := IntToStr(Lists[High(Lists)]) + '. ';
          Inc(Lists[High(Lists)]);
        end;
        ItemFresh := True;
      end;
    end
    else if Name = 'dt' then
    begin
      if Closing then begin Put('</b>'); EndLine end
      else begin EndLine; LineStart; Put('<b>') end;
    end
    else if Name = 'dd' then
    begin
      EndLine;
      if not Closing then Put('<ind="20">');
    end
    else if Name = 'input' then
    begin
      if LowerCase(AttrValue(Tag, 'type')) = 'checkbox' then
      begin
        if HasAttr(Tag, 'checked') then Text := BOX_TICKED else Text := BOX_EMPTY;
        if Marker <> '' then Marker := Text + ' '
        else begin LineStart; Put(Text + ' ') end;
      end;
    end
    else if Name = 'hr' then
    begin
      EndLine;
      Put('<hr>');
      AtLineStart := True;
    end
    else if Name = 'br' then
    begin
      AtLineStart := False;
      EndLine;
    end
    else if Name = 'table' then
    begin
      if Closing then
      begin
        Put('</table>');
        InTable := False;
        AtLineStart := True;
      end
      else
      begin
        Gap;
        LineStart;
        Put('<table>');
        InTable := True;
      end;
    end
    else
    begin
      { inline }
      ItemFresh := False;
      if (Name = 'b') or (Name = 'strong') then Text := 'b'
      else if (Name = 'i') or (Name = 'em') or (Name = 'cite') then Text := 'i'
      else if (Name = 's') or (Name = 'del') or (Name = 'strike') then Text := 's'
      else if (Name = 'u') or (Name = 'ins') then Text := 'u'
      else if (Name = 'sup') or (Name = 'sub') then Text := Name
      else Text := '';
      if Text <> '' then
      begin
        if not Closing then LineStart;
        if Closing then Put('</' + Text + '>') else Put('<' + Text + '>');
      end
      else if ((Name = 'code') or (Name = 'kbd') or (Name = 'tt') or (Name = 'samp')) and
        not InPre and not InHeading then
      begin
        { a heading's size is a font tag too, and the renderer does not
          nest them: code in a heading stays in the heading's face }
        if Closing then Put('</font>')
        else begin LineStart; Put('<font face="' + InkMonoFace + '">') end;
      end
      else if Name = 'a' then
      begin
        if Closing then Put('</a>')
        else if AttrValue(Tag, 'href') <> '' then
        begin
          LineStart;
          Put('<a href="' + Escape(StringReplace(StringReplace(StringReplace(
            AttrValue(Tag, 'href'), '&quot;', '"', [rfReplaceAll]),
            '&lt;', '<', [rfReplaceAll]), '&amp;', '&', [rfReplaceAll])) + '">');
        end;
      end
      else if Name = 'img' then
        AddText(AttrValue(Tag, 'alt'))
      else if Name = 'font' then
      begin
        if not Closing then LineStart;
        Put(Tag);
      end;
    end;
  end;
  { no trailing blank lines }
  while (Length(Output) >= 4) and (Copy(Output, Length(Output) - 3, 4) = '<br>') do
    SetLength(Output, Length(Output) - 4);
  Result := Output;
end;

function MarkdownToInk(const S: string; Options: TInkMarkdownOptions): string;
begin
  Result := HTMLToInk(MarkdownToHTML(S, Options));
end;

function InkToHTML(const S: string; AFormat: TInkTextFormat): string;
begin
  if AFormat = itfMarkdown then Result := MarkdownToInk(S) else Result := S;
end;

end.
