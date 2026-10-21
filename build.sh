#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

identity=${SIGN_IDENTITY:--}
flags=(-c release)
[[ -n ${UNIVERSAL:-} ]] && flags+=(--arch arm64 --arch x86_64)

swift build $flags
bin=$(swift build $flags --show-bin-path)

app=build/Floatlate.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Floatlate" "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"

if [[ -n ${VERSION:-} ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$app/Contents/Info.plist"
fi

if [[ $identity == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi

echo "Built $app"
