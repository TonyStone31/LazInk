{ LazInk — component registration. }
unit LazInkReg;

{$mode objfpc}{$H+}

interface

uses
  Classes, LResources;

procedure Register;

implementation

uses
  InkLabel, InkEdit, InkMemo, InkListBox;

procedure Register;
begin
  RegisterComponents('LazInk', [TInkLabel, TInkEdit, TInkMemo, TInkListBox]);
end;

initialization
  {$I lazink_images.lrs}

end.
