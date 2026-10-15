import fcntl
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace

import pytest

spec = importlib.util.spec_from_file_location('jev_tunnel', Path(__file__).parents[1]/'tunnel.py')
tunnel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tunnel)


@pytest.fixture
def setup(tmp_path, monkeypatch):
    monkeypatch.setenv('XDG_CONFIG_HOME', str(tmp_path))
    monkeypatch.setenv('XDG_RUNTIME_DIR', str(tmp_path))
    key = tmp_path/'runtime-key'
    key.write_text('fake-runtime-secret')
    key.chmod(0o600)
    args = SimpleNamespace(action='configure', tunnel_id='tunnel_jevtest', runtime_key_file=str(key), mcp_command='/nix/store/fake/bin/jev-native-mcp', tunnel_client='/nix/store/fake/bin/tunnel-client')
    return tmp_path, key, args


def test_no_secret_copy_and_distinct_profile(setup):
    tmp_path, key, args = setup
    p = tunnel.root()
    bb = {'control_plane': {'tunnel_id': 'tunnel_buildbuddy'}}
    (p/'buildbuddy.yaml').write_text(json.dumps(bb))
    tunnel.run(args)
    profile = (p/'jev.yaml').read_text()
    assert 'fake-runtime-secret' not in profile + (p/'jev.json').read_text()
    assert json.loads(profile)['control_plane']['api_key'] == 'file:'+str(key)
    assert json.loads(profile)['mcp']['commands'][0]['channel'] == 'main'
    assert json.loads((p/'buildbuddy.yaml').read_text()) == bb
    assert (p/'jev.yaml').stat().st_mode & 0o777 == 0o600
    args.tunnel_id = 'tunnel_buildbuddy'
    (p/'jev.json').unlink()
    with pytest.raises(ValueError, match='own tunnel'):
        tunnel.run(args)
    assert not (p/'jev.json').exists()


def test_singleton_lock(setup):
    tmp_path, key, args = setup
    tunnel.run(args)
    lock = os.open(tmp_path/'jev-tunnel_jevtest.lock', os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.action = 'run'
        with pytest.raises(ValueError, match='already owns'):
            tunnel.run(args)
    finally:
        os.close(lock)


def test_reject_public_runtime_key(setup):
    tmp_path, key, args = setup
    key.chmod(0o644)
    with pytest.raises(ValueError, match='owner-private'):
        tunnel.run(args)
