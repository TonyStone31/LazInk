#!/bin/sh
set -eu
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
LCL_WIDGETSET=${LCL_WIDGETSET:-gtk3}
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cd "$(dirname "$0")/.."
# the document tree first: it needs no widgetset, and every page goes through it
"$FPC" -gl -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/dom_tests.pas >"$BUILD_DIR/dom.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/dom.log"; exit 1; }
"$BUILD_DIR/dom_tests"
"$FPC" -gl -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/style_tests.pas >"$BUILD_DIR/style.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/style.log"; exit 1; }
"$BUILD_DIR/style_tests"
"$FPC" -gl -dLCL -dLCL$LCL_WIDGETSET -Fu. -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux" \
  -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux/$LCL_WIDGETSET" \
  -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
  -Fu"$LAZARUS_DIR/components/freetype/lib/x86_64-linux" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/render_tests.pas
"$BUILD_DIR/render_tests" "$@"
# Given a page list and a results folder, also check that every piece of
# visible text in the pages survived into what was rendered.
if [ "$#" -ge 2 ]; then
  "$FPC" -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/check_help_text.pas >"$BUILD_DIR/check.log" 2>&1 ||
    { tail -20 "$BUILD_DIR/check.log"; exit 1; }
  "$BUILD_DIR/check_help_text" "$1" "$2"
fi
