#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build"
/usr/bin/clang -fobjc-arc \
  -framework Foundation \
  -framework IOKit \
  "$project_dir/Sources/hid-media-key.m" \
  -o "$project_dir/build/hid-media-key"
chmod 755 "$project_dir/build/hid-media-key"
echo "built $project_dir/build/hid-media-key"
