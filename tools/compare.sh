#!/bin/sh
# Put a page up beside a real browser's rendering of it, in one command.
#
#   tools/compare.sh                          the long page, in Xephyr
#   tools/compare.sh tests/compare/page.html  a page of your own
#   tools/compare.sh some.html 760            at another width
#
# It builds tools/sidebyside.pas, takes the browser's picture when there
# isn't a current one, starts Xephyr if DISPLAY is not already somewhere
# safe, and opens the two side by side.  Nothing is rebuilt or re-shot that
# does not need to be, so a second run is immediate.
#
# Environment:
#   LAZARUS_DIR   the Lazarus source directory        (required)
#   FPC           the compiler                        (required)
#   XDISPLAY      which display to open on            (default :9)
#   NO_XEPHYR=1   use $DISPLAY as it stands
#
# Keys, once it is up: wheel or arrows scroll both sides, S snapshots,
# 1-4 switch between TInkPage/TInkMemo/TInkListBox/TInkLabel, L unlocks the
# two sides so one can be nudged back into line, Q quits.
#
# It is a tool, not a test; tests/run.sh does not build it.
#
# SPDX-License-Identifier: 0BSD
set -eu

cd "$(dirname "$0")/.."
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"

PAGE=${1:-tests/compare/long.html}
WIDTH=${2:-700}
XDISPLAY=${XDISPLAY:-:9}
LCL_WIDGETSET=${LCL_WIDGETSET:-gtk3}
BUILD=${TMPDIR:-/tmp}/lazink-compare
SHOT=${PAGE%.*}-browser.png

mkdir -p "$BUILD"

# the long page writes itself, if it is the one being asked for and it is
# older than the script that makes it
if [ "$PAGE" = tests/compare/long.html ] &&
   { [ ! -f "$PAGE" ] || [ tools/make_long_page.py -nt "$PAGE" ]; }; then
  echo "writing $PAGE"
  python3 tools/make_long_page.py > "$PAGE"
fi
[ -f "$PAGE" ] || { echo "no such page: $PAGE" >&2; exit 1; }

# the browser's picture, when there is no current one
if [ ! -f "$SHOT" ] || [ "$PAGE" -nt "$SHOT" ]; then
  echo "shooting $PAGE"
  tools/browser_shot.sh "$PAGE" "$SHOT" "$WIDTH" 32000
fi

# the tool, when it is older than anything it is built from
NEWEST=$(ls -t tools/sidebyside.pas ink*.pas 2>/dev/null | head -1)
if [ ! -x "$BUILD/sidebyside" ] || [ "$NEWEST" -nt "$BUILD/sidebyside" ]; then
  echo "building sidebyside"
  "$FPC" -O2 -dLCL -dLCL$LCL_WIDGETSET -Fu. \
    -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux" \
    -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux/$LCL_WIDGETSET" \
    -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
    -Fu"$LAZARUS_DIR/components/freetype/lib/x86_64-linux" \
    -FU"$BUILD" -FE"$BUILD" tools/sidebyside.pas >"$BUILD/build.log" 2>&1 ||
    { cat "$BUILD/build.log"; exit 1; }
fi

if [ "${NO_XEPHYR:-0}" = 1 ]; then
  exec "$BUILD/sidebyside" "$PAGE" "$WIDTH"
fi

# a nested server, so this never lands on top of whatever you are doing
if ! DISPLAY=$XDISPLAY xdpyinfo >/dev/null 2>&1; then
  echo "starting Xephyr on $XDISPLAY"
  setsid Xephyr "$XDISPLAY" -screen $((WIDTH * 2 + 40))x1000 -ac \
    </dev/null >/dev/null 2>&1 &
  I=0
  while ! DISPLAY=$XDISPLAY xdpyinfo >/dev/null 2>&1; do
    I=$((I + 1)); [ "$I" -gt 50 ] && { echo "Xephyr did not start" >&2; exit 1; }
    sleep 0.1
  done
fi

echo "opening $PAGE on $XDISPLAY"
DISPLAY=$XDISPLAY exec "$BUILD/sidebyside" "$PAGE" "$WIDTH"
