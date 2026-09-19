#!/usr/bin/env python3
"""The long comparison page, written out.

    tools/make_long_page.py [sections] > tests/compare/long.html

Every section is numbered and anchored (#s41), and each one leads with a
different construct, so scrolling the page beside a browser walks through
the whole vocabulary several times over rather than showing the same
paragraph a thousand times.  Say "section 41" and both sides can be looked
at in the same place.

It is a fixture, not a test; tests/run.sh does not build or read it.

SPDX-License-Identifier: 0BSD
"""
import sys

HEAD = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>LazInk against a browser - the long page</title>
<style>
  body { background: #ffffff; color: #22262c; font-size: 15px; padding: 12px;
         font-family: sans-serif; line-height: 1.45 }
  h1 { color: #14315c; font-size: 28px }
  h2 { color: #176bbd; font-size: 21px; margin-top: 26px }
  h3 { color: #5e6670; font-size: 16px }
  h4 { color: #5e6670 }
  a { color: #176bbd }
  code, kbd { background: #eef0f3; color: #22262c }
  pre { background: #f4f6f8; padding: 10px }
  blockquote { color: #5e6670 }
  hr { color: #c8ccd2 }
  small { color: #7a828c }
  mark { background: #fff3a0 }
  table { border-collapse: collapse; margin: 8px 0 }
  th, td { border: 1px solid #c8ccd2; padding: 6px 10px }
  th { background: #eef2f7 }
  table.cards { width: 100%; table-layout: fixed; border-spacing: 10px;
                border-collapse: separate }
  table.cards td { background: #f4f7ff; border: 1px solid #c7d2fe;
                   border-radius: 8px; padding: 10px 12px }
  table.cards td.empty { background: none; border: none }
  table.span th { text-transform: uppercase }
  table.tight th, table.tight td { padding: 2px 4px }
  table.roomy th, table.roomy td { padding: 12px 18px }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px }
  .card { background: #f4f7ff; border: 1px solid #c7d2fe; padding: 10px;
          text-decoration: none; display: block }
  .note { background: #f4f6f8; border-left: 4px solid #176bbd; padding: 8px 10px }
  .warn { background: #fff7ed; border-left: 4px solid #d97706; padding: 8px 10px }
  .right { text-align: right }
  .middle { text-align: center }
  .airy { line-height: 2.2 }
  .snug { line-height: 1 }
  .shout { text-transform: uppercase }
  .quiet { text-transform: lowercase }
  .title-case { text-transform: capitalize }
  .keep { white-space: nowrap }
  .marker { color: #b45309 }
  figure { background: #f4f6f8; padding: 8px }
  figcaption { color: #7a828c; font-size: 13px }
  dt { color: #14315c }
  @media (max-width: 420px) {
    .grid { grid-template-columns: 1fr }
    body { font-size: 13px }
  }
</style>
</head>
<body>

<h1 id="top">The long page</h1>

<p>This page exists to be scrolled beside a browser. Every section below is
numbered and anchored, so a section that looks wrong can be named: the
heading of section forty-one is <code>#s41</code>. Each section leads with a
different construct and they cycle, so a screenful anywhere on the page has
something worth comparing on it.</p>

<p>What is <b>expected</b> to differ, and is not a bug: LazInk takes its
colors from the control's theme rather than the page's, it draws no form
controls, and nothing floats or flows around a picture. Everything else
should line up.</p>

<hr>
"""

TAIL = """
<hr>

<h2 id="end">The end</h2>

<p><small>If the two sides diverged anywhere above, the section number is
in the heading. See <a href="#top">back to the top</a>.</small></p>

</body>
</html>
"""

WORDS = ("the quick brown fox jumps over the lazy dog and keeps on jumping "
         "because one line is never enough to show where a renderer chooses "
         "to break a line and where it carries on").split()


def prose(n, extra=0):
    """A paragraph whose length varies with the section, so wrapping differs."""
    out = []
    for i in range((len(WORDS) // 2) + extra + (n % 11) * 4):
        out.append(WORDS[(i + n) % len(WORDS)])
    return " ".join(out).capitalize() + "."


def headings(n):
    return f"""<h3>Every heading level, at section {n}</h3>
<h4>An h4, which a browser leaves the size of the body text</h4>
<h5>An h5, smaller</h5>
<h6>And an h6, smaller again</h6>
<p>{prose(n)}</p>"""


def inline(n):
    return f"""<p>Ordinary words, then <b>bold</b>, <i>italic</i>,
<u>underlined</u>, <s>struck through</s>, <code>inline_code({n})</code>,
<kbd>Ctrl</kbd>+<kbd>{chr(65 + n % 26)}</kbd>, <mark>highlighted</mark>,
<del>deleted</del>, <ins>inserted</ins>, <small>small print</small>,
H<sub>2</sub>O, E=mc<sup>2</sup>, <cite>a citation</cite>,
<abbr title="as it happens">abbr</abbr> and
<a href="#s{max(1, n - 1)}">a link back one section</a>.</p>
<p>Entities: &amp; &lt; &gt; &quot; &copy; &reg; &trade; &rarr; &larr;
&mdash; &ndash; &hellip; &times; &deg; &euro; &nbsp; &#233; &#x2713; and a
<q>quotation inside a sentence</q>.</p>
<p>{prose(n, 20)} And
averylongunbreakablewordthatcannotbesplitanywhere{n} sits in it on purpose.</p>"""


def lists(n):
    start = (n * 3) % 20 + 1
    return f"""<ul>
  <li>a bullet with enough words in it that the line wraps and the wrapped
      part lines up under the first word rather than under the bullet</li>
  <li>another bullet
    <ul>
      <li>a nested one</li>
      <li>and another, with <a href="#s{n}">a link</a> in it
        <ul><li>and a third level, to see the indent step</li></ul>
      </li>
    </ul>
  </li>
  <li>a third</li>
</ul>
<ol start="{start}">
  <li>numbered from {start}, because the list says so</li>
  <li>the next one</li>
  <li>and one that wraps in the same way a bullet does when the text in it
      runs past the edge of the column</li>
</ol>
<ol type="a"><li>lettered</li><li>and again</li></ol>
<ul>
  <li><input type="checkbox" checked> a task that is done</li>
  <li><input type="checkbox"> and one that is not</li>
</ul>
<dl>
  <dt>A term</dt>
  <dd>and what it means.</dd>
  <dt>Another</dt>
  <dd>and its meaning, which is longer and wraps onto a second line to show
      how the indent behaves.</dd>
</dl>"""


def plain_table(n):
    rows = "".join(
        f"<tr><td><a href='#s{n}'>Row {i}</a></td><td>middle column {i}</td>"
        f"<td>{prose(n + i)[:40]}</td></tr>"
        for i in range(1, 5))
    cls = ["", " class='tight'", " class='roomy'"][n % 3]
    return f"""<table{cls}>
  <caption>Table {n}, with a caption above it</caption>
  <tr><th>Link</th><th>Middle</th><th>Wrapping text</th></tr>
  {rows}
</table>"""


def span_table(n):
    return f"""<table class="span">
  <tr><th>Release</th><th>Part</th><th>What changed</th></tr>
  <tr>
    <td rowspan="3">{n}.0</td>
    <td>renderer</td><td>font sizes in pixels</td>
  </tr>
  <tr><td>tables</td><td>rowspan as well as colspan</td></tr>
  <tr><td>pictures</td><td>sized the way the page asks</td></tr>
  <tr><td colspan="2">both parts of {n - 1}.9</td><td>the one before</td></tr>
  <tr>
    <td style="background:#f4f7ff">its own background</td>
    <td style="background:#fff7ed">
      <table><tr><td>inner one</td><td>inner two</td></tr>
      <tr><td colspan="2">and a spanning inner cell</td></tr></table>
    </td>
    <td><a href="#s{n}">a link in the third column</a></td>
  </tr>
</table>"""


def cards(n):
    return f"""<table class="cards">
  <tr>
    <td><b>Card one</b><br><small>section {n}</small></td>
    <td><b>Card two</b><br><small>with rather more words in it than the
        first one has, so the row has to grow</small></td>
    <td class="empty"></td>
  </tr>
</table>
<div class="grid">
  <a class="card" href="#s{n}"><b>A grid card</b><br><small>first</small></a>
  <a class="card" href="#s{n}"><b>Another</b><br><small>second</small></a>
  <a class="card" href="#s{n}"><b>And a third</b><br><small>third</small></a>
</div>"""


def code(n):
    langs = [
        ("pascal", f"""procedure TForm{n}.FormCreate(Sender: TObject);
const Greeting = 'It''s ready';      {{ a doubled quote }}
begin
  {{$IFDEF WINDOWS}}
  InkPage1.Color := $00FF8800;       // a Delphi-style hex number
  {{$ENDIF}}
  if Sender &lt;&gt; nil then
    InkPage1.LoadFromFile('help/index.html');  (* an old-style comment *)
end;"""),
        ("python", f'''@property
def greeting(self) -&gt; str:
    """What the greeter says."""
    return f"{{self.name}} says ready, {{{n}}} times"'''),
        ("c", f"""/* a block comment */
int main(int argc, char **argv) {{
    if (argc &gt; {n}) return 0;   // too many
    printf("%s\\n", "hello");
}}"""),
        ("sql", f"""-- how many are left
SELECT name, COUNT(*) AS n FROM items
 WHERE kind = 'open' AND id &gt; {n}
 GROUP BY name ORDER BY n DESC;"""),
        ("", f"""a line of code that names no language, which is colored by
the rules most languages share: if (n &gt; {n}) return "too big";  // a comment"""),
    ]
    lang, body = langs[n % len(langs)]
    attr = f' class="language-{lang}"' if lang else ""
    long_line = "x" * 40 + " = a line far too long for the column, which is cut off at its edge rather than wrapped, " + "y" * 40
    return f"""<pre><code{attr}>{body}</code></pre>
<pre><code>{long_line}</code></pre>"""


def quotes(n):
    return f"""<blockquote>
  <p>A quote has a bar down its side, and it can hold more than one
  paragraph. {prose(n)}</p>
  <blockquote><p>And a quote inside a quote has two bars.</p>
    <blockquote><p>Three, at the third level.</p></blockquote>
  </blockquote>
</blockquote>
<div class="note"><b>A note box.</b> A div with a background, a left border
and some padding, which is how most documentation sites draw a callout.</div>
<div class="warn"><b>And a warning.</b> The same shape in another color.</div>"""


def pictures(n):
    shots = ["palette.png", "TInkPage.png", "TInkMemo.png", "TInkLabel.png",
             "demo-markdown.png", "demo-listbox.png"]
    shot = shots[n % len(shots)]
    webps = ["drawing-lossless.webp", "gradient-lossy.webp",
             "palette-lossless.webp", "column-lossy.webp"]
    webp = webps[n % len(webps)]
    return f"""<p>A PNG at its own size, then at a width in pixels, then at
half the column, then with a max-width:</p>
<p><img src="../../images/{shot}" alt="{shot}"></p>
<p><img src="../../images/{shot}" alt="{shot} at 140px" width="140"></p>
<p><img src="../../images/{shot}" alt="{shot} at half" width="50%"></p>
<p><img src="../../images/{shot}" alt="{shot} capped" style="max-width: 200px"></p>
<figure>
  <img src="../fixtures/webp/{webp}" alt="{webp}">
  <figcaption>Figure {n}. A WebP, which LazInk decodes itself.</figcaption>
</figure>
<p>And inside a &lt;picture&gt;, plus one that is not there at all:</p>
<p><picture><source srcset="../../images/{shot}" type="image/png">
<img src="../../images/{shot}" alt="in a picture element" style="width: 90px"></picture></p>
<p><img src="missing-{n}.png" alt="[this picture is missing]"></p>"""


def folding(n):
    return f"""<details>
  <summary>Click to see more, in section {n}</summary>
  <p>This paragraph is folded away until the summary is clicked.</p>
  <ul><li>and so is this list</li><li>with two items</li></ul>
  <table><tr><th>Even</th><th>a table</th></tr>
    <tr><td>is</td><td>hidden</td></tr></table>
</details>
<details open>
  <summary>Already open</summary>
  <p>This one was written with the open attribute, so it starts showing.</p>
</details>"""


def spacing(n):
    return f"""<p class="airy">Line-height 2.2, so the lines stand well apart.
{prose(n)}</p>
<p class="snug">Line-height 1, so they close up. {prose(n)}</p>
<p class="shout">A line the stylesheet shouts in uppercase, with
<b>bold</b> and an &amp; entity in it.</p>
<p class="quiet">AND ONE IT QUIETENS BACK DOWN.</p>
<p class="title-case">and one it puts in title case</p>
<p class="keep">A line that says white-space: nowrap, so it runs off the edge of the column instead of wrapping onto a second line at all.</p>
<p class="middle">A centered line.</p>
<p class="right">And one against the right edge.</p>"""


def scripts(n):
    return f"""<p>CJK, which wraps between characters rather than at spaces:
中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試中文測試{n}。</p>
<p>日本語のテキストもここにあります。カタカナ、ひらがな、漢字。</p>
<p>한국어도 여기에 있습니다.</p>
<p>And a line with a <span style="color:#c0392b">red span</span>, a
<span style="background:#fff3a0">highlighted span</span>, a
<span style="font-size:22px">bigger one</span> and a
<span style="font-size:10px">smaller one</span> on it, to show how a line
with mixed sizes sits on its baseline.</p>"""


SECTIONS = [
    ("Headings", headings),
    ("Inline text", inline),
    ("Lists", lists),
    ("A plain table", plain_table),
    ("Spans and nesting", span_table),
    ("Cards", cards),
    ("Code", code),
    ("Quotes and notes", quotes),
    ("Pictures", pictures),
    ("Folding", folding),
    ("Spacing and case", spacing),
    ("Other scripts", scripts),
]


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 96
    out = [HEAD]
    for n in range(1, count + 1):
        name, build = SECTIONS[(n - 1) % len(SECTIONS)]
        out.append(f'\n<h2 id="s{n}">{n}. {name}</h2>\n')
        out.append(build(n))
        out.append("\n")
        if n % 4 == 0:
            out.append("<hr>\n")
    out.append(TAIL)
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
