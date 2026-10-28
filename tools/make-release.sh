#!/bin/zsh
# Monta PixyBar.app e gera dist/PixyBar-<versão>.zip e dist/PixyBar-<versão>.dmg
set -e
set -o pipefail
cd "$(dirname "$0")/.."
./PixyBar/build.sh
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" PixyBar/Resources/Info.plist)
rm -rf dist && mkdir -p dist
ditto -c -k --keepParent PixyBar/build/PixyBar.app "dist/PixyBar-$VER.zip"
STAGE=$(mktemp -d)
cp -R PixyBar/build/PixyBar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "PixyBar $VER" -srcfolder "$STAGE" -ov -format UDZO "dist/PixyBar-$VER.dmg"
rm -rf "$STAGE"
ls -la dist
