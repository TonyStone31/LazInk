{ InkHtml — inline HTML canvas rendering for the LazInk controls.

  ATTRIBUTION: this unit is derived from the JVCL project's JvHtControls
  (JvHTMLParser / HTML drawing routines), originally by Maciej Kaczkowski
  and the Project JEDI JVCL contributors — https://jvcl.github.io/ — and
  later adapted for Lazarus/LCL. Licensed under the Mozilla Public License
  Version 1.1 (MPL 1.1); you may obtain a copy of the license at
  http://www.mozilla.org/MPL/MPL-1.1.html

  Software distributed under the License is distributed on an "AS IS"
  basis, WITHOUT WARRANTY OF ANY KIND, either expressed or implied.

  Modifications for LazInk: standalone unit, LCL types, UTF-8 handling.
  Keep this notice intact in any redistribution. }
unit InkHtml;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, LCLIntf, LCLType, Types;

type
  TJvHTMLCalcType = (htmlShow, htmlCalcWidth, htmlCalcHeight, htmlHyperLink);

procedure HTMLDrawTextEx(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; out Width: integer; CalcType: TJvHTMLCalcType;
  MouseX, MouseY: integer; out MouseOnLink: boolean; var LinkName: string;
  SuperSubScriptRatio: double; Scale: integer = 100); overload;
procedure HTMLDrawTextEx2(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; out Width, Height: integer;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer; out MouseOnLink: boolean;
  var LinkName: string; SuperSubScriptRatio: double; Scale: integer = 100); overload;
procedure HTMLDrawText(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100);
procedure HTMLDrawTextHL(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; MouseX, MouseY: integer; SuperSubScriptRatio: double;
  Scale: integer = 100);
function HTMLPlainText(const Text: string): string;
function HTMLTextExtent(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): TSize;
function HTMLTextWidth(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): integer;
function HTMLTextHeight(Canvas: TCanvas; const Text: string;
  SuperSubScriptRatio: double; Scale: integer = 100): integer;
function HTMLPrepareText(const Text: string): string;
function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;


implementation

uses
  Math, Forms;

const
  cBR = '<BR>';
  cBR2 = '<BR/>';
  cHR = '<HR>';
  cTagBegin = '<';
  cTagEnd = '>';
  cLT = '<';
  cGT = '>';
  //cQuote = '"';
  cCENTER = 'CENTER';
  cRIGHT = 'RIGHT';
  cHREF = 'HREF';
  cIND = 'IND';
  cCOLOR = 'COLOR';
  cBGCOLOR = 'BGCOLOR';

function CanvasMaxTextHeight(Canvas: TCanvas): integer;
var
  tt: TTextMetric;
begin
  // (ahuser) Qt returns different values for TextHeight('Ay') and TextHeigth(#1..#255)
  GetTextMetrics(Canvas.Handle, tt{%H-});
  Result := tt.tmHeight;
end;

// moved from JvHTControls and renamed
function HTMLPrepareText(const Text: string): string;
type
  THtmlCode = record
    Html: string;
    Text: UTF8String;
  end;
const
  Conversions: array [0..6] of THtmlCode = (
    (Html: '&amp;'; Text: '&'),
    (Html: '&quot;'; Text: '"'),
    (Html: '&reg;'; Text: #$C2#$AE),
    (Html: '&copy;'; Text: #$C2#$A9),
    (Html: '&trade;'; Text: #$E2#$84#$A2),
    (Html: '&euro;'; Text: #$E2#$82#$AC),
    (Html: '&nbsp;'; Text: ' ')
    );
var
  I: integer;
begin
  Result := Text;
  for I := Low(Conversions) to High(Conversions) do
    Result := StringReplace(Result, Conversions[I].Html,
      Utf8ToAnsi(Conversions[I].Text), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  // only <BR> can be new line
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  // only <BR> can be new line
  Result := StringReplace(Result, cBR, sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cBR2, sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  // Fixes <BR/>, but not <BR />!
  Result := StringReplace(Result, cHR, cHR + sLineBreak, [rfReplaceAll, rfIgnoreCase]);
  // fixed <HR><BR>
end;

function HTMLStringToColor(AText: string; ADefColor: TColor = clBlack): TColor;
type
  TRGBA = packed record
    R, G, B, A: byte;
  end;
var
  c: Int32;
begin
  if AText = '' then
  begin
    Result := ADefColor;
    exit;
  end;

  if AText[1] = '#' then
    AText[1] := '$';
  if TryStrToInt(AText, c) then
  begin
    TRgba(Result).R := TRgba(c).B;
    TRgba(Result).G := TRgba(c).G;
    TRgba(Result).B := TRgba(c).R;
    TRgba(Result).A := 0;
  end
  else
  begin
    if Lowercase(Copy(AText, 1, 2)) <> 'cl' then
      AText := 'cl' + AText;
    Result := StringToColorDef(AText, ADefColor);
  end;
end;

function HTMLBeforeTag(var Str: string; DeleteToTag: boolean = False): string;
begin
  if Pos(cTagBegin, Str) > 0 then
  begin
    Result := Copy(Str, 1, Pos(cTagBegin, Str) - 1);
    if DeleteToTag then
      Delete(Str, 1, Pos(cTagBegin, Str) - 1);
  end
  else
  begin
    Result := Str;
    if DeleteToTag then
      Str := '';
  end;
end;

function GetChar(const Str: string; Pos: word; Up: boolean = False): char;
begin
  if Length(Str) >= Pos then
    Result := Str[Pos]
  else
    Result := ' ';
  if Up then
    Result := UpCase(Result);
end;

function HTMLDeleteTag(const Str: string): string;
begin
  Result := Str;
  if (GetChar(Result, 1) = cTagBegin) and (Pos(cTagEnd, Result) > 1) then
    Delete(Result, 1, Pos(cTagEnd, Result));
end;

// wp: Made Width and MouseOnLink out parameters (were "var" in the original)
// to silence the compiler
procedure HTMLDrawTextEx(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; out Width: integer; CalcType: TJvHTMLCalcType;
  MouseX, MouseY: integer; out MouseOnLink: boolean; var LinkName: string;
  SuperSubScriptRatio: double; Scale: integer);
var
  H: integer;
begin
  HTMLDrawTextEx2(Canvas, Rect, State, Text, Width, H, CalcType,
    MouseX, MouseY, MouseOnLink,
    LinkName, SuperSubScriptRatio, Scale);
  if CalcType = htmlCalcHeight then
    Width := H;
end;

type
  TScriptPosition = (spNormal, spSuperscript, spSubscript);

// wp: Make Width, Height and MouseOnLink "out" parameters
// (they were "var" in the original) to silence the compiler
procedure HTMLDrawTextEx2(Canvas: TCanvas; Rect: TRect;
  const State: TOwnerDrawState; const Text: string; out Width, Height: integer;
  CalcType: TJvHTMLCalcType; MouseX, MouseY: integer; out MouseOnLink: boolean;
  var LinkName: string; SuperSubScriptRatio: double; Scale: integer);
const
  DefaultLeft = 0; // (ahuser) was 2
var
  vText, vM, TagPrp, Prp, TempLink: string;
  vCount: integer;
  vStr: TStringList;
  Selected: boolean;
  Alignment: TAlignment;
  Trans, IsLink: boolean;
  CurLeft: integer;
  // for begin and end
  OldFontStyles: TFontStyles;
  OldFontColor: TColor;
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldAlignment: TAlignment;
  OldFont: TFont;
  OldWidth: integer;
  // for font style
  RemFontColor, RemBrushColor: TColor;
  RemFontSize: integer;
  ScriptPosition: TScriptPosition;

  function ExtractPropertyValue(const Tag: string; PropName: string): string;
  var
    I: integer;
  begin
    Result := '';
    PropName := UpperCase(PropName);
    if Pos(PropName, UpperCase(Tag)) > 0 then
    begin
      Result := Copy(Tag, Pos(PropName, UpperCase(Tag)) + Length(PropName), Length(Tag));
      if Pos('"', Result) <> 0 then
      begin
        Result := Copy(Result, Pos('"', Result) + 1, Length(Result));
        Result := Copy(Result, 1, Pos('"', Result) - 1);
      end
      else
      if Pos('''', Result) <> 0 then
      begin
        Result := Copy(Result, Pos('''', Result) + 1, Length(Result));
        Result := Copy(Result, 1, Pos('''', Result) - 1);
      end
      else
      begin
        Result := Trim(Result);
        Delete(Result, 1, 1);
        Result := Trim(Result);
        I := 1;
        while (I < Length(Result)) and (Result[I + 1] <> ' ') do
          Inc(I);
        Result := Copy(Result, 1, I);
      end;
    end;
  end;

  procedure Style(const Style: TFontStyle; const Include: boolean);
  begin
    if Assigned(Canvas) then
      if Include then
        Canvas.Font.Style := Canvas.Font.Style + [Style]
      else
        Canvas.Font.Style := Canvas.Font.Style - [Style];
  end;

  function CalcPos(const Str: string): integer;
  begin
    case Alignment of
      taRightJustify:
        Result := (Rect.Right - Rect.Left) - HTMLTextWidth(Canvas,
          Rect, State, Str, Scale);
      taCenter:
        Result := DefaultLeft + ((Rect.Right - Rect.Left) -
          HTMLTextWidth(Canvas, Rect, State, Str, SuperSubScriptRatio)) div 2;
      else
        Result := DefaultLeft;
    end;
    if Result <= 0 then
      Result := DefaultLeft;
  end;

  procedure Draw(const M: string);
  var
    Width, Height: integer;
    R: TRect;
    OriginalFontSize: integer;
    lineHeight: integer;
  begin
    R := Rect;
    Inc(R.Left, CurLeft);
    if Assigned(Canvas) then
    begin
      lineHeight := Canvas.TextHeight('Tg');
      OriginalFontSize := Canvas.Font.Size;
      try
        if ScriptPosition <> spNormal then
          Canvas.Font.Size := Round(Canvas.Font.Size * SuperSubScriptRatio);

        Width := Canvas.TextWidth(M);
        Height := CanvasMaxTextHeight(Canvas);

        if ScriptPosition = spSubscript then
          R.Top := R.Top + lineHeight - Height - 1;

        if IsLink and not MouseOnLink then
          if (MouseY >= R.Top) and (MouseY <= R.Top + Height) and
            (MouseX >= R.Left) and (MouseX <= R.Left + Width) and
            ((MouseY > 0) or (MouseX > 0)) then
          begin
            MouseOnLink := True;
            LinkName := TempLink;
          end;

        if CalcType = htmlShow then
        begin
          if Trans then
            Canvas.Brush.Style := bsClear; // for transparent
          Canvas.TextOut(R.Left, R.Top, M);
        end;
        CurLeft := CurLeft + Width;
      finally
        Canvas.Font.Size := OriginalFontSize;
      end;
    end;
  end;

  procedure NewLine(Always: boolean = False);
  begin
    if Assigned(Canvas) then
      if Always or (vCount < vStr.Count - 1) then
      begin
        Width := Max(Width, CurLeft);
        CurLeft := DefaultLeft;
        Rect.Top := Rect.Top + CanvasMaxTextHeight(Canvas);
      end;
  end;

begin
  // (p3) remove warnings
  OldFontColor := 0;
  OldBrushColor := 0;
  OldBrushStyle := bsClear;
  RemFontSize := 0;
  RemFontColor := 0;
  RemBrushColor := 0;
  OldAlignment := taLeftJustify;
  OldFont := TFont.Create;

  if Canvas <> nil then
  begin
    if Lowercase(Canvas.Font.Name) = 'default' then
      Canvas.Font.Name := Screen.SystemFont.Name;
    if Canvas.Font.Size = 0 then
      Canvas.Font.Size := Screen.SystemFont.Size;
    OldFontStyles := Canvas.Font.Style;
    OldFontColor := Canvas.Font.Color;
    OldBrushColor := Canvas.Brush.Color;
    OldBrushStyle := Canvas.Brush.Style;
    //  OldAlignment  := Alignment;
    RemFontColor := Canvas.Font.Color;
    RemBrushColor := Canvas.Brush.Color;
    RemFontSize := Canvas.Font.size;
  end;

  vStr := TStringList.Create;
  try
    Alignment := taLeftJustify;
    IsLink := False;
    MouseOnLink := False;
    vText := Text;
    vStr.Text := HTMLPrepareText(vText);
    LinkName := '';
    TempLink := '';
    ScriptPosition := spNormal;

    Selected := (odSelected in State) or (odDisabled in State);
    Trans := (Canvas.Brush.Style = bsClear) and not selected;

    Width := DefaultLeft;
    CurLeft := DefaultLeft;

    vM := '';
    for vCount := 0 to vStr.Count - 1 do
    begin
      //      vText := HTMLPrepareText(vStr[vCount]);
      vText := vStr[vCount];
      CurLeft := CalcPos(vText);
      while vText <> '' do
      begin
        vM := HTMLBeforeTag(vText, True);
        vM := StringReplace(vM, '&lt;', cLT, [rfReplaceAll, rfIgnoreCase]);
        // <--+ this must be here
        vM := StringReplace(vM, '&gt;', cGT, [rfReplaceAll, rfIgnoreCase]); // <--/
        if GetChar(vText, 1) = cTagBegin then
        begin
          if vM <> '' then
            Draw(vM);
          if Pos(cTagEnd, vText) = 0 then
            Insert(cTagEnd, vText, 2);
          if GetChar(vText, 2) = '/' then
          begin
            case GetChar(vText, 3, True) of
              'A':
              begin
                IsLink := False;
                Canvas.Font.Assign(OldFont);
              end;
              'B':
                Style(fsBold, False);
              'I':
                Style(fsItalic, False);
              'U':
                Style(fsUnderline, False);
              'S':
              begin
                ScriptPosition := spNormal;
                Style(fsStrikeOut, False);
              end;
              'F':
              begin
                if not Selected then // restore old colors
                begin
                  Canvas.Font.Color := RemFontColor;
                  Canvas.Brush.Color := RemBrushColor;
                  Canvas.Font.Size := RemFontSize;
                  Trans := True;
                end;
              end;
            end;
          end
          else
          begin
            case GetChar(vText, 2, True) of
              'A':
              begin
                if GetChar(vText, 3, True) = 'L' then // ALIGN
                begin
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  if Pos(cCENTER, TagPrp) > 0 then
                    Alignment := taCenter
                  else
                  if Pos(cRIGHT, TagPrp) > 0 then
                    Alignment := taRightJustify
                  else
                    Alignment := taLeftJustify;
                  CurLeft := DefaultLeft;
                  if CalcType in [htmlShow, htmlHyperLink] then
                    CurLeft := CalcPos(vText);
                end
                else
                begin   // A HREF
                  TagPrp := Copy(vText, 2, Pos(cTagEnd, vText) - 2);
                  if Pos(cHREF, UpperCase(TagPrp)) > 0 then
                  begin
                    IsLink := True;
                    OldFont.Assign(Canvas.Font);
                    if not Selected then
                      Canvas.Font.Color := clBlue;
                    TempLink := ExtractPropertyValue(TagPrp, cHREF);
                  end;
                end;
              end;
              'B':
                Style(fsBold, True);
              'I':
                if GetChar(vText, 3, True) = 'N' then //IND="%d"
                begin
                  TagPrp := Copy(vText, 2, Pos(cTagEnd, vText) - 2);
                  CurLeft := StrToInt(ExtractPropertyValue(TagPrp, cIND)); // ex IND="10"
                  if odReserved1 in State then
                    CurLeft := Round((CurLeft * Scale) div 100);
                end
                else
                  Style(fsItalic, True); // ITALIC
              'U':
                Style(fsUnderline, True);
              'S':
              begin
                if GetChar(vText, 4, True) = 'P' then
                begin
                  ScriptPosition := spSuperscript;
                end
                else if GetChar(vText, 4, True) = 'B' then
                begin
                  ScriptPosition := spSubscript;
                end
                else
                begin
                  ScriptPosition := spNormal;
                  Style(fsStrikeOut, True);
                end;
              end;
              'H':
                if (GetChar(vText, 3, True) = 'R') and Assigned(Canvas) then // HR
                begin
                  if odDisabled in State then // only when disabled
                    Canvas.Pen.Color := Canvas.Font.Color;
                  OldWidth := Canvas.Pen.Width;
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  Canvas.Pen.Width :=
                    StrToIntDef(ExtractPropertyValue(TagPrp, 'SIZE'), 1); // ex HR="10"
                  if odReserved1 in State then
                    Canvas.Pen.Width := Round((Canvas.Pen.Width * Scale) div 100);
                  if CalcType = htmlShow then
                  begin
                    Canvas.MoveTo(Rect.Left, Rect.Top + CanvasMaxTextHeight(Canvas));
                    Canvas.LineTo(Rect.Right, Rect.Top + CanvasMaxTextHeight(Canvas));
                  end;
                  Rect.Top := Rect.Top + 1 + Canvas.Pen.Width;
                  Canvas.Pen.Width := OldWidth;
                  NewLine(HTMLDeleteTag(vText) <> '');
                end;
              'F':
                if (Pos(cTagEnd, vText) > 0) and (not Selected) and
                  Assigned(Canvas) {and (CalcType in [htmlShow, htmlHyperLink])} then // F from FONT
                begin
                  TagPrp := UpperCase(Copy(vText, 2, Pos(cTagEnd, vText) - 2));
                  RemFontColor := Canvas.Font.Color;
                  RemBrushColor := Canvas.Brush.Color;

                  if Pos(cCOLOR, TagPrp) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagPrp, cCOLOR);
                    Canvas.Font.Color := HTMLStringToColor(Prp);
                  end;
                  if Pos(cBGCOLOR, TagPrp) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagPrp, cBGCOLOR);
                    if UpperCase(Prp) = 'CLNONE' then
                      Trans := True
                    else
                    begin
                      Canvas.Brush.Color := HTMLStringToColor(Prp);
                      Trans := False;
                    end;
                  end;
                  if Pos('SIZE', TagPrp) > 0 then
                  begin
                    Prp := ExtractPropertyValue(TagPrp, 'SIZE');
                    Canvas.Font.Size := StrToIntDef(Prp, 2){ * Canvas.Font.Size div 2};
                  end;
                end;
            end;
          end;
          vText := HTMLDeleteTag(vText);
          vM := '';
        end;
      end;
      if vM <> '' then
        Draw(vM);
      NewLine;
      vM := '';
    end;
  finally
    if Canvas <> nil then
    begin
      Canvas.Font.Style := OldFontStyles;
      Canvas.Font.Color := OldFontColor;
      Canvas.Brush.Color := OldBrushColor;
      Canvas.Brush.Style := OldBrushStyle;
      Alignment := OldAlignment;
  {    Canvas.Font.Color := RemFontColor;
      Canvas.Brush.Color:= RemBrushColor;}
    end;
    FreeAndNil(vStr);
    FreeAndNil(OldFont);
  end;
  Width := Max(Width, CurLeft - DefaultLeft);
  Height := Rect.Top + CanvasMaxTextHeight(Canvas);
end;

// wp: I made this a procedure - it was a function in the original with the
// result being unassigned.
procedure HTMLDrawText(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer);
var
  W: integer;
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, W, htmlShow, 0, 0, S, St,
    SuperSubScriptRatio, Scale);
end;

// wp: I made this a procedure - it was a function in the original with the
// result being unassigned.
procedure HTMLDrawTextHL(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; MouseX, MouseY: integer; SuperSubScriptRatio: double;
  Scale: integer);
var
  W: integer;
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, W, htmlShow, MouseX,
    MouseY, S, St, SuperSubScriptRatio, Scale);
end;

function HTMLPlainText(const Text: string): string;
var
  S: string;
begin
  Result := '';
  S := HTMLPrepareText(Text);
  while Pos(cTagBegin, S) > 0 do
  begin
    Result := Result + Copy(S, 1, Pos(cTagBegin, S) - 1);
    if Pos(cTagEnd, S) > 0 then
      Delete(S, 1, Pos(cTagEnd, S))
    else
      Delete(S, 1, Pos(cTagBegin, S));
  end;
  Result := Result + S;
end;

function HTMLTextExtent(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): TSize;
var
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx2(Canvas, Rect, State, Text, Result.cx, Result.cy,
    htmlCalcWidth, 0, 0, S, St, SuperSubScriptRatio, Scale);
  if Result.cy = 0 then
    Result.cy := CanvasMaxTextHeight(Canvas);
  Inc(Result.cy);
end;

function HTMLTextWidth(Canvas: TCanvas; Rect: TRect; const State: TOwnerDrawState;
  const Text: string; SuperSubScriptRatio: double; Scale: integer = 100): integer;
var
  S: boolean;
  St: string = '';
begin
  HTMLDrawTextEx(Canvas, Rect, State, Text, Result, htmlCalcWidth,
    0, 0, S, St, SuperSubScriptRatio, Scale);
end;

function HTMLTextHeight(Canvas: TCanvas; const Text: string;
  SuperSubScriptRatio: double; Scale: integer = 100): integer;
var
  S: boolean;
  St: string = '';
  R: TRect;
begin
  R := Rect(0, 0, 0, 0);
  HTMLDrawTextEx(Canvas, R, [], Text, Result, htmlCalcHeight, 0, 0,
    S, St, SuperSubScriptRatio, Scale);
  if Result = 0 then
    Result := CanvasMaxTextHeight(Canvas);
  Inc(Result);
end;

end.
end.
