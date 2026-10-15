"""Reader for the shared Attune JSONL event fixture and run streams."""

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "events.jsonl"


def load_events(path: Path = FIXTURE) -> list[dict[str, Any]]:
    events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    for event in events:
        if event.get("schema") != "attune.research-event.v1":
            raise ValueError("unsupported event schema")
    return events
