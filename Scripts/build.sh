#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"

args=(-c release --disable-sandbox)
if [[ "${1:-}" == "--universal" ]]; then
    args+=(--arch arm64 --arch x86_64)
elif [[ $# -gt 0 ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 1
fi
swift build "${args[@]}"
bin_dir="$(swift build "${args[@]}" --show-bin-path)"

# Stage the bundle before replacing it. Never overwrite a running executable.
mkdir -p build
stage="$(mktemp -d "$PWD/build/.package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/CmdTabPlus.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CmdTabPlus" "$app/Contents/MacOS/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
if [[ -e build/CmdTabPlus.app ]]; then
    mv build/CmdTabPlus.app "$stage/previous.app"
fi
mv "$app" build/CmdTabPlus.app
printf 'Built %s/build/CmdTabPlus.app\n' "$PWD"
