#!/usr/bin/env bash
#
# Regenerate the app icon for both platforms from scripts/GenerateIcon.swift:
#   • Resources/AppIcon.icns                    (macOS bundle)
#   • iOS/Assets.xcassets/AppIcon.appiconset/…  (iOS asset catalog)
#
set -euo pipefail
cd "$(dirname "$0")/.."

GEN="$(mktemp -d)/genicon"
echo "==> Compiling icon generator"
swiftc scripts/GenerateIcon.swift -o "$GEN"

# ---- macOS .icns ----------------------------------------------------------
ICONSET="$(mktemp -d)/Scheduled.iconset"
mkdir -p "$ICONSET"
echo "==> Rendering macOS iconset"
"$GEN" "$ICONSET/icon_16x16.png"        16   macos
"$GEN" "$ICONSET/icon_16x16@2x.png"     32   macos
"$GEN" "$ICONSET/icon_32x32.png"        32   macos
"$GEN" "$ICONSET/icon_32x32@2x.png"     64   macos
"$GEN" "$ICONSET/icon_128x128.png"      128  macos
"$GEN" "$ICONSET/icon_128x128@2x.png"   256  macos
"$GEN" "$ICONSET/icon_256x256.png"      256  macos
"$GEN" "$ICONSET/icon_256x256@2x.png"   512  macos
"$GEN" "$ICONSET/icon_512x512.png"      512  macos
"$GEN" "$ICONSET/icon_512x512@2x.png"   1024 macos
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> Wrote Resources/AppIcon.icns"

# ---- iOS asset catalog ----------------------------------------------------
APPICON="iOS/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$APPICON"
echo "==> Rendering iOS 1024 icon"
"$GEN" "$APPICON/icon_1024.png" 1024 ios
echo "==> Wrote $APPICON/icon_1024.png"
