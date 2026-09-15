#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build"
/usr/bin/clang -fobjc-arc \
  -framework AppKit \
  -framework ApplicationServices \
  "$project_dir/Sources/ax-touchbar-probe.m" \
  -o "$project_dir/build/ax-touchbar-probe"
chmod 755 "$project_dir/build/ax-touchbar-probe"
echo "built $project_dir/build/ax-touchbar-probe"
