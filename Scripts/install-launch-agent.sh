#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
agent="$project_dir/build/touchbar-lyrics-agent"
if [[ ! -x "$agent" ]]; then
  "$project_dir/Scripts/build-agent.sh"
fi

launch_agents="$HOME/Library/LaunchAgents"
mkdir -p "$launch_agents"
sed -e "s|__AGENT_PATH__|$agent|g" -e "s|__LOG_PATH__|$HOME/Library/Logs/touchbarlyrics-mtmr2.log|g" \
  "$project_dir/LaunchAgents/com.ahs.touchbarlyrics.plist.in" > "$launch_agents/com.ahs.touchbarlyrics.mtmr2.plist"
# Only one lyric agent may own the display state at a time.
launchctl bootout "gui/$(id -u)/com.ahs.touchbarlyrics" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.ahs.touchbarlyrics.mtmr2" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$launch_agents/com.ahs.touchbarlyrics.mtmr2.plist"
echo "installed com.ahs.touchbarlyrics.mtmr2"
