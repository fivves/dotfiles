-- Keybindings for Hyprland 0.55+ (Lua config)
-- Converted from bindings.conf

---@module 'hl'

local terminal = "uwsm app -- " .. os.getenv("TERMINAL")
local browser = "omarchy-launch-browser"

-- Typing Hotkeys
hl.bind("CTRL + SUPER + SHIFT + P", hl.dsp.exec_cmd("wtype 'eddie.lucitt@patagonia.com'"))

-- Remove stupid Mac-style copy/paste / Tiling settings
hl.unbind("SUPER + SHIFT + V")
hl.unbind("SUPER + C")
hl.unbind("SUPER + V")
hl.unbind("SUPER + J")
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd("~/.config/hypr/pip-toggle.sh"))

-- Change lock bind to Windows-like
hl.unbind("SUPER + CTRL + L")
hl.bind("SUPER + L", hl.dsp.exec_cmd("omarchy-system-lock"))
hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("~/.local/bin/close-desktop-apps --force"))

hl.unbind("SUPER + SHIFT + BACKSPACE")
hl.bind("SUPER + SHIFT + BACKSPACE", hl.dsp.exec_cmd("omarchy-hyprland-window-gaps-toggle & omarchy-toggle-waybar"))

-- Control scratchpad
hl.bind("SUPER + grave", hl.dsp.workspace.toggle_special("scratchpad"))
hl.bind("SUPER + SHIFT + grave", hl.dsp.window.move({ workspace = "special:scratchpad" }, { follow = false }))

-- Launch Applications
hl.bind("SUPER + return", hl.dsp.exec_cmd(terminal .. " --dir=$(omarchy-cmd-terminal-cwd)"))
hl.bind("SUPER + A", hl.dsp.exec_cmd("omarchy-launch-tui hermes"))
hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("omarchy-launch-tui claude"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("uwsm app -- vesktop"))
hl.bind("SUPER + F", hl.dsp.exec_cmd("uwsm app -- nautilus --new-window"))
hl.bind("SUPER + H", hl.dsp.exec_cmd("uwsm app -- heroic"))
hl.bind("SUPER + M", hl.dsp.exec_cmd("uwsm app -- gtunes"))
hl.bind("SUPER + N", hl.dsp.exec_cmd("uwsm app -- nautilus --new-window"))
hl.bind("SUPER + O", hl.dsp.exec_cmd("omarchy-launch-or-focus obsidian \"uwsm-app -- obsidian\""))
hl.bind("SUPER + S", hl.dsp.exec_cmd("uwsm app -- steam"))
hl.bind("SUPER + T", hl.dsp.exec_cmd("omarchy-launch-tui btop"))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd(browser .. " --private"))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("omarchy-launch-tui cava"))
hl.bind("SUPER + SHIFT + J", hl.dsp.exec_cmd("uwsm app -- delfin"))
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("uwsm app -- youtube-music-desktop-app"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("bash -lc 'hyprctl dispatch exit'"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("uwsm app -- subl"))

-- Launch webapps
-- If your web app url contains #, type it as ## to prevent hyperland treat it as comments
hl.bind("SUPER + C", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp \"Notion Calendar\" \"https://calendar.notion.so/\""))
hl.bind("SUPER + G", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp \"Google Messages\" \"https://messages.google.com/web/conversations\""))
hl.bind("SUPER + R", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Reddit \"https://reddit.com\""))
hl.bind("SUPER + X", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp BlueSky \"https://bsky.app\""))
hl.bind("SUPER + Y", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp YouTube \"https://youtube.com/\""))
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp \"Google Maps\" \"https://google.com/maps\""))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Photopea \"https://photopea.com\""))
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Monochrome \"https://monochrome.tf/\""))

-- Work
hl.bind("SUPER + E", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Brivo \"https://access.brivo.com/users\""))
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Badge \"https://patagonia-my.sharepoint.com/:x:/p/robert_tamayo/IQAwR0fqj7tFQZcqBzTOPy5wAVOljM8P_eymaZDiDXel3ro?e=77in6w&wdOrigin=TEAMS-WEB.null_ns.rwc&wdExp=TEAMS-TREATMENT&wdhostclicktime=1773176758807&web=1\""))
hl.bind("SHIFT + ALT + E", hl.dsp.exec_cmd("omarchy-launch-or-focus-webapp Envoy \"https://dashboard.envoy.com/visitors/entries\""))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("/opt/outlook-for-linux/outlook-for-linux %U"))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("/opt/teams-for-linux/teams-for-linux %UV"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("uwsm app -- \"/opt/WhatsApp Desktop/whatsapp-linux-desktop\""))

-- Overwrite existing bindings, like putting Omarchy Menu on Super + Space
-- hl.unbind("SUPER + SPACE")
-- hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("omarchy-menu"))
