#!/usr/bin/env python3
"""
Wordle TUI — looks like actual Wordle.
Colored tiles (green/yellow/dark), on-screen keyboard with letter states.
"""

import curses
import json
import subprocess
from pathlib import Path

STATE_FILE  = Path.home() / ".local" / "share" / "waybar-wordle" / "state.json"
WORDLE_SCRIPT = Path(__file__).parent / "wordle.py"

# Color pair IDs
P_ERROR   = 1
P_CORRECT = 2  # green bg
P_PRESENT = 3  # yellow bg
P_ABSENT  = 4  # dark bg  (letter was guessed, not in word)
P_FILLED  = 5  # white bg (typed, not yet submitted)
P_EMPTY   = 6  # default  (blank tile)
P_DIM     = 7  # dimmed text

TILE_W   = 5
TILE_H   = 3
TILE_GAP = 1  # gap between tiles

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


def load_state() -> dict | None:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            return None
    return None


def get_letter_states(state: dict) -> dict[str, str]:
    """Best known state for each letter that's been guessed."""
    priority = {"correct": 3, "present": 2, "absent": 1}
    result: dict[str, str] = {}
    for entry in state["guesses"]:
        for letter, tile in zip(entry["word"], entry["tiles"]):
            s = TILE_TO_STATE.get(tile, "absent")
            if priority.get(s, 0) > priority.get(result.get(letter, ""), 0):
                result[letter] = s
    return result


def draw_tile(
    stdscr, row: int, col: int, letter: str, tile_state: str
):
    """Draw a 3-tall × 5-wide bordered tile at (row, col)."""
    pair = STATE_TO_PAIR.get(tile_state, P_EMPTY)
    attr = curses.color_pair(pair)

    blank = "     "
    mid   = f"  {letter}  "

    try:
        stdscr.addstr(row,     col, blank, attr | curses.A_BOLD)
        stdscr.addstr(row + 1, col, mid,   attr | curses.A_BOLD)
        stdscr.addstr(row + 2, col, blank, attr | curses.A_BOLD)
    except curses.error:
        pass  # Don't crash if window is too small


def draw_keyboard(stdscr, start_row: int, cx: int, letter_states: dict):
    """
    Draw 3-row keyboard. Each key is 3 wide with 1 gap.
    Letters colored by their best known state.
    """
    for r, row_keys in enumerate(KB_ROWS):
        row_str_w = len(row_keys) * 3 + (len(row_keys) - 1)
        x = cx - row_str_w // 2
        for key in row_keys:
            state = letter_states.get(key)
            if state == "correct":
                attr = curses.color_pair(P_CORRECT) | curses.A_BOLD
            elif state == "present":
                attr = curses.color_pair(P_PRESENT) | curses.A_BOLD
            elif state == "absent":
                attr = curses.color_pair(P_ABSENT)
            else:
                attr = curses.A_NORMAL | curses.A_BOLD

            try:
                stdscr.addstr(start_row + r, x, f" {key} ", attr)
            except curses.error:
                pass
            x += 4


def draw_board(stdscr, state: dict, guess: str, message: str):
    stdscr.clear()
    h, w = stdscr.getmaxyx()
    cx = w // 2

    board_w = 5 * TILE_W + 4 * TILE_GAP
    board_col = cx - board_w // 2

    # ── Title ──────────────────────────────────────────────────────────────
    title = f"WORDLE  #{state.get('puzzle_id', '?')}   {state.get('date', '')}"
    try:
        stdscr.addstr(0, cx - len(title) // 2, title, curses.A_BOLD)
        stdscr.addstr(1, cx - 15, "─" * 30, curses.color_pair(P_DIM))
    except curses.error:
        pass

    board_start = 2

    # ── Submitted guess rows ───────────────────────────────────────────────
    for g_idx, entry in enumerate(state["guesses"]):
        row = board_start + g_idx * (TILE_H + 1)
        for t_idx, (letter, tile) in enumerate(
            zip(entry["word"], entry["tiles"])
        ):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, row, col, letter, TILE_TO_STATE.get(tile, "absent"))

    # ── Active guess row ───────────────────────────────────────────────────
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
    empty_start = len(state["guesses"]) + (1 if state["status"] == "playing" else 0)
    for e_idx in range(empty_start, 6):
        row = board_start + e_idx * (TILE_H + 1)
        for t_idx in range(5):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, row, col, " ", "empty")

    # ── Keyboard ───────────────────────────────────────────────────────────
    kb_row = board_start + 6 * (TILE_H + 1) + 1
    try:
        stdscr.addstr(kb_row - 1, cx - 15, "─" * 30, curses.color_pair(P_DIM))
    except curses.error:
        pass
    draw_keyboard(stdscr, kb_row, cx, get_letter_states(state))

    # ── Status line ────────────────────────────────────────────────────────
    status_row = kb_row + 5
    if state["status"] == "won":
        msgs = [
            "GENIUS!", "Magnificent!", "Impressive!",
            "Splendid!", "Great!", "Phew!",
        ]
        status = msgs[min(len(state["guesses"]) - 1, 5)]
        line = f"{status}  Press any key to close."
        try:
            stdscr.addstr(
                status_row, cx - len(line) // 2, line,
                curses.A_BOLD | curses.color_pair(P_CORRECT),
            )
        except curses.error:
            pass
    elif state["status"] == "lost":
        line = f"The word was {state['word']}   Press any key to close."
        try:
            stdscr.addstr(
                status_row, cx - len(line) // 2, line,
                curses.A_BOLD | curses.color_pair(P_ABSENT),
            )
        except curses.error:
            pass
    else:
        hint = "Type  •  ENTER to submit  •  ESC to quit"
        try:
            stdscr.addstr(
                status_row, cx - len(hint) // 2, hint,
                curses.color_pair(P_DIM),
            )
        except curses.error:
            pass

    if message:
        try:
            stdscr.addstr(
                status_row + 1, cx - len(message) // 2, message,
                curses.A_BOLD | curses.color_pair(P_ERROR),
            )
        except curses.error:
            pass

    stdscr.refresh()


def setup_colors():
    curses.start_color()
    curses.use_default_colors()

    # Try to use 256-color gray for absent tiles, fall back to black
    try:
        curses.init_color(10, 300, 300, 300)   # custom dark gray
        absent_bg = 10
    except Exception:
        absent_bg = curses.COLOR_BLACK

    curses.init_pair(P_ERROR,   curses.COLOR_RED,    -1)
    curses.init_pair(P_CORRECT, curses.COLOR_BLACK,  curses.COLOR_GREEN)
    curses.init_pair(P_PRESENT, curses.COLOR_BLACK,  curses.COLOR_YELLOW)
    curses.init_pair(P_ABSENT,  curses.COLOR_WHITE,  absent_bg)
    curses.init_pair(P_FILLED,  curses.COLOR_BLACK,  curses.COLOR_WHITE)
    curses.init_pair(P_EMPTY,   curses.COLOR_WHITE,  -1)
    curses.init_pair(P_DIM,     curses.COLOR_WHITE,  -1)


def main(stdscr):
    curses.curs_set(0)
    setup_colors()

    state = load_state()
    if not state:
        stdscr.addstr(0, 0, "No state found. Hover the widget first, then click.")
        stdscr.getch()
        return

    # If game is already over, just show the board
    if state["status"] != "playing":
        draw_board(stdscr, state, "", "")
        stdscr.getch()
        return

    guess   = ""
    message = ""

    while True:
        draw_board(stdscr, state, guess, message)
        message = ""
        key = stdscr.getch()

        if key == 27:  # ESC
            return

        elif key in (curses.KEY_BACKSPACE, 127, 8):
            guess = guess[:-1]

        elif key in (10, curses.KEY_ENTER):
            if len(guess) != 5:
                message = "Must be exactly 5 letters!"
                continue

            draw_board(stdscr, state, guess, "Checking...")
            subprocess.run(
                ["python3", str(WORDLE_SCRIPT), "--guess", guess],
                capture_output=True,
                text=True,
            )
            subprocess.run(["pkill", "-SIGRTMIN+8", "waybar"])

            # Reload fresh state
            state = load_state()
            guess = ""

            if state["status"] != "playing":
                draw_board(stdscr, state, "", "")
                stdscr.getch()
                return

        elif 0 < key < 256 and chr(key).isalpha():
            if len(guess) < 5:
                guess += chr(key).upper()


curses.wrapper(main)