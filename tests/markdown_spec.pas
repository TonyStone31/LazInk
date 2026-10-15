program MarkdownSpec;
{$mode objfpc}{$H+}
uses
  Classes,
  SysUtils,
  fpjson,
  jsonparser,
  InkMarkdown;

var
  Input: TFileStream;
  Cases: TJSONArray;
  I: integer;
begin
  if ParamCount <> 1 then Halt(2);
  Input := TFileStream.Create(ParamStr(1), fmOpenRead or fmShareDenyNone);
  try
    Cases := GetJSON(Input) as TJSONArray
  finally
    Input.Free
  end;
  try
    for I := 0 to Cases.Count - 1 do
      Cases.Objects[I].Add('actual', MarkdownToHTML(Cases.Objects[I].Get('markdown', ''), [imoRawHTML]));
    WriteLn(Cases.AsJSON);
  finally
    Cases.Free
  end;
end.
