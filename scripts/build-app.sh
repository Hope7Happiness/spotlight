#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/QuickAsk.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/QuickAsk" "$MACOS_DIR/QuickAsk"
cp "$ROOT_DIR/scripts/quickask-launcher.sh" "$MACOS_DIR/quickask-launcher.sh"
cp "$ROOT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "$APP_DIR"
