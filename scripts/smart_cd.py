#!/usr/bin/env python3
from pathlib import Path
from plumbum import local, ProcessExecutionError
import os, sys

def smart_cd(args):
    target = args[0] if args else None
    cwd = Path.cwd()

    # Default no-arg behavior: jump to git root or home
    if not target:
        try:
            git_root = Path(local["git"]("rev-parse", "--show-toplevel").strip())
            if cwd != git_root:
                return git_root
        except ProcessExecutionError:
            pass
        return Path.home()

    # If it's a direct path
    tpath = Path(target).expanduser()
    if tpath.is_dir() or target in {".", ".."}:
        return tpath.resolve()

    # Otherwise try prefix match with fd
    try:
        matches = local["fd"]("--max-depth", "1", "-t", "d", f"^{target}", ".").splitlines()
        if len(matches) == 1:
            return Path(matches[0]).resolve()
    except ProcessExecutionError:
        pass

    # Fallback to zoxide
    try:
        path = Path(local["zoxide"]("query", target).strip())
        if path.is_dir():
            return path
    except ProcessExecutionError:
        pass

    return cwd


if __name__ == "__main__":
    newdir = smart_cd(sys.argv[1:])
    if newdir:
        os.chdir(newdir)
        print(str(newdir))
