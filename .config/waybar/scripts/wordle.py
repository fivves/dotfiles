#!/usr/bin/env python3
"""
Waybar Wordle Module
- Fetches today's word from NYT's public endpoint
- Manages game state in ~/.local/share/waybar-wordle/state.json
- Outputs JSON for waybar (text + tooltip)
- Accepts a guess via CLI arg: wordle.py --guess CRANE
"""

import json
import sys
import os
import tempfile
import requests
from datetime import date
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
STATE_DIR  = Path.home() / ".local" / "share" / "waybar-wordle"
STATE_FILE = STATE_DIR / "state.json"
NYT_API    = "https://www.nytimes.com/svc/wordle/v2/{date}.json"
MAX_GUESSES = 6

CORRECT = "🟩"
PRESENT = "🟨"
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


def load_state() -> dict:
    today = str(date.today())
    if STATE_FILE.exists():
        try:
            state = json.loads(STATE_FILE.read_text())
            if state.get("date") != today:
                return new_state(today)
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
        "fetch_error": result.get("error"),
    }


def save_state(state: dict):
    """Atomic write — prevents TUI reading a half-written file."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        fd, tmp_path = tempfile.mkstemp(dir=STATE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp_path, STATE_FILE)
    except Exception:
        # Fallback to direct write if atomic fails for some reason
        STATE_FILE.write_text(json.dumps(state, indent=2))


def score_guess(guess: str, answer: str) -> list[str]:
    result = [ABSENT] * 5
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


def render_board(state: dict) -> str:
    lines = []
    puzzle_id = state.get("puzzle_id", "?")
    lines.append(f"Wordle #{puzzle_id}  —  {state['date']}")
    lines.append("")

    for guess_entry in state["guesses"]:
        tiles = "".join(guess_entry["tiles"])
        lines.append(f"{tiles}  {guess_entry['word']}")

    for _ in range(MAX_GUESSES - len(state["guesses"])):
        lines.append("⬜⬜⬜⬜⬜")

    lines.append("")
    if state["status"] == "won":
        lines.append(f"🎉 Solved in {len(state['guesses'])}/{MAX_GUESSES}!")
    elif state["status"] == "lost":
        lines.append(f"💀 Answer was: {state['word']}")
    else:
        lines.append(f"{MAX_GUESSES - len(state['guesses'])} guess(es) remaining")
        lines.append("Click to guess!")

    return "\n".join(lines)


def status_icon(state: dict) -> str:
    if state["status"] == "won":
        return "✅ Wordle"
    elif state["status"] == "lost":
        return "💀 Wordle"
    elif state.get("fetch_error"):
        return "⚠ Wordle"
    else:
        return f"  Wordle {len(state['guesses'])}/{MAX_GUESSES}"


def do_guess(state: dict, guess: str) -> str:
    guess = guess.strip().upper()

    if state["status"] != "playing":
        return "Game is already over!"
    if len(guess) != 5:
        return "Guess must be exactly 5 letters."
    if not guess.isalpha():
        return "Letters only."
    if state["word"] is None:
        return "Couldn't fetch today's word. Check your connection."

    tiles = score_guess(guess, state["word"])
    state["guesses"].append({"word": guess, "tiles": tiles})

    if guess == state["word"]:
        state["status"] = "won"
    elif len(state["guesses"]) >= MAX_GUESSES:
        state["status"] = "lost"

    return ""


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