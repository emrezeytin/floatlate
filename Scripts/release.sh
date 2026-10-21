#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

version=${1:?Usage: Scripts/release.sh <version>, for example 1.0.0}
tag=v$version
profile=${NOTARY_PROFILE:-floatlate}
identity=${SIGN_IDENTITY:-Developer ID Application}

if [[ -n $(git status --porcelain) ]]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi
git fetch -q origin
if [[ $(git rev-parse HEAD) != $(git rev-parse @{upstream}) ]]; then
    echo "Push your branch first, so the release matches GitHub." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

VERSION=$version UNIVERSAL=1 SIGN_IDENTITY=$identity ./build.sh
app=build/Floatlate.app
codesign --verify --strict --deep --verbose=2 "$app"

zip=build/Floatlate.zip
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
rm "$zip"

dmg=build/Floatlate-$version.dmg
staging=build/dmg
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Floatlate.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Floatlate -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"
rm -rf "$staging"

codesign --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"

spctl --assess --type execute --verbose "$app"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

git tag -a "$tag" -m "Floatlate $version"
git push origin "$tag"
gh release create "$tag" "$dmg" --title "Floatlate $version" --generate-notes \
    --notes "SHA-256: \`$(shasum -a 256 "$dmg" | cut -d' ' -f1)\`"

echo "Released $tag"
