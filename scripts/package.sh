#!/usr/bin/env bash
# Build a notarization-ready Release zip for Homebrew cask / GitHub Releases.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
DERIVED="${ROOT}/.derived-release"
OUT_DIR="${ROOT}/dist"
APP_NAME="ModeBar"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"

rm -rf "$DERIVED" "$OUT_DIR"
mkdir -p "$OUT_DIR"

xcodebuild \
  -project "${ROOT}/ModeBar/ModeBar.xcodeproj" \
  -scheme ModeBar \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  build

APP_SRC="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
ditto -c -k --sequesterRsrc --keepParent "$APP_SRC" "${OUT_DIR}/${ZIP_NAME}"
shasum -a 256 "${OUT_DIR}/${ZIP_NAME}" | tee "${OUT_DIR}/${ZIP_NAME}.sha256"
echo "Built ${OUT_DIR}/${ZIP_NAME}"
