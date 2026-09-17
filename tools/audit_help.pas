#!/usr/bin/env instantfpc
program audit_help;

{ Inventory a local HTML help tree, or download a site's same-site linked
  pages first and inventory those.

      audit_help LOCAL_DIRECTORY [--output report.json]
      audit_help URL --download DIRECTORY [--output report.json]

  The report says which tags, attributes and classes the pages use - the
  list of things a renderer has to understand to show them - and which of
  their links and pictures point at nothing, anchors included.

  Pages are read with the FCL's HTML reader (sax_html), not LazInk's own
  parser, so the inventory is somebody else's reading of the files.

  It is a script for instantfpc, which comes with Free Pascal: run it
  directly, and it is compiled the first time and cached after that.

      tools/audit_help.pas docs/help
      instantfpc tools/audit_help.pas docs/help    if instantfpc is not on PATH

  https needs OpenSSL at run time. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  Classes, SysUtils, StrUtils, fpjson, sax, sax_html, xmlutils, xmlreader,
  uriparser, fphttpclient, opensslsockets;

type
  { counts that remember the order things were first seen in }
  TCounter = class
  private
    FNames: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const S: string; N: Integer = 1);
    procedure AddAll(C: TCounter);
    function AsJSON: TJSONObject;
  end;

  TPage = class
  public
    Tags, Attrs, Classes_: TCounter;
    Links, Assets, Ids: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure StartElement(Sender: TObject; const NamespaceURI, LocalName,
      QName: SAXString; Atts: TSAXAttributes);
  end;

constructor TCounter.Create;
begin
  FNames := TStringList.Create;
  FNames.CaseSensitive := True;
end;

destructor TCounter.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TCounter.Add(const S: string; N: Integer);
var
  I: Integer;
begin
  I := FNames.IndexOf(S);
  if I < 0 then
    FNames.AddObject(S, TObject(PtrInt(N)))
  else
    FNames.Objects[I] := TObject(PtrInt(FNames.Objects[I]) + N);
end;

procedure TCounter.AddAll(C: TCounter);
var
  I: Integer;
begin
  for I := 0 to C.FNames.Count - 1 do
    Add(C.FNames[I], PtrInt(C.FNames.Objects[I]));
end;

function TCounter.AsJSON: TJSONObject;
var
  I: Integer;
begin
  Result := TJSONObject.Create;
  for I := 0 to FNames.Count - 1 do
    Result.Add(FNames[I], Integer(PtrInt(FNames.Objects[I])));
end;

constructor TPage.Create;
begin
  Tags := TCounter.Create;
  Attrs := TCounter.Create;
  Classes_ := TCounter.Create;
  Links := TStringList.Create;
  Assets := TStringList.Create;
  Ids := TStringList.Create;
  Ids.CaseSensitive := True;
end;

destructor TPage.Destroy;
begin
  Tags.Free; Attrs.Free; Classes_.Free;
  Links.Free; Assets.Free; Ids.Free;
  inherited Destroy;
end;

procedure TPage.StartElement(Sender: TObject; const NamespaceURI, LocalName,
  QName: SAXString; Atts: TSAXAttributes);
var
  Tag, Key, Value: string;
  I: Integer;
  Words: TStringArray;
  W: string;
  Href, Src, Rel: string;
begin
  Tag := LowerCase(UTF8Encode(LocalName));
  Tags.Add(Tag);
  Href := ''; Src := ''; Rel := '';
  if Atts <> nil then
    for I := 0 to Atts.Length - 1 do
    begin
      Key := LowerCase(UTF8Encode(Atts.GetLocalName(I)));
      Value := UTF8Encode(Atts.GetValue(I));
      Attrs.Add(Tag + '.' + Key);
      if Key = 'class' then
      begin
        Words := Value.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty);
        for W in Words do Classes_.Add(W);
      end
      else if Key = 'id' then Ids.Add(Value)
      else if Key = 'href' then Href := Value
      else if Key = 'src' then Src := Value
      else if Key = 'rel' then Rel := Value;
    end;
  if (Tag = 'a') and (Href <> '') then Links.Add(Href);
  if (Tag = 'img') and (Src <> '') then Assets.Add(Src);
  if (Tag = 'link') and (Rel = 'stylesheet') and (Href <> '') then Assets.Add(Href);
end;

function ReadPage(Stream: TStream): TPage;
var
  Reader: THTMLReader;
  Input: TXMLInputSource;
begin
  Result := TPage.Create;
  Reader := THTMLReader.Create;
  Input := TXMLInputSource.Create(Stream);
  try
    Reader.OnStartElement := @Result.StartElement;
    Reader.Parse(Input);
  finally
    Input.Free;
    Reader.Free;
  end;
end;

function ReadPageFile(const Path: string): TPage;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    Result := ReadPage(F);
  finally
    F.Free;
  end;
end;

{ %41 to A, the way a path in a link means it }
function Unquote(const S: string): string;
var
  I, V: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and
       TryStrToInt('$' + Copy(S, I + 1, 2), V) then
    begin
      Result := Result + Chr(V);
      Inc(I, 3);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

{ everything before a # or a ? }
function StripFragment(const U: string): string;
var
  P: Integer;
begin
  Result := U;
  P := Pos('#', Result);
  if P > 0 then SetLength(Result, P - 1);
  P := Pos('?', Result);
  if P > 0 then SetLength(Result, P - 1);
end;

{ a link that names a scheme or a host of its own is somebody else's }
function IsElsewhere(const Ref: string): Boolean;
var
  I: Integer;
begin
  if Copy(Ref, 1, 2) = '//' then Exit(True);
  Result := False;
  for I := 1 to Length(Ref) do
    case Ref[I] of
      'a'..'z', 'A'..'Z': ;
      '0'..'9', '+', '-', '.': if I = 1 then Exit(False);
      ':': Exit(I > 1);
    else
      Exit(False);
    end;
end;

procedure Download(const Source, Root: string);
var
  Base, Url, Resolved, Rel, Target, RootFull: string;
  Pending, Seen: TStringList;
  Client: TFPHTTPClient;
  Data: TMemoryStream;
  Page: TPage;
  I: Integer;
begin
  Base := Source;
  while (Base <> '') and (Base[Length(Base)] = '/') do SetLength(Base, Length(Base) - 1);
  Base := Base + '/';
  RootFull := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  Pending := TStringList.Create;
  Seen := TStringList.Create;
  Seen.Sorted := True;
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.IOTimeout := 30000;
    Pending.Add(Base);
    while Pending.Count > 0 do
    begin
      Url := StripFragment(Pending[Pending.Count - 1]);
      Pending.Delete(Pending.Count - 1);
      if (Seen.IndexOf(Url) >= 0) or not AnsiStartsStr(Base, Url) then Continue;
      Seen.Add(Url);
      Rel := Unquote(Copy(Url, Length(Base) + 1, MaxInt));
      if (Rel = '') or (Rel[Length(Rel)] = '/') then Rel := Rel + 'index.html';
      Target := ExpandFileName(RootFull + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]));
      { nothing written outside the folder asked for, whatever a link says }
      if not AnsiStartsStr(RootFull, Target) then Continue;
      Data := TMemoryStream.Create;
      try
        Client.Get(Url, Data);
        ForceDirectories(ExtractFileDir(Target));
        Data.SaveToFile(Target);
        if LowerCase(ExtractFileExt(Target)) = '.html' then
        begin
          Data.Position := 0;
          Page := ReadPage(Data);
          try
            for I := 0 to Page.Links.Count - 1 do
              if ResolveRelativeURI(Url, Page.Links[I], Resolved) and
                 AnsiStartsStr(Base, Resolved) then Pending.Add(Resolved);
            for I := 0 to Page.Assets.Count - 1 do
              if ResolveRelativeURI(Url, Page.Assets[I], Resolved) and
                 AnsiStartsStr(Base, Resolved) then Pending.Add(Resolved);
          finally
            Page.Free;
          end;
        end;
      finally
        Data.Free;
      end;
    end;
  finally
    Client.Free;
    Seen.Free;
    Pending.Free;
  end;
end;

procedure FindPages(const Root, Sub: string; Into: TStringList);
var
  SR: TSearchRec;
begin
  if FindFirst(Root + Sub + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
        FindPages(Root, Sub + SR.Name + '/', Into)
      else if LowerCase(ExtractFileExt(SR.Name)) = '.html' then
        Into.Add(Sub + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

var
  Source, DownloadTo, Output, Root, Name, Ref, PathPart, Frag, Path: string;
  I, K, P: Integer;
  Names, AllAssets: TStringList;
  Pages: array of TPage;
  Tags, Attrs, Cls: TCounter;
  Report, Broken: TJSONObject;
  BrokenList, List: TJSONArray;
  Dest: Integer;
  Text: string;
  L: TStringList;
begin
  Source := '';
  DownloadTo := '';
  Output := '';
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--download') and (I < ParamCount) then
    begin
      Inc(I);
      DownloadTo := ParamStr(I);
    end
    else if (ParamStr(I) = '--output') and (I < ParamCount) then
    begin
      Inc(I);
      Output := ParamStr(I);
    end
    else if Source = '' then
      Source := ParamStr(I)
    else
    begin
      WriteLn('unexpected argument: ', ParamStr(I));
      Halt(2);
    end;
    Inc(I);
  end;
  if Source = '' then
  begin
    WriteLn('usage: audit_help LOCAL_DIRECTORY [--output report.json]');
    WriteLn('       audit_help URL --download DIRECTORY [--output report.json]');
    Halt(2);
  end;

  if AnsiStartsText('https://', Source) or AnsiStartsText('http://', Source) then
  begin
    if DownloadTo = '' then
    begin
      WriteLn('a URL needs --download DIRECTORY');
      Halt(2);
    end;
    Download(Source, DownloadTo);
    Root := DownloadTo;
  end
  else
    Root := Source;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(Root));

  { sorted by character code, not by the machine's idea of alphabetical,
    so the report reads the same wherever it is made }
  Names := TStringList.Create;
  Names.CaseSensitive := True;
  Names.UseLocale := False;
  AllAssets := TStringList.Create;
  AllAssets.CaseSensitive := True;
  AllAssets.UseLocale := False;
  AllAssets.Sorted := True;
  AllAssets.Duplicates := dupIgnore;
  Tags := TCounter.Create;
  Attrs := TCounter.Create;
  Cls := TCounter.Create;
  Report := TJSONObject.Create;
  try
    FindPages(Root, '', Names);
    Names.Sort;
    SetLength(Pages, Names.Count);
    for I := 0 to Names.Count - 1 do
    begin
      Pages[I] := ReadPageFile(Root + Names[I]);
      Tags.AddAll(Pages[I].Tags);
      Attrs.AddAll(Pages[I].Attrs);
      Cls.AddAll(Pages[I].Classes_);
    end;

    BrokenList := TJSONArray.Create;
    for I := 0 to Names.Count - 1 do
    begin
      L := TStringList.Create;
      try
        L.AddStrings(Pages[I].Links);
        L.AddStrings(Pages[I].Assets);
        for K := 0 to L.Count - 1 do
        begin
          Ref := L[K];
          if IsElsewhere(Ref) then Continue;
          Frag := '';
          PathPart := Ref;
          P := Pos('#', PathPart);
          if P > 0 then
          begin
            Frag := Unquote(Copy(PathPart, P + 1, MaxInt));
            SetLength(PathPart, P - 1);
          end;
          P := Pos('?', PathPart);
          if P > 0 then SetLength(PathPart, P - 1);
          if PathPart <> '' then
            Path := ExpandFileName(ExtractFilePath(Root + Names[I]) +
              StringReplace(Unquote(PathPart), '/', PathDelim, [rfReplaceAll]))
          else
            Path := ExpandFileName(Root + Names[I]);
          if DirectoryExists(Path) then
            Path := IncludeTrailingPathDelimiter(Path) + 'index.html';
          if not FileExists(Path) then
          begin
            Broken := TJSONObject.Create;
            Broken.Add('page', Names[I]);
            Broken.Add('reference', Ref);
            BrokenList.Add(Broken);
          end
          else if (Frag <> '') and (LowerCase(ExtractFileExt(Path)) = '.html') then
          begin
            Dest := -1;
            if AnsiStartsStr(Root, Path) then
              Dest := Names.IndexOf(StringReplace(Copy(Path, Length(Root) + 1, MaxInt),
                PathDelim, '/', [rfReplaceAll]));
            if (Dest >= 0) and (Pages[Dest].Ids.IndexOf(Frag) < 0) then
            begin
              Broken := TJSONObject.Create;
              Broken.Add('page', Names[I]);
              Broken.Add('reference', Ref);
              Broken.Add('reason', 'missing anchor');
              BrokenList.Add(Broken);
            end;
          end;
        end;
      finally
        L.Free;
      end;
      AllAssets.AddStrings(Pages[I].Assets);
    end;

    Report.Add('source', Source);
    Report.Add('page_count', Names.Count);
    List := TJSONArray.Create;
    for Name in Names do List.Add(Name);
    Report.Add('pages', List);
    Report.Add('tags', Tags.AsJSON);
    Report.Add('attributes', Attrs.AsJSON);
    Report.Add('classes', Cls.AsJSON);
    List := TJSONArray.Create;
    for Name in AllAssets do List.Add(Name);
    Report.Add('asset_references', List);
    Report.Add('broken_references', BrokenList);

    Text := Report.FormatJSON + LineEnding;
    if Output <> '' then
    begin
      L := TStringList.Create;
      try
        L.Text := Text;
        L.SaveToFile(Output);
      finally
        L.Free;
      end;
    end
    else
      Write(Text);
  finally
    for I := 0 to High(Pages) do Pages[I].Free;
    Report.Free;
    Tags.Free; Attrs.Free; Cls.Free;
    AllAssets.Free;
    Names.Free;
  end;
end.
