{ WebP container reader and pure Pascal animation compositor.
  Frames are decoded on demand; only the current canvas is retained.
  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkWebP;

{$mode objfpc}{$H+}
{$pointermath on}

interface

uses
  Classes, SysUtils, Graphics, Types, Math, GraphType, InkWebPLossless, InkWebPVP8;

type
  { what kind of image the file holds }
  TInkWebPKind = (wkNone, wkLossy, wkLossless, wkExtended);

  { how the canvas is cleared before a frame }
  TInkWebPDisposal = (wdNone, wdBackground);

  TInkWebPFrame = record
    { where in the file the frame's own image data starts, and how long it
      is: what a decoder will be handed }
    Offset, Size: Integer;
    AlphaOffset, AlphaSize: Integer;
    { the frame's place on the canvas, and its size }
    X, Y, Width, Height: Integer;
    { how long it is shown, in milliseconds }
    Duration: Integer;
    Disposal: TInkWebPDisposal;
    { whether the frame is blended onto what is already there }
    Blend: Boolean;
    { lossy, lossless, or - for a frame whose payload is an ALPH plus VP8 -
      lossy with alpha }
    Kind: TInkWebPKind;
    HasAlpha: Boolean;
  end;

  TInkWebP = class
  private
    FData: RawByteString;
    FFrames: array of TInkWebPFrame;
    FBitmap: TBitmap;
    FIndex, FCompletedLoops: Integer;
    FCanvas: TInkWebPPixels;
    FBackgroundAlpha: Byte;
    FFinished: Boolean;
    FDue: QWord;
    FValid, FAnimated, FDecoded: Boolean;
    FAnimationFlag, FHasAnimationHeader: Boolean;
    FWidth, FHeight, FLoops: Integer;
    FKind: TInkWebPKind;
    FBackground: TColor;
    function DrawFrame(Index: Integer): Boolean;
    procedure PublishBitmap;
    function ByteAt(A: Integer): Byte;
    function Read16(A: Integer): Integer;
    function Read24(A: Integer): Integer;
    function Read32(A: Integer): Integer;
    procedure ReadChunks(AStart, AEnd: Integer);
    procedure ReadAnimationFrame(AStart, ASize: Integer);
  public
    constructor Create(Stream: TStream);
    destructor Destroy; override;
    { Random access replays preceding frames to preserve compositing.
      Sequential access decodes only one frame. UI thread only. }
    function DecodeFrame(Index: Integer): Boolean;
    { the next frame, if its time has come; True when the picture changed }
    function Advance: Boolean; overload;
    function Advance(ANow: QWord): Boolean; overload;
    procedure Restart;
    property Finished: Boolean read FFinished;
    property FrameIndex: Integer read FIndex;
    function FrameCount: Integer;
    function Frame(Index: Integer): TInkWebPFrame;
    { a WebP at all, and readable as far as its structure }
    property Valid: Boolean read FValid;
    { more than one frame }
    property Animated: Boolean read FAnimated;
    { whether Bitmap holds real pixels - False if decoding failed }
    property Decoded: Boolean read FDecoded;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    { 0 means for ever }
    property Loops: Integer read FLoops;
    property Kind: TInkWebPKind read FKind;
    property Background: TColor read FBackground;
    property BackgroundAlpha: Byte read FBackgroundAlpha;
    property Bitmap: TBitmap read FBitmap;
  end;

{ Does this look like a WebP?  Cheap enough to call on any stream before
  deciding what to do with it: the first twelve bytes are RIFF....WEBP. }
function InkIsWebP(const AData: RawByteString): Boolean;

implementation

const
  MaxInputBytes = 256 * 1024 * 1024;
  MaxCanvasPixels = 16 * 1024 * 1024;

function InkIsWebP(const AData: RawByteString): Boolean;
begin
  Result := (Length(AData) >= 12) and (Copy(AData,1,4) = 'RIFF') and
    (Copy(AData,9,4) = 'WEBP');
end;

constructor TInkWebP.Create(Stream: TStream);
var Size: Integer;
begin
  inherited Create;
  FBitmap := TBitmap.Create;
  FIndex := -1; FDue := 0; FLoops := 0; FKind := wkNone;
  FBackground := clNone;
  if (Stream.Size < 12) or (Stream.Size > MaxInputBytes) then Exit;
  Stream.Position := 0;
  SetLength(FData, Stream.Size);
  if Length(FData) > 0 then Stream.ReadBuffer(FData[1], Length(FData));
  if not InkIsWebP(FData) then Exit;
  { Require the complete declared RIFF body; ignore trailing file data. }
  Size := Read32(5);
  if (Size < 4) or (Size > Length(FData)-8) then Exit;
  Inc(Size, 8);
  SetLength(FData, Size);
  FValid := True;
  ReadChunks(13, Size);
  if (FWidth <= 0) or (FHeight <= 0) or (FrameCount = 0) or
    (QWord(FWidth)*QWord(FHeight) > MaxCanvasPixels) then FValid := False;
  FAnimated := Length(FFrames) > 1;
  if FValid then DecodeFrame(0);
end;

destructor TInkWebP.Destroy;
begin
  FBitmap.Free;
  inherited Destroy;
end;

function TInkWebP.ByteAt(A: Integer): Byte;
begin
  if (A < 1) or (A > Length(FData)) then Exit(0);
  Result := Ord(FData[A]);
end;

function TInkWebP.Read16(A: Integer): Integer;
begin Result := ByteAt(A) or (ByteAt(A+1) shl 8) end;

function TInkWebP.Read24(A: Integer): Integer;
begin Result := ByteAt(A) or (ByteAt(A+1) shl 8) or (ByteAt(A+2) shl 16) end;

function TInkWebP.Read32(A: Integer): Integer;
begin
  Result := ByteAt(A) or (ByteAt(A+1) shl 8) or (ByteAt(A+2) shl 16) or
    (ByteAt(A+3) shl 24);
end;

{ Walks the RIFF chunks between AStart and AEnd.  Every chunk is a
  four-character name, a 32-bit size, the payload, and a pad byte when the
  size is odd. }
procedure TInkWebP.ReadChunks(AStart, AEnd: Integer);
var P, Size, N, AlphaOffset, AlphaSize: Integer; Name: string;
begin
  P := AStart; AlphaOffset := 0; AlphaSize := 0;
  while P <= AEnd - 7 do
  begin
    Name := Copy(FData, P, 4);
    Size := Read32(P+4);
    if (Size < 0) or (Size > AEnd-P-7) or
      ((Size and 1) > AEnd-P-7-Size) then
    begin FValid := False; Exit end;
    if ((Name = 'VP8X') and (Size <> 10)) or
      ((Name = 'VP8 ') and (Size < 10)) or
      ((Name = 'VP8L') and (Size < 5)) or
      ((Name = 'ANIM') and (Size <> 6)) or
      ((Name = 'ANMF') and (Size < 16)) then
    begin FValid := False; Exit end;
    if Name = 'VP8X' then
    begin
      { the extended header: flags, then canvas width and height as
        one-less, 24 bits each }
      if (P <> 13) or (FKind <> wkNone) then begin FValid := False; Exit end;
      FAnimationFlag := (ByteAt(P+8) and 2) <> 0;
      FKind := wkExtended;
      FWidth := Read24(P+12) + 1;
      FHeight := Read24(P+15) + 1;
    end
    else if Name = 'ALPH' then
    begin
      if (FKind <> wkExtended) or FAnimationFlag or (FrameCount <> 0) or
        (AlphaSize <> 0) or (Size < 1) then begin FValid := False; Exit end;
      AlphaOffset := P+8; AlphaSize := Size;
    end
    else if Name = 'VP8 ' then
    begin
      if FAnimationFlag or (FrameCount <> 0) then begin FValid := False; Exit end;
      if FKind = wkNone then FKind := wkLossy;
      if FWidth <= 0 then
      begin
        { the lossy keyframe header: a start code, then 14 bits each of
          width and height }
        FWidth := Read16(P+15) and $3FFF;
        FHeight := Read16(P+17) and $3FFF;
      end;
      if Length(FFrames) = 0 then
      begin
        SetLength(FFrames, 1);
        FFrames[0].Offset := P+8; FFrames[0].Size := Size;
        FFrames[0].Width := FWidth; FFrames[0].Height := FHeight;
        FFrames[0].Kind := wkLossy;
        FFrames[0].AlphaOffset := AlphaOffset; FFrames[0].AlphaSize := AlphaSize;
        FFrames[0].HasAlpha := AlphaSize > 0;
      end;
    end
    else if Name = 'VP8L' then
    begin
      if FAnimationFlag or (FrameCount <> 0) or (AlphaSize <> 0) then
      begin FValid := False; Exit end;
      if FKind = wkNone then FKind := wkLossless;
      if FWidth <= 0 then
      begin
        { lossless: a signature byte, then 14 bits of width-1 and 14 of
          height-1, packed little-endian }
        N := Read32(P+9);
        FWidth := (N and $3FFF) + 1;
        FHeight := ((N shr 14) and $3FFF) + 1;
      end;
      if Length(FFrames) = 0 then
      begin
        SetLength(FFrames, 1);
        FFrames[0].Offset := P+8; FFrames[0].Size := Size;
        FFrames[0].Width := FWidth; FFrames[0].Height := FHeight;
        FFrames[0].Kind := wkLossless;
        FFrames[0].HasAlpha := (ByteAt(P+12) and $10) <> 0;
      end;
    end
    else if Name = 'ANIM' then
    begin
      if not FAnimationFlag or FHasAnimationHeader or (FrameCount <> 0) then
      begin FValid := False; Exit end;
      FHasAnimationHeader := True;
      { the background color the canvas is cleared to, and the loop count }
      FBackgroundAlpha := ByteAt(P+11);
      FBackground := RGBToColor(ByteAt(P+10), ByteAt(P+9), ByteAt(P+8));
      FLoops := Read16(P+12);
    end
    else if Name = 'ANMF' then
    begin
      if not FHasAnimationHeader then begin FValid := False; Exit end;
      ReadAnimationFrame(P+8, Size);
    end;
    if not FValid then Exit;
    Inc(P, 8 + Size + (Size and 1));
  end;
  if P <> AEnd+1 then FValid := False;
end;

{ One animation frame: where it goes, how big it is, how long it stays, and
  the sub-chunk holding its pixels. }
procedure TInkWebP.ReadAnimationFrame(AStart, ASize: Integer);
var N, P, Sub, SubSize: Integer; Name: string; F: TInkWebPFrame;
begin
  FillChar(F, SizeOf(F), 0);
  { Positions are doubled; dimensions store the actual size minus one. }
  F.X := Read24(AStart) * 2;
  F.Y := Read24(AStart+3) * 2;
  F.Width := Read24(AStart+6) + 1;
  F.Height := Read24(AStart+9) + 1;
  F.Duration := Read24(AStart+12);
  N := ByteAt(AStart+15);
  if (N and 1) <> 0 then F.Disposal := wdBackground else F.Disposal := wdNone;
  { bit 1 set means "do not blend", so the flag reads the other way round }
  F.Blend := (N and 2) = 0;
  if (F.X > FWidth-F.Width) or (F.Y > FHeight-F.Height) or
    ((N and $FC) <> 0) then begin FValid := False; Exit end;
  { and inside the frame, the chunks that hold its pixels }
  P := AStart + 16;
  while P <= AStart + ASize - 8 do
  begin
    Name := Copy(FData, P, 4);
    SubSize := Read32(P+4);
    if (SubSize < 0) or (SubSize > AStart+ASize-P-8) or
      ((SubSize and 1) > AStart+ASize-P-8-SubSize) then
    begin FValid := False; Exit end;
    if Name = 'ALPH' then
    begin
      if (F.AlphaSize <> 0) or (F.Size <> 0) or (SubSize < 1) then
      begin FValid := False; Exit end;
      F.HasAlpha := True; F.AlphaOffset := P+8; F.AlphaSize := SubSize;
    end
    else if Name = 'VP8 ' then
    begin
      if (F.Size <> 0) or (SubSize < 10) then begin FValid := False; Exit end;
      F.Offset := P+8; F.Size := SubSize; F.Kind := wkLossy;
    end
    else if Name = 'VP8L' then
    begin
      if (F.Size <> 0) or (F.AlphaSize <> 0) or (SubSize < 5) then
      begin FValid := False; Exit end;
      F.Offset := P+8; F.Size := SubSize; F.Kind := wkLossless;
      F.HasAlpha := (ByteAt(P+12) and $10) <> 0;
    end;
    Inc(P, 8 + SubSize + (SubSize and 1));
  end;
  if (P <> AStart+ASize) or (F.Size = 0) then
  begin FValid := False; Exit end;
  Sub := Length(FFrames);
  if Sub >= 65536 then begin FValid := False; Exit end;
  SetLength(FFrames, Sub+1);
  FFrames[Sub] := F;
end;

function TInkWebP.FrameCount: Integer;
begin Result := Length(FFrames) end;

function TInkWebP.Frame(Index: Integer): TInkWebPFrame;
begin
  if (Index < 0) or (Index > High(FFrames)) then FillChar(Result, SizeOf(Result), 0)
  else Result := FFrames[Index];
end;

function BlendPixel(S, D: LongWord): LongWord; inline;
var SA, DA, A, Weight, C, Shift: LongWord;
begin
  SA := S shr 24;
  if SA = 255 then Exit(S);
  if SA = 0 then Exit(D);
  DA := D shr 24;
  { Eight-bit fixed-point source-over, including the alpha channel. }
  Weight := (DA*(256-SA)) shr 8;
  A := SA+Weight;
  Result := A shl 24;
  for Shift := 0 to 2 do
  begin
    C := (((S shr (Shift*8)) and 255)*SA+
      ((D shr (Shift*8)) and 255)*Weight) div A;
    Result := Result or (C shl (Shift*8));
  end;
end;

function DecodeAlpha(Data: PByte; Size, W, H: Integer;
  var Pixels: TInkWebPPixels): Boolean;
var Values: TInkWebPPixels; Alpha: TBytes;
    Compression, Filter, X,Y,I,Prediction,Value: Integer;
begin
  Result := False;
  if Size < 1 then Exit;
  Compression := Data[0] and 3; Filter := (Data[0] shr 2) and 3;
  if Compression > 1 then Exit;
  SetLength(Alpha,W*H);
  if Compression = 0 then
  begin
    if Size-1 <> W*H then Exit;
    Move(Data[1],Alpha[0],Length(Alpha));
  end
  else
  begin
    if not InkDecodeVP8L(Data+1,Size-1,W,H,Values,False) then Exit;
    for I := 0 to High(Alpha) do Alpha[I] := (Values[I] shr 8) and 255;
  end;
  for Y := 0 to H-1 do for X := 0 to W-1 do
  begin
    I := Y*W+X; Prediction := 0;
    if Filter <> 0 then
      if (X = 0) and (Y = 0) then Prediction := 0
      else if Y = 0 then Prediction := Alpha[I-1]
      else if X = 0 then Prediction := Alpha[I-W]
      else case Filter of
        1: Prediction := Alpha[I-1];
        2: Prediction := Alpha[I-W];
        3: Prediction := EnsureRange(Integer(Alpha[I-1])+Integer(Alpha[I-W])-Integer(Alpha[I-W-1]),0,255);
      end;
    Value := (Integer(Alpha[I])+Prediction) and 255; Alpha[I] := Value;
    Pixels[I] := (Pixels[I] and $FFFFFF) or (LongWord(Value) shl 24);
  end;
  Result := True;
end;

function TInkWebP.DrawFrame(Index: Integer): Boolean;
var Pixels: TInkWebPPixels; F, Previous: TInkWebPFrame;
    X, Y, Source, Dest: Integer;
begin
  Result := False; F := FFrames[Index];
  if F.Kind = wkLossless then
  begin
    if not InkDecodeVP8L(PByte(@FData[F.Offset]), F.Size, F.Width, F.Height, Pixels) then Exit;
  end
  else if F.Kind = wkLossy then
  begin
    if not InkDecodeVP8(PByte(@FData[F.Offset]), F.Size, F.Width, F.Height, Pixels) then Exit;
    if (F.AlphaSize > 0) and not DecodeAlpha(PByte(@FData[F.AlphaOffset]),
      F.AlphaSize,F.Width,F.Height,Pixels) then Exit;
  end
  else Exit;
  { Transparent canvas is the application-defined background, like a browser.
    ANIM's suggested background (including alpha) remains available as metadata. }
  if Index > 0 then
  begin
    Previous := FFrames[Index-1];
    if Previous.Disposal = wdBackground then
      for Y := Previous.Y to Previous.Y+Previous.Height-1 do
        FillChar(FCanvas[Y*FWidth+Previous.X], Previous.Width*4, 0);
  end;
  for Y := 0 to F.Height-1 do
  begin
    Source := Y*F.Width; Dest := (Y+F.Y)*FWidth+F.X;
    if not F.Blend then Move(Pixels[Source], FCanvas[Dest], F.Width*4)
    else for X := 0 to F.Width-1 do
      FCanvas[Dest+X] := BlendPixel(Pixels[Source+X], FCanvas[Dest+X]);
  end;
  Result := True;
end;

procedure TInkWebP.PublishBitmap;
var Raw: TRawImage;
begin
  Raw.Init;
  Raw.Description.Init_BPP32_B8G8R8A8_BIO_TTB(FWidth, FHeight);
  Raw.Data := PByte(@FCanvas[0]);
  Raw.DataSize := SizeUInt(FWidth)*SizeUInt(FHeight)*4;
  FBitmap.LoadFromRawImage(Raw, False);
end;

function TInkWebP.DecodeFrame(Index: Integer): Boolean;
var I: Integer;
begin
  Result := False;
  if not FValid or (Index < 0) or (Index >= FrameCount) then Exit;
  if FDecoded and (Index = FIndex) then Exit(True);
  if (Index <= FIndex) or not FDecoded then
  begin
    FIndex := -1;
    SetLength(FCanvas, FWidth*FHeight);
    FillChar(FCanvas[0], Length(FCanvas)*SizeOf(LongWord), 0);
  end;
  for I := FIndex+1 to Index do
    if not DrawFrame(I) then
    begin FFinished := True; FIndex := -1; Exit end;
  PublishBitmap;
  FIndex := Index; FDecoded := True;
  Result := True;
end;

procedure TInkWebP.Restart;
begin
  FDue := 0; FCompletedLoops := 0; FFinished := False; FIndex := -1;
  FDecoded := False;
  DecodeFrame(0);
end;

function TInkWebP.Advance: Boolean;
begin
  Result := Advance(GetTickCount64);
end;

function TInkWebP.Advance(ANow: QWord): Boolean;
var Next, Delay: Integer;
begin
  Result := False;
  if not FAnimated or not FDecoded or FFinished then Exit;
  Delay := FFrames[FIndex].Duration;
  if Delay <= 0 then Delay := 100;
  if FDue = 0 then begin FDue := ANow + QWord(Delay); Exit end;
  if ANow < FDue then Exit;
  Next := FIndex+1;
  if Next = FrameCount then
  begin
    Inc(FCompletedLoops);
    if (FLoops > 0) and (FCompletedLoops >= FLoops) then
    begin FFinished := True; Exit end;
    Next := 0;
  end;
  Result := DecodeFrame(Next);
  if not Result then Exit;
  Delay := FFrames[FIndex].Duration;
  if Delay <= 0 then Delay := 100;
  { Preserve deadlines during normal playback; bound work to one frame per
    tick after stalls/offscreen periods instead of blocking the UI to catch up. }
  Inc(FDue, QWord(Delay));
  if FDue <= ANow then FDue := ANow + QWord(Delay);
end;

end.
