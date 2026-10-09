program DOMTests;
{ InkDOM: the tree a page is parsed into, checked against what a browser
  builds from the same source.  Needs no widgetset. }
{$mode objfpc}{$H+}
uses Classes, SysUtils, DateUtils, InkDOM;

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

function Shown(const S: string): string;
begin
  Result := StringReplace(S, #10, '\n', [rfReplaceAll]);
end;

{ the body's HTML after parsing - the part of the tree most cases are about }
function BodyOf(const HTML: string): string;
var D: TInkDocument;
begin
  D := InkParseHTML(HTML);
  try Result := D.Body.InnerHTML finally D.Free end;
end;

function DocOf(const HTML: string): string;
var D: TInkDocument;
begin
  D := InkParseHTML(HTML);
  try Result := InkSerializeHTML(D) finally D.Free end;
end;

procedure Body(const HTML, Wanted: string);
var Got: string;
begin
  Got := BodyOf(HTML);
  Check(Got = Wanted, Shown(HTML) + #10'    wanted ' + Shown(Wanted) + #10'    got    ' + Shown(Got));
end;

procedure Whole(const HTML, Wanted: string);
var Got: string;
begin
  Got := DocOf(HTML);
  Check(Got = Wanted, Shown(HTML) + #10'    wanted ' + Shown(Wanted) + #10'    got    ' + Shown(Got));
end;

procedure TreeChecks;
begin
  Whole('', '<html><head></head><body></body></html>');
  Whole('Hello', '<html><head></head><body>Hello</body></html>');
  Whole('<!DOCTYPE html><title>T</title><p>x',
    '<!DOCTYPE html><html><head><title>T</title></head><body><p>x</p></body></html>');
  Whole('<!-- before --><p>x', '<!-- before --><html><head></head><body><p>x</p></body></html>');
  Whole('<html><body><p>x</body></html><!-- after -->',
    '<html><head></head><body><p>x</p></body></html><!-- after -->');
  { what closes what }
  Body('<p>One<p>Two', '<p>One</p><p>Two</p>');
  Body('<ul><li>a<li>b</ul>', '<ul><li>a</li><li>b</li></ul>');
  Body('<ul><li>a<ul><li>b</ul><li>c</ul>', '<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>');
  Body('<dl><dt>a<dd>b<dt>c</dl>', '<dl><dt>a</dt><dd>b</dd><dt>c</dt></dl>');
  Body('<h1>a<h2>b</h2>', '<h1>a</h1><h2>b</h2>');
  Body('<div><span>a</div>b', '<div><span>a</span></div>b');
  Body('<p>a<div>b</div>', '<p>a</p><div>b</div>');
  Body('<p>a</p></p>', '<p>a</p><p></p>');
  Body('a</br>b', 'a<br>b');
  Body('<p>a<br/>b', '<p>a<br>b</p>');
  Body('<div/>x', '<div>x</div>');
  { formatting carried across blocks, and misnesting repaired }
  Body('<b>1<i>2</b>3</i>', '<b>1<i>2</i></b><i>3</i>');
  Body('<p><b>bold<p>still', '<p><b>bold</b></p><p><b>still</b></p>');
  Body('<b><p>x</b>y</p>', '<b></b><p><b>x</b>y</p>');
  Body('<a href=1>x<a href=2>y', '<a href="1">x</a><a href="2">y</a>');
  Body('<b><b><b><b>x</b></b></b></b>y', '<b><b><b><b>x</b></b></b></b>y');
  { tables }
  Body('<table><tr><td>1</td></tr></table>',
    '<table><tbody><tr><td>1</td></tr></tbody></table>');
  Body('<table><td>1<td>2<tr><td>3</table>',
    '<table><tbody><tr><td>1</td><td>2</td></tr><tr><td>3</td></tr></tbody></table>');
  Body('<table>oops<tr><td>1</table>',
    'oops<table><tbody><tr><td>1</td></tr></tbody></table>');
  Body('<table><tr><td><table><tr><td>in</table>out</table>',
    '<table><tbody><tr><td><table><tbody><tr><td>in</td></tr></tbody></table>out</td></tr></tbody></table>');
  Body('<table><caption>c<tr><td>1</table>',
    '<table><caption>c</caption><tbody><tr><td>1</td></tr></tbody></table>');
  Body('<table><colgroup><col span=2></colgroup><tr><td>1</table>',
    '<table><colgroup><col span="2"></colgroup><tbody><tr><td>1</td></tr></tbody></table>');
  Body('<table><b><tr><td>x</table>',
    '<b></b><table><tbody><tr><td>x</td></tr></tbody></table>');
  Body('<td>stray', 'stray');
  Whole('<!DOCTYPE html><p><table><tr><td>x</table>',
    '<!DOCTYPE html><html><head></head><body><p></p><table><tbody><tr><td>x</td></tr></tbody></table></body></html>');
  { quirks: a table stays in the paragraph }
  Body('<p><table><tr><td>x</table>',
    '<p><table><tbody><tr><td>x</td></tr></tbody></table></p>');
  { raw text }
  Body('<body><script>if (a<b) document.write("</p>")</script>x',
    '<script>if (a<b) document.write("</p>")</script>x');
  Whole('<style>p > a { color: red }</style>',
    '<html><head><style>p > a { color: red }</style></head><body></body></html>');
  Body('<textarea>'#10'<b>&amp;</b></textarea>', '<textarea>&lt;b&gt;&amp;&lt;/b&gt;</textarea>');
  Body('<xmp><b></xmp>', '<xmp><b></xmp>');
  Body('<body><noscript><p>no script</p></noscript>', '<noscript><p>no script</p></noscript>');
  Whole('<noscript><link rel=stylesheet href=a.css></noscript><p>x',
    '<html><head><noscript><link rel="stylesheet" href="a.css"></noscript></head><body><p>x</p></body></html>');
  Body('<body><script><!--document.write("<script>a</script>")--></script>x',
    '<script><!--document.write("<script>a</script>")--></script>x');
  Whole('<frameset><frame src=a.html><noframes>none</noframes></frameset>',
    '<html><head></head><frameset><frame src="a.html"><noframes>none</noframes></frameset></html>');
  Body('<body><template><tr><td>x</td></tr></template><p>y', '<template><tr><td>x</td></tr></template><p>y</p>');
  Body('<math><mtext><i>x</i></mtext></math>', '<math><mtext><i>x</i></mtext></math>');
  Body('&NotEqualTilde;&ThickSpace;', #$E2#$89#$82#$CC#$B8#$E2#$81#$9F#$E2#$80#$8A);
  { <pre> loses the newline after its tag, once }
  Body('<pre>'#10'code</pre>', '<pre>code</pre>');
  Body('<pre>'#10#10'code</pre>', '<pre>'#10#10'code</pre>');
  Body('<pre>'#13#10'a'#13'b</pre>', '<pre>a'#10'b</pre>');
  { lists of options }
  Body('<select><option>a<option>b</select>x',
    '<select><option>a</option><option>b</option></select>x');
  { drawings }
  Body('<svg viewbox="0 0 1 1"><path d="M0"/><foreignobject><p>x</p></foreignobject></svg>',
    '<svg viewBox="0 0 1 1"><path d="M0"></path><foreignObject><p>x</p></foreignObject></svg>');
  Body('<svg><p>x', '<svg></svg><p>x</p>');
  Body('<svg><title>t</title><circle r=1 /></svg>y', '<svg><title>t</title><circle r="1"></circle></svg>y');
  Body('<math><mi>x</mi></math>', '<math><mi>x</mi></math>');
  { head content late, and body content early }
  Whole('<p>x</p><style>a{}</style>',
    '<html><head></head><body><p>x</p><style>a{}</style></body></html>');
  Whole('<meta charset=utf-8><link rel=stylesheet href=a.css>text',
    '<html><head><meta charset="utf-8"><link rel="stylesheet" href="a.css"></head><body>text</body></html>');
  Whole('<html lang=en><head></head>  <body class=b>x</body></html>',
    '<html lang="en"><head></head>  <body class="b">x</body></html>');
  { odd tokens }
  Body('a < b > c', 'a &lt; b &gt; c');
  Body('<p title=''it''s''>x', '<p title="it" s''="">x</p>');
  Body('<p a=1 a=2 B=3>x', '<p a="1" b="3">x</p>');
  Body('</>x<?php echo 1 ?>y', 'x<!--?php echo 1 ?-->y');
  Body('x<!-- open', 'x<!-- open-->');
  Body('x<p', 'x');
  Body('<img src="a.png" alt="a &amp; b">', '<img src="a.png" alt="a &amp; b">');
end;

procedure EntityChecks;
var D: TInkDocument;
begin
  Body('&eacute;&copy &#x41;&#65;&#150;&notit;&bogus;', 'é© AA–¬it;&amp;bogus;');
  Body('&nbsp;', '&nbsp;');
  Body('&#0;&#xD800;&#x110000;', #$EF#$BF#$BD#$EF#$BF#$BD#$EF#$BF#$BD);
  Body('&alpha;&Omega;&hellip;&rarr;&euro;&check;', 'αΩ…→€✓');
  D := InkParseHTML('<a href="?a=1&copy=2&amp;b=3&lang=x">x</a>');
  try
    Check(D.GetElementsByTagName('a')[0].GetAttribute('href') = '?a=1&copy=2&b=3&lang=x',
      'An attribute keeps &name followed by = ('+D.GetElementsByTagName('a')[0].GetAttribute('href')+')');
  finally D.Free end;
  Check(InkEntity('eacute') = 'é', 'InkEntity');
  Check(InkEntity('nonsense') = '', 'InkEntity unknown');
end;

procedure APIChecks;
var D: TInkDocument; N, M: TInkNode; L: TInkNodeArray;
begin
  D := InkParseHTML('<!DOCTYPE html><title> A &amp;'#10'  B </title>' +
    '<div id=main class="box wide"><p>one <b>two</b></p><p id=second>three</p></div>');
  try
    Check(not D.Quirks, 'A doctype is not quirks');
    Check(D.Title = 'A & B', 'Title collapses its white space: "' + D.Title + '"');
    N := D.GetElementById('main');
    Check((N <> nil) and N.IsElement('div'), 'GetElementById');
    Check(N.HasClass('wide') and N.HasClass('box') and not N.HasClass('bo'), 'HasClass');
    Check(N.TextContent = 'one twothree', 'TextContent: ' + N.TextContent);
    L := D.GetElementsByTagName('p');
    Check(Length(L) = 2, 'GetElementsByTagName');
    Check(Length(D.GetElementsByTagName('*')) = 8, 'Every element: ' + IntToStr(Length(D.GetElementsByTagName('*'))));
    M := D.GetElementById('second');
    M.TextContent := 'a < b';
    Check(M.OuterHTML = '<p id="second">a &lt; b</p>', 'Set TextContent: ' + M.OuterHTML);
    M.InnerHTML := '<li>a<li>b';
    Check(M.InnerHTML = '<li>a</li><li>b</li>', 'Set InnerHTML: ' + M.InnerHTML);
    M.SetAttribute('Data-X', '"q"');
    Check(M.GetAttribute('data-x') = '"q"', 'Attribute names are lowercase');
    Check(Pos('data-x="&quot;q&quot;"', M.OuterHTML) > 0, 'Attribute quotes escape');
    M.RemoveAttribute('data-x');
    Check(not M.HasAttribute('data-x'), 'RemoveAttribute');
    N.InsertBefore(M, N.FirstChild);
    Check(N.FirstElementChild = M, 'InsertBefore moves a node');
    M.Remove;
    Check(M.Parent = nil, 'Remove detaches');
    M.Free;
    Check(Length(D.GetElementsByTagName('li')) = 0, 'A removed subtree is gone');
    N.Free;
    Check(D.GetElementById('main') = nil, 'Freeing a node takes it out of the tree');
    Check(D.Body.ChildCount = 0, 'And out of its parent');
    M := D.Body.AppendChild(TInkNode.Create(inkElement, 'p'));
    M.TextContent := 'new';
    Check(D.Body.InnerHTML = '<p>new</p>', 'AppendChild');
    N := M.Clone(True);
    Check(N.OuterHTML = M.OuterHTML, 'A deep clone serializes the same');
    N.Free;
  finally D.Free end;
  D := InkParseHTML('<p>x');
  try Check(D.Quirks, 'No doctype is quirks') finally D.Free end;
  D := InkParseHTML('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">');
  try Check(D.Quirks, 'HTML 4.01 Transitional without a system id is quirks') finally D.Free end;
  D := InkParseHTML('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">');
  try Check(not D.Quirks, 'HTML 4.01 Strict is not quirks') finally D.Free end;
end;

procedure EncodingChecks;
begin
  Check(InkDecodeHTML('caf'#$E9) = 'café', 'Bytes that are not UTF-8 are Windows-1252');
  Check(InkDecodeHTML('caf'#$C3#$A9) = 'café', 'UTF-8 stays');
  Check(InkDecodeHTML(#$EF#$BB#$BF'x') = 'x', 'A UTF-8 byte order mark goes');
  Check(InkDecodeHTML(#$FF#$FE'h'#0'i'#0) = 'hi', 'UTF-16 little endian');
  Check(InkDecodeHTML('<meta charset="iso-8859-1">'#$93'q'#$94) = '<meta charset="iso-8859-1">“q”',
    'Latin-1 is read as Windows-1252, as browsers do');
  Check(InkDecodeHTML('<meta http-equiv="Content-Type" content="text/html; charset=windows-1251">'#$C0) =
    '<meta http-equiv="Content-Type" content="text/html; charset=windows-1251">А',
    'Another code page through LazUtils');
end;

{ Serializing and parsing again gives the same tree. }
procedure RoundTrip(const HTML: string);
var A, B: string;
begin
  A := DocOf(HTML);
  B := DocOf(A);
  Check(A = B, 'Round trip of ' + Shown(HTML) + #10'    first  ' + Shown(A) + #10'    second ' + Shown(B));
end;

procedure RobustnessChecks;
const
  Pieces: array[0..39] of string = ('<p>', '</p>', '<b>', '</b>', '<i>', '</i>',
    '<table>', '</table>', '<tr>', '<td>', '</td>', '<div>', '</div>', 'text',
    ' ', '<a href=x>', '</a>', '<ul>', '<li>', '</ul>', '<svg>', '</svg>',
    '<select>', '<option>', '<pre>', '</pre>', '<!--', '-->', '&amp;', '&',
    '<', '>', '<script>', '</script>', '<style>', '<caption>', '<h1>', '</h2>',
    '<form>', '<textarea>');
var I, K: Integer; S: string; D: TInkDocument; Seed: Cardinal;
  function Rand(N: Integer): Integer;
  begin
    Seed := Seed * 1103515245 + 12345;
    Result := (Seed shr 16) mod N;
  end;
begin
  RoundTrip('<b>1<i>2</b>3</i>');
  RoundTrip('<table>oops<tr><td>1</table>');
  RoundTrip('<p>a &amp; b &lt; c</p><pre>'#10#10'x</pre>');
  RoundTrip('<svg viewbox="0 0 1 1"><path d="M0"/></svg>');
  Seed := 20261009;
  for I := 1 to 3000 do
  begin
    S := '';
    for K := 1 to 1 + Rand(30) do S := S + Pieces[Rand(Length(Pieces))];
    try
      D := InkParseHTML(S);
      try
        Check((D.DocumentElement <> nil) and (D.Body <> nil), 'A tree for ' + S);
      finally D.Free end;
    except
      on E: Exception do Check(False, 'Parsing ' + S + ' raised ' + E.Message);
    end;
  end;
end;

procedure SpeedChecks;
var S: string; I: Integer; T: TDateTime; D: TInkDocument; Ms: Int64;
begin
  S := '<!DOCTYPE html><table>';
  for I := 1 to 20000 do
    S := S + '<tr><td class=c>cell ' + IntToStr(I) + ' &amp; <b>bold<td><a href="#x">link</a>';
  S := S + '</table>';
  for I := 1 to 20000 do S := S + '<p>Paragraph <i>' + IntToStr(I) + '</i>';
  T := Now;
  D := InkParseHTML(S);
  try
    Check(Length(D.GetElementsByTagName('td')) = 40000, 'Every cell of a big table');
    Ms := MilliSecondsBetween(Now, T);
    WriteLn('Parsed ', Length(S) div 1024, ' KB in ', Ms, ' ms');
    Check(Ms < 3000, 'A big page parses in good time');
    T := Now;
    S := InkSerializeHTML(D);
    Ms := MilliSecondsBetween(Now, T);
    WriteLn('Serialized in ', Ms, ' ms');
    Check(Ms < 2000, 'And serializes in good time');
  finally D.Free end;
end;

begin
  Failures := 0; Checks := 0;
  TreeChecks;
  EntityChecks;
  APIChecks;
  EncodingChecks;
  RobustnessChecks;
  SpeedChecks;
  WriteLn(Checks, ' DOM checks, ', Failures, ' failed.');
  if Failures > 0 then Halt(1);
end.
