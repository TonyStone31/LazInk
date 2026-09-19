{ Pure Pascal VP8L decoder, independently implemented from RFC 9649 section 3.
  Packed pixels are $AARRGGBB. No native libraries or external codec units.
  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkWebPLossless;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}{$pointermath on}
interface
uses SysUtils;
type
  TInkWebPPixels = array of LongWord;
function InkDecodeVP8L(Data: PByte; Size, Width, Height: Integer;
  out Pixels: TInkWebPPixels; Header: Boolean = True): Boolean;
implementation
const
  MaxPixels = 16*1024*1024;
  MaxTables = 4096; { bound entropy table memory on hostile input }
type
  EWebPBits = class(Exception);
  TBits = record
    Data: PByte;
    Size, Position, Count: Integer;
    Buffer: QWord;
    function Read(N: Integer): LongWord;
    function Peek8: Integer;
    procedure Drop(N: Integer); inline;
  end;
  TNode = record Child: array[0..1] of Integer end;
  TFast = record Value: Integer; Bits: Byte end;
  THuffman = record
    Nodes: array of TNode;
    Fast: array[0..255] of TFast;
    Single: Integer;
    procedure Build(const Lengths: array of Byte);
    function Decode(var Bits: TBits): Integer;
  end;
  TGroup = array[0..4] of THuffman;
  TTransform = record
    Kind, Bits, Width, Count: Integer;
    Data: TInkWebPPixels;
  end;
  TDecoder = class
    Bits: TBits;
    Budget: Int64;
    procedure ReadTree(var Tree: THuffman; Alphabet: Integer);
    function Raster(W, H: Integer; Main: Boolean): TInkWebPPixels;
    function Image(W, H: Integer): TInkWebPPixels;
  end;

procedure Bad;
begin raise EWebPBits.Create('Invalid or truncated VP8L data') end;

function TBits.Read(N: Integer): LongWord;
begin
  while Count < N do
  begin
    if Position >= Size then Bad;
    Buffer := Buffer or (QWord(Data[Position]) shl Count);
    Inc(Position); Inc(Count, 8);
  end;
  Result := LongWord(Buffer and ((QWord(1) shl N)-1));
  Drop(N);
end;

procedure TBits.Drop(N: Integer);
begin Buffer := Buffer shr N; Dec(Count, N) end;

function TBits.Peek8: Integer;
begin
  if (Count < 8) and (Position < Size) then
  begin
    Buffer := Buffer or (QWord(Data[Position]) shl Count);
    Inc(Position); Inc(Count, 8);
  end;
  if Count < 8 then Exit(-1);
  Result := Buffer and 255;
end;

procedure THuffman.Build(const Lengths: array of Byte);
var Counts, Next: array[0..15] of Integer;
    I, J, N, Used, Code, Left, Node, Bit, Child: Integer;
begin
  FillChar(Counts, SizeOf(Counts), 0);
  Single := -1; Used := 0;
  for I := 0 to High(Lengths) do
    if Lengths[I] <> 0 then
    begin
      if Lengths[I] > 15 then Bad;
      Inc(Counts[Lengths[I]]); Inc(Used); Single := I;
    end;
  if Used = 0 then Bad;
  if Used = 1 then Exit;
  Single := -1;
  Left := 1; Code := 0; Next[0] := 0;
  for I := 1 to 15 do
  begin
    Left := Left*2-Counts[I];
    if Left < 0 then Bad;
    Code := (Code+Counts[I-1])*2; Next[I] := Code;
  end;
  if Left <> 0 then Bad;
  SetLength(Nodes, 2*Used);
  for I := 0 to High(Nodes) do
  begin Nodes[I].Child[0] := 0; Nodes[I].Child[1] := 0 end;
  N := 1;
  for I := 0 to High(Lengths) do
    if Lengths[I] <> 0 then
    begin
      Code := Next[Lengths[I]]; Inc(Next[Lengths[I]]); Node := 0;
      for J := Lengths[I]-1 downto 0 do
      begin
        Bit := (Code shr J) and 1;
        if J = 0 then Nodes[Node].Child[Bit] := -I-1
        else
        begin
          Child := Nodes[Node].Child[Bit];
          if Child = 0 then
          begin
            if N >= Length(Nodes) then Bad;
            Child := N; Inc(N); Nodes[Node].Child[Bit] := Child;
          end;
          if Child < 0 then Bad;
          Node := Child;
        end;
      end;
    end;
  for I := 0 to 255 do
  begin
    Node := 0; J := 0;
    repeat
      Node := Nodes[Node].Child[(I shr J) and 1]; Inc(J);
    until (Node < 0) or (J = 8);
    Fast[I].Value := Node; Fast[I].Bits := J;
  end;
end;

function THuffman.Decode(var Bits: TBits): Integer;
var Node, V: Integer;
begin
  if Single >= 0 then Exit(Single);
  V := Bits.Peek8;
  Node := 0;
  if V >= 0 then
  begin Node := Fast[V].Value; Bits.Drop(Fast[V].Bits) end;
  while Node >= 0 do Node := Nodes[Node].Child[Bits.Read(1)];
  Result := -Node-1;
end;

procedure TDecoder.ReadTree(var Tree: THuffman; Alphabet: Integer);
const Order: array[0..18] of Byte =
  (17,18,0,1,2,3,4,5,16,6,7,8,9,10,11,12,13,14,15);
var Lengths: array of Byte; CL: array[0..18] of Byte; Codes: THuffman;
    N, I, V, Previous, RepeatCount, Limit, J: Integer;
begin
  SetLength(Lengths, Alphabet);
  if Bits.Read(1) <> 0 then
  begin
    N := Bits.Read(1)+1;
    I := Bits.Read(1); V := Bits.Read(1+7*I);
    if V >= Alphabet then Bad;
    Lengths[V] := 1;
    if N = 2 then
    begin V := Bits.Read(8); if V >= Alphabet then Bad; Lengths[V] := 1 end;
  end
  else
  begin
    FillChar(CL, SizeOf(CL), 0);
    N := Bits.Read(4)+4;
    for I := 0 to N-1 do CL[Order[I]] := Bits.Read(3);
    Codes.Build(CL);
    Limit := Alphabet;
    if Bits.Read(1) <> 0 then
    begin N := 2+2*Bits.Read(3); Limit := 2+Bits.Read(N) end;
    if Limit > Alphabet then Bad;
    I := 0; Previous := 8;
    while (I < Alphabet) and (Limit > 0) do
    begin
      Dec(Limit); V := Codes.Decode(Bits);
      if V < 16 then
      begin Lengths[I] := V; Inc(I); if V <> 0 then Previous := V end
      else
      begin
        case V of
          16: begin RepeatCount := 3+Bits.Read(2); V := Previous end;
          17: begin RepeatCount := 3+Bits.Read(3); V := 0 end;
          18: begin RepeatCount := 11+Bits.Read(7); V := 0 end;
        else Bad; RepeatCount := 0 end;
        if RepeatCount > Alphabet-I then Bad;
        for J := 1 to RepeatCount do begin Lengths[I] := V; Inc(I) end;
      end;
    end;
  end;
  Tree.Build(Lengths);
end;

function Prefix(var Bits: TBits; Code: Integer): Integer;
var N: Integer;
begin
  if Code < 4 then Exit(Code+1);
  N := (Code-2) shr 1;
  Result := ((2+(Code and 1)) shl N)+Integer(Bits.Read(N))+1;
end;

function TDecoder.Raster(W, H: Integer; Main: Boolean): TInkWebPPixels;
const
  DistanceX: array[0..119] of ShortInt = (0,1,1,-1,0,2,1,-1,2,-2,2,-2,0,3,1,-1,3,-3,2,-2,3,-3,0,4,1,-1,4,-4,3,-3,2,-2,4,-4,0,3,-3,4,-4,5,1,-1,5,-5,2,-2,5,-5,4,-4,3,-3,5,-5,0,6,1,-1,6,-6,2,-2,6,-6,4,-4,5,-5,3,-3,6,-6,0,7,1,-1,5,-5,7,-7,4,-4,6,-6,2,-2,7,-7,3,-3,7,-7,5,-5,6,-6,8,4,-4,7,-7,8,8,6,-6,8,5,-5,7,-7,8,6,-6,7,-7,8,7,-7,8,8);
  DistanceY: array[0..119] of Byte = (1,0,1,1,2,0,2,2,1,1,2,2,3,0,3,3,1,1,3,3,2,2,4,0,4,4,1,1,3,3,4,4,2,2,5,4,4,3,3,0,5,5,1,1,5,5,2,2,4,4,5,5,3,3,6,0,6,6,1,1,6,6,2,2,5,5,4,4,6,6,3,3,7,0,7,7,5,5,1,1,6,6,4,4,7,7,2,2,7,7,3,3,6,6,5,5,0,7,7,4,4,1,2,6,6,3,7,7,5,5,4,7,7,6,6,5,7,7,6,7);
var Cache: TInkWebPPixels = nil; Map: TInkWebPPixels = nil; Groups: array of TGroup;
    CacheBits, CacheSize, MapBits, MapW, MapH, GroupCount: Integer;
    I, J, N, G, S, R, B, A, Run, Distance, EndRun, Index: Integer;
    Pixel: LongWord;
    Hash: QWord;
begin
  Result := nil;
  N := W*H;
  if (W <= 0) or (H <= 0) or (Int64(W)*H > MaxPixels) then Bad;
  Dec(Budget, Int64(N)*4); if Budget < 0 then Bad;
  CacheBits := 0; CacheSize := 0;
  if Bits.Read(1) <> 0 then
  begin
    CacheBits := Bits.Read(4);
    if (CacheBits < 1) or (CacheBits > 11) then Bad;
    CacheSize := 1 shl CacheBits; SetLength(Cache, CacheSize);
  end;
  MapBits := 0; MapW := 0; GroupCount := 1;
  if Main and (Bits.Read(1) <> 0) then
  begin
    MapBits := Bits.Read(3)+2;
    MapW := (W+(1 shl MapBits)-1) shr MapBits;
    MapH := (H+(1 shl MapBits)-1) shr MapBits;
    Map := Raster(MapW, MapH, False);
    for I := 0 to High(Map) do
    begin
      Map[I] := (Map[I] shr 8) and $FFFF;
      if Map[I] >= LongWord(GroupCount) then GroupCount := Map[I]+1;
    end;
  end;
  if GroupCount > MaxTables then Bad;
  Dec(Budget, Int64(GroupCount)*5*4096); if Budget < 0 then Bad;
  SetLength(Groups, GroupCount);
  for I := 0 to GroupCount-1 do
  begin
    ReadTree(Groups[I][0], 280+CacheSize);
    for J := 1 to 3 do ReadTree(Groups[I][J], 256);
    ReadTree(Groups[I][4], 40);
  end;
  SetLength(Result, N); I := 0;
  while I < N do
  begin
    G := 0;
    if MapBits <> 0 then G := Map[((I div W) shr MapBits)*MapW+((I mod W) shr MapBits)];
    S := Groups[G][0].Decode(Bits);
    EndRun := I+1;
    if S < 256 then
    begin
      R := Groups[G][1].Decode(Bits); B := Groups[G][2].Decode(Bits);
      A := Groups[G][3].Decode(Bits);
      Result[I] := (LongWord(A) shl 24) or (LongWord(R) shl 16) or
        (LongWord(S) shl 8) or LongWord(B);
    end
    else if S < 280 then
    begin
      Run := Prefix(Bits, S-256);
      Distance := Prefix(Bits, Groups[G][4].Decode(Bits));
      if Distance > 120 then Dec(Distance,120)
      else
      begin
        Distance := DistanceX[Distance-1]+DistanceY[Distance-1]*W;
        if Distance < 1 then Distance := 1;
      end;
      if (Distance > I) or (Run > N-I) then Bad;
      EndRun := I+Run;
      for J := I to EndRun-1 do Result[J] := Result[J-Distance];
    end
    else
    begin
      Index := S-280;
      if Index >= CacheSize then Bad;
      Result[I] := Cache[Index];
    end;
    if CacheBits <> 0 then
      for J := I to EndRun-1 do
      begin
        Pixel := Result[J];
        Hash := (QWord(Pixel)*$1E35A7BD) and $FFFFFFFF;
        Cache[Hash shr (32-CacheBits)] := Pixel;
      end;
    I := EndRun;
  end;
end;

function AddPixels(A, B: LongWord): LongWord; inline;
begin
  Result := (((A and $00FF00FF)+(B and $00FF00FF)) and $00FF00FF) or
    (((((A shr 8) and $00FF00FF)+((B shr 8) and $00FF00FF)) and $00FF00FF) shl 8);
end;

function Average(A, B: LongWord): LongWord; inline;
begin Result := (A and B)+(((A xor B) and $FEFEFEFE) shr 1) end;

function Clamp(A: Integer): Integer; inline;
begin if A < 0 then Result := 0 else if A > 255 then Result := 255 else Result := A end;

function Predict(Mode: Integer; L, T, TL, TR: LongWord): LongWord;
var I, A, B, C, V, DL, DT: Integer;
begin
  case Mode of
    0: Result := $FF000000;
    1: Result := L;
    2: Result := T;
    3: Result := TR;
    4: Result := TL;
    5: Result := Average(Average(L,TR),T);
    6: Result := Average(L,TL);
    7: Result := Average(L,T);
    8: Result := Average(TL,T);
    9: Result := Average(T,TR);
    10: Result := Average(Average(L,TL),Average(T,TR));
    11: begin
      DL := 0; DT := 0;
      for I := 0 to 3 do
      begin
        A := (L shr (8*I)) and 255; B := (T shr (8*I)) and 255;
        C := (TL shr (8*I)) and 255;
        Inc(DL, Abs(B-C)); Inc(DT, Abs(A-C));
      end;
      if DL < DT then Result := L else Result := T;
    end;
    12,13: begin
      Result := 0;
      for I := 0 to 3 do
      begin
        A := (L shr (8*I)) and 255; B := (T shr (8*I)) and 255;
        C := (TL shr (8*I)) and 255;
        if Mode = 12 then V := A+B-C
        else begin V := (A+B) div 2; V := V+(V-C) div 2 end;
        Result := Result or (LongWord(Clamp(V)) shl (8*I));
      end;
    end;
  else Bad; Result := 0 end;
end;

function SignedByte(V: LongWord): Integer; inline;
begin Result := V and 255; if Result >= 128 then Dec(Result,256) end;

function Delta(A, B: LongWord): Integer; inline;
var V: Integer;
begin
  V := SignedByte(A)*SignedByte(B);
  if V < 0 then Result := -((-V+31) div 32) else Result := V div 32;
end;

function TDecoder.Image(W, H: Integer): TInkWebPPixels;
var Transforms: array[0..3] of TTransform;
    Seen: set of 0..3;
    Count, K, I, X, Y, TW, TH, N, Mode, R, G, B, PackedW: Integer;
    C, P, L, T, TL, TR: LongWord;
    Expanded: TInkWebPPixels;
begin
  Seen := []; Count := 0; TW := W;
  while Bits.Read(1) <> 0 do
  begin
    K := Bits.Read(2); if K in Seen then Bad; Include(Seen, K);
    Transforms[Count].Kind := K; Transforms[Count].Width := TW;
    case K of
      0,1: begin
        N := Bits.Read(3)+2; Transforms[Count].Bits := N;
        Transforms[Count].Data := Raster((TW+(1 shl N)-1) shr N,
          (H+(1 shl N)-1) shr N, False);
      end;
      3: begin
        N := Bits.Read(8)+1; Transforms[Count].Count := N;
        Transforms[Count].Data := Raster(N,1,False);
        for I := 1 to N-1 do Transforms[Count].Data[I] :=
          AddPixels(Transforms[Count].Data[I], Transforms[Count].Data[I-1]);
        if N <= 2 then K := 3 else if N <= 4 then K := 2
        else if N <= 16 then K := 1 else K := 0;
        Transforms[Count].Bits := K;
        TW := (TW+(1 shl K)-1) shr K;
      end;
    end;
    Inc(Count);
  end;
  Result := Raster(TW,H,True);
  for K := Count-1 downto 0 do
  begin
    TW := Transforms[K].Width; N := Transforms[K].Bits;
    if Transforms[K].Kind = 3 then
    begin
      SetLength(Expanded, TW*H); PackedW := (TW+(1 shl N)-1) shr N;
      for Y := 0 to H-1 do for X := 0 to TW-1 do
      begin
        I := (Result[Y*PackedW+(X shr N)] shr 8) and 255;
        I := (I shr ((X and ((1 shl N)-1))*(8 shr N))) and ((1 shl (8 shr N))-1);
        if I >= Transforms[K].Count then P := 0 else P := Transforms[K].Data[I];
        Expanded[Y*TW+X] := P;
      end;
      Result := Expanded; Expanded := nil;
      Continue;
    end;
    TH := (TW+(1 shl N)-1) shr N;
    for Y := 0 to H-1 do for X := 0 to TW-1 do
    begin
      I := Y*TW+X; P := Result[I];
      case Transforms[K].Kind of
        0: begin
          if Y = 0 then begin if X = 0 then C := $FF000000 else C := Result[I-1] end
          else if X = 0 then C := Result[I-TW]
          else
          begin
            Mode := (Transforms[K].Data[(Y shr N)*TH+(X shr N)] shr 8) and 255;
            L := Result[I-1]; T := Result[I-TW]; TL := Result[I-TW-1]; TR := Result[I-TW+1];
            C := Predict(Mode,L,T,TL,TR);
          end;
          P := AddPixels(P,C);
        end;
        1: begin
          C := Transforms[K].Data[(Y shr N)*TH+(X shr N)]; G := (P shr 8) and 255;
          R := ((P shr 16)+Delta(C,G)) and 255;
          B := (Integer(P and 255)+Delta(C shr 8,G)+Delta(C shr 16,R)) and 255;
          P := (P and $FF00FF00) or (LongWord(R) shl 16) or LongWord(B);
        end;
        2: begin
          G := (P shr 8) and 255;
          P := (P and $FF00FF00) or (((((P shr 16) and 255)+LongWord(G)) and 255) shl 16)
            or (((P and 255)+LongWord(G)) and 255);
        end;
      end;
      Result[I] := P;
    end;
  end;
end;

function InkDecodeVP8L(Data: PByte; Size, Width, Height: Integer;
  out Pixels: TInkWebPPixels; Header: Boolean): Boolean;
var Decoder: TDecoder; W,H: Integer;
begin
  Pixels := nil; Result := False;
  if (Data = nil) or (Size <= 0) or (Width <= 0) or (Height <= 0) or
    (Int64(Width)*Height > MaxPixels) then Exit;
  Decoder := TDecoder.Create;
  try
    Decoder.Bits.Data := Data; Decoder.Bits.Size := Size;
    Decoder.Budget := 256*1024*1024;
    try
      if Header then
      begin
        if Decoder.Bits.Read(8) <> $2F then Exit;
        W := Decoder.Bits.Read(14)+1; H := Decoder.Bits.Read(14)+1;
        if (W <> Width) or (H <> Height) then Exit;
        Decoder.Bits.Read(1);
        if Decoder.Bits.Read(3) <> 0 then Exit;
      end;
      Pixels := Decoder.Image(Width,Height);
      Result := True;
    except on E: EWebPBits do Pixels := nil end;
  finally Decoder.Free end;
end;
end.
