program MarkdownRoundTripTests;
{$mode objfpc}{$H+}
uses
  Interfaces,
  Forms,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  LazUTF8,
  LCLType,
  InkDraw,
  InkRichEdit,
  InkCodeMemo,
  InkMarkdown,
  fpjson,
  jsonparser;

type
  TProbe = class(TInkRichEdit)
    procedure TypeText(const S: string);
    procedure RightClick(X, Y: integer);
    function Attr(I: integer): TInkAttr;
    function DocHeight: integer;
  end;

  procedure TProbe.RightClick(X, Y: integer);
  begin
    MouseDown(mbRight, [ssRight], X, Y);
  end;

  procedure TProbe.TypeText(const S: string);
  begin
    InsertPlainText(S);
  end;

  function TProbe.Attr(I: integer): TInkAttr;
  begin
    Result := EffAttr(I);
  end;

  function TProbe.DocHeight: integer;
  begin
    Result := DocumentHeight;
  end;

type
  TImages = class
    Loads: integer;
    procedure Supply(Sender: TObject; const Source: string; Picture: TPicture);
  end;

  procedure TImages.Supply(Sender: TObject; const Source: string; Picture: TPicture);
  begin
    Inc(Loads);
    Picture.Bitmap.SetSize(20, 40);
    Picture.Bitmap.Canvas.Brush.Color := clRed;
    Picture.Bitmap.Canvas.FillRect(0, 0, 20, 40);
  end;

var
  E: TProbe;
  M: TInkCodeMemo;
  F: TForm;
  Checks: integer;

  procedure Equal(const Name, Actual, Expected: string);
  begin
    Inc(Checks);
    if Actual <> Expected then
      raise Exception.Create(Name + LineEnding + 'Expected: ' + Expected + LineEnding + 'Actual: ' + Actual);
  end;

  procedure RoundTrip(const S: string);
  begin
    E.LoadMarkdown(S);
    Equal('untouched round trip', E.AsMarkdown, S);
  end;

var
  S, T: string;
  Col: integer;
  Images: TImages;
  Cases: TJSONArray;
  Input: TFileStream;
  I, SourceFirst, SourceCount: integer;
  B: TInkMarkdownBlocks;
begin
  try
    Application.Initialize;
    F := TForm.CreateNew(nil);
    E := TProbe.Create(F);
    E.Parent := F;
    M := TInkCodeMemo.Create(F);
    M.Parent := F;
    try
      for S in ['', 'hello', 'hello' + #10, 'hello' + #10#10, #10, #10#10] do
      begin
        M.Text := S;
        Equal('plain memo retains final line breaks', M.Text, S);
      end;
      RoundTrip('Title' + #13#10 + '=====' + #13#10#13#10 + '__bold__ &amp; `code`');
      RoundTrip('<!-- keep -->' + #10#10 + '[ref]: /target "Title"' + #10#10 + '[text][ref]');
      RoundTrip('- [x] task' + #10 + '- [ ] next' + #10#10 + '![alt](pic.png "Title")');
      RoundTrip('| A | B |' + #10 + '| :--- | ---: |' + #10 + '| x | y |');
      RoundTrip('~~~pascal' + #10 + '  code' + #10 + '~~~' + #10#10);
      S := 'Title' + #13#10 + '=====' + #13#10#13#10 + 'hello' + #13#10#13#10 + '<!-- keep -->' + #13#10 + '![alt](pic.png)';
      E.LoadMarkdown(S);
      E.SelStart := Pos('hello', E.PlainText) - 1;
      E.SelLength := 5;
      E.TypeText('world');
      Equal('one edited paragraph preserves other blocks', E.AsMarkdown, StringReplace(S, 'hello', 'world', []));
      E.Undo;
      Equal('undo restores original bytes', E.AsMarkdown, S);
      E.Redo;
      Equal('redo preserves other blocks', E.AsMarkdown, StringReplace(S, 'hello', 'world', []));
      E.LoadMarkdown('A paragraph with a' + #10 + 'wrapped line and **bold text**.');
      E.SelStart := 0;
      Equal('wrapped paragraph stays rendered', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkText)));
      Equal('wrapped paragraph has no Markdown markers', E.PlainText, 'A paragraph with a wrapped line and bold text.');
      Images := TImages.Create;
      try
        E.OnImageNeeded := @Images.Supply;
        S := '![a picture](picture.png "Title")';
        E.LoadMarkdown(S);
        Equal('image stays rendered', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkText)));
        Equal('image has one object character', IntToStr(UTF8Length(E.PlainText)), '1');
        Equal('image retains its destination', E.Attr(0).ImageSource, 'picture.png');
        Equal('image participates in line height', IntToStr(Ord(E.DocHeight >= 40)), '1');
        Equal('image decoded once per document', IntToStr(Images.Loads), '1');
        E.SelStart := 1;
        E.TypeText(' caption');
        Equal('typing after image keeps it', E.AsMarkdown, S + ' caption');
        E.Undo;
        Equal('image undo restores original source', E.AsMarkdown, S);
        Col := Images.Loads;
        E.ImageBaseURI := 'file:///another/document.md';
        I := E.DocHeight;
        Equal('changing image base invalidates decoded pictures', IntToStr(Images.Loads), IntToStr(Col + 1));
        Equal('changing image base preserves Markdown bytes', E.AsMarkdown, S);

        E.SelStart := 1;
        E.RightClick(5, 8);
        Equal('right click targets image without selection', IntToStr(E.SelLength), '1');
        Equal('image source range resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
        Equal('image source includes full expression', Copy(E.AsMarkdown, SourceFirst, SourceCount), S);
        E.SelLength := 0;
        E.RightClick(21, 8);
        Equal('right half of image targets same object', IntToStr(E.SelStart), '0');
        Equal('right half selects image object', IntToStr(E.SelLength), '1');
        E.LoadMarkdown('hello');
        E.SelStart := 0;
        E.SelLength := 5;
        E.InsertImage('picture.png', 'A [bracket] and *star* &amp;', 'A "quote" &amp;');
        T := E.AsMarkdown;
        E.LoadMarkdown(T);
        Equal('inserted picture is an object', IntToStr(UTF8Length(E.PlainText)), '1');
        Equal('inserted picture alt text survives punctuation', E.Attr(0).ImageAlt, 'A [bracket] and *star* &amp;');
        Equal('inserted picture title survives quotes and entities', E.Attr(0).ImageTitle, 'A "quote" &amp;');

      finally
        E.OnImageNeeded := nil;
        Images.Free;
      end;
      S := '- [x] completed' + #10 + '- [ ] pending';
      E.LoadMarkdown(S);
      E.SelStart := 0;
      Equal('tasks stay rendered', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkBullet)));
      Equal('task is a checkbox object', IntToStr(E.Attr(0).TaskState), '1');
      E.ToggleTask;
      Equal('task toggle changes only its marker', E.AsMarkdown, StringReplace(S, '[x]', '[ ]', []));
      E.Undo;
      Equal('task undo keeps original source', E.AsMarkdown, S);
      S := '[named][ref]' + #10#10 + '[ref]: /target "Title"';
      E.LoadMarkdown(S);
      E.SelStart := 0;
      Equal('reference with title stays rendered', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkText)));
      Equal('link retains its title', E.Attr(0).LinkTitle, 'Title');
      Equal('reference source remains intact', E.AsMarkdown, S);
      S := 'first  ' + #10 + 'second' + #10#10 + '__unchanged__';
      E.LoadMarkdown(S);
      E.SelStart := 0;
      Equal('hard break stays rendered', E.PlainText, 'first' + LineEnding + 'second' + LineEnding + 'unchanged');
      E.SelStart := 6;
      E.SelLength := 6;
      E.TypeText('third');
      Equal('editing after hard break preserves other blocks', E.AsMarkdown, StringReplace(S, 'second', 'third', []));
      S := '| A | B |' + #10 + '| :--- | ---: |' + #10 + '| a\|b | 12 |';
      E.LoadMarkdown(S);
      E.SelStart := 0;
      Equal('aligned table stays rendered', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkTableHead)));
      E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('a|b', E.PlainText) - 1));
      E.SelLength := 3;
      E.TypeText('x|y');
      Equal('literal pipe stays inside its cell', E.AsMarkdown, StringReplace(S, 'a\|b', 'x\|y', []));
      E.Undo;
      Equal('table undo restores original bytes', E.AsMarkdown, S);
      S := '__hello__ and other words';
      E.LoadMarkdown(S);
      E.SelStart := 3;
      E.TypeText('p');
      Equal('local insertion keeps alternate emphasis markers', E.AsMarkdown, '__helplo__ and other words');
      E.Undo;
      Equal('insertion undo', E.AsMarkdown, S);
      E.LoadMarkdown('one' + #10#10 + 'two');
      E.SelStart := 3;
      E.SelLength := 1;
      E.TypeText('');
      Equal('joining paragraphs keeps both words', Trim(E.AsMarkdown), 'onetwo');
      E.Undo;
      Equal('join undo restores spacing', E.AsMarkdown, 'one' + #10#10 + 'two');
      E.LoadMarkdown('# Heading' + #10#10 + 'paragraph');
      E.SelStart := Pos('paragraph', E.PlainText) - 1;
      E.TypeText('new ');
      Equal('typing at paragraph start keeps its kind', E.AsMarkdown, '# Heading' + #10#10 + 'new paragraph');
      E.LoadMarkdown('first' + #10#10 + 'second');
      E.Clear;
      E.TypeText('replacement');
      Equal('clear then type retains new content', Trim(E.AsMarkdown), 'replacement');
      E.Undo;
      E.Undo;
      Equal('undo clear and typing restores source', E.AsMarkdown, 'first' + #10#10 + 'second');
      E.LoadMarkdown('before' + #10#10 + '__bold__');
      E.SelStart := 7;
      E.SelLength := 4;
      E.ClearFormatting;
      Equal('clear formatting keeps source identity', E.AsMarkdown, 'before' + #10#10 + 'bold');
      for Col := 1 to 4 do
      begin
        E.Markup.Clear;
        E.InsertTable(Col, 2);
        T := '|';
        while Length(T) < 1 + Col * 6 do T := T + ' --- |';
        Equal('new table has delimiter columns', IntToStr(Ord(Pos(T, E.AsMarkdown) > 0)), '1');
      end;
      E.Markup.Text := '<font face="Monospace">a`b</font>';
      Equal('code spans quote embedded backticks', Trim(E.AsMarkdown), '``a`b``');
      E.Markup.Text := '<pre>```</pre>';
      Equal('code fences exceed embedded backticks', E.AsMarkdown, '````' + LineEnding + '```' + LineEnding + '````' + LineEnding);
      B := MarkdownBlocks('# a' + #10 + 'text' + #10#10 + '- b' + #10 + '- c');
      Equal('three source blocks', IntToStr(Length(B)), '3');
      Equal('heading range', Copy('# a' + #10 + 'text', B[0].First, B[0].Count), '# a' + #10);
      E.LoadMarkdown('hello');
      E.SelStart := 5;
      E.InsertParagraph;
      Equal('a new empty paragraph is saved', E.AsMarkdown, 'hello' + #10#10);
      E.Undo;
      Equal('empty paragraph undo restores missing final newline', E.AsMarkdown, 'hello');
      E.LoadMarkdown('hello world');
      E.SelStart := 0;
      E.SelLength := 6;
      E.ApplyStyle(fsBold, True);
      Equal('bold with trailing selection space is valid Markdown', MarkdownToHTML(E.AsMarkdown), '<p><strong>hello</strong> world</p>' + #10);
      { a written paragraph is escaped only where Markdown would read markup }
      for T in ['well-known & co. #tag! a<b ~x [y] +z snake_case 1. a', '- not a list', '1. not a list', '# not a heading', '> not a quote',
          '---', '&amp; is an entity', '~~not struck~~'] do
      begin
        E.LoadMarkdown('first');
        E.SelStart := 5;
        E.InsertParagraph;
        E.TypeText(T);
        S := E.AsMarkdown;
        E.LoadMarkdown(S);
        Equal('typed text survives a reload: ' + T, E.PlainText, 'first' + LineEnding + T);
      end;
      E.LoadMarkdown('first');
      E.SelStart := 5;
      E.InsertParagraph;
      E.TypeText('well-known & co. #tag! a<b snake_case 1. a');
      Equal('plain punctuation is not escaped', E.AsMarkdown, 'first' + #10#10 + 'well-known & co. #tag! a\<b snake_case 1. a');
      E.LoadMarkdown('text here');
      E.SelStart := 0;
      E.SelLength := 4;
      E.ApplyLink('https://example.com/a?b=1&c=2');
      Equal('a plain link destination', E.AsMarkdown, '[text](https://example.com/a?b=1&c=2) here');
      E.LoadMarkdown('x');
      E.SelStart := 1;
      E.InsertImage('pic one.png', 'alt');
      Equal('a destination with a space goes in angle brackets', E.AsMarkdown, 'x![alt](<pic one.png>)');
      Equal('an escaped backslash before a pipe leaves the pipe a divider',
        MarkdownToHTML('| A | B |' + #10 + '| - | - |' + #10 + '| a\\| b |'),
        '<table>' + #10 + '<thead><tr><th>A</th><th>B</th></tr></thead>' + #10 + '<tbody>' + #10 + '<tr><td>a\</td><td>b</td></tr>' +
        #10 + '</tbody>' + #10 + '</table>' + #10);
      { a block shown as source keeps its empty lines when one of its lines is edited }
    S := '* one' + #10#10 + '* two' + #10#10 + '* three';
    E.LoadMarkdown(S);
    E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('two', E.PlainText) - 1));
    E.TypeText('2 ');
    Equal('edited source block keeps its blank lines', E.AsMarkdown, StringReplace(S, 'two', '2 two', []));
    { an edit in a code block keeps its tabs, its indent style and its info }
    for T in ['```java {.numberLines}' + #10 + 'if (x) {' + #10 + #9 + 'throw y;' + #10 + '}' + #10 + '```',
      'Text' + #10#10 + '    cp a b' + #10 + '    ls' + #10#10 + '    # later' + #10 + '    run'] do
    begin
      E.LoadMarkdown(T);
      if Pos('throw', E.PlainText) > 0 then
        E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('throw', E.PlainText) - 1))
      else
        E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('cp a', E.PlainText) - 1));
      E.TypeText('Z');
      if Pos('throw', T) > 0 then
        Equal('code edit keeps tabs and info', E.AsMarkdown, StringReplace(T, 'throw', 'Zthrow', []))
      else
        Equal('indented code edit stays indented', E.AsMarkdown, StringReplace(T, 'cp a', 'Zcp a', []));
    end;
    { find: on through the matches, round the end, back, case }
    E.LoadMarkdown('Alpha beta alpha **ALPHA**' + #10#10 + 'é café');
    E.SelStart := 0;
    Equal('find selects the first', IntToStr(Ord(E.Find('alpha'))) + ' ' + IntToStr(E.SelStart), '1 0');
    E.Find('alpha');
    Equal('find goes on to the next', IntToStr(E.SelStart), '11');
    E.Find('alpha');
    Equal('find ignores case and formatting', IntToStr(E.SelStart) + ' ' + E.SelText, '17 ALPHA');
    E.Find('alpha');
    Equal('find goes round the end', IntToStr(E.SelStart), '0');
    E.Find('alpha', [ifoBackwards]);
    Equal('find backwards goes round the start', IntToStr(E.SelStart), '17');
    Equal('find counts and knows which is selected', IntToStr(E.FindCount('alpha', [], I)) + ' ' + IntToStr(I), '3 3');
    Equal('match case counts one', IntToStr(E.FindCount('alpha', [ifoMatchCase], I)), '1');
    Equal('find across a paragraph break and accents', IntToStr(Ord(E.Find('CAFÉ'))) + ' ' + E.SelText, '1 café');
    Equal('nothing found', IntToStr(Ord(E.Find('gamma'))), '0');
    Equal('find leaves the source alone', E.AsMarkdown, 'Alpha beta alpha **ALPHA**' + #10#10 + 'é café');
    { paragraph spacing: between blocks, never inside one list }
    for T in ['one' + #10#10 + 'two', '- one' + #10 + '- two', '- one' + #10 + '  - two', '- one' + #10#10 + '1. two'] do
    begin
      E.ParagraphSpacing := False;
      E.LoadMarkdown(T);
      Col := E.DocHeight;
      E.ParagraphSpacing := True;
      I := E.DocHeight;
      if (T = '- one' + #10 + '- two') or (T = '- one' + #10 + '  - two') then
        Equal('no space inside a list: ' + T, IntToStr(I), IntToStr(Col))
      else
        Equal('space between blocks: ' + T, IntToStr(Ord(I > Col)), '1');
    end;
    E.ParagraphSpacing := False;
    E.LoadMarkdown('# First' + #10#10 + '# First');
      Equal('duplicate heading anchor resolves', IntToStr(Ord(E.JumpToAnchor('first-1'))), '1');
      Equal('anchor moves into the second heading', IntToStr(E.SelStart), '6');
      S := '# A heading' + #13#10#13#10 + '**same** and [same](same) then same';
      E.LoadMarkdown(S);
      E.SelStart := Pos('then same', E.PlainText) - 1 + 5;
      E.SelLength := 4;
      Equal('source range finds repeated selected word', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('source range selects the correct occurrence', IntToStr(SourceFirst), IntToStr(Length(S) - 3));
      Equal('source range preserves source bytes', E.AsMarkdown, S);
      E.LoadMarkdown('**bold** and *italic*');
      E.SelStart := 0;
      E.SelLength := 15;
      Equal('source range crosses formatting runs', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('source span includes intervening markup', Copy(E.AsMarkdown, SourceFirst, SourceCount), 'bold** and *italic');
      E.LoadMarkdown('A &amp; B');
      E.SelStart := 2;
      E.SelLength := 1;
      Equal('entity source range resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('entity source selection covers the whole entity', Copy(E.AsMarkdown, SourceFirst, SourceCount), '&amp;');
      E.LoadMarkdown('A &#233; B');
      E.SelStart := 2;
      E.SelLength := 1;
      Equal('numeric entity source range resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('numeric entity source selection covers whole spelling', Copy(E.AsMarkdown, SourceFirst, SourceCount), '&#233;');
      E.LoadMarkdown('a \* b');
      E.SelStart := 2;
      E.SelLength := 1;
      Equal('escaped punctuation source range resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('escape source selection includes backslash', Copy(E.AsMarkdown, SourceFirst, SourceCount), '\*');
      S := 'before ![same](a.png "title") then ![same](b.png) after';
      E.LoadMarkdown(S);
      E.SelStart := UTF8Length('before ') + 1 + UTF8Length(' then ');
      E.SelLength := 1;
      Equal('second image source resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('second image selects its own markup', Copy(S, SourceFirst, SourceCount), '![same](b.png)');
      S := '![same][picture]' + #10#10 + '[picture]: pic.png "Title"';
      E.LoadMarkdown(S);
      E.SelStart := 0;
      E.SelLength := 1;
      Equal('reference image source resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('reference image selects expression without definition', Copy(S, SourceFirst, SourceCount), '![same][picture]');
      E.SelLength := 0;
      Equal('caret before image resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('caret before image points at image syntax', IntToStr(SourceFirst), '1');
      E.SelStart := 1;
      Equal('caret after image resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('caret after image points past image syntax', IntToStr(SourceFirst), IntToStr(Length('![same][picture]') + 1));
      E.LoadMarkdown('- [X] complete');
      E.SelStart := 0;
      Equal('task caret resolves without selection', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('task caret points at its original checkbox marker', IntToStr(SourceFirst), '3');

      E.LoadMarkdown('A **bold** word');
      E.SelStart := 4;
      Equal('caret within bold maps without selection', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('caret points into bold source', IntToStr(SourceFirst), '7');
      Equal('caret navigation leaves source selection empty', IntToStr(SourceCount), '0');
      E.SelStart := UTF8Length(E.PlainText);
      Equal('end caret resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('end caret points past final source character', IntToStr(SourceFirst), '16');
      E.LoadMarkdown('');
      Equal('empty document caret resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('empty source position is one', IntToStr(SourceFirst), '1');
      S := '| Alpha | Beta |' + #10 + '| --- | --- |' + #10 + '| same | same |';
      E.LoadMarkdown(S);
      E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('Beta', E.PlainText) - 1)) + 1;
      Equal('table caret resolves without selection', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('table caret points into matching cell', Copy(S, SourceFirst, 3), 'eta');
      E.RightClick(95, 8);
      Equal('right click table maps without selecting', IntToStr(E.SelLength), '0');
      Equal('right click table source resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('right click table source stays in its header row', IntToStr(Ord((SourceFirst >= 1) and (SourceFirst <= Pos(#10, S)))), '1');

      E.LoadMarkdown('| A | B |' + #10 + '| --- | --- |' + #10 + '|  |  |');
      E.SelStart := UTF8Length(E.PlainText);
      Equal('empty table cell resolves', IntToStr(Ord(E.MarkdownSourceRange(SourceFirst, SourceCount))), '1');
      Equal('empty cell navigation is a caret', IntToStr(SourceCount), '0');
      E.LoadMarkdown('hello world');
      E.SelStart := 0;
      E.SelLength := 2;
      E.RightClick(70, 8);
      Equal('right click outside selection places a caret', IntToStr(E.SelLength), '0');
      Equal('right click moves away from stale selection', IntToStr(Ord(E.SelStart > 2)), '1');
      S := '| A |' + #10 + '| --- |' + #10 + '| `a\|b` |';
      E.LoadMarkdown(S);
      Equal('escaped code pipe renders inside table', IntToStr(Ord(Pos('a|b', E.PlainText) > 0)), '1');
      E.SelStart := UTF8Length(Copy(E.PlainText, 1, Pos('a|b', E.PlainText) - 1));
      E.SelLength := 3;
      E.ApplyStyle(fsBold, True);
      T := E.AsMarkdown;
      E.LoadMarkdown(T);
      Equal('code pipe serialization retains cell contents', IntToStr(Ord(Pos('a|b', E.PlainText) > 0)), '1');
      Equal('code pipe serialization retains table', IntToStr(Ord(E.SelParaKind)), IntToStr(Ord(ipkTableHead)));
      E.LoadMarkdown('before');
      E.SelStart := 6;
      E.InsertImage('pic.png', 'picture');
      E.Undo;
      Equal('image insertion is one undo step', E.AsMarkdown, 'before');
      E.LoadMarkdown('```' + #10 + 'code' + #10 + '```');
      E.InsertImage('pic.png', 'picture');
      Equal('image markup is not inserted into literal code', E.AsMarkdown, '```' + #10 + 'code' + #10 + '```');
      Equal('escaped final pipe stays in the table cell', MarkdownToHTML('| A |' + #10 + '| --- |' + #10 + '| a\|'),
        '<table>' + #10 + '<thead><tr><th>A</th></tr></thead>' + #10 + '<tbody>' + #10 + '<tr><td>a|</td></tr>' + #10 + '</tbody>' + #10 + '</table>' + #10);
      if ParamCount > 0 then
      begin
        Input := TFileStream.Create(ParamStr(1), fmOpenRead);
        try
          Cases := GetJSON(Input) as TJSONArray
        finally
          Input.Free
        end;
        try
          for I := 0 to Cases.Count - 1 do RoundTrip(Cases.Objects[I].Get('markdown', ''));
        finally
          Cases.Free
        end;
      end;
      WriteLn(Checks, ' round-trip checks passed.');
    finally
      F.Free;
    end;
  except
    on Err: Exception do
    begin
      WriteLn(Err.ClassName, ': ', Err.Message);
      Halt(1);
    end;
  end;
end.
