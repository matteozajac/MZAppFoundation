#!/usr/bin/env python3
"""Read-only release check: latest stable provider SDKs and documented exceptions."""
import argparse
import json
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parents[1]
PROVIDERS = {
    'kean/Pulse': ('5.2.1', {'5.2.3': 'PulseUI glassEffect is unavailable on visionOS; retain 5.2.1 until the cross-platform build passes.'}),
    'getsentry/sentry-cocoa': ('9.30.2', {}),
    'RevenueCat/purchases-ios': ('5.96.0', {}),
    'firebase/firebase-ios-sdk': ('13.0.1', {}),
}


def check(manifest, releases):
    result = []
    for repository, (expected, exceptions) in PROVIDERS.items():
        match = re.search(r'github\.com/' + re.escape(repository) + r'(?:\.git)?", exact: "([^"]+)"', manifest)
        pinned = match.group(1) if match else None
        latest = releases[repository]['tag_name'].removeprefix('v')
        exception = exceptions.get(latest) if pinned == expected and pinned != latest else None
        result.append({'repository': repository, 'pinned': pinned, 'latest': latest,
                       'accepted': pinned == latest or exception is not None, 'exception': exception})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Exit nonzero for unacknowledged version drift')
    args = parser.parse_args()
    releases = {}
    for repository in PROVIDERS:
        completed = subprocess.run(['gh', 'api', f'repos/{repository}/releases/latest'],
                                   check=True, capture_output=True, text=True)
        releases[repository] = json.loads(completed.stdout)
    results = check((REPO / 'Package.swift').read_text(), releases)
    print(json.dumps(results, indent=2))
    return int(args.check and not all(item['accepted'] for item in results))


if __name__ == '__main__':
    raise SystemExit(main())
