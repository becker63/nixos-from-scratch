# XONSH WEBCONFIG START
xontrib load jedi
xontrib load prompt_starship

#$XONSH_SHOW_TRACEBACK = True

# ───────────────────────────────
# aliases
aliases['cloc'] = 'tokei'
aliases['htop'] = 'btm'
aliases['btop'] = 'btm'
aliases['top'] = 'btm'
aliases['cpu'] = 'btm --default_widget_type cpu --default_widget_count 1 --expanded'
aliases['dev'] = 'nix develop -c $SHELL || true'
aliases['resetxonsh'] = "tmux ls | awk '/^xonsh_reserve_/ {print $1}' | sed 's/:$//' | xargs -r tmux kill-session -t"
aliases['zed'] = 'zed -n'
aliases['zed_raw'] = 'zed_raw -n'
aliases['bluetooth'] = 'bluetuith'


from pathlib import Path
import subprocess

def repoclip(args, stdin=None):
    target = args[0] if args else "."
    output = Path("repomix-output.xml")

    pack = subprocess.run(["repomix", target])
    if pack.returncode != 0:
        return pack.returncode

    if not output.exists():
        print(f"[repoclip] expected output file not found: {output}")
        return 1

    with output.open("rb") as f:
        copy = subprocess.run(["wl-copy"], stdin=f)

    if copy.returncode == 0:
        print(f"[repoclip] packed {target} and copied {output} to clipboard")
    return copy.returncode

aliases["repoclip"] = repoclip
aliases["rmx"] = repoclip

import shutil
import os

REAL_NIX = shutil.which("nix")

def nix(args, stdin=None):
    if args and args[0] == "develop":
        os.execv(REAL_NIX, [REAL_NIX, "develop", "-c", "xonsh", *args[1:]])
    else:
        os.execv(REAL_NIX, [REAL_NIX, *args])

aliases["nix"] = nix

import os

def find_executable(cmd):
    for p in $PATH:
        full = os.path.join(p, cmd)
        if os.path.exists(full) and os.access(full, os.X_OK):
            return full
    return None

clear_bin = find_executable("clear")
aliases['cb'] = clear_bin
aliases['c'] = 'printf "\\033[H\\033[2J"'

# starship
$STARSHIP_CONFIG = $HOME + '/.config/starship/starship.toml'

# ───────────────────────────────
# Lorri + Nix helpers
import subprocess, os
from xonsh.built_ins import XSH
from pathlib import Path

def in_lorri_project():
    """Return True if cwd (or a parent) has .envrc / shell.nix / flake.nix"""
    cur = Path.cwd()
    for marker in [".envrc", "shell.nix", "flake.nix"]:
        if any(p.joinpath(marker).exists() for p in cur.parents) or cur.joinpath(marker).exists():
            return True
    return False

def lorri_env():
    bash_cmd = 'eval "$(lorri direnv)" >/dev/null 2>&1; env -0'
    result = subprocess.run(["bash", "-c", bash_cmd], capture_output=True, text=False)
    env_vars = {}
    for entry in result.stdout.split(b"\0"):
        if b"=" in entry:
            k, v = entry.split(b"=", 1)
            env_vars[k.decode()] = v.decode()
    return env_vars

def clear_lorri():
    for k in list(XSH.env.keys()):
        if "NIX" in k or k in ("IN_NIX_SHELL",):
            XSH.env.pop(k, None)
    print("[lorri] environment cleared")

def apply_lorri():
    if not in_lorri_project():
        clear_lorri()
        return
    env_vars = lorri_env()
    if not env_vars:
        print("[lorri] no env captured, falling back to nix develop...")
        os.system("nix develop")
        return
    with XSH.env.swap(UPDATE_OS_ENVIRON=True):
        for k, v in env_vars.items():
            if v is None:
                XSH.env.pop(k, None)
            else:
                XSH.env[k] = v
    print("[lorri] environment applied")

def smart_cd_alias(args):
    result = subprocess.run(["smart_cd"] + list(args), text=True, capture_output=True)
    newdir = result.stdout.strip()
    if newdir and os.path.isdir(newdir):
        os.chdir(newdir)
    else:
        print(f"No matching directory for {args!r}")

aliases['cd'] = smart_cd_alias
aliases['lorri-reload'] = lambda args: __xonsh__.ctx['apply_lorri']()
aliases['lorri-leave'] = lambda args: __xonsh__.ctx['clear_lorri']()

# ───────────────────────────────
# Adaptive File / Clipboard System
from dataclasses import dataclass
import time, pyclip

@dataclass
class FileMeta:
    path: str
    name: str
    ext: str
    size: int
    lines: int
    mtime: str
    content: str


_BasePath = type(Path())

class File(_BasePath):
    """Procedural File interface with adaptive truncation and auto clipboard copy."""
    _collected = []
    _prepared = False
    _max_bytes = 1_000_000
    _default_lines = 100
    _clip_total = 0
    _autocommit = True

    # ───────────────────────────────
    @classmethod
    def clip_reset(cls):
        cls._collected.clear()
        cls._prepared = False
        cls._clip_total = 0

    @classmethod
    def _finalize(cls):
        if not cls._collected:
            return
        total_est = sum(len(f._raw_preview.encode("utf8")) for f in cls._collected)
        scale = 1.0 if total_est <= cls._max_bytes else cls._max_bytes / total_est
        scaled_lines = max(1, int(cls._default_lines * scale))
        cls._clip_total = 0
        for f in cls._collected:
            f._truncated_content = "\n".join(f._raw_preview.splitlines()[:scaled_lines])
            cls._clip_total += len(f._truncated_content.encode("utf8"))
        cls._prepared = True
        if cls._autocommit:
            text = "\n\n".join(f"## {f.name}\n{f._truncated_content}" for f in cls._collected)
            pyclip.copy(text)
            print(f"📏 adaptive scale={scale:.2f} → {scaled_lines} lines per file")
            print(f"✅ copied {len(cls._collected)} files ({len(text)/1024:.1f} KB total)")

    # ───────────────────────────────
    def rglob(self, pattern):
        File.clip_reset()
        for f in super().rglob(pattern):
            yield File(f)
        if File._autocommit:
            File._finalize()

    @property
    def readable(self):
        return self.is_file() and os.access(self, os.R_OK)

    def clip(self, lines=100, max_bytes=1_000_000):
        File._default_lines = lines
        File._max_bytes = max_bytes
        if not self.readable:
            return False
        with open(self, encoding="utf8", errors="ignore") as f:
            raw = []
            for i, line in enumerate(f):
                if i >= lines:
                    break
                raw.append(line)
        self._raw_preview = "".join(raw)
        File._collected.append(self)
        return len(self._raw_preview.strip()) > 0

    @property
    def truncated(self):
        return getattr(self, "_truncated_content", getattr(self, "_raw_preview", ""))

    @property
    def content(self):
        return self.truncated

execx($(atuin init xonsh))

$SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"
$SSL_CERT_DIR = "/etc/ssl/certs"

if "~/.local/bin" not in $PATH:
    $PATH.append("~/.local/bin")


npm_global_bin = os.path.expanduser("~/.npm-global/bin")
if npm_global_bin not in $PATH:
    $PATH.insert(0, npm_global_bin)


# XONSH WEBCONFIG END
