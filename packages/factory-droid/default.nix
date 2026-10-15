{
  droid,
  fetchurl,
  stdenv,
  python3,
  writeShellApplication,
  writeText,
}:

let
  # Update only the CLI binary; keep all flake inputs and kernel pins frozen.
  version = "0.241.1";
  platforms = {
    aarch64-linux = {
      path = "linux/arm64";
      hash = "0d22c2783710c83089f87d3b1f8228629cff12d8753c69b802298760f00bd019";
    };
    x86_64-linux = {
      path = "linux/x64";
      hash = "2e32c416a6763ea728418d63fec435571d16669a0485025200a4a547372a3723";
    };
    aarch64-darwin = {
      path = "darwin/arm64";
      hash = "f8bc0191309f005b9f78f5d479affe8fd5d205558e653d015e8be44fb5f644f8";
    };
  };
  platform = platforms.${stdenv.hostPlatform.system};
  updatedDroid = droid.overrideAttrs {
    inherit version;
    src = fetchurl {
      url = "https://downloads.factory.ai/factory-cli/releases/${version}/${platform.path}/droid";
      sha256 = platform.hash;
    };
  };
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
    executable = "${updatedDroid}/bin/droid"
    os.execve(executable, [executable, *sys.argv[1:]], environment)
  '';
in
writeShellApplication {
  name = "droid";
  text = ''
    exec ${python3}/bin/python3 ${launcher} "$@"
  '';
}
