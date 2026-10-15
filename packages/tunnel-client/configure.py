"""Write a local tunnel profile; credentials are prompted and never emitted."""

import getpass
import json
import os
import re
import sys
import tempfile
import warnings
from pathlib import Path


def private_write(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".setup-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    os.umask(0o077)
    if not sys.stdin.isatty():
        raise ValueError("Run setup in your terminal so key input can be hidden.")
    warnings.simplefilter("error", getpass.GetPassWarning)
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tunnel-client"
    secrets = root / "buildbuddy-secrets"
    profile = root / "buildbuddy.yaml"
    if profile.exists() or secrets.exists():
        raise ValueError("BuildBuddy tunnel configuration already exists; preserve it and edit locally.")
    tunnel_id = input("OpenAI tunnel ID: ").strip()
    if not re.fullmatch(r"tunnel_[A-Za-z0-9_-]+", tunnel_id):
        raise ValueError("Invalid tunnel ID format.")
    runtime_key = getpass.getpass("OpenAI tunnel runtime key (Tunnels Read + Use): ").strip()
    reader_key = getpass.getpass("BuildBuddy read-only API key: ").strip()
    if not runtime_key or not reader_key or any(c.isspace() for c in runtime_key + reader_key):
        raise ValueError("Keys must be nonempty and contain no whitespace.")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid():
        raise ValueError("Configuration directory must be owned by you and not a symlink.")
    os.chmod(root, 0o700)
    secrets.mkdir(mode=0o700)
    private_write(secrets / "openai-runtime-key", runtime_key)
    private_write(secrets / "buildbuddy-bearer-header", "Bearer " + reader_key)
    config = {
        "config_version": 1,
        "control_plane": {
            "base_url": "https://api.openai.com",
            "tunnel_id": tunnel_id,
            "api_key": "file:" + str(secrets / "openai-runtime-key"),
        },
        "mcp": {
            "server_urls": [{"channel": "main", "url": "https://becker63.buildbuddy.io/mcp"}],
            "extra_headers": {"Authorization": "file:" + str(secrets / "buildbuddy-bearer-header")},
        },
        "health": {"listen_addr": "127.0.0.1:0", "url_file": str(root / "buildbuddy-health-url")},
        "admin_ui": {"open_browser": False},
        "log": {"level": "info", "format": "json"},
    }
    # JSON is accepted by the client's YAML parser and avoids an extra dependency.
    private_write(profile, json.dumps(config, indent=2) + "\n")
    print(f"Private profile saved: {profile}")
    print("Next: tunnel-client doctor --profile buildbuddy --explain")


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("Setup cancelled.")
    except getpass.GetPassWarning:
        raise SystemExit("Hidden key input is unavailable; setup stopped.")
    except (ValueError, OSError) as error:
        # File errors may reveal paths but never values entered through getpass.
        raise SystemExit(str(error))
