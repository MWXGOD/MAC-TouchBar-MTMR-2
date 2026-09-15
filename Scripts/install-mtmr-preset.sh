#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# MTMR has one active preset location. The source remains isolated in MTMR-2,
# while installation intentionally switches that shared runtime configuration.
destination="$HOME/Library/Application Support/MTMR/items.json"
mkdir -p "$(dirname "$destination")"

if [[ -e "$destination" ]]; then
  backup="$destination.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$destination" "$backup"
  echo "backed up existing MTMR preset to $backup"
fi

sed "s|__PROJECT_DIR__|$project_dir|g" "$project_dir/MTMR/items.json" > "$destination"
defaults write Toxblh.MTMR com.toxblh.mtmr.settings.showControlStrip -bool true
echo "installed MTMR preset at $destination"
echo "enabled the macOS Control Strip"
echo "Restart MTMR or use its reload configuration command."
