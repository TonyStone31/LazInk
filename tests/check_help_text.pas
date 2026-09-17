program check_help_text;

{ Check that native page parsing preserves every visible text fragment.

  Run render_tests with its page-list and output-directory arguments first -
  tests/run.sh does both when it is given them - then:

      check_help_text PAGES.TXT RESULTS/

  Every piece of text inside <body>, outside <script> and <style>, has to
  turn up in the text render_tests wrote for that page.  Whitespace is not
  compared: the renderer wraps and collapses it, and that is its job.

  The pages are read with the FCL's own HTML reader (sax_html), not with
  LazInk's parser - the point is to check LazInk against somebody else's
  reading of the same file. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  Classes, SysUtils, sax, sax_html, xmlutils, xmlreader;

type
  TVisibleText = class
  public
    Body: Boolean;
    Hidden: Integer;
    Fragments: TStringList;       { UTF-8 }
    Pending: UnicodeString;
    constructor Create;
    destructor Destroy; override;
    procedure Flush;
    procedure StartElement(Sender: TObject; const NamespaceURI, LocalName,
      QName: SAXString; Atts: TSAXAttributes);
    procedure EndElement(Sender: TObject; const NamespaceURI, LocalName,
      QName: SAXString);
    procedure Characters(Sender: TObject; const Ch: PSAXChar;
      AStart, ALength: Integer);
  end;

constructor TVisibleText.Create;
begin
  Fragments := TStringList.Create;
end;

destructor TVisibleText.Destroy;
begin
  Fragments.Free;
  inherited Destroy;
end;

{ A fragment is all the text between two tags, entities and all - the reader
  hands an entity over as a piece of its own, so the pieces are joined here
  until the next tag. }
procedure TVisibleText.Flush;
begin
  if (Pending <> '') and Body and (Hidden = 0) and (Trim(Pending) <> '') then
    Fragments.Add(UTF8Encode(Pending));
  Pending := '';
end;

procedure TVisibleText.StartElement(Sender: TObject; const NamespaceURI,
  LocalName, QName: SAXString; Atts: TSAXAttributes);
var
  Tag: UnicodeString;
begin
  Flush;
  Tag := LowerCase(LocalName);
  if Tag = 'body' then Body := True;
  if (Tag = 'script') or (Tag = 'style') then Inc(Hidden);
end;

procedure TVisibleText.EndElement(Sender: TObject; const NamespaceURI,
  LocalName, QName: SAXString);
var
  Tag: UnicodeString;
begin
  Flush;
  Tag := LowerCase(LocalName);
  if Tag = 'body' then Body := False;
  if ((Tag = 'script') or (Tag = 'style')) and (Hidden > 0) then Dec(Hidden);
end;

procedure TVisibleText.Characters(Sender: TObject; const Ch: PSAXChar;
  AStart, ALength: Integer);
var
  S: UnicodeString;
begin
  SetLength(S, ALength);
  if ALength > 0 then
    Move(Ch[AStart], S[1], ALength * SizeOf(WideChar));
  Pending := Pending + S;
end;

{ Every kind of space taken out, the no-break one included - &nbsp; is a
  space to a reader and to the renderer's wrapping, if not to the file. }
function Compact(const S: UnicodeString): UnicodeString;
var
  I, N: Integer;
  C: WideChar;
begin
  SetLength(Result, Length(S));
  N := 0;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case Ord(C) of
      9..13, 28..32, $85, $A0, $1680, $2000..$200A, $2028, $2029, $202F,
      $205F, $3000: Continue;
    end;
    Inc(N);
    Result[N] := C;
  end;
  SetLength(Result, N);
end;

function ReadUTF8(const Path: string): UnicodeString;
var
  F: TFileStream;
  Raw: RawByteString;
begin
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Raw, F.Size);
    if F.Size > 0 then F.ReadBuffer(Raw[1], F.Size);
  finally
    F.Free;
  end;
  Result := UTF8Decode(Raw);
end;

procedure ReadPage(const Path: string; Into: TVisibleText);
var
  Reader: THTMLReader;
  Stream: TFileStream;
  Input: TXMLInputSource;
begin
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  Reader := THTMLReader.Create;
  Input := TXMLInputSource.Create(Stream);
  try
    Reader.OnStartElement := @Into.StartElement;
    Reader.OnEndElement := @Into.EndElement;
    Reader.OnCharacters := @Into.Characters;
    { whitespace between tags is a fragment's edge, never a fragment }
    Reader.Parse(Input);
    Into.Flush;
  finally
    Input.Free;
    Reader.Free;
    Stream.Free;
  end;
end;

var
  Pages: TStringList;
  Page: TVisibleText;
  Rendered: UnicodeString;
  I, K, Count, Lost: Integer;
  Name: string;
begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: check_help_text PAGES.TXT RESULTS/');
    Halt(2);
  end;
  Count := 0;
  Lost := 0;
  Pages := TStringList.Create;
  try
    Pages.LoadFromFile(ParamStr(1));
    for I := 0 to Pages.Count - 1 do
    begin
      Name := Trim(Pages[I]);
      if Name = '' then Continue;
      Page := TVisibleText.Create;
      try
        ReadPage(Name, Page);
        Rendered := Compact(ReadUTF8(IncludeTrailingPathDelimiter(ParamStr(2)) +
          ExtractFileName(Name) + '.txt'));
        for K := 0 to Page.Fragments.Count - 1 do
        begin
          if Pos(Compact(UTF8Decode(Page.Fragments[K])), Rendered) = 0 then
          begin
            WriteLn(ExtractFileName(Name), ': lost text "', Page.Fragments[K], '"');
            Inc(Lost);
          end;
          Inc(Count);
        end;
      finally
        Page.Free;
      end;
    end;
  finally
    Pages.Free;
  end;
  if Lost > 0 then
  begin
    WriteLn(Format('%d of %d visible HTML text fragments lost.', [Lost, Count]));
    Halt(1);
  end;
  WriteLn(Format('All %d visible HTML text fragments preserved.', [Count]));
end.
