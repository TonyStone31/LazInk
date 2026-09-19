#!/bin/sh
set -eu
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
LCL_WIDGETSET=${LCL_WIDGETSET:-gtk3}
BUILD_DIR=$(mktemp -d)
trap 'rm -r "$BUILD_DIR"' EXIT
cd "$(dirname "$0")/.."
"$FPC" -O2 -gl -dLCL -dLCL$LCL_WIDGETSET -Fu. -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux" \
  -Fu"$LAZARUS_DIR/lcl/units/x86_64-linux/$LCL_WIDGETSET" \
  -Fu"$LAZARUS_DIR/components/lazutils/lib/x86_64-linux" \
  -Fu"$LAZARUS_DIR/components/freetype/lib/x86_64-linux" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tools/render_bench.pas >"$BUILD_DIR/build.log" 2>&1 ||
  { cat "$BUILD_DIR/build.log"; exit 1; }
"$BUILD_DIR/render_bench" "$@"
