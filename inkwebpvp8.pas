{ VP8 key-frame decoder for WebP, independently implemented from RFC 6386.
  Only intra frames belong in WebP; video/inter-frame decoding is excluded.
  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkWebPVP8;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}{$pointermath on}
interface
uses SysUtils, Math, InkWebPLossless;
function InkDecodeVP8(Data: PByte; Size, Width, Height: Integer;
  out Pixels: TInkWebPPixels): Boolean;
implementation
type
  EInvalidVP8 = class(Exception);
  TBoolReader = record
    Data: PByte;
    Size, Position, Remaining: Integer;
    Range, Value: LongWord;
    procedure Init(P: PByte; N: Integer);
    function Read(Probability: LongWord): Integer; inline;
    function Literal(N: Integer): Integer;
    function Signed(N: Integer): Integer;
    function Tree(const Nodes: array of ShortInt; Prob: PByte): Integer;
    function NextByte: Byte;
  end;
  TBlock = array[0..15] of Integer;
  TPlane = record
    Data: TBytes;
    Stride, Width, Height: Integer;
    procedure Init(W,H: Integer);
    function At(X,Y: Integer): PByte; inline;
  end;
  TMB = record
    Level: Integer;
    Inner: Boolean;
  end;
  TDecoder = class
    Header: TBoolReader;
    Tokens: array[0..7] of TBoolReader;
    Prob: array[0..1055] of Byte;
    MBWidth, MBHeight, Parts, Sharpness, FilterLevel: Integer;
    Simple, SegmentEnabled, UpdateMap, SegmentAbsolute, AdjustFilter: Boolean;
    SegmentQ, SegmentFilter: array[0..3] of Integer;
    RefDelta, ModeDelta: array[0..3] of Integer;
    SegmentProb: array[0..2] of Byte;
    Quant, SkipProb: Integer;
    QuantDelta: array[0..4] of Integer;
    SkipEnabled: Boolean;
    YPlane, UPlane, VPlane: TPlane;
    Blocks: array of TMB;
    procedure ReadHeader(Data: PByte; Size: Integer);
    function Coefficients(var Reader: TBoolReader; Kind, Context, DC, AC: Integer;
      out Block: TBlock): Integer;
    procedure Reconstruct;
    procedure Filter;
    function Pixels(W,H: Integer): TInkWebPPixels;
  end;
const
{$I inkwebpvp8tables.inc}
  ModeTree: array[0..17] of ShortInt = (0,2,-1,4,-2,6,8,12,-3,10,-5,-6,-4,14,-7,16,-8,-9);
  CoeffTree: array[0..21] of ShortInt = (-11,2,0,4,-1,6,8,12,-2,10,-3,-4,14,16,-5,-6,18,20,-7,-8,-9,-10);
  Band: array[0..15] of Byte = (0,1,2,3,6,4,5,6,6,6,6,6,6,6,6,7);
  Zigzag: array[0..15] of Byte = (0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15);
  ExtraBits: array[0..5] of Byte = (1,2,3,4,5,11);
  ExtraBase: array[0..5] of Word = (5,7,11,19,35,67);
  ExtraProb: array[0..5,0..10] of Byte = (
    (159,0,0,0,0,0,0,0,0,0,0),(165,145,0,0,0,0,0,0,0,0,0),
    (173,148,140,0,0,0,0,0,0,0,0),(176,155,140,135,0,0,0,0,0,0,0),
    (180,157,141,134,130,0,0,0,0,0,0),(254,254,243,230,196,177,153,140,133,130,129));

procedure Invalid;
begin raise EInvalidVP8.Create('Invalid or truncated VP8 key frame') end;

function ASR(V: Integer; N: Byte): Integer; inline;
begin Result := SarLongInt(V,N) end;
function Mul16(V, C: Integer): Integer; inline;
begin Result := SarInt64(Int64(V)*C,16) end;
function Clip(V: Integer): Byte; inline;
begin if V < 0 then Result := 0 else if V > 255 then Result := 255 else Result := V end;
function SignedClip(V: Integer): Integer; inline;
begin Result := EnsureRange(V,-128,127) end;

function TBoolReader.NextByte: Byte;
begin
  if Position >= Size+2 then Invalid;
  if Position < Size then Result := Data[Position] else Result := 0;
  Inc(Position);
end;
procedure TBoolReader.Init(P: PByte; N: Integer);
begin
  if N < 1 then Invalid;
  Data := P; Size := N; Position := 0; Range := 255; Remaining := 8;
  Value := LongWord(NextByte) shl 8; Value := Value or NextByte;
end;
function TBoolReader.Read(Probability: LongWord): Integer;
var Split: LongWord;
begin
  Split := 1+(((Range-1)*Probability) shr 8);
  if Value >= Split shl 8 then
  begin Result := 1; Dec(Value,Split shl 8); Dec(Range,Split) end
  else begin Result := 0; Range := Split end;
  while Range < 128 do
  begin
    Range := Range shl 1; Value := Value shl 1;
    Dec(Remaining);
    if Remaining = 0 then begin Value := Value or NextByte; Remaining := 8 end;
  end;
end;
function TBoolReader.Literal(N: Integer): Integer;
var I: Integer;
begin Result := 0; for I := 1 to N do Result := Result*2+Read(128) end;
function TBoolReader.Signed(N: Integer): Integer;
begin Result := Literal(N); if Read(128) <> 0 then Result := -Result end;
function TBoolReader.Tree(const Nodes: array of ShortInt; Prob: PByte): Integer;
var N: Integer;
begin
  N := 0;
  repeat N := Nodes[N+Read(Prob[N shr 1])] until N <= 0;
  Result := -N;
end;
procedure TPlane.Init(W,H: Integer);
begin
  Width := W; Height := H; Stride := W+32;
  SetLength(Data, (H+2)*Stride);
end;
function TPlane.At(X,Y: Integer): PByte;
begin Result := @Data[(Y+1)*Stride+X+8] end;

procedure TDecoder.ReadHeader(Data: PByte; Size: Integer);
var N, I, J, Start, Offset, PartSize: Integer;
begin
  N := (LongWord(Data[0]) or (LongWord(Data[1]) shl 8) or (LongWord(Data[2]) shl 16)) shr 5;
  if (N < 1) or (N > Size-10) then Invalid;
  Header.Init(Data+10,N);
  if Header.Read(128) <> 0 then Invalid; { reserved color space }
  Header.Read(128); { clamping hint }
  SegmentEnabled := Header.Read(128) <> 0;
  FillChar(SegmentProb,SizeOf(SegmentProb),255);
  if SegmentEnabled then
  begin
    UpdateMap := Header.Read(128) <> 0;
    if Header.Read(128) <> 0 then
    begin
      SegmentAbsolute := Header.Read(128) <> 0;
      for I := 0 to 3 do if Header.Read(128) <> 0 then SegmentQ[I] := Header.Signed(7);
      for I := 0 to 3 do if Header.Read(128) <> 0 then SegmentFilter[I] := Header.Signed(6);
    end;
    if UpdateMap then for I := 0 to 2 do
      if Header.Read(128) <> 0 then SegmentProb[I] := Header.Literal(8);
  end;
  Simple := Header.Read(128) <> 0;
  FilterLevel := Header.Literal(6); Sharpness := Header.Literal(3);
  AdjustFilter := Header.Read(128) <> 0;
  if AdjustFilter and (Header.Read(128) <> 0) then
  begin
    for I := 0 to 3 do if Header.Read(128) <> 0 then RefDelta[I] := Header.Signed(6);
    for I := 0 to 3 do if Header.Read(128) <> 0 then ModeDelta[I] := Header.Signed(6);
  end;
  Parts := 1 shl Header.Literal(2);
  Start := N+10; Offset := Start+3*(Parts-1);
  if Offset > Size then Invalid;
  for I := 0 to Parts-1 do
  begin
    if I = Parts-1 then PartSize := Size-Offset
    else
    begin
      J := Start+3*I;
      PartSize := Data[J] or (Data[J+1] shl 8) or (Data[J+2] shl 16);
    end;
    if PartSize > Size-Offset then Invalid;
    { Empty unused token partitions are legal on very short images. }
    if PartSize > 0 then Tokens[I].Init(Data+Offset, PartSize)
    else begin Tokens[I].Size := 0; Tokens[I].Position := 2; Tokens[I].Range := 255; Tokens[I].Remaining := 8 end;
    Inc(Offset,PartSize);
  end;
  Quant := Header.Literal(7);
  for I := 0 to 4 do if Header.Read(128) <> 0 then QuantDelta[I] := Header.Signed(4);
  Header.Read(128); { refresh entropy probabilities; no subsequent video frames }
  Prob := DefaultProb;
  for I := 0 to High(Prob) do
    if Header.Read(UpdateProb[I]) <> 0 then Prob[I] := Header.Literal(8);
  SkipEnabled := Header.Read(128) <> 0;
  if SkipEnabled then SkipProb := Header.Literal(8);
end;

function TDecoder.Coefficients(var Reader: TBoolReader; Kind, Context, DC, AC: Integer;
  out Block: TBlock): Integer;
var I, Node, Token, V, J, Cat, Quantizer: Integer; P: PByte; WasZero: Boolean;
begin
  FillChar(Block,SizeOf(Block),0); Result := 0;
  I := Ord(Kind = 0); WasZero := False;
  while I < 16 do
  begin
    P := @Prob[((Kind*8+Band[I])*3+Context)*11];
    if WasZero then Node := 2 else Node := 0;
    repeat Node := CoeffTree[Node+Reader.Read(P[Node shr 1])] until Node <= 0;
    Token := -Node;
    if Token = 11 then Exit;
    V := Token;
    if Token >= 5 then
    begin
      Cat := Token-5; V := 0;
      for J := 0 to ExtraBits[Cat]-1 do V := V*2+Reader.Read(ExtraProb[Cat,J]);
      Inc(V,ExtraBase[Cat]);
    end;
    WasZero := V = 0; Context := Min(V,2);
    if V <> 0 then
    begin
      Result := 1;
      if Reader.Read(128) <> 0 then V := -V;
      if I = 0 then Quantizer := DC else Quantizer := AC;
      Block[Zigzag[I]] := V*Quantizer;
    end;
    Inc(I);
  end;
end;

procedure Inverse(var B: TBlock; Walsh: Boolean);
var Temp: TBlock; Pass, I, A,C,D,E, X0,X1,X2,X3, J, Step, Base: Integer;
begin
  for Pass := 0 to 1 do
  begin
    if Pass = 0 then Step := 4 else Step := 1;
    for I := 0 to 3 do
    begin
      if Pass = 0 then Base := I else Base := I*4;
      X0 := B[Base]; X1 := B[Base+Step]; X2 := B[Base+2*Step]; X3 := B[Base+3*Step];
      if Walsh then
      begin A := X0+X3; C := X1+X2; D := X1-X2; E := X0-X3 end
      else
      begin
        A := X0+X2; E := X0-X2;
        D := Mul16(X1,35468)-(X3+Mul16(X3,20091));
        C := X1+Mul16(X1,20091)+Mul16(X3,35468);
      end;
      Temp[Base] := A+C; Temp[Base+Step] := E+D;
      Temp[Base+2*Step] := A-C; Temp[Base+3*Step] := E-D;
      if not Walsh then
      begin Temp[Base+2*Step] := E-D; Temp[Base+3*Step] := A-C end;
    end;
    B := Temp;
  end;
  for J := 0 to 15 do B[J] := ASR(B[J]+4-Ord(Walsh),3);
end;

procedure AddBlock(var Plane: TPlane; X,Y: Integer; var B: TBlock);
var R,C,I,DC: Integer; P: PByte; OnlyDC: Boolean;
begin
  OnlyDC := True;
  for I := 1 to 15 do if B[I] <> 0 then begin OnlyDC := False; Break end;
  if OnlyDC then
  begin
    DC := ASR(B[0]+4,3);
    if DC = 0 then Exit;
    for R := 0 to 3 do
    begin P := Plane.At(X,Y+R); for C := 0 to 3 do P[C] := Clip(Integer(P[C])+DC) end;
    Exit;
  end;
  Inverse(B,False);
  for R := 0 to 3 do
  begin P := Plane.At(X,Y+R); for C := 0 to 3 do P[C] := Clip(P[C]+B[R*4+C]) end;
end;

procedure PredictLarge(var Plane: TPlane; X,Y,N,Mode: Integer);
var R,C,DC,Count: Integer; Top, Left, P: PByte;
begin
  Top := Plane.At(X,Y-1); Left := Plane.At(X-1,Y);
  DC := 0; Count := 0;
  if Y > 0 then begin for C := 0 to N-1 do Inc(DC,Top[C]); Inc(Count,N) end;
  if X > 0 then begin for R := 0 to N-1 do Inc(DC,Left[R*Plane.Stride]); Inc(Count,N) end;
  if Count = 0 then DC := 128 else DC := (DC+Count div 2) div Count;
  for R := 0 to N-1 do
  begin
    P := Plane.At(X,Y+R);
    for C := 0 to N-1 do
      case Mode of
        0: P[C] := DC;
        1: P[C] := Top[C];
        2: P[C] := Left[R*Plane.Stride];
        3: P[C] := Clip(Integer(Left[R*Plane.Stride])+Integer(Top[C])-Integer(Top[-1]));
      end;
  end;
end;

procedure PredictSmall(var Plane: TPlane; X,Y,MBX,MBY,Mode: Integer);
var Top: array[-1..8] of Integer; Left: array[-1..4] of Integer;
    Edge: array[0..8] of Integer;
    R,C,I,V,N,DC: Integer; P: PByte;
  function Avg3(A,B,C: Integer): Integer; inline;
  begin Result := (A+2*B+C+2) shr 2 end;
  function Edge3(Index: Integer): Integer;
  begin Result := Avg3(Edge[Index-1],Edge[Index],Edge[Index+1]) end;
begin
  for I := -1 to 3 do Top[I] := Plane.At(X+I,Y-1)^;
  for I := 4 to 7 do
    if X-MBX = 12 then
    begin
      if MBY = 0 then Top[I] := 127
      else if MBX+16 = Plane.Width then Top[I] := Plane.At(MBX+15,MBY-1)^
      else Top[I] := Plane.At(X+I,MBY-1)^;
    end
    else Top[I] := Plane.At(X+I,Y-1)^;
  Top[8] := Top[7];
  for I := -1 to 3 do Left[I] := Plane.At(X-1,Y+I)^;
  Left[4] := Left[3];
  for I := 0 to 3 do begin Edge[I] := Left[3-I]; Edge[I+5] := Top[I] end;
  Edge[4] := Top[-1]; DC := 4;
  for I := 0 to 3 do Inc(DC,Top[I]+Left[I]); DC := DC shr 3;
  for R := 0 to 3 do
  begin
    P := Plane.At(X,Y+R);
    for C := 0 to 3 do
    begin
      case Mode of
        0: V := DC;
        1: V := Clip(Left[R]+Top[C]-Top[-1]);
        2: V := Avg3(Top[C-1],Top[C],Top[C+1]);
        3: V := Avg3(Left[R-1],Left[R],Left[R+1]);
        4: begin N := R+C; V := Avg3(Top[N],Top[N+1],Top[N+2]) end;
        5: V := Edge3(4+C-R);
        6: begin
          N := 2*C-R;
          if N < -1 then V := Edge3(5+N)
          else if Odd(N) then V := Edge3(4+(N+1) div 2)
          else V := (Edge[4+N div 2]+Edge[5+N div 2]+1) shr 1;
        end;
        7: begin
          N := C+R div 2;
          if (C = 3) and (R >= 2) then V := Avg3(Top[R+2],Top[R+3],Top[R+4])
          else if Odd(R) then V := Avg3(Top[N],Top[N+1],Top[N+2])
          else V := (Top[N]+Top[N+1]+1) shr 1;
        end;
        8: begin
          N := 2*R-C;
          if N < -1 then V := Edge3(3-N)
          else if Odd(N) then V := Edge3(4-(N+1) div 2)
          else V := (Edge[3-N div 2]+Edge[4-N div 2]+1) shr 1;
        end;
        9: begin
          N := R+C div 2;
          if N >= 3 then V := Left[3]
          else if Odd(C) then V := Avg3(Left[N],Left[N+1],Left[N+2])
          else V := (Left[N]+Left[N+1]+1) shr 1;
        end;
      else V := 0 end;
      P[C] := V;
    end;
  end;
end;

procedure TDecoder.Reconstruct;
const ModeContext: array[0..3] of Byte = (0,2,3,1);
var TopY,TopU,TopV,TopY2,TopMode: TBytes;
    LeftY: array[0..3] of Byte; LeftU,LeftV: array[0..1] of Byte;
    LeftMode: array[0..3] of Byte;
    LeftY2: Byte;
    Modes: array[0..15] of Byte;
    MX,MY,X,Y,I,J,Seg,YMode,UVMode,Q,YDC,YAC,Y2DC,Y2AC,UVDC,UVAC: Integer;
    Context,Kind,NZ,AnyNZ,Level,Part: Integer;
    Skip: Boolean; B,Y2: TBlock;
    Plane: ^TPlane;
    Top: ^TBytes; Left: PByte;
begin
  YPlane.Init(MBWidth*16,MBHeight*16);
  UPlane.Init(MBWidth*8,MBHeight*8); VPlane.Init(MBWidth*8,MBHeight*8);
  for I := 0 to 2 do
  begin
    case I of 0: Plane := @YPlane; 1: Plane := @UPlane; else Plane := @VPlane end;
    FillChar(Plane^.At(-1,-1)^,Plane^.Width+9,127);
    for Y := 0 to Plane^.Height-1 do Plane^.At(-1,Y)^ := 129;
  end;
  SetLength(TopY,MBWidth*4); SetLength(TopU,MBWidth*2); SetLength(TopV,MBWidth*2);
  SetLength(TopY2,MBWidth); SetLength(TopMode,MBWidth*4); SetLength(Blocks,MBWidth*MBHeight);
  for MY := 0 to MBHeight-1 do
  begin
    FillChar(LeftY,SizeOf(LeftY),0); FillChar(LeftU,SizeOf(LeftU),0);
    FillChar(LeftV,SizeOf(LeftV),0); FillChar(LeftMode,SizeOf(LeftMode),0); LeftY2 := 0;
    Part := MY and (Parts-1);
    for MX := 0 to MBWidth-1 do
    begin
      { only an intra-4x4 macroblock fills these, and only one reads them,
        but a zeroed block is the safe answer either way }
      FillChar(Modes,SizeOf(Modes),0);
      Seg := 0;
      if UpdateMap then
      begin
        I := Header.Read(SegmentProb[0]); Seg := I*2+Header.Read(SegmentProb[1+I]);
      end;
      Skip := SkipEnabled and (Header.Read(SkipProb) <> 0);
      if Header.Read(145) = 0 then YMode := 4
      else if Header.Read(156) = 0 then YMode := Header.Read(163)
      else YMode := 2+Header.Read(128);
      if YMode = 4 then
        for Y := 0 to 3 do for X := 0 to 3 do
        begin
          I := Header.Tree(ModeTree,@ModeProb[(TopMode[MX*4+X]*10+LeftMode[Y])*9]);
          Modes[Y*4+X] := I; TopMode[MX*4+X] := I; LeftMode[Y] := I;
        end
      else for I := 0 to 3 do
      begin TopMode[MX*4+I] := ModeContext[YMode]; LeftMode[I] := ModeContext[YMode] end;
      if Header.Read(142) = 0 then UVMode := 0
      else if Header.Read(114) = 0 then UVMode := 1 else UVMode := 2+Header.Read(183);
      Q := Quant;
      if SegmentEnabled then
        if SegmentAbsolute then Q := SegmentQ[Seg] else Inc(Q,SegmentQ[Seg]);
      Q := EnsureRange(Q,0,127);
      YAC := ACQuant[Q]; YDC := DCQuant[EnsureRange(Q+QuantDelta[0],0,127)];
      Y2DC := 2*DCQuant[EnsureRange(Q+QuantDelta[1],0,127)];
      Y2AC := Max(8,(ACQuant[EnsureRange(Q+QuantDelta[2],0,127)]*155) div 100);
      UVDC := Min(132,DCQuant[EnsureRange(Q+QuantDelta[3],0,127)]);
      UVAC := ACQuant[EnsureRange(Q+QuantDelta[4],0,127)];
      AnyNZ := 0; FillChar(Y2,SizeOf(Y2),0);
      if YMode <> 4 then
      begin
        NZ := 0;
        if not Skip then NZ := Coefficients(Tokens[Part],1,TopY2[MX]+LeftY2,Y2DC,Y2AC,Y2);
        TopY2[MX] := NZ; LeftY2 := NZ; AnyNZ := NZ;
        Inverse(Y2,True);
        PredictLarge(YPlane,MX*16,MY*16,16,YMode);
      end;
      for Y := 0 to 3 do for X := 0 to 3 do
      begin
        if YMode = 4 then
        begin Kind := 3; PredictSmall(YPlane,MX*16+X*4,MY*16+Y*4,MX*16,MY*16,Modes[Y*4+X]) end
        else Kind := 0;
        NZ := 0; FillChar(B,SizeOf(B),0);
        Context := TopY[MX*4+X]+LeftY[Y];
        if not Skip then NZ := Coefficients(Tokens[Part],Kind,Context,YDC,YAC,B);
        TopY[MX*4+X] := NZ; LeftY[Y] := NZ; AnyNZ := AnyNZ or NZ;
        if YMode <> 4 then B[0] := Y2[Y*4+X];
        AddBlock(YPlane,MX*16+X*4,MY*16+Y*4,B);
      end;
      for I := 0 to 1 do
      begin
        if I = 0 then begin Plane := @UPlane; Top := @TopU; Left := @LeftU[0] end
        else begin Plane := @VPlane; Top := @TopV; Left := @LeftV[0] end;
        PredictLarge(Plane^,MX*8,MY*8,8,UVMode);
        for Y := 0 to 1 do for X := 0 to 1 do
        begin
          NZ := 0; FillChar(B,SizeOf(B),0);
          if not Skip then NZ := Coefficients(Tokens[Part],2,Top^[MX*2+X]+Left[Y],UVDC,UVAC,B);
          Top^[MX*2+X] := NZ; Left[Y] := NZ; AnyNZ := AnyNZ or NZ;
          AddBlock(Plane^,MX*8+X*4,MY*8+Y*4,B);
        end;
      end;
      Level := FilterLevel;
      if SegmentEnabled then
        if SegmentAbsolute then Level := SegmentFilter[Seg] else Inc(Level,SegmentFilter[Seg]);
      if AdjustFilter then
      begin Inc(Level,RefDelta[0]); if YMode = 4 then Inc(Level,ModeDelta[0]) end;
      J := MY*MBWidth+MX;
      Blocks[J].Level := EnsureRange(Level,0,63);
      Blocks[J].Inner := (YMode = 4) or (AnyNZ <> 0);
    end;
  end;
end;

procedure FilterEdge(P: PByte; Along, Across, Count, Interior, Limit, HEV: Integer;
  Simple, MacroEdge: Boolean);
var I,J,W,A,B: Integer; V: array[-4..3] of Integer; HighVariance, Allowed: Boolean;
begin
  for I := 0 to Count-1 do
  begin
    for J := -4 to 3 do V[J] := P[J*Across];
    Allowed := 2*Abs(V[-1]-V[0])+Abs(V[-2]-V[1]) div 2 <= Limit;
    if not Simple then
      for J := 1 to 3 do
        Allowed := Allowed and (Abs(V[-J-1]-V[-J]) <= Interior) and
          (Abs(V[J]-V[J-1]) <= Interior);
    if Allowed then
    begin
      HighVariance := Simple or (Abs(V[-2]-V[-1]) > HEV) or (Abs(V[1]-V[0]) > HEV);
      if MacroEdge and not HighVariance then
      begin
        W := SignedClip(SignedClip(V[-2]-V[1])+3*(V[0]-V[-1]));
        for J := 0 to 2 do
        begin
          A := ASR((27-9*J)*W+63,7);
          P[J*Across] := Clip(V[J]-A); P[(-1-J)*Across] := Clip(V[-1-J]+A);
        end;
      end
      else
      begin
        W := 0; if HighVariance then W := SignedClip(V[-2]-V[1]);
        W := SignedClip(W+3*(V[0]-V[-1]));
        A := ASR(SignedClip(W+4),3); B := ASR(SignedClip(W+3),3);
        P[0] := Clip(V[0]-A); P[-Across] := Clip(V[-1]+B);
        if not HighVariance then
        begin
          A := ASR(A+1,1);
          P[Across] := Clip(V[1]-A); P[-2*Across] := Clip(V[-2]+A);
        end;
      end;
    end;
    Inc(P,Along);
  end;
end;

procedure TDecoder.Filter;
var MX,MY,I,N,X,Y,Level,Interior,HEV,Limit,Edge: Integer;
    Plane: ^TPlane; Inner: Boolean;
begin
  for MY := 0 to MBHeight-1 do for MX := 0 to MBWidth-1 do
  begin
    Level := Blocks[MY*MBWidth+MX].Level;
    if Level = 0 then Continue;
    Inner := Blocks[MY*MBWidth+MX].Inner;
    Interior := Level;
    if Sharpness > 0 then Interior := Min(9-Sharpness,Interior shr (1+Ord(Sharpness > 4)));
    Interior := Max(1,Interior); HEV := Ord(Level >= 15)+Ord(Level >= 40);
    Limit := 2*Level+Interior;
    for I := 0 to 2 do
    begin
      if Simple and (I > 0) then Break;
      case I of 0: begin Plane := @YPlane; N := 16 end;
        1: begin Plane := @UPlane; N := 8 end;
        else begin Plane := @VPlane; N := 8 end end;
      X := MX*N; Y := MY*N;
      if MX > 0 then FilterEdge(Plane^.At(X,Y),Plane^.Stride,1,N,Interior,Limit+4,HEV,Simple,True);
      if Inner then for Edge := 1 to N div 4-1 do
        FilterEdge(Plane^.At(X+Edge*4,Y),Plane^.Stride,1,N,Interior,Limit,HEV,Simple,False);
      if MY > 0 then FilterEdge(Plane^.At(X,Y),1,Plane^.Stride,N,Interior,Limit+4,HEV,Simple,True);
      if Inner then for Edge := 1 to N div 4-1 do
        FilterEdge(Plane^.At(X,Y+Edge*4),1,Plane^.Stride,N,Interior,Limit,HEV,Simple,False);
    end;
  end;
end;

function RGBPixel(Y,U,V: Integer): LongWord; inline;
var Luma: Integer;
begin
  Luma := 19077*(Y-16)+8192; Dec(U,128); Dec(V,128);
  Result := $FF000000 or (LongWord(Clip(ASR(Luma+26149*V,14))) shl 16) or
    (LongWord(Clip(ASR(Luma-6419*U-13320*V,14))) shl 8) or
    LongWord(Clip(ASR(Luma+33050*U,14)));
end;

function TDecoder.Pixels(W,H: Integer): TInkWebPPixels;
var X,Y,I,CW,CH,TopRow,BottomRow,Weight,U,V: Integer;
    VerticalU,VerticalV: array of Integer;
    UT,UB,VT,VB,Luma: PByte;
    Dest: PLongWord;
begin
  Result := nil; SetLength(Result,W*H); CW := (W+1) div 2; CH := (H+1) div 2;
  SetLength(VerticalU,CW); SetLength(VerticalV,CW);
  for Y := 0 to H-1 do
  begin
    TopRow := Max(0,(Y-1) div 2); BottomRow := Min(CH-1,(Y+1) div 2);
    if Odd(Y) then Weight := 3 else Weight := 1;
    UT := UPlane.At(0,TopRow); UB := UPlane.At(0,BottomRow);
    VT := VPlane.At(0,TopRow); VB := VPlane.At(0,BottomRow);
    { Separable 3:1 chroma interpolation, retaining fractional precision.
      Each chroma sample is loaded twice per output row, not per pixel. }
    for I := 0 to CW-1 do
    begin
      VerticalU[I] := UT[I]*Weight+UB[I]*(4-Weight);
      VerticalV[I] := VT[I]*Weight+VB[I]*(4-Weight);
    end;
    Luma := YPlane.At(0,Y); Dest := @Result[Y*W];
    Dest[0] := RGBPixel(Luma[0],(VerticalU[0]+2) shr 2,(VerticalV[0]+2) shr 2);
    X := 1;
    for I := 0 to CW-2 do
    begin
      U := (3*VerticalU[I]+VerticalU[I+1]+8) shr 4;
      V := (3*VerticalV[I]+VerticalV[I+1]+8) shr 4;
      Dest[X] := RGBPixel(Luma[X],U,V); Inc(X);
      U := (VerticalU[I]+3*VerticalU[I+1]+8) shr 4;
      V := (VerticalV[I]+3*VerticalV[I+1]+8) shr 4;
      Dest[X] := RGBPixel(Luma[X],U,V); Inc(X);
    end;
    if X < W then Dest[X] := RGBPixel(Luma[X],
      (VerticalU[CW-1]+2) shr 2,(VerticalV[CW-1]+2) shr 2);
  end;
end;

function InkDecodeVP8(Data: PByte; Size, Width, Height: Integer;
  out Pixels: TInkWebPPixels): Boolean;
var Decoder: TDecoder; W,H: Integer;
begin
  Result := False; Pixels := nil;
  if (Data = nil) or (Size < 10) or (Width <= 0) or (Height <= 0) or
    (Int64(Width)*Height > 16*1024*1024) then Exit;
  if (Data[0] and 1 <> 0) or ((Data[0] shr 1) and 7 > 3) or
    (Data[0] and 16 = 0) or (Data[3] <> $9D) or (Data[4] <> 1) or (Data[5] <> $2A) then Exit;
  W := (Data[6] or (Data[7] shl 8)) and $3FFF;
  H := (Data[8] or (Data[9] shl 8)) and $3FFF;
  if (W <> Width) or (H <> Height) then Exit;
  Decoder := TDecoder.Create;
  try
    try
      Decoder.MBWidth := (W+15) div 16; Decoder.MBHeight := (H+15) div 16;
      Decoder.ReadHeader(Data,Size);
      Decoder.Reconstruct;
      Decoder.Filter;
      Pixels := Decoder.Pixels(W,H);
      Result := True;
    except on E: EInvalidVP8 do Pixels := nil end;
  finally Decoder.Free end;
end;
end.
