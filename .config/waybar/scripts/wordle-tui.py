#!/usr/bin/env python3
"""
Wordle TUI — replicates the Wordle UI in the terminal.
Forced orange (correct) and blue (present) regardless of terminal theme.
Streak + stats screen shown after game over, TAB toggles between views.
"""

import curses
import json
import subprocess
import time
from pathlib import Path

STATE_FILE    = Path.home() / ".local" / "share" / "waybar-wordle" / "state.json"
STATS_FILE    = Path.home() / ".local" / "share" / "waybar-wordle" / "stats.json"
WORDLE_SCRIPT = Path(__file__).parent / "wordle.py"

import sys
sys.path.append(str(Path(__file__).parent))
import wordle

# ── Color pair IDs ────────────────────────────────────────────────────────────
P_ERROR   = 1
P_CORRECT = 2  # orange bg
P_PRESENT = 3  # blue bg
P_ABSENT  = 4  # dark gray bg
P_FILLED  = 5  # white bg (active input)
P_EMPTY   = 6  # default (blank tile)
P_DIM     = 7
P_TITLE   = 8
P_STAT    = 9  # highlighted bar in distribution

# Custom color slots
C_ORANGE    = 16
C_BLUE      = 17
C_DARK_GRAY = 18
C_OFF_WHITE = 19

TILE_W   = 5
TILE_H   = 3
TILE_GAP = 1

TILE_TO_STATE = {"🟧": "correct", "🟦": "present", "⬛": "absent"}
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

MIN_H = 38
MIN_W = 52

WIN_MSGS = [
    "GENIUS!",
    "Magnificent!",
    "Impressive!",
    "Splendid!",
    "Great!",
    "Phew!",
]


# ── State / stats ─────────────────────────────────────────────────────────────

def load_state(retries: int = 5, delay: float = 0.1) -> dict | None:
    for _ in range(retries):
        if STATE_FILE.exists():
            try:
                text = STATE_FILE.read_text().strip()
                if text:
                    state = json.loads(text)
                    if state.get("guesses") and isinstance(state["guesses"][0], dict):
                        state["guesses"] = [g["word"] for g in state["guesses"]]
                    return state
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(delay)
    return None


def load_stats() -> dict:
    if STATS_FILE.exists():
        try:
            return json.loads(STATS_FILE.read_text())
        except Exception:
            pass
    return {
        "games_played": 0,
        "games_won": 0,
        "current_streak": 0,
        "max_streak": 0,
        "last_completed_date": None,
        "last_win_date": None,
        "guess_distribution": {str(i): 0 for i in range(1, 7)},
    }


def get_letter_states(state: dict) -> dict[str, str]:
    priority = {"correct": 3, "present": 2, "absent": 1}
    result: dict[str, str] = {}
    answer = state.get("word", "")
    for guess in state["guesses"]:
        tiles = wordle.score_guess(guess, answer)
        for letter, tile in zip(guess, tiles):
            s = TILE_TO_STATE.get(tile, "absent")
            if priority.get(s, 0) > priority.get(result.get(letter, ""), 0):
                result[letter] = s
    return result


# ── Color setup ───────────────────────────────────────────────────────────────

def setup_colors():
    curses.start_color()
    curses.use_default_colors()

    if curses.can_change_color():
        # curses RGB is 0-1000 scale
        # Orange  ~#E07000 → (878, 435, 0)
        # Blue    ~#3A78F2 → (227, 471, 949)
        # Dark gray ~#3A3A3C → (227, 227, 235)
        # Off-white ~#FFFFFF → (1000, 1000, 1000)
        curses.init_color(C_ORANGE,    878, 435,    0)
        curses.init_color(C_BLUE,      227, 471,  949)
        curses.init_color(C_DARK_GRAY, 227, 227,  235)
        curses.init_color(C_OFF_WHITE, 1000, 1000, 1000)

        curses.init_pair(P_CORRECT, C_OFF_WHITE, C_ORANGE)
        curses.init_pair(P_PRESENT, C_OFF_WHITE, C_BLUE)
        curses.init_pair(P_ABSENT,  C_OFF_WHITE, C_DARK_GRAY)
        curses.init_pair(P_FILLED,  curses.COLOR_BLACK, C_OFF_WHITE)
        curses.init_pair(P_STAT,    C_OFF_WHITE, C_ORANGE)
    else:
        # Fallback for terminals that don't support custom colors
        curses.init_pair(P_CORRECT, curses.COLOR_BLACK,  curses.COLOR_YELLOW)
        curses.init_pair(P_PRESENT, curses.COLOR_BLACK,  curses.COLOR_CYAN)
        curses.init_pair(P_ABSENT,  curses.COLOR_WHITE,  curses.COLOR_BLACK)
        curses.init_pair(P_FILLED,  curses.COLOR_BLACK,  curses.COLOR_WHITE)
        curses.init_pair(P_STAT,    curses.COLOR_BLACK,  curses.COLOR_YELLOW)

    curses.init_pair(P_ERROR, curses.COLOR_RED,   -1)
    curses.init_pair(P_EMPTY, curses.COLOR_WHITE, -1)
    curses.init_pair(P_DIM,   curses.COLOR_WHITE, -1)
    curses.init_pair(P_TITLE, curses.COLOR_WHITE, -1)


# ── Drawing helpers ───────────────────────────────────────────────────────────

def safe_addstr(stdscr, row: int, col: int, text: str, attr=curses.A_NORMAL):
    h, w = stdscr.getmaxyx()
    if row < 0 or row >= h or col < 0:
        return
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
            ls = letter_states.get(key)
            if ls == "correct":
                attr = curses.color_pair(P_CORRECT) | curses.A_BOLD
            elif ls == "present":
                attr = curses.color_pair(P_PRESENT) | curses.A_BOLD
            elif ls == "absent":
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
    safe_addstr(stdscr, h // 2,
                max(0, w // 2 - len(msg) // 2), msg, curses.A_BOLD)
    safe_addstr(stdscr, h // 2 + 1,
                max(0, w // 2 - len(sub) // 2), sub)
    stdscr.refresh()


# ── Board ─────────────────────────────────────────────────────────────────────

def draw_board(stdscr, state: dict, guess: str, message: str):
    stdscr.clear()
    h, w = stdscr.getmaxyx()

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
    for g_idx, guess in enumerate(state["guesses"]):
        row = board_start + g_idx * (TILE_H + 1)
        tiles = wordle.score_guess(guess, state.get("word", ""))
        for t_idx, (letter, tile) in enumerate(
            zip(guess, tiles)
        ):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, row, col, letter,
                      TILE_TO_STATE.get(tile, "absent"))

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
        row = board_start + e_idx * (TILE_H + 1)
        for t_idx in range(5):
            col = board_col + t_idx * (TILE_W + TILE_GAP)
            draw_tile(stdscr, row, col, " ", "empty")

    # ── Keyboard ───────────────────────────────────────────────────────────
    kb_row = board_start + 6 * (TILE_H + 1) + 1
    safe_addstr(stdscr, kb_row - 1, cx - 15, "─" * 30,
                curses.color_pair(P_DIM))
    draw_keyboard(stdscr, kb_row, cx, get_letter_states(state))

    # ── Status / hint ──────────────────────────────────────────────────────
    status_row = kb_row + 5
    if state["status"] == "playing":
        hint = "Type  •  ENTER to submit  •  ESC to quit"
        safe_addstr(stdscr, status_row, cx - len(hint) // 2, hint,
                    curses.color_pair(P_DIM))
    else:
        hint = "TAB toggle stats  •  any other key to close"
        safe_addstr(stdscr, status_row, cx - len(hint) // 2, hint,
                    curses.color_pair(P_DIM))

    if message:
        safe_addstr(stdscr, status_row + 2, cx - len(message) // 2, message,
                    curses.A_BOLD | curses.color_pair(P_ERROR))

    stdscr.refresh()


# ── Stats screen ──────────────────────────────────────────────────────────────

def draw_stats_screen(stdscr, state: dict):
    """
    Renders stats. Does NOT call getch() — end_game_loop owns all input.
    """
    stats = load_stats()
    stdscr.clear()
    h, w = stdscr.getmaxyx()
    cx = w // 2

    row = 1

    # ── Header ─────────────────────────────────────────────────────────────
    title = "STATISTICS"
    safe_addstr(stdscr, row, cx - len(title) // 2, title,
                curses.A_BOLD | curses.color_pair(P_TITLE))
    row += 2

    # ── Four stat boxes ────────────────────────────────────────────────────
    win_pct = (
        round((stats["games_won"] / stats["games_played"]) * 100)
        if stats["games_played"] > 0 else 0
    )

    stat_items = [
        (str(stats["games_played"]),   "Played"),
        (f"{win_pct}%",                "Win %"),
        (str(stats["current_streak"]), "Current\nStreak"),
        (str(stats["max_streak"]),     "Max\nStreak"),
    ]

    box_w     = 10
    box_gap   = 4
    total_w   = len(stat_items) * box_w + (len(stat_items) - 1) * box_gap
    box_start = cx - total_w // 2

    for i, (val, label) in enumerate(stat_items):
        bx = box_start + i * (box_w + box_gap)
        safe_addstr(stdscr, row,
                    bx + box_w // 2 - len(val) // 2, val,
                    curses.A_BOLD | curses.color_pair(P_TITLE))
        for li, lline in enumerate(label.split("\n")):
            safe_addstr(stdscr, row + 1 + li,
                        bx + box_w // 2 - len(lline) // 2,
                        lline, curses.color_pair(P_DIM))

    row += 4

    # ── Divider ────────────────────────────────────────────────────────────
    safe_addstr(stdscr, row, cx - 20, "─" * 40, curses.color_pair(P_DIM))
    row += 2

    # ── Guess distribution ─────────────────────────────────────────────────
    dist_title = "GUESS DISTRIBUTION"
    safe_addstr(stdscr, row, cx - len(dist_title) // 2, dist_title,
                curses.A_BOLD | curses.color_pair(P_TITLE))
    row += 2

    dist  = stats["guess_distribution"]
    max_v = max(max(int(v) for v in dist.values()), 1)

    bar_max_w     = min(28, w - 12)
    winning_guess = (
        str(len(state["guesses"])) if state["status"] == "won" else None
    )

    for i in range(1, 7):
        count    = int(dist.get(str(i), 0))
        bar_w    = max(1, round((count / max_v) * bar_max_w))
        bar      = " " * bar_w
        bar_attr = (
            curses.color_pair(P_STAT) | curses.A_BOLD
            if str(i) == winning_guess
            else curses.color_pair(P_ABSENT)
        )

        safe_addstr(stdscr, row, cx - bar_max_w // 2 - 4,
                    f"{i} ", curses.A_BOLD)
        try:
            stdscr.addstr(row, cx - bar_max_w // 2 - 2, bar, bar_attr)
            stdscr.addstr(
                row, cx - bar_max_w // 2 - 2 + bar_w,
                f" {count}", curses.A_BOLD,
            )
        except curses.error:
            pass
        row += 2

    # ── Divider ────────────────────────────────────────────────────────────
    safe_addstr(stdscr, row, cx - 20, "─" * 40, curses.color_pair(P_DIM))
    row += 2

    # ── Result message ─────────────────────────────────────────────────────
    if state["status"] == "won":
        msg  = WIN_MSGS[min(len(state["guesses"]) - 1, 5)]
        attr = curses.color_pair(P_CORRECT) | curses.A_BOLD
    else:
        msg  = f"The word was: {state.get('word', '?')}"
        attr = curses.color_pair(P_ABSENT) | curses.A_BOLD

    safe_addstr(stdscr, row, cx - len(msg) // 2, msg, attr)
    row += 2

    hint = "TAB toggle board  •  any other key to close"
    safe_addstr(stdscr, row, cx - len(hint) // 2, hint,
                curses.color_pair(P_DIM))

    # intentionally no getch() here — end_game_loop owns all input
    stdscr.refresh()


# ── End game loop ─────────────────────────────────────────────────────────────

def end_game_loop(stdscr, state: dict):
    """
    After game over: starts on stats screen, TAB toggles to board and back.
    Any non-TAB non-resize key exits.
    """
    show_stats = True
    time.sleep(0.6)
    curses.flushinp()  # Discard buffered keys (e.g. ENTER from final guess)

    while True:
        if show_stats:
            draw_stats_screen(stdscr, state)
        else:
            draw_board(stdscr, state, "", "")

        key = stdscr.getch()

        if key == curses.KEY_RESIZE:
            curses.update_lines_cols()
            continue
        elif key in (9, ord("\t")):  # TAB
            show_stats = not show_stats
        else:
            return


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

    # Game already over — go straight to end game loop
    if state["status"] != "playing":
        end_game_loop(stdscr, state)
        return

    guess   = ""
    message = ""

    while True:
        draw_board(stdscr, state, guess, message)
        message = ""

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

            try:
                resp = json.loads(result.stdout)
                if resp.get("class") == "error":
                    message = resp.get("text", "Unknown error").lstrip("❌ ")
                    guess = ""
                    continue
            except (json.JSONDecodeError, AttributeError):
                pass

            subprocess.run(["pkill", "-SIGRTMIN+8", "waybar"])

            new_state = load_state()
            if new_state is None:
                message = "Failed to reload state, try again."
                continue

            state = new_state
            guess = ""

            if state["status"] != "playing":
                end_game_loop(stdscr, state)
                return

        elif 0 < key < 256 and chr(key).isalpha():
            if len(guess) < 5:
                guess += chr(key).upper()


curses.wrapper(main)