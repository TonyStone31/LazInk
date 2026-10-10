{ Documents laid out from their trees: InkStyle's computed styles,
  InkLayout's boxes, and the page's own blocks for the words in them.

  Each run of inline content - a box InkLayout calls ibkText - becomes one
  of the page's blocks, its markup made from the styles of the elements the
  words sit in; the inline renderer lays it out at the width the box was
  given, so selection, find, copy, links and code headers work as they
  always have.  Backgrounds and borders belong to the boxes and are painted
  under the words in the order CSS paints them. }

type
  TPageMeasure = class(TInkLayoutMeasure)
  public
    Page: TInkCustomPage;
    function TextHeight(ABox: TInkBox; AWidth: Integer): Integer; override;
    procedure TextWidths(ABox: TInkBox; out AMin, AMax: Integer); override;
    procedure ImageSize(ABox: TInkBox; out AWidth, AHeight: Integer); override;
  end;

function TPageMeasure.TextHeight(ABox: TInkBox; AWidth: Integer): Integer;
begin
  if ABox.Data = nil then Exit(0);
  Result := Page.TreeTextHeight(TInkPageBlock(ABox.Data), AWidth);
end;

procedure TPageMeasure.TextWidths(ABox: TInkBox; out AMin, AMax: Integer);
begin
  AMin := 0; AMax := 0;
  if ABox.Data <> nil then Page.TreeTextWidths(TInkPageBlock(ABox.Data), AMin, AMax);
end;

procedure TPageMeasure.ImageSize(ABox: TInkBox; out AWidth, AHeight: Integer);
var B: TInkPageBlock; N: TInkNode; VB: TStringArray; Fit: Double;
begin
  AWidth := 0; AHeight := 0;
  B := TInkPageBlock(ABox.Data);
  if (B <> nil) and (B.Picture.Graphic <> nil) then
  begin
    AWidth := B.Picture.Width; AHeight := B.Picture.Height;
    { a window for one picture: as large as fits in it, up or down }
    if (Page.ImageFit = iifWindow) and (AWidth > 0) and (AHeight > 0) then
    begin
      Fit := Min((Page.TreeViewWidth - 16) / AWidth, (Max(1, Page.ClientHeight) - 16) / AHeight);
      if Fit > 0 then
      begin
        AWidth := Max(1, Round(AWidth * Fit)); AHeight := Max(1, Round(AHeight * Fit));
      end;
    end;
    Exit;
  end;
  N := ABox.Node;
  if N = nil then Exit;
  { a drawing, or a picture that did not come: the size its attributes say }
  AWidth := StrToIntDef(N.GetAttribute('width'), 0);
  AHeight := StrToIntDef(N.GetAttribute('height'), 0);
  if (AWidth = 0) and (AHeight = 0) and N.HasAttribute('viewBox') then
  begin
    VB := Trim(StringReplace(N.GetAttribute('viewBox'), ',', ' ', [rfReplaceAll])).Split([' '],
      TStringSplitOptions.ExcludeEmpty);
    if Length(VB) = 4 then
    begin
      AWidth := Round(StrToFloatDef(VB[2], 0, DefaultFormatSettings));
      AHeight := Round(StrToFloatDef(VB[3], 0, DefaultFormatSettings));
    end;
  end;
  if (N.Name = 'iframe') or (N.Name = 'video') or (N.Name = 'canvas') or (N.Name = 'embed') or
    (N.Name = 'object') then
  begin
    if AWidth = 0 then AWidth := 300;
    if AHeight = 0 then AHeight := 150;
  end;
end;

{ ---------------------------------------------------------- the words }

{ how tall a block's words are at a width, with a code block's header }
function TInkCustomPage.TreeTextHeight(B: TInkPageBlock; AWidth: Integer): Integer;
var O: THTMLOptions; Sz: TSize; TextW: Integer;
begin
  BlockFont(Canvas, B);
  O := Options;
  O.LineHeight := B.LineHeight;
  O.NoWrap := B.NoWrap;
  O.CSSLines := True;
  B.MarkerWidth := 0;
  if B.Marker <> '' then B.MarkerWidth := Canvas.TextWidth(B.Marker + ' ');
  B.CodeHead := 0;
  TextW := Max(1, AWidth);
  if B.NoWrap then B.Wrapped := B.Source
  else B.Wrapped := HTMLWordWrap(Canvas, B.Source, TextW, O.SuperSubScriptRatio, O.Scale);
  if FCodeHeader and (B.Code <> '') then
  begin
    B.CodeHead := Max(16, Round(FLayoutBase * 1.9));
    B.CodeLines := CodeLineCount(B.Code);
    if not B.CodeFoldSet then
    begin
      B.CodeFolded := (FCodeFoldLines > 0) and (B.CodeLines > FCodeFoldLines);
      B.CodeFoldSet := True;
    end;
    if B.CodeFolded and (FCodeFoldLines > 0) and (B.CodeLines > FCodeFoldLines) then
      B.Wrapped := FirstCodeLines(B.Wrapped, FCodeFoldLines) + '<br><font color="' +
        ColorToHTMLHex(MixColor(B.TextColor, FCanvasBack, 0.5)) + '">...</font>';
  end;
  if B.Source = '' then Sz.cy := 0
  else Sz := HTMLTextExtentOpt(Canvas, Rect(0, 0, TextW, 0), [], B.Wrapped, O);
  B.WrapWidth := AWidth;
  B.TreeTextH := B.CodeHead + Sz.cy;
  Result := B.TreeTextH;
end;

{ the narrowest a block's words can be - their longest word - and the
  widest - all on one line }
procedure TInkCustomPage.TreeTextWidths(B: TInkPageBlock; out AMin, AMax: Integer);
var O: THTMLOptions; Sz: TSize; Src: string;
begin
  if B.WidthsKnown then begin AMin := B.TextMinW; AMax := B.TextMaxW; Exit end;
  BlockFont(Canvas, B);
  O := Options;
  O.LineHeight := B.LineHeight;
  O.NoWrap := True;
  O.CSSLines := True;
  { centered or right-aligned words would measure as wide as the room }
  Src := B.Source;
  if Copy(Src, 1, 8) = '<center>' then Delete(Src, 1, 8)
  else if Copy(Src, 1, 7) = '<right>' then Delete(Src, 1, 7);
  Sz := HTMLTextExtentOpt(Canvas, Rect(0, 0, 100000, 0), [], Src, O);
  AMax := Sz.cx;
  if B.NoWrap then AMin := AMax
  else
  begin
    { laid out a pixel wide, every word is a line: the widest is the
      narrowest the words can be }
    O.NoWrap := False;
    Sz := HTMLTextExtentOpt(Canvas, Rect(0, 0, 1, 0), [], Src, O);
    AMin := Min(AMax, Sz.cx);
  end;
  if (B.Marker <> '') and not B.MarkerHangs then
  begin
    Inc(AMin, Canvas.TextWidth(B.Marker + ' ')); Inc(AMax, Canvas.TextWidth(B.Marker + ' '));
  end;
  B.TextMinW := AMin; B.TextMaxW := AMax; B.WidthsKnown := True;
end;

function FontFamilyFace(const AStack: string): string;
begin
  Result := '';
  if Trim(AStack) = '' then Exit;
  Result := InkResolveFace(AStack);
end;

{ a computed line-height in whole pixels, or -1 for normal }
function LinePixels(S: TInkStyle): Integer;
var V: string; LH: Double;
begin
  V := S.Keyword('line-height');
  Result := -1;
  if (V = '') or (V = 'normal') then Exit;
  if Pos('px', V) > 0 then Result := Round(S.Px('line-height'))
  else if TryStrToFloat(V, LH, DefaultFormatSettings) or
    TryStrToFloat(StringReplace(V, '.', DefaultFormatSettings.DecimalSeparator, []), LH) then
    Result := Round(LH * S.FontSize);
end;

function WeightOf(S: TInkStyle): Integer;
begin
  Result := StrToIntDef(S.Value('font-weight'), 400);
end;

{ the block's markup, made from the inline content of ABox }
procedure TInkCustomPage.TreeText(ABox: TInkBox; B: TInkPageBlock);
var OwnerEl: TInkNode; Base: TInkStyle; Out_, V, Head, Tail: string; PendingSpace, AtStart: Boolean;
  Targets, Titles: TStringList; BackCol: TColor; I: Integer; N: TInkNode; Faded: TInkBox;

  procedure Put(const AText: string);
  begin
    Out_ := Out_ + AText;
  end;

  { words, white space collapsed or kept as their own element says }
  procedure Words(const T: string; S: TInkStyle);
  var WS, Tr, Chunk: string; P, Col, K: Integer; C: Char; Keep: Boolean;
  begin
    { hidden words are left out, not kept as room: a run cannot hold a gap }
    WS := S.Keyword('visibility');
    if (WS = 'hidden') or (WS = 'collapse') then Exit;
    WS := S.Keyword('white-space');
    Keep := (WS = 'pre') or (WS = 'pre-wrap') or (WS = 'break-spaces') or (WS = 'pre-line');
    Tr := S.Keyword('text-transform');
    Chunk := T;
    if Tr = 'uppercase' then Chunk := UTF8UpperCase(Chunk)
    else if Tr = 'lowercase' then Chunk := UTF8LowerCase(Chunk)
    else if Tr = 'capitalize' then Chunk := Transformed(Chunk, 'capitalize');
    if Keep then
    begin
      Col := 0;
      P := 1;
      while P <= Length(Chunk) do
      begin
        C := Chunk[P];
        if C = #10 then begin Put('<br>'); Col := 0 end
        else if C = #13 then
        else if C = #9 then
        begin
          if WS = 'pre-line' then Put(' ')
          else repeat Put(' '); Inc(Col) until Col mod 8 = 0;
        end
        else if (C = ' ') and (WS = 'pre-line') then
        begin
          if not PendingSpace then Put(' ');
          PendingSpace := True;
          Inc(P); Continue;
        end
        else
        begin
          K := P;
          while (K <= Length(Chunk)) and not (Chunk[K] in [#10, #13, #9]) and
            not ((WS = 'pre-line') and (Chunk[K] = ' ')) do Inc(K);
          Put(HTMLEscape(Copy(Chunk, P, K - P)));
          Inc(Col, UTF8Length(Copy(Chunk, P, K - P)));
          P := K; PendingSpace := False; AtStart := False;
          Continue;
        end;
        PendingSpace := False;
        Inc(P);
      end;
      AtStart := False;
      Exit;
    end;
    P := 1;
    while P <= Length(Chunk) do
    begin
      if Chunk[P] in [' ', #9, #10, #12, #13] then
      begin
        if not AtStart then PendingSpace := True;
        Inc(P);
        Continue;
      end;
      K := P;
      while (K <= Length(Chunk)) and not (Chunk[K] in [' ', #9, #10, #12, #13]) do Inc(K);
      if PendingSpace then Put(' ');
      PendingSpace := False; AtStart := False;
      Put(HTMLEscape(Copy(Chunk, P, K - P)));
      P := K;
    end;
  end;

  { generated text: content: "..." in ::before and ::after }
  procedure Generated(E: TInkNode; const APseudo: string);
  var PS: TInkStyle; C: string; Q: Char; P, K: Integer; Txt: string;
  begin
    PS := FStyler.PseudoStyleOf(E, APseudo);
    if (PS = nil) or (PS.Keyword('display') = 'none') then Exit;
    if CSSFloat(PS.Value('opacity'), 1) <= 0 then Exit;
    C := Trim(PS.Value('content'));
    if (C = '') or (LowerCase(C) = 'none') or (LowerCase(C) = 'normal') then Exit;
    Txt := ''; P := 1;
    while P <= Length(C) do
    begin
      if C[P] in ['"', ''''] then
      begin
        Q := C[P]; K := P + 1;
        while (K <= Length(C)) and (C[K] <> Q) do
        begin
          if (C[K] = '\') and (K < Length(C)) then
          begin
            Inc(K);
            { \201C and the like: a character by its number }
            if C[K] in ['0'..'9', 'a'..'f', 'A'..'F'] then
            begin
              P := K;
              while (K <= Length(C)) and (K - P < 6) and (C[K] in ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(K);
              Txt := Txt + UnicodeToUTF8(StrToIntDef('$' + Copy(C, P, K - P), 32));
              if (K <= Length(C)) and (C[K] = ' ') then Inc(K);
              Continue;
            end;
          end;
          Txt := Txt + C[K];
          Inc(K);
        end;
        P := K + 1;
      end
      else if LowerCase(Copy(C, P, 10)) = 'open-quote' then begin Txt := Txt + '“'; Inc(P, 10) end
      else if LowerCase(Copy(C, P, 11)) = 'close-quote' then begin Txt := Txt + '”'; Inc(P, 11) end
      else if LowerCase(Copy(C, P, 5)) = 'attr(' then
      begin
        K := PosEx(')', C, P);
        Txt := Txt + E.GetAttribute(Trim(Copy(C, P + 5, K - P - 5)));
        P := K + 1;
      end
      else Inc(P);
    end;
    if Txt <> '' then Words(Txt, PS);
  end;

  procedure Element(E: TInkNode; P: TInkStyle; Deco: string); forward;

  procedure Node(N: TInkNode; P: TInkStyle; const Deco: string);
  begin
    if N.Kind = inkText then Words(N.Data, P)
    else if N.Kind = inkElement then Element(N, P, Deco);
  end;

  { an element inside the run: what it changes, around its content }
  procedure Element(E: TInkNode; P: TInkStyle; Deco: string);
  var S: TInkStyle; Open, Close, Attrs, Ty, V2, Href: string; C: TInkNode; Bg: TInkRGBA;
    PadV, PadH, Rad, Bw, SpL, SpR: Integer; Sub: Boolean;
  begin
    S := FStyler.StyleOf(E);
    if S = nil then S := P;
    if S.Keyword('display') = 'none' then Exit;
    if E.Id <> '' then B.Anchor := Trim(B.Anchor + ' ' + E.Id);
    if (E.Name = 'a') and E.HasAttribute('name') then B.Anchor := Trim(B.Anchor + ' ' + E.GetAttribute('name'));
    if (E.Name = 'script') or (E.Name = 'style') or (E.Namespace <> insHTML) then Exit;
    if CSSFloat(S.Value('opacity'), 1) <= 0 then Exit;
    if E.Name = 'br' then
    begin
      Put('<br>'); PendingSpace := False;
      Exit;
    end;
    if E.Name = 'img' then
    begin
      V2 := E.GetAttribute('alt');
      if V2 <> '' then Words(V2, S);
      Exit;
    end;
    if E.Name = 'input' then
    begin
      Ty := LowerCase(E.GetAttribute('type'));
      if (Ty = 'checkbox') or (Ty = 'radio') then
      begin
        if PendingSpace then Put(' ');
        PendingSpace := False; AtStart := False;
        Put(InkCheckboxMarkup(E.HasAttribute('checked')) + ' ');
      end
      else if Ty <> 'hidden' then
      begin
        V2 := E.GetAttribute('value');
        if V2 = '' then V2 := E.GetAttribute('placeholder');
        if V2 <> '' then Words(V2, S);
      end;
      Exit;
    end;
    Open := ''; Close := '';
    Sub := False;
    { font, size and color where they change }
    Attrs := '';
    V2 := S.Keyword('vertical-align');
    if (V2 = 'sub') or (V2 = 'super') then
    begin
      Sub := True;
      if V2 = 'sub' then begin Open := Open + '<sub>'; Close := '</sub>' + Close end
      else begin Open := Open + '<sup>'; Close := '</sup>' + Close end;
    end
    else if Abs(S.FontSize - P.FontSize) > 0.4 then
      Attrs := Attrs + ' size="' + IntToStr(-Max(1, Round(S.FontSize))) + '"';
    if S.Color('color') <> P.Color('color') then
      Attrs := Attrs + ' color="' + ColorAttr(InkToColor(S.Color('color'), BackCol)) + '"';
    if S.Value('font-family') <> P.Value('font-family') then
    begin
      V2 := FontFamilyFace(S.Value('font-family'));
      if V2 <> '' then Attrs := Attrs + ' face="' + V2 + '"';
    end;
    if LinePixels(S) <> LinePixels(P) then
      Attrs := Attrs + ' lineheight="' + IntToStr(LinePixels(S)) + '"';
    { a background of its own, and the padding, corners and border that make
      a pill of it; the border's width is part of the pill's padding }
    Bg := S.Color('background-color');
    { a masked one is an icon cut from its color: without the mask, nothing }
    if (S.Keyword('mask-image') <> 'none') and (S.Keyword('mask-image') <> '') then Bg := 0;
    if (Bg shr 24) > 0 then
      Attrs := Attrs + ' bgcolor="' + ColorAttr(InkToColor(Bg, BackCol)) + '"';
    Bw := Round(S.Px('border-top-width'));
    if S.Keyword('border-top-style') = 'none' then Bw := 0;
    PadV := Round(S.Px('padding-top')) + Bw; PadH := Round(S.Px('padding-left')) + Bw;
    Rad := Round(S.Px('border-top-left-radius'));
    { the room around it: its margins, and its padding too when there is
      nothing to paint in that - a pill keeps its words on one line }
    SpL := Max(0, Round(S.Px('margin-left'))); SpR := Max(0, Round(S.Px('margin-right')));
    if ((Bg shr 24) > 0) or (Bw > 0) then
    begin
      if (PadV > 0) or (PadH > 0) or (Rad > 0) then
      begin
        Attrs := Attrs + Format(' pad="%d %d"', [PadV, PadH]);
        if Rad > 0 then Attrs := Attrs + ' radius="' + IntToStr(Rad) + '"';
        if Bw > 0 then
          Attrs := Attrs + ' pillborder="' + ColorAttr(InkToColor(S.Color('border-top-color'), BackCol)) + '"';
      end;
    end
    else
    begin
      Inc(SpL, Max(0, Round(S.Px('padding-left')))); Inc(SpR, Max(0, Round(S.Px('padding-right'))));
    end;
    if SpL > 0 then Open := '<sp w="' + IntToStr(SpL) + '">' + Open;
    if SpR > 0 then Close := Close + '<sp w="' + IntToStr(SpR) + '">';
    if Attrs <> '' then begin Open := Open + '<font' + Attrs + '>'; Close := '</font>' + Close end;
    if (WeightOf(S) >= 600) and (WeightOf(P) < 600) then begin Open := Open + '<b>'; Close := '</b>' + Close end;
    if (S.Keyword('font-style') <> 'normal') and (P.Keyword('font-style') = 'normal') then
    begin
      Open := Open + '<i>'; Close := '</i>' + Close;
    end;
    { underline and strike-through reach every descendant }
    V2 := S.Keyword('text-decoration-line');
    if (Pos('underline', V2) > 0) and (Pos('u', Deco) = 0) then
    begin
      Open := Open + '<u>'; Close := '</u>' + Close; Deco := Deco + 'u';
    end;
    if (Pos('line-through', V2) > 0) and (Pos('s', Deco) = 0) then
    begin
      Open := Open + '<s>'; Close := '</s>' + Close; Deco := Deco + 's';
    end;
    if (E.Name = 'a') and E.HasAttribute('href') then
    begin
      Href := StringReplace(HTMLEscape(E.GetAttribute('href')), '"', '&quot;', [rfReplaceAll]);
      Open := '<a href="' + Href + '">' + Open; Close := Close + '</a>';
      Targets.Add(E.GetAttribute('target')); Titles.Add(E.GetAttribute('title'));
    end;
    if PendingSpace and (Open <> '') then
    begin
      { the space before an element belongs before it, not inside its pill }
      Put(' '); PendingSpace := False;
    end;
    Put(Open);
    Generated(E, 'before');
    C := E.FirstChild;
    while C <> nil do
    begin
      Node(C, S, Deco);
      C := C.NextSibling;
    end;
    Generated(E, 'after');
    if Sub then ;
    Put(Close);
  end;

  { the text decorations a block and its block ancestors carry to it }
  function BlockDeco: string;
  var X: TInkNode; St: TInkStyle; D: string;
  begin
    Result := '';
    X := OwnerEl;
    while (X <> nil) and (X.Kind = inkElement) do
    begin
      St := FStyler.StyleOf(X);
      if St <> nil then
      begin
        D := St.Keyword('text-decoration-line');
        if (Pos('underline', D) > 0) and (Pos('u', Result) = 0) then Result := Result + 'u';
        if (Pos('line-through', D) > 0) and (Pos('s', Result) = 0) then Result := Result + 's';
        if (St.Keyword('float') <> 'none') or (St.Keyword('position') = 'absolute') then Break;
      end;
      X := X.Parent;
    end;
  end;

  { a link round the whole block, the way a card is written: <a><div>... }
  function BlockLink: TInkNode;
  var X: TInkNode;
  begin
    X := OwnerEl;
    while (X <> nil) and (X.Kind = inkElement) do
    begin
      if (X.Name = 'a') and X.HasAttribute('href') then Exit(X);
      X := X.Parent;
    end;
    Result := nil;
  end;

  { what is behind the words: the nearest background that is not clear }
  function BackOf(X: TInkBox): TColor;
  var C: TInkRGBA;
  begin
    while X <> nil do
    begin
      if not X.Anon then
      begin
        C := X.Style.Color('background-color');
        if (C shr 24) = 255 then Exit(TColor(C and $FFFFFF));
      end;
      X := X.Parent;
    end;
    Result := FCanvasBack;
  end;

var Deco: string; LinkNode: TInkNode; LangCls: string; Kid: TInkNode;
begin
  { the element the run belongs to: its own, or its parent box's }
  OwnerEl := ABox.Node;
  if ABox.PseudoOf <> nil then OwnerEl := ABox.PseudoOf
  else if OwnerEl = nil then
  begin
    if (ABox.Parent <> nil) and (ABox.Parent.Node <> nil) then OwnerEl := ABox.Parent.Node;
  end;
  Base := ABox.Style;
  BackCol := BackOf(ABox);
  B.Tree := True;
  B.TreeBox := ABox;
  B.FoldHead := -1;
  if OwnerEl <> nil then begin B.Tag := OwnerEl.Name; B.CSSClass := OwnerEl.GetAttribute('class') end
  else B.Tag := 'p';
  B.PointSize := -Max(1, Round(Base.FontSize));
  B.TextColor := InkToColor(Base.Color('color'), BackCol);
  B.FaceName := FontFamilyFace(Base.Value('font-family'));
  B.Bold := False;
  B.BackColor := clNone;
  B.Indent := 0; B.Padding := 0; B.GapBefore := 0; B.GapAfter := 0;
  B.LineHeight := Max(0, LinePixels(Base));
  V := Base.Keyword('white-space');
  B.NoWrap := (V = 'pre') or (V = 'nowrap');
  B.Pre := (V = 'pre') or (V = 'pre-wrap') or (V = 'break-spaces');
  Targets := TStringList.Create; Titles := TStringList.Create;
  try
    Out_ := ''; PendingSpace := False; AtStart := True;
    B.Marker := '';
    B.MarkerHangs := True;
    if ABox.Marker <> '' then
    begin
      if ABox.MarkerInside then
      begin
        Put(HTMLEscape(ABox.Marker) + ' ');
        B.MarkerHangs := False;
      end
      else B.Marker := ABox.Marker;
    end;
    Deco := BlockDeco;
    { in a see-through box the words are not there to read or find }
    Faded := ABox;
    while (Faded <> nil) and (Faded.Anon or (CSSFloat(Faded.Style.Value('opacity'), 1) > 0)) do
      Faded := Faded.Parent;
    if Faded = nil then
    begin
      if ABox.PseudoOf <> nil then Generated(ABox.PseudoOf, ABox.Pseudo)
      else if ABox.InlineBefore and (OwnerEl <> nil) then Generated(OwnerEl, 'before');
      for I := 0 to High(ABox.Inline) do
      begin
        N := ABox.Inline[I];
        if N.Kind = inkText then Words(N.Data, FStyler.StyleOf(N.Parent))
        else if FStyler.StyleOf(N.Parent) <> nil then Element(N, FStyler.StyleOf(N.Parent), Deco)
        else Element(N, Base, Deco);
      end;
      if (ABox.PseudoOf = nil) and ABox.InlineAfter and (OwnerEl <> nil) then Generated(OwnerEl, 'after');
    end;
    { the run as a whole: its alignment, its own weight and slant, the
      decoration and link it is wrapped in }
    Head := ''; Tail := '';
    V := Base.Keyword('text-align');
    if (V = 'center') or (V = '-webkit-center') then Head := '<center>'
    else if (V = 'right') or (V = 'end') or (V = '-webkit-right') then Head := '<right>';
    if WeightOf(Base) >= 600 then begin Head := Head + '<b>'; Tail := '</b>' + Tail end;
    if Base.Keyword('font-style') <> 'normal' then begin Head := Head + '<i>'; Tail := '</i>' + Tail end;
    if Pos('u', Deco) > 0 then begin Head := Head + '<u>'; Tail := '</u>' + Tail end;
    if Pos('s', Deco) > 0 then begin Head := Head + '<s>'; Tail := '</s>' + Tail end;
    LinkNode := BlockLink;
    if LinkNode <> nil then
    begin
      Head := Head + '<a href="' + StringReplace(HTMLEscape(LinkNode.GetAttribute('href')), '"', '&quot;',
        [rfReplaceAll]) + '">';
      Tail := '</a>' + Tail;
      Targets.Insert(0, LinkNode.GetAttribute('target')); Titles.Insert(0, LinkNode.GetAttribute('title'));
    end;
    if Out_ = '' then B.Source := '' else B.Source := Head + Out_ + Tail;
    SetLength(B.LinkTargets, Targets.Count);
    for I := 0 to Targets.Count - 1 do B.LinkTargets[I] := Targets[I];
    SetLength(B.LinkTitles, Titles.Count);
    for I := 0 to Titles.Count - 1 do B.LinkTitles[I] := Titles[I];
  finally Targets.Free; Titles.Free end;
  { a code block: its text for the header's Copy, and colored when the
    page wrote <pre><code> and colored nothing itself }
  if (OwnerEl <> nil) and (OwnerEl.Name = 'pre') and (ABox.Node = OwnerEl) then
  begin
    B.Code := TrimRight(OwnerEl.TextContent);
    { the header is a shade of the block's own background }
    if (ABox.Style.Color('background-color') shr 24) > 0 then B.BackColor := BackCol;
    LangCls := InkCodeLanguage(OwnerEl.GetAttribute('class'));
    Kid := OwnerEl.FirstElementChild;
    if (Kid <> nil) and (Kid.Name = 'code') and (LangCls = '') then
      LangCls := InkCodeLanguage(Kid.GetAttribute('class'));
    B.CodeLanguage := LangCls;
    if (Kid <> nil) and (Kid.Name = 'code') and (Kid.FirstElementChild = nil) then
    begin
      V := CodeMarkup(B.Code, LangCls);
      if V <> '' then B.Source := V;
    end;
  end;
end;

{ ---------------------------------------------------------- building }

procedure TInkCustomPage.TreeStyle(AWidth: Integer);
begin
  ResetStyler;
  FStyler.Media.Width := AWidth;
  { the control's own say first; the host's sheet and the page's win }
  FStyler.AddSheet(ImageFitSheet);
  if FTextFormat = itfMarkdown then FStyler.AddSheet(MarkdownSheet);
  if FStyleSheet.Count > 0 then FStyler.AddSheet(FStyleSheet.Text, FLocation);
  FStyler.AddDocumentSheets(FDocument, FLocation);
  FStyler.Compute(FDocument);
  FStyled := True;
  FTreeKey := FStyler.MediaKey(AWidth);
end;

{ a document's boxes, and a block for each run of words and each picture in
  them, put among the page's blocks at S.BlockFrom }
procedure TInkCustomPage.BuildSection(S: TInkTreeSection);
var PendingIds: string; Made: TList; I: Integer;

  procedure Ids(N: TInkNode);
  begin
    if N = nil then Exit;
    if N.Id <> '' then PendingIds := Trim(PendingIds + ' ' + N.Id);
  end;

  procedure Walk(Box: TInkBox);
  var I: Integer; B: TInkPageBlock; LinkNode: TInkNode; Det: TInkNode;
  begin
    Ids(Box.Node);
    if Box.Kind = ibkText then
    begin
      B := TInkPageBlock.Create;
      TreeText(Box, B);
      B.Anchor := Trim(PendingIds + ' ' + B.Anchor); PendingIds := '';
      { a <summary>: the fold it opens and shuts }
      if (Box.Node <> nil) and (Box.Node.Name = 'summary') and (Box.Node.Parent <> nil) and
        (Box.Node.Parent.Name = 'details') then
      begin
        Det := Box.Node.Parent;
        B.FoldHead := Length(S.Folds);
        SetLength(S.Folds, Length(S.Folds) + 1);
        S.Folds[High(S.Folds)] := Det;
      end;
      Box.Data := B;
      Made.Add(B);
    end
    else if Box.Kind = ibkImage then
    begin
      B := TInkPageBlock.Create;
      B.Tree := True; B.TreeBox := Box;
      B.FoldHead := -1;
      B.Tag := Box.Node.Name;
      B.Anchor := PendingIds; PendingIds := '';
      B.BackColor := clNone;
      if Box.Node.Name = 'img' then
      begin
        B.ImageSrc := ResolveURL(Box.Node.GetAttribute('src'));
        if B.ImageSrc <> '' then LoadPicture(B);
        LinkNode := Box.Node.Parent;
        while (LinkNode <> nil) and (LinkNode.Kind = inkElement) and not
          ((LinkNode.Name = 'a') and LinkNode.HasAttribute('href')) do LinkNode := LinkNode.Parent;
        if (LinkNode <> nil) and (LinkNode.Kind = inkElement) then
        begin
          B.LinkHref := StringReplace(HTMLEscape(LinkNode.GetAttribute('href')), '"', '&quot;', [rfReplaceAll]);
          B.LinkTarget := LinkNode.GetAttribute('target');
        end;
        if (B.Picture.Graphic = nil) and (Box.Node.GetAttribute('alt') <> '') then
        begin
          { a picture that did not come is its words }
          Box.Kind := ibkText;
          TreeText(Box, B);
          B.Source := HTMLEscape(Box.Node.GetAttribute('alt'));
          if B.LinkHref <> '' then
          begin
            B.Source := '<a href="' + B.LinkHref + '">' + B.Source + '</a>';
            SetLength(B.LinkTargets, 1); B.LinkTargets[0] := B.LinkTarget;
            B.LinkHref := '';
          end;
        end;
      end;
      Box.Data := B;
      Made.Add(B);
    end;
    for I := 0 to Box.Count - 1 do Walk(Box[I]);
  end;

begin
  if FTreeMeasure = nil then
  begin
    FTreeMeasure := TPageMeasure.Create;
    TPageMeasure(FTreeMeasure).Page := Self;
  end;
  FreeAndNil(S.Layout);
  S.Layout := TInkLayout.Create(FStyler, TPageMeasure(FTreeMeasure));
  S.Layout.BuildFrom(S.Doc);
  SetLength(S.Folds, 0);
  FLayoutBase := ControlFontPixels;
  PendingIds := '';
  Made := TList.Create;
  try
    if S.Layout.Root <> nil then Walk(S.Layout.Root);
    if PendingIds <> '' then
    begin
      { ids at the very end still lead somewhere }
      Made.Add(TInkPageBlock.Create);
      TInkPageBlock(Made[Made.Count - 1]).Anchor := PendingIds;
      TInkPageBlock(Made[Made.Count - 1]).Tree := True;
    end;
    for I := 0 to Made.Count - 1 do
    begin
      TInkPageBlock(Made[I]).Section := S;
      TInkPageBlock(Made[I]).Entry := S.Item;
      FBlocks.Insert(S.BlockFrom + I, Made[I]);
    end;
    S.BlockCount := Made.Count;
  finally Made.Free end;
end;

{ a document's blocks taken out of the page's and freed }
procedure TInkCustomPage.ClearSectionBlocks(S: TInkTreeSection);
var I: Integer;
begin
  for I := S.BlockFrom + S.BlockCount - 1 downto S.BlockFrom do
  begin
    FAnimated.Remove(FBlocks[I]);
    TObject(FBlocks[I]).Free;
    FBlocks.Delete(I);
  end;
  S.BlockCount := 0;
  if FRenderCache <> nil then FRenderCache.Clear;
  SetLength(FTreePaint, 0);
  FHoverBlock := -1; FRunBlock := nil;
end;

{ where each item's blocks start, and each block's place, from AFromItem on }
procedure TInkCustomPage.Renumber(AFromItem: Integer);
var I, K, N: Integer; It: TObject;
begin
  N := 0;
  if AFromItem > 0 then
  begin
    It := TObject(FItems[AFromItem - 1]);
    if It is TInkTreeSection then N := TInkTreeSection(It).BlockFrom + TInkTreeSection(It).BlockCount
    else N := TInkPageBlock(It).Index + 1;
  end;
  for I := AFromItem to FItems.Count - 1 do
  begin
    It := TObject(FItems[I]);
    if It is TInkTreeSection then
    begin
      TInkTreeSection(It).Item := I;
      TInkTreeSection(It).BlockFrom := N;
      for K := 0 to TInkTreeSection(It).BlockCount - 1 do
      begin
        TInkPageBlock(FBlocks[N + K]).Index := N + K;
        TInkPageBlock(FBlocks[N + K]).Entry := I;
      end;
      Inc(N, TInkTreeSection(It).BlockCount);
    end
    else
    begin
      TInkPageBlock(It).Entry := I;
      TInkPageBlock(It).Index := N;
      Inc(N);
    end;
  end;
end;

function TInkCustomPage.AddSection(ADoc: TInkDocument; AOwns: Boolean): TInkTreeSection;
begin
  Result := TInkTreeSection.Create;
  Result.Doc := ADoc; Result.OwnsDoc := AOwns;
  Result.Item := FItems.Count;
  Result.BlockFrom := FBlocks.Count;
  Result.Back := clNone;
  FItems.Add(Result);
  if FStyler = nil then ResetStyler;
  { the page's own document was styled with its sheets; anything else is
    styled now, with what the styler has }
  if ADoc <> FDocument then
  begin
    Result.StyleMark := FStyler.Mark;
    FStyler.Include(ADoc);
  end;
  BuildSection(Result);
  Renumber(Result.Item);
end;

procedure TInkCustomPage.ResetStyler;
begin
  if FStyler = nil then
  begin
    FStyler := TInkStyler.Create;
    FStyler.OnFetch := @FetchSheet;
  end;
  FStyler.Clear;
  FStyler.Media.Width := TreeViewWidth;
  if ClientHeight > 0 then FStyler.Media.Height := ClientHeight else FStyler.Media.Height := 768;
  FStyler.Media.Dark := GetActiveColorScheme = icsDark;
  FStyler.CanvasColor := Cardinal(ColorToRGB(Color)) or $FF000000;
  FStyler.CanvasTextColor := Cardinal(ColorToRGB(Font.Color)) or $FF000000;
  FStyler.MediumFont := ControlFontPixels;
  FCanvasBack := Color;
end;

{ the window's width less the scrollbar: what the page is laid out in }
function TInkCustomPage.TreeViewWidth: Integer;
begin
  Result := Max(40, ClientWidth - FScroll.Width);
  if ClientWidth <= 0 then Result := 1024;
end;

function TInkCustomPage.ControlFontPixels: Integer;
begin
  if Font.Height <> 0 then Result := Abs(Font.Height)
  else if Font.Size > 0 then Result := Round(Font.Size * 4 / 3)
  else Result := 16;
end;

{ the canvas: the root's background, or the body's when the root has none }
function TInkCustomPage.TreeCanvasBack: TColor;
var C: TInkRGBA;
begin
  Result := Color;
  if (FDocument = nil) or (FStyler = nil) then Exit;
  if FDocument.DocumentElement <> nil then
  begin
    C := FStyler.StyleOf(FDocument.DocumentElement).Color('background-color');
    if (C shr 24) > 0 then Exit(InkToColor(C, Color));
  end;
  if (FDocument.Body <> nil) and (FStyler.StyleOf(FDocument.Body) <> nil) then
  begin
    C := FStyler.StyleOf(FDocument.Body).Color('background-color');
    if (C shr 24) > 0 then Exit(InkToColor(C, Color));
  end;
end;

{ ---------------------------------------------------------- laying out }

function TInkCustomPage.PageStyle(ABody: Boolean): TInkStyle;
begin
  Result := nil;
  if (FDocument = nil) or (FStyler = nil) or not FStyled then Exit;
  if ABody then Result := FStyler.StyleOf(FDocument.Body)
  else Result := FStyler.StyleOf(FDocument.DocumentElement);
end;

function TInkCustomPage.PageValue(const AProp: string): string;
begin
  Result := 'auto';
  if PageStyle(False) <> nil then Result := PageStyle(False).Value(AProp);
  if ((Result = 'auto') or (Result = '')) and (PageStyle(True) <> nil) then
    Result := PageStyle(True).Value(AProp);
  if Result = '' then Result := 'auto';
end;

{ a document at Y: its boxes laid out at the column's width and moved
  there, and its blocks put where their boxes are }
procedure TInkCustomPage.LaySection(S: TInkTreeSection; ALeft, AWidth: Integer;
  var Y, Pending: Integer);

  procedure Place(Box: TInkBox);
  var I: Integer; B: TInkPageBlock;
  begin
    B := TInkPageBlock(Box.Data);
    if B <> nil then
    begin
      B.RunsReady := False;
      if Box.Kind = ibkText then
      begin
        if B.WrapWidth <> Box.TextW then TreeTextHeight(B, Box.TextW);
        B.Bounds := Rect(Box.TextX, Box.TextY, Box.TextX + Box.TextW, Box.TextY + B.TreeTextH);
        B.TextBounds := Rect(Box.TextX, Box.TextY + B.CodeHead, Box.TextX + Box.TextW, B.Bounds.Bottom);
      end
      else
      begin
        B.Bounds := Box.BorderRect;
        B.TextBounds := B.Bounds;
        B.ImageRect := Rect(Box.ContentX, Box.ContentY, Box.ContentX + Box.ContentW, Box.ContentY + Box.ContentH);
        B.Wrapped := '';
      end;
    end;
    for I := 0 to Box.Count - 1 do Place(Box[I]);
  end;

begin
  StyleSection(S);
  Inc(Y, Max(Pending, S.GapBefore)); Pending := 0;
  S.Left := ALeft + S.Indent; S.Top := Y;
  S.Width := Max(20, AWidth - S.Indent);
  S.Height := 0;
  if (S.Layout <> nil) and (S.Layout.Root <> nil) then
  begin
    S.Layout.Run(S.Width, Max(1, ClientHeight));
    S.Layout.Root.Shift(S.Left, S.Top);
    Place(S.Layout.Root);
    S.Height := S.Layout.Height;
  end;
  Inc(Y, S.Height); Pending := S.GapAfter;
end;

{ ----------------------------------------------------------- painting }

function Positioned(B: TInkBox): Boolean;
begin
  Result := not B.Anon and (B.Style.Keyword('position') <> 'static');
end;

function ZIndex(B: TInkBox): Integer;
begin
  Result := 0;
  if not B.Anon then Result := StrToIntDef(B.Style.Keyword('z-index'), 0);
end;

{ the order CSS paints in: each box's background under its words, floats
  over the flow, positioned boxes last, by z-index - and what a box with
  overflow: hidden holds, cut to it }
procedure TInkCustomPage.TreePaintOrder;
var N: Integer;

  procedure Push(ABox: TInkBox; ABlock: Integer; const AClip: TRect; AClipped: Boolean);
  begin
    if N = Length(FTreePaint) then SetLength(FTreePaint, N * 2 + 64);
    FTreePaint[N].Box := ABox; FTreePaint[N].Block := ABlock;
    FTreePaint[N].Clip := AClip; FTreePaint[N].Clipped := AClipped;
    FTreePaint[N].Section := nil;
    Inc(N);
  end;

  procedure Atomic(Root: TInkBox; const AClip: TRect; AClipped: Boolean);
  var Decos, Texts, Floats, Later: TFPList; Clips: array of TRect; Clipped: array of Boolean;
    I, J, K: Integer; X: TInkBox;

    procedure Note(L: TFPList; B: TInkBox; const C: TRect; HasClip: Boolean);
    begin
      L.Add(B);
      SetLength(Clips, Length(Clips) + 1); SetLength(Clipped, Length(Clipped) + 1);
      Clips[High(Clips)] := C; Clipped[High(Clipped)] := HasClip;
      B.Tag := High(Clips);
    end;

    procedure Gather(B: TInkBox; const C: TRect; HasClip, IsRoot: Boolean);
    var Q: Integer; NC: TRect; NH, Seen: Boolean; O: string;
    begin
      { a box made fully transparent takes everything in it along }
      if not B.Anon and (CSSFloat(B.Style.Value('opacity'), 1) <= 0) then Exit;
      if not IsRoot and (Positioned(B) or B.Absolute) then begin Note(Later, B, C, HasClip); Exit end;
      if not IsRoot and B.Floating then begin Note(Floats, B, C, HasClip); Exit end;
      { a hidden one keeps its room, and what is in it may still show }
      O := '';
      if B.Style <> nil then O := B.Style.Keyword('visibility');
      Seen := (O <> 'hidden') and (O <> 'collapse');
      { a masked box is most often an icon: its color cut to a picture's
        shape.  Without the mask it is a solid block, so it goes unpainted }
      if Seen and ((B.Style = nil) or (B.Style.Keyword('mask-image') = 'none') or
        (B.Style.Keyword('mask-image') = '')) then Note(Decos, B, C, HasClip);
      if Seen and (B.Data <> nil) then Note(Texts, B, C, HasClip);
      NC := C; NH := HasClip;
      if not B.Anon then
      begin
        O := B.Style.Keyword('overflow-x') + ' ' + B.Style.Keyword('overflow-y');
        if (Pos('hidden', O) > 0) or (Pos('clip', O) > 0) then
        begin
          if NH then IntersectRect(NC, NC, B.PaddingRect) else NC := B.PaddingRect;
          NH := True;
        end;
      end;
      for Q := 0 to B.Count - 1 do Gather(B[Q], NC, NH, False);
    end;

  begin
    Decos := TFPList.Create; Texts := TFPList.Create; Floats := TFPList.Create; Later := TFPList.Create;
    try
      Clips := nil; Clipped := nil;
      Gather(Root, AClip, AClipped, True);
      for I := 0 to Decos.Count - 1 do
      begin
        X := TInkBox(Decos[I]);
        Push(X, -1, Clips[X.Tag], Clipped[X.Tag]);
      end;
      for I := 0 to Floats.Count - 1 do
      begin
        X := TInkBox(Floats[I]);
        Atomic(X, Clips[X.Tag], Clipped[X.Tag]);
      end;
      for I := 0 to Texts.Count - 1 do
      begin
        X := TInkBox(Texts[I]);
        Push(nil, TInkPageBlock(X.Data).Index, Clips[X.Tag], Clipped[X.Tag]);
      end;
      { positioned boxes by z-index, in the order written within one }
      for I := 1 to Later.Count - 1 do
      begin
        X := TInkBox(Later[I]); J := I - 1;
        while (J >= 0) and (ZIndex(TInkBox(Later[J])) > ZIndex(X)) do
        begin
          Later[J + 1] := Later[J]; Dec(J);
        end;
        Later[J + 1] := X;
      end;
      for I := 0 to Later.Count - 1 do
      begin
        X := TInkBox(Later[I]);
        K := X.Tag;
        Atomic(X, Clips[K], Clipped[K]);
      end;
    finally Decos.Free; Texts.Free; Floats.Free; Later.Free end;
  end;

var I: Integer; It: TObject; S: TInkTreeSection;
begin
  N := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    It := TObject(FItems[I]);
    if It is TInkTreeSection then
    begin
      S := TInkTreeSection(It);
      if S.Back <> clNone then
      begin
        Push(nil, -1, Rect(0, 0, 0, 0), False);
        FTreePaint[N - 1].Section := S;
      end;
      if (S.Layout <> nil) and (S.Layout.Root <> nil) then
        Atomic(S.Layout.Root, Rect(0, 0, 0, 0), False);
    end
    else Push(nil, TInkPageBlock(It).Index, Rect(0, 0, 0, 0), False);
  end;
  SetLength(FTreePaint, N);
end;

{ a box's background and borders }
procedure TInkCustomPage.TreePaintBox(ACanvas: TCanvas; ABox: TInkBox);
var S: TInkStyle; R, P: TRect; Bg: TInkRGBA; Behind, Col: TColor; Radius, I, W, X, Len_: Integer;
  St, Img: string; Up: TInkBox; Words: TStringArray;

  function SideColor(const ASide: string): TColor;
  begin
    Result := InkToColor(S.Color('border-' + ASide + '-color'), Behind);
  end;

  function Shade(C: TColor; ADark: Boolean): TColor;
  begin
    C := ColorToRGB(C);
    if ADark then Result := RGBToColor(Red(C) * 2 div 3, Green(C) * 2 div 3, Blue(C) * 2 div 3)
    else Result := MixColor(C, clWhite, 0.6);
  end;

  { one side, in the style it asks for }
  procedure Side(const ASide: string; ARect: TRect; AWidth: Integer; AHorizontal: Boolean; ADarkInset: Boolean);
  var Style_: string; C: TColor; K, Step: Integer;
  begin
    if AWidth <= 0 then Exit;
    Style_ := S.Keyword('border-' + ASide + '-style');
    if (Style_ = 'none') or (Style_ = 'hidden') then Exit;
    C := SideColor(ASide);
    if (Style_ = 'inset') or (Style_ = 'groove') then C := Shade(C, ADarkInset)
    else if (Style_ = 'outset') or (Style_ = 'ridge') then C := Shade(C, not ADarkInset);
    ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := C;
    if (Style_ = 'dashed') or (Style_ = 'dotted') then
    begin
      if Style_ = 'dotted' then Step := AWidth else Step := AWidth * 3;
      Step := Max(2, Step);
      if AHorizontal then
      begin
        K := ARect.Left;
        while K < ARect.Right do
        begin
          ACanvas.FillRect(Rect(K, ARect.Top, Min(K + Step, ARect.Right), ARect.Bottom));
          Inc(K, Step * 2);
        end;
      end
      else
      begin
        K := ARect.Top;
        while K < ARect.Bottom do
        begin
          ACanvas.FillRect(Rect(ARect.Left, K, ARect.Right, Min(K + Step, ARect.Bottom)));
          Inc(K, Step * 2);
        end;
      end;
    end
    else if (Style_ = 'double') and (AWidth >= 3) then
    begin
      if AHorizontal then
      begin
        ACanvas.FillRect(Rect(ARect.Left, ARect.Top, ARect.Right, ARect.Top + AWidth div 3));
        ACanvas.FillRect(Rect(ARect.Left, ARect.Bottom - AWidth div 3, ARect.Right, ARect.Bottom));
      end
      else
      begin
        ACanvas.FillRect(Rect(ARect.Left, ARect.Top, ARect.Left + AWidth div 3, ARect.Bottom));
        ACanvas.FillRect(Rect(ARect.Right - AWidth div 3, ARect.Top, ARect.Right, ARect.Bottom));
      end;
    end
    else ACanvas.FillRect(ARect);
  end;

begin
  if ABox.Anon then Exit;
  S := ABox.Style;
  R := ABox.BorderRect;
  OffsetRect(R, 0, -FScroll.Position);
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  { what is behind: the nearest solid background further out }
  Behind := FCanvasBack;
  Up := ABox.Parent;
  while Up <> nil do
  begin
    if not Up.Anon and ((Up.Style.Color('background-color') shr 24) = 255) then
    begin
      Behind := TColor(Up.Style.Color('background-color') and $FFFFFF);
      Break;
    end;
    Up := Up.Parent;
  end;
  Bg := S.Color('background-color');
  { a gradient is drawn as its first color }
  if (Bg shr 24) = 0 then
  begin
    Img := S.Value('background-image');
    if Pos('gradient(', LowerCase(Img)) > 0 then
    begin
      Words := StringReplace(StringReplace(Copy(Img, Pos('(', Img) + 1, MaxInt), ',', ' ', [rfReplaceAll]),
        ')', ') ', [rfReplaceAll]).Split([' '], TStringSplitOptions.ExcludeEmpty);
      for I := 0 to High(Words) do
        if InkParseColor(Words[I], Bg, FStyler.Media.Dark) then Break;
    end;
  end;
  { the root's background is the canvas's, and so is the body's when the
    root has none }
  if (ABox.Parent = nil) or ((ABox.Node <> nil) and (ABox.Node.Name = 'body') and (ABox.Parent.Parent = nil) and
    ((FStyler.StyleOf(ABox.Parent.Node).Color('background-color') shr 24) = 0)) then Bg := 0;
  Radius := Round(S.Px('border-top-left-radius', ABox.W));
  Radius := Max(Radius, Round(S.Px('border-top-right-radius', ABox.W)));
  { a radius too big for the box is as round as the box can be: a pill }
  Radius := Min(Radius, Min(ABox.W, ABox.H) div 2);
  if (Bg shr 24) > 0 then
  begin
    Col := InkToColor(Bg, Behind);
    ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := Col;
    if Radius > 0 then
    begin
      ACanvas.Pen.Color := Col; ACanvas.Pen.Width := 1;
      ACanvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius * 2, Radius * 2);
    end
    else ACanvas.FillRect(R);
  end;
  with ABox.Border do
    if (Left > 0) or (Top > 0) or (Right > 0) or (Bottom > 0) then
    begin
      if (Radius > 0) and (Left = Top) and (Top = Right) and (Right = Bottom) and
        (S.Keyword('border-top-style') <> 'none') and (S.Keyword('border-top-style') <> 'hidden') then
      begin
        { a round box with one border all round }
        ACanvas.Brush.Style := bsClear;
        ACanvas.Pen.Color := SideColor('top'); ACanvas.Pen.Width := Top;
        P := R; InflateRect(P, -(Top div 2), -(Top div 2));
        ACanvas.RoundRect(P.Left, P.Top, P.Right, P.Bottom, Radius * 2, Radius * 2);
        ACanvas.Pen.Width := 1;
      end
      else
      begin
        Side('top', Rect(R.Left, R.Top, R.Right, R.Top + Top), Top, True, True);
        Side('bottom', Rect(R.Left, R.Bottom - Bottom, R.Right, R.Bottom), Bottom, True, False);
        Side('left', Rect(R.Left, R.Top, R.Left + Left, R.Bottom), Left, False, True);
        Side('right', Rect(R.Right - Right, R.Top, R.Right, R.Bottom), Right, False, False);
      end;
    end;
  ACanvas.Brush.Style := bsClear;
  St := ''; W := 0; X := 0; Len_ := 0;
  if (St <> '') or (W <> 0) or (X <> 0) or (Len_ <> 0) then ;
end;

{ disc, circle and square markers are shapes sized from the font, as a
  browser draws them, not the font's own bullet glyphs }
function TInkCustomPage.TreePaintMarker(ACanvas: TCanvas; B: TInkPageBlock;
  const TR: TRect): Boolean;
var TM: TTextMetric; Asc, Desc, Base, D, CX, CY, Em: Integer;
begin
  Result := (B.Marker = '•') or (B.Marker = '◦') or (B.Marker = '▪');
  if not Result then Exit;
  if GetTextMetrics(ACanvas.Handle, TM) then
  begin
    Asc := TM.tmAscent - TM.tmInternalLeading; Desc := TM.tmDescent;
  end
  else begin Asc := Round(ACanvas.TextHeight('Tg') * 0.78); Desc := ACanvas.TextHeight('Tg') - Asc end;
  Base := TR.Top + Asc;
  if B.LineHeight > 0 then Inc(Base, (B.LineHeight - Asc - Desc) div 2);
  if B.PointSize < 0 then Em := -B.PointSize else Em := Max(1, Round(B.PointSize * 96 / 72));
  D := Max(3, Round(Em * 0.3) + 1);
  CX := TR.Left - Round(Em * 0.95); CY := Base - Round(Em * 0.33);
  ACanvas.Pen.Color := B.TextColor; ACanvas.Pen.Width := 1;
  ACanvas.Brush.Color := B.TextColor;
  if B.Marker = '◦' then ACanvas.Brush.Style := bsClear else ACanvas.Brush.Style := bsSolid;
  if B.Marker = '▪' then
    ACanvas.FillRect(Rect(CX - D div 2, CY - D div 2, CX - D div 2 + D, CY - D div 2 + D))
  else
    ACanvas.Ellipse(CX - D div 2, CY - D div 2, CX - D div 2 + D, CY - D div 2 + D);
  ACanvas.Brush.Style := bsClear;
end;

procedure TInkCustomPage.TreeRender(ACanvas: TCanvas);
var I: Integer; R: TRect; It: TInkTreePaint; SelFrom, SelTo: TInkPagePosition; Selected: Boolean;
  B: TInkPageBlock; ViewTop, ViewBottom: Integer;
begin
  Layout;
  Selected := HasSelection;
  SelFrom := SelectionStart; SelTo := SelectionEnd;
  ACanvas.Brush.Color := FCanvasBack;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(ClientRect);
  ViewTop := FScroll.Position; ViewBottom := ViewTop + ClientHeight;
  for I := 0 to High(FTreePaint) do
  begin
    It := FTreePaint[I];
    if It.Section <> nil then
    begin
      { a memo entry's band, behind the document it shows }
      with TInkTreeSection(It.Section) do R := Rect(Left, Top, Left + Width, Top + Height);
      if (R.Bottom < ViewTop) or (R.Top > ViewBottom) then Continue;
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := TInkTreeSection(It.Section).Back;
      ACanvas.FillRect(Rect(R.Left, R.Top - ViewTop, R.Right, R.Bottom - ViewTop));
      Continue;
    end;
    if It.Box <> nil then R := TInkBox(It.Box).BorderRect
    else
    begin
      if (It.Block < 0) or (It.Block >= FBlocks.Count) then Continue;
      B := TInkPageBlock(FBlocks[It.Block]);
      R := B.Bounds;
      { the marker hangs to the left }
      Dec(R.Left, B.MarkerWidth);
    end;
    if (R.Bottom < ViewTop) or (R.Top > ViewBottom) then Continue;
    if It.Clipped and ((It.Clip.Bottom < ViewTop) or (It.Clip.Top > ViewBottom)) then Continue;
    if It.Box <> nil then
    begin
      { clipped on the canvas, not with SaveDC: GTK3 cannot always restore }
      if It.Clipped then
      begin
        ACanvas.ClipRect := Rect(It.Clip.Left, It.Clip.Top - ViewTop, It.Clip.Right, It.Clip.Bottom - ViewTop);
        ACanvas.Clipping := True;
      end;
      try
        TreePaintBox(ACanvas, TInkBox(It.Box));
      finally
        if It.Clipped then ACanvas.Clipping := False;
      end;
    end
    else
    begin
      { PaintBlock clips to it, in the one save it makes }
      FPaintClipped := It.Clipped;
      FPaintClip := Rect(It.Clip.Left, It.Clip.Top - ViewTop, It.Clip.Right, It.Clip.Bottom - ViewTop);
      try
        PaintBlock(ACanvas, It.Block, Selected, SelFrom, SelTo);
      finally FPaintClipped := False end;
    end;
  end;
  if FScroll.Visible then
    FScroll.RenderTo(ACanvas, Rect(ClientWidth - FScroll.Width, 0, ClientWidth, ClientHeight));
  if FindBarVisible then PaintFindBar(ACanvas);
end;

{ ------------------------------------------------------- finding things }

{ the block under a point of the page: the one it is in, or the nearest }
function TInkCustomPage.TreeBlockAt(X, DocY: Integer; ANearest: Boolean): Integer;
var I, D, Best: Integer; B: TInkPageBlock; R: TRect;
begin
  Result := -1; Best := MaxInt;
  for I := FBlocks.Count - 1 downto 0 do
  begin
    B := TInkPageBlock(FBlocks[I]);
    R := B.Bounds;
    if R.Bottom <= R.Top then Continue;
    if (X >= R.Left - B.MarkerWidth) and (X < R.Right) and (DocY >= R.Top) and (DocY < R.Bottom) then Exit(I);
    if ANearest then
    begin
      if DocY < R.Top then D := (R.Top - DocY) * 4
      else if DocY >= R.Bottom then D := (DocY - R.Bottom + 1) * 4
      else D := 0;
      if X < R.Left then Inc(D, R.Left - X) else if X >= R.Right then Inc(D, X - R.Right + 1);
      if D <= Best then begin Best := D; Result := I end;
    end;
  end;
end;

procedure TInkCustomPage.TreeToggleFold(Index: Integer);
var B: TInkPageBlock; S: TInkTreeSection; D: TInkNode;
begin
  B := TInkPageBlock(FBlocks[Index]);
  S := TInkTreeSection(B.Section);
  if (S = nil) or (B.FoldHead < 0) or (B.FoldHead > High(S.Folds)) then Exit;
  D := S.Folds[B.FoldHead];
  if D.HasAttribute('open') then D.RemoveAttribute('open') else D.SetAttribute('open', '');
  { only this document is styled and laid out again; the selection's
    blocks may be gone }
  ClearSelection;
  FStyler.Restyle(S.Doc);
  ClearSectionBlocks(S);
  BuildSection(S);
  Renumber(S.Item);
  FindAnimations;
  InvalidateLayout(S.Item);
end;
