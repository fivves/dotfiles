#!/usr/bin/env bash

TUI="$HOME/.config/waybar/scripts/wordle-tui.py"

# Find whatever terminal is available
if command -v kitty &>/dev/null; then
    TERM_CMD="kitty --title=Wordle -e"
elif command -v foot &>/dev/null; then
    TERM_CMD="foot --title=Wordle"
elif command -v ghostty &>/dev/null; then
    TERM_CMD="kitty --title Wordle"
elif command -v alacritty &>/dev/null; then
    TERM_CMD="alacritty --title Wordle -e"
elif command -v wezterm &>/dev/null; then
    TERM_CMD="wezterm --title Wordle start"
else
    notify-send "Wordle" "No terminal emulator found!"
    exit 1
fi

# Launch as a floating window centered via hyprctl
hyprctl dispatch exec "[float; size 430 680; center] $TERM_CMD python3 $TUI"