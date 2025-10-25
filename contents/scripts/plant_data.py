#!/usr/bin/env python3
"""
Utility script to track BloomBuddy growth progress.

The script maintains a simple JSON data file under
~/.local/share/plasma-bloombuddy/data.json containing:
{
  "last_opened": "YYYY-MM-DD",
  "growth_stage": 0,
  "day_count": 1
}

Invoking the script returns a JSON payload describing the current plant state.
Use the --water flag to trigger a manual growth update (e.g., when the user
presses the "Water Me" button in the plasmoid UI).
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Dict, Any


DATA_DIR = Path.home() / ".local" / "share" / "plasma-bloombuddy"
DATA_FILE = DATA_DIR / "data.json"

STAGE_NAMES = ["seed", "sprout", "leaf", "bloom"]
MAX_STAGE_INDEX = len(STAGE_NAMES) - 1


@dataclass
class PlantState:
    last_opened: date
    growth_stage: int = 0
    day_count: int = 1
    extra: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def load(cls) -> "PlantState":
        DATA_DIR.mkdir(parents=True, exist_ok=True)

        if not DATA_FILE.exists():
            today = date.today()
            state = cls(last_opened=today)
            state.save()
            return state

        try:
            raw = json.loads(DATA_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            # Fall back to defaults if the file is unreadable/corrupted.
            today = date.today()
            state = cls(last_opened=today)
            state.save()
            return state

        last_opened_str = raw.get("last_opened")
        try:
            last_opened = datetime.strptime(last_opened_str, "%Y-%m-%d").date()
        except (TypeError, ValueError):
            last_opened = date.today()

        growth_stage = int(raw.get("growth_stage", 0))
        day_count = int(raw.get("day_count", max(1, growth_stage + 1)))

        # Capture any unrecognised fields so we can persist them unchanged.
        known_keys = {"last_opened", "growth_stage", "day_count"}
        extra = {key: value for key, value in raw.items() if key not in known_keys}

        return cls(
            last_opened=last_opened,
            growth_stage=max(0, min(growth_stage, MAX_STAGE_INDEX)),
            day_count=max(1, day_count),
            extra=extra,
        )

    def save(self) -> None:
        payload = {
            "last_opened": self.last_opened.isoformat(),
            "growth_stage": self.growth_stage,
            "day_count": self.day_count,
            **self.extra,
        }
        DATA_FILE.write_text(json.dumps(payload, indent=2))

    def advance_days(self, days: int) -> None:
        if days <= 0:
            return

        self.growth_stage = min(self.growth_stage + days, MAX_STAGE_INDEX)
        self.day_count += days
        self.last_opened = date.today()

    def water(self) -> None:
        if self.growth_stage < MAX_STAGE_INDEX:
            self.growth_stage += 1
        self.day_count = max(self.day_count, self.growth_stage + 1)
        # Watering is considered care taken today.
        self.last_opened = date.today()


def build_response(state: PlantState, days_idle: int) -> Dict[str, Any]:
    stage_name = STAGE_NAMES[state.growth_stage]
    return {
        "stage": stage_name,
        "stage_index": state.growth_stage,
        "day": state.day_count,
        "image": f"assets/plant_{stage_name}.png",
        "is_wilted": days_idle > 3,
        "days_idle": days_idle,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="BloomBuddy growth tracker")
    parser.add_argument(
        "--water",
        action="store_true",
        help="Trigger a manual growth update as if the plant was watered.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    state = PlantState.load()
    today = date.today()
    days_since_last_open = (today - state.last_opened).days

    if days_since_last_open > 0:
        state.advance_days(days_since_last_open)

    if args.water:
        state.water()

    # Persist state after any changes.
    state.save()

    response = build_response(state, days_since_last_open)
    print(json.dumps(response))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
