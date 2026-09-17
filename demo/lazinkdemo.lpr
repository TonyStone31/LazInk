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
  Application.Run;
end.
