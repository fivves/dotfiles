#!/usr/bin/env bash

set -euo pipefail

title="Twitch"
class="org.omarchy.terminal"
width=700
height=330

addresses_for_twitch_menu() {
  hyprctl clients -j |
    jq -r --arg class "$class" --arg title "$title" \
      '.[] | select(.class == $class and .title == $title) | .address'
}

existing="$(addresses_for_twitch_menu || true)"

setsid uwsm-app -- alacritty \
  --class "$class" \
  --title "$title" \
  --option 'window.dimensions.columns=68' \
  --option 'window.dimensions.lines=15' \
  --command python3 "$HOME/.config/waybar/scripts/twitch.py" --menu \
  >/dev/null 2>&1 &
disown

for _ in {1..80}; do
  while read -r addr; do
    if [[ -n "$addr" && "$addr" != "null" ]] && ! grep -Fxq "$addr" <<<"$existing"; then
      hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
      hyprctl dispatch resizewindowpixel "exact $width $height,address:$addr" >/dev/null 2>&1 || true
      hyprctl dispatch centerwindow >/dev/null 2>&1 || true
      exit 0
    fi
  done < <(addresses_for_twitch_menu || true)
  sleep 0.05
done
