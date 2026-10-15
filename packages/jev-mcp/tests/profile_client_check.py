"""Build-time regression: validate the generated profile with the pinned binary."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    key = root/'runtime-key'
    key.write_text('fake-regression-key')
    key.chmod(0o600)
    env = dict(os.environ, XDG_CONFIG_HOME=tmp)
    subprocess.run([sys.argv[1], 'configure', '--tunnel-id', 'tunnel_0123456789abcdef0123456789abcdef', '--runtime-key-file', str(key)], env=env, check=True, capture_output=True, timeout=10)
    profile = root/'tunnel-client/jev.yaml'
    r = subprocess.run([sys.argv[2], 'doctor', '--profile-file', str(profile), '--control-plane.max-inflight', '4'], env=env, capture_output=True, text=True, timeout=30)
    output = r.stdout + r.stderr
    # Doctor may reject the fake control-plane identity; profile decoding must pass.
    assert 'PASS '+str(profile) in output, 'Generated profile was not loaded'
    assert 'FAIL parse config' not in output, 'Pinned client rejected generated profile'
    assert 'unmarshal errors' not in output, 'Pinned client rejected a profile field'
    assert 'fake-regression-key' not in output, 'Diagnostic credential reflection'
    assert json.loads(profile.read_text())['mcp']['commands'][0]['channel'] == 'main'
    print('Generated stdio profile accepted by pinned tunnel-client; credential-safe diagnostics')
