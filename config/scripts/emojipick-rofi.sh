#!/usr/bin/env bash
# Wayland-native emoji picker built on the `emojipick` package.
# emojipick's own launcher uses dmenu + xclip (X11), which don't work under
# niri, so we reuse its emoji-list generator (emojiget.py) with rofi + wl-copy.
# First run downloads the emoji list to ~/.cache/emojiget (needs network once).

set -euo pipefail

choice=$(emojiget.py -c | rofi -dmenu -i -p "emoji" -l 15)
[ -n "${choice:-}" ] || exit 0

emoji=$(printf '%s' "$choice" | cut -d' ' -f1)
printf '%s' "$emoji" | wl-copy
notify-send -u low "Copied $emoji to clipboard" 2>/dev/null || true
