#!/bin/sh
set -eu

template_dir="$HOME/.config/omarchy/themed"
hook_dir="$HOME/.config/omarchy/hooks/theme-set.d"
template_path="$template_dir/starship.toml.tpl"
hook_path="$hook_dir/sync-starship"
starship_path="$HOME/.config/starship.toml"
current_theme_dir="$HOME/.config/omarchy/current/theme"
current_starship="$current_theme_dir/starship.toml"
colors_file="$current_theme_dir/colors.toml"

mkdir -p "$template_dir" "$hook_dir" "$HOME/.config"

if [ -f "$starship_path" ]; then
  backup_path="$starship_path.bak.$(date +%s)"
  cp "$starship_path" "$backup_path"
  echo "Backed up existing Starship config to $backup_path"
fi

cat > "$template_path" <<'STARSHIP_TEMPLATE'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[]({{ color5 }})\
$os\
$username\
[](bg:{{ color1 }} fg:{{ color5 }})\
$directory\
[](fg:{{ color1 }} bg:{{ color3 }})\
$git_branch\
$git_status\
[](fg:{{ color3 }} bg:{{ color4 }})\
$c\
$elixir\
$elm\
$golang\
$gradle\
$haskell\
$java\
$julia\
$nodejs\
$nim\
$rust\
$scala\
[](fg:{{ color4 }} bg:{{ color6 }})\
$docker_context\
[](fg:{{ color6 }} bg:{{ color8 }})\
$time\
[ ](fg:{{ color8 }})\
"""

# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like   or disable this
# and use the os module below
[username]
show_always = true
style_user = "fg:{{ background }} bg:{{ color5 }}"
style_root = "fg:{{ background }} bg:{{ color5 }}"
format = '[$user ]($style)'
disabled = false

# An alternative to the username module which displays a symbol that
# represents the current operating system
[os]
style = "fg:{{ background }} bg:{{ color5 }}"
disabled = true # Disabled by default

[directory]
style = "fg:{{ background }} bg:{{ color1 }}"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = " 󰈙 "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important 󰈙 " = " 󰈙 "

[c]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[cpp]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "fg:{{ background }} bg:{{ color6 }}"
format = '[ $symbol $context ]($style)'

[elixir]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "fg:{{ background }} bg:{{ color3 }}"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "fg:{{ background }} bg:{{ color3 }}"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[gradle]
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = "󰆥 "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[rust]
symbol = ""
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[scala]
symbol = " "
style = "fg:{{ background }} bg:{{ color4 }}"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "fg:{{ foreground }} bg:{{ color8 }}"
format = '[ ♥ $time ]($style)'
STARSHIP_TEMPLATE

cat > "$hook_path" <<'STARSHIP_HOOK'
#!/usr/bin/env bash
set -euo pipefail

theme_starship="$HOME/.config/omarchy/current/theme/starship.toml"

if [[ -f "$theme_starship" ]]; then
  cp "$theme_starship" "$HOME/.config/starship.toml"
fi
STARSHIP_HOOK

chmod +x "$hook_path"

hex_to_rgb() {
  hex=$(printf '%s' "$1" | sed 's/^#//')
  r=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c1-2)")
  g=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c3-4)")
  b=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c5-6)")
  printf '%s,%s,%s' "$r" "$g" "$b"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

render_current_starship() {
  if [ ! -f "$colors_file" ]; then
    echo "No current Omarchy colors file found at $colors_file"
    echo "The Starship template and hook are installed; run 'omarchy theme set <theme>' later to apply it."
    return 0
  fi

  sed_script=$(mktemp)

  while IFS='=' read -r key value; do
    key=$(printf '%s' "$key" | tr -d '"'\'' ')
    case "$key" in
      ''|\#*) continue ;;
    esac

    value=$(printf '%s' "$value" | sed 's/^[^"'\'']*["'\'']//; s/["'\''].*$//')
    escaped_value=$(escape_sed_replacement "$value")
    stripped_value=$(escape_sed_replacement "$(printf '%s' "$value" | sed 's/^#//')")

    printf 's|{{ %s }}|%s|g\n' "$key" "$escaped_value" >> "$sed_script"
    printf 's|{{ %s_strip }}|%s|g\n' "$key" "$stripped_value" >> "$sed_script"

    case "$value" in
      \#??????)
        rgb_value=$(hex_to_rgb "$value")
        printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$rgb_value" >> "$sed_script"
        ;;
    esac
  done < "$colors_file"

  sed -f "$sed_script" "$template_path" > "$starship_path"
  mkdir -p "$current_theme_dir"
  cp "$starship_path" "$current_starship"
  rm -f "$sed_script"
  echo "Applied current Omarchy theme colors to $starship_path"
}

render_current_starship

if command -v starship >/dev/null 2>&1; then
  starship prompt --status 0 >/dev/null
  echo "Starship config validated."
else
  echo "Starship command not found; installed files without validation."
fi

echo "Installed:"
echo "  $template_path"
echo "  $hook_path"
echo "  $starship_path"
