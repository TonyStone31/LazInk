program htmlprobe;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, Classes, SysUtils, Graphics, Types, InkPage;
var F: TForm; P: TInkPage; I: Integer;
begin
  Application.Initialize;
  F := TForm.CreateNew(nil);
  F.SetBounds(0,0,760,600);
  P := TInkPage.Create(F);
  P.Parent := F;
  P.SetBounds(0,0,760,600);
  P.LoadFromFile(ParamStr(1));
  F.Show;
  for I := 1 to 30 do begin Application.ProcessMessages; Sleep(50) end;
  WriteLn('shown');
end.
