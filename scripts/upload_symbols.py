#!/usr/bin/env python3
"""Upload only a device archive's matching dSYMs; secrets come from CI environment."""
import json
import os
from pathlib import Path
import re
import plistlib
import subprocess
import sys
import urllib.parse
import urllib.request


def run(args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def uuids(path):
    return {m.lower() for m in re.findall(r'UUID: ([0-9A-Fa-f-]+)', run(['dwarfdump', '--uuid', str(path)]))}


def main():
    env = os.environ
    if env.get('PLATFORM_NAME') not in ('iphoneos', 'xros') or env.get('CONFIGURATION', '').lower() == 'debug' or env.get('ACTION') != 'install':
        print('Sentry symbols skipped: not a device archive'); return
    for key in ['SENTRY_AUTH_TOKEN', 'SENTRY_ORG', 'SENTRY_PROJECT', 'SENTRY_CLI_VERSION', 'DWARF_DSYM_FOLDER_PATH', 'DWARF_DSYM_FILE_NAME', 'TARGET_BUILD_DIR', 'EXECUTABLE_PATH', 'PRODUCT_BUNDLE_IDENTIFIER', 'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION']:
        if not env.get(key): raise RuntimeError(f'Missing {key}')
    version = run(['sentry-cli', '--version']).strip().split()[-1]
    if version != env['SENTRY_CLI_VERSION']: raise RuntimeError('Sentry CLI version does not match configured pin')
    executable = Path(env['TARGET_BUILD_DIR']) / env['EXECUTABLE_PATH']
    dsym = Path(env['DWARF_DSYM_FOLDER_PATH']) / env['DWARF_DSYM_FILE_NAME']
    bundle_info = plistlib.loads((executable.parent / 'Info.plist').read_bytes())
    for plist_key, env_key in [('CFBundleIdentifier', 'PRODUCT_BUNDLE_IDENTIFIER'),
                               ('CFBundleShortVersionString', 'MARKETING_VERSION'), ('CFBundleVersion', 'CURRENT_PROJECT_VERSION')]:
        if str(bundle_info.get(plist_key)) != env[env_key]: raise RuntimeError('Built bundle release identity mismatch')
    expected_platform = 'iPhoneOS' if env['PLATFORM_NAME'] == 'iphoneos' else 'XROS'
    if expected_platform not in bundle_info.get('CFBundleSupportedPlatforms', []): raise RuntimeError('Built bundle platform mismatch')
    executable_ids = uuids(executable)
    if not executable_ids or executable_ids != uuids(dsym): raise RuntimeError('Executable and dSYM UUID mismatch')
    base = env.get('SENTRY_URL', 'https://sentry.io').rstrip('/')
    if not base.startswith('https://'): raise RuntimeError('SENTRY_URL requires HTTPS')
    org, project = (urllib.parse.quote(env[key], safe='') for key in ['SENTRY_ORG', 'SENTRY_PROJECT'])
    def get(path):
        request = urllib.request.Request(base + path, headers={'Authorization': 'Bearer ' + env['SENTRY_AUTH_TOKEN']})
        with urllib.request.urlopen(request, timeout=30) as response: return json.load(response)
    identity = get(f'/api/0/projects/{org}/{project}/')
    if identity['slug'] != env['SENTRY_PROJECT'] or identity['organization']['slug'] != env['SENTRY_ORG']:
        raise RuntimeError('Sentry project identity mismatch')
    subprocess.run(['sentry-cli', 'debug-files', 'upload', '--wait', str(dsym)], check=True)
    for uuid in executable_ids:
        files = get(f'/api/0/projects/{org}/{project}/files/dsyms/?uuid={uuid}')
        if not any(str(item.get('uuid', '')).lower() == uuid for item in files):
            raise RuntimeError(f'Sentry did not return uploaded UUID {uuid}')
    release = f"{env['PRODUCT_BUNDLE_IDENTIFIER']}@{env['MARKETING_VERSION']}+{env['CURRENT_PROJECT_VERSION']}"
    print(json.dumps({'release': release, 'verified_dsym_uuids': sorted(executable_ids)}))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(f'Symbol verification failed: {error}', file=sys.stderr); sys.exit(1)
