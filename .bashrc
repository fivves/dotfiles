# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

fastfetch

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

alias ss='omarchy-launch-screensaver & exit'
alias fonts='fc-cache -fv'
alias notify='notify-send "Test notification" "If you can read this, the gremlins are off duty."'
alias pcp='java -jar /home/eddie/Apps/PCPanel/pcpanel.jar'

gitty() {
    git add .
    git commit -m "$*"
    git push
}

twitch() {
  local channel="$1"

  if [[ -z "$channel" ]]; then
    echo "Usage: twitch <channelname>"
    return 1
  fi

  hyprctl dispatch workspace 7
  streamlink "twitch.tv/$channel" best --player mpv &
  sleep 2
  chatterino --channels "t:$channel" &
  sleep 2
  hyprctl dispatch splitratio -0.25

  exit
}