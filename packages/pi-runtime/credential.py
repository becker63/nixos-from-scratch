"""Private Fabric credential command. Never evaluates dotenv as shell code."""
import re
import sys
from pathlib import Path

ENV_FILE = Path("/home/becker/nixos-from-scratch/.env")


def parse(text):
    entries = []
    for line in text.splitlines():
        if not re.match(r"^\s*(?:export\s+)?JEV_KEY(?:\s|=|$)", line):
            continue
        match = re.fullmatch(r"\s*(?:export\s+)?JEV_KEY\s*=\s*(.*?)\s*", line)
        if not match:
            raise ValueError()
        value = match[1]
        if value.startswith(("'", '"')):
            quote = value[0]
            if len(value) < 2 or value[-1] != quote:
                raise ValueError()
            value = value[1:-1]
        # Keys are opaque printable tokens, never escapes, expansions or comments.
        if not re.fullmatch(r"[A-Za-z0-9_./:+=\-]+", value):
            raise ValueError()
        entries.append(value)
    if len(entries) != 1:
        raise ValueError()
    return entries[0]


if __name__ == "__main__":
    try:
        if len(sys.argv) != 1:
            raise ValueError()
        key = parse(ENV_FILE.read_text())
    except (OSError, UnicodeError, ValueError):
        sys.stderr.write("Jev credential unavailable or malformed\n")
        sys.exit(1)
    sys.stdout.write(key)
