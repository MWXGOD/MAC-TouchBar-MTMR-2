#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
build_dir="$project_dir/build/native-touchbar"
app_dir="$build_dir/MTMR-2.app"
mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

/usr/bin/clang -fobjc-arc -isysroot "$sdk" -mmacosx-version-min=11.0 \
  -I "$project_dir/Sources" \
  -framework AppKit -framework Foundation -F/System/Library/PrivateFrameworks \
  -framework DFRFoundation -ldl \
  "$project_dir/Sources/NativeTouchBarController.m" \
  -o "$app_dir/Contents/MacOS/MTMR-2"

cp "$project_dir/build/touchbar-media-command" "$app_dir/Contents/Resources/touchbar-media-command"
cp "$project_dir/Assets/mtmr-logo.png" "$app_dir/Contents/Resources/mtmr-logo.png"
chmod 755 "$app_dir/Contents/MacOS/MTMR-2" "$app_dir/Contents/Resources/touchbar-media-command"
cp "$project_dir/Resources/native-touchbar-Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
