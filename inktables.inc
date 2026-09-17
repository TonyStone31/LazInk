{ Shared table layout for drawing, measurement and link hit testing.
  SPDX-License-Identifier: MPL-1.1

  The contents of this file are subject to the Mozilla Public License
  Version 1.1 (the "License"); you may not use this file except in
  compliance with the License. You may obtain a copy of the License at
  https://www.mozilla.org/MPL/1.1/ or in LICENSES/MPL-1.1.txt.

  Software distributed under the License is distributed on an "AS IS"
  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
  License for the specific language governing rights and limitations
  under the License.

  The Original Code is the LazInk table-layout extension to InkHtml.
  The Initial Developer is the LazInk project.
  Copyright (c) 2026 LazInk contributors. All Rights Reserved.
  Contributor(s): LazInk contributors.

  This implementation include is distributed with the MPL-covered renderer.
  For the renderer's JVCL provenance and initial developers, see inkhtml.pas
  and THIRD_PARTY_NOTICES.md. Changes: docs/RENDERER_CHANGES.md. }
{ Attributes the table code reads - written by TInkPage from CSS, or by hand:
    <table width="100%" layout="fixed" cellspacing="10" cellpadding="T R B L"
           cellbg="#rrggbb" bordercolor="#rrggbb" border="none" sides="trbl"
           radius="10">
    <td bgcolor="#rrggbb" bordercolor="#rrggbb" border="none" sides="b"
        color="#rrggbb" radius="10">
  A table with none of them is drawn as it always was: a grid in the text
  color, six pixels of padding, columns sized to their content. }
function TableAttr(const ATag, AName: string): string;
var P, Q: integer; Lower: string; Quote: char;
begin
  Result := '';
  Lower := LowerCase(ATag);
  P := Pos(' ' + AName + '=', Lower);
  if P = 0 then
  begin
    { a bare attribute - "fixed" - is there with no value }
    if Pos(' ' + AName + ' ', Lower + ' ') > 0 then Result := AName;
    if Pos(' ' + AName + '>', Lower) > 0 then Result := AName;
    Exit;
  end;
  P := P + Length(AName) + 2;
  if P > Length(ATag) then Exit;
  Quote := ATag[P];
  if (Quote = '"') or (Quote = '''') then
  begin
    Inc(P);
    Q := P;
    while (Q <= Length(ATag)) and (ATag[Q] <> Quote) do Inc(Q);
  end
  else
  begin
    Q := P;
    while (Q <= Length(ATag)) and not (ATag[Q] in [' ', '>']) do Inc(Q);
  end;
  Result := Copy(ATag, P, Q - P);
end;

type
  TTableCellStyle = record
    Back, Line, Text: TColor;   // clNone: none; clDefault: the text color
    Sides: string;              // which of t, r, b, l have a line
    Radius: integer;
  end;

procedure ReadCellStyle(const ATag: string; var AStyle: TTableCellStyle;
  const BackName: string);
var V: string;
begin
  V := TableAttr(ATag, BackName);
  if V <> '' then AStyle.Back := HTMLStringToColor(V, clNone);
  V := TableAttr(ATag, 'bordercolor');
  if V <> '' then AStyle.Line := HTMLStringToColor(V, clDefault);
  V := TableAttr(ATag, 'sides');
  if V <> '' then AStyle.Sides := LowerCase(V);
  if LowerCase(TableAttr(ATag, 'border')) = 'none' then AStyle.Sides := '';
  V := TableAttr(ATag, 'color');
  if V <> '' then AStyle.Text := HTMLStringToColor(V, clDefault);
  V := TableAttr(ATag, 'radius');
  if V <> '' then AStyle.Radius := StrToIntDef(V, AStyle.Radius);
end;

procedure HTMLDrawTextEx3(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; const AOpts: THTMLOptions;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer;
  out Width, Height: integer; out AHit: THTMLHitInfo);
type
  TRow = array of string;
  TStyleRow = array of TTableCellStyle;
var
  Rows: array of TRow;
  Styles: array of TStyleRow;
  Cols, MinCols: array of Integer;
  S, Lower, Body, Tag, Cell, Part, TableTag, V: string;
  P, Q, E, R, C, N, X, Y, W, H, RH, Total, Avail, Offset, MinTotal, Spare: Integer;
  Spacing, PadL, PadT, PadR, PadB, Extra, NCols: Integer;
  Full, Fixed: Boolean;
  Default, CellStyle, St: TTableCellStyle;
  Pads: TStringList;
  O, Measure: THTMLOptions;
  Hit: THTMLHitInfo;
  Box: TRect;
  InCell: Boolean;
  SavedPen: TPen;
  SavedBrush: TBrush;
  function LinkCount(const A: string): Integer;
  var K: Integer; B: string;
  begin
    B := LowerCase(A); Result := 0;
    for K := 1 to Length(B)-2 do
      if (Copy(B,K,2) = '<a') and (B[K+2] in [' ',#9,#10,#13]) then Inc(Result);
  end;
  procedure RenderPart(const A: string; const Bounds: TRect);
  begin
    O.HoverIndex := AOpts.HoverIndex - Offset;
    HTMLDrawTextEx3(Canvas, Bounds, State, A, O, CalcType, MouseX, MouseY,W,H,Hit);
    Inc(O.RunPart);
    if Hit.OnLink then begin AHit := Hit; Inc(AHit.LinkIndex, Offset) end;
    Inc(Offset, LinkCount(A));
  end;
  procedure AddCell;
  begin
    if R < 0 then Exit;
    N := Length(Rows[R]);
    SetLength(Rows[R], N+1); SetLength(Styles[R], N+1);
    Rows[R][N] := Trim(Cell);
    Styles[R][N] := CellStyle;
    if Length(Cols) <= N then SetLength(Cols, N+1);
  end;
  { a cell's background and lines }
  procedure PaintCell(const ABox: TRect; const AStyle: TTableCellStyle);
  var LineColor: TColor;
  begin
    LineColor := AStyle.Line;
    if LineColor = clDefault then LineColor := Canvas.Font.Color;
    Canvas.Pen.Width := 1;
    if AStyle.Back <> clNone then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AStyle.Back;
      if (AStyle.Sides = 'trbl') and (LineColor <> clNone) then
      begin
        Canvas.Pen.Style := psSolid;
        Canvas.Pen.Color := LineColor;
      end
      else
      begin
        Canvas.Pen.Style := psSolid;
        Canvas.Pen.Color := AStyle.Back;
      end;
      if AStyle.Radius > 0 then
        Canvas.RoundRect(ABox, AStyle.Radius * 2, AStyle.Radius * 2)
      else
        Canvas.Rectangle(ABox);
      if (AStyle.Sides = 'trbl') and (LineColor <> clNone) then Exit;
    end;
    if (AStyle.Sides = '') or (LineColor = clNone) then Exit;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := LineColor;
    Canvas.Brush.Style := bsClear;
    if AStyle.Sides = 'trbl' then
    begin
      if AStyle.Radius > 0 then
        Canvas.RoundRect(ABox, AStyle.Radius * 2, AStyle.Radius * 2)
      else
        Canvas.Rectangle(ABox);
      Exit;
    end;
    if Pos('t', AStyle.Sides) > 0 then
      Canvas.Line(ABox.Left, ABox.Top, ABox.Right, ABox.Top);
    if Pos('b', AStyle.Sides) > 0 then
      Canvas.Line(ABox.Left, ABox.Bottom - 1, ABox.Right, ABox.Bottom - 1);
    if Pos('l', AStyle.Sides) > 0 then
      Canvas.Line(ABox.Left, ABox.Top, ABox.Left, ABox.Bottom);
    if Pos('r', AStyle.Sides) > 0 then
      Canvas.Line(ABox.Right - 1, ABox.Top, ABox.Right - 1, ABox.Bottom);
  end;
begin
  if Pos('<table', LowerCase(Text)) = 0 then
  begin
    HTMLDrawInline(Canvas, Rect, State, Text, AOpts, CalcType, MouseX, MouseY, Width, Height, AHit);
    Exit;
  end;
  AHit.OnLink := False; AHit.LinkName := ''; AHit.LinkText := ''; AHit.LinkIndex := 0;
  Width := 0; Y := Rect.Top + AOpts.Borders.Top; Offset := 0;
  O := AOpts; O.Borders := Types.Rect(0,0,0,0);
  O.VertAlign := ivaTop; O.HorzAlign := ihaLeft;
  { measuring a cell is not laying it out: no runs reported }
  Measure := O; Measure.OnRun := nil;
  Inc(Rect.Left,AOpts.Borders.Left); Dec(Rect.Right,AOpts.Borders.Right);
  SavedPen := TPen.Create; SavedBrush := TBrush.Create;
  SavedPen.Assign(Canvas.Pen); SavedBrush.Assign(Canvas.Brush);
  Pads := TStringList.Create;
  try
    S := Text;
    while S <> '' do
    begin
      Lower := LowerCase(S); P := Pos('<table',Lower);
      if P = 0 then P := Length(S)+1;
      Part := Copy(S,1,P-1);
      if Trim(Part) <> '' then
      begin
        RenderPart(Part,Types.Rect(Rect.Left,Y,Rect.Right,Rect.Bottom));
        Width := Max(Width,W); Y := H;
      end;
      if P > Length(S) then Break;
      Delete(S,1,P-1); E := Pos('</table>',LowerCase(S));
      if E = 0 then E := Length(S)+1;
      Body := Copy(S,1,E-1); Delete(S,1,E+7);

      { the table's own attributes, and the style its cells start from }
      Q := Pos('>', Body);
      if Q = 0 then Q := Length(Body);
      TableTag := Copy(Body, 1, Q);
      Full := TableAttr(TableTag, 'width') = '100%';
      Fixed := LowerCase(TableAttr(TableTag, 'layout')) = 'fixed';
      Spacing := Max(0, StrToIntDef(TableAttr(TableTag, 'cellspacing'), 0));
      PadL := 6; PadT := 6; PadR := 6; PadB := 6;
      V := TableAttr(TableTag, 'cellpadding');
      if V <> '' then
      begin
        Pads.Delimiter := ' '; Pads.StrictDelimiter := False;
        Pads.DelimitedText := V;
        if Pads.Count = 4 then
        begin
          PadT := StrToIntDef(Pads[0], 6); PadR := StrToIntDef(Pads[1], 6);
          PadB := StrToIntDef(Pads[2], 6); PadL := StrToIntDef(Pads[3], 6);
        end
        else if Pads.Count >= 1 then
        begin
          PadT := StrToIntDef(Pads[0], 6);
          PadL := PadT; PadR := PadT; PadB := PadT;
        end;
      end;
      Default.Back := clNone; Default.Line := clDefault; Default.Text := clDefault;
      Default.Sides := 'trbl'; Default.Radius := 0;
      ReadCellStyle(TableTag, Default, 'cellbg');

      SetLength(Rows,0); SetLength(Styles,0); SetLength(Cols,0);
      R := -1; Cell := ''; Tag := ''; InCell := False;
      CellStyle := Default;
      P := 1;
      while P <= Length(Body) do
      begin
        if Body[P] <> '<' then begin Cell := Cell + Body[P]; Inc(P); Continue end;
        Q := P; while (Q <= Length(Body)) and (Body[Q] <> '>') do Inc(Q);
        Part := Copy(Body,P,Q-P+1); Tag := LowerCase(Part);
        N := Pos(' ',Tag); if N > 0 then Tag := Copy(Tag,1,N-1)+'>';
        if Tag = '<tr>' then
        begin
          Inc(R); SetLength(Rows,R+1); SetLength(Styles,R+1); Cell := '';
        end
        else if (Tag = '<td>') or (Tag = '<th>') then
        begin
          if R < 0 then begin R := 0; SetLength(Rows,1); SetLength(Styles,1) end;
          InCell := True;
          CellStyle := Default;
          ReadCellStyle(Part, CellStyle, 'bgcolor');
          Cell := '';
          if CellStyle.Text <> clDefault then
            Cell := Format('<font color="#%.2x%.2x%.2x">', [Red(ColorToRGB(CellStyle.Text)),
              Green(ColorToRGB(CellStyle.Text)), Blue(ColorToRGB(CellStyle.Text))]);
          if Tag = '<th>' then Cell := Cell + '<b>';
        end
        else if (Tag = '</td>') or (Tag = '</th>') then
        begin
          if R >= 0 then
          begin
            if Tag = '</th>' then Cell := Cell + '</b>';
            if CellStyle.Text <> clDefault then Cell := Cell + '</font>';
            AddCell;
          end;
          Cell := ''; InCell := False;
        end
        else if (Tag <> '</tr>') and (Tag <> '<table>') and
          (Tag <> '<thead>') and (Tag <> '</thead>') and
          (Tag <> '<tbody>') and (Tag <> '</tbody>') then Cell := Cell + Part;
        P := Q+1;
      end;
      if InCell and (R >= 0) then AddCell;

      { Each column wants its content on one line (Cols) and cannot go below
        its longest word (MinCols).  When the widest layout does not fit,
        every column first gets its longest word and the room left over is
        shared out by how much more each would like - so a column of short
        names is not squeezed to make way for a column of sentences. }
      Total := 0; MinTotal := 0;
      NCols := Length(Cols);
      SetLength(MinCols, NCols);
      for C := 0 to NCols-1 do
      begin
        Cols[C] := 24; MinCols[C] := 24;
        for R := 0 to High(Rows) do if C < Length(Rows[R]) then
        begin
          Cols[C] := Max(Cols[C],HTMLTextWidth(Canvas,Types.Rect(0,0,0,0),State,Rows[R][C],O.SuperSubScriptRatio,O.Scale)+PadL+PadR);
          MinCols[C] := Max(MinCols[C],HTMLTextWidth(Canvas,Types.Rect(0,0,0,0),State,
            HTMLWordWrap(Canvas,Rows[R][C],1,O.SuperSubScriptRatio,O.Scale),O.SuperSubScriptRatio,O.Scale)+PadL+PadR);
        end;
        MinCols[C] := Min(MinCols[C],Cols[C]);
        Inc(Total,Cols[C]); Inc(MinTotal,MinCols[C]);
      end;
      Avail := Rect.Right-Rect.Left-Spacing*(NCols+1);
      if (NCols > 0) and Fixed and (Avail > 0) then
      begin
        { equal columns, the whole width }
        for C := 0 to NCols-1 do Cols[C] := Avail div NCols;
        Inc(Cols[NCols-1], Avail mod NCols);
      end
      else if (Avail > 0) and (Total > Avail) then
      begin
        if MinTotal >= Avail then
          for C := 0 to NCols-1 do Cols[C] := Max(12,MinCols[C]*Avail div MinTotal)
        else
        begin
          Spare := Avail-MinTotal;
          for C := 0 to NCols-1 do
            Cols[C] := MinCols[C]+Int64(Cols[C]-MinCols[C])*Spare div (Total-MinTotal);
        end;
      end
      else if Full and (Avail > Total) and (Total > 0) then
      begin
        { a full-width table shares the room its columns do not need }
        Extra := Avail - Total;
        for C := 0 to NCols-1 do
          Inc(Cols[C], Int64(Extra)*Cols[C] div Total);
        Total := 0; for C := 0 to NCols-1 do Inc(Total,Cols[C]);
        Inc(Cols[NCols-1], Avail - Total);
      end;
      Total := Spacing*(NCols+1); for C := 0 to NCols-1 do Inc(Total,Cols[C]);
      Width := Max(Width,Total);
      Inc(Y, Spacing);
      for R := 0 to High(Rows) do
      begin
        RH := Canvas.TextHeight('Tg')+PadT+PadB;
        for C := 0 to High(Rows[R]) do
        begin
          Rows[R][C] := HTMLWordWrap(Canvas,Rows[R][C],Max(1,Cols[C]-PadL-PadR),O.SuperSubScriptRatio,O.Scale);
          RH := Max(RH,HTMLTextHeightOpt(Canvas,Rows[R][C],Measure)+PadT+PadB);
        end;
        X := Rect.Left + Spacing;
        for C := 0 to NCols-1 do
        begin
          Box := Types.Rect(X,Y,X+Cols[C],Y+RH);
          if C < Length(Rows[R]) then St := Styles[R][C] else St := Default;
          if CalcType = htmlShow then PaintCell(Box, St);
          if C < Length(Rows[R]) then
          begin
            Canvas.Brush.Style := bsClear;
            RenderPart(Rows[R][C],Types.Rect(X+PadL,Y+PadT,X+Cols[C]-PadR,Y+RH-PadB));
          end;
          Inc(X,Cols[C]+Spacing);
        end;
        Inc(Y,RH+Spacing);
      end;
    end;
    Height := Y;
  finally
    Canvas.Pen.Assign(SavedPen); Canvas.Brush.Assign(SavedBrush);
    SavedPen.Free; SavedBrush.Free;
    Pads.Free;
  end;
end;
