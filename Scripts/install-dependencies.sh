#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This installer targets Apple Silicon Macs." >&2
  exit 1
fi

source_dir="$project_dir/build/nowplaying-cli-src"
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --depth 1 --branch v2.1.0 https://github.com/kirtan-shah/nowplaying-cli.git "$source_dir"
fi
make -C "$source_dir" -j2
cp "$source_dir/nowplaying-cli" "$project_dir/build/nowplaying-cli"
clang -O2 -framework Foundation "$project_dir/Sources/MediaRemoteCommand.m" \
  -o "$project_dir/build/touchbar-media-command"
mkdir -p "$project_dir/build/scripts" "$project_dir/build/build/mediaremote-mini"
cp "$source_dir/scripts/mediaremote-mini.pl" "$project_dir/build/scripts/mediaremote-mini.pl"
cp "$source_dir/build/mediaremote-mini/MediaRemoteMini.dylib" "$project_dir/build/build/mediaremote-mini/MediaRemoteMini.dylib"
chmod 755 "$project_dir/build/nowplaying-cli" "$project_dir/build/touchbar-media-command" "$project_dir/build/scripts/mediaremote-mini.pl"
chmod 644 "$project_dir/Scripts/netease-media-command.applescript"
echo "installed MediaRemote adapter at $project_dir/build/nowplaying-cli"

if command -v brew >/dev/null 2>&1; then
  brew install --cask mtmr
else
  echo "Homebrew is not installed; install MTMR manually from https://github.com/Toxblh/MTMR/releases" >&2
fi
