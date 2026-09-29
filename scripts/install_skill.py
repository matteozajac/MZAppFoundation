#!/usr/bin/env python3
"""Install the repo-backed setup, logging and bug-report skills globally without copying its source."""
import json
import os
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[1]
home = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
revision = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip() or 'uncommitted'
for name in ('mz-app-foundation-setup', 'app-logging', 'app-bug-report'):
    source = repo / 'skills' / name
    destination = home / 'skills' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() and destination.resolve() == source:
        pass
    elif destination.exists() or destination.is_symlink():
        raise SystemExit(f'Refusing to replace unrelated existing skill at {destination}')
    else:
        destination.symlink_to(source, target_is_directory=True)
    record = home / 'skill-installations' / (name + '.json')
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(json.dumps({'repository': str(repo), 'revision_at_install': revision, 'source': str(source)}, indent=2) + '\n')
    print(f'Installed {destination} -> {source} ({revision})')
