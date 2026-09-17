#!/usr/bin/env python3
"""Check that native page parsing preserves every visible text fragment.
Run render_tests with its page-list and output-directory arguments first.
"""
from html.parser import HTMLParser
from pathlib import Path
import sys

class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.body = False
        self.hidden = 0
        self.fragments = []
    def handle_starttag(self, tag, attrs):
        if tag == 'body': self.body = True
        if tag in ('script', 'style'): self.hidden += 1
    def handle_endtag(self, tag):
        if tag == 'body': self.body = False
        if tag in ('script', 'style'): self.hidden -= 1
    def handle_data(self, data):
        if self.body and not self.hidden and data.strip(): self.fragments.append(data)

def compact(text): return ''.join(text.split())

count = 0
for filename in Path(sys.argv[1]).read_text().splitlines():
    page = Path(filename)
    parsed = VisibleText(); parsed.feed(page.read_text())
    rendered = compact((Path(sys.argv[2]) / (page.name + '.txt')).read_text())
    for fragment in parsed.fragments:
        assert compact(fragment) in rendered, f'{page.name}: lost text {fragment!r}'
        count += 1
print(f'All {count} visible HTML text fragments preserved.')
