#!/usr/bin/env bash

set -o pipefail

if ! command -v cava >/dev/null 2>&1; then
  printf '{"text":"▁▁▁▁▁▁▁▁▁▁","class":"missing","tooltip":"cava is not installed"}\n'
  exit 0
fi

cava -p "$HOME/.config/waybar/scripts/cava.conf" 2>/dev/null | awk -F';' '
  BEGIN {
    bars[0] = "▁"
    bars[1] = "▂"
    bars[2] = "▃"
    bars[3] = "▄"
    bars[4] = "▅"
    bars[5] = "▆"
    bars[6] = "▇"
    bars[7] = "█"
  }

  NF {
    text = ""
    for (i = 1; i <= NF; i++) {
      if ($i == "") continue
      level = int($i)
      if (level < 0) level = 0
      if (level > 7) level = 7
      text = text bars[level]
    }

    printf "{\"text\":\"%s\",\"tooltip\":\"CAVA\"}\n", text
    fflush()
  }
'
