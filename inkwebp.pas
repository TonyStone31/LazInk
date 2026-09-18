{ InkWebP - reading a WebP file's structure, so LazInk can show one.

  **This is a skeleton with a hole in the middle.**  Everything about the
  *container* is here and works: RIFF chunks, the canvas size, whether the
  file is lossy (VP8 ), lossless (VP8L) or extended (VP8X), whether it is
  animated, and every frame's position, size, duration, disposal and blend.
  What is not here is the **pixel decoder**: DecodeFrame always returns
  False, and that is the piece to write or bind.

  Why bother.  A page that teaches a program is mostly pictures of it
  moving, and GIF is a 1987 format: 256 colors a frame and next to no
  compression between frames.  One of Heckers Sketch's own recordings is
  1,221 KB as GIF and 452 KB as animated WebP - see ROADMAP.md section 4,
  item 17, which also sets out the two ways to fill the hole:

    * bind libwebp at run time - a small job, a well-tested decoder, and a
      shared library to find;
    * write the decoder in Pascal - no dependency at all, and real work:
      lossless (VP8L) alone is a far smaller job than lossy (VP8) and would
      already cover screenshots.

  Whichever way it goes, **GIF stays**: pages in the wild use it, and a
  WebP that cannot be decoded must fall back rather than show a hole.
  TInkWebP.Decoded says whether there are pixels to draw; until a decoder
  is plugged in it is False and a caller shows the alt text.

  The container side is tested in tests/render_tests.pas (WebPChecks): the
  test builds WebP files byte by byte - a still and an animation - and
  checks what this unit reads back from them.  Add to those as the decoder
  grows.

  SPDX-License-Identifier: 0BSD
  Copyright (c) 2026 LazInk contributors }
unit InkWebP;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Math;

type
  { what kind of image the file holds }
  TInkWebPKind = (wkNone, wkLossy, wkLossless, wkExtended);

  { how the canvas is cleared before a frame }
  TInkWebPDisposal = (wdNone, wdBackground);

  TInkWebPFrame = record
    { where in the file the frame's own image data starts, and how long it
      is: what a decoder will be handed }
    Offset, Size: Integer;
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

  { A WebP file, read as far as its structure goes.

    Create it with a stream; Valid says whether it was a WebP at all.  Then
    Width, Height, Animated, FrameCount and Frame() describe it, and
    Advance / Bitmap play it, exactly as TInkGIF does - once DecodeFrame
    knows how to fill a bitmap. }
  TInkWebP = class
  private
    FData: RawByteString;
    FFrames: array of TInkWebPFrame;
    FBitmap: TBitmap;
    FIndex: Integer;
    FDue: QWord;
    FValid, FAnimated, FDecoded: Boolean;
    FWidth, FHeight, FLoops: Integer;
    FKind: TInkWebPKind;
    FBackground: TColor;
    function ByteAt(A: Integer): Byte;
    function Read16(A: Integer): Integer;
    function Read24(A: Integer): Integer;
    function Read32(A: Integer): Integer;
    procedure ReadChunks(AStart, AEnd: Integer);
    procedure ReadAnimationFrame(AStart, ASize: Integer);
  public
    constructor Create(Stream: TStream);
    destructor Destroy; override;
    { Draws frame Index into Bitmap.  **Not implemented**: it returns False,
      which is what makes this a skeleton.  A decoder plugged in here - a
      libwebp binding, or Pascal - is the whole job, and nothing else in
      LazInk has to change when it lands. }
    function DecodeFrame(Index: Integer): Boolean;
    { the next frame, if its time has come; True when the picture changed }
    function Advance: Boolean;
    function FrameCount: Integer;
    function Frame(Index: Integer): TInkWebPFrame;
    { a WebP at all, and readable as far as its structure }
    property Valid: Boolean read FValid;
    { more than one frame }
    property Animated: Boolean read FAnimated;
    { whether Bitmap holds real pixels - False until a decoder exists }
    property Decoded: Boolean read FDecoded;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    { 0 means for ever }
    property Loops: Integer read FLoops;
    property Kind: TInkWebPKind read FKind;
    property Background: TColor read FBackground;
    property Bitmap: TBitmap read FBitmap;
  end;

{ Does this look like a WebP?  Cheap enough to call on any stream before
  deciding what to do with it: the first twelve bytes are RIFF....WEBP. }
function InkIsWebP(const AData: RawByteString): Boolean;

implementation

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
  FIndex := 0; FDue := 0; FLoops := 0; FKind := wkNone;
  FBackground := clNone;
  Stream.Position := 0;
  SetLength(FData, Stream.Size);
  if Length(FData) > 0 then Stream.ReadBuffer(FData[1], Length(FData));
  if not InkIsWebP(FData) then Exit;
  { RIFF says how much of the file is payload; trust the smaller of that
    and what is actually here }
  Size := Read32(5) + 8;
  if (Size < 12) or (Size > Length(FData)) then Size := Length(FData);
  FValid := True;
  ReadChunks(13, Size);
  if FWidth <= 0 then FValid := False;
  if FValid then
  begin
    FBitmap.SetSize(FWidth, FHeight);
    FBitmap.Canvas.Brush.Color := clWhite;
    FBitmap.Canvas.FillRect(0, 0, FWidth, FHeight);
  end;
  FAnimated := Length(FFrames) > 1;
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
var P, Size, N: Integer; Name: string;
begin
  P := AStart;
  while P + 8 <= AEnd do
  begin
    Name := Copy(FData, P, 4);
    Size := Read32(P+4);
    if (Size < 0) or (P + 8 + Size > AEnd + 1) then Break;
    if Name = 'VP8X' then
    begin
      { the extended header: flags, then canvas width and height as
        one-less, 24 bits each }
      FKind := wkExtended;
      FWidth := Read24(P+12) + 1;
      FHeight := Read24(P+15) + 1;
    end
    else if Name = 'VP8 ' then
    begin
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
      end;
    end
    else if Name = 'VP8L' then
    begin
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
      end;
    end
    else if Name = 'ANIM' then
    begin
      { the background color the canvas is cleared to, and the loop count }
      FBackground := RGBToColor(ByteAt(P+10), ByteAt(P+9), ByteAt(P+8));
      FLoops := Read16(P+12);
    end
    else if Name = 'ANMF' then
      ReadAnimationFrame(P+8, Size);
    Inc(P, 8 + Size + (Size and 1));
  end;
end;

{ One animation frame: where it goes, how big it is, how long it stays, and
  the sub-chunk holding its pixels. }
procedure TInkWebP.ReadAnimationFrame(AStart, ASize: Integer);
var N, P, Sub, SubSize: Integer; Name: string; F: TInkWebPFrame;
begin
  FillChar(F, SizeOf(F), 0);
  { positions and sizes are in units of two pixels, and one less than real }
  F.X := Read24(AStart) * 2;
  F.Y := Read24(AStart+3) * 2;
  F.Width := Read24(AStart+6) + 1;
  F.Height := Read24(AStart+9) + 1;
  F.Duration := Read24(AStart+12);
  N := ByteAt(AStart+15);
  if (N and 1) <> 0 then F.Disposal := wdBackground else F.Disposal := wdNone;
  { bit 1 set means "do not blend", so the flag reads the other way round }
  F.Blend := (N and 2) = 0;
  { and inside the frame, the chunks that hold its pixels }
  P := AStart + 16;
  while P + 8 <= AStart + ASize do
  begin
    Name := Copy(FData, P, 4);
    SubSize := Read32(P+4);
    if (SubSize < 0) or (P + 8 + SubSize > AStart + ASize + 1) then Break;
    if Name = 'ALPH' then F.HasAlpha := True
    else if Name = 'VP8 ' then
    begin
      F.Offset := P+8; F.Size := SubSize; F.Kind := wkLossy;
    end
    else if Name = 'VP8L' then
    begin
      F.Offset := P+8; F.Size := SubSize; F.Kind := wkLossless;
    end;
    Inc(P, 8 + SubSize + (SubSize and 1));
  end;
  Sub := Length(FFrames);
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

function TInkWebP.DecodeFrame(Index: Integer): Boolean;
begin
  { ---------------------------------------------------------------------
    THE HOLE.  Everything above knows where frame Index's pixels are:
    Frame(Index).Offset and .Size point into FData, and .Kind says whether
    they are VP8 (lossy) or VP8L (lossless).  What is missing is turning
    those bytes into pixels and drawing them into FBitmap at .X, .Y, with
    .Disposal and .Blend honored.

    Two ways to fill it, and the choice matters more than the feature - see
    ROADMAP.md section 4, item 17:

      1. libwebp, loaded at run time.  WebPDecodeBGRA on the frame's bytes
         gives a buffer to blit into FBitmap; the unit keeps working when
         the library is missing, because this returns False and the caller
         falls back to the GIF or the alt text.
      2. A decoder in Pascal.  Start with VP8L: it is a far smaller job
         than VP8, it is lossless, and it already covers screenshots, which
         is most of what a manual shows.  Check it against libwebp's own
         output bit for bit, the way the AVIF/HEIC port checks itself
         against dav1d.

    Whichever it is, set FDecoded := True when FBitmap holds real pixels.
    Nothing else in LazInk needs to change.
    --------------------------------------------------------------------- }
  Result := False;
end;

function TInkWebP.Advance: Boolean;
var Now_: QWord; Wait: Integer;
begin
  Result := False;
  if not FAnimated or (Length(FFrames) = 0) then Exit;
  Now_ := GetTickCount64;
  if FDue = 0 then FDue := Now_ + Cardinal(Max(1, FFrames[FIndex].Duration));
  if Now_ < FDue then Exit;
  FIndex := (FIndex + 1) mod Length(FFrames);
  Wait := FFrames[FIndex].Duration;
  { a frame with no duration of its own is shown for a tenth of a second,
    the same rule GIF playback uses for a zero delay }
  if Wait <= 0 then Wait := 100;
  FDue := Now_ + Cardinal(Wait);
  Result := DecodeFrame(FIndex);
end;

end.
