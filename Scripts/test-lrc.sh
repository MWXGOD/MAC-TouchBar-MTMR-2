#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/Tests/test_lrc.py"
python3 "$project_dir/Tests/test_agent.py"
