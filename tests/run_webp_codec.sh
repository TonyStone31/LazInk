#!/bin/sh
set -eu
: "${FPC:?Set FPC to the Free Pascal compiler executable}"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cd "$(dirname "$0")/.."
"$FPC" -O2 -gl -Cr -Co -Fu. -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/webp_codec_tests.pas
"$BUILD_DIR/webp_codec_tests"
# Optimizer behavior is checked separately from checked arithmetic.
"$FPC" -B -O3 -gl -Fu. -FU"$BUILD_DIR" -FE"$BUILD_DIR" tests/webp_codec_tests.pas
"$BUILD_DIR/webp_codec_tests"
