#!/bin/sh
# A browser's rendering of a page, to hold LazInk's up against.
#
#   tools/browser_shot.sh page.html out.png [width] [height]
#
# Uses whichever Chromium-family browser is installed - Chrome, Chromium,
# Brave, Edge - headless, no profile, no network beyond the file itself.
# Nothing here is part of the package or the tests; it is for looking.
#
# Render the same page with LazInk beside it and compare by eye:
#   tools/browser_shot.sh docs/help/index.html browser.png 760
#   (then your own TInkPage render at the same width)
#
# What is expected to differ, and is not a bug: LazInk takes its colors from
# the control's theme rather than the page's light/dark scheme, it does not
# read line-height or text-transform, and it draws no form controls.
#
# SPDX-License-Identifier: MIT
set -eu

PAGE=${1:?usage: browser_shot.sh page.html out.png [width] [height]}
OUT=${2:?usage: browser_shot.sh page.html out.png [width] [height]}
WIDTH=${3:-760}
HEIGHT=${4:-1400}

for B in google-chrome-stable google-chrome chromium chromium-browser \
         brave-browser brave-browser-stable microsoft-edge; do
  if command -v "$B" >/dev/null 2>&1; then BROWSER=$B; break; fi
done
: "${BROWSER:?no Chromium-family browser found; install one or pass a path in BROWSER}"

case $PAGE in
  /*) URL="file://$PAGE" ;;
  *)  URL="file://$(pwd)/$PAGE" ;;
esac

"$BROWSER" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --screenshot="$OUT" --window-size="$WIDTH,$HEIGHT" "$URL" >/dev/null 2>&1

echo "$BROWSER wrote $OUT at ${WIDTH}x${HEIGHT}"
