# XONSH WEBCONFIG START
xontrib load jedi
xontrib load prompt_starship

#$XONSH_SHOW_TRACEBACK = True

# A failed interactive command should update $LAST_RETURN_CODE, not terminate
# xonsh (and therefore Alacritty).  Xonsh otherwise raises for a failed final
# command in a logical chain by default.
$XONSH_SUBPROC_RAISE_ERROR = False
$XONSH_SUBPROC_CMD_RAISE_ERROR = False

# ───────────────────────────────
# aliases
aliases['cloc'] = 'tokei'
aliases['htop'] = 'btm'
aliases['btop'] = 'btm'
aliases['top'] = 'btm'
aliases['cpu'] = 'btm --default_widget_type cpu --default_widget_count 1 --expanded'
aliases['mem'] = 'btm --default_widget_type mem --default_widget_count 1 --expanded'
aliases['dev'] = 'nix develop -c $SHELL || true'
aliases['zed'] = 'zed -n'
aliases['zed_raw'] = 'zed_raw -n'
aliases['bluetooth'] = 'bluetuith'
# Project-local refactoring tools. Their Python APIs are also importable
# directly in Xonsh whenever the current uv workspace provides them.
aliases['cst'] = 'uv run python -m libcst.tool'
aliases['griffe'] = 'uv run python -m griffe'


def _parse_meminfo():
    memory = {}
    with open("/proc/meminfo", encoding="utf-8") as meminfo:
        for line in meminfo:
            key, value, *_unit = line.split()
            try:
                memory[key[:-1]] = int(value)
            except ValueError:
                continue
    return memory


def _read_pressure_stat(path):
    pressures = {}
    try:
        with open(path, encoding="utf-8") as pressure_file:
            for line in pressure_file:
                parts = line.split()
                if len(parts) < 2:
                    continue
                kind = parts[0]
                values = {}
                for token in parts[1:]:
                    key, value = token.split("=")
                    values[key] = value
                pressures[kind] = values
    except OSError:
        return {}
    return pressures


def _read_nvme_stat(device):
    base = f"/sys/block/{device}"
    if not os.path.isdir(base):
        return None

    sector_size = 512
    hw_sector = Path(base) / "queue" / "hw_sector_size"
    if hw_sector.is_file():
        try:
            sector_size = int(hw_sector.read_text().strip())
        except ValueError:
            pass

    stats = Path(base) / "stat"
    if not stats.is_file():
        return None

    values = list(map(int, stats.read_text().split()))
    if len(values) < 11:
        return None

    return {
        "device": device,
        "read_ios": values[0],
        "read_merges": values[1],
        "read_sectors": values[2],
        "read_ms": values[3],
        "write_ios": values[4],
        "write_merges": values[5],
        "write_sectors": values[6],
        "write_ms": values[7],
        "ios_inflight": values[8],
        "io_ms": values[9],
        "weighted_io_ms": values[10],
        "sector_size": sector_size,
        "inflight_path": Path(base) / "inflight",
        "queue_depth_path": Path(base) / "queue" / "nr_requests",
    }


def _read_zswap_status():
    enabled_file = Path("/sys/module/zswap/parameters/enabled")
    if not enabled_file.is_file():
        return "zswap module not loaded"

    enabled = enabled_file.read_text().strip()
    if enabled.lower() == "n":
        return "zswap disabled"

    debug_root = Path("/sys/kernel/debug/zswap")
    if not debug_root.is_dir():
        return "zswap enabled (debugfs stats unavailable)"

    fields = [
        "stored_pages",
        "pool_used_pages",
        "compressed_size",
        "same_filled_pages",
        "decompressed_pages",
    ]
    values = []
    for field in fields:
        path = debug_root / field
        if path.is_file():
            try:
                values.append(f"{field}={path.read_text().strip()}")
            except OSError:
                values.append(f"{field}=!")
    if not values:
        return "zswap enabled (no counters readable)"
    return ", ".join(values)


def _human(v):
    for unit in ("KiB", "MiB", "GiB", "TiB"):
        if abs(v) < 1024:
            return f"{v:.1f} {unit}"
        v = v / 1024
    return f"{v:.1f} PiB"


def memwatch(args, stdin=None):
    interval = 2.0
    device = "nvme0n1"
    if args:
        try:
            interval = float(args[0])
            if len(args) > 1:
                device = args[1]
        except ValueError:
            device = args[0]
            if len(args) > 1:
                interval = float(args[1])

    if interval <= 0:
        interval = 1.0

    previous_nvme = None
    previous_ts = None
    while True:
        now = time.time()

        mem = _parse_meminfo()
        mem_used = mem.get("MemTotal", 0) - mem.get("MemAvailable", 0)
        swap_used = mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)
        mem_pressure = _read_pressure_stat("/proc/pressure/memory")
        io_pressure = _read_pressure_stat("/proc/pressure/io")
        nvme = _read_nvme_stat(device)

        mem_line = "Mem {used} / {total} ({pct:.1f}%)".format(
            used=_human(mem_used / 1024),
            total=_human(mem.get("MemTotal", 0) / 1024),
            pct=(mem_used / mem.get("MemTotal", 1)) * 100,
        )
        swap_line = "Swap {used} / {total} ({pct:.1f}%)".format(
            used=_human(swap_used / 1024),
            total=_human(mem.get("SwapTotal", 0) / 1024),
            pct=(swap_used / mem.get("SwapTotal", 1)) * 100 if mem.get("SwapTotal", 0) else 0.0,
        )
        print("\033[2J\033[H", end="")
        print(f"[memwatch] interval={interval:.2f}s device={device}")
        print(f"Memory: {mem_line}")
        print(f"{swap_line}")
        print(f"zswap: {_read_zswap_status()}")
        if mem_pressure.get("some"):
            print(
                "PSI memory: some avg10={some[avg10]} avg60={some[avg60]} avg300={some[avg300]} "
                "full avg10={full[avg10]} avg60={full[avg60]} avg300={full[avg300]}".format(
                    some=mem_pressure.get("some", {}),
                    full=mem_pressure.get("full", {}),
                ),
            )
        if io_pressure.get("some"):
            print(
                "PSI io    : some avg10={some[avg10]} avg60={some[avg60]} avg300={some[avg300]} "
                "full avg10={full[avg10]} avg60={full[avg60]} avg300={full[avg300]}".format(
                    some=io_pressure.get("some", {}),
                    full=io_pressure.get("full", {}),
                ),
            )

        if nvme is None:
            print(f"NVMe      : /sys/block/{device} not available")
        else:
            queue_depth = "?"
            if nvme["queue_depth_path"].is_file():
                try:
                    queue_depth = nvme["queue_depth_path"].read_text().strip()
                except OSError:
                    pass

            inflight = "?"
            if nvme["inflight_path"].is_file():
                try:
                    inr, inw = nvme["inflight_path"].read_text().split()
                    inflight = f"{inr}/{inw}"
                except Exception:
                    pass

            print(f"NVMe {device}: queue_depth={queue_depth} inflight={inflight}")

            if previous_nvme and previous_ts:
                dt = now - previous_ts
                if dt > 0:
                    read_ios = nvme["read_ios"] - previous_nvme["read_ios"]
                    write_ios = nvme["write_ios"] - previous_nvme["write_ios"]
                    read_bytes = (nvme["read_sectors"] - previous_nvme["read_sectors"]) * nvme["sector_size"]
                    write_bytes = (nvme["write_sectors"] - previous_nvme["write_sectors"]) * nvme["sector_size"]
                    io_ms = nvme["io_ms"] - previous_nvme["io_ms"]
                    weighted_ms = nvme["weighted_io_ms"] - previous_nvme["weighted_io_ms"]

                    io_util = (io_ms / (dt * 1000)) * 100
                    avg_q = weighted_ms / (dt * 1000)
                    print(
                        "iostat-like: read {r_iops:.1f} r/s, {r_mbps:.2f} MB/s; "
                        "write {w_iops:.1f} w/s, {w_mbps:.2f} MB/s; util {util:.1f}%, avg_q {avgq:.2f}".format(
                            r_iops=read_ios / dt,
                            r_mbps=read_bytes / dt / (1024 ** 2),
                            w_iops=write_ios / dt,
                            w_mbps=write_bytes / dt / (1024 ** 2),
                            util=io_util,
                            avgq=avg_q,
                        )
                    )
            previous_nvme = nvme
            previous_ts = now

        print("\nCtrl-C to stop")
        time.sleep(interval)


aliases["memwatch"] = memwatch


from pathlib import Path
import importlib.util
import jedi
import os
import pkgutil
import re
import site
import shutil
import subprocess
import sys
import tempfile
from xonsh.built_ins import XSH
from xonsh.completers import completer
from xonsh.completers.tools import RichCompletion, contextual_completer


# Make Python expressions entered at the prompt use the active uv project's
# existing virtual environment. This lets `import attune` and `import mlflow`
# work after `cd`-ing into a project, without activating a venv or syncing it.
_uv_import_paths = []


def _uv_project_root(directory):
    """Return the nearest uv project containing an existing .venv."""
    for candidate in (Path(directory).resolve(), *Path(directory).resolve().parents):
        if (candidate / "pyproject.toml").is_file() and (candidate / ".venv").is_dir():
            return candidate
    return None


def refresh_uv_workspace_imports(directory=None):
    """Replace shell-only import paths with those from the current uv project."""
    global _uv_import_paths

    for path in _uv_import_paths:
        while path in sys.path:
            sys.path.remove(path)
    _uv_import_paths = []

    project = _uv_project_root(directory or Path.cwd())
    if project is None:
        return

    # uv projects commonly use a src/ layout. Add it explicitly since a
    # project need not be installed into its own virtual environment.
    project_paths = [
        str(path)
        for path in (project / "src", project)
        if path.is_dir()
    ]
    site_paths = []
    site_packages = project / ".venv" / "lib"
    for python_lib in site_packages.glob("python*/site-packages"):
        original_paths = list(sys.path)
        site.addsitedir(str(python_lib))
        added_paths = [path for path in sys.path if path not in original_paths]
        for path in added_paths:
            sys.path.remove(path)
        site_paths.extend(added_paths)

    # Keep the project's code and dependencies ahead of xonsh's interpreter
    # paths, with local source taking precedence over installed packages.
    _uv_import_paths = project_paths + site_paths
    sys.path[0:0] = _uv_import_paths


@events.on_chdir
def _refresh_uv_workspace_imports_on_chdir(olddir, newdir):
    refresh_uv_workspace_imports(newdir)


refresh_uv_workspace_imports()


_workspace_module_expression = re.compile(
    r"(?P<package>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(?P<prefix>[A-Za-z_]\w*)?$"
)


@contextual_completer
def complete_uv_workspace_modules(context):
    """Complete unimported local package modules without executing them."""
    python_context = context.python
    if python_context is None:
        return None

    match = _workspace_module_expression.search(python_context.prefix)
    if match is None:
        return None

    package_name = match.group("package")
    typed_prefix = match.group("prefix") or ""
    root_package = package_name.partition(".")[0]
    root_module = sys.modules.get(root_package)
    if root_module is None or not hasattr(root_module, "__path__"):
        return None

    try:
        spec = importlib.util.find_spec(package_name)
    except (AttributeError, ModuleNotFoundError, ValueError):
        return None
    if spec is None:
        return None

    if spec.submodule_search_locations is not None:
        modules = {
            RichCompletion(
                module.name,
                prefix_len=len(typed_prefix),
                display=module.name,
                description=f"local module: {package_name}.{module.name}",
            )
            for module in pkgutil.iter_modules(spec.submodule_search_locations)
            if module.name.startswith(typed_prefix) and not module.name.startswith("_")
        }
        return modules or None

    # A leaf module has no package directory to enumerate. Jedi can analyze
    # its local source without executing it, which exposes public classes and
    # functions such as `attune.composition.CompositionProgram`.
    source = f"import {package_name}\n{package_name}.{typed_prefix}"
    column = len(package_name) + 1 + len(typed_prefix)
    try:
        symbols = jedi.Interpreter(source, [python_context.ctx or {}, {"__xonsh__": XSH}]).complete(2, column)
    except Exception:
        return None
    completions = {
        RichCompletion(
            symbol.name,
            prefix_len=len(typed_prefix),
            display=symbol.name + ("()" if symbol.type == "function" else ""),
            description=f"{symbol.type} from {package_name}",
        )
        for symbol in symbols
        if symbol.name.startswith(typed_prefix) and not symbol.name.startswith("_")
    }
    return completions or None


# Let local source packages contribute their actual on-disk module tree before
# Jedi completes imported Python attributes.
completer.add_one_completer("uv_workspace_modules", complete_uv_workspace_modules, "<jedi_python")

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


def rapidpack(args, stdin=None):
    """Serialize a repository quickly and copy it for a ChatGPT paste.

    Yek is a parallel Rust packer.  This intentionally skips token accounting
    and configuration loading, and uses every CPU available to the shell.
    """
    target = list(args) or ["."]
    environment = os.environ.copy()
    environment["RAYON_NUM_THREADS"] = str(os.cpu_count() or 1)
    pack = subprocess.run(
        ["yek", "--no-config", "--output-name", "chatgpt-context.txt", *target],
        env=environment,
    )
    if pack.returncode != 0:
        return pack.returncode

    output = Path("/tmp/yek-output/chatgpt-context.txt")
    if not output.is_file():
        print(f"rp: expected Yek output was not found: {output}")
        return 1

    with output.open("rb") as source:
        return subprocess.run(["wl-copy"], stdin=source).returncode


aliases["rp"] = rapidpack
aliases["rapidpack"] = rapidpack


def _copybuffer_archive_path():
    """Return this Alacritty window's private transcript path."""
    window_id = os.environ.get("ALACRITTY_WINDOW_ID")
    if not window_id:
        return None

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        state_dir = Path(runtime_dir) / "alacritty-copybuffer"
    else:
        state_dir = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "alacritty-copybuffer"
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)

    safe_window_id = re.sub(r"[^A-Za-z0-9_.-]", "_", window_id)
    return state_dir / f"{safe_window_id}.txt"


def _replace_copybuffer_archive(path, contents):
    """Atomically retain a transcript without exposing it to other users."""
    with tempfile.NamedTemporaryFile(mode="wb", dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
        temporary.write(contents)
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def _copybuffer(args, stdin=None):
    if args:
        print("usage: cb")
        return 2

    alacritty = shutil.which("alacritty")
    if alacritty is None:
        print("cb: alacritty is not available")
        return 127

    # Capture and clear the live terminal in one IPC request. The captured
    # text is then appended to this window's private transcript, so
    # later `cb` runs retain all history while the terminal itself is clean.
    # ALACRITTY_SOCKET and ALACRITTY_WINDOW_ID target this terminal.
    capture = subprocess.run([alacritty, "msg", "copy-buffer", "--clear"])
    if capture.returncode != 0:
        return capture.returncode

    snapshot = subprocess.run(["wl-paste", "--no-newline"], stdout=subprocess.PIPE)
    if snapshot.returncode != 0:
        print("cb: could not read Alacritty's captured clipboard")
        return snapshot.returncode

    archive_path = _copybuffer_archive_path()
    if archive_path is None:
        print("cb: ALACRITTY_WINDOW_ID is not available")
        return 1

    previous = archive_path.read_bytes() if archive_path.is_file() else b""
    transcript = previous + (b"\n" if previous and snapshot.stdout else b"") + snapshot.stdout
    _replace_copybuffer_archive(archive_path, transcript)
    return subprocess.run(["wl-copy"], input=transcript).returncode


aliases["cb"] = _copybuffer
aliases["copybuffer"] = _copybuffer
aliases["copyall"] = _copybuffer


REAL_ALACRITTY = shutil.which("alacritty")
REAL_CODEX = shutil.which("codex")


_GUTTER_EVENTS = frozenset({
    "codex-start",
    "codex-stop",
    "command-start",
    "command-pass",
    "command-fail",
})


def _gutter_event(event):
    """Best-effort delivery of one typed event to this Alacritty window."""
    if event not in _GUTTER_EVENTS or REAL_ALACRITTY is None:
        return False
    if not os.environ.get("ALACRITTY_SOCKET") or not os.environ.get("ALACRITTY_WINDOW_ID"):
        return False

    try:
        result = subprocess.run(
            [REAL_ALACRITTY, "msg", "gutter-event", event],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=0.5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


@events.on_precommand
def _gutter_command_started(cmd, **kwargs):
    """Open a visual scope for an interactive command."""
    _gutter_event("command-start")


@events.on_postcommand
def _gutter_command_finished(cmd, rtn, out, ts, **kwargs):
    """Close the current visual scope with its real command result."""
    _gutter_event("command-pass" if rtn == 0 else "command-fail")


def _codex(args, stdin=None):
    """Run Codex inside the semantic gutter's agent interval."""
    if REAL_CODEX is None:
        print("codex: command not found")
        return 127

    _gutter_event("codex-start")
    try:
        return subprocess.run([REAL_CODEX, *args], stdin=stdin).returncode
    finally:
        _gutter_event("codex-stop")


aliases["codex"] = _codex


REAL_NIX = shutil.which("nix")

def nix(args, stdin=None):
    if REAL_NIX is None:
        print("nix: command not found")
        return 127

    if args and args[0] == "develop":
        result = subprocess.run([REAL_NIX, "develop", "-c", "xonsh", *args[1:]], stdin=stdin)
    else:
        result = subprocess.run([REAL_NIX, *args], stdin=stdin)

    return result.returncode

aliases["nix"] = nix

# `c` remains the lightweight visible-screen clear.
aliases['c'] = 'printf "\\033[H\\033[2J"'

# Starship keeps Git status in project repositories, but skips its expensive
# home-directory scan. The config updates automatically when changing dirs.
_starship_config = $HOME + '/.config/starship/starship.toml'
_starship_home_config = $HOME + '/.config/starship/home.toml'


def refresh_starship_config(directory=None):
    current_dir = Path(directory or os.getcwd()).resolve()
    home_dir = Path(os.path.expanduser("~")).resolve()
    XSH.env["STARSHIP_CONFIG"] = _starship_home_config if current_dir == home_dir else _starship_config


@events.on_chdir
def _refresh_starship_config_on_chdir(olddir, newdir):
    refresh_starship_config(newdir)


refresh_starship_config()

# ───────────────────────────────
# Directory helper
def smart_cd_alias(args):
    result = subprocess.run(["smart_cd"] + list(args), text=True, capture_output=True)
    newdir = result.stdout.strip()
    if newdir and os.path.isdir(newdir):
        os.chdir(newdir)
        refresh_uv_workspace_imports(newdir)
    else:
        print(f"No matching directory for {args!r}")

aliases['cd'] = smart_cd_alias

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


bun_global_bin = os.path.expanduser("~/.bun/bin")
if bun_global_bin not in $PATH:
    $PATH.insert(0, bun_global_bin)

# XONSH WEBCONFIG END

