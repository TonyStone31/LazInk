{ Headless codec checks; run with range and overflow checks enabled.
  SPDX-License-Identifier: 0BSD }
program WebPCodecTests;
{$mode objfpc}{$H+}
uses Classes, SysUtils, InkWebPLossless, InkWebPVP8;
var Data, Mutant, Expected: TBytes; Pixels: TInkWebPPixels; S: TFileStream;
    Names: array[0..3] of string = ('noise-lossless','drawing-lossless','noise-lossy','drawing-lossy');
    Widths: array[0..3] of Integer = (35,97,35,97);
    Heights: array[0..3] of Integer = (31,65,31,65);
    I,J,K,P,N,Size,Codec,Diff,Tolerance: Integer; Seed: LongWord; OK: Boolean;
function RandomBelow(N: Integer): Integer;
begin Seed := LongWord((QWord(Seed)*1664525+1013904223) and $FFFFFFFF); Result := Seed mod LongWord(N) end;
function Decode(const Bytes: TBytes; Count: Integer): Boolean;
begin
  if Codec = 0 then Result := InkDecodeVP8L(@Bytes[0],Count,Widths[I],Heights[I],Pixels)
  else Result := InkDecodeVP8(@Bytes[0],Count,Widths[I],Heights[I],Pixels);
end;
begin
  Seed := 9649;
  for I := 0 to High(Names) do
  begin
    S := TFileStream.Create('tests/fixtures/webp/'+Names[I]+'.webp',fmOpenRead);
    try SetLength(Data,S.Size); S.ReadBuffer(Data[0],S.Size) finally S.Free end;
    P := 12;
    while P+8 <= Length(Data) do
    begin
      Size := Data[P+4] or (Data[P+5] shl 8) or (Data[P+6] shl 16) or (Data[P+7] shl 24);
      if (Data[P]=Ord('V')) and (Data[P+1]=Ord('P')) and (Data[P+2]=Ord('8')) and
        (Data[P+3] in [Ord('L'),Ord(' ')]) then Break;
      Inc(P,8+Size+(Size and 1));
    end;
    Codec := Ord(Data[P+3]=Ord(' ')); Data := Copy(Data,P+8,Size);
    if not Decode(Data,Size) then raise Exception.Create('Valid codec fixture failed');
    S := TFileStream.Create('tests/fixtures/webp/'+Names[I]+'.bgra',fmOpenRead);
    try SetLength(Expected,S.Size); S.ReadBuffer(Expected[0],S.Size) finally S.Free end;
    if Codec = 0 then Tolerance := 0 else Tolerance := 3;
    for J := 0 to High(Pixels) do for K := 0 to 3 do
      if (Codec = 0) or (K < 3) then
      begin
        Diff := Abs(Integer((Pixels[J] shr (K*8)) and 255)-Integer(Expected[J*4+K]));
        if Diff > Tolerance then raise Exception.Create('Codec pixel mismatch: '+Names[I]);
      end;
    for J := 0 to Size-1 do OK := Decode(Data,J);
    for J := 1 to 2000 do
    begin
      Mutant := Copy(Data,0,Length(Data));
      for K := 1 to 1+RandomBelow(5) do
      begin N := RandomBelow(Length(Mutant)); Mutant[N] := RandomBelow(256) end;
      OK := Decode(Mutant,Length(Mutant));
    end;
  end;
  if InkDecodeVP8(nil,100,1,1,Pixels) or InkDecodeVP8L(nil,100,1,1,Pixels) then Halt(1);
  WriteLn('WebP codec checks: valid input, every payload truncation, and 8000 deterministic mutations passed.');
end.
