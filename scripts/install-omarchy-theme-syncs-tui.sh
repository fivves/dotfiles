#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BRANDING_DIR="${OMARCHY_BRANDING_DIR:-$HOME/.config/omarchy/branding}"
FALLBACK_BRANDING_DIR="${OMARCHY_FALLBACK_BRANDING_DIR:-$SCRIPT_DIR/../omarchy/branding}"

bold=$'\033[1m'
dim=$'\033[2m'
reset=$'\033[0m'
accent=$'\033[38;5;45m'
ok=$'\033[38;5;114m'
warn=$'\033[38;5;214m'
bad=$'\033[38;5;203m'

# Coding-agent extension point:
# Add future theme installers here as one pipe-delimited entry:
#   "id|Display name|relative-or-absolute-script-path|Short description"
#
# Keep ids short, lowercase, and stable. The path may point to scripts with or
# without a .sh suffix. This registry is intentionally explicit so an agent can
# add new installers without relying on filename parsing or changing TUI logic.
INSTALLERS=(
  "steam|Adwaita for Steam|install-omarchy-adwaita-for-steam-theme-sync.sh|Sync Steam's Adwaita-for-Steam colors from the active Omarchy theme"
  "chatterino|Chatterino|install-omarchy-chatterino-theme-sync.sh|Generate and select a Chatterino theme from the active Omarchy palette"
  "heroic|Heroic|install-omarchy-heroic-theme-sync.sh|Generate and select a Heroic theme from the active Omarchy palette"
  "starship|Starship|install-omarchy-starship-theme.sh|Install the Omarchy-colored Starship prompt template and theme hook"
  "sublime|Sublime Text|install-omarchy-sublime-theme-sync.sh|Generate and select a Sublime Text color scheme from the active Omarchy palette"
  "vesktop|Vesktop|install-omarchy-vesktop-theme-sync|Copy and enable the active Omarchy Vencord theme in Vesktop"
  "zen|Zen Browser|install-omarchy-zen-theme-sync|Generate Zen profile chrome CSS from the active Omarchy theme"
)

declare -a SELECTED
declare -a RESULTS
cursor=0

for ((i = 0; i < ${#INSTALLERS[@]}; i++)); do
  SELECTED[$i]=0
done

terminal_width() {
  local width
  width="$(tput cols 2>/dev/null || true)"
  printf '%s\n' "${width:-80}"
}

file_width() {
  local path="$1"
  awk '{ if (length($0) > width) width = length($0) } END { print width + 0 }' "$path"
}

branding_path() {
  local branding_dir="$BRANDING_DIR"
  local width
  [[ -d "$branding_dir" ]] || branding_dir="$FALLBACK_BRANDING_DIR"
  width="$(terminal_width)"

  # The installer treats screensaver.txt as the branded wordmark. If a future
  # agent replaces or adds branding files, keep this order: wide wordmark first,
  # compact fallback second. The width check prevents wide ASCII art from
  # wrapping and breaking the TUI layout on smaller terminals.
  if [[ -f "$branding_dir/screensaver.txt" ]] && (( $(file_width "$branding_dir/screensaver.txt") <= width )); then
    printf '%s\n' "$branding_dir/screensaver.txt"
  elif [[ -f "$branding_dir/about.txt" ]]; then
    printf '%s\n' "$branding_dir/about.txt"
  fi
}

print_logo() {
  local logo
  logo="$(branding_path)"

  if [[ -n "$logo" && -f "$logo" ]]; then
    printf '%s' "$accent"
    local logo_width left_padding
    logo_width="$(file_width "$logo")"
    left_padding=$(( ( $(terminal_width) - logo_width ) / 2 ))
    (( left_padding < 0 )) && left_padding=0

    while IFS= read -r line; do
      printf '%*s%s\n' "$left_padding" '' "$line"
    done <"$logo"
    printf '%s' "$reset"
  else
    printf '%sOMARCHY%s\n' "$accent$bold" "$reset"
  fi
}

clear_screen() {
  printf '\033[2J\033[H'
}

field() {
  local entry="$1"
  local index="$2"
  IFS='|' read -r id label path description <<<"$entry"

  case "$index" in
    id) printf '%s\n' "$id" ;;
    label) printf '%s\n' "$label" ;;
    path) printf '%s\n' "$path" ;;
    description) printf '%s\n' "$description" ;;
  esac
}

installer_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$SCRIPT_DIR/$path"
  fi
}

selected_count() {
  local count=0
  local selected
  for selected in "${SELECTED[@]}"; do
    (( selected == 1 )) && ((count++))
  done
  printf '%s\n' "$count"
}

draw_ui() {
  local count width
  count="$(selected_count)"
  width="$(terminal_width)"

  clear_screen
  print_logo
  printf '\n'
  printf '%sOmarchy Theme Sync Installer%s\n' "$bold" "$reset"
  printf '%sUse arrow keys to move, Space to select, Enter to install.%s\n\n' "$dim" "$reset"

  for ((i = 0; i < ${#INSTALLERS[@]}; i++)); do
    local label description marker path full_path state pointer
    label="$(field "${INSTALLERS[$i]}" label)"
    description="$(field "${INSTALLERS[$i]}" description)"
    path="$(field "${INSTALLERS[$i]}" path)"
    full_path="$(installer_path "$path")"

    pointer=" "
    if (( i == cursor )); then
      pointer="${accent}>${reset}"
    fi

    marker="[ ]"
    state="$dim"
    if (( SELECTED[$i] == 1 )); then
      marker="[$ok*$reset]"
      state="$reset"
    fi

    if [[ ! -x "$full_path" ]]; then
      printf '%b %s%2d.%s %s %-18s %s%s%s\n' "$pointer" "$bad" "$((i + 1))" "$reset" "$marker" "$label" "$dim" "(missing or not executable)" "$reset"
    elif (( width >= 112 )); then
      printf '%b %s%2d.%s %s %s%-18s%s %s\n' "$pointer" "$accent" "$((i + 1))" "$reset" "$marker" "$state" "$label" "$reset" "$description"
    else
      # Narrow-terminal layout: keep the selectable row short, then print a
      # bounded description below it. Add new installers freely in INSTALLERS;
      # this presentation layer will keep long descriptions from wrapping.
      local description_width=$((width - 8))
      (( description_width < 24 )) && description_width=24
      printf '%b %s%2d.%s %s %s%s%s\n' "$pointer" "$accent" "$((i + 1))" "$reset" "$marker" "$state" "$label" "$reset"
      printf '      %s%.*s%s\n' "$dim" "$description_width" "$description" "$reset"
    fi
  done

  printf '\n'
  printf '%sSelected:%s %s/%s\n' "$bold" "$reset" "$count" "${#INSTALLERS[@]}"
  printf '%sKeys:%s %sUp/Down%s move, %sSpace%s select, %sEnter%s install, %sa%s all, %sn%s none, %sq%s quit\n' \
    "$bold" "$reset" "$accent" "$reset" "$accent" "$reset" "$accent" "$reset" "$accent" "$reset" "$accent" "$reset" "$accent" "$reset"
}

toggle_index() {
  local number="$1"
  local index=$((number - 1))

  if (( index < 0 || index >= ${#INSTALLERS[@]} )); then
    return
  fi

  if (( SELECTED[$index] == 1 )); then
    SELECTED[$index]=0
  else
    SELECTED[$index]=1
  fi
}

select_all() {
  for ((i = 0; i < ${#SELECTED[@]}; i++)); do
    SELECTED[$i]=1
  done
}

select_none() {
  for ((i = 0; i < ${#SELECTED[@]}; i++)); do
    SELECTED[$i]=0
  done
}

move_cursor() {
  local direction="$1"
  cursor=$((cursor + direction))

  if (( cursor < 0 )); then
    cursor=$((${#INSTALLERS[@]} - 1))
  elif (( cursor >= ${#INSTALLERS[@]} )); then
    cursor=0
  fi
}

select_ids() {
  local wanted id
  for wanted in "$@"; do
    [[ "$wanted" == "all" || "$wanted" == "--all" ]] && {
      select_all
      continue
    }

    for ((i = 0; i < ${#INSTALLERS[@]}; i++)); do
      id="$(field "${INSTALLERS[$i]}" id)"
      if [[ "$wanted" == "$id" ]]; then
        SELECTED[$i]=1
      fi
    done
  done
}

list_installers() {
  local id label path description
  for entry in "${INSTALLERS[@]}"; do
    id="$(field "$entry" id)"
    label="$(field "$entry" label)"
    path="$(field "$entry" path)"
    description="$(field "$entry" description)"
    printf '%-10s %-16s %-48s %s\n' "$id" "$label" "$path" "$description"
  done
}

run_selected() {
  local count
  count="$(selected_count)"
  if (( count == 0 )); then
    RESULTS+=("${warn}No installers selected.${reset}")
    return 1
  fi

  clear_screen
  print_logo
  printf '\n%sRunning %s installer(s)%s\n\n' "$bold" "$count" "$reset"

  local failed=0
  for ((i = 0; i < ${#INSTALLERS[@]}; i++)); do
    (( SELECTED[$i] == 1 )) || continue

    local label path full_path
    label="$(field "${INSTALLERS[$i]}" label)"
    path="$(field "${INSTALLERS[$i]}" path)"
    full_path="$(installer_path "$path")"

    if [[ ! -x "$full_path" ]]; then
      printf '%sSKIP%s %s: %s is missing or not executable\n' "$warn" "$reset" "$label" "$full_path"
      RESULTS+=("${warn}SKIP${reset} $label")
      failed=1
      continue
    fi

    printf '%sRUN %s%s\n' "$accent" "$label" "$reset"
    if "$full_path"; then
      printf '%sOK%s  %s\n\n' "$ok" "$reset" "$label"
      RESULTS+=("${ok}OK${reset}   $label")
    else
      local status=$?
      printf '%sFAIL%s %s exited with status %s\n\n' "$bad" "$reset" "$label" "$status"
      RESULTS+=("${bad}FAIL${reset} $label (exit $status)")
      failed=1
    fi
  done

  printf '%sSummary%s\n' "$bold" "$reset"
  printf '  %b\n' "${RESULTS[@]}"
  return "$failed"
}

usage() {
  cat <<USAGE
Usage:
  $(basename "$0")                 Open the interactive TUI
  $(basename "$0") --all           Install every registered theme sync
  $(basename "$0") --list          List registered installer ids
  $(basename "$0") id [id ...]     Install selected ids non-interactively

Examples:
  $(basename "$0") zen starship
  $(basename "$0") --all
USAGE
}

interactive() {
  local key install_status

  while true; do
    draw_ui

    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 0.05 key || key=""
        case "$key" in
          "[A") move_cursor -1 ;;
          "[B") move_cursor 1 ;;
        esac
        ;;
      " ")
        toggle_index "$((cursor + 1))"
        ;;
      "")
        run_selected
        install_status=$?
        printf '\nPress Enter to close.'
        IFS= read -r _
        return "$install_status"
        ;;
      q|Q)
        clear_screen
        return 0
        ;;
      a|A)
        select_all
        ;;
      n|N)
        select_none
        ;;
      j|J)
        move_cursor 1
        ;;
      k|K)
        move_cursor -1
        ;;
    esac
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      ;;
    --list)
      list_installers
      ;;
    --all)
      select_all
      run_selected
      ;;
    "")
      interactive
      ;;
    *)
      select_ids "$@"
      run_selected
      ;;
  esac
}

main "$@"
