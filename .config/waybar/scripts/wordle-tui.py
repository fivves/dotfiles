#!/usr/bin/env python3
"""
Wordle TUI — replicates the Wordle UI in the terminal.
Colored tiles, on-screen keyboard with letter states.
"""

import curses
import json
import subprocess
import time
from pathlib import Path

STATE_FILE    = Path.home() / ".local" / "share" / "waybar-wordle" / "state.json"
WORDLE_SCRIPT = Path(__file__).parent / "wordle.py"

# Color pair IDs
P_ERROR   = 1
P_CORRECT = 2
P_PRESENT = 3
P_ABSENT  = 4
P_FILLED  = 5
P_EMPTY   = 6
P_DIM     = 7
P_TITLE   = 8

TILE_W   = 5
TILE_H   = 3
TILE_GAP = 1

TILE_TO_STATE = {"🟩": "correct", "🟨": "present", "⬛": "absent"}
STATE_TO_PAIR = {
    "correct": P_CORRECT,
    "present": P_PRESENT,
    "absent":  P_ABSENT,
    "filled":  P_FILLED,
    "empty":   P_EMPTY,
}

KB_ROWS = [
    list("QWERTYUIOP"),
    list("ASDFGHJKL"),
    list("ZXCVBNM"),
]

MIN_H = 36
MIN_W = 50

WIN_MSGS = [
    "GENIUS!",
    "Magnificent!",
    "Impressive!",
    "Splendid!",
    "Great!",
    "Phew!",
]


# ── State ─────────────────────────────────────────────────────────────────────

def load_state(retries: int = 5, delay: float = 0.1) -> dict | None:
    """Load state with retries to handle atomic write race conditions."""
    for _ in range(retries):
        if STATE_FILE.exists():
            try:
                text = STATE_FILE.read_text()
                if text.strip():
                    return json.loads(text)
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(delay)
    return None


def get_letter_states(state: dict) -> dict[str, str]:
    priority = {"correct": 3, "present": 2, "absent": 1}
    result: dict[str, str] = {}
    for entry in state["guesses"]:
        for letter, tile in zip(entry["word"], entry["tiles"]):
            s = TILE_TO_STATE.get(tile, "absent")
            if priority.get(s, 0) > priority.get(result.get(letter, ""), 0):
                result[letter] = s
    return result


# ── Drawing ───────────────────────────────────────────────────────────────────

def safe_addstr(stdscr, row: int, col: int, text: str, attr=curses.A_NORMAL):
    h, w = stdscr.getmaxyx()
    if row < 0 or row >= h or col < 0:
        return
    # Clip text to window width
    available = w - col
    if available <= 0:
        return
    try:
        stdscr.addstr(row, col, text[:available], attr)
    except curses.error:
        pass


def draw_tile(stdscr, row: int, col: int, letter: str, tile_state: str):
    pair  = STATE_TO_PAIR.get(tile_state, P_EMPTY)
    attr  = curses.color_pair(pair) | curses.A_BOLD
    blank = "     "
    mid   = f"  {letter}  "
    safe_addstr(stdscr, row,     col, blank, attr)
    safe_addstr(stdscr, row + 1, col, mid,   attr)
    safe_addstr(stdscr, row + 2, col, blank, attr)


def draw_keyboard(stdscr, start_row: int, cx: int, letter_states: dict):
    for r, row_keys in enumerate(KB_ROWS):
        row_w = len(row_keys) * 3 + (len(row_keys) - 1)
        x = cx - row_w // 2
        for key in row_keys:
            state = letter_states.get(key)
            if state == "correct":
                attr = curses.color_pair(P_CORRECT) | curses.A_BOLD
            elif state == "present":
                attr = curses.color_pair(P_PRESENT) | curses.A_BOLD
            elif state == "absent":
                attr = curses.color_pair(P_ABSENT)
            else:
                attr = curses.A_BOLD
            safe_addstr(stdscr, start_row + r, x, f" {key} ", attr)
            x += 4


def draw_size_error(stdscr):
    stdscr.clear()
    h, w = stdscr.getmaxyx()
    msg = f"Terminal too small! Need {MIN_W}x{MIN_H}, got {w}x{h}"
    sub = "Resize the window to continue."
    safe_addstr(stdscr, h // 2,     max(0, w // 2 - len(msg) // 2), msg, curses.A_BOLD)
    safe_addstr(stdscr, h // 2 + 1, max(0, w // 2 - len(sub) // 2), sub)
    stdscr.refresh()


def draw_board(stdscr, state: dict, guess: str, message: str):
    stdscr.clear()
    h, w = stdscr.getmaxyx()

    # Size guard
    if h < MIN_H or w < MIN_W:
        draw_size_error(stdscr)
        return

    cx = w // 2

    board_w   = 5 * TILE_W + 4 * TILE_GAP
    board_col = cx - board_w // 2

    # ── Title ──────────────────────────────────────────────────────────────
    title = f"WORDLE  #{state.get('puzzle_id', '?')}   {state.get('date', '')}"
    safe_addstr(stdscr, 0, cx - len(title) // 2, title,
                curses.color_pair(P_TITLE) | curses.A_BOLD)
    safe_addstr(stdscr, 1, cx - 15, "─" * 30, curses.color_pair(P_DIM))

    board_start = 2

    # ── Submitted rows ─────────────────────────────────────────────────────
    for g_idx, entry in enumerate(state["guesses"]):
        row = board_start + g_idx * (TILE_H + 1)
        for t_idx, (letter, tile) in enumerate(
            zip(entry["word"], entry["tiles"])
        ):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, row, col, letter, TILE_TO_STATE.get(tile, "absent"))

    # ── Active input row ───────────────────────────────────────────────────
    if state["status"] == "playing":
        active_idx = len(state["guesses"])
        row = board_start + active_idx * (TILE_H + 1)
        for t_idx in range(5):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            if t_idx < len(guess):
                draw_tile(stdscr, row, col, guess[t_idx], "filled")
            else:
                draw_tile(stdscr, row, col, " ", "empty")

    # ── Remaining empty rows ───────────────────────────────────────────────
    empty_start = len(state["guesses"]) + (
        1 if state["status"] == "playing" else 0
    )
    for e_idx in range(empty_start, 6):
        row = board_col + e_idx * (TILE_H + 1)
        for t_idx in range(5):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, board_start + e_idx * (TILE_H + 1), col, " ", "empty")

    # ── Keyboard ───────────────────────────────────────────────────────────
    kb_row = board_start + 6 * (TILE_H + 1) + 1
    safe_addstr(stdscr, kb_row - 1, cx - 15, "─" * 30, curses.color_pair(P_DIM))
    draw_keyboard(stdscr, kb_row, cx, get_letter_states(state))

    # ── Status / message ───────────────────────────────────────────────────
    status_row = kb_row + 5

    if state["status"] == "won":
        txt = WIN_MSGS[min(len(state["guesses"]) - 1, 5)]
        hint = f"{txt}  —  Press any key to close."
        safe_addstr(stdscr, status_row, cx - len(hint) // 2, hint,
                    curses.A_BOLD | curses.color_pair(P_CORRECT))
    elif state["status"] == "lost":
        hint = f"The word was {state.get('word', '?')}   Press any key to close."
        safe_addstr(stdscr, status_row, cx - len(hint) // 2, hint,
                    curses.A_BOLD | curses.color_pair(P_ABSENT))
    else:
        hint = "Type  •  ENTER to submit  •  ESC to quit"
        safe_addstr(stdscr, status_row, cx - len(hint) // 2, hint,
                    curses.color_pair(P_DIM))

    if message:
        safe_addstr(stdscr, status_row + 2, cx - len(message) // 2, message,
                    curses.A_BOLD | curses.color_pair(P_ERROR))

    stdscr.refresh()


# ── Colors ────────────────────────────────────────────────────────────────────

def setup_colors():
    curses.start_color()
    curses.use_default_colors()

    try:
        curses.init_color(10, 300, 300, 300)
        absent_bg = 10
    except Exception:
        absent_bg = curses.COLOR_BLACK

    curses.init_pair(P_ERROR,   curses.COLOR_RED,     -1)
    curses.init_pair(P_CORRECT, curses.COLOR_BLACK,   curses.COLOR_GREEN)
    curses.init_pair(P_PRESENT, curses.COLOR_BLACK,   curses.COLOR_YELLOW)
    curses.init_pair(P_ABSENT,  curses.COLOR_WHITE,   absent_bg)
    curses.init_pair(P_FILLED,  curses.COLOR_BLACK,   curses.COLOR_WHITE)
    curses.init_pair(P_EMPTY,   curses.COLOR_WHITE,   -1)
    curses.init_pair(P_DIM,     curses.COLOR_WHITE,   -1)
    curses.init_pair(P_TITLE,   curses.COLOR_WHITE,   -1)


# ── Main ──────────────────────────────────────────────────────────────────────

def main(stdscr):
    curses.curs_set(0)
    setup_colors()
    stdscr.keypad(True)

    state = load_state()

    if state is None:
        safe_addstr(stdscr, 0, 0,
                    "Could not load game state. Try hovering the widget first.",
                    curses.A_BOLD)
        safe_addstr(stdscr, 1, 0, "Press any key to exit.")
        stdscr.refresh()
        stdscr.getch()
        return

    # Game already over — show board and exit on keypress
    if state["status"] != "playing":
        draw_board(stdscr, state, "", "")
        stdscr.getch()
        return

    guess   = ""
    message = ""

    while True:
        draw_board(stdscr, state, guess, message)
        message = ""

        # Handle terminal resize
        key = stdscr.getch()
        if key == curses.KEY_RESIZE:
            curses.update_lines_cols()
            continue

        if key == 27:  # ESC
            return

        elif key in (curses.KEY_BACKSPACE, 127, 8):
            guess = guess[:-1]

        elif key in (10, curses.KEY_ENTER):
            if len(guess) != 5:
                message = "Must be exactly 5 letters!"
                continue

            draw_board(stdscr, state, guess, "Checking...")
            stdscr.refresh()

            result = subprocess.run(
                ["python3", str(WORDLE_SCRIPT), "--guess", guess],
                capture_output=True,
                text=True,
            )

            # Check for error response from wordle.py
            try:
                resp = json.loads(result.stdout)
                if resp.get("class") == "error":
                    message = resp.get("text", "Unknown error").lstrip("❌ ")
                    guess = ""
                    continue
            except (json.JSONDecodeError, AttributeError):
                pass

            subprocess.run(["pkill", "-SIGRTMIN+8", "waybar"])

            # Reload state — retries handle any write timing issues
            new_state = load_state()
            if new_state is None:
                message = "Failed to reload state, try again."
                continue

            state = new_state
            guess = ""

            if state["status"] != "playing":
                draw_board(stdscr, state, "", "")
                stdscr.getch()
                return

        elif 0 < key < 256 and chr(key).isalpha():
            if len(guess) < 5:
                guess += chr(key).upper()


curses.wrapper(main)