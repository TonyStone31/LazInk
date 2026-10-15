#!/usr/bin/env python3
"""Compare InkMarkdown with a CommonMark or GFM spec.json downloaded separately."""
import argparse
from collections import Counter
from html.parser import HTMLParser
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile


class CanonicalHTML(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.tokens = []
        self.pre = 0
        self.stack = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        if tag == 'pre':
            self.pre += 1
        # GitHub heading IDs and HTML/XHTML void-tag spelling are rendering choices.
        attrs = [(k, v or '') for k, v in attrs if not (tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6') and k == 'id')]
        self.tokens.append(('start', tag, tuple(sorted(attrs))))
        if tag not in ('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'):
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.tokens.append(('end', tag))
        if tag in self.stack:
            index = len(self.stack) - 1 - self.stack[::-1].index(tag)
            del self.stack[index:]
        if tag == 'pre':
            self.pre -= 1

    def handle_data(self, data):
        inline_text = ('p', 'a', 'em', 'strong', 'del', 'span', 'code', 'kbd', 'sup', 'sub', 'th', 'td',
                       'h1', 'h2', 'h3', 'h4', 'h5', 'h6')
        if data.strip() or self.pre or (self.stack and self.stack[-1] in inline_text):
            self.tokens.append(('text', data))

    def handle_comment(self, data):
        self.tokens.append(('comment', data))

    def handle_decl(self, data):
        self.tokens.append(('declaration', data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec', type=Path, help='spec.json or the published spec.txt')
    parser.add_argument('--report', type=Path, help='write failing examples as JSON')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    compiler = os.environ.get('FPC', 'fpc')
    with tempfile.TemporaryDirectory() as build:
        spec = args.spec.resolve()
        if spec.suffix == '.txt':
            cases = []
            section = ''
            fence = None
            markdown, html = [], None
            for line in spec.read_text().splitlines(keepends=True):
                if fence is None:
                    heading = re.match(r'^#{1,6} (.+)', line)
                    if heading:
                        section = heading.group(1).strip()
                    example = re.match(r'^(`{3,}) example', line)
                    if example:
                        fence = example.group(1)
                        markdown, html = [], None
                elif line.rstrip('\r\n') == fence:
                    if html is None:
                        raise ValueError('example has no HTML separator')
                    cases.append(dict(example=len(cases) + 1, section=section,
                                      markdown=''.join(markdown).replace('→', '\t'),
                                      html=''.join(html).replace('→', '\t')))
                    fence = None
                elif line.rstrip('\r\n') == '.' and html is None:
                    html = []
                else:
                    (markdown if html is None else html).append(line)
            spec = Path(build) / 'spec.json'
            spec.write_text(json.dumps(cases))
        command = [compiler, '-gl', '-Cr', '-Co', '-Ci', '-Sa', f'-Fu{root}',
                   f'-FU{build}', f'-FE{build}', str(root / 'tests/markdown_spec.pas')]
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            print(result.stdout)
            return result.returncode
        result = subprocess.run([str(Path(build) / 'markdown_spec'), str(spec)],
                                text=True, stdout=subprocess.PIPE, check=True)
    cases = json.loads(result.stdout)
    failures = [case for case in cases if CanonicalHTML(case['html']).tokens != CanonicalHTML(case['actual']).tokens]
    print(f'{len(cases) - len(failures)}/{len(cases)} examples match; {len(failures)} differ.')
    for section, count in Counter(case['section'] for case in failures).most_common():
        print(f'  {section}: {count}')
    if args.report:
        args.report.write_text(json.dumps(failures, indent=2, ensure_ascii=False) + '\n')
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
