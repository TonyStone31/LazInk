#!/bin/sh
# A Markdown file as GitHub renders it, beside TInkPage and TInkRichEdit.
#
#   tools/github_side.sh FILE.md
#
# The headings are numbered first, on all three, so a difference can be
# named by section.  GitHub's own HTML for the file comes from its API (gh
# has to be logged in), dressed in GitHub's stylesheet and photographed by
# tools/browser_shot.sh.  A window then shows that picture, TInkPage and
# TInkRichEdit side by side, scrolling together.  Pictures and links with
# relative paths are found beside the file, in all three.
#
# For looking, not a test.  Nothing is kept: the work happens in a
# temporary folder, except GitHub's stylesheet, cached once under
# ~/.cache/lazink.
#
# SPDX-License-Identifier: 0BSD
set -eu
SRC=${1:?usage: github_side.sh FILE.md}
WIDTH=${WIDTH:-620}
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
command -v gh >/dev/null || { echo "needs the GitHub command line, gh"; exit 1; }
SRC=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# headings numbered in a copy, outside code fences
python3 -I - "$SRC" "$WORK/numbered.md" <<'EOF'
import re, sys
lines = open(sys.argv[1], encoding='utf-8', errors='replace').read().split('\n')
out, fence, n = [], None, 0
for i, line in enumerate(lines):
    m = re.match(r'^ {0,3}(`{3,}|~{3,})', line)
    if fence:
        if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
            fence = None
        out.append(line)
        continue
    if m:
        fence = m.group(1)
        out.append(line)
        continue
    h = re.match(r'^( {0,3}#{1,6}[ \t]+)(.*)$', line)
    under = i + 1 < len(lines) and re.match(r'^ {0,3}(=+|-+)[ \t]*$', lines[i + 1])
    if h:
        n += 1
        line = '%s%d. %s' % (h.group(1), n, h.group(2))
    elif under and line.strip() and not re.match(r'^ {0,3}([-*+>|]|\d+[.)])', line):
        n += 1
        line = '%d. %s' % (n, line)
    out.append(line)
open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(out))
EOF

# GitHub's HTML for it, the way github.com would show it; without a
# repository named, relative paths stay as written
gh api -X POST markdown -f mode=gfm -F text=@"$WORK/numbered.md" > "$WORK/github.html"

CSS=${XDG_CACHE_HOME:-$HOME/.cache}/lazink/github-markdown-light.css
if [ ! -s "$CSS" ]; then
  mkdir -p "$(dirname "$CSS")"
  curl -sSfL -o "$CSS" https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown-light.css
fi
{
  printf '<!doctype html><html><head><meta charset="utf-8"><base href="file://%s/"><style>\n' "$(dirname "$SRC")"
  cat "$CSS"
  printf '\n.markdown-body { box-sizing: border-box; padding: 8px; }\n'
  printf '</style></head><body style="margin:0"><article class="markdown-body">\n'
  cat "$WORK/github.html"
  printf '</article></body></html>\n'
} > "$WORK/github-page.html"
tools/browser_shot.sh "$WORK/github-page.html" "$WORK/github.png" "$WIDTH" "${HEIGHT:-20000}" >/dev/null

TARGET="$("$FPC" -iTP)-$("$FPC" -iTO)"
"$FPC" -dLCL -dLCLgtk3 -Fu. -Fu"$LAZARUS_DIR/lcl/units/$TARGET" \
  -Fu"$LAZARUS_DIR/lcl/units/$TARGET/gtk3" \
  -Fu"$LAZARUS_DIR/components/lazutils/lib/$TARGET" \
  -Fu"$LAZARUS_DIR/components/freetype/lib/$TARGET" \
  -FU"$WORK" -FE"$WORK" tools/github_side.pas >"$WORK/build.log" 2>&1 ||
  { tail -20 "$WORK/build.log"; exit 1; }
"$WORK/github_side" "$WORK/github.png" "$WORK/numbered.md" "$(dirname "$SRC")" "$WIDTH"
