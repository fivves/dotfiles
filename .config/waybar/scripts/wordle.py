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
import requests
from datetime import date
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
STATE_DIR = Path.home() / ".local" / "share" / "waybar-wordle"
STATE_FILE = STATE_DIR / "state.json"
NYT_API = "https://www.nytimes.com/svc/wordle/v2/{date}.json"
MAX_GUESSES = 6

# Tile colors for tooltip (using unicode blocks + labels)
CORRECT = "🟩"   # right letter, right spot
PRESENT = "🟨"   # right letter, wrong spot
ABSENT  = "⬛"   # not in word

# ── Helpers ───────────────────────────────────────────────────────────────────

def fetch_word(today: str) -> dict:
    """Fetch today's Wordle from NYT."""
    try:
        resp = requests.get(
            NYT_API.format(date=today), timeout=5
        )
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
            # Reset if it's a new day
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
        "status": "playing",  # playing | won | lost
        "fetch_error": result.get("error"),
    }


def save_state(state: dict):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def score_guess(guess: str, answer: str) -> list[str]:
    """Return a list of CORRECT/PRESENT/ABSENT tiles for a guess."""
    result = [ABSENT] * 5
    answer_chars = list(answer)
    guess_chars = list(guess)

    # First pass: correct positions
    for i in range(5):
        if guess_chars[i] == answer_chars[i]:
            result[i] = CORRECT
            answer_chars[i] = None
            guess_chars[i] = None

    # Second pass: present but wrong position
    for i in range(5):
        if guess_chars[i] is None:
            continue
        if guess_chars[i] in answer_chars:
            result[i] = PRESENT
            answer_chars[answer_chars.index(guess_chars[i])] = None

    return result


def render_board(state: dict) -> str:
    """Render the Wordle board for the tooltip."""
    lines = []
    puzzle_id = state.get("puzzle_id", "?")
    lines.append(f"Wordle #{puzzle_id}  —  {state['date']}")
    lines.append("")

    for guess_entry in state["guesses"]:
        word = guess_entry["word"]
        tiles = guess_entry["tiles"]
        lines.append(f"{''.join(tiles)}  {word}")

    # Empty rows
    remaining = MAX_GUESSES - len(state["guesses"])
    for _ in range(remaining):
        lines.append("⬜⬜⬜⬜⬜")

    lines.append("")
    if state["status"] == "won":
        guesses_taken = len(state["guesses"])
        lines.append(f"🎉 Solved in {guesses_taken}/{MAX_GUESSES}!")
    elif state["status"] == "lost":
        lines.append(f"💀 Answer was: {state['word']}")
    else:
        guesses_left = MAX_GUESSES - len(state["guesses"])
        lines.append(f"{guesses_left} guess(es) remaining")
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
        guesses_taken = len(state["guesses"])
        return f"🟩 Wordle {guesses_taken}/{MAX_GUESSES}"


def do_guess(state: dict, guess: str) -> str:
    """Process a guess. Returns an error string or empty string on success."""
    guess = guess.strip().upper()

    if state["status"] != "playing":
        return "Game is already over!"
    if len(guess) != 5:
        return "Guess must be exactly 5 letters."
    if not guess.isalpha():
        return "Guess must be letters only."
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

    # Handle --guess argument (called by on-click)
    if len(sys.argv) >= 3 and sys.argv[1] == "--guess":
        guess = sys.argv[2]
        err = do_guess(state, guess)
        save_state(state)
        if err:
            # Output error briefly — waybar will re-poll
            print(json.dumps({
                "text": f"❌ {err}",
                "tooltip": render_board(state),
                "class": "error",
            }))
        else:
            print(json.dumps({
                "text": status_icon(state),
                "tooltip": render_board(state),
            }))
        return

    # Normal output
    save_state(state)
    output = {
        "text": status_icon(state),
        "tooltip": render_board(state),
        "class": state["status"],
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()