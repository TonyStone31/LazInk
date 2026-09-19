program repro;

{ The smallest thing that shows the fault: a TInkPage, a stylesheet, a piece
  of Markdown, and a window left up long enough to photograph.

    fpc -dLCL -dLCLgtk3 -Fu<LazInk> -Fu<lcl units> ... repro.pas
    DISPLAY=:77 ./repro repro.css repro.md

  Take the picture with anything - import -window root will do.  What you
  are looking for is a solid block of color behind the bullets, and no
  block behind the paragraphs.  See README.md beside this. }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types,
  InkPage, InkMarkdown;

var
  F: TForm;
  P: TInkPage;
  L: TStringList;
  I: Integer;
begin
  Application.Initialize;
  F := TForm.CreateNew(nil);
  F.SetBounds(0, 0, 700, 600);
  P := TInkPage.Create(F);
  P.Parent := F;
  P.SetBounds(0, 0, 700, 600);
  P.TextFormat := itfMarkdown;
  L := TStringList.Create;
  L.LoadFromFile(ParamStr(1));            { the stylesheet }
  P.StyleSheet.Text := L.Text;
  L.LoadFromFile(ParamStr(2));            { the Markdown }
  P.Source := L.Text;
  F.Show;
  for I := 1 to 40 do
  begin
    Application.ProcessMessages;
    Sleep(50);
  end;
  WriteLn('shown');
end.
