#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
build_dir="$project_dir/build/native-touchbar"
app_dir="$build_dir/MTMR-2.app"
mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

if [[ ! -x "$project_dir/build/hid-media-key" ]]; then
  "$project_dir/Scripts/build-hid-media-key.sh"
fi

/usr/bin/clang -fobjc-arc -isysroot "$sdk" -mmacosx-version-min=11.0 \
  -I "$project_dir/Sources" \
  -framework AppKit -framework Foundation -framework CoreGraphics -framework ApplicationServices -F/System/Library/PrivateFrameworks \
  -framework DFRFoundation -ldl \
  "$project_dir/Sources/NativeTouchBarController.m" \
  -o "$app_dir/Contents/MacOS/MTMR-2"

cp "$project_dir/build/touchbar-media-command" "$app_dir/Contents/Resources/touchbar-media-command"
cp "$project_dir/build/hid-media-key" "$app_dir/Contents/Resources/hid-media-key"
cp "$project_dir/Assets/mtmr-logo.png" "$app_dir/Contents/Resources/mtmr-logo.png"
cp "$project_dir/Scripts/netease-media-command.applescript" "$app_dir/Contents/Resources/netease-media-command.applescript"
mkdir -p "$app_dir/Contents/Resources/netease-touchbar"
cp "$project_dir/Assets/netease-touchbar/TouchBarLast.png" \
  "$project_dir/Assets/netease-touchbar/TouchBarPlay.png" \
  "$project_dir/Assets/netease-touchbar/TouchBarPause.png" \
  "$project_dir/Assets/netease-touchbar/TouchBarNext.png" \
  "$app_dir/Contents/Resources/netease-touchbar/"
chmod 755 "$app_dir/Contents/MacOS/MTMR-2" \
  "$app_dir/Contents/Resources/touchbar-media-command" \
  "$app_dir/Contents/Resources/hid-media-key"
cp "$project_dir/Resources/native-touchbar-Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
