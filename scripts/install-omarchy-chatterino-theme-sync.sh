#!/usr/bin/env bash
set -uo pipefail

INSTALLER_PATH="$HOME/.local/bin/install-omarchy-chatterino-theme-sync.sh"
HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
HOOK_PATH="$HOOK_DIR/sync-chatterino"
THEME_DIR="$HOME/.config/omarchy/current/theme"
COLORS_FILE="$THEME_DIR/colors.toml"
THEME_NAME_FILE="$HOME/.config/omarchy/current/theme.name"
CHATTERINO_DIR="${CHATTERINO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/chatterino}"
CHATTERINO_SETTINGS_DIR="$CHATTERINO_DIR/Settings"
CHATTERINO_SETTINGS_PATH="$CHATTERINO_SETTINGS_DIR/settings.json"
CHATTERINO_THEMES_DIR="$CHATTERINO_DIR/Themes"
CHATTERINO_THEME_NAME="Omarchy"
CHATTERINO_THEME_PATH="$CHATTERINO_THEMES_DIR/$CHATTERINO_THEME_NAME.json"
CHATTERINO_THEME_SETTING="$CHATTERINO_THEME_NAME.json"

log() {
  printf 'omarchy-chatterino-theme-sync: %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  install-omarchy-chatterino-theme-sync.sh          Install the Omarchy hook and sync Chatterino now
  install-omarchy-chatterino-theme-sync.sh --sync   Sync Chatterino with the current Omarchy theme now

The hook runs after `omarchy theme set ...`, generates
~/.local/share/chatterino/Themes/Omarchy.json from the active Omarchy
colors.toml, and selects Omarchy.json in Chatterino's settings.

Set CHATTERINO_DIR before running if your Chatterino data directory is not
~/.local/share/chatterino.
USAGE
}

sync_chatterino() {
  if [[ ! -f "$COLORS_FILE" ]]; then
    log "No Omarchy colors file found at $COLORS_FILE"
    return 0
  fi

  if ! command -v python3 >/dev/null; then
    log "python3 is required to update Chatterino's JSON files"
    return 1
  fi

  mkdir -p "$CHATTERINO_SETTINGS_DIR" "$CHATTERINO_THEMES_DIR"

  python3 - "$COLORS_FILE" "$THEME_DIR" "$THEME_NAME_FILE" "$CHATTERINO_THEME_PATH" "$CHATTERINO_SETTINGS_PATH" "$CHATTERINO_THEME_SETTING" <<'PYTHON'
import json
import re
import shutil
import sys
from pathlib import Path

colors_path = Path(sys.argv[1])
theme_dir = Path(sys.argv[2])
theme_name_path = Path(sys.argv[3])
theme_path = Path(sys.argv[4])
settings_path = Path(sys.argv[5])
theme_setting = sys.argv[6]

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def read_colors(path):
    colors = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith(("\"", "'")):
            quote = value[0]
            value = value[1:].split(quote, 1)[0]
        else:
            value = value.split("#", 1)[0].strip()
        if HEX_RE.match(value):
            colors[key] = value.upper()
    return colors


def color(colors, key, fallback):
    value = colors.get(key, fallback)
    return value.upper() if HEX_RE.match(value) else fallback.upper()


def rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def hex_from_rgb(values):
    return "#" + "".join(f"{max(0, min(255, round(v))):02X}" for v in values)


def mix(a, b, amount):
    ar, ag, ab = rgb(a)
    br, bg, bb = rgb(b)
    return hex_from_rgb((
        ar + (br - ar) * amount,
        ag + (bg - ag) * amount,
        ab + (bb - ab) * amount,
    ))


def alpha(hex_color, alpha_byte):
    return f"#{alpha_byte}{hex_color.lstrip('#').upper()}"


colors = read_colors(colors_path)
is_light = (theme_dir / "light.mode").exists()
omarchy_theme_name = theme_name_path.read_text().strip() if theme_name_path.exists() else "unknown"

bg = color(colors, "background", "#FAFAFA" if is_light else "#111111")
fg = color(colors, "foreground", "#1A1A1A" if is_light else "#EEEEEE")
accent = color(colors, "accent", color(colors, "color4", "#00AEEF"))
cursor = color(colors, "cursor", fg)
selection_bg = color(colors, "selection_background", accent)
selection_fg = color(colors, "selection_foreground", bg)
muted = color(colors, "color8", mix(bg, fg, 0.45))
red = color(colors, "color1", "#FF5555")
yellow = color(colors, "color3", "#C7C715")

panel = mix(bg, fg, 0.07)
panel_hover = mix(bg, fg, 0.11)
panel_selected = mix(bg, accent, 0.30)
border = mix(bg, fg, 0.18)
input_bg = mix(bg, fg, 0.10)
disabled = alpha(bg, "99")

theme = {
    "$schema": "https://github.com/Chatterino/chatterino2/raw/master/docs/ChatterinoTheme.schema.json",
    "metadata": {
        "iconTheme": "dark" if is_light else "light",
        "fallbackTheme": "White" if is_light else "Black",
    },
    "colors": {
        "accent": accent,
        "messages": {
            "backgrounds": {"alternate": mix(bg, fg, 0.04), "regular": bg},
            "disabled": disabled,
            "highlightAnimationEnd": alpha(fg, "00"),
            "highlightAnimationStart": alpha(accent, "66"),
            "selection": alpha(selection_bg, "55"),
            "textColors": {
                "caret": cursor,
                "chatPlaceholder": muted,
                "link": accent,
                "regular": fg,
                "system": mix(fg, bg, 0.35),
            },
        },
        "overlayMessages": {
            "backgrounds": {"alternate": alpha(bg, "44"), "regular": "transparent"},
            "disabled": alpha(bg, "88"),
            "selection": alpha(selection_bg, "55"),
            "textColors": {
                "caret": cursor,
                "chatPlaceholder": muted,
                "link": accent,
                "regular": fg,
                "system": mix(fg, bg, 0.35),
            },
            "background": bg,
        },
        "scrollbars": {
            "background": "#00000000",
            "thumb": mix(bg, fg, 0.25),
            "thumbSelected": mix(bg, accent, 0.45),
        },
        "splits": {
            "background": bg,
            "dropPreview": alpha(accent, "30"),
            "dropPreviewBorder": accent,
            "dropTargetRect": alpha(accent, "30"),
            "dropTargetRectBorder": accent,
            "header": {
                "background": panel,
                "border": border,
                "focusedBackground": panel_selected,
                "focusedBorder": accent,
                "focusedText": fg,
                "text": fg,
            },
            "input": {"background": input_bg, "backgroundPulse": mix(bg, accent, 0.28), "text": fg},
            "messageSeperator": border,
            "resizeHandle": alpha(accent, "70"),
            "resizeHandleBackground": alpha(accent, "20"),
        },
        "tabs": {
            "liveIndicator": red,
            "rerunIndicator": yellow,
            "dividerLine": border,
            "highlighted": {
                "backgrounds": {"hover": panel_hover, "regular": panel, "unfocused": panel},
                "line": {"hover": accent, "regular": accent, "unfocused": accent},
                "text": fg,
            },
            "newMessage": {
                "backgrounds": {"hover": panel_hover, "regular": panel, "unfocused": panel},
                "line": {"hover": muted, "regular": muted, "unfocused": muted},
                "text": fg,
            },
            "regular": {
                "backgrounds": {"hover": panel_hover, "regular": panel, "unfocused": panel},
                "line": {"hover": border, "regular": border, "unfocused": border},
                "text": mix(fg, bg, 0.25),
            },
            "selected": {
                "backgrounds": {"hover": panel_selected, "regular": panel_selected, "unfocused": panel_selected},
                "line": {"hover": accent, "regular": accent, "unfocused": accent},
                "text": selection_fg if is_light else fg,
            },
        },
        "window": {"background": bg, "text": fg},
    },
}

theme_path.write_text(json.dumps(theme, indent=4) + "\n")

if settings_path.exists():
    raw = settings_path.read_text().strip()
    settings = json.loads(raw) if raw else {}
    backup_path = settings_path.with_name(settings_path.name + ".pre-omarchy-chatterino-theme-sync")
    if not backup_path.exists():
        shutil.copy2(settings_path, backup_path)
else:
    settings = {}

appearance = settings.setdefault("appearance", {})
theme_settings = appearance.setdefault("theme", {})
theme_settings["name"] = theme_setting
theme_settings["lightSystem"] = theme_setting
theme_settings["darkSystem"] = theme_setting

settings_path.write_text(json.dumps(settings, indent=4) + "\n")
print(f"wrote {theme_path} from Omarchy theme {omarchy_theme_name}")
print(f"selected {theme_setting} in {settings_path}")
PYTHON

  log "Synced Chatterino to the current Omarchy theme."
  if pgrep -x chatterino >/dev/null; then
    log "Restart Chatterino, or use /c2-theme-autoreload if you have it enabled, to see the change."
  fi
}

install_hook() {
  local source_path target_path

  mkdir -p "$HOME/.local/bin" "$HOOK_DIR"

  source_path=$(realpath -m "${BASH_SOURCE[0]}")
  target_path=$(realpath -m "$INSTALLER_PATH")
  if [[ "$source_path" != "$target_path" ]]; then
    cp "$source_path" "$INSTALLER_PATH"
  fi
  chmod +x "$INSTALLER_PATH"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exec "$HOME/.local/bin/install-omarchy-chatterino-theme-sync.sh" --sync "$@"' \
    >"$HOOK_PATH"
  chmod +x "$HOOK_PATH"

  log "Installed hook at $HOOK_PATH"
  "$INSTALLER_PATH" --sync
}

case "${1:-}" in
  ""|--install)
    install_hook
    ;;
  --sync)
    shift
    sync_chatterino "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
