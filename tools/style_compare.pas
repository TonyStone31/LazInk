{ The comparing half of tools/style_compare.sh.

    style_compare page.html browser-dump.html [show]

  Reads the computed styles the browser wrote into its dump, computes the
  page with InkStyle at the same width, and counts the disagreements per
  property.  Percentages and auto margins, which the browser resolves
  against a layout LazInk has not done yet, are left out.

  SPDX-License-Identifier: 0BSD }
program style_compare;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, URIParser, InkDOM, InkStyle;

type
  TFetcher = class
    function Fetch(const URL: string): string;
  end;

function TFetcher.Fetch(const URL: string): string;
var FileName: string; L: TStringList;
begin
  Result := '';
  if not URIToFilename(URL, FileName) or not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Result := L.Text;
  finally L.Free end;
end;

function ReadFile(const AName: string): RawByteString;
var F: TFileStream;
begin
  F := TFileStream.Create(AName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally F.Free end;
end;

function Num(const S: string; out V: Double): Boolean;
var T: string; FS: TFormatSettings;
begin
  T := Trim(S);
  if Copy(T, Length(T) - 1, 2) = 'px' then SetLength(T, Length(T) - 2);
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Result := TryStrToFloat(T, V, FS);
end;

function ColorText(C: TInkRGBA): string;
var A: Integer; FS: TFormatSettings;
begin
  A := C shr 24;
  if A = 255 then
    Result := Format('rgb(%d, %d, %d)', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF])
  else
  begin
    FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
    Result := Format('rgba(%d, %d, %d, %s)', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF,
      FloatToStrF(A / 255, ffGeneral, 2, 0, FS)]);
  end;
end;

function Family(const S: string): string;
begin
  Result := LowerCase(StringReplace(StringReplace(StringReplace(S, '"', '', [rfReplaceAll]),
    '''', '', [rfReplaceAll]), ' ', '', [rfReplaceAll]));
end;

{ whether ours agrees with the browser's, and ours as text to show }
function Agrees(St: TInkStyle; const Prop, Theirs: string; out Ours: string): Boolean;
var V, A, B: Double; Raw: string; C1, C2: TInkRGBA;
begin
  Raw := St.Value(Prop);
  Ours := Raw;
  if (Prop = 'color') or (Prop = 'background-color') then
  begin
    C1 := St.Color(Prop);
    Ours := ColorText(C1);
    if not InkParseColor(Theirs, C2) then Exit(Ours = Theirs);
    if (C1 shr 24 = 0) and (C2 shr 24 = 0) then Exit(True);
    { channel by channel, a step either way for rounding }
    Exit((Abs(Integer(C1 and $FF) - Integer(C2 and $FF)) <= 2) and
      (Abs(Integer((C1 shr 8) and $FF) - Integer((C2 shr 8) and $FF)) <= 2) and
      (Abs(Integer((C1 shr 16) and $FF) - Integer((C2 shr 16) and $FF)) <= 2) and
      (Abs(Integer(C1 shr 24) - Integer(C2 shr 24)) <= 2));
  end;
  if (Prop = 'font-size') or (Prop = 'margin-top') or (Prop = 'margin-bottom') or
    (Copy(Prop, 1, 8) = 'padding-') or (Prop = 'border-top-width') or (Prop = 'border-left-width') then
  begin
    if (Pos('%', Raw) > 0) or (LowerCase(Raw) = 'auto') then Exit(True);
    A := St.Px(Prop);
    Ours := FloatToStrF(A, ffGeneral, 6, 0) + 'px';
    if not Num(Theirs, B) then Exit(False);
    { the browser snaps borders to whole pixels }
    if Copy(Prop, 1, 7) = 'border-' then Exit(Abs(Floor(A + 0.001) - B) < 0.6);
    Exit(Abs(A - B) < 0.05);
  end;
  if Prop = 'line-height' then
  begin
    if LowerCase(Raw) = 'normal' then Exit(Theirs = 'normal');
    if Num(Raw, V) and (Pos('px', Raw) = 0) then A := V * St.FontSize
    else A := St.Px(Prop);
    Ours := FloatToStrF(A, ffGeneral, 6, 0) + 'px';
    if not Num(Theirs, B) then Exit(False);
    Exit(Abs(A - B) < 0.05);
  end;
  if Prop = 'font-family' then
  begin
    if Raw = '' then Exit(True);
    Exit(Family(Raw) = Family(Theirs));
  end;
  if Prop = 'text-align' then
  begin
    { the browser's own names for what the standard calls center }
    Ours := LowerCase(Raw);
    Exit((Ours = Theirs) or ('-webkit-' + Ours = Theirs) or ('-internal-' + Ours = Theirs));
  end;
  Ours := LowerCase(Trim(Raw));
  Result := Ours = Theirs;
end;

var
  Doc, Dump: TInkDocument;
  Styler: TInkStyler;
  Fetcher: TFetcher;
  Lines, Cols, Props: TStringList;
  Out_: TInkNode;
  Ours: TInkNodeArray;
  I, K, Show, Total, Wrong, PageWrong: Integer;
  Counts: array of Integer;
  OurText, Shown: string;
begin
  if ParamCount < 2 then begin WriteLn('usage: style_compare page.html dump.html [show]'); Halt(2) end;
  Show := 0;
  if ParamCount > 2 then Show := StrToIntDef(ParamStr(3), 0);
  Dump := InkParseHTML(ReadFile(ParamStr(2)));
  Out_ := Dump.GetElementById('__ink_out');
  if Out_ = nil then begin WriteLn(ExtractFileName(ParamStr(1)), ': the browser wrote nothing'); Halt(1) end;
  Lines := TStringList.Create;
  Lines.Text := Out_.TextContent;
  Props := TStringList.Create;
  Props.Delimiter := #9; Props.StrictDelimiter := True; Props.QuoteChar := #1;
  Props.DelimitedText := Lines[0];
  Lines.Delete(0);
  Doc := InkParseHTML(InkDecodeHTML(ReadFile(ParamStr(1))));
  Fetcher := TFetcher.Create;
  Styler := TInkStyler.Create;
  Styler.Media.Width := 1024; Styler.Media.Height := 800;
  Styler.OnFetch := @Fetcher.Fetch;
  Styler.AddDocumentSheets(Doc, FilenameToURI(ExpandFileName(ParamStr(1))));
  Styler.Compute(Doc);
  { what is in a <template> is not in the browser's document }
  Ours := Doc.GetElementsByTagName('*');
  K := 0;
  for I := 0 to High(Ours) do
  begin
    Out_ := Ours[I].Parent;
    while (Out_ <> nil) and not Out_.IsElement('template') do Out_ := Out_.Parent;
    { a declarative shadow root leaves the tree altogether }
    if (Out_ = nil) and not (Ours[I].IsElement('template') and Ours[I].HasAttribute('shadowrootmode')) then
    begin
      Ours[K] := Ours[I]; Inc(K);
    end;
  end;
  SetLength(Ours, K);
  SetLength(Counts, Props.Count);
  Cols := TStringList.Create;
  Cols.Delimiter := #9; Cols.StrictDelimiter := True; Cols.QuoteChar := #1;
  Total := 0; Wrong := 0; PageWrong := 0;
  if Length(Ours) <> Lines.Count then
    WriteLn(Format('  %d elements here, %d in the browser - compared as far as they agree',
      [Length(Ours), Lines.Count]));
  for I := 0 to Min(Length(Ours), Lines.Count) - 1 do
  begin
    Cols.DelimitedText := Lines[I];
    if not SameText(Cols[0], Ours[I].Name) then
    begin
      WriteLn(Format('  element %d is <%s> here, <%s> in the browser: stopping', [I, Ours[I].Name, Cols[0]]));
      Break;
    end;
    for K := 0 to Props.Count - 1 do
    begin
      Inc(Total);
      if not Agrees(Styler.StyleOf(Ours[I]), Props[K], Cols[K + 1], OurText) then
      begin
        Inc(Wrong); Inc(Counts[K]);
        if Show > 0 then
        begin
          Dec(Show);
          WriteLn(Format('  <%s class="%s"> #%d %s: ours "%s", browser "%s"', [Ours[I].Name,
            Ours[I].GetAttribute('class'), I, Props[K], OurText, Cols[K + 1]]));
        end;
      end;
    end;
  end;
  if ParamCount > 3 then Shown := ParamStr(4) else Shown := ExtractFileName(ParamStr(1));
  Write(Format('%-28s %6d values, %5d differ (%.1f%% agree)', [Shown, Total, Wrong,
    100 - 100.0 * Wrong / Max(1, Total)]));
  for K := 0 to Props.Count - 1 do
    if Counts[K] > 0 then Write(Format('  %s %d', [Props[K], Counts[K]]));
  WriteLn;
  Styler.Free; Fetcher.Free; Doc.Free; Dump.Free; Lines.Free; Props.Free; Cols.Free;
  if PageWrong > 0 then ;
end.
