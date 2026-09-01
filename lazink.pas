{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit LazInk;

{$warn 5023 off : no warning about unused units}
interface

uses
  InkHtml, InkLabel, InkEdit, InkMemo, InkListBox, LazInkReg, 
  LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('LazInkReg', @LazInkReg.Register);
end;

initialization
  RegisterPackage('LazInk', @Register);
end.
