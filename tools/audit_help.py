#!/usr/bin/env python3
"""Inventory a local HTML help tree or download its same-site linked pages.
Usage: audit_help.py LOCAL_DIRECTORY [--output report.json]
       audit_help.py URL --download DIRECTORY [--output report.json]
"""
import argparse
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
import json
from urllib.parse import urljoin, urlsplit, unquote
from urllib.request import urlopen

class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags, self.attrs, self.classes = Counter(), Counter(), Counter()
        self.links, self.assets, self.ids = [], [], set()
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags[tag] += 1
        self.attrs.update(f'{tag}.{k}' for k in a)
        self.classes.update(a.get('class', '').split())
        if 'id' in a: self.ids.add(a['id'])
        if tag == 'a' and 'href' in a: self.links.append(a['href'])
        if tag == 'img' and 'src' in a: self.assets.append(a['src'])
        if tag == 'link' and a.get('rel') == 'stylesheet': self.assets.append(a['href'])
    handle_startendtag = handle_starttag

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('source'); ap.add_argument('--download', type=Path)
    ap.add_argument('--output', type=Path)
    args = ap.parse_args()
    if args.source.startswith(('https://', 'http://')):
        if not args.download: ap.error('URL requires --download')
        base = args.source.rstrip('/') + '/'
        root = args.download
        pending, seen = [base], set()
        while pending:
            url = pending.pop()
            parts = urlsplit(url)
            url = parts._replace(fragment='', query='').geturl()
            if url in seen or not url.startswith(base): continue
            seen.add(url)
            rel = unquote(url[len(base):]) or 'index.html'
            target = root / rel
            if not target.resolve().is_relative_to(root.resolve()): continue
            with urlopen(url, timeout=30) as response: data = response.read()
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
            if target.suffix == '.html':
                page = Page(); page.feed(data.decode('utf-8'))
                for link in page.links + page.assets:
                    resolved = urljoin(url, link)
                    if resolved.startswith(base): pending.append(resolved)
    else: root = Path(args.source)
    pages, tags, attrs, classes = {}, Counter(), Counter(), Counter()
    for path in sorted(root.rglob('*.html')):
        page = Page(); page.feed(path.read_text())
        pages[path.relative_to(root).as_posix()] = page
        tags.update(page.tags); attrs.update(page.attrs); classes.update(page.classes)
    broken, assets = [], set()
    for name, page in pages.items():
        for ref in page.links + page.assets:
            parts = urlsplit(ref)
            if parts.scheme or parts.netloc: continue
            path = ((root/name).parent / unquote(parts.path)).resolve() if parts.path else (root/name).resolve()
            if path.is_dir(): path /= 'index.html'
            if not path.exists(): broken.append({'page': name, 'reference': ref})
            elif parts.fragment and path.suffix == '.html':
                dest = pages.get(path.relative_to(root.resolve()).as_posix())
                if dest and unquote(parts.fragment) not in dest.ids:
                    broken.append({'page': name, 'reference': ref, 'reason': 'missing anchor'})
        assets.update(page.assets)
    report = dict(source=args.source, page_count=len(pages), pages=list(pages), tags=dict(tags),
                  attributes=dict(attrs), classes=dict(classes), asset_references=sorted(assets), broken_references=broken)
    out = json.dumps(report, indent=2) + '\n'
    if args.output: args.output.write_text(out)
    else: print(out, end='')
if __name__ == '__main__': main()
