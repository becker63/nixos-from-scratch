"""Configure and run the dedicated secure tunnel for the research graph app."""

from __future__ import annotations

import argparse
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import warnings


def config_root() -> Path:
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tunnel-client"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink() or path.stat().st_uid != os.getuid():
        raise ValueError("Tunnel configuration directory must be owner-owned and not a symlink")
    os.chmod(path, 0o700)
    return path


def write_private(path: Path, content: str) -> None:
    fd, temporary = tempfile.mkstemp(prefix=".research-graph-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure(args: argparse.Namespace) -> None:
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        raise ValueError("Run tunnel setup in a terminal so runtime key input can stay hidden")
    warnings.simplefilter("error", getpass.GetPassWarning)
    root = config_root()
    profile = root / "research-visualizer.yaml"
    secret_dir = root / "research-visualizer-secrets"
    if profile.exists() or secret_dir.exists():
        raise ValueError("Research graph tunnel configuration already exists; preserve it and edit locally")
    tunnel_id = args.tunnel_id or input("OpenAI tunnel ID: ").strip()
    if not re.fullmatch(r"tunnel_[A-Za-z0-9_-]+", tunnel_id):
        raise ValueError("Invalid OpenAI tunnel ID")
    for name in ("jev.json", "buildbuddy.yaml"):
        existing = root / name
        if existing.exists():
            try:
                config = json.loads(existing.read_text(encoding="utf-8"))
                configured_id = config.get("tunnel_id") or config.get("control_plane", {}).get("tunnel_id")
                if configured_id == tunnel_id:
                    raise ValueError("Use a new tunnel ID dedicated to the research graph app")
            except json.JSONDecodeError:
                raise ValueError("Could not verify that the tunnel ID is unique") from None
    key = getpass.getpass("OpenAI tunnel runtime key (Tunnels Read + Use): ").strip()
    if not key or any(char.isspace() for char in key):
        raise ValueError("Tunnel runtime key must be nonempty and contain no whitespace")
    secret_dir.mkdir(mode=0o700)
    os.chmod(secret_dir, 0o700)
    key_path = secret_dir / "openai-runtime-key"
    write_private(key_path, key)
    body = {
        "config_version": 1,
        "control_plane": {
            "base_url": "https://api.openai.com",
            "tunnel_id": tunnel_id,
            "api_key": "file:" + str(key_path),
        },
        "mcp": {
            "commands": [{"channel": "main", "command": args.mcp_command}],
            "stdio_send_initialized_notification": True,
        },
        "health": {"listen_addr": "127.0.0.1:0", "url_file": str(root / "research-visualizer-health-url")},
        "admin_ui": {"open_browser": False},
        "log": {"level": "info", "format": "json"},
    }
    write_private(profile, json.dumps(body, indent=2) + "\n")
    print(f"Private profile saved to {profile}")
    print("Start it with: systemctl --user start research-visualizer-tunnel.service")


def run(args: argparse.Namespace) -> None:
    root = config_root()
    profile = root / "research-visualizer.yaml"
    if not profile.is_file() or profile.is_symlink() or profile.stat().st_mode & 0o077:
        raise ValueError("Configure the owner-private research graph tunnel profile first")
    config = json.loads(profile.read_text(encoding="utf-8"))
    tunnel_id = config["control_plane"]["tunnel_id"]
    if args.action == "doctor":
        os.execv(args.tunnel_client, [args.tunnel_client, "doctor", "--profile-file", str(profile), "--explain"])
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    lock = os.open(runtime / ("research-visualizer-" + tunnel_id + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise ValueError("A client already owns this research graph tunnel ID") from None
    os.set_inheritable(lock, True)
    (root / "research-visualizer-health-url").unlink(missing_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith(("CONTROL_PLANE_", "MCP_", "TUNNEL_CLIENT_", "HEALTH_", "CLOUDFLARED_")) and key not in ("OPENAI_API_KEY", "OPENAI_ADMIN_KEY", "JEV_KEY")}
    os.execve(args.tunnel_client, [args.tunnel_client, "run", "--profile-file", str(profile), "--control-plane.max-inflight", "4"], env)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tunnel-client", required=True)
    parser.add_argument("--mcp-command", required=True)
    actions = parser.add_subparsers(dest="action", required=True)
    setup = actions.add_parser("configure")
    setup.add_argument("--tunnel-id")
    actions.add_parser("doctor")
    actions.add_parser("run")
    args = parser.parse_args()
    try:
        configure(args) if args.action == "configure" else run(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        sys.stderr.write("Research graph tunnel setup failed; check tunnel ID, file ownership, and local profile.\n")
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
