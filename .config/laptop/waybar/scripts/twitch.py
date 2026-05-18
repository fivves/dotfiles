#!/usr/bin/env python3

import argparse
import curses
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ICON = ""
CONFIG_FILE = Path.home() / ".config" / "waybar" / "twitch.json"
API_BASE = "https://api.twitch.tv/helix"
USER_WIDTH = 18
GAME_WIDTH = 26
TWITCH_WORKSPACE = "7"
TWITCH_MONITOR = "HDMI-A-1"
TWITCH_MPV_CLASS = "mpv-twitch"


def output(tooltip, css_class=None):
    payload = {
        "text": ICON,
        "tooltip": tooltip,
    }
    if css_class:
        payload["class"] = css_class
    print(json.dumps(payload))


def load_config():
    config = {}
    if CONFIG_FILE.exists():
        try:
            config = json.loads(CONFIG_FILE.read_text())
        except Exception as exc:
            output(f"Twitch\nCould not read {CONFIG_FILE}: {exc}", "error")
            sys.exit(0)

    def get(name, default=None):
        return os.environ.get(name) or config.get(name.lower()) or config.get(name, default)

    return {
        "client_id": get("TWITCH_CLIENT_ID"),
        "access_token": get("TWITCH_ACCESS_TOKEN"),
        "followed_user_id": get("TWITCH_FOLLOWED_USER_ID"),
        "user_logins": split_list(get("TWITCH_USER_LOGINS", [])),
        "user_ids": split_list(get("TWITCH_USER_IDS", [])),
    }


def split_list(value):
    if not value:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [item.strip() for item in str(value).replace(",", " ").split() if item.strip()]


def twitch_get(path, params, client_id, access_token):
    query = urllib.parse.urlencode(params, doseq=True)
    request = urllib.request.Request(
        f"{API_BASE}{path}?{query}",
        headers={
            "Client-ID": client_id,
            "Authorization": f"Bearer {access_token}",
        },
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def live_streams(config):
    params = {"first": 100}

    if config["followed_user_id"]:
        params["user_id"] = config["followed_user_id"]
        return twitch_get(
            "/streams/followed",
            params,
            config["client_id"],
            config["access_token"],
        ).get("data", [])

    if not config["user_logins"] and not config["user_ids"]:
        output(
            "Twitch\nSet TWITCH_FOLLOWED_USER_ID for followed streams, "
            "or TWITCH_USER_LOGINS/TWITCH_USER_IDS for a channel list.",
            "error",
        )
        sys.exit(0)

    params["user_login"] = config["user_logins"][:100]
    params["user_id"] = config["user_ids"][:100]
    return twitch_get(
        "/streams",
        params,
        config["client_id"],
        config["access_token"],
    ).get("data", [])


def truncate(value, width):
    value = " ".join(str(value).split())
    if len(value) <= width:
        return value
    return value[: max(0, width - 1)] + "…"


def viewer_count(value):
    if not isinstance(value, int):
        return "?"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if value >= 10_000:
        return f"{round(value / 1_000):.0f}K"
    if value >= 1_000:
        return f"{value / 1_000:.1f}K"
    return str(value)


def stream_row(stream):
    user = stream.get("user_name") or stream.get("user_login") or "Unknown"
    game = stream.get("game_name") or "No category"
    viewers = viewer_count(stream.get("viewer_count"))
    return (
        f"│ {truncate(user, USER_WIDTH):<{USER_WIDTH}} "
        f"│ {truncate(game, GAME_WIDTH):<{GAME_WIDTH}} "
        f"│ {viewers:>7} │"
    )


def streams_tooltip(streams):
    count = len(streams)
    noun = "stream" if count == 1 else "streams"
    header = (
        f"│ {'Streamer':<{USER_WIDTH}} "
        f"│ {'Game':<{GAME_WIDTH}} "
        f"│ {'Viewers':>7} │"
    )
    inner_width = len(header) - 2
    title = f" Twitch Live - {count} {noun} "
    top = f"┌{title}{'─' * max(0, inner_width - len(title))}┐"
    divider = (
        f"├{'─' * (USER_WIDTH + 2)}"
        f"┼{'─' * (GAME_WIDTH + 2)}"
        f"┼{'─' * 9}┤"
    )
    bottom = f"└{'─' * (USER_WIDTH + 2)}┴{'─' * (GAME_WIDTH + 2)}┴{'─' * 9}┘"
    rows = [stream_row(stream) for stream in streams]
    return "\n".join([top, header, divider, *rows, bottom])


def sorted_streams():
    config = load_config()
    if not config["client_id"] or not config["access_token"]:
        raise RuntimeError(
            "Set TWITCH_CLIENT_ID and TWITCH_ACCESS_TOKEN, "
            f"or create {CONFIG_FILE}."
        )

    streams = live_streams(config)
    streams.sort(key=lambda item: item.get("viewer_count", 0), reverse=True)
    return streams


def hyprctl(*args, check=False):
    result = subprocess.run(
        ["hyprctl", *args],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return result.stdout


def hypr_clients():
    try:
        return json.loads(hyprctl("clients", "-j") or "[]")
    except Exception:
        return []


def addresses_for_class(class_name):
    return {
        client.get("address")
        for client in hypr_clients()
        if client.get("class", "").lower() == class_name.lower()
    }


def addresses_matching_class(fragment):
    fragment = fragment.lower()
    return {
        client.get("address")
        for client in hypr_clients()
        if fragment in client.get("class", "").lower()
    }


def wait_for_new_window(addresses_func, existing):
    for _ in range(200):
        current = {addr for addr in addresses_func() if addr}
        new_addresses = current - existing
        if new_addresses:
            return sorted(new_addresses)[0]
        time.sleep(0.1)
    return None


def client_for_address(address):
    for client in hypr_clients():
        if client.get("address") == address:
            return client
    return {}


def tile_window(address):
    if client_for_address(address).get("floating") is True:
        hyprctl("dispatch", "focuswindow", f"address:{address}")
        hyprctl("dispatch", "togglefloating")


def require_command(command):
    if shutil.which(command):
        return
    raise RuntimeError(f"Missing required command: {command}")


def launch_stream(channel):
    if not channel or not channel.replace("_", "").isalnum():
        raise RuntimeError("Channel names can only contain letters, numbers, and underscores")

    for command in ("hyprctl", "streamlink", "mpv", "chatterino"):
        require_command(command)

    title = f"twitch:{channel}"

    hyprctl("dispatch", "moveworkspacetomonitor", f"{TWITCH_WORKSPACE} {TWITCH_MONITOR}")
    hyprctl("dispatch", "focusmonitor", TWITCH_MONITOR)
    hyprctl("dispatch", "workspace", TWITCH_WORKSPACE)

    existing_mpv = addresses_for_class(TWITCH_MPV_CLASS)
    subprocess.Popen(
        [
            "streamlink",
            f"twitch.tv/{channel}",
            "best",
            "--player",
            "mpv",
            "--title",
            title,
            "--player-args",
            f"--wayland-app-id={TWITCH_MPV_CLASS} {{playertitleargs}} {{playerinput}}",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    mpv_addr = wait_for_new_window(lambda: addresses_for_class(TWITCH_MPV_CLASS), existing_mpv)
    if not mpv_addr:
        raise RuntimeError("Timed out waiting for mpv")

    existing_chat = addresses_matching_class("chatterino")
    subprocess.Popen(
        ["chatterino", "--channels", f"t:{channel}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    chat_addr = wait_for_new_window(lambda: addresses_matching_class("chatterino"), existing_chat)
    if not chat_addr:
        raise RuntimeError("Timed out waiting for Chatterino")

    hyprctl("dispatch", "movetoworkspacesilent", f"{TWITCH_WORKSPACE},address:{mpv_addr}")
    hyprctl("dispatch", "movetoworkspacesilent", f"{TWITCH_WORKSPACE},address:{chat_addr}")
    hyprctl("dispatch", "focusmonitor", TWITCH_MONITOR)
    hyprctl("dispatch", "workspace", TWITCH_WORKSPACE)
    tile_window(mpv_addr)
    tile_window(chat_addr)
    hyprctl("dispatch", "focuswindow", f"address:{mpv_addr}")
    hyprctl("dispatch", "focuswindow", f"address:{chat_addr}")
    hyprctl("dispatch", "layoutmsg", "splitratio", "1.6", "exact")

    chat_x = client_for_address(chat_addr).get("at", [0])[0]
    mpv_x = client_for_address(mpv_addr).get("at", [0])[0]
    if chat_x < mpv_x:
        hyprctl("dispatch", "layoutmsg", "swapsplit")


def table_lines(streams, selected=None):
    count = len(streams)
    noun = "stream" if count == 1 else "streams"
    header = (
        f"│ {'Streamer':<{USER_WIDTH}} "
        f"│ {'Game':<{GAME_WIDTH}} "
        f"│ {'Viewers':>7} │"
    )
    inner_width = len(header) - 2
    title = f" Twitch Live - {count} {noun} "
    top = f"┌{title}{'─' * max(0, inner_width - len(title))}┐"
    divider = (
        f"├{'─' * (USER_WIDTH + 2)}"
        f"┼{'─' * (GAME_WIDTH + 2)}"
        f"┼{'─' * 9}┤"
    )
    bottom = f"└{'─' * (USER_WIDTH + 2)}┴{'─' * (GAME_WIDTH + 2)}┴{'─' * 9}┘"
    rows = []
    for index, stream in enumerate(streams):
        row = stream_row(stream)
        if selected == index:
            row = "▶" + row[1:-1] + "◀"
        rows.append(row)
    return [top, header, divider, *rows, bottom]


def draw_menu(screen, streams, selected, status=""):
    screen.erase()
    curses.curs_set(0)
    lines = table_lines(streams, selected)
    height, width = screen.getmaxyx()
    start_y = max(0, (height - len(lines) - 2) // 2)
    start_x = max(0, (width - len(lines[0])) // 2)

    for row_index, line in enumerate(lines):
        attr = curses.A_NORMAL
        stream_row_start = 3
        stream_row_end = stream_row_start + len(streams)
        if stream_row_start <= row_index < stream_row_end:
            if row_index - stream_row_start == selected:
                attr = curses.A_REVERSE
        screen.addnstr(start_y + row_index, start_x, line, max(0, width - start_x - 1), attr)

    hint = "↑/↓ or Tab select  Enter open  q/Esc cancel"
    screen.addnstr(start_y + len(lines) + 1, start_x, hint, max(0, width - start_x - 1), curses.A_DIM)
    if status:
        screen.addnstr(start_y + len(lines) + 2, start_x, status, max(0, width - start_x - 1))
    screen.refresh()
    return {
        "start_x": start_x,
        "start_y": start_y,
        "width": len(lines[0]),
        "stream_row_start": 3,
    }


def clicked_stream_index(mouse_event, layout, stream_count):
    _, x, y, _, button_state = mouse_event
    if not button_state & curses.BUTTON1_CLICKED:
        return None

    row = y - layout["start_y"]
    col = x - layout["start_x"]
    stream_index = row - layout["stream_row_start"]
    if 0 <= stream_index < stream_count and 0 <= col < layout["width"]:
        return stream_index
    return None


def run_menu(screen, streams):
    if not streams:
        screen.addstr(0, 0, "Twitch: no streams live")
        screen.refresh()
        screen.getch()
        return

    selected = 0
    curses.mousemask(curses.BUTTON1_CLICKED)
    curses.mouseinterval(0)
    while True:
        layout = draw_menu(screen, streams, selected)
        key = screen.getch()
        if key in (ord("q"), 27):
            return
        if key in (curses.KEY_DOWN, ord("\t"), ord("j")):
            selected = (selected + 1) % len(streams)
        elif key in (curses.KEY_UP, curses.KEY_BTAB, ord("k")):
            selected = (selected - 1) % len(streams)
        elif key == curses.KEY_MOUSE:
            try:
                clicked = clicked_stream_index(curses.getmouse(), layout, len(streams))
            except curses.error:
                clicked = None
            if clicked is not None:
                selected = clicked
                channel = streams[selected].get("user_login") or streams[selected].get("user_name")
                draw_menu(screen, streams, selected, f"Opening {channel}...")
                launch_stream(channel)
                return
        elif key in (curses.KEY_ENTER, 10, 13):
            channel = streams[selected].get("user_login") or streams[selected].get("user_name")
            draw_menu(screen, streams, selected, f"Opening {channel}...")
            launch_stream(channel)
            return


def menu_main():
    try:
        streams = sorted_streams()
        curses.wrapper(run_menu, streams)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"Twitch API error {exc.code}\n{detail}")
        input("Press Enter to close.")
    except Exception as exc:
        print(f"Twitch: {exc}")
        input("Press Enter to close.")


def waybar_main():
    try:
        streams = sorted_streams()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        output(f"Twitch API error {exc.code}\n{detail}", "error")
        return
    except Exception as exc:
        output(f"Twitch\n{exc}", "error")
        return

    if not streams:
        output("Twitch\nNo streams live", "idle")
        return

    output(streams_tooltip(streams), "live")


def main():
    parser = argparse.ArgumentParser(description="Waybar Twitch status and launcher")
    parser.add_argument("--menu", action="store_true", help="show interactive stream picker")
    args = parser.parse_args()

    if args.menu:
        menu_main()
    else:
        waybar_main()


if __name__ == "__main__":
    main()
