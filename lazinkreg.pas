{ LazInk — component registration. }
unit LazInkReg;

{$mode objfpc}{$H+}

interface

uses
  Classes, LResources;

procedure Register;

implementation

uses
  InkLabel, InkEdit, InkMemo, InkListBox, InkRichEdit, InkPage;

procedure Register;
begin
  RegisterComponents('LazInk', [TInkLabel, TInkEdit, TInkRichEdit, TInkMemo, TInkListBox, TInkPage]);
end;

initialization
  {$I lazink_images.lrs}

end.
