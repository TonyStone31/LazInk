program StyleTests;
{ InkStyle: the cascade on a document tree, checked against what a browser
  computes for the same page.  Needs no widgetset. }
{$mode objfpc}{$H+}
uses Classes, SysUtils, DateUtils, Math, InkDOM, InkStyle;

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

{ a page, its sheet, and the styler that computed it }
var Doc: TInkDocument; Styler: TInkStyler;

procedure Load(const HTML: string; AWidth: Integer = 1024; ADark: Boolean = False);
begin
  FreeAndNil(Styler); FreeAndNil(Doc);
  Doc := InkParseHTML(HTML);
  Styler := TInkStyler.Create;
  Styler.Media.Width := AWidth; Styler.Media.Height := 800; Styler.Media.Dark := ADark;
  Styler.AddDocumentSheets(Doc, 'file:///page/index.html');
  Styler.Compute(Doc);
end;

function El(const Selector: string): TInkNode;
begin
  Result := InkQuerySelector(Doc, Selector);
  if Result = nil then WriteLn('  (no element for ', Selector, ')');
end;

procedure Is_(const Selector, Prop, Wanted: string);
var N: TInkNode; Got: string;
begin
  N := El(Selector);
  if N = nil then begin Check(False, Selector + ' missing'); Exit end;
  Got := Styler.StyleOf(N).Value(Prop);
  Check(Got = Wanted, Format('%s { %s } wanted "%s" got "%s"', [Selector, Prop, Wanted, Got]));
end;

procedure PxIs(const Selector, Prop: string; Wanted: Double; Percent: Double = 0);
var N: TInkNode; Got: Double;
begin
  N := El(Selector);
  if N = nil then begin Check(False, Selector + ' missing'); Exit end;
  Got := Styler.StyleOf(N).Px(Prop, Percent);
  Check(Abs(Got - Wanted) < 0.01, Format('%s { %s } wanted %.2fpx got %.2fpx', [Selector, Prop, Wanted, Got]));
end;

procedure ColorIs(const Selector, Prop: string; Wanted: TInkRGBA);
var N: TInkNode; Got: TInkRGBA;
begin
  N := El(Selector);
  if N = nil then begin Check(False, Selector + ' missing'); Exit end;
  Got := Styler.StyleOf(N).Color(Prop);
  Check(Got = Wanted, Format('%s { %s } wanted %.8x got %.8x', [Selector, Prop, Wanted, Got]));
end;

const
  Opaque = $FF000000;

procedure SelectorChecks;
  procedure M(const HTML, Sel, Wanted: string);
  var D: TInkDocument; L: TInkNodeArray; Got: string; I: Integer;
  begin
    D := InkParseHTML(HTML);
    try
      L := InkQuerySelectorAll(D, Sel);
      Got := '';
      for I := 0 to High(L) do
      begin
        if Got <> '' then Got := Got + ' ';
        Got := Got + L[I].GetAttribute('id');
      end;
      Check(Got = Wanted, Format('%s on %s wanted [%s] got [%s]', [Sel, HTML, Wanted, Got]));
    finally D.Free end;
  end;
const
  List = '<ul id=u><li id=a class="x y">1<li id=b class=x>2<li id=c>3<li id=d lang=en-GB>4<li id=e>5</ul>';
begin
  M(List, 'li', 'a b c d e');
  M(List, '.x', 'a b');
  M(List, '.x.y', 'a');
  M(List, '#c', 'c');
  M(List, 'li:first-child', 'a');
  M(List, 'li:last-child', 'e');
  M(List, 'li:nth-child(2n)', 'b d');
  M(List, 'li:nth-child(odd)', 'a c e');
  M(List, 'li:nth-child(-n+2)', 'a b');
  M(List, 'li:nth-child(n+4)', 'd e');
  M(List, 'li:nth-last-child(2)', 'd');
  M(List, 'li:nth-child(2 of .x)', 'b');
  M(List, 'li:not(.x)', 'c d e');
  M(List, 'li:not(.x, #e)', 'c d');
  M(List, ':is(#a, #e)', 'a e');
  M(List, 'li:where(.y)', 'a');
  M(List, '#a + li', 'b');
  M(List, '#b ~ li', 'c d e');
  M(List, 'ul > li.x', 'a b');
  M(List, 'body li#c', 'c');
  M(List, 'div li', '');
  M(List, '[lang|=en]', 'd');
  M(List, '[class~=y]', 'a');
  M(List, '[id^=a]', 'a');
  M(List, '[class$=y]', 'a');
  M(List, '[class*=" "]', 'a');
  M(List, '[ID=C i]', 'c');
  M(List, ':lang(en)', 'd');
  M(List, 'ul:has(> #c)', 'u');
  M(List, 'ul:has(.nothing)', '');
  M(List, 'li:has(+ #c)', 'b');
  M(List, 'li:has(~ #e)', 'a b c d');
  M('<div id=o><p id=p><span id=s></span></p></div><div id=q></div>', 'div:has(span)', 'o');
  M('<p id=e1></p><p id=e2> </p><p id=e3><!--c--></p>', 'p:empty', 'e1 e3');
  M('<a id=l href=x>l</a><a id=n>n</a>', ':any-link', 'l');
  M('<p id=a1></p><div id=b1></div><p id=a2></p><p id=a3></p>', 'p:first-of-type', 'a1');
  M('<p id=a1></p><div id=b1></div><p id=a2></p><p id=a3></p>', 'p:last-of-type', 'a3');
  M('<p id=a1></p><div id=b1></div><p id=a2></p>', 'div:only-of-type', 'b1');
  M('<input id=i1 type=checkbox checked><input id=i2 type=checkbox disabled>', ':checked', 'i1');
  M('<input id=i1 type=checkbox checked><input id=i2 type=checkbox disabled>', ':disabled', 'i2');
  M('<p id=x1 class="a:b"></p>', '.a\:b', 'x1');
  M('<p id=x1 class=1st></p>', '.\31 st', 'x1');
  M('<p id=x1></p>', 'p:unknown-thing', '');
  M('<p id=x1></p>', 'p,,', '');
  M('<svg id=sv><foreignObject id=fo></foreignObject></svg>', 'foreignobject', 'fo');
  Check(InkMatches(InkQuerySelector(InkParseHTML('<p class=a>'), 'p'), 'p.a'), 'InkMatches');
end;

procedure CascadeChecks;
begin
  { specificity, then order, then !important, then style="" }
  Load('<style>p { color: red } .c { color: green } p { color: blue }</style><p class=c id=x>x');
  ColorIs('#x', 'color', Opaque or $008000);
  Load('<style>#x { color: red } p.c { color: green !important }</style><p class=c id=x>x');
  ColorIs('#x', 'color', Opaque or $008000);
  Load('<style>p { color: red }</style><p id=x style="color: #00f">x');
  ColorIs('#x', 'color', Opaque or $FF0000);
  Load('<style>p { color: red !important }</style><p id=x style="color: #00f">x');
  ColorIs('#x', 'color', Opaque or $0000FF);
  Load('<style>p { color: red }</style><p id=x style="color: #00f !important">x');
  ColorIs('#x', 'color', Opaque or $FF0000);
  { the browser's own sheet is below the page }
  Load('<style>h1 { font-size: 10px; font-weight: 300 }</style><h1 id=h>x</h1><h2 id=g>y</h2>');
  Is_('#h', 'font-size', '10px');
  Is_('#h', 'font-weight', '300');
  Is_('#g', 'font-size', '24px');
  Is_('#g', 'font-weight', '700');
  Is_('#g', 'display', 'block');
  Is_('head', 'display', 'none');
  Is_('body', 'margin-top', '8px');
  { :where counts nothing, :is its strongest }
  Load('<style>:where(#x) { color: red } p { color: green }</style><p id=x>x');
  ColorIs('#x', 'color', Opaque or $008000);
  Load('<style>:is(#x, p) { color: red } p.c { color: green }</style><p id=x class=c>x');
  ColorIs('#x', 'color', Opaque or $0000FF);
end;

procedure InheritanceChecks;
begin
  Load('<style>body { color: #123456; font-size: 20px; border: 1px solid red; line-height: 1.5 }' +
    ' div { font-size: 1.5em; line-height: 2em } span { font-size: 50% } em { border: inherit }' +
    ' i { color: initial } b { margin-top: 2em }</style>' +
    '<body><div id=d><span id=s>x</span><em id=e>y</em><i id=i>z</i><b id=b>w</b></div><p id=p>q</p>');
  ColorIs('#s', 'color', Opaque or $563412);
  Is_('#d', 'font-size', '30px');
  Is_('#s', 'font-size', '15px');
  Is_('#d', 'line-height', '60px');
  Is_('#s', 'line-height', '60px');
  Is_('#p', 'line-height', '1.5');
  Is_('#d', 'border-top-style', 'none');
  Is_('#e', 'border-top-style', 'none');
  Is_('#i', 'color', 'canvastext');
  PxIs('#b', 'margin-top', 60);
  Is_('#b', 'font-weight', '700');
  { bolder and lighter step from the parent }
  Load('<style>p { font-weight: 300 } b { font-weight: bolder } .l { font-weight: lighter }</style>' +
    '<p><b id=b>x<span class=l id=l>y</span></b></p>');
  Is_('#b', 'font-weight', '400');
  Is_('#l', 'font-weight', '100');
  { font-size keywords and rem }
  Load('<style>html { font-size: 10px } p { font-size: 2rem } small { font-size: smaller }' +
    ' big { font-size: x-large }</style><p id=p>x<small id=s>y</small></p><big id=b>z</big>');
  Is_('#p', 'font-size', '20px');
  Is_('#b', 'font-size', '24px');
  PxIs('#s', 'font-size', 20 / 1.2);
end;

procedure VariableChecks;
begin
  Load('<style>:root { --main: #ff0000; --gap: 4px; --both: var(--gap) var(--gap) }' +
    ' .card { --main: rgb(0, 128, 0); color: var(--main); margin: var(--both) }' +
    ' p { color: var(--main); padding: var(--missing, 7px) } i { color: var(--nope) }' +
    ' .loop { --a: var(--b); --b: var(--a); color: var(--a, blue) }</style>' +
    '<p id=p>x</p><div class=card id=c><p id=q>y<i id=i>z</i></p></div><p class=loop id=l>l</p>');
  ColorIs('#p', 'color', Opaque or $0000FF);
  ColorIs('#c', 'color', Opaque or $008000);
  ColorIs('#q', 'color', Opaque or $008000);
  Is_('#c', 'margin-top', '4px');
  Is_('#c', 'margin-left', '4px');
  Is_('#p', 'padding-top', '7px');
  ColorIs('#i', 'color', Opaque or $008000);
  ColorIs('#l', 'color', Opaque or $FF0000);
end;

procedure ShorthandChecks;
begin
  Load('<style>p { margin: 1px 2px 3px; padding: 5px 6px; border: 2px dashed #f00;' +
    ' border-left: none; border-radius: 4px 8px; font: italic bold 12px/30px Georgia, serif;' +
    ' background: #eee url(a.png) no-repeat center; flex: 1; list-style: square inside;' +
    ' text-decoration: underline dotted red; overflow: hidden auto; gap: 10px 20px; inset: 1px }' +
    ' div { margin-inline: 5px 6px; flex: none; outline: 2px solid blue; grid-column: 1 / 3 }</style>' +
    '<p id=p>x</p><div id=d>y</div>');
  Is_('#p', 'margin-top', '1px'); Is_('#p', 'margin-right', '2px');
  Is_('#p', 'margin-bottom', '3px'); Is_('#p', 'margin-left', '2px');
  Is_('#p', 'padding-left', '6px');
  Is_('#p', 'border-top-width', '2px'); Is_('#p', 'border-top-style', 'dashed');
  Is_('#p', 'border-left-style', 'none');
  ColorIs('#p', 'border-right-color', Opaque or $0000FF);
  PxIs('#p', 'border-left-width', 0);
  Is_('#p', 'border-top-right-radius', '8px'); Is_('#p', 'border-bottom-right-radius', '4px');
  Is_('#p', 'font-style', 'italic'); Is_('#p', 'font-weight', '700');
  Is_('#p', 'font-size', '12px'); Is_('#p', 'line-height', '30px');
  Is_('#p', 'font-family', 'Georgia, serif');
  ColorIs('#p', 'background-color', Opaque or $EEEEEE);
  Is_('#p', 'background-image', 'url("file:///page/a.png")');
  Is_('#p', 'background-repeat', 'no-repeat');
  Is_('#p', 'flex-grow', '1'); Is_('#p', 'flex-basis', '0%');
  Is_('#p', 'list-style-type', 'square'); Is_('#p', 'list-style-position', 'inside');
  Is_('#p', 'text-decoration-line', 'underline'); Is_('#p', 'text-decoration-style', 'dotted');
  Is_('#p', 'overflow-x', 'hidden'); Is_('#p', 'overflow-y', 'auto');
  Is_('#p', 'row-gap', '10px'); Is_('#p', 'column-gap', '20px');
  Is_('#p', 'top', '1px'); Is_('#p', 'left', '1px');
  Is_('#d', 'margin-left', '5px'); Is_('#d', 'margin-right', '6px');
  Is_('#d', 'flex-grow', '0'); Is_('#d', 'flex-basis', 'auto');
  Is_('#d', 'outline-style', 'solid');
  Is_('#d', 'grid-column-start', '1'); Is_('#d', 'grid-column-end', '3');
  Load('<style>:root { --s: dashed } p { border-inline-style: var(--s); border-inline-width: 1px 3px;' +
    ' border-block-start-width: 4px; border-block-start-style: solid } @property --u { syntax: "*";' +
    ' inherits: false; initial-value: 7px } div { --u: 2px } i { padding-top: var(--u) }</style>' +
    '<p id=p>x</p><div><i id=i>y</i></div>');
  Is_('#p', 'border-left-style', 'dashed'); Is_('#p', 'border-right-width', '3px');
  Is_('#p', 'border-top-width', '4px');
  Is_('#i', 'padding-top', '7px');
  { a later longhand wins over an earlier shorthand, and the other way }
  Load('<style>p { margin: 5px; margin-top: 1px } div { margin-top: 1px; margin: 5px }</style>' +
    '<p id=p></p><div id=d></div>');
  Is_('#p', 'margin-top', '1px'); Is_('#d', 'margin-top', '5px');
  { a shorthand with a var() waits for it }
  Load('<style>:root { --b: 3px solid green } p { border: var(--b); border-left-width: 9px }</style><p id=p>x');
  Is_('#p', 'border-top-width', '3px'); Is_('#p', 'border-left-width', '9px');
  Is_('#p', 'border-bottom-style', 'solid');
  { inherit on a shorthand reaches every part }
  Load('<style>div { padding: 4px } p { padding: inherit }</style><div><p id=p>x</p></div>');
  Is_('#p', 'padding-bottom', '4px');
end;

procedure LengthChecks;
begin
  Load('<style>p { width: calc(50% - 10px); height: min(100px, 10em); margin-top: clamp(1px, 5vw, 30px);' +
    ' padding-top: 2pt; padding-left: 1in; font-size: 20px; text-indent: 2em }' +
    ' span { text-indent: inherit }</style><p id=p><span id=s>x</span></p>', 400);
  PxIs('#p', 'width', 190, 400);
  PxIs('#p', 'height', 100);
  PxIs('#p', 'margin-top', 20);
  PxIs('#p', 'padding-top', 2 * 96 / 72);
  PxIs('#p', 'padding-left', 96);
  Is_('#s', 'text-indent', '40px');
  PxIs('#p', 'border-top-width', 0);
end;

procedure MediaChecks;
const
  Sheet = '<style>p { color: red } @media (max-width: 600px) { p { color: green } }' +
    ' @media screen and (min-width: 601px) and (max-width: 900px) { p { color: blue } }' +
    ' @media (width >= 1000px) { p { color: black } } @media print { p { color: purple } }' +
    ' @media (prefers-color-scheme: dark) { div { color: white } }' +
    ' @media not all and (monochrome) { div { background: #010203 } }' +
    ' @supports (display: grid) { div { display: grid } }' +
    ' @supports not (display: grid) { div { display: table } }' +
    ' @media (min-width: 400px) { @media (max-width: 500px) { span { color: lime } } }' +
    ' .n { color: red; & span { color: navy } &.m { color: teal } }' +
    '</style><p id=p>x</p><div id=d><span id=s>y</span></div><div class="n m" id=n><span id=ns>z</span></div>';
begin
  Load(Sheet, 500);
  ColorIs('#p', 'color', Opaque or $008000);
  ColorIs('#s', 'color', Opaque or $00FF00);
  Is_('#d', 'display', 'grid');
  ColorIs('#d', 'background-color', Opaque or $030201);
  Load(Sheet, 700);
  ColorIs('#p', 'color', Opaque or $FF0000);
  Load(Sheet, 1200, True);
  ColorIs('#p', 'color', Opaque or $000000);
  ColorIs('#d', 'color', Opaque or $FFFFFF);
  ColorIs('#ns', 'color', Opaque or $800000);
  ColorIs('#n', 'color', Opaque or $808000);
end;

{ cascade layers: a later layer wins, plain CSS beats every layer, and
  !important turns the order round }
procedure LayerChecks;
begin
  Load('<style>@layer base, utilities; @layer utilities { p { color: red } }' +
    ' @layer base { #p { color: blue } }</style><p id=p>x</p>');
  ColorIs('#p', 'color', Opaque or $0000FF);
  Load('<style>@layer x { #p.a.b { color: red } } p { color: green }</style><p id=p class="a b">x</p>');
  ColorIs('#p', 'color', Opaque or $008000);
  Load('<style>@layer a { p { color: red !important } } @layer b { p { color: blue !important } }' +
    ' p { color: green !important }</style><p id=p>x</p>');
  ColorIs('#p', 'color', Opaque or $0000FF);
  Load('<style>@layer a { @layer x { p { color: red } } p { color: blue } }</style><p id=p>x</p>');
  ColorIs('#p', 'color', Opaque or $FF0000);
  Load('<style>@layer a.x { p { color: red } } @layer a { p { color: navy } }' +
    ' @layer a.y { p { color: blue } }</style><p id=p>x</p>');
  ColorIs('#p', 'color', Opaque or $800000);
  Load('<style>@layer { p { color: red } } @layer { p { color: blue } }</style><p id=p>x</p>');
  ColorIs('#p', 'color', Opaque or $FF0000);
  { the Tailwind shape: utilities over components over base }
  Load('<style>@layer theme, base, components, utilities;' +
    ' @layer utilities { .text-red { color: red } } @layer components { .btn.btn { color: blue } }' +
    ' @layer base { button { color: black } }</style><button class="btn text-red" id=b>x</button>');
  ColorIs('#b', 'color', Opaque or $0000FF);
end;

procedure HintChecks;
begin
  Load('<body bgcolor=ffffcc text=#333><table border=1 cellpadding=5 cellspacing=0 width=80% align=center>' +
    '<tr><td id=td bgcolor=red align=right valign=top nowrap width=40>x</table>' +
    '<font id=f color=green size=5 face=Arial>y</font><p id=p align=center>z</p>' +
    '<img id=i src=a.png width=100 height="50" border=2 align=left><hr id=h size=4 noshade>' +
    '<ol id=o type=a><li>q</ol><font size=+1 id=g>g</font>');
  ColorIs('body', 'background-color', Opaque or $CCFFFF);
  ColorIs('body', 'color', Opaque or $333333);
  Is_('table', 'width', '80%');
  Is_('table', 'margin-left', 'auto');
  Is_('table', 'border-spacing', '0px');
  Is_('table', 'border-top-style', 'outset');
  Is_('#td', 'padding-top', '5px');
  Is_('#td', 'border-left-style', 'inset');
  ColorIs('#td', 'background-color', Opaque or $0000FF);
  Is_('#td', 'text-align', 'right');
  Is_('#td', 'vertical-align', 'top');
  Is_('#td', 'white-space', 'nowrap');
  Is_('#td', 'width', '40px');
  ColorIs('#f', 'color', Opaque or $008000);
  Is_('#f', 'font-size', '24px');
  Is_('#g', 'font-size', '18px');
  Is_('#f', 'font-family', 'Arial');
  Is_('#p', 'text-align', 'center');
  Is_('#i', 'width', '100px'); Is_('#i', 'height', '50px');
  Is_('#i', 'float', 'left'); Is_('#i', 'display', 'block');
  Is_('#h', 'height', '4px');
  Is_('#o', 'list-style-type', 'lower-alpha');
  { the page's own CSS beats an attribute }
  Load('<style>td { background: blue }</style><table><tr><td id=t bgcolor=red>x</table>');
  ColorIs('#t', 'background-color', Opaque or $FF0000);
end;

procedure ColorChecks;
var C: TInkRGBA;
begin
  Check(InkParseColor('#abc', C) and (C = Opaque or $CCBBAA), '#abc');
  Check(InkParseColor('#11223344', C) and (C = $44332211), '#rrggbbaa');
  Check(InkParseColor('rgb(255 0 0 / 50%)', C) and (C = $80 shl 24 or $0000FF), 'rgb with a slash');
  Check(InkParseColor('rgba(0,0,255,0.5)', C) and (C = $80 shl 24 or $FF0000), 'rgba');
  Check(InkParseColor('hsl(120, 100%, 25%)', C) and (C = Opaque or $008000), 'hsl');
  Check(InkParseColor('RebeccaPurple', C) and (C = Opaque or $993366), 'a name');
  Check(InkParseColor('transparent', C) and (C = 0), 'transparent');
  Check(not InkParseColor('notacolor', C), 'not a color');
  Check(InkParseColor('lab(54.29% 80.8 69.89)', C) and (Abs(Integer(C and $FF) - 255) <= 2) and
    ((C shr 8) and $FF <= 2), 'lab() red');
  Check(InkParseColor('oklch(62.8% 0.2577 29.23)', C) and (Abs(Integer(C and $FF) - 255) <= 2), 'oklch() red');
  Check(InkParseColor('lch(87.82 113.3 134.4)', C) and (((C shr 8) and $FF) >= 250), 'lch() lime');
  Load('<style>p { color: #f00; border: 1px solid currentcolor } p a { color: currentcolor }</style>' +
    '<p id=p><a id=a href=x>l</a></p><a id=b href=y>m</a>');
  ColorIs('#p', 'border-top-color', Opaque or $0000FF);
  ColorIs('#a', 'color', Opaque or $0000FF);
  ColorIs('#b', 'color', Opaque or $EE0000);
end;

procedure PseudoChecks;
var S: TInkStyle;
begin
  Load('<style>p::before { content: "> "; color: red } p::after { content: "!" }</style><p id=p>x');
  S := Styler.PseudoStyleOf(El('#p'), 'before');
  Check((S <> nil) and (S.Value('content') = '"> "'), '::before content');
  Check((S <> nil) and (S.Color('color') = Opaque or $0000FF), '::before color');
  Check(Styler.PseudoStyleOf(El('#p'), 'after') <> nil, '::after');
  Check(Styler.PseudoStyleOf(El('body'), 'before') = nil, 'no ::before where none asked');
  Styler.Free; Styler := nil;
  Load('<style>a:hover { color: red } li:hover > b { color: green } :target { color: blue }</style>' +
    '<ul><li id=l><b id=b>x</b></li></ul><a id=a href=x>y</a><p id=t>t</p>');
  Styler.Hover := El('#b'); Styler.TargetId := 't';
  Styler.Compute(Doc);
  ColorIs('#b', 'color', Opaque or $008000);
  ColorIs('#a', 'color', Opaque or $EE0000);
  ColorIs('#t', 'color', Opaque or $FF0000);
end;

procedure SharingAndSpeedChecks;
var S: string; I: Integer; T: TDateTime; Ms: Int64; N: TInkNodeArray;
begin
  S := '<style>tr:nth-child(odd) td { background: #eee } td.c { padding: 2px }' +
    ' .row > td:first-child { font-weight: bold } a[href^="#"] { color: green }';
  for I := 1 to 300 do S := S + Format(' .unused%d .x%d > span { color: red }', [I, I]);
  S := S + '</style><table>';
  for I := 1 to 5000 do
    S := S + '<tr class=row><td class=c>cell ' + IntToStr(I) + '<td><a href="#x">link</a>';
  S := S + '</table>';
  T := Now;
  Load(S);
  Ms := MilliSecondsBetween(Now, T);
  WriteLn('Styled ', 15000 + 4, ' elements against ', Styler.RuleCount, ' rules in ', Ms,
    ' ms, ', Styler.StyleCount, ' distinct styles');
  Check(Ms < 2000, 'A big table styles in good time');
  Check(Styler.StyleCount < 100, 'Identical cells share their style');
  N := InkQuerySelectorAll(Doc, 'td');
  ColorIs('tr:nth-child(3) td', 'background-color', Opaque or $EEEEEE);
  Check(Styler.StyleOf(N[2]).Value('background-color') = 'transparent', 'an even row is not striped');
  Is_('td', 'font-weight', '700');
end;

begin
  Failures := 0; Checks := 0;
  SelectorChecks;
  CascadeChecks;
  InheritanceChecks;
  VariableChecks;
  ShorthandChecks;
  LengthChecks;
  MediaChecks;
  LayerChecks;
  HintChecks;
  ColorChecks;
  PseudoChecks;
  SharingAndSpeedChecks;
  FreeAndNil(Styler); FreeAndNil(Doc);
  WriteLn(Checks, ' style checks, ', Failures, ' failed.');
  if Failures > 0 then Halt(1);
end.
