#!/usr/bin/env python3
"""Inspect a built .app for actual forbidden local SDK linkage and Pulse code."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

SDK_MODULES = ('RevenueCat', 'Sentry', 'FirebaseAnalytics', 'FirebaseAnalyticsCore',
               'GoogleAppMeasurement')


def has_swift_module(symbols, module):
    # The module is the first length-prefixed component of the mangled symbol.
    # App-owned SentryEventPrivacyScrubber/PulseLogEngine names do not qualify.
    return bool(re.search(r'(?:^|\s)_?\$s' + str(len(module)) + re.escape(module)
                          + r'(?=[A-Za-z0-9_])', symbols, re.MULTILINE))


def sdk_evidence(symbols, paths):
    """Return linkage evidence without broad matches against application names."""
    evidence = {}
    for module in SDK_MODULES:
        reasons = []
        if has_swift_module(symbols, module):
            reasons.append('swift_module_symbol')
        if re.search(r'/' + re.escape(module) + r'\.build/', symbols):
            reasons.append('object_file_path')
        component = re.compile(
            r'^' + re.escape(module)
            + r'(?:\.framework|(?:_[A-Za-z0-9_]+)?\.bundle|_[A-Za-z0-9_]+_PackageProduct\.framework)?$'
        )
        if any(component.fullmatch(part) for path in paths for part in Path(path).parts):
            reasons.append('vendor_bundle_path')
        if reasons:
            evidence[module] = reasons

    for sdk, objective_c_class in [('Sentry', 'SentrySDK'),
                                    ('FirebaseAnalytics', 'FIRAnalytics'),
                                    ('GoogleAppMeasurement', 'APMAnalytics')]:
        # FIRAnalyticsConfiguration belongs to Firebase Core and is permitted.
        # Only the exact Analytics class, not its configuration helper, qualifies.
        class_symbol = (r'(?:^|\s)_OBJC_(?:META)?CLASS_\$_'
                        + objective_c_class + r'(?=$|\s)')
        method_symbol = r'[+-]\[' + objective_c_class + r'\s'
        if re.search(class_symbol, symbols, re.MULTILINE) or re.search(method_symbol, symbols):
            evidence.setdefault(sdk, []).append('objective_c_sdk_class')
    return evidence


def executable_paths(app):
    """Include embedded extensions/frameworks as well as Xcode's debug dylib."""
    bundles = [app]
    for suffix in ('*.appex', '*.app', '*.framework'):
        bundles.extend(app.rglob(suffix))
    executables = []
    for bundle in bundles:
        info_path = next((path for path in [bundle / 'Info.plist', bundle / 'Contents/Info.plist',
                         bundle / 'Resources/Info.plist', bundle / 'Versions/Current/Resources/Info.plist']
                          if path.is_file()), None)
        if info_path is None:
            continue
        info = plistlib.loads(info_path.read_bytes())
        binary_directory = bundle / 'Contents/MacOS' if info_path == bundle / 'Contents/Info.plist' else bundle
        if executable := info.get('CFBundleExecutable'):
            path = binary_directory / executable
            if path.is_file():
                executables.append(path)
        executables.extend(binary_directory.glob('*.debug.dylib'))
    return sorted(set(executables))


def audit(app, local=False):
    executables = executable_paths(app)
    if not executables:
        raise ValueError('No executable found in the application bundle')
    symbols = '\n'.join(subprocess.run(['nm', '-a', str(path)], check=True,
                                      capture_output=True, text=True).stdout
                        for path in executables)
    paths = [str(path.relative_to(app)) for path in app.rglob('*')]
    evidence = sdk_evidence(symbols, paths)
    pulse = any(has_swift_module(symbols, module) for module in ('Pulse', 'PulseUI'))
    return {'app': str(app), 'local': local,
            'inspected_executables': [str(path.relative_to(app)) for path in executables],
            'forbidden_local_sdk_matches': sorted(evidence),
            'sdk_linkage_evidence': evidence, 'pulse_symbols_present': pulse}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--local', action='store_true')
    args = parser.parse_args(argv)
    result = audit(args.app, local=args.local)
    print(json.dumps(result, indent=2))
    return int(not result['pulse_symbols_present']
               or (args.local and bool(result['forbidden_local_sdk_matches'])))


if __name__ == '__main__':
    raise SystemExit(main())
