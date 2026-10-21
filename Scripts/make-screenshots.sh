#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

bin="$(mktemp -d)/screenshots"
sources=(Sources/Floatlate/*.swift)
xcrun swiftc -swift-version 5 -O -o "$bin" Scripts/Screenshots/main.swift ${sources:#*/main.swift}
"$bin" docs/screenshot.png

echo "Wrote docs/screenshot.png"
