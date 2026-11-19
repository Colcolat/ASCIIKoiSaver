#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
BUNDLE_NAME="ASCIIKoiSaver.saver"
BUNDLE_DIR="$BUILD_DIR/$BUNDLE_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

echo "🔨 Compilando $BUNDLE_NAME (100% nativo Swift + CoreGraphics)..."

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$PROJECT_DIR/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macosx13.0" \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework QuartzCore \
  -framework CoreText \
  -framework ScreenSaver \
  -Xlinker -bundle \
  -o "$BUNDLE_DIR/Contents/MacOS/ASCIIKoiSaver" \
  "$PROJECT_DIR/Sources/PondEngine.swift" \
  "$PROJECT_DIR/Sources/ASCIIKoiSaverView.swift"

echo "🎨 Generando icono/miniatura ASCII Koi (thumbnail.png y thumbnail@2x.png)..."
swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macosx13.0" \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework CoreText \
  -o "$BUILD_DIR/gen_thumb" \
  "$PROJECT_DIR/Sources/PondEngine.swift" \
  "$PROJECT_DIR/Tools/GenerateThumbnail.swift"

"$BUILD_DIR/gen_thumb" "$BUNDLE_DIR/Contents/Resources"
tiffutil -cat \
  "$BUNDLE_DIR/Contents/Resources/thumbnail.png" \
  "$BUNDLE_DIR/Contents/Resources/thumbnail@2x.png" \
  -out "$BUNDLE_DIR/Contents/Resources/thumbnail.tiff"

echo "🔏 Firmando bundle (ad-hoc para $ARCH)..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "📦 Instalando en $INSTALL_DIR/$BUNDLE_NAME..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
cp -R "$BUNDLE_DIR" "$INSTALL_DIR/$BUNDLE_NAME"

# Reiniciar los procesos de screensaver y Wallpaper para recargar binario, opciones y miniatura
killall legacyScreenSaver WallpaperLegacyExtension WallpaperAgent 2>/dev/null || true

echo "✅ ¡Listo! Instalado en: $INSTALL_DIR/$BUNDLE_NAME"
