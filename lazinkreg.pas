{ LazInk — component registration. }
unit LazInkReg;

{$mode objfpc}{$H+}

interface

uses
  Classes, LResources, InkCodeMemo;

procedure Register;

implementation

uses
  InkLabel, InkEdit, InkMemo, InkListBox, InkRichEdit, InkPage;

procedure Register;
begin
  RegisterComponents('LazInk', [TInkLabel, TInkEdit, TInkRichEdit, TInkCodeMemo, TInkMemo, TInkListBox, TInkPage]);
end;

initialization
  {$I lazink_images.lrs}

end.
