#!/bin/sh
# How far LazInk's computed styles agree with a real browser's, page by page.
#
#   tools/style_compare.sh page.html [more.html ...]
#   SHOW=20 tools/style_compare.sh page.html     the first 20 disagreements too
#
# A Chromium-family browser loads a copy of each page with a script that
# writes getComputedStyle for every element into the page; tools/
# style_compare.pas computes the same page with InkStyle and compares
# property by property.  A tool for looking, not a test.
#
# SPDX-License-Identifier: 0BSD
set -eu
cd "$(dirname "$0")/.."
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
for B in google-chrome-stable google-chrome chromium chromium-browser \
         brave-browser brave-browser-stable microsoft-edge; do
  if command -v "$B" >/dev/null 2>&1; then BROWSER=$B; break; fi
done
: "${BROWSER:?no Chromium-family browser found}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$FPC" -O2 -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
  -FU"$WORK" -FE"$WORK" tools/style_compare.pas >"$WORK/build.log" 2>&1 ||
  { tail -20 "$WORK/build.log"; exit 1; }
SCRIPT='<script id="__ink_js">(function(){var P=["display","color","background-color","font-size","font-weight","font-style","margin-top","margin-bottom","padding-top","padding-right","padding-bottom","padding-left","border-top-width","border-top-style","border-left-width","text-align","white-space","list-style-type","text-transform","vertical-align","line-height","float","position","visibility","text-decoration-line","overflow-x","font-family"];var o=[],a=document.getElementsByTagName("*");for(var i=0;i<a.length;i++){var e=a[i];if(e.id=="__ink_js")continue;var c=getComputedStyle(e);o.push(e.localName+"\t"+P.map(function(p){return c.getPropertyValue(p)}).join("\t"))}var x=document.createElement("textarea");x.id="__ink_out";x.textContent=P.join("\t")+"\n"+o.join("\n");document.documentElement.appendChild(x)})()</script>'
for PAGE in "$@"; do
  ABS=$(cd "$(dirname "$PAGE")" && pwd)/$(basename "$PAGE")
  COPY="$(dirname "$ABS")/.ink-style-$$.html"
  # the page's own scripts are made inert, so both sides read the same tree,
  # and <noscript> becomes an ordinary element, as it is with no script;
  # ours goes last, so every element it reports is one the page made
  { sed -e 's/<script/<script type="text\/inert" /Ig' \
        -e 's/<noscript/<ink-noscript/Ig' -e 's/<\/noscript/<\/ink-noscript/Ig' "$ABS"
    printf '%s' "$SCRIPT"; } > "$COPY"
  "$BROWSER" --headless=new --disable-gpu --no-sandbox --window-size=1024,800 \
    --dump-dom "file://$COPY" > "$WORK/dom.html" 2>/dev/null || true
  "$WORK/style_compare" "$COPY" "$WORK/dom.html" "${SHOW:-0}" "$(basename "$PAGE")"
  rm -f "$COPY"
done
