program LayoutTests;
{ InkLayout: boxes placed where a browser places them, with a pretend
  measurer - every character 8 pixels wide, every line 20 tall - so each
  number can be worked out by hand.  Needs no widgetset. }
{$mode objfpc}{$H+}
uses Classes, SysUtils, DateUtils, Math, InkDOM, InkStyle, InkLayout;

var Failures, Checks: Integer;

procedure Check(OK: Boolean; const What: string);
begin
  Inc(Checks);
  if not OK then
  begin
    Inc(Failures);
    WriteLn('FAIL: ', What);
  end;
end;

type
  TFake = class(TInkLayoutMeasure)
  public
    function TextOf(ABox: TInkBox): string;
    function TextHeight(ABox: TInkBox; AWidth: Integer): Integer; override;
    procedure TextWidths(ABox: TInkBox; out AMin, AMax: Integer); override;
    procedure ImageSize(ABox: TInkBox; out AWidth, AHeight: Integer); override;
  end;

function TFake.TextOf(ABox: TInkBox): string;
var I: Integer; S: string;
begin
  S := '';
  for I := 0 to High(ABox.Inline) do S := S + ABox.Inline[I].TextContent;
  { white space collapses, as on a page }
  S := Trim(StringReplace(StringReplace(S, #10, ' ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]));
  while Pos('  ', S) > 0 do S := StringReplace(S, '  ', ' ', [rfReplaceAll]);
  if ABox.Marker <> '' then S := S;
  Result := S;
end;

{ words wrapped to the width, 8 pixels a character }
function TFake.TextHeight(ABox: TInkBox; AWidth: Integer): Integer;
var Words: TStringArray; I, Line, Lines: Integer;
begin
  Words := TextOf(ABox).Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then Exit(20);
  Lines := 1; Line := 0;
  for I := 0 to High(Words) do
  begin
    if (Line > 0) and (Line + 8 + 8 * Length(Words[I]) > AWidth) then
    begin
      Inc(Lines); Line := 0;
    end;
    if Line > 0 then Inc(Line, 8);
    Inc(Line, 8 * Length(Words[I]));
  end;
  Result := 20 * Lines;
end;

procedure TFake.TextWidths(ABox: TInkBox; out AMin, AMax: Integer);
var Words: TStringArray; I: Integer;
begin
  Words := TextOf(ABox).Split([' '], TStringSplitOptions.ExcludeEmpty);
  AMin := 0;
  for I := 0 to High(Words) do AMin := Max(AMin, 8 * Length(Words[I]));
  AMax := 8 * Length(TextOf(ABox));
end;

procedure TFake.ImageSize(ABox: TInkBox; out AWidth, AHeight: Integer);
begin
  AWidth := StrToIntDef(ABox.Node.GetAttribute('data-w'), 0);
  AHeight := StrToIntDef(ABox.Node.GetAttribute('data-h'), 0);
end;

var
  Doc: TInkDocument; Styler: TInkStyler; Fake: TFake; Lay: TInkLayout;

procedure Load(const HTML: string; AWidth: Integer = 800);
begin
  FreeAndNil(Lay); FreeAndNil(Styler); FreeAndNil(Doc);
  Doc := InkParseHTML(HTML);
  Styler := TInkStyler.Create;
  Styler.Media.Width := AWidth; Styler.Media.Height := 600;
  Styler.AddDocumentSheets(Doc, '');
  Styler.Compute(Doc);
  Lay := TInkLayout.Create(Styler, Fake);
  Lay.BuildFrom(Doc);
  Lay.Run(AWidth, 600);
end;

{ the box made from the element a selector finds }
function BoxOf(const Selector: string): TInkBox;
var N: TInkNode;
  function Find(B: TInkBox): TInkBox;
  var I: Integer;
  begin
    if B.Node = N then Exit(B);
    for I := 0 to B.Count - 1 do
    begin
      Result := Find(B[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;
begin
  Result := nil;
  N := InkQuerySelector(Doc, Selector);
  if (N <> nil) and (Lay.Root <> nil) then Result := Find(Lay.Root);
  if Result = nil then WriteLn('  (no box for ', Selector, ')');
end;

procedure At(const Selector: string; X, Y, W, H: Integer);
var B: TInkBox;
begin
  B := BoxOf(Selector);
  if B = nil then begin Check(False, Selector + ' has no box'); Exit end;
  Check((B.X = X) and (B.Y = Y) and (B.W = W) and (B.H = H),
    Format('%s at %d,%d %dx%d - wanted %d,%d %dx%d', [Selector, B.X, B.Y, B.W, B.H, X, Y, W, H]));
end;

procedure Eq(Got, Wanted: Integer; const What: string);
begin
  Check(Got = Wanted, Format('%s: %d, wanted %d', [What, Got, Wanted]));
end;

procedure FlowChecks;
begin
  { the body's 8px margin and the paragraph's 16 meet: 16 above }
  Load('<!DOCTYPE html><p id=a>hello world</p>');
  At('body', 8, 16, 784, 20);
  At('#a', 8, 16, 784, 20);
  Eq(Lay.Height, 52, 'page height: 16 + 20 + 16');
  { margins between paragraphs collapse to the larger }
  Load('<!DOCTYPE html><style>body{margin:0} p{margin:10px 0} #b{margin-top:30px}</style>' +
    '<p id=a>x</p><p id=b>y</p><p id=c style="margin-top:-15px">z</p>');
  At('#a', 0, 10, 800, 20);
  At('#b', 0, 60, 800, 20);
  Eq(BoxOf('#c').Y, 80 + 10 - 15, 'a negative margin takes from the positive');
  { padding or a border keeps a child's margin inside }
  Load('<!DOCTYPE html><style>body{margin:0} div{padding-top:1px} p{margin:20px 0}</style>' +
    '<div id=d><p id=p>x</p></div>');
  At('#d', 0, 0, 800, 1 + 20 + 20);
  At('#p', 0, 21, 800, 20);
  { width, padding, border; and border-box }
  Load('<!DOCTYPE html><style>body{margin:0} #a{width:200px;padding:10px;border:5px solid}' +
    ' #b{width:200px;padding:10px;border:5px solid;box-sizing:border-box}' +
    ' #c{width:400px;margin:0 auto} #d{max-width:50%} #e{width:50%;min-width:500px}</style>' +
    '<div id=a>x</div><div id=b>x</div><div id=c>x</div><div id=d>x</div><div id=e>x</div>');
  At('#a', 0, 0, 230, 50);
  At('#b', 0, 50, 200, 50);
  At('#c', 200, 100, 400, 20);
  At('#d', 0, 120, 400, 20);
  Eq(BoxOf('#e').W, 500, 'min-width wins over a smaller width');
  { text wraps at the width it is given }
  Load('<!DOCTYPE html><style>body{margin:0} p{width:100px;margin:0}</style>' +
    '<p id=p>aaaa bbbb cccc dddd</p>');
  At('#p', 0, 0, 100, 40);
  { a block holding text and a block: the text is a box of its own }
  Load('<!DOCTYPE html><style>body{margin:0} p{margin:0}</style><div id=d>words <p id=p>para</p> more</div>');
  Eq(BoxOf('#d').Count, 3, 'text, block, text');
  At('#p', 0, 20, 800, 20);
  Eq(BoxOf('#d').H, 60, 'the three lines');
  { display: none makes nothing; an inline block stays in the text }
  Load('<!DOCTYPE html><style>body{margin:0} span{display:inline-block}</style>' +
    '<div id=d>a <span>b</span> c<em style="display:none">gone</em></div>');
  Eq(BoxOf('#d').Count, 0, 'one run of text');
  Check(BoxOf('#d').Kind = ibkText, 'the div is its text');
end;

procedure FloatChecks;
var B: TInkBox;
begin
  Load('<!DOCTYPE html><style>body{margin:0} #f{float:left;width:100px;height:50px}' +
    ' #g{float:right;width:50px;height:30px} p{margin:0} #c{clear:both}</style>' +
    '<div id=f></div><div id=g></div><p id=p>beside</p><p id=c>below</p>');
  At('#f', 0, 0, 100, 50);
  At('#g', 750, 0, 50, 30);
  B := BoxOf('#p');
  Eq(B.TextX, 100, 'text starts after the left float');
  Eq(B.TextW, 650, 'and stops before the right one');
  Eq(BoxOf('#c').Y, 50, 'clear: both goes below them');
  { a context of its own holds its floats }
  Load('<!DOCTYPE html><style>body{margin:0} #o{overflow:hidden} #f{float:left;width:10px;height:70px}</style>' +
    '<div id=o><div id=f></div></div>');
  Eq(BoxOf('#o').H, 70, 'overflow: hidden grows round its float');
end;

procedure FlexChecks;
begin
  Load('<!DOCTYPE html><style>body{margin:0} .r{display:flex;gap:10px} .r>div{flex:1}</style>' +
    '<div class=r id=r><div id=a>a</div><div id=b>b</div><div id=c>c</div></div>', 620);
  At('#a', 0, 0, 200, 20);
  At('#b', 210, 0, 200, 20);
  At('#c', 420, 0, 200, 20);
  Load('<!DOCTYPE html><style>body{margin:0} .r{display:flex;justify-content:space-between;align-items:center}' +
    ' .r>div{width:100px} #t{height:60px}</style>' +
    '<div class=r><div id=a>a</div><div id=t>t</div><div id=c>c</div></div>');
  At('#a', 0, 20, 100, 20);
  At('#t', 350, 0, 100, 60);
  At('#c', 700, 20, 100, 20);
  { a row of items too wide wraps }
  Load('<!DOCTYPE html><style>body{margin:0} .r{display:flex;flex-wrap:wrap} .r>div{width:300px}</style>' +
    '<div class=r><div id=a>a</div><div id=b>b</div><div id=c>c</div></div>', 700);
  At('#c', 0, 20, 300, 20);
  { stretched across the line, shrunk to fit, a margin pushing right }
  Load('<!DOCTYPE html><style>body{margin:0} .r{display:flex} #a{height:40px;width:50px} #b{width:50px}' +
    ' #c{margin-left:auto;width:60px}</style>' +
    '<div class=r><div id=a>a</div><div id=b>b</div><div id=c>c</div></div>');
  At('#b', 50, 0, 50, 40);
  At('#c', 740, 0, 60, 40);
  { a column }
  Load('<!DOCTYPE html><style>body{margin:0} .c{display:flex;flex-direction:column;gap:5px;align-items:flex-start}</style>' +
    '<div class=c><div id=a>aaaa</div><div id=b>bb</div></div>');
  At('#a', 0, 0, 32, 20);
  At('#b', 0, 25, 16, 20);
  { the items shrink to fit, no narrower than their longest word }
  Load('<!DOCTYPE html><style>body{margin:0} .r{display:flex;width:100px} .r>div{width:80px}</style>' +
    '<div class=r><div id=a>aaaaaaaa</div><div id=b>b</div></div>');
  Eq(BoxOf('#a').W, 64, 'shrunk to its longest word');
  Eq(BoxOf('#b').W, 36, 'and its neighbour takes the rest');
end;

function PseudoBox(const Selector, Which: string): TInkBox;
var N: TInkNode;
  function Find(B: TInkBox): TInkBox;
  var I: Integer;
  begin
    if (B.PseudoOf = N) and (B.Pseudo = Which) then Exit(B);
    for I := 0 to B.Count - 1 do
    begin
      Result := Find(B[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;
begin
  Result := nil;
  N := InkQuerySelector(Doc, Selector);
  if (N <> nil) and (Lay.Root <> nil) then Result := Find(Lay.Root);
end;

procedure FixedColumnChecks;
begin
  { a column with a width keeps it; the spare room goes to the others }
  Load('<!DOCTYPE html><style>body{margin:0}</style><table width="100%" cellspacing=0 cellpadding=0><tr>' +
    '<td id=a style="width:50px">a</td><td id=b>bb</td><td id=c>cccc</td></tr></table>', 400);
  Check(BoxOf('#a').W = 50, Format('the column with a width keeps it (%d)', [BoxOf('#a').W]));
  Check(BoxOf('#b').W + BoxOf('#c').W = 350, Format('and the others share the rest (%d, %d)',
    [BoxOf('#b').W, BoxOf('#c').W]));
end;

procedure TableFixChecks;
begin
  { table-layout: fixed shares the width out evenly, whatever the cells hold }
  Load('<!DOCTYPE html><style>body{margin:0} table{width:300px;table-layout:fixed;border-spacing:0}' +
    'td{padding:0}</style><table><tr><td id=a>a</td><td id=b>a much longer cell</td>' +
    '<td id=c></td></tr></table>', 400);
  Check((BoxOf('#a').W = 100) and (BoxOf('#b').W = 100) and (BoxOf('#c').W = 100),
    Format('a fixed table''s columns are equal (%d, %d, %d)', [BoxOf('#a').W, BoxOf('#b').W, BoxOf('#c').W]));
  { cells made blocks go into one cell made for them, and stack }
  Load('<!DOCTYPE html><style>body{margin:0} td{display:block;padding:0}</style>' +
    '<table><tr><td id=a>a</td><td id=b>b</td></tr></table>', 400);
  Check((BoxOf('#a').X = BoxOf('#b').X) and (BoxOf('#b').Y = BoxOf('#a').Y + BoxOf('#a').H),
    Format('cells made blocks stack (%d,%d and %d,%d)', [BoxOf('#a').X, BoxOf('#a').Y, BoxOf('#b').X, BoxOf('#b').Y]));
end;

procedure CenterChecks;
begin
  { <center> centres a table or a block narrower than it }
  Load('<!DOCTYPE html><style>body{margin:0}</style><center><table id=t width="50%"><tr><td>a</td></tr></table>' +
    '<div id=d style="width:100px">b</div></center>', 400);
  Check(BoxOf('#t').X = 100, Format('a table in <center> is centred (%d)', [BoxOf('#t').X]));
  Check(BoxOf('#d').X = 150, Format('and so is a narrow block (%d)', [BoxOf('#d').X]));
end;

procedure PseudoChecks;
var P: TInkBox;
begin
  { a flex container's ::after is an item, sized by its own width }
  Load('<!DOCTYPE html><style>body{margin:0} .f{display:flex}' +
    '.f::after{content:"";width:20px;height:10px;margin-left:4px}</style>' +
    '<div class=f><span id=s>ab</span></div>', 400);
  P := PseudoBox('.f', 'after');
  Check(P <> nil, 'a flex ::after has a box');
  if P <> nil then
    Check((P.X = 20) and (P.Y = 0) and (P.W = 20) and (P.H = 10),
      Format('the flex ::after sits after its sibling (%d,%d %dx%d)', [P.X, P.Y, P.W, P.H]));
  { one in the words joins their run }
  Load('<!DOCTYPE html><style>p{margin:0} p::before{content:"x "}</style><p>ab</p>', 400);
  Check(BoxOf('p').InlineBefore and (PseudoBox('p', 'before') = nil), 'an inline ::before joins the words');
  { a block one stands above them }
  Load('<!DOCTYPE html><style>body{margin:0} div::before{content:"";display:block;height:30px}</style>' +
    '<div>ab</div>', 400);
  P := PseudoBox('div', 'before');
  Check((P <> nil) and (P.H = 30), 'a block ::before has its height');
  Check((BoxOf('div').H = 50), Format('and the words go under it (%d)', [BoxOf('div').H]));
  { nothing where there is no content }
  Load('<!DOCTYPE html><style>.f{display:flex} .f::after{width:20px}</style><div class=f>a</div>', 400);
  Check(PseudoBox('.f', 'after') = nil, 'no content, no box');
end;

procedure GridChecks;
begin
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;grid-template-columns:1fr 2fr 100px}</style>' +
    '<div class=g><div id=a>a</div><div id=b>b</div><div id=c>c</div><div id=d>d</div></div>', 400);
  At('#a', 0, 0, 100, 20);
  At('#b', 100, 0, 200, 20);
  At('#c', 300, 0, 100, 20);
  At('#d', 0, 20, 100, 20);
  { a capped middle column takes what the sides' minimums leave }
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;' +
    'grid-template-columns:minmax(100px,1fr) 20px minmax(0,400px) 20px minmax(100px,1fr)}' +
    '#b{grid-column:3} #c{grid-column:5}</style>' +
    '<div class=g><div id=a>a</div><div id=b>b</div><div id=c>c</div></div>', 600);
  At('#a', 0, 0, 100, 20);
  At('#b', 120, 0, 360, 20);
  At('#c', 500, 0, 100, 20);
  { and once it is full, the sides share the rest }
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;' +
    'grid-template-columns:minmax(100px,1fr) 20px minmax(0,400px) 20px minmax(100px,1fr)}' +
    '#b{grid-column:3} #c{grid-column:5}</style>' +
    '<div class=g><div id=a>a</div><div id=b>b</div><div id=c>c</div></div>', 800);
  At('#a', 0, 0, 180, 20);
  At('#b', 200, 0, 400, 20);
  At('#c', 620, 0, 180, 20);
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;gap:10px;' +
    'grid-template-columns:repeat(auto-fill,minmax(150px,1fr))}</style>' +
    '<div class=g><div id=a>a</div><div id=b>b</div><div id=c>c</div><div id=d>d</div></div>', 500);
  At('#a', 0, 0, 160, 20);
  At('#c', 340, 0, 160, 20);
  At('#d', 0, 30, 160, 20);
  { named areas, and a span }
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;grid-template-columns:100px 1fr;' +
    'grid-template-areas:"head head" "side main"} #h{grid-area:head} #s{grid-area:side} #m{grid-area:main}' +
    ' #x{grid-column:span 2}</style>' +
    '<div class=g><div id=m>main</div><div id=s>side</div><div id=h>head</div><div id=x>x</div></div>', 500);
  At('#h', 0, 0, 500, 20);
  At('#s', 0, 20, 100, 20);
  At('#m', 100, 20, 400, 20);
  At('#x', 0, 40, 500, 20);
  { a row as tall as its tallest, every item stretched }
  Load('<!DOCTYPE html><style>body{margin:0} .g{display:grid;grid-template-columns:100px 100px}</style>' +
    '<div class=g><div id=a>a</div><div id=b>bbb bbb bbb bbb</div></div>');
  At('#a', 0, 0, 100, 40);
end;

procedure TableChecks;
begin
  Load('<!DOCTYPE html><style>body{margin:0} table{border-spacing:0} td{padding:0}</style>' +
    '<table id=t><tr><td id=a>aa</td><td id=b>bbbb</td></tr><tr><td id=c colspan=2>c</td></tr></table>');
  At('#t', 0, 0, 48, 40);
  At('#a', 0, 0, 16, 20);
  At('#b', 16, 0, 32, 20);
  At('#c', 0, 20, 48, 20);
  { a width shares out the room by how much each column could use }
  Load('<!DOCTYPE html><style>body{margin:0} table{border-spacing:0;width:100%} td{padding:0}</style>' +
    '<table><tr><td id=a>aa</td><td id=b>bbbbbb</td></tr></table>', 400);
  Eq(BoxOf('#a').W, 100, 'a quarter for the short column');
  Eq(BoxOf('#b').W, 300, 'three quarters for the long one');
  { spacing, padding, a row as tall as its tallest cell, vertical-align }
  Load('<!DOCTYPE html><style>body{margin:0} table{border-spacing:2px} td{padding:1px;vertical-align:middle}' +
    ' #b{width:40px}</style>' +
    '<table id=t><tr><td id=a>a</td><td id=b>bbbbbbbb bbbbbbbb</td></tr></table>');
  At('#a', 2, 2, 10, 42);
  At('#b', 14, 2, 66, 42);
  Eq(BoxOf('#t').H, 46, 'the table: spacing and the row');
end;

procedure PositionChecks;
begin
  Load('<!DOCTYPE html><style>body{margin:0} #p{position:relative;width:400px;height:100px;margin-top:20px}' +
    ' #a{position:absolute;right:0;top:10px;width:50px} #r{position:relative;left:5px;top:7px}' +
    ' #n{margin:0}</style>' +
    '<div id=p><div id=a>a</div></div><p id=r>r</p><p id=n>n</p>');
  At('#a', 350, 30, 50, 20);
  Eq(BoxOf('#r').X, 5, 'relative: moved right');
  Eq(BoxOf('#r').Y, 120 + 16 + 7, 'and down');
  Eq(BoxOf('#n').Y, 120 + 16 + 20 + 16, 'what follows does not move');
end;

procedure ListAndImageChecks;
var B: TInkBox;
begin
  Load('<!DOCTYPE html><ol start=5><li id=a>a<li id=b>b<ul><li id=c>c</ul></ol>');
  Check(BoxOf('#a').Marker = '5.', 'start=5: ' + BoxOf('#a').Marker);
  B := BoxOf('#b');
  Check((B.Count > 0) and (B[0].Marker = '6.'), 'the next is 6.');
  Check(BoxOf('#c').Marker = '◦', 'a nested list: a circle');
  Load('<!DOCTYPE html><style>body{margin:0} img{max-width:100%} div{width:300px}</style>' +
    '<div><img id=i data-w=400 data-h=200></div><img id=j data-w=40 data-h=20 width=80>');
  At('#i', 0, 0, 300, 150);
  At('#j', 0, 150, 80, 40);
end;

procedure SpeedCheck;
var S: string; I: Integer; T: TDateTime; Ms: Int64;
begin
  S := '<!DOCTYPE html><style>.c{display:flex;gap:4px} .c>div{flex:1}</style>';
  for I := 1 to 2000 do
    S := S + '<div class=c><div>cell ' + IntToStr(I) + '</div><div>more text here</div></div><p>para ' +
      IntToStr(I) + ' with words</p>';
  T := Now;
  Load(S);
  Ms := MilliSecondsBetween(Now, T);
  WriteLn('Styled and laid out ', 2000 * 5, ' boxes in ', Ms, ' ms');
  Check(Ms < 3000, 'a long page lays out in good time');
end;

begin
  Failures := 0; Checks := 0;
  Fake := TFake.Create;
  FlowChecks;
  FloatChecks;
  FlexChecks;
  GridChecks;
  PseudoChecks;
  CenterChecks;
  FixedColumnChecks;
  TableFixChecks;
  TableChecks;
  PositionChecks;
  ListAndImageChecks;
  SpeedCheck;
  FreeAndNil(Lay); FreeAndNil(Styler); FreeAndNil(Doc); Fake.Free;
  WriteLn(Checks, ' layout checks, ', Failures, ' failed.');
  if Failures > 0 then Halt(1);
end.
