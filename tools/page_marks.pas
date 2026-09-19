{ Where each heading of a page lands, in LazInk.

    tools/page_marks.pas page.html [column-width]

  Prints one line per heading - its top in document pixels, its tag and its
  first words - and the document's height.  tools/drift.sh asks a browser
  the same question and puts the two side by side, which is how a section
  that has drifted is found without scrolling to it.

  The column is what the text is laid out in, not the control: the control
  is made wider by its own scrollbar so that a column of 700 here is the
  same 700 a browser viewport of 700 gives the page.

  It is a tool, not a test; tests/run.sh does not build it.

  SPDX-License-Identifier: 0BSD }
program PageMarks;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Controls, Classes, SysUtils, InkPage, InkDraw;

var
  Host: TForm;
  Page: TInkPage;
  Block: TInkPageBlock;
  I, Column: Integer;
  Text: string;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: page_marks page.html [column-width]');
    Halt(1);
  end;
  Column := StrToIntDef(ParamStr(2), 700);
  Application.Initialize;
  Host := TForm.CreateNew(nil);
  Host.SetBounds(0, 0, Column + 80, 900);
  Page := TInkPage.Create(Host);
  Page.Parent := Host;
  Page.SetBounds(0, 0, Column, 860);
  Host.Show;
  Application.ProcessMessages;
  { the scrollbar gets its own room, so the text column is exactly Column }
  Page.SetBounds(0, 0, Column + Page.ScrollBar.Width, 860);
  Application.ProcessMessages;
  Page.LoadFromFile(ParamStr(1));
  Application.ProcessMessages;
  for I := 0 to Page.BlockCount - 1 do
  begin
    Block := Page.Block(I);
    if (Length(Block.Tag) = 2) and (Block.Tag[1] = 'h') and
      (Block.Tag[2] in ['1'..'6']) then
    begin
      Text := Trim(HTMLPlainText(Block.Source));
      if Text <> '' then
        WriteLn('MARK ', Block.Bounds.Top, ' ', Block.Tag, ' ', Text);
    end;
  end;
  WriteLn('HEIGHT ', Page.ContentHeight);
end.
