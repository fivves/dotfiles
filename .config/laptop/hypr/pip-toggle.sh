#!/bin/bash

active=$(hyprctl activewindow -j) || exit 1
addr=$(echo "$active" | jq -r ".address // empty")

if [[ -z $addr || $addr == "0x0" ]]; then
  hyprctl notify -1 2500 "rgb(f38ba8)" "No active window to pin"
  exit 0
fi

pinned=$(echo "$active" | jq -r ".pinned // false")
floating=$(echo "$active" | jq -r ".floating // false")

if [[ $pinned == "true" ]]; then
  hyprctl -q --batch "dispatch pin address:$addr; dispatch tagwindow -pip address:$addr"

  if [[ $floating == "true" ]]; then
    hyprctl -q dispatch togglefloating "address:$addr"
  fi

  exit 0
fi

monitor_id=$(echo "$active" | jq -r ".monitor")
gaps_out=$(hyprctl getoption general:gaps_out -j | jq -r '.custom // "0 0 0 0"')
border_size=$(hyprctl getoption general:border_size -j | jq -r '.int // 0')

read -r gap_top gap_right gap_bottom gap_left <<< "$gaps_out"

read -r width height pos_x pos_y < <(
  hyprctl monitors -j | jq -r \
    --argjson id "$monitor_id" \
    --argjson gap_top "$gap_top" \
    --argjson gap_right "$gap_right" \
    --argjson gap_bottom "$gap_bottom" \
    --argjson gap_left "$gap_left" \
    --argjson border_size "$border_size" '
    .[] | select(.id == $id) |
    .width as $monitor_width |
    .height as $monitor_height |
    .x as $monitor_x |
    .y as $monitor_y |
    (.reserved[0] // 0) as $reserved_left |
    (.reserved[1] // 0) as $reserved_top |
    (.reserved[2] // 0) as $reserved_right |
    (.reserved[3] // 0) as $reserved_bottom |
    ($monitor_width - $reserved_left - $reserved_right - $gap_left - $gap_right - ($border_size * 2)) as $work_width |
    ([$work_width * 0.32 | floor, 600] | min) as $width |
    ($width * 9 / 16 | floor) as $height |
    ($monitor_x + $monitor_width - $reserved_right - $gap_right - $border_size - $width) as $pos_x |
    ($monitor_y + $reserved_top + $gap_top + $border_size) as $pos_y |
    "\($width) \($height) \($pos_x) \($pos_y)"
  '
)

if [[ -z $width ]]; then
  hyprctl notify -1 2500 "rgb(f38ba8)" "Could not find active monitor"
  exit 1
fi

if [[ $floating != "true" ]]; then
  hyprctl -q dispatch setfloating "address:$addr"
fi

hyprctl -q dispatch resizewindowpixel "exact $width $height,address:$addr"
hyprctl -q dispatch movewindowpixel "exact $pos_x $pos_y,address:$addr"
hyprctl -q --batch "dispatch pin address:$addr; dispatch alterzorder top address:$addr; dispatch tagwindow +pip address:$addr"
