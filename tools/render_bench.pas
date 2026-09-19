{ Reproducible TInkPage rendering benchmark, including tables and scrolling.
  Run each workload in a fresh process so the shared text cache starts empty.
  Optional PNGs let before/after runs be compared pixel for pixel.
  SPDX-License-Identifier: 0BSD }
program RenderBench;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Graphics, Types, Math, InkPage;
const Repeats = 8;
var Host: TForm; Page: TInkPage; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
    Source: TStringList; Workload, OutputDir: string; I,N: Integer;
    Started, ParseMS, LayoutMS, PaintMS, ScrollMS, ResizeMS: QWord;
    Extent, NarrowExtent: Integer;

procedure Snapshot(const Name: string);
begin
  if OutputDir='' then Exit;
  PNG.Assign(Bitmap);
  PNG.SaveToFile(IncludeTrailingPathDelimiter(OutputDir)+Workload+'-'+Name+'.png');
end;

procedure Paragraphs;
var I: Integer;
begin
  for I := 1 to N do
    Source.Add('<p class="c'+IntToStr(I mod 40)+'" id="p'+IntToStr(I)+'"><b>Section '+IntToStr(I)+'</b>: repeated words ' +
      'and <i>emphasis</i>, <a href="item'+IntToStr(I)+'.html">a link</a>, ' +
      '<code>sample code</code> and Unicode café 日本語. Text wraps across the available column.</p>');
end;

procedure TableRows(Nested: Boolean);
var I: Integer;
begin
  Source.Add('<table style="width:100%;border-collapse:collapse">');
  for I := 1 to N do
  begin
    Source.Add('<tr>');
    if (Workload='spans') and (I mod 8=0) and (I<N) then
      Source.Add('<td rowspan="2" valign="bottom">Row span '+IntToStr(I)+'</td>')
    else if not ((Workload='spans') and (I>1) and (I mod 8=1)) then
      Source.Add('<td>'+IntToStr(I)+'</td>');
    Source.Add('<td><b>A cell with text</b> that wraps into several lines.');
    if Nested then
      Source.Add('<table><tr><td>Nested left column with wrapping text</td>'+
        '<td><i>Nested right column</i></td></tr><tr><td colspan="2">A second nested row.</td></tr></table>');
    if (Workload='spans') and (I mod 5=0) then
      Source.Add('</td><td colspan="2" valign="middle">Column span with wrapping words</td></tr>')
    else Source.Add('</td><td style="vertical-align:middle">Middle-aligned text</td>'+
      '<td style="vertical-align:bottom">Bottom-aligned text</td></tr>');
  end;
  Source.Add('</table>');
end;

begin
  Application.Initialize;
  if ParamCount<1 then
  begin WriteLn('Usage: render_bench paragraphs|styled|table|nested|spans [count] [snapshot-directory]'); Halt(1) end;
  Workload := ParamStr(1);
  if Workload='styled' then N := 500 else if Workload='paragraphs' then N := 2000 else if Workload='table' then N := 250 else N := 60;
  if ParamCount>=2 then N := StrToInt(ParamStr(2));
  if N<1 then Halt(1);
  OutputDir := ParamStr(3); if OutputDir<>'' then ForceDirectories(OutputDir);
  Host := TForm.Create(nil); Bitmap := TBitmap.Create;
  PNG := TPortableNetworkGraphic.Create; Source := TStringList.Create;
  try
    Host.SetBounds(0,0,1000,800);
    Page := TInkPage.Create(Host); Page.Parent := Host; Page.SetBounds(0,0,900,640);
    Page.Font.Name := 'DejaVu Sans'; Page.Font.Height := -16;
    Bitmap.SetSize(900,640);
    Source.Add('<style>body{margin:0;padding:8px} td{padding:6px;border:1px solid #888}</style>');
    if Workload='styled' then
    begin
      Source.Add('<style>');
      for I := 0 to 119 do
        Source.Add('.c'+IntToStr(I)+'{color:#245678} .c'+IntToStr(I)+
          ' code{background-color:#eeeeee} .c'+IntToStr(I)+' a{text-decoration:underline}');
      Source.Add('</style>');
    end;
    if (Workload='paragraphs') or (Workload='styled') then Paragraphs
    else if Workload='table' then TableRows(False)
    else if (Workload='nested') or (Workload='spans') then TableRows(True)
    else raise Exception.Create('Unknown workload');
    Started := GetTickCount64; Page.LoadHTML(Source.Text); ParseMS := GetTickCount64-Started;
    Started := GetTickCount64; Page.ScrollTo(0); LayoutMS := GetTickCount64-Started;
    Extent := Page.ContentHeight;
    Page.RenderTo(Bitmap.Canvas); Snapshot('top');
    Started := GetTickCount64;
    for I := 1 to Repeats do Page.RenderTo(Bitmap.Canvas);
    PaintMS := GetTickCount64-Started;
    Started := GetTickCount64;
    for I := 1 to Repeats do
    begin Page.ScrollTo(Max(0,Extent-Page.Height)*I div Repeats); Page.RenderTo(Bitmap.Canvas) end;
    ScrollMS := GetTickCount64-Started; Snapshot('bottom');
    Page.ScrollTo(Extent div 2); Page.RenderTo(Bitmap.Canvas); Snapshot('middle');
    Started := GetTickCount64;
    Page.Width := 650; Page.ScrollTo(0); ResizeMS := GetTickCount64-Started;
    NarrowExtent := Page.ContentHeight;
    Bitmap.SetSize(650,640); Page.RenderTo(Bitmap.Canvas); Snapshot('narrow');
    WriteLn(Format('%s,count=%d,blocks=%d,height=%d,narrow_height=%d,parse_ms=%d,layout_ms=%d,paint_ms=%.3f,scroll_ms=%.3f,resize_ms=%d',
      [Workload,N,Page.BlockCount,Extent,NarrowExtent,ParseMS,LayoutMS,PaintMS/Repeats,ScrollMS/Repeats,ResizeMS]));
  finally Source.Free; PNG.Free; Bitmap.Free; Host.Free end;
end.
