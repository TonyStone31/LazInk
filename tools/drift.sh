#!/bin/sh
# Where a page drifts away from the browser, section by section.
#
#   tools/drift.sh tests/compare/long.html [width]
#
# Asks a browser where each heading of the page lands, asks LazInk the same,
# and prints the two beside each other with the drift at each heading and
# how much each section grew or shrank between them.  Finding the section
# that is wrong this way takes a second; finding it by scrolling takes a
# while.
#
# The browser is asked with a script injected into a copy of the page, so
# the numbers are its own layout rather than something read off a picture.
#
# Environment: LAZARUS_DIR and FPC, as tests/run.sh wants them.
#
# It is a tool, not a test; tests/run.sh does not build it.
#
# SPDX-License-Identifier: 0BSD
set -eu

cd "$(dirname "$0")/.."
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"

PAGE=${1:?usage: drift.sh page.html [width]}
WIDTH=${2:-700}
LCL_WIDGETSET=${LCL_WIDGETSET:-gtk3}
BUILD=${TMPDIR:-/tmp}/lazink-drift
mkdir -p "$BUILD"

for B in google-chrome-stable google-chrome chromium chromium-browser \
         brave-browser brave-browser-stable microsoft-edge; do
  if command -v "$B" >/dev/null 2>&1; then BROWSER=$B; break; fi
done
: "${BROWSER:?no Chromium-family browser found}"

# the page with a script that reports where its headings landed.  It is
# written beside the original so that relative images and stylesheets still
# resolve.
PROBE=$(dirname "$PAGE")/.drift-probe.html
trap 'rm -f "$PROBE"' EXIT
awk '
  /<\/body>/ && !done {
    print "<script>window.addEventListener(\"load\",function(){var o=[];"
    print "document.querySelectorAll(\"h1,h2,h3,h4,h5,h6\").forEach(function(e){"
    print "o.push(\"MARK \"+Math.round(e.getBoundingClientRect().top+window.scrollY)"
    print "+\" \"+e.tagName.toLowerCase()+\" \"+e.textContent.trim());});"
    print "o.push(\"HEIGHT \"+document.body.getBoundingClientRect().height);"
    print "document.body.innerHTML=\"<pre>\"+o.join(\"\\n\")+\"</pre>\";});</script>"
    done = 1
  }
  { print }
' "$PAGE" > "$PROBE"

"$BROWSER" --headless --disable-gpu --no-sandbox \
  --window-size="$WIDTH",2000 --virtual-time-budget=5000 \
  --dump-dom "file://$(cd "$(dirname "$PROBE")" && pwd)/$(basename "$PROBE")" \
  2>/dev/null | sed -e 's/<[^>]*>//g' | grep -E '^(MARK|HEIGHT) ' > "$BUILD/browser.txt" ||
  { echo "the browser reported nothing" >&2; exit 1; }

NEWEST=$(ls -t tools/page_marks.pas ink*.pas 2>/dev/null | head -1)
if [ ! -x "$BUILD/page_marks" ] || [ "$NEWEST" -nt "$BUILD/page_marks" ]; then
  "$FPC" -O2 -dLCL -dLCL$LCL_WIDGETSET -Fu. \
    -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux" \
    -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux/$LCL_WIDGETSET" \
    -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
    -Fu"$LAZARUS_DIR/components/freetype/lib/x86_64-linux" \
    -FU"$BUILD" -FE"$BUILD" tools/page_marks.pas >"$BUILD/build.log" 2>&1 ||
    { cat "$BUILD/build.log"; exit 1; }
fi
"$BUILD/page_marks" "$PAGE" "$WIDTH" 2>/dev/null |
  grep -E '^(MARK|HEIGHT) ' > "$BUILD/lazink.txt"

python3 - "$BUILD/browser.txt" "$BUILD/lazink.txt" <<'PY'
import sys

def read(path):
    marks, height = [], None
    for line in open(path, encoding='utf-8', errors='replace'):
        parts = line.rstrip('\n').split(' ', 3)
        if parts[0] == 'MARK' and len(parts) >= 4:
            marks.append((int(float(parts[1])), parts[2], parts[3].strip()))
        elif parts[0] == 'HEIGHT':
            height = int(float(parts[1]))
    return marks, height

b, bh = read(sys.argv[1])
l, lh = read(sys.argv[2])

# join on the heading's own words, in order, so a heading either side is
# missing does not shift everything after it
bi = li = 0
rows = []
while bi < len(b) and li < len(l):
    if b[bi][2] == l[li][2]:
        rows.append((b[bi], l[li])); bi += 1; li += 1
    elif any(b[k][2] == l[li][2] for k in range(bi + 1, min(bi + 4, len(b)))):
        bi += 1
    else:
        li += 1

print(f'{"heading":38} {"browser":>8} {"lazink":>8} {"drift":>7} {"section":>8}')
print('-' * 74)
prev = 0
worst = []
for (by, bt, bx), (ly, lt, lx) in rows:
    drift = ly - by
    grew = drift - prev
    worst.append((abs(grew), grew, bx))
    print(f'{bx[:38]:38} {by:8} {ly:8} {drift:+7} {grew:+8}')
    prev = drift
if bh and lh:
    print('-' * 74)
    print(f'{"whole page":38} {bh:8} {lh:8} {lh - bh:+7}')
worst.sort(reverse=True)
if worst:
    print()
    print('the sections that moved most:')
    for _, grew, name in worst[:5]:
        if grew:
            print(f'  {grew:+5} before "{name[:50]}"')
PY
