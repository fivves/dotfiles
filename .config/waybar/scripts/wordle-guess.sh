#!/usr/bin/env bash

TUI="$HOME/.config/waybar/scripts/wordle-tui.py"
WINDOW_SIZE="430 735"

# Find whatever terminal is available
if command -v kitty &>/dev/null; then
    TERM_CMD="kitty --title=Wordle -e"
elif command -v foot &>/dev/null; then
    TERM_CMD="foot --title=Wordle"
elif command -v ghostty &>/dev/null; then
    TERM_CMD="ghostty --title=Wordle -e"
elif command -v alacritty &>/dev/null; then
    TERM_CMD="alacritty --title Wordle -o window.dimensions.columns=52 -o window.dimensions.lines=40 -e"
elif command -v wezterm &>/dev/null; then
    TERM_CMD="wezterm --title Wordle start"
else
    notify-send "Wordle" "No terminal emulator found!"
    exit 1
fi

# Launch as a floating window centered via hyprctl.
# At the current Alacritty font metrics, 600px is only 33 rows; 735px clears
# the TUI's 40-row minimum without making the window unnecessarily wide.
hyprctl dispatch exec "[float; size $WINDOW_SIZE; center] $TERM_CMD python3 $TUI"
