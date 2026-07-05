#!/usr/bin/env bash
set -euo pipefail

# Syncs Adwaita-for-Steam colors with the current Omarchy/GTK theme via Millennium.
# Millennium must already be installed (https://steambrew.app).

SYNC_SCRIPT_PATH="$HOME/.local/bin/sync-steam-from-gtk.py"
HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
HOOK_PATH="$HOOK_DIR/sync-steam-from-gtk.sh"
SYSTEMD_DIR="$HOME/.config/systemd/user"

log() { printf 'omarchy-adwaita-for-steam-theme-sync: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  install-omarchy-adwaita-for-steam-theme-sync.sh          Install and sync now
  install-omarchy-adwaita-for-steam-theme-sync.sh --sync   Sync colors now (no reinstall)

Installs a sync script that reads ~/.config/gtk-4.0/gtk.css and generates an
"Omarchy" color theme for Adwaita-for-Steam running under Millennium. The hook
fires automatically after `omarchy theme set` and whenever gtk.css changes.

Requirements: Millennium (https://steambrew.app), Adwaita-for-Steam installed
as a Millennium theme.
USAGE
}

sync_colors() {
  [[ -f $SYNC_SCRIPT_PATH ]] || die "Sync script not found: $SYNC_SCRIPT_PATH. Run without --sync to install first."
  python3 "$SYNC_SCRIPT_PATH"
}

install_sync_script() {
  mkdir -p "$(dirname "$SYNC_SCRIPT_PATH")"

  cat >"$SYNC_SCRIPT_PATH" <<'PYEOF'
#!/usr/bin/env python3
"""Sync Adwaita-for-Steam (Millennium) color theme from ~/.config/gtk-4.0/gtk.css."""

import json
import os
import re
import sys
from pathlib import Path

GTK_CSS_PATH = Path(os.environ.get("GTK_CSS_FILE", Path.home() / ".config/gtk-4.0/gtk.css"))
THEME_DIR = Path(os.environ.get(
    "ADWAITA_MILLENNIUM_DIR",
    Path.home() / ".local/share/Steam/millennium/themes/Adwaita-for-Steam"
))
MILLENNIUM_CONFIG = Path.home() / ".config/millennium/config.json"
COLOR_THEME_NAME = "Omarchy"
COLOR_THEME_SLUG = "omarchy"
COLOR_THEME_CSS = THEME_DIR / "adwaita/colorthemes" / COLOR_THEME_SLUG / f"{COLOR_THEME_SLUG}.css"
SKIN_JSON = THEME_DIR / "skin.json"


def parse_gtk_colors(css_path: Path) -> dict[str, str]:
    colors = {}
    for m in re.finditer(r"@define-color\s+(\w+)\s+(.+?)\s*;", css_path.read_text()):
        name = m.group(1)
        value = re.sub(r"/\*.*?\*/", "", m.group(2)).strip()
        colors[name] = value
    return colors


def resolve(colors: dict, value: str, depth: int = 0) -> str:
    if depth > 20:
        return "#000000"
    m = re.fullmatch(r"@(\w+)", value)
    if m:
        return resolve(colors, colors.get(m.group(1), "#000000"), depth + 1)
    m = re.fullmatch(r"alpha\((.+?),\s*([0-9.]+)\)", value)
    if m:
        color = resolve(colors, m.group(1).strip(), depth + 1)
        opacity = float(m.group(2))
        bg = resolve(colors, colors.get("background", "#000000"), depth + 1)
        return blend(bg, color, opacity)
    if value.startswith("#"):
        return value
    return "#000000"


def blend(base: str, overlay: str, opacity: float) -> str:
    br, bg_, bb = _hex(base)
    or_, og, ob = _hex(overlay)
    r = round(br * (1 - opacity) + or_ * opacity)
    g = round(bg_ * (1 - opacity) + og * opacity)
    b = round(bb * (1 - opacity) + ob * opacity)
    return f"#{r:02x}{g:02x}{b:02x}"


def _hex(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def to_rgba(h: str, a: float) -> str:
    r, g, b = _hex(h)
    return f"rgba({r}, {g}, {b}, {a})"


def main():
    if not GTK_CSS_PATH.exists():
        print(f"error: GTK CSS not found: {GTK_CSS_PATH}", file=sys.stderr)
        sys.exit(1)

    if not THEME_DIR.exists():
        print(f"error: Millennium Adwaita-for-Steam not found: {THEME_DIR}", file=sys.stderr)
        sys.exit(1)

    raw = parse_gtk_colors(GTK_CSS_PATH)

    def c(name: str) -> str:
        return resolve(raw, raw.get(name, "#000000"))

    bg = c("background")
    fg = c("foreground")
    black = c("black")

    accent_bg = c("accent_bg_color")
    accent_fg = c("accent_fg_color")
    accent = c("accent_color")

    red = c("destructive_bg_color")
    red_bright = c("bright_red") if "bright_red" in raw else red
    green = c("success_bg_color")
    green_bright = c("bright_green") if "bright_green" in raw else green
    yellow = c("warning_bg_color")

    headerbar = c("headerbar_bg_color")
    headerbar_backdrop = c("headerbar_backdrop_color") if "headerbar_backdrop_color" in raw else black
    sidebar = c("sidebar_bg_color") if "sidebar_bg_color" in raw else black
    sidebar_backdrop = c("sidebar_backdrop_color") if "sidebar_backdrop_color" in raw else black
    popover = c("popover_bg_color") if "popover_bg_color" in raw else black
    dialog = c("dialog_bg_color") if "dialog_bg_color" in raw else bg

    css = f"""\
:root
{{
\t--adw-color-scheme: dark !important;

\t--adw-accent-bg-light: {accent_bg} !important;
\t--adw-accent-bg-dark: {accent_bg} !important;
\t--adw-accent-fg: {accent_fg} !important;

\t--adw-destructive-bg-light: {red} !important;
\t--adw-destructive-bg-dark: {red} !important;
\t--adw-destructive-fg: {accent_fg} !important;

\t--adw-success-bg-light: {green} !important;
\t--adw-success-bg-dark: {green} !important;
\t--adw-success-fg: {accent_fg} !important;

\t--adw-warning-bg-light: {yellow} !important;
\t--adw-warning-bg-dark: {yellow} !important;
\t--adw-warning-fg: {to_rgba(accent_fg, 0.8)} !important;

\t--adw-error-bg-light: {red} !important;
\t--adw-error-bg-dark: {red} !important;
\t--adw-error-fg: {accent_fg} !important;

\t--adw-window-bg: {bg} !important;
\t--adw-window-fg: {fg} !important;

\t--adw-view-bg: {black} !important;
\t--adw-view-fg: {fg} !important;

\t--adw-headerbar-bg: {headerbar} !important;
\t--adw-headerbar-fg: {fg} !important;
\t--adw-headerbar-backdrop: {headerbar_backdrop} !important;
\t--adw-headerbar-shade: {to_rgba(black, 0.36)} !important;
\t--adw-headerbar-darker-shade: {to_rgba(black, 0.9)} !important;

\t--adw-sidebar-bg: {sidebar} !important;
\t--adw-sidebar-fg: {fg} !important;
\t--adw-sidebar-backdrop: {sidebar_backdrop} !important;
\t--adw-sidebar-shade: {to_rgba(black, 0.25)} !important;

\t--adw-secondary-sidebar-bg: {sidebar} !important;
\t--adw-secondary-sidebar-fg: {fg} !important;
\t--adw-secondary-sidebar-backdrop: {sidebar_backdrop} !important;
\t--adw-secondary-sidebar-shade: {to_rgba(black, 0.25)} !important;

\t--adw-card-bg: {to_rgba(fg, 0.08)} !important;
\t--adw-card-fg: {fg} !important;
\t--adw-card-shade: {to_rgba(black, 0.36)} !important;

\t--adw-dialog-bg: {dialog} !important;
\t--adw-dialog-fg: {fg} !important;

\t--adw-popover-bg: {popover} !important;
\t--adw-popover-fg: {fg} !important;
\t--adw-popover-shade: {to_rgba(black, 0.25)} !important;

\t--adw-thumbnail-bg: {popover} !important;
\t--adw-thumbnail-fg: {fg} !important;

\t--adw-shade: {to_rgba(black, 0.25)} !important;

\t--adw-banner: {blend(bg, fg, 0.5)} !important;

\t--adw-user-online: {accent} !important;
\t--adw-user-ingame: {green_bright} !important;
}}
"""

    COLOR_THEME_CSS.parent.mkdir(parents=True, exist_ok=True)
    COLOR_THEME_CSS.write_text(css)
    print(f"Generated {COLOR_THEME_CSS}", file=sys.stderr)

    # Add "Omarchy" to skin.json conditions if not already there
    if SKIN_JSON.exists():
        skin = json.loads(SKIN_JSON.read_text())
        color_theme_values = skin.get("Conditions", {}).get("Color theme", {}).get("values", {})
        if COLOR_THEME_NAME not in color_theme_values:
            color_theme_values[COLOR_THEME_NAME] = {
                "TargetCss": {
                    "affects": [".*"],
                    "src": f"adwaita/colorthemes/{COLOR_THEME_SLUG}/{COLOR_THEME_SLUG}.css"
                }
            }
            SKIN_JSON.write_text(json.dumps(skin, indent="\t"))
            print(f"Added '{COLOR_THEME_NAME}' to skin.json", file=sys.stderr)

    # Activate the Omarchy color theme in Millennium config
    if MILLENNIUM_CONFIG.exists():
        config = json.loads(MILLENNIUM_CONFIG.read_text())
        conditions = config.setdefault("themes", {}).setdefault("conditions", {}).setdefault("Adwaita-for-Steam", {})
        if conditions.get("Color theme") != COLOR_THEME_NAME:
            conditions["Color theme"] = COLOR_THEME_NAME
            MILLENNIUM_CONFIG.write_text(json.dumps(config, indent=4))
            print(f"Set active color theme to '{COLOR_THEME_NAME}' in Millennium config", file=sys.stderr)

    print("Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
PYEOF

  chmod +x "$SYNC_SCRIPT_PATH"
  log "Installed sync script at $SYNC_SCRIPT_PATH"
}

install_hook() {
  mkdir -p "$HOOK_DIR"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exec "$HOME/.local/bin/sync-steam-from-gtk.py" "$@"' \
    >"$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  log "Installed Omarchy hook at $HOOK_PATH"
}

install_systemd_units() {
  mkdir -p "$SYSTEMD_DIR"

  cat >"$SYSTEMD_DIR/sync-steam-from-gtk.service" <<'EOF'
[Unit]
Description=Sync Adwaita-for-Steam (Millennium) colors from GTK4 CSS

[Service]
Type=oneshot
ExecStart=%h/.local/bin/sync-steam-from-gtk.py
StandardOutput=journal
StandardError=journal
EOF

  cat >"$SYSTEMD_DIR/sync-steam-from-gtk.path" <<'EOF'
[Unit]
Description=Watch GTK4 CSS for Adwaita-for-Steam (Millennium) sync

[Path]
PathModified=%h/.config/gtk-4.0/gtk.css

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now sync-steam-from-gtk.path
  log "Enabled systemd path watcher for gtk.css"
}

install_all() {
  command -v python3 >/dev/null || die "python3 is required"

  [[ -d "$HOME/.local/share/Steam/millennium/themes/Adwaita-for-Steam" ]] \
    || die "Adwaita-for-Steam not found in Millennium themes. Install Millennium (https://steambrew.app) and add the Adwaita-for-Steam theme first."

  install_sync_script
  install_hook
  install_systemd_units

  log "Running initial sync..."
  python3 "$SYNC_SCRIPT_PATH"
  log "Done. Restart Steam for colors to take effect."
}

case "${1:-}" in
  ""|--install) install_all ;;
  --sync)       sync_colors ;;
  -h|--help)    usage ;;
  *) usage >&2; exit 2 ;;
esac
