{ InkCode - the small code highlighter LazInk draws code blocks with. 0BSD.

  Not a highlighter in the SynEdit sense and not meant to become one: it
  colors the four things that make a block read as code - comments, strings,
  numbers and a language's keywords - and leaves everything else alone.
  Types, functions, operators and brackets are where a small highlighter
  starts being wrong more often than it is right, so they stay plain.

  Comment and string rules come in a handful of families (C-like, Pascal,
  hash, dash, semicolon, markup); only the keyword list is per language.  A
  block that does not say which language it is still gets colored, by rules
  that take the things most languages agree on: // and # comments, /* */,
  (* *) and <!-- -->, quotes, numbers, and the words that turn up in nearly
  every language - if, else, for, while, return, begin, end, class, true.
  It will be wrong here and there, which is the deal: some coloring on every
  block beats none, and naming the language in the fence makes it right.

  A host that wants a real highlighter - SynEdit's, say - answers
  TInkCustomPage.OnHighlightCode instead; nothing here is in its way. }
unit InkCode;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Graphics;

type
  { what a code block is painted with }
  TInkCodeColors = record
    Comment, Quoted, Number, Keyword: TColor;
  end;

{ 'language-pascal', 'PASCAL', 'pas' and '  pascal  ' all come back
  'pascal': the name LazInk knows a language by, or '' for nothing said }
function InkCodeLanguage(const AName: string): string;
{ whether there are rules for it beyond the safe subset }
function InkCodeKnown(const ALanguage: string): Boolean;
{ colors that can be read on a page of this background: a light set on a
  light page, a lighter set on a dark one }
function InkCodeColors(ABackground: TColor): TInkCodeColors;
{ The code as LazInk markup - <font color> around comments, strings,
  numbers and keywords, everything else escaped as it was.  ACode is plain
  text with its tabs already turned into spaces; its line breaks come back
  as <br>, so HTMLPlainText gives the code back unchanged. }
function InkHighlight(const ACode, ALanguage: string;
  const AColors: TInkCodeColors): string;

implementation

type
  { how one family of languages writes its comments and strings }
  TInkCodeRules = record
    { up to two line comment leads, and three block comment pairs }
    Line1, Line2, Open1, Close1, Open2, Close2, Open3, Close3: string;
    { line comment leads that are only comments where they cannot be
      anything else - at the start of a line, or with a space on both sides.
      '#' is a comment in "# install", a color in "color: #fff"; '--' is a
      comment in "x -- note", a decrement in "i--". }
    Loose1, Loose2: string;
    { the characters a string may be written in }
    Quotes: string;
    { \" is a quote inside a string; "" is one too }
    Escape, Doubled: Boolean;
    { """ around a string that may cross lines, as Python writes it }
    Triples: Boolean;
    { <tag> and </tag> names are colored, for HTML and XML }
    Tags: Boolean;
    { @decorator and @Annotation are colored, for Python and the JVM ones }
    AtWords: Boolean;
    { a directive is colored like a keyword, not like a comment:
      '$' is Pascal's dollar directive in braces, '#' is C's #include }
    Directive: Char;
    { keywords, space-delimited and space-surrounded }
    Words: string;
    { keywords are case-insensitive, as in Pascal and SQL }
    Fold: Boolean;
    { there are rules at all }
    Known: Boolean;
    { prose: color nothing, not even numbers }
    Off: Boolean;
  end;

const
  PascalWords =
    ' and array asm begin case class const constructor destructor div do downto ' +
    'else end except exports false file finally for function goto if implementation ' +
    'in inherited initialization interface is label library mod nil not object of ' +
    'on operator or out overload override packed procedure program property raise ' +
    'record repeat resourcestring self set shl shr string then threadvar to true ' +
    'try type unit until uses var virtual while with xor ';
  CWords =
    ' auto bool break case catch char class const constexpr continue default delete ' +
    'do double else enum explicit extern false float for friend goto if inline int ' +
    'long namespace new nullptr operator private protected public register return ' +
    'short signed sizeof static struct switch template this throw true try typedef ' +
    'typename union unsigned using virtual void volatile while ';
  CSharpWords =
    ' abstract as async await base bool break byte case catch char checked class const ' +
    'continue decimal default delegate do double else enum event explicit extern false ' +
    'finally fixed float for foreach get goto if implicit in int interface internal is ' +
    'lock long namespace new null object operator out override params private protected ' +
    'public readonly ref return sealed set short sizeof static string struct switch this ' +
    'throw true try typeof uint ulong ushort using var virtual void while yield ';
  JavaWords =
    ' abstract assert boolean break byte case catch char class const continue default do ' +
    'double else enum extends false final finally float for if implements import ' +
    'instanceof int interface long native new null package private protected public ' +
    'record return short static strictfp super switch synchronized this throw throws ' +
    'transient true try var void volatile while ';
  JSWords =
    ' as async await break case catch class const continue debugger default delete do ' +
    'else enum export extends false finally for from function get if implements import ' +
    'in instanceof interface let new null of private protected public readonly return ' +
    'set static super switch this throw true try type typeof undefined var void while yield ';
  GoWords =
    ' break case chan const continue default defer else fallthrough false for func go ' +
    'goto if import interface iota map nil package range return select struct switch ' +
    'true type var ';
  RustWords =
    ' as async await break const continue crate dyn else enum extern false fn for if ' +
    'impl in let loop match mod move mut pub ref return self static struct super trait ' +
    'true type unsafe use where while ';
  PythonWords =
    ' False None True and as assert async await break class cls continue def del elif ' +
    'else except finally for from global if import in is lambda nonlocal not or pass ' +
    'raise return self try while with yield ';
  RubyWords =
    ' alias and begin break case class def defined? do else elsif end ensure false for ' +
    'if in module next nil not or redo rescue retry return self super then true undef ' +
    'unless until when while yield ';
  ShellWords =
    ' case do done elif else esac exit export fi for function if in local read readonly ' +
    'return select shift source then time until while ';
  PHPWords =
    ' abstract and array as break case catch class clone const continue declare default ' +
    'do echo else elseif empty enum extends final finally fn for foreach function global ' +
    'if implements include instanceof interface isset list match namespace new null or ' +
    'print private protected public require return static switch throw trait true try ' +
    'unset use var while yield false ';
  SQLWords =
    ' add all alter and as asc between by case cast column commit constraint count create ' +
    'cross default delete desc distinct drop else end exists foreign from full group ' +
    'having in index inner insert into is join key left like limit max min not null ' +
    'offset on or order outer primary references right rollback select set sum table then ' +
    'union unique update values view when where with ';
  LuaWords =
    ' and break do else elseif end false for function goto if in local nil not or repeat ' +
    'return then true until while ';
  HaskellWords =
    ' case class data deriving do else if import in instance let module newtype of then ' +
    'type where ';
  JSONWords = ' true false null ';
  { For a block that did not say what it is.  The words that mean roughly the
    same wherever they turn up, from every list above - begin and end are in
    Pascal, Ruby, Lua and shell; class is in half of them. }
  CommonWords =
    ' abstract and array as begin bool boolean break byte case catch char class const ' +
    'constructor continue def default define defer del delete do done double elif else ' +
    'elseif elsif end endif ensure enum except exit export extends false final finally ' +
    'fi float fn for foreach from func function global goto if implements import in ' +
    'include inherited init inline instanceof int integer interface is lambda let ' +
    'library local long match module namespace new next nil none not null nullptr ' +
    'object of or override package pass print private procedure program protected ' +
    'public raise range record register repeat require return select self set shared ' +
    'short signed sizeof static string struct super switch template then this throw ' +
    'to true try type typedef undef union unless unsigned until use using var virtual ' +
    'void when where while with yield ';

{ the name a fence or a class gave, mapped onto the one LazInk knows }
function InkCodeLanguage(const AName: string): string;
var S: string; P: Integer;
begin
  S := LowerCase(Trim(AName));
  if Copy(S,1,9)='language-' then Delete(S,1,9)
  else if Copy(S,1,5)='lang-' then Delete(S,1,5);
  { a fence's info string may carry more than the language, as in
    "pascal .numberLines" - the first word is the language }
  P := Pos(' ', S);
  if P>0 then S := Copy(S,1,P-1);
  if S='' then Exit('');
  if (S='pas') or (S='pp') or (S='dpr') or (S='lpr') or (S='inc') or (S='delphi') or
    (S='objectpascal') or (S='object-pascal') or (S='fpc') or (S='lazarus') then S := 'pascal'
  else if (S='c++') or (S='cxx') or (S='cc') or (S='hpp') or (S='h') or (S='cpp') then S := 'cpp'
  else if (S='cs') or (S='c#') then S := 'csharp'
  else if (S='js') or (S='jsx') or (S='mjs') or (S='node') then S := 'javascript'
  else if (S='ts') or (S='tsx') then S := 'typescript'
  else if S='py' then S := 'python'
  else if S='rb' then S := 'ruby'
  else if (S='sh') or (S='bash') or (S='zsh') or (S='shell') or (S='console') or
    (S='terminal') then S := 'shell'
  else if S='yml' then S := 'yaml'
  else if S='golang' then S := 'go'
  else if S='rs' then S := 'rust'
  else if (S='kt') or (S='kts') then S := 'kotlin'
  else if (S='xml') or (S='svg') or (S='xhtml') or (S='htm') then S := 'html'
  else if (S='scss') or (S='less') then S := 'css'
  else if (S='conf') or (S='cfg') or (S='toml') or (S='dosini') then S := 'ini'
  else if (S='md') or (S='text') or (S='txt') or (S='plain') or (S='plaintext') or
    (S='none') then S := 'markdown';
  Result := S;
end;

{ the rules for a language, or Known=False for the safe subset }
{ is L one of the space-separated names in AList }
function InList(const L, AList: string): Boolean;
begin
  Result := (L<>'') and (Pos(' '+L+' ',AList)>0);
end;

{ The rules for a language.  Comments and quotes are the cheap part - most
  languages write them one of eight ways - so the names below are spread
  wide and cost a line or two each.  Keyword lists are the expensive part
  and there are only a handful, for the languages people put in documents. }
function RulesFor(const ALanguage: string): TInkCodeRules;
var L: string;
begin
  Result := Default(TInkCodeRules);
  Result.Quotes := '"';
  L := ALanguage;
  { prose is not code: a Markdown or plain-text block is left alone }
  if L='markdown' then
  begin
    Result.Quotes := ''; Result.Off := True; Exit;
  end;
  if L='' then
  begin
    { nothing said: the rules everybody roughly agrees on }
    Result.Line1 := '//';
    Result.Loose1 := '#'; Result.Loose2 := '--';
    Result.Open1 := '/*'; Result.Close1 := '*/';
    Result.Open2 := '(*'; Result.Close2 := '*)';
    Result.Open3 := '<!--'; Result.Close3 := '-->';
    Result.Quotes := '"''`'; Result.Escape := True; Result.Doubled := True;
    Result.Words := CommonWords; Result.Fold := True;
    Exit;
  end;
  Result.Known := True;

  { Pascal, with the most complete rules of the lot: braces, (* *), //,
    doubled quotes, dollar directives and $FF numbers }
  if L='pascal' then
  begin
    Result.Line1 := '//'; Result.Open1 := '{'; Result.Close1 := '}';
    Result.Open2 := '(*'; Result.Close2 := '*)';
    Result.Quotes := ''''; Result.Doubled := True; Result.Directive := '$';
    Result.Words := PascalWords; Result.Fold := True;
    Exit;
  end;
  { ML and friends: (* *), and // as well in F# }
  if InList(L,' ocaml sml fsharp ') then
  begin
    Result.Open1 := '(*'; Result.Close1 := '*)'; Result.Escape := True;
    if L='fsharp' then Result.Line1 := '//';
    Exit;
  end;
  { markup: <!-- -->, and the tag names read as this language's keywords }
  if InList(L,' html vue xslt xaml ') then
  begin
    Result.Open1 := '<!--'; Result.Close1 := '-->';
    Result.Quotes := '"'''; Result.Tags := True;
    Exit;
  end;
  { stylesheets: /* */, and // in the preprocessors }
  if InList(L,' css stylus ') then
  begin
    Result.Open1 := '/*'; Result.Close1 := '*/'; Result.Quotes := '"''';
    if L='stylus' then Result.Line1 := '//';
    Exit;
  end;
  if L='json' then
  begin
    { .jsonc and friends allow //, and reading it costs nothing }
    Result.Line1 := '//'; Result.Words := JSONWords;
    Exit;
  end;
  { hash: # to the end of the line }
  if InList(L,' python ruby perl shell powershell r tcl awk elixir crystal ' +
    'nim julia yaml toml ini dockerfile makefile cmake gitignore nginx conf ' +
    'apache puppet hcl terraform properties desktop ') then
  begin
    Result.Line1 := '#'; Result.Quotes := '"'''; Result.Escape := True;
    if L='python' then
    begin
      { docstrings in triple quotes, and @decorators }
      Result.Words := PythonWords; Result.Triples := True; Result.AtWords := True;
    end
    else if L='ruby' then Result.Words := RubyWords
    else if InList(L,' shell powershell ') then
    begin
      Result.Words := ShellWords; Result.Quotes := '"''`';
    end;
    { the block comment each of these adds on top of # }
    if L='powershell' then begin Result.Open1 := '<#'; Result.Close1 := '#>' end
    else if L='julia' then begin Result.Open1 := '#='; Result.Close1 := '=#' end
    else if L='nim' then begin Result.Open1 := '#['; Result.Close1 := ']#' end
    else if InList(L,' ini properties desktop ') then Result.Line2 := ';'
    else if InList(L,' hcl terraform ') then Result.Line2 := '//';
    Exit;
  end;
  { semicolon: the lisps, assembler, a couple of config formats }
  if InList(L,' lisp scheme clojure elisp racket asm nasm autohotkey ') then
  begin
    Result.Line1 := ';'; Result.Quotes := '"'; Result.Escape := True;
    Exit;
  end;
  { percent: TeX, MATLAB, Erlang, Prolog }
  if InList(L,' latex tex bibtex matlab octave erlang prolog postscript ') then
  begin
    Result.Line1 := '%'; Result.Quotes := '''"'; Result.Escape := True;
    if InList(L,' matlab octave ') then
    begin
      Result.Open1 := '%{'; Result.Close1 := '%}';
    end;
    Exit;
  end;
  { a quote, REM or :: to the end of the line: the Basics and batch files }
  if InList(L,' vb vbnet vba basic freebasic ') then
  begin
    Result.Line1 := ''''; Result.Line2 := 'REM'; Result.Quotes := '"';
    Result.Fold := True;
    Exit;
  end;
  if InList(L,' batch bat cmd ') then
  begin
    Result.Line1 := '::'; Result.Line2 := 'REM'; Result.Quotes := '"';
    Result.Fold := True;
    Exit;
  end;
  if L='vim' then
  begin
    Result.Line1 := '"'; Result.Quotes := ''''; Result.Escape := True;
    Exit;
  end;
  if L='fortran' then
  begin
    Result.Line1 := '!'; Result.Quotes := '''"'; Result.Fold := True;
    Exit;
  end;
  { dash: SQL and the languages that borrowed its comment }
  if InList(L,' sql lua haskell ada elm vhdl applescript ') then
  begin
    Result.Line1 := '--'; Result.Quotes := '''"'; Result.Escape := True;
    if L='sql' then
    begin
      Result.Open1 := '/*'; Result.Close1 := '*/'; Result.Doubled := True;
      Result.Escape := False; Result.Words := SQLWords; Result.Fold := True;
    end
    else if L='lua' then
    begin
      Result.Open1 := '--[['; Result.Close1 := ']]'; Result.Words := LuaWords;
    end
    else if L='haskell' then
    begin
      Result.Open1 := '{-'; Result.Close1 := '-}'; Result.Words := HaskellWords;
    end
    else if L='applescript' then
    begin
      Result.Open1 := '(*'; Result.Close1 := '*)';
    end;
    Exit;
  end;
  { everything written with braces: // and /* */ }
  Result.Line1 := '//'; Result.Open1 := '/*'; Result.Close1 := '*/';
  Result.Quotes := '"'''; Result.Escape := True;
  if InList(L,' c cpp objc ') then
  begin
    Result.Words := CWords; Result.Directive := '#';
  end
  else if L='csharp' then Result.Words := CSharpWords
  else if InList(L,' java kotlin scala groovy dart swift ') then
  begin
    Result.Words := JavaWords; Result.AtWords := True;
  end
  else if InList(L,' javascript typescript ') then
  begin
    { `a template string` is a string too }
    Result.Words := JSWords; Result.Quotes := '"''`';
  end
  else if L='go' then
  begin
    Result.Words := GoWords; Result.Quotes := '"''`';
  end
  else if L='rust' then Result.Words := RustWords
  else if L='php' then
  begin
    Result.Words := PHPWords; Result.Line2 := '#';
  end
  else
  begin
    { a language we have no word list for still gets its comments, strings
      and the words most languages share }
    Result.Words := CommonWords; Result.Fold := True;
  end;
end;

function InkCodeKnown(const ALanguage: string): Boolean;
begin
  Result := RulesFor(InkCodeLanguage(ALanguage)).Known;
end;

function InkCodeColors(ABackground: TColor): TInkCodeColors;
var C: LongInt; Light: Boolean;
begin
  C := ColorToRGB(ABackground);
  { the same test the rest of LazInk uses: how much light the page gives back }
  Light := (Red(C)*30+Green(C)*59+Blue(C)*11) div 100 >= 128;
  if Light then
  begin
    Result.Comment := RGBToColor($6A,$73,$7D);
    Result.Quoted := RGBToColor($03,$2F,$62);
    Result.Number := RGBToColor($00,$5C,$C5);
    Result.Keyword := RGBToColor($D7,$3A,$49);
  end
  else
  begin
    Result.Comment := RGBToColor($8B,$94,$9E);
    Result.Quoted := RGBToColor($A5,$D6,$FF);
    Result.Number := RGBToColor($79,$C0,$FF);
    Result.Keyword := RGBToColor($FF,$7B,$72);
  end;
end;

function Escape(const S: string): string;
begin
  Result := StringReplace(S,'&','&amp;',[rfReplaceAll]);
  Result := StringReplace(Result,'<','&lt;',[rfReplaceAll]);
  Result := StringReplace(Result,'>','&gt;',[rfReplaceAll]);
  Result := StringReplace(Result,#10,'<br>',[rfReplaceAll]);
end;

function ColorText(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x',[Red(C),Green(C),Blue(C)]);
end;

function InkHighlight(const ACode, ALanguage: string;
  const AColors: TInkCodeColors): string;
var
  R: TInkCodeRules;
  P, Q, Len, Start: Integer;
  Plain: string;

  function At(const What: string): Boolean;
  begin
    Result := (What<>'') and (Copy(ACode,P,Length(What))=What);
  end;

  procedure Emit(C: TColor; const S: string);
  begin
    if S='' then Exit;
    Result := Result+'<font color="'+ColorText(C)+'">'+Escape(S)+'</font>';
  end;

  { everything not colored goes out as it was }
  procedure Flush;
  begin
    if Plain='' then Exit;
    Result := Result+Escape(Plain); Plain := '';
  end;

  procedure TakeTo(const Close: string; C: TColor);
  var Q: Integer;
  begin
    Start := P; Inc(P,1);
    if Close='' then
    begin
      { to the end of the line }
      while (P<=Len) and (ACode[P]<>#10) do Inc(P);
    end
    else
    begin
      Q := Pos(Close,ACode,Start+1);
      if Q=0 then P := Len+1 else P := Q+Length(Close);
    end;
    Emit(C,Copy(ACode,Start,P-Start));
  end;

  { A quote opens a string only if it closes again on the same line.  An
    apostrophe in "don't", a Rust lifetime and a stray tick are then just
    characters, instead of coloring the rest of the line. }
  function Closes(Quote: Char; From: Integer): Boolean;
  var Q: Integer;
  begin
    Result := False;
    if R.Triples and (Copy(ACode,From,3)=StringOfChar(Quote,3)) then Exit(True);
    Q := From+1;
    while (Q<=Len) and (ACode[Q]<>#10) do
    begin
      if R.Escape and (ACode[Q]='\') then begin Inc(Q,2); Continue end;
      if ACode[Q]=Quote then
      begin
        if R.Doubled and (Q<Len) and (ACode[Q+1]=Quote) then begin Inc(Q,2); Continue end;
        Exit(True);
      end;
      Inc(Q);
    end;
  end;
  { a lead that is only a comment where it cannot be anything else }
  function Loose(const Lead: string): Boolean;
  var Q: Integer;
  begin
    Result := False;
    if (Lead='') or not At(Lead) then Exit;
    Q := P-1;
    while (Q>=1) and (ACode[Q] in [' ',#9]) do Dec(Q);
    { at the start of its line, or spaced away from the code like a note }
    if (Q<1) or (ACode[Q]=#10) then Exit(True);
    Result := (ACode[P-1] in [' ',#9]) and (P+Length(Lead)<=Len) and
      (ACode[P+Length(Lead)] in [' ',#9]);
  end;
  { From is where the colored span begins: the quote, or a prefix in front
    of it - Python's f"..." and r"..." }
  procedure TakeString(Quote: Char; From: Integer);
  var Triple: Boolean; Close: string;
  begin
    Start := From;
    Triple := R.Triples and (Copy(ACode,P,3)=StringOfChar(Quote,3));
    if Triple then
    begin
      Close := StringOfChar(Quote,3);
      Inc(P,3);
      while (P<=Len) and (Copy(ACode,P,3)<>Close) do Inc(P);
      if P<=Len then Inc(P,3);
    end
    else
    begin
      Inc(P);
      while P<=Len do
      begin
        if R.Escape and (ACode[P]='\') and (P<Len) then begin Inc(P,2); Continue end;
        if ACode[P]=Quote then
        begin
          { '' inside a Pascal or SQL string is one quote, not the end }
          if R.Doubled and (P<Len) and (ACode[P+1]=Quote) then begin Inc(P,2); Continue end;
          Inc(P); Break;
        end;
        { a string that never closes stops at the end of its line }
        if ACode[P]=#10 then Break;
        Inc(P);
      end;
    end;
    Emit(AColors.Quoted,Copy(ACode,Start,P-Start));
  end;

  procedure TakeNumber;
  begin
    Start := P;
    if ACode[P] in ['$','#'] then Inc(P);
    while (P<=Len) and (ACode[P] in ['0'..'9','a'..'f','A'..'F','x','X','_','.']) do
    begin
      { 1..10 in Pascal is a range, not a number with two dots }
      if (ACode[P]='.') and (P<Len) and (ACode[P+1]='.') then Break;
      Inc(P);
    end;
    { "see 1." ends a sentence; the dot is not part of the number }
    while (P>Start+1) and (ACode[P-1]='.') do Dec(P);
    Emit(AColors.Number,Copy(ACode,Start,P-Start));
  end;

  procedure TakeWord;
  var W: string;
  begin
    Start := P;
    while (P<=Len) and (ACode[P] in ['a'..'z','A'..'Z','0'..'9','_','?','!']) do Inc(P);
    W := Copy(ACode,Start,P-Start);
    { ? and ! end a Ruby name but are not part of anything else }
    while (W<>'') and (W[Length(W)] in ['?','!']) and (Pos(' '+W+' ',R.Words)=0) do
    begin
      Dec(P); SetLength(W,Length(W)-1);
    end;
    if (R.Words<>'') and
      ((Pos(' '+W+' ',R.Words)>0) or (R.Fold and (Pos(' '+LowerCase(W)+' ',R.Words)>0))) then
      Emit(AColors.Keyword,W)
    else
      Plain := Plain+W;
  end;

begin
  Result := ''; Plain := '';
  R := RulesFor(InkCodeLanguage(ALanguage));
  if R.Off then Exit(Escape(ACode));
  Len := Length(ACode); P := 1;
  while P<=Len do
  begin
    { a directive is not a comment: a dollar one in Pascal's braces, or
      C's #include }
    if (R.Directive<>#0) and (R.Open1<>'') and At(R.Open1) and
      (Copy(ACode,P+Length(R.Open1),1)=R.Directive) then
    begin
      Flush; TakeTo(R.Close1,AColors.Keyword); Continue;
    end;
    if (R.Directive='#') and (ACode[P]='#') and
      ((P=1) or (ACode[P-1]=#10) or (Trim(Copy(ACode,1,P-1))='')) then
    begin
      Flush; TakeTo('',AColors.Keyword); Continue;
    end;
    if At(R.Line1) or At(R.Line2) or Loose(R.Loose1) or Loose(R.Loose2) then
    begin
      Flush; TakeTo('',AColors.Comment); Continue;
    end;
    if At(R.Open1) then
    begin
      Flush; TakeTo(R.Close1,AColors.Comment); Continue;
    end;
    if At(R.Open2) then
    begin
      Flush; TakeTo(R.Close2,AColors.Comment); Continue;
    end;
    if At(R.Open3) then
    begin
      Flush; TakeTo(R.Close3,AColors.Comment); Continue;
    end;
    { @property, @Override: a decorator reads as a word of the language }
    if R.AtWords and (ACode[P]='@') and (P<Len) and
      (ACode[P+1] in ['a'..'z','A'..'Z','_']) then
    begin
      Flush; Start := P; Inc(P);
      while (P<=Len) and (ACode[P] in ['a'..'z','A'..'Z','0'..'9','_','.']) do Inc(P);
      Emit(AColors.Keyword,Copy(ACode,Start,P-Start));
      Continue;
    end;
    { a string may wear a prefix: f"", r'', b"", rb"" - it is part of it }
    if R.Triples and (ACode[P] in ['f','r','b','u','F','R','B','U']) and (P<Len) and
      (Pos(ACode[P+1],R.Quotes)>0) and Closes(ACode[P+1],P+1) and
      ((P=1) or not (ACode[P-1] in ['a'..'z','A'..'Z','0'..'9','_'])) then
    begin
      Flush; Q := P; Inc(P); TakeString(ACode[P],Q); Continue;
    end;
    { <div>, </div>: the tag's name is this language's keyword }
    if R.Tags and (ACode[P]='<') and (P<Len) and
      (ACode[P+1] in ['a'..'z','A'..'Z','/','!','?']) then
    begin
      Flush; Start := P; Inc(P);
      if ACode[P] in ['/','!','?'] then Inc(P);
      while (P<=Len) and (ACode[P] in ['a'..'z','A'..'Z','0'..'9','-','_',':']) do Inc(P);
      Emit(AColors.Keyword,Copy(ACode,Start,P-Start));
      Continue;
    end;
    if (R.Quotes<>'') and (Pos(ACode[P],R.Quotes)>0) and Closes(ACode[P],P) then
    begin
      Flush; TakeString(ACode[P],P); Continue;
    end;
    if (ACode[P] in ['0'..'9']) and
      ((P=1) or not (ACode[P-1] in ['a'..'z','A'..'Z','0'..'9','_'])) then
    begin
      Flush; TakeNumber; Continue;
    end;
    { $FF and #13 are numbers in Pascal }
    if (R.Directive='$') and (ACode[P] in ['$','#']) and (P<Len) and
      (ACode[P+1] in ['0'..'9','a'..'f','A'..'F']) and
      ((P=1) or not (ACode[P-1] in ['a'..'z','A'..'Z','0'..'9','_'])) then
    begin
      Flush; TakeNumber; Continue;
    end;
    if ACode[P] in ['a'..'z','A'..'Z','_'] then
    begin
      if R.Words='' then
      begin
        { no word list: skip the name whole, so its letters are not read
          as anything else }
        Start := P;
        while (P<=Len) and (ACode[P] in ['a'..'z','A'..'Z','0'..'9','_']) do Inc(P);
        Plain := Plain+Copy(ACode,Start,P-Start);
      end
      else
      begin
        Flush; TakeWord;
      end;
      Continue;
    end;
    Plain := Plain+ACode[P]; Inc(P);
  end;
  Flush;
end;

end.
