{ CSS linear gradients, rasterized only inside the visible rectangle.
  SPDX-License-Identifier: 0BSD; see LICENSE. }
unit InkGradient;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Types, GraphType, InkStyle;

{ Paint one linear-gradient or repeating-linear-gradient. Unsupported values
  leave the canvas alone. ARect fixes the gradient; AClip limits the work. }
function InkPaintLinearGradient(ACanvas: TCanvas; const ARect, AClip: TRect; ARadius: integer; AStyle: TInkStyle; const AValue: string; ADark: boolean): boolean;

implementation

type
  TGradientStop = record
    Color: TInkRGBA;
    Position: double;
    Placed: boolean;
  end;
  TGradientStops = array of TGradientStop;

function Direction(const S: string; W, H: double; out DX, DY: double): boolean;
var
  Parts: TStringArray;
  I, N: integer;
  Angle, Factor: double;
  V, Unit_: string;
  Format_: TFormatSettings;
begin
  Result := False;
  V := LowerCase(Trim(S));
  DX := 0;
  DY := 0;
  Parts := InkCSSParts(V, ' ');
  if (Length(Parts) >= 2) and (Length(Parts) <= 3) and (Parts[0] = 'to') then
  begin
    for I := 1 to High(Parts) do
      if (Parts[I] = 'left') and (DX = 0) then DX := -1
      else if (Parts[I] = 'right') and (DX = 0) then DX := 1
      else if (Parts[I] = 'top') and (DY = 0) then DY := -1
      else if (Parts[I] = 'bottom') and (DY = 0) then DY := 1
      else
        Exit;
    { A corner's line is perpendicular to the diagonal between its neighbors. }
    if (DX <> 0) and (DY <> 0) then
    begin
      DX := DX * H;
      DY := DY * W;
    end;
  end
  else
  begin
    N := Length(V);
    while (N > 0) and (V[N] in ['a'..'z']) do Dec(N);
    Unit_ := Copy(V, N + 1, MaxInt);
    if Unit_ = 'deg' then Factor := Pi / 180
    else if Unit_ = 'grad' then Factor := Pi / 200
    else if Unit_ = 'turn' then Factor := 2 * Pi
    else if Unit_ = 'rad' then Factor := 1
    else
      Exit;
    Format_ := DefaultFormatSettings;
    Format_.DecimalSeparator := '.';
    if not TryStrToFloat(Copy(V, 1, N), Angle, Format_) then Exit;
    if IsNan(Angle) or IsInfinite(Angle) then Exit;
    Angle := Angle * Factor;
    DX := Sin(Angle);
    DY := -Cos(Angle);
  end;
  Factor := Hypot(DX, DY);
  if Factor = 0 then Exit;
  DX := DX / Factor;
  DY := DY / Factor;
  Result := True;
end;

function ReadGradient(const Value: string; Style: TInkStyle; W, H: integer; Dark: boolean; out DX, DY, LineLength: double; out Repeating: boolean;
  out Stops: TGradientStops): boolean;
var
  V, Name_: string;
  Parts, Words: TStringArray;
  I, J, K, First, N, Last: integer;
  C: TInkRGBA;
  P, Step: double;
begin
  Result := False;
  Stops := nil;
  V := Trim(Value);
  I := Pos('(', V);
  if (I = 0) or (V[Length(V)] <> ')') then Exit;
  Name_ := LowerCase(Trim(Copy(V, 1, I - 1)));
  Repeating := Name_ = 'repeating-linear-gradient';
  if not Repeating and (Name_ <> 'linear-gradient') then Exit;
  Parts := InkCSSParts(Copy(V, I + 1, Length(V) - I - 1), ',');
  if Length(Parts) < 2 then Exit;
  DX := 0;
  DY := 1;
  First := 0;
  if Direction(Parts[0], W, H, DX, DY) then First := 1
  else
  begin
    DX := 0;
    DY := 1;
  end;
  LineLength := Abs(W * DX) + Abs(H * DY);
  for I := First to High(Parts) do
  begin
    Words := InkCSSParts(Parts[I], ' ');
    if (Length(Words) < 1) or (Length(Words) > 3) then Exit;
    if LowerCase(Words[0]) = 'currentcolor' then C := Style.Color('color')
    else if not InkParseColor(Words[0], C, Dark) then Exit;
    for J := 1 to Max(1, High(Words)) do
    begin
      N := Length(Stops);
      SetLength(Stops, N + 1);
      Stops[N].Color := C;
      Stops[N].Placed := Length(Words) > 1;
      if Stops[N].Placed then
      begin
        P := Style.Length(Words[J], LineLength, NaN);
        if IsNan(P) or IsInfinite(P) then Exit;
        Stops[N].Position := P;
      end;
    end;
  end;
  N := High(Stops);
  if N < 1 then Exit;
  if not Stops[0].Placed then Stops[0].Position := 0;
  Stops[0].Placed := True;
  if not Stops[N].Placed then Stops[N].Position := LineLength;
  Stops[N].Placed := True;
  Last := 0;
  for I := 1 to N do
    if Stops[I].Placed then
    begin
      Stops[I].Position := Max(Stops[Last].Position, Stops[I].Position);
      Step := (Stops[I].Position - Stops[Last].Position) / (I - Last);
      for K := Last + 1 to I - 1 do
        Stops[K].Position := Stops[Last].Position + (K - Last) * Step;
      Last := I;
    end;
  Result := True;
end;

function PremultipliedPixel(A, R, G, B: double): cardinal;
begin
  if Round(A) = 0 then Exit(0);
  Result := (cardinal(Round(A)) shl 24) or (cardinal(Round(R / A)) shl 16) or (cardinal(Round(G / A)) shl 8) or cardinal(Round(B / A));
end;

function AverageColor(const Stops: TGradientStops): cardinal;
var
  I, J: integer;
  Period, Weight, Alpha, A, R, G, B: double;
  C: TInkRGBA;
begin
  Period := Stops[High(Stops)].Position - Stops[0].Position;
  A := 0;
  R := 0;
  G := 0;
  B := 0;
  for I := 1 to High(Stops) do
  begin
    if Period > 0 then Weight := (Stops[I].Position - Stops[I - 1].Position) / (2 * Period)
    else
      Weight := 1 / (2 * High(Stops));
    for J := I - 1 to I do
    begin
      C := Stops[J].Color;
      Alpha := (C shr 24) * Weight;
      A := A + Alpha;
      R := R + (C and $FF) * Alpha;
      G := G + ((C shr 8) and $FF) * Alpha;
      B := B + ((C shr 16) and $FF) * Alpha;
    end;
  end;
  Result := PremultipliedPixel(A, R, G, B);
end;

function Sample(const Stops: TGradientStops; P: double; Repeating: boolean): cardinal;
var
  I, Last: integer;
  T, A, BWeight, Period: double;
  C, D: TInkRGBA;
begin
  Last := High(Stops);
  Period := Stops[Last].Position - Stops[0].Position;
  if Repeating and (Period > 0) then
    P := Stops[0].Position + (P - Stops[0].Position) - Floor((P - Stops[0].Position) / Period) * Period;
  I := 0;
  while (I < Last) and (P >= Stops[I + 1].Position) do Inc(I);
  C := Stops[I].Color;
  D := C;
  T := 0;
  if (I < Last) and (P > Stops[I].Position) then
  begin
    D := Stops[I + 1].Color;
    T := (P - Stops[I].Position) / (Stops[I + 1].Position - Stops[I].Position);
  end;
  { Interpolate premultiplied colors so a transparent stop adds no black. }
  A := (C shr 24) * (1 - T);
  BWeight := (D shr 24) * T;
  Result := PremultipliedPixel(A + BWeight, (C and $FF) * A + (D and $FF) * BWeight, ((C shr 8) and $FF) * A + ((D shr 8) and $FF) *
    BWeight, ((C shr 16) and $FF) * A + ((D shr 16) and $FF) * BWeight);
end;

function InkPaintLinearGradient(ACanvas: TCanvas; const ARect, AClip: TRect; ARadius: integer; AStyle: TInkStyle; const AValue: string; ADark: boolean): boolean;
var
  Stops: TGradientStops;
  DX, DY, LineLength, P, CX, CY, Distance, Coverage: double;
  Repeating, Averaged: boolean;
  R: TRect;
  X, Y, W, H, I, A: integer;
  Pixels: array of cardinal;
  C, Solid: cardinal;
  Raw: TRawImage;
  Bitmap: TBitmap;
begin
  Result := False;
  W := ARect.Right - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  if (W <= 0) or (H <= 0) then Exit;
  if not ReadGradient(AValue, AStyle, W, H, ADark, DX, DY, LineLength, Repeating, Stops) then Exit;
  Result := True;
  if not IntersectRect(R, ARect, AClip) then Exit;
  if ACanvas.Clipping then
    if not IntersectRect(R, R, ACanvas.ClipRect) then Exit;
  ARadius := EnsureRange(ARadius, 0, Min(W, H) div 2);
  Averaged := Repeating and (Stops[High(Stops)].Position - Stops[0].Position < 1);
  Solid := 0;
  if Averaged then Solid := AverageColor(Stops);
  SetLength(Pixels, SizeInt(R.Right - R.Left) * (R.Bottom - R.Top));
  I := 0;
  for Y := R.Top to R.Bottom - 1 do
    for X := R.Left to R.Right - 1 do
    begin
      P := (X + 0.5 - ARect.Left - W / 2) * DX + (Y + 0.5 - ARect.Top - H / 2) * DY + LineLength / 2;
      if Averaged then C := Solid
      else
        C := Sample(Stops, P, Repeating);
      if ARadius > 0 then
      begin
        CX := Max(0, Abs(X + 0.5 - ARect.Left - W / 2) - (W / 2 - ARadius));
        CY := Max(0, Abs(Y + 0.5 - ARect.Top - H / 2) - (H / 2 - ARadius));
        if (CX > 0) and (CY > 0) then
        begin
          Distance := Hypot(CX, CY);
          Coverage := EnsureRange(ARadius + 0.5 - Distance, 0.0, 1.0);
          A := Round((C shr 24) * Coverage);
          C := (C and $FFFFFF) or (cardinal(A) shl 24);
        end;
      end;
      Pixels[I] := C;
      Inc(I);
    end;
  Bitmap := TBitmap.Create;
  try
    Raw.Init;
    Raw.Description.Init_BPP32_B8G8R8A8_BIO_TTB(R.Right - R.Left, R.Bottom - R.Top);
    Raw.Data := pbyte(@Pixels[0]);
    Raw.DataSize := Length(Pixels) * 4;
    Bitmap.LoadFromRawImage(Raw, False);
    ACanvas.Draw(R.Left, R.Top, Bitmap);
  finally
    Bitmap.Free;
  end;
end;

end.
