{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit LazInk;

{$warn 5023 off : no warning about unused units}
interface

uses
  InkScrollBar, InkTouch, InkCopyMenu, InkGIF, InkCSS, InkCode, InkWebP, InkWebPLossless, InkWebPVP8, 
  InkBox, InkRender, InkDraw, InkPage, InkMarkdown, InkLabel, InkEdit, 
  InkMemo, InkListBox, InkRichEdit, LazInkReg, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('LazInkReg', @LazInkReg.Register);
end;

initialization
  RegisterPackage('LazInk', @Register);
end.
