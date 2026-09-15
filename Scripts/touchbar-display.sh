#!/bin/zsh
display_file="$HOME/Library/Application Support/TouchBarLyrics-MTMR-2/display.txt"
if [[ -s "$display_file" ]]; then
  lyric_line="$(/usr/bin/sed -n '1p' "$display_file" 2>/dev/null)"
  [[ -n "$lyric_line" ]] && printf '%s' "$lyric_line"
fi
exit 0
