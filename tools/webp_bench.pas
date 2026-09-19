{ Headless pixel-decoder benchmark. Input: a still WebP, optional iterations.
  Build: fpc -O3 -Fu. -FU<temporary-dir> -FE<temporary-dir> tools/webp_bench.pas
  SPDX-License-Identifier: 0BSD }
program WebPBench;
{$mode objfpc}{$H+}
uses Classes, SysUtils, InkWebPLossless, InkWebPVP8;
var Stream: TFileStream; Data: TBytes; Pixels: TInkWebPPixels;
    Pos, Size, W,H,N,I: Integer; Lossless,OK: Boolean; Started,Elapsed: QWord;
    Kind: string;
begin
  if ParamCount < 1 then
  begin WriteLn('Usage: webp_bench still.webp [iterations]'); Halt(1) end;
  N := 100; if ParamCount > 1 then N := StrToInt(ParamStr(2));
  if N < 1 then Halt(1);
  Stream := TFileStream.Create(ParamStr(1),fmOpenRead);
  try SetLength(Data,Stream.Size); Stream.ReadBuffer(Data[0],Length(Data)) finally Stream.Free end;
  Pos := 12;
  while Pos+8 <= Length(Data) do
  begin
    Size := Data[Pos+4] or (Data[Pos+5] shl 8) or (Data[Pos+6] shl 16) or (Data[Pos+7] shl 24);
    if (Size < 0) or (Size > Length(Data)-Pos-8) then Halt(2);
    if (Data[Pos]=Ord('V')) and (Data[Pos+1]=Ord('P')) and (Data[Pos+2]=Ord('8')) and
      (Data[Pos+3] in [Ord('L'),Ord(' ')]) then Break;
    Inc(Pos,8+Size+(Size and 1));
  end;
  if Pos+8 > Length(Data) then begin WriteLn('Expected a still VP8/VP8L chunk'); Halt(2) end;
  Lossless := Data[Pos+3]=Ord('L'); Inc(Pos,8);
  if Lossless then
  begin
    if Size < 5 then Halt(2);
    W := 1+(Data[Pos+1] or ((Data[Pos+2] and 63) shl 8));
    H := 1+((Data[Pos+2] shr 6) or (Data[Pos+3] shl 2) or ((Data[Pos+4] and 15) shl 10));
    Kind := 'VP8L';
  end
  else
  begin
    if Size < 10 then Halt(2);
    W := Data[Pos+6] or ((Data[Pos+7] and 63) shl 8);
    H := Data[Pos+8] or ((Data[Pos+9] and 63) shl 8); Kind := 'VP8';
  end;
  Started := GetTickCount64;
  for I := 1 to N do
  begin
    if Lossless then OK := InkDecodeVP8L(@Data[Pos],Size,W,H,Pixels)
    else OK := InkDecodeVP8(@Data[Pos],Size,W,H,Pixels);
    if not OK then begin WriteLn('Decode failed'); Halt(2) end;
  end;
  Elapsed := GetTickCount64-Started;
  WriteLn(Format('%s %dx%d: %.3f ms/decode, %d iterations, %d ms total',
    [Kind,W,H,Elapsed/N,N,Elapsed]));
end.
