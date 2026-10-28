#!/bin/zsh
# Compila e monta build/PixyBar.app (app de barra de menu, sem Xcode).
set -e
set -o pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -5
APP=build/PixyBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PixyBar "$APP/Contents/MacOS/PixyBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuIcon.png Resources/MenuIcon@2x.png Resources/MenuIconOff.png Resources/MenuIconOff@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "pronto: $APP"
