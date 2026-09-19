#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build.sh --universal
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
mkdir -p dist
archive="CmdTabPlus-${version}-universal.zip"
rm -f "dist/$archive"
ditto -c -k --sequesterRsrc --keepParent build/CmdTabPlus.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Packaged dist/%s\n' "$archive"
