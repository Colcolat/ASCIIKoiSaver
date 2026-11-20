#!/usr/bin/env bash
set -euo pipefail

DESKTOP_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$DESKTOP_DIR/.." && pwd)"
BUILD_DIR="$DESKTOP_DIR/build"
APP_NAME="ASCIIKoiDesktop.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="$HOME/Applications"

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

echo "🔨 Compilando $APP_NAME (Swift + AppKit + CoreGraphics)..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$DESKTOP_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macosx14.2" \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework QuartzCore \
  -framework CoreText \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework Accelerate \
  -framework IOKit \
  -framework ServiceManagement \
  -o "$APP_DIR/Contents/MacOS/ASCIIKoiDesktop" \
  "$ROOT_DIR/Sources/PondEngine.swift" \
  "$DESKTOP_DIR/Sources/AgentMonitor.swift" \
  "$DESKTOP_DIR/Sources/TrashMonitor.swift" \
  "$DESKTOP_DIR/Sources/MusicMonitor.swift" \
  "$DESKTOP_DIR/Sources/NowPlayingMonitor.swift" \
  "$DESKTOP_DIR/Sources/WeatherMonitor.swift" \
  "$DESKTOP_DIR/Sources/DesktopWallpaperManager.swift" \
  "$DESKTOP_DIR/Sources/AppDelegate.swift"

echo "🔏 Firmando app (ad-hoc para $ARCH)..."
codesign --force --deep --sign - "$APP_DIR"

echo "📦 Instalando en $INSTALL_DIR/$APP_NAME..."
mkdir -p "$INSTALL_DIR"
killall ASCIIKoiDesktop 2>/dev/null || true
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$APP_DIR" "$INSTALL_DIR/$APP_NAME"

echo "✅ ¡Listo! Instalado en: $INSTALL_DIR/$APP_NAME"
echo "👉 Para abrirlo: open \"$INSTALL_DIR/$APP_NAME\""
