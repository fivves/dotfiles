#!/usr/bin/env python3
"""
Waybar Wordle Module
- Fetches today's word from NYT's public endpoint
- Manages game state in ~/.local/share/waybar-wordle/state.json
- Manages stats in ~/.local/share/waybar-wordle/stats.json
- Outputs JSON for waybar (text + tooltip)
- Accepts a guess via CLI arg: wordle.py --guess CRANE
"""

import json
import sys
import os
import tempfile
import requests
from datetime import date, timedelta
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
STATE_DIR      = Path.home() / ".local" / "share" / "waybar-wordle"
STATE_FILE     = STATE_DIR / "state.json"
STATS_FILE     = STATE_DIR / "stats.json"
WORD_LIST_FILE = STATE_DIR / "wordlist.txt"
NYT_API        = "https://www.nytimes.com/svc/wordle/v2/{date}.json"
WORD_LIST_URL  = (
    "https://raw.githubusercontent.com/tabatkins/wordle-list/main/words"
)
MAX_GUESSES = 6

CORRECT = "🟧"
PRESENT = "🟦"
ABSENT  = "⬛"

# ── Helpers ───────────────────────────────────────────────────────────────────

def fetch_word(today: str) -> dict:
    try:
        resp = requests.get(NYT_API.format(date=today), timeout=5)
        resp.raise_for_status()
        data = resp.json()
        return {
            "word": data["solution"].upper(),
            "puzzle_id": data.get("id", data.get("days_since_launch", "?")),
        }
    except Exception as e:
        return {"word": None, "puzzle_id": None, "error": str(e)}


def atomic_write(path: Path, data: dict):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        path.write_text(json.dumps(data, indent=2))


def load_word_list() -> set[str]:
    """
    Load valid Wordle words from cache, downloading on first run.
    Fails open (returns empty set) so a network hiccup doesn't brick the game.
    """
    if WORD_LIST_FILE.exists():
        try:
            return set(WORD_LIST_FILE.read_text().upper().split())
        except Exception:
            pass
    try:
        resp = requests.get(WORD_LIST_URL, timeout=10)
        resp.raise_for_status()
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        WORD_LIST_FILE.write_text(resp.text.lower())
        return set(resp.text.upper().split())
    except Exception:
        return set()


def is_valid_word(word: str) -> bool:
    """
    Returns True if word is in the Wordle word list.
    Falls back to True if the list couldn't be loaded.
    """
    words = load_word_list()
    return not words or word.upper() in words


# ── Stats ─────────────────────────────────────────────────────────────────────

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


def update_stats(state: dict):
    """
    Update stats for a completed game. Guards against double-counting
    via stats_recorded flag on state.
    """
    if state.get("stats_recorded"):
        return
    if state["status"] not in ("won", "lost"):
        return

    stats = load_stats()
    today = state["date"]

    stats["games_played"] += 1

    if state["status"] == "won":
        stats["games_won"] += 1
        guess_count = str(len(state["guesses"]))
        stats["guess_distribution"][guess_count] = (
            stats["guess_distribution"].get(guess_count, 0) + 1
        )

        last_win  = stats.get("last_win_date")
        yesterday = str(date.fromisoformat(today) - timedelta(days=1))
        if last_win in (today, yesterday):
            stats["current_streak"] += 1
        else:
            stats["current_streak"] = 1

        stats["max_streak"] = max(stats["max_streak"], stats["current_streak"])
        stats["last_win_date"] = today
    else:
        stats["current_streak"] = 0

    stats["last_completed_date"] = today
    atomic_write(STATS_FILE, stats)
    state["stats_recorded"] = True


# ── State ─────────────────────────────────────────────────────────────────────

def load_state() -> dict:
    today = str(date.today())
    if STATE_FILE.exists():
        try:
            state = json.loads(STATE_FILE.read_text())
            if state.get("date") != today or state.get("fetch_error") or not state.get("word"):
                return new_state(today)

            # Migrate old state format to new format
            if state.get("guesses") and isinstance(state["guesses"][0], dict):
                state["guesses"] = [g["word"] for g in state["guesses"]]
                save_state(state)

            return state
        except Exception:
            pass
    return new_state(today)


def new_state(today: str) -> dict:
    result = fetch_word(today)
    return {
        "date": today,
        "word": result["word"],
        "puzzle_id": result.get("puzzle_id"),
        "guesses": [],
        "status": "playing",
        "stats_recorded": False,
        "fetch_error": result.get("error"),
    }


def save_state(state: dict):
    atomic_write(STATE_FILE, state)


# ── Game logic ────────────────────────────────────────────────────────────────

def score_guess(guess: str, answer: str) -> list[str]:
    result       = [ABSENT] * 5
    answer_chars = list(answer)
    guess_chars  = list(guess)

    for i in range(5):
        if guess_chars[i] == answer_chars[i]:
            result[i]       = CORRECT
            answer_chars[i] = None
            guess_chars[i]  = None

    for i in range(5):
        if guess_chars[i] is None:
            continue
        if guess_chars[i] in answer_chars:
            result[i] = PRESENT
            answer_chars[answer_chars.index(guess_chars[i])] = None

    return result


def do_guess(state: dict, guess: str) -> str:
    guess = guess.strip().upper()

    if state["status"] != "playing":
        return "Game is already over!"
    if len(guess) != 5:
        return "Guess must be exactly 5 letters."
    if not guess.isalpha():
        return "Letters only."
    if not is_valid_word(guess):
        return "Not in word list!"
    if state["word"] is None:
        return "Couldn't fetch today's word. Check your connection."

    state["guesses"].append(guess)

    if guess == state["word"]:
        state["status"] = "won"
    elif len(state["guesses"]) >= MAX_GUESSES:
        state["status"] = "lost"

    if state["status"] in ("won", "lost"):
        update_stats(state)

    return ""


# ── Waybar output ─────────────────────────────────────────────────────────────

def render_board(state: dict) -> str:
    lines = []
    lines.append(f"Wordle #{state.get('puzzle_id', '?')}  —  {state['date']}")
    lines.append("")

    for guess in state["guesses"]:
        tiles = "".join(score_guess(guess, state["word"]))
        lines.append(f"{tiles}  {guess}")

    for _ in range(MAX_GUESSES - len(state["guesses"])):
        lines.append("⬜⬜⬜⬜⬜")

    lines.append("")

    stats = load_stats()
    if state["status"] == "won":
        lines.append(f"🎉 Solved in {len(state['guesses'])}/{MAX_GUESSES}!")
    elif state["status"] == "lost":
        lines.append(f"💀 Answer was: {state['word']}")
    else:
        lines.append(f"{MAX_GUESSES - len(state['guesses'])} guess(es) remaining")
        lines.append("Click to guess!")

    lines.append("")
    lines.append(
        f"🔥 Streak: {stats['current_streak']}  "
        f"⭐ Best: {stats['max_streak']}  "
        f"🎮 Played: {stats['games_played']}"
    )

    return "\n".join(lines)


def status_icon(state: dict) -> str:
    if state["status"] == "won":
        return "󰸞"
    elif state["status"] == "lost":
        return ""
    elif state.get("fetch_error"):
        return ""
    else:
        return f"󰋁  {len(state['guesses'])}/{MAX_GUESSES}"


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    state = load_state()

    if len(sys.argv) >= 3 and sys.argv[1] == "--guess":
        err = do_guess(state, sys.argv[2])
        save_state(state)
        print(json.dumps({
            "text": f"❌ {err}" if err else status_icon(state),
            "tooltip": render_board(state),
            "class": "error" if err else state["status"],
        }))
        return

    save_state(state)
    print(json.dumps({
        "text": status_icon(state),
        "tooltip": render_board(state),
        "class": state["status"],
    }))


if __name__ == "__main__":
    main()