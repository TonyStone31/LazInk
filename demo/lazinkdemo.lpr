program lazinkdemo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Main;


begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'LazInk demo';
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  if (ParamCount >= 2) and (ParamStr(1) = '--screenshots') then
  begin
    frmMain.Show;
    Application.ProcessMessages;
    frmMain.SaveScreenshots(ParamStr(2));
    Exit;
  end;
  Application.Run;
end.
