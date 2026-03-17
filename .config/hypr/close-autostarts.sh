#!/usr/bin/env bash
set -euo pipefail

# Targets from your hyprctl clients -j
PCPANEL_CLASS='com.getpcpanel.MainFX'
SD_CLASS='python3'  # Stream Deck UI is python3 class (title can vary)

log() { printf '[close-autostarts] %s\n' "$*" >&2; }

# Wait for Hyprland to be ready
for _ in {1..100}; do
  if hyprctl -j monitors >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

# Helper: list client addresses matching a class
find_addrs_by_class() {
  local class="$1"
  hyprctl -j clients \
    | jq -r --arg c "$class" '.[] | select(.class==$c) | .address'
}

# Close all windows for a given class (best-effort)
close_by_class() {
  local class="$1" name="$2"
  local tries=0
  local closed_any=0

  # Try up to ~3 seconds, as some windows appear late
  while [ $tries -lt 30 ]; do
    mapfile -t addrs < <(find_addrs_by_class "$class")
    if [ "${#addrs[@]}" -eq 0 ]; then
      sleep 0.1
      tries=$((tries+1))
      continue
    fi

    for addr in "${addrs[@]}"; do
      if [ -z "$addr" ]; then
        continue
      fi
      log "Closing $name at $addr"
      # Focus by address, then killactive (equivalent to SUPER+W)
      hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
      # Small grace; some XWayland windows need a brief moment
      sleep 0.03
      hyprctl dispatch killactive >/dev/null 2>&1 || true
      closed_any=1
      # Give compositor a tick to remove it before next iteration
      sleep 0.05
    done

    # Re-check if any remain; if none, we’re done for this class
    mapfile -t addrs2 < <(find_addrs_by_class "$class")
    if [ "${#addrs2[@]}" -eq 0 ]; then
      break
    fi

    tries=$((tries+1))
  done

  if [ $closed_any -eq 0 ]; then
    log "Did not find any $name windows to close (class=$class)"
  fi
}

# Optional: remember focused window to restore
prev_addr="$(hyprctl -j activewindow | jq -r '.address // empty')"

# Wait a bit so both windows have mapped; adjust if needed
sleep 0.3

close_by_class "$PCPANEL_CLASS" "PCPanel"
close_by_class "$SD_CLASS" "Stream Deck"

# Restore previous focus if still present
if [ -n "$prev_addr" ]; then
  hyprctl dispatch focuswindow "address:$prev_addr" >/dev/null 2>&1 || true
fi