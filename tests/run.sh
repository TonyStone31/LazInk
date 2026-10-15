#!/bin/sh
set -eu
: "${LAZARUS_DIR:?Set LAZARUS_DIR to the Lazarus source directory}"
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
TARGET_CPU=$("$FPC" -iTP)
TARGET_OS=$("$FPC" -iTO)
UNIT_TARGET="$TARGET_CPU-$TARGET_OS"
case "$TARGET_OS" in
  darwin) DEFAULT_WIDGETSET=cocoa ;;
  *) DEFAULT_WIDGETSET=gtk3 ;;
esac
LCL_WIDGETSET=${LCL_WIDGETSET:-$DEFAULT_WIDGETSET}
# lazbuild names this framework for Cocoa; compiling by hand has to
COCOA_LINK=
[ "$TARGET_OS" != darwin ] || COCOA_LINK="-k-framework -kUserNotifications"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cd "$(dirname "$0")/.."
# the document tree first: it needs no widgetset, and every page goes through it
"$FPC" -gl -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/$UNIT_TARGET" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/dom_tests.pas >"$BUILD_DIR/dom.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/dom.log"; exit 1; }
"$BUILD_DIR/dom_tests"
"$FPC" -gl -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/$UNIT_TARGET" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/style_tests.pas >"$BUILD_DIR/style.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/style.log"; exit 1; }
"$BUILD_DIR/style_tests"
"$FPC" -gl -Fu. -Fu"$LAZARUS_DIR/components/lazutils/lib/$UNIT_TARGET" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/layout_tests.pas >"$BUILD_DIR/layout.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/layout.log"; exit 1; }
"$BUILD_DIR/layout_tests"
"$FPC" $COCOA_LINK -gl -dLCL -dLCL$LCL_WIDGETSET -Fu. -Fu"$LAZARUS_DIR/lcl/units/$UNIT_TARGET" \
  -Fu"$LAZARUS_DIR/lcl/units/$UNIT_TARGET/$LCL_WIDGETSET" \
  -Fu"$LAZARUS_DIR/components/lazutils/lib/$UNIT_TARGET" \
  -Fu"$LAZARUS_DIR/components/freetype/lib/$UNIT_TARGET" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/render_tests.pas
"$BUILD_DIR/render_tests" "$@"
# Source preservation and rendered editing, separate from parser conformance.
"$FPC" $COCOA_LINK -gl -Cr -Co -Ci -Sa -dLCL -dLCL$LCL_WIDGETSET -Fu. \
  -Fu"$LAZARUS_DIR/lcl/units/$UNIT_TARGET" \
  -Fu"$LAZARUS_DIR/lcl/units/$UNIT_TARGET/$LCL_WIDGETSET" \
  -Fu"$LAZARUS_DIR/components/lazutils/lib/$UNIT_TARGET" \
  -Fu"$LAZARUS_DIR/components/freetype/lib/$UNIT_TARGET" \
  -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/markdown_roundtrip_tests.pas >"$BUILD_DIR/roundtrip.log" 2>&1 ||
  { tail -20 "$BUILD_DIR/roundtrip.log"; exit 1; }
if [ -n "${MARKDOWN_SPEC:-}" ]; then "$BUILD_DIR/markdown_roundtrip_tests" "$MARKDOWN_SPEC"
else "$BUILD_DIR/markdown_roundtrip_tests"; fi
# Given a page list and a results folder, also check that every piece of
# visible text in the pages survived into what was rendered.
if [ "$#" -ge 2 ]; then
  "$FPC" -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/check_help_text.pas >"$BUILD_DIR/check.log" 2>&1 ||
    { tail -20 "$BUILD_DIR/check.log"; exit 1; }
  "$BUILD_DIR/check_help_text" "$1" "$2"
fi
