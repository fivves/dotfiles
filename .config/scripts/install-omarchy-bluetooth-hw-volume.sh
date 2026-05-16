#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
CONFIG_FILE="$CONFIG_DIR/99-bluez-hw-volume.conf"

mkdir -p "$CONFIG_DIR"

cat >"$CONFIG_FILE" <<'WIREPLUMBER'
monitor.bluez.properties = {
  bluez5.enable-hw-volume = true
}

monitor.bluez.rules = [
  {
    matches = [
      {
        device.name = "~bluez_card.*"
      }
    ]
    actions = {
      update-props = {
        bluez5.hw-volume = [ a2dp_sink a2dp_source hfp_hf hsp_hs hfp_ag hsp_ag ]
      }
    }
  }
]
WIREPLUMBER

echo "Installed Bluetooth hardware volume config:"
echo "  $CONFIG_FILE"

if command -v systemctl >/dev/null; then
  echo "Restarting user audio services..."
  systemctl --user restart wireplumber pipewire pipewire-pulse
else
  echo "systemctl not found; reboot or restart PipeWire/WirePlumber manually." >&2
fi

echo
echo "Done. If the speaker was already connected, disconnect and reconnect it once."
echo "Waybar volume scroll should now control the Bluetooth speaker volume."
