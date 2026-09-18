{ Small GIF playback adapter. FPC still performs GIF/LZW decoding. 0BSD. }
unit InkGIF;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Types;
type
  TInkGIF = class
  private
    type TFrame = record
      Data: RawByteString;
      X,Y,W,H,Delay,Disposal: Integer;
    end;
  private
    FFrames: array of TFrame;
    FBitmap, FPrevious: TBitmap;
    FIndex: Integer;
    FDue: QWord;
    FBackground: TColor;
    procedure DrawFrame;
  public
    constructor Create(Stream: TStream);
    destructor Destroy; override;
    function Advance: Boolean;
    function FrameCount: Integer;
    property Bitmap: TBitmap read FBitmap;
  end;
implementation
uses Math;
constructor TInkGIF.Create(Stream: TStream);
var S,Header,Control: RawByteString; P,Start,N,PaletteBytes,Delay,Disposal,I: Integer;
  function ByteAt(A: Integer): Byte;
  begin
    if (A<1) or (A>Length(S)) then raise EReadError.Create('Truncated GIF');
    Result := Ord(S[A]);
  end;
  function WordAt(A: Integer): Integer;
  begin Result := ByteAt(A)+ByteAt(A+1)*256 end;
  procedure SkipBlocks;
  var Count: Integer;
  begin
    repeat Count := ByteAt(P); Inc(P,Count+1) until Count=0;
    if P>Length(S)+1 then raise EReadError.Create('Truncated GIF block');
  end;
begin
  inherited Create;
  FBitmap := TBitmap.Create; FPrevious := TBitmap.Create;
  Stream.Position := 0; SetLength(S,Stream.Size);
  if Length(S)>0 then Stream.ReadBuffer(S[1],Length(S));
  if (Copy(S,1,6)<>'GIF89a') and (Copy(S,1,6)<>'GIF87a') then raise EReadError.Create('Not a GIF');
  FBitmap.SetSize(WordAt(7),WordAt(9));
  PaletteBytes := 0;
  if ByteAt(11) and $80<>0 then PaletteBytes := 3*(1 shl ((ByteAt(11) and 7)+1));
  Header := Copy(S,1,13+PaletteBytes); P := 14+PaletteBytes;
  FBackground := clWhite;
  I := 14+ByteAt(12)*3;
  if (PaletteBytes>0) and (I+2<=13+PaletteBytes) then
    FBackground := RGBToColor(ByteAt(I),ByteAt(I+1),ByteAt(I+2));
  Control := ''; Delay := 100; Disposal := 0;
  while P<=Length(S) do
  begin
    case ByteAt(P) of
      $3B: Break;
      $21:
        begin
          Start := P; Inc(P,2);
          if ByteAt(Start+1)=$F9 then
          begin
            Disposal := (ByteAt(P+1) shr 2) and 7;
            Delay := Max(20,WordAt(P+2)*10);
            SkipBlocks; Control := Copy(S,Start,P-Start);
          end else SkipBlocks;
        end;
      $2C:
        begin
          Start := P; N := Length(FFrames); SetLength(FFrames,N+1);
          FFrames[N].X := WordAt(P+1); FFrames[N].Y := WordAt(P+3);
          FFrames[N].W := WordAt(P+5); FFrames[N].H := WordAt(P+7);
          I := ByteAt(P+9); Inc(P,10);
          if I and $80<>0 then Inc(P,3*(1 shl ((I and 7)+1)));
          Inc(P); SkipBlocks;
          FFrames[N].Data := Header+Control+Copy(S,Start,P-Start)+#$3B;
          FFrames[N].Delay := Delay; FFrames[N].Disposal := Disposal;
          Control := ''; Delay := 100; Disposal := 0;
        end;
    else raise EReadError.Create('Invalid GIF block') end;
  end;
  if Length(FFrames)=0 then raise EReadError.Create('GIF has no frames');
  FBitmap.Canvas.Brush.Color := FBackground; FBitmap.Canvas.FillRect(0,0,FBitmap.Width,FBitmap.Height);
  FIndex := 0; DrawFrame;
end;
destructor TInkGIF.Destroy;
begin FPrevious.Free; FBitmap.Free; inherited end;
procedure TInkGIF.DrawFrame;
var Pic: TPicture; Data: TMemoryStream;
begin
  if FFrames[FIndex].Disposal=3 then FPrevious.Assign(FBitmap);
  Pic := TPicture.Create; Data := TMemoryStream.Create;
  try
    Data.WriteBuffer(FFrames[FIndex].Data[1],Length(FFrames[FIndex].Data)); Data.Position := 0;
    Pic.LoadFromStream(Data);
    FBitmap.Canvas.Draw(FFrames[FIndex].X,FFrames[FIndex].Y,Pic.Graphic);
  finally Data.Free; Pic.Free end;
  FDue := GetTickCount64+QWord(FFrames[FIndex].Delay);
end;
function TInkGIF.Advance: Boolean;
var R: TRect;
begin
  Result := (Length(FFrames)>1) and (GetTickCount64>=FDue);
  if not Result then Exit;
  if FFrames[FIndex].Disposal=2 then
  begin
    R := Rect(FFrames[FIndex].X,FFrames[FIndex].Y,
      FFrames[FIndex].X+FFrames[FIndex].W,FFrames[FIndex].Y+FFrames[FIndex].H);
    FBitmap.Canvas.Brush.Color := FBackground; FBitmap.Canvas.FillRect(R);
  end
  else if FFrames[FIndex].Disposal=3 then FBitmap.Assign(FPrevious);
  FIndex := (FIndex+1) mod Length(FFrames);
  if FIndex=0 then
  begin FBitmap.Canvas.Brush.Color := FBackground; FBitmap.Canvas.FillRect(0,0,FBitmap.Width,FBitmap.Height) end;
  DrawFrame;
end;
function TInkGIF.FrameCount: Integer;
begin Result := Length(FFrames) end;
end.
