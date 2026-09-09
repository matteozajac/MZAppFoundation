#!/usr/bin/env python3
"""Inspect a built .app for forbidden local SDKs and required Pulse symbols."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--local', action='store_true')
args = parser.parse_args()
info = plistlib.loads((args.app / 'Info.plist').read_bytes())
executables = [args.app / info['CFBundleExecutable']] + list(args.app.glob('*.debug.dylib'))
text = '\n'.join(subprocess.run(['nm', '-a', str(path)], check=True, capture_output=True, text=True).stdout for path in executables)
files = '\n'.join(str(p.relative_to(args.app)) for p in args.app.rglob('*'))
forbidden = sorted(set(re.findall(r'RevenueCat|Sentry|FirebaseAnalytics|GoogleAppMeasurement|FIRAnalytics|APMAnalytics', text + '\n' + files)))
pulse = bool(re.search(r'Pulse(?:UI)?', text))
result = {'app': str(args.app), 'local': args.local, 'forbidden_local_sdk_matches': forbidden, 'pulse_symbols_present': pulse}
print(json.dumps(result, indent=2))
if not pulse or (args.local and forbidden): raise SystemExit(1)
