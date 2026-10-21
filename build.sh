#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

swift build -c release

app=build/Floatlate.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Floatlate "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - "$app"

echo "Built $app"
