#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT/build/一键邮.app"
TARGET_DIR="${1:-$HOME/Applications}"
TARGET_APP="$TARGET_DIR/一键邮.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "还没有构建应用。请先运行：$ROOT/scripts/build.sh" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "已安装：$TARGET_APP"
echo "打开：open \"$TARGET_APP\""
