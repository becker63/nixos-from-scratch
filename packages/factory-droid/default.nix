{
  droid,
  python3,
  writeShellApplication,
  writeText,
}:

let
  launcher = writeText "droid-launcher.py" ''
    import json
    import os
    import stat
    import sys
    from pathlib import Path

    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    secret_file = config_home / "factory" / "secrets" / "jev.env"
    if not secret_file.is_file():
        print(
            f"droid: missing {secret_file}; restore the private Jev credential file",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if stat.S_IMODE(secret_file.stat().st_mode) & 0o077:
        print(f"droid: {secret_file} must have mode 0600", file=sys.stderr)
        raise SystemExit(2)

    values = []
    for raw_line in secret_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        name, separator, encoded = line.partition("=")
        if separator != "=" or name.strip() != "OPENROUTER_JEV_KEY":
            print(
                f"droid: {secret_file} may contain only OPENROUTER_JEV_KEY",
                file=sys.stderr,
            )
            raise SystemExit(2)
        encoded = encoded.strip()
        try:
            value = json.loads(encoded) if encoded.startswith('"') else encoded
        except json.JSONDecodeError:
            print(f"droid: malformed OPENROUTER_JEV_KEY in {secret_file}", file=sys.stderr)
            raise SystemExit(2)
        if not isinstance(value, str) or not value:
            print(f"droid: empty OPENROUTER_JEV_KEY in {secret_file}", file=sys.stderr)
            raise SystemExit(2)
        values.append(value)

    if len(values) != 1:
        print(
            f"droid: {secret_file} must contain exactly one OPENROUTER_JEV_KEY",
            file=sys.stderr,
        )
        raise SystemExit(2)

    environment = os.environ.copy()
    environment["OPENROUTER_JEV_KEY"] = values[0]
    environment["FACTORY_DROID_AUTO_UPDATE_ENABLED"] = "false"
    executable = "${droid}/bin/droid"
    os.execve(executable, [executable, *sys.argv[1:]], environment)
  '';
in
writeShellApplication {
  name = "droid";
  text = ''
    exec ${python3}/bin/python3 ${launcher} "$@"
  '';
}
