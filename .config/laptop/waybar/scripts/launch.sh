#!/usr/bin/env bash
set -euo pipefail

base_config="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
runtime_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
runtime_config="$runtime_dir/config.jsonc"

mkdir -p "$runtime_dir"

monitors_json="$(hyprctl monitors -j 2>/dev/null || true)"

monitor="$(printf '%s' "$monitors_json" | jq -r '
    if type == "array" then
      (
        map(select(.x == 0 and .y == 0))[0].name //
        map(select(.focused == true))[0].name //
        .[0].name //
        empty
      )
    else
      empty
    end
  ' 2>/dev/null || true)"

if [[ -n "$monitor" ]]; then
  jq --arg output "$monitor" '.output = $output' "$base_config" > "$runtime_config"
else
  cp "$base_config" "$runtime_config"
fi

# Replace Omarchy's default Waybar instance with the monitor-specific config.
pkill -x waybar 2>/dev/null || true
exec /usr/bin/waybar --config "$runtime_config"
