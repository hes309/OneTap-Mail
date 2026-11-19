#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="一键邮"
APP="$ROOT/build/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  ARCH="arm64"
fi

echo "==> Building $APP_NAME for $ARCH"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "==> Generating app icon"
  python3 "$ROOT/scripts/make_icon.py"
fi

mkdir -p "$ROOT/.build/modulecache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/modulecache"

swiftc \
  -O \
  -disable-sandbox \
  -swift-version 5 \
  -parse-as-library \
  -module-cache-path "$ROOT/.build/modulecache" \
  -target "$ARCH-apple-macos14.0" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Security \
  -framework UniformTypeIdentifiers \
  -framework WebKit \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/OneClickMail"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
touch "$APP"

echo "==> Built: $APP"
echo "==> Launch: open \"$APP\""
