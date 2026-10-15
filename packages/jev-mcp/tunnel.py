"""Local Jev tunnel provisioning. Never reads or copies runtime API key contents."""
import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def write_private(path, value):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.jev-')
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(value)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def root():
    p = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))/'tunnel-client'
    p.mkdir(mode=0o700, parents=True, exist_ok=True)
    if p.is_symlink() or p.stat().st_uid != os.getuid():
        raise ValueError('Unsafe tunnel configuration directory')
    return p


def prepare(args):
    p = root()
    meta = json.loads((p/'jev.json').read_text())
    tunnel_id = meta['tunnel_id']
    if not re.fullmatch(r'tunnel_[A-Za-z0-9_-]+', tunnel_id):
        raise ValueError('Invalid tunnel ID')
    if (p/'buildbuddy.yaml').exists():
        bb = json.loads((p/'buildbuddy.yaml').read_text())
        if bb['control_plane']['tunnel_id'] == tunnel_id:
            raise ValueError('Jev must have its own tunnel ID')
    key = Path(meta['runtime_key_file'])
    if not key.is_absolute() or not key.is_file() or key.stat().st_uid != os.getuid() or key.stat().st_mode & 0o077:
        raise ValueError('Runtime key file must be owner-private')
    config = {'config_version': 1,
              'control_plane': {'base_url': 'https://api.openai.com', 'tunnel_id': tunnel_id, 'api_key': 'file:'+str(key)},
              'mcp': {'commands': [{'channel': 'main', 'command': args.mcp_command}], 'stdio_send_initialized_notification': True},
              'health': {'listen_addr': '127.0.0.1:0', 'url_file': str(p/'jev-health-url')},
              'admin_ui': {'open_browser': False}, 'log': {'level': 'info', 'format': 'json'}}
    write_private(p/'jev.yaml', json.dumps(config, indent=2)+'\n')
    return p, tunnel_id


def run(args):
    os.umask(0o077)
    p = root()
    if args.action == 'configure':
        if (p/'jev.json').exists():
            raise ValueError('Jev configuration exists; preserve it')
        key = args.runtime_key_file or str(p/'buildbuddy-secrets/openai-runtime-key')
        write_private(p/'jev.json', json.dumps({'tunnel_id': args.tunnel_id, 'runtime_key_file': key})+'\n')
        try:
            prepare(args)
        except Exception:
            (p/'jev.json').unlink()
            raise
        print('Jev profile configured; enable jev-tunnel.service to start it.')
    elif args.action in ('run', 'doctor'):
        p, tunnel_id = prepare(args)
        if args.action == 'run':
            runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
            lock = os.open(runtime/('jev-'+tunnel_id+'.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('A Jev client already owns this tunnel ID') from None
            os.set_inheritable(lock, True)
            (p/'jev-health-url').unlink(missing_ok=True)
        # Prevent inherited CLI configuration or credential variables overriding the profile.
        env = {k: v for k, v in os.environ.items() if not k.startswith(('CONTROL_PLANE_', 'MCP_', 'TUNNEL_CLIENT_', 'HEALTH_', 'CLOUDFLARED_')) and k not in ('OPENAI_API_KEY', 'OPENAI_ADMIN_KEY', 'JEV_KEY', 'TYPESAFE_API_KEY', 'ALLOW_REMOTE_UI', 'OPEN_WEB_UI')}
        os.execve(args.tunnel_client, [args.tunnel_client, args.action, '--profile-file', str(p/'jev.yaml'), '--control-plane.max-inflight', '4'], env)
    elif args.action == 'health':
        result = subprocess.run([args.tunnel_client, 'health', '--url-file', str(p/'jev-health-url'), '--require-control-plane-poll'], capture_output=True, timeout=15)
        if result.returncode:
            print('Jev tunnel health failed; restarting its service.', file=sys.stderr)
            subprocess.run([args.systemctl, '--user', 'try-restart', 'jev-tunnel.service'], check=True, timeout=15)
            raise ValueError('Jev tunnel is not ready')
        print('Jev tunnel health and control-plane polling are ready.')
    elif args.action == 'install':
        unit_root = Path.home()/'.config/systemd/user'
        unit_root.mkdir(parents=True, exist_ok=True)
        for name in ('jev-tunnel.service', 'jev-tunnel-health.service', 'jev-tunnel-health.timer'):
            target = unit_root/name
            if target.exists() and not target.is_symlink():
                raise ValueError('Existing unmanaged Jev service file; refusing overwrite')
            target.unlink(missing_ok=True)
            target.symlink_to(Path(args.unit_dir)/name)
        subprocess.run([args.systemctl, '--user', 'daemon-reload'], check=True)
        subprocess.run([args.systemctl, '--user', 'enable', '--now', 'jev-tunnel.service', 'jev-tunnel-health.timer'], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tunnel-client', required=True)
    p.add_argument('--mcp-command', required=True)
    p.add_argument('--systemctl', required=True)
    p.add_argument('--unit-dir', required=True)
    subs = p.add_subparsers(dest='action', required=True)
    c = subs.add_parser('configure')
    c.add_argument('--tunnel-id', required=True)
    c.add_argument('--runtime-key-file')
    for name in ('run', 'doctor', 'health', 'install'):
        subs.add_parser(name)
    try:
        run(p.parse_args())
    except Exception:
        # No traceback, subprocess stderr, provider content, or secret file contents.
        sys.stderr.write('Jev tunnel operation failed; check configuration, ownership, and service status.\n')
        raise SystemExit(1) from None


if __name__ == '__main__':
    main()
