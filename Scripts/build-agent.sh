#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build"
cp "$project_dir/Scripts/touchbar-lyrics-agent.py" "$project_dir/build/touchbar-lyrics-agent"
chmod 755 "$project_dir/build/touchbar-lyrics-agent"
echo "installed $project_dir/build/touchbar-lyrics-agent"
