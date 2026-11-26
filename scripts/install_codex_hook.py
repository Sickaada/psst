#!/usr/bin/env python3
"""Register the Psst Stop handler alongside existing local Codex hooks."""
import argparse
import json
import os
from pathlib import Path
import shlex
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path, help='Path to the installed Psst.app')
parser.add_argument('--codex-dir', type=Path, default=Path(os.environ.get('CODEX_HOME', Path.home()/'.codex')))
args = parser.parse_args()
executable = args.app.resolve()/'Contents/MacOS/AlienPing'
if not os.access(executable, os.X_OK):
    parser.error('The supplied app does not contain the Psst executable.')
path = args.codex_dir/'hooks.json'
path.parent.mkdir(mode=0o700, exist_ok=True, parents=True)
original = path.read_bytes() if path.exists() else None
config = json.loads(original) if original else {}
groups = config.setdefault('hooks', {}).setdefault('Stop', [])
command = shlex.quote(str(executable)) + ' --codex-stop'
if any(h.get('command') == command for g in groups for h in g.get('hooks', [])):
    print('Psst hook already registered.')
else:
    groups.append({'hooks':[{'type':'command','command':command,'timeout':5,'statusMessage':'Save local update in Psst'}]})
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        temp = Path(f.name)
        f.write((json.dumps(config, indent=2, ensure_ascii=False)+'\n').encode())
    try:
        if (path.read_bytes() if path.exists() else None) != original:
            raise SystemExit('Codex hook settings changed concurrently; rerun the installer.')
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    print('Registered Psst. Review the new Stop command in Codex Settings → Hooks.')
