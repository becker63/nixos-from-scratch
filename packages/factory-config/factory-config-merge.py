#!/usr/bin/env python3
"""Merge the Nix-owned Factory defaults without freezing user-managed JSON."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any


JEV_ENV_PLACEHOLDER = "${OPENROUTER_JEV_KEY}"

SETTINGS_DEFAULTS: dict[str, Any] = {
    "model": "glm-5.3-flash",
    "reasoningEffort": "max",
    "showTokenUsageIndicator": True,
    "blockOnMcpLoad": True,
    "subagentAutonomyLevel": "inherit",
    "subagentModelSettings": {
        "lightModel": "glm-5.3-flash",
        "lightReasoningEffort": "high",
        "mediumModel": "glm-5.3-flash",
        "mediumReasoningEffort": "max",
        "heavyModel": "glm-5.3",
        "heavyReasoningEffort": "max",
    },
    "sessionDefaultSettings": {
        "specModeModel": "glm-5.3",
        "specModeReasoningEffort": "max",
    },
    "missionModelSettings": {
        "workerModel": "glm-5.3-flash",
        "workerReasoningEffort": "max",
        "validationWorkerModel": "glm-5.3",
        "validationWorkerReasoningEffort": "max",
    },
    "missionOrchestratorModel": "glm-5.3",
    "missionOrchestratorReasoningEffort": "max",
    "modelFallbacks": {"glm-5.3-flash": "glm-5.3"},
}


class ConfigError(RuntimeError):
    """Raised before writing when an existing Factory file is unsafe to merge."""


def load_object(path: Path, empty: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return empty.copy()
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConfigError(f"Factory config is malformed; refusing to overwrite {path}") from error
    if not isinstance(value, dict):
        raise ConfigError(f"Factory config must be a JSON object; refusing to overwrite {path}")
    return value


def merge_owned(existing: dict[str, Any], desired: dict[str, Any]) -> dict[str, Any]:
    """Recursively overlay only desired keys, preserving every unrelated value."""
    result = existing.copy()
    for key, value in desired.items():
        previous = result.get(key)
        if isinstance(value, dict) and isinstance(previous, dict):
            result[key] = merge_owned(previous, value)
        elif isinstance(value, dict):
            result[key] = merge_owned({}, value)
        else:
            result[key] = value
    return result


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(payload)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def configure(factory_dir: Path, jev_command: str) -> None:
    factory_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(factory_dir, 0o700)

    mcp_path = factory_dir / "mcp.json"
    settings_path = factory_dir / "settings.json"

    # Parse and validate every input before changing either file.
    mcp = load_object(mcp_path, {"mcpServers": {}})
    settings = load_object(settings_path, {})
    servers = mcp.get("mcpServers", {})
    if not isinstance(servers, dict):
        raise ConfigError(
            f"Factory mcpServers must be a JSON object; refusing to overwrite {mcp_path}"
        )

    mcp = merge_owned(
        mcp,
        {
            "mcpServers": {
                "jev": {
                    "type": "stdio",
                    "command": jev_command,
                    "args": [],
                    "disabled": False,
                    "env": {"OPENROUTER_API_KEY": JEV_ENV_PLACEHOLDER},
                    "connectTimeout": 30_000,
                    "timeout": 60_000,
                }
            }
        },
    )
    settings = merge_owned(settings, SETTINGS_DEFAULTS)

    # Auto is the default for a new setup, but retain an intentional existing mode.
    session_defaults = settings.setdefault("sessionDefaultSettings", {})
    if not isinstance(session_defaults, dict):
        raise ConfigError(
            f"Factory sessionDefaultSettings must be a JSON object; refusing to overwrite {settings_path}"
        )
    session_defaults.setdefault("interactionMode", "auto")

    atomic_json(mcp_path, mcp)
    atomic_json(settings_path, settings)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--factory-dir", required=True, type=Path)
    parser.add_argument("--jev-command", required=True)
    args = parser.parse_args()
    try:
        configure(args.factory_dir, args.jev_command)
    except ConfigError as error:
        parser.exit(1, f"factory-config-merge: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
