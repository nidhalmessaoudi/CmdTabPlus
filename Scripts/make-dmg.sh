#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-build/CmdTabPlus.app}"
if [[ ! -d "$app" ]]; then
    printf 'App not found: %s\n' "$app" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
name="CmdTabPlus-${version}-universal.dmg"
mkdir -p build dist
stage="$(mktemp -d "$PWD/build/.dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/CmdTabPlus.app"
ln -s /Applications "$stage/Applications"
hdiutil create -srcfolder "$stage" -volname CmdTabPlus -fs HFS+ -format UDZO -ov "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
printf 'Packaged dist/%s\n' "$name"
