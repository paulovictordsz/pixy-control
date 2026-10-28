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
# Assinatura: uma identidade FIXA faz o macOS lembrar as permissões (câmera) entre builds.
# Com "-" (ad hoc) o requisito é o hash do binário e cada build vira um app novo para o TCC.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier br.com.growdoc.pixybar "$APP"
echo "assinado com: $IDENTITY"
codesign -d -r- "$APP" 2>&1 | grep designated
echo "pronto: $APP"
