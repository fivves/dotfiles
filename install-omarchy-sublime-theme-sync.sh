#!/usr/bin/env bash
set -euo pipefail

SUBLIME_USER_DIR="$HOME/.config/sublime-text/Packages/User"
OMARCHY_HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
SYNC_SCRIPT="$SUBLIME_USER_DIR/omarchy_sublime_theme_sync.py"
HOOK_SCRIPT="$OMARCHY_HOOK_DIR/sync-sublime-text"

if [[ ! -d "$HOME/.config/omarchy/current/theme" ]]; then
  echo "Omarchy current theme not found at ~/.config/omarchy/current/theme" >&2
  exit 1
fi

command -v python3 >/dev/null || {
  echo "python3 is required" >&2
  exit 1
}

mkdir -p "$SUBLIME_USER_DIR" "$OMARCHY_HOOK_DIR"

cat >"$SYNC_SCRIPT" <<'PYTHON'
#!/usr/bin/env python3
import json
import re
from pathlib import Path


HOME = Path.home()
THEME_DIR = HOME / ".config/omarchy/current/theme"
THEME_NAME_PATH = HOME / ".config/omarchy/current/theme.name"
SUBLIME_USER_DIR = HOME / ".config/sublime-text/Packages/User"
COLOR_SCHEME_PATH = SUBLIME_USER_DIR / "Omarchy.sublime-color-scheme"
PREFERENCES_PATH = SUBLIME_USER_DIR / "Preferences.sublime-settings"


def read_colors():
    colors_path = THEME_DIR / "colors.toml"
    colors = {}

    for line in colors_path.read_text().splitlines():
        line = line.strip()
        match = re.match(r'^([A-Za-z0-9_]+)\s*=\s*"?(#[0-9A-Fa-f]{6})"?\s*(?:#.*)?$', line)
        if match:
            colors[match.group(1)] = match.group(2)

    required = {
        "background",
        "foreground",
        "cursor",
        "selection_background",
        "selection_foreground",
        "accent",
    }
    missing = sorted(required - colors.keys())
    if missing:
        raise SystemExit(f"Missing colors in {colors_path}: {', '.join(missing)}")

    return colors


def theme_display_name():
    if THEME_NAME_PATH.exists():
        name = THEME_NAME_PATH.read_text().strip()
        if name:
            return name.replace("-", " ").replace("_", " ").title()
    return "Omarchy"


def write_json(path, data):
    path.write_text(json.dumps(data, indent=4) + "\n")


def write_color_scheme(colors, display_name):
    data = {
        "name": f"Omarchy ({display_name})",
        "variables": {
            "bg": colors["background"],
            "fg": colors["foreground"],
            "accent": colors["accent"],
            "cursor": colors["cursor"],
            "selection_bg": colors["selection_background"],
            "selection_fg": colors["selection_foreground"],
            "black": colors.get("color0", colors["background"]),
            "red": colors.get("color1", colors["accent"]),
            "green": colors.get("color2", colors["accent"]),
            "yellow": colors.get("color3", colors["foreground"]),
            "blue": colors.get("color4", colors["accent"]),
            "magenta": colors.get("color5", colors["accent"]),
            "cyan": colors.get("color6", colors["accent"]),
            "white": colors.get("color7", colors["foreground"]),
            "dim": colors.get("color8", colors["foreground"]),
            "bright_red": colors.get("color9", colors.get("color1", colors["accent"])),
            "bright_green": colors.get("color10", colors.get("color2", colors["accent"])),
            "bright_yellow": colors.get("color11", colors.get("color3", colors["foreground"])),
            "bright_blue": colors.get("color12", colors.get("color4", colors["accent"])),
            "bright_magenta": colors.get("color13", colors.get("color5", colors["accent"])),
            "bright_cyan": colors.get("color14", colors.get("color6", colors["accent"])),
            "bright_white": colors.get("color15", colors["foreground"]),
        },
        "globals": {
            "foreground": "var(fg)",
            "background": "var(bg)",
            "caret": "var(cursor)",
            "line_highlight": "color(var(accent) alpha(0.18))",
            "selection": "color(var(selection_bg) alpha(0.35))",
            "selection_foreground": "var(selection_fg)",
            "misspelling": "var(red)",
            "active_guide": "color(var(accent) alpha(0.55))",
            "find_highlight": "var(yellow)",
            "find_highlight_foreground": "var(bg)",
            "brackets_foreground": "var(cursor)",
            "bracket_contents_foreground": "var(cursor)",
            "tags_options": "stippled_underline",
        },
        "rules": [
            {"scope": "comment, punctuation.definition.comment", "foreground": "var(dim)", "font_style": "italic"},
            {"scope": "keyword, storage, modifier", "foreground": "var(magenta)"},
            {"scope": "entity.name.function, support.function", "foreground": "var(blue)"},
            {"scope": "entity.name.type, support.type, storage.type", "foreground": "var(yellow)"},
            {"scope": "variable, variable.parameter", "foreground": "var(fg)"},
            {"scope": "string, punctuation.definition.string", "foreground": "var(green)"},
            {"scope": "constant.numeric, constant.language, constant.character", "foreground": "var(cyan)"},
            {"scope": "entity.name.tag, punctuation.definition.tag", "foreground": "var(red)"},
            {"scope": "entity.other.attribute-name", "foreground": "var(bright_yellow)"},
            {"scope": "markup.heading", "foreground": "var(blue)", "font_style": "bold"},
            {"scope": "markup.bold", "font_style": "bold"},
            {"scope": "markup.italic", "font_style": "italic"},
            {"scope": "markup.inserted", "foreground": "var(green)"},
            {"scope": "markup.deleted", "foreground": "var(red)"},
            {"scope": "markup.changed", "foreground": "var(yellow)"},
            {"scope": "invalid", "foreground": "var(bg)", "background": "var(red)"},
        ],
    }
    write_json(COLOR_SCHEME_PATH, data)


def read_preferences():
    if not PREFERENCES_PATH.exists():
        return {}

    raw = PREFERENCES_PATH.read_text().strip()
    if not raw:
        return {}

    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        backup = PREFERENCES_PATH.with_suffix(".sublime-settings.invalid")
        backup.write_text(PREFERENCES_PATH.read_text())
        raise SystemExit(f"Could not parse {PREFERENCES_PATH}; copied it to {backup}: {error}")


def update_preferences():
    preferences = read_preferences()
    preferences["theme"] = "Adaptive.sublime-theme"
    preferences["color_scheme"] = "Packages/User/Omarchy.sublime-color-scheme"
    write_json(PREFERENCES_PATH, preferences)


def main():
    SUBLIME_USER_DIR.mkdir(parents=True, exist_ok=True)
    colors = read_colors()
    display_name = theme_display_name()
    write_color_scheme(colors, display_name)
    update_preferences()
    print(f"Sublime Text color scheme now matches Omarchy theme: {display_name}")


if __name__ == "__main__":
    main()
PYTHON

cat >"$HOOK_SCRIPT" <<'BASH'
#!/usr/bin/env bash
python3 "$HOME/.config/sublime-text/Packages/User/omarchy_sublime_theme_sync.py"
BASH

chmod +x "$SYNC_SCRIPT" "$HOOK_SCRIPT"
rm -f "$SUBLIME_USER_DIR/Omarchy.sublime-theme"

python3 "$SYNC_SCRIPT"

echo
echo "Installed Omarchy -> Sublime Text theme sync."
echo "Future 'omarchy theme set ...' runs will refresh Sublime's color scheme."
echo "Restart Sublime Text if it is already open."
