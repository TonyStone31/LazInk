program HTML5LibCheck;
{ Scores InkDOM against the html5lib tree-construction tests (MIT, not in
  this repository - fetch them and pass their folder):

    tests/html5lib_check /path/to/html5lib-tests/tree-construction [show]

  Tests that need scripting are skipped: LazInk never runs script. }
{$mode objfpc}{$H+}
uses Classes, SysUtils, InkDOM;

var Shown: Integer;

function NsPrefix(N: TInkNode): string;
begin
  case N.Namespace of
    insSVG: Result := 'svg ';
    insMathML: Result := 'math ';
  else Result := '';
  end;
end;

procedure Dump(N: TInkNode; Indent: Integer; Lines: TStrings);
var C: TInkNode; Pad, A: string; I: Integer; Attrs: TStringList;
begin
  C := N.FirstChild;
  while C <> nil do
  begin
    Pad := '| ' + StringOfChar(' ', Indent * 2);
    case C.Kind of
      inkText: Lines.Add(Pad + '"' + C.Data + '"');
      inkComment: Lines.Add(Pad + '<!-- ' + C.Data + ' -->');
      inkDoctype:
        if C.HasAttribute('publicid') then
          Lines.Add(Pad + '<!DOCTYPE ' + C.Name + ' "' + C.GetAttribute('publicid') + '" "' +
            C.GetAttribute('systemid') + '">')
        else Lines.Add(Pad + '<!DOCTYPE ' + C.Name + '>');
      inkElement:
        begin
          Lines.Add(Pad + '<' + NsPrefix(C) + C.Name + '>');
          Attrs := TStringList.Create;
          try
            for I := 0 to C.AttributeCount - 1 do
            begin
              A := C.AttributeName(I);
              if (C.Namespace <> insHTML) and
                ((Copy(A, 1, 6) = 'xlink:') or (Copy(A, 1, 4) = 'xml:') or (Copy(A, 1, 6) = 'xmlns:')) then
                A := StringReplace(A, ':', ' ', []);
              Attrs.Add(Pad + '  ' + A + '="' + C.AttributeValue(I) + '"');
            end;
            Attrs.Sort;
            Lines.AddStrings(Attrs);
          finally Attrs.Free end;
          if (C.Namespace = insHTML) and (C.Name = 'template') then
          begin
            Lines.Add(Pad + '  content');
            Dump(C, Indent + 2, Lines);
          end
          else Dump(C, Indent + 1, Lines);
        end;
    end;
    C := C.NextSibling;
  end;
end;

function RunOne(const Data, Fragment, Expected: string): Boolean;
var D: TInkDocument; Ctx: TInkNode; Lines: TStringList; Got, CtxName: string;
  Ns: TInkNamespace;
begin
  Lines := TStringList.Create;
  try
    if Fragment <> '' then
    begin
      CtxName := Fragment; Ns := insHTML;
      if Copy(CtxName, 1, 4) = 'svg ' then begin Ns := insSVG; Delete(CtxName, 1, 4) end
      else if Copy(CtxName, 1, 5) = 'math ' then begin Ns := insMathML; Delete(CtxName, 1, 5) end;
      Ctx := TInkNode.Create(inkElement, CtxName, Ns);
      try
        InkParseFragment(Data, Ctx);
        Dump(Ctx, 0, Lines);
      finally Ctx.Free end;
    end
    else
    begin
      D := InkParseHTML(Data);
      try Dump(D, 0, Lines) finally D.Free end;
    end;
    Got := TrimRight(Lines.Text);
  finally Lines.Free end;
  Got := StringReplace(Got, #13, '', [rfReplaceAll]);
  Result := Got = Expected;
  if not Result and (Shown > 0) then
  begin
    Dec(Shown);
    WriteLn('--- ', StringReplace(Data, #10, '\n', [rfReplaceAll]));
    if Fragment <> '' then WriteLn('    (fragment in ', Fragment, ')');
    WriteLn('wanted:'#10, Expected);
    WriteLn('got:'#10, Got);
  end;
end;

var Files: TStringList; SR: TSearchRec; F, I: Integer; Lines: TStringList;
  Section, Data, Fragment, Expected: string; ScriptOn: Boolean;
  Pass, Total, FilePass, FileTotal, Skipped: Integer;

procedure Finish;
begin
  if Section = '' then Exit;
  if ScriptOn then begin Inc(Skipped); Exit end;
  { the data's own last line break is the format's, not the test's }
  if (Data <> '') and (Data[Length(Data)] = #10) then SetLength(Data, Length(Data) - 1);
  Inc(FileTotal);
  if RunOne(Data, Fragment, TrimRight(Expected)) then Inc(FilePass);
end;

begin
  if ParamCount < 1 then begin WriteLn('usage: html5lib_check <tree-construction folder> [show]'); Halt(2) end;
  if ParamCount > 1 then Shown := StrToIntDef(ParamStr(2), 20) else Shown := 0;
  Files := TStringList.Create;
  if FindFirst(IncludeTrailingPathDelimiter(ParamStr(1)) + '*.dat', faAnyFile, SR) = 0 then
  begin
    repeat Files.Add(SR.Name) until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  Files.Sort;
  Pass := 0; Total := 0; Skipped := 0;
  Lines := TStringList.Create;
  for F := 0 to Files.Count - 1 do
  begin
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(ParamStr(1)) + Files[F]);
    FilePass := 0; FileTotal := 0;
    Section := ''; Data := ''; Fragment := ''; Expected := ''; ScriptOn := False;
    for I := 0 to Lines.Count - 1 do
    begin
      if Lines[I] = '#data' then
      begin
        Finish;
        Section := 'data'; Data := ''; Fragment := ''; Expected := ''; ScriptOn := False;
        Continue;
      end;
      if (Section <> 'document') or (Copy(Lines[I], 1, 1) = '#') then
        if (Lines[I] = '#errors') or (Lines[I] = '#new-errors') or (Lines[I] = '#document') or
          (Lines[I] = '#document-fragment') or (Lines[I] = '#script-on') or
          (Lines[I] = '#script-off') then
        begin
          if Lines[I] = '#script-on' then ScriptOn := True;
          Section := Copy(Lines[I], 2, MaxInt);
          Continue;
        end;
      if Section = 'data' then Data := Data + Lines[I] + #10
      else if Section = 'document-fragment' then Fragment := Lines[I]
      else if Section = 'document' then Expected := Expected + Lines[I] + #10;
    end;
    Finish;
    WriteLn(Format('%-40s %4d / %4d', [Files[F], FilePass, FileTotal]));
    Inc(Pass, FilePass); Inc(Total, FileTotal);
  end;
  WriteLn(Format('All: %d of %d (%.1f%%), %d needing script skipped',
    [Pass, Total, 100.0 * Pass / Total, Skipped]));
  Lines.Free; Files.Free;
end.
