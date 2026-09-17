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
procedure HTMLDrawTextEx3(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; const AOpts: THTMLOptions;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer;
  out Width, Height: integer; out AHit: THTMLHitInfo);
type
  TRow = array of string;
var
  Rows: array of TRow;
  Cols, MinCols: array of Integer;
  S, Lower, Body, Tag, Cell, Part: string;
  P, Q, E, R, C, N, X, Y, W, H, RH, Total, Avail, Offset, MinTotal, Spare: Integer;
  O: THTMLOptions;
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
    if Hit.OnLink then begin AHit := Hit; Inc(AHit.LinkIndex, Offset) end;
    Inc(Offset, LinkCount(A));
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
  Inc(Rect.Left,AOpts.Borders.Left); Dec(Rect.Right,AOpts.Borders.Right);
  SavedPen := TPen.Create; SavedBrush := TBrush.Create;
  SavedPen.Assign(Canvas.Pen); SavedBrush.Assign(Canvas.Brush);
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
      SetLength(Rows,0); SetLength(Cols,0); R := -1; Cell := ''; Tag := ''; InCell := False;
      P := 1;
      while P <= Length(Body) do
      begin
        if Body[P] <> '<' then begin Cell := Cell + Body[P]; Inc(P); Continue end;
        Q := P; while (Q <= Length(Body)) and (Body[Q] <> '>') do Inc(Q);
        Part := Copy(Body,P,Q-P+1); Tag := LowerCase(Part);
        N := Pos(' ',Tag); if N > 0 then Tag := Copy(Tag,1,N-1)+'>';
        if Tag = '<tr>' then
        begin Inc(R); SetLength(Rows,R+1); Cell := '' end
        else if (Tag = '<td>') or (Tag = '<th>') then
        begin
          if R < 0 then begin R := 0; SetLength(Rows,1) end;
          InCell := True;
          Cell := ''; if Tag = '<th>' then Cell := '<b>';
        end
        else if (Tag = '</td>') or (Tag = '</th>') then
        begin
          if R >= 0 then
          begin
            if Tag = '</th>' then Cell := Cell + '</b>';
            N := Length(Rows[R]); SetLength(Rows[R],N+1); Rows[R][N] := Trim(Cell);
            if Length(Cols) <= N then SetLength(Cols,N+1);
          end;
          Cell := ''; InCell := False;
        end
        else if (Tag <> '</tr>') and (Tag <> '<table>') and
          (Tag <> '<thead>') and (Tag <> '</thead>') and
          (Tag <> '<tbody>') and (Tag <> '</tbody>') then Cell := Cell + Part;
        P := Q+1;
      end;
      if InCell and (R >= 0) then
      begin
        N := Length(Rows[R]); SetLength(Rows[R], N+1);
        Rows[R][N] := Trim(Cell);
        if Length(Cols) <= N then SetLength(Cols, N+1);
      end;
      { Each column wants its content on one line (Cols) and cannot go below
        its longest word (MinCols).  When the widest layout does not fit,
        every column first gets its longest word and the room left over is
        shared out by how much more each would like - so a column of short
        names is not squeezed to make way for a column of sentences. }
      Total := 0; MinTotal := 0;
      SetLength(MinCols, Length(Cols));
      for C := 0 to High(Cols) do
      begin
        Cols[C] := 24; MinCols[C] := 24;
        for R := 0 to High(Rows) do if C < Length(Rows[R]) then
        begin
          Cols[C] := Max(Cols[C],HTMLTextWidth(Canvas,Types.Rect(0,0,0,0),State,Rows[R][C],O.SuperSubScriptRatio,O.Scale)+12);
          MinCols[C] := Max(MinCols[C],HTMLTextWidth(Canvas,Types.Rect(0,0,0,0),State,
            HTMLWordWrap(Canvas,Rows[R][C],1,O.SuperSubScriptRatio,O.Scale),O.SuperSubScriptRatio,O.Scale)+12);
        end;
        MinCols[C] := Min(MinCols[C],Cols[C]);
        Inc(Total,Cols[C]); Inc(MinTotal,MinCols[C]);
      end;
      Avail := Rect.Right-Rect.Left;
      if (Avail > 0) and (Total > Avail) then
      begin
        if MinTotal >= Avail then
          for C := 0 to High(Cols) do Cols[C] := Max(12,MinCols[C]*Avail div MinTotal)
        else
        begin
          Spare := Avail-MinTotal;
          for C := 0 to High(Cols) do
            Cols[C] := MinCols[C]+Int64(Cols[C]-MinCols[C])*Spare div (Total-MinTotal);
        end;
      end;
      Total := 0; for C := 0 to High(Cols) do Inc(Total,Cols[C]);
      Width := Max(Width,Total);
      for R := 0 to High(Rows) do
      begin
        RH := Canvas.TextHeight('Tg')+12;
        for C := 0 to High(Rows[R]) do
        begin
          Rows[R][C] := HTMLWordWrap(Canvas,Rows[R][C],Max(1,Cols[C]-12),O.SuperSubScriptRatio,O.Scale);
          RH := Max(RH,HTMLTextHeightOpt(Canvas,Rows[R][C],O)+12);
        end;
        X := Rect.Left;
        for C := 0 to High(Cols) do
        begin
          Box := Types.Rect(X,Y,X+Cols[C],Y+RH);
          if CalcType = htmlShow then
          begin
            Canvas.Pen.Color := Canvas.Font.Color; Canvas.Pen.Width := 1;
            Canvas.Brush.Style := bsClear; Canvas.Rectangle(Box);
          end;
          if C < Length(Rows[R]) then
            RenderPart(Rows[R][C],Types.Rect(X+6,Y+6,X+Cols[C]-6,Y+RH-6));
          Inc(X,Cols[C]);
        end;
        Inc(Y,RH);
      end;
    end;
    Height := Y;
  finally
    Canvas.Pen.Assign(SavedPen); Canvas.Brush.Assign(SavedBrush);
    SavedPen.Free; SavedBrush.Free;
  end;
end;
