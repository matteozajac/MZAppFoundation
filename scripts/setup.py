#!/usr/bin/env python3
"""Inspect, apply, and verify repeatable app integration. Remote provisioning belongs to the skill."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
VENDOR_PRODUCTS = {'RevenueCat', 'RevenueCatUI', 'Sentry', 'Sentry-Dynamic', 'FirebaseAnalytics', 'FirebaseAnalyticsCore', 'FirebaseCore', 'Pulse', 'PulseUI', 'PulseProxy'}
SAFETY = {'FirebaseAutomaticScreenReportingEnabled': False, 'FIREBASE_ANALYTICS_COLLECTION_ENABLED': False,
          'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED': False, 'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS': False}


DEFAULT_MICROPHONE = 'Record a voice message when you choose to describe a bug.'

def reporting_enabled(config):
    return config.get('bug_reporting', False) and config['platform'] == 'iOS'

def microphone_description(config):
    return config.get('microphone_usage_description', DEFAULT_MICROPHONE).strip()

def within(root, relative):
    root = root.resolve()
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f'Path escapes app root: {relative}')
    return path


def load(root, config_path):
    config = json.loads(config_path.read_text())
    for key in ['project', 'project_type', 'target', 'bundle_id', 'url_scheme', 'platform']:
        if not config.get(key):
            raise ValueError(f'Missing {key}')
    if config['project_type'] not in ['xcodegen', 'native'] or config['platform'] not in ['iOS', 'visionOS']:
        raise ValueError('Unsupported project_type or platform')
    for key in ['target', 'bundle_id', 'url_scheme']:
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]*', config[key]):
            raise ValueError(f'Invalid {key}')
    within(root, config['project'])
    # Administrative secrets must never enter a source-generation manifest.
    for key in config.get('providers', {}):
        if key not in ['revenuecat_public_key', 'sentry_dsn', 'google_service_info', 'sentry_org', 'sentry_project']:
            raise ValueError(f'Unsupported provider setting: {key}; administrative tokens belong in environment/CI')
    public_key = config.get('providers', {}).get('revenuecat_public_key')
    if public_key and not public_key.startswith('appl_'):
        raise ValueError('RevenueCat configuration requires an Apple public SDK key')
    if 'package_path' not in config and not re.fullmatch(r'\d+\.\d+\.\d+', config.get('package_version', '0.3.1')):
        raise ValueError('package_version must be an exact semantic version')
    if not isinstance(config.get('bug_reporting', False), bool):
        raise ValueError('bug_reporting must be a boolean')
    if config.get('bug_reporting'):
        if 'package_path' not in config and tuple(map(int, config.get('package_version', '0.3.1').split('.'))) < (0, 3, 0):
            raise ValueError('Bug reporting requires MZAppFoundation 0.3.0 or later')
        if config['platform'] != 'iOS':
            raise ValueError('Bug reporting in 0.3.0 requires iOS; keep the standard console on other platforms')
        if not isinstance(config.get('microphone_usage_description', DEFAULT_MICROPHONE), str) or not microphone_description(config):
            raise ValueError('microphone_usage_description must be nonempty')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', config.get('report_archive_prefix', 'bug-report')):
            raise ValueError('report_archive_prefix must contain only letters, digits, hyphens or underscores')
    return config


def inventory(root, config):
    files = sorted(p for p in root.rglob('*.swift') if not any(x.startswith('.') or x in ['DerivedData', 'output'] for x in p.relative_to(root).parts))
    imports = []
    products = []
    for path in files:
        source = path.read_text(errors='replace')
        modules = re.findall(r'^\s*(?:@preconcurrency )?import (RevenueCat\w*|Sentry\w*|Firebase\w*|Pulse\w*)', source, re.M)
        if modules:
            imports.append({'file': str(path.relative_to(root)), 'modules': sorted(set(modules))})
        if re.search(r'productIdentifier|productID|entitlementIdentifier|offeringIdentifier', source):
            products.append(str(path.relative_to(root)))
    return {'target': config['target'], 'vendor_imports': imports, 'product_definition_candidates': products,
            'catalog': 'defined' if config.get('products') else 'absent; do not create an offering',
            'provider_configuration': sorted(config.get('providers', {})),
            'remote_provisioning': 'Use skill references/provisioning.md; no remote writes in this script'}


def swift_literal(value):
    return json.dumps(value, ensure_ascii=False)


def bootstrap(config):
    providers = config.get('providers', {})
    events = config.get('events', {})
    event_literal = '[' + ', '.join(swift_literal(k) + ': Set([' + ', '.join(swift_literal(x) for x in sorted(v)) + '])' for k, v in sorted(events.items())) + ']' if events else '[:]'
    key = swift_literal(providers['revenuecat_public_key']) if providers.get('revenuecat_public_key') else 'nil'
    dsn = swift_literal(providers['sentry_dsn']) if providers.get('sentry_dsn') else 'nil'
    firebase_path = 'bundle.path(forResource: "GoogleService-Info", ofType: "plist")' if providers.get('google_service_info') else 'nil'
    analytics = str(config.get('analytics_enabled', True)).lower()
    diagnostics = str(config.get('diagnostics_enabled', True)).lower()
    reporting = ''
    if reporting_enabled(config):
        prefix = swift_literal(config.get('report_archive_prefix', 'bug-report'))
        reporting = f'    #if os(iOS)\n    static let reporting = DeveloperReporting(archivePrefix: {prefix})\n    #endif\n'
    return f'''// Generated by mz-app-foundation-setup. App-specific event definitions remain in config.json.
import Foundation
import MZAppFoundation
import MZAppFoundationLocal
#if !MZ_LOCAL && !targetEnvironment(simulator)
import MZAppFoundationLive
#if os(iOS)
import MZAppFoundationFirebase
#endif
#endif

@MainActor enum MZBootstrap {{
{reporting}    static let services: AppServices = make()
    private static func make() -> AppServices {{
        let environment: AppEnvironment
        #if MZ_LOCAL || DEBUG || targetEnvironment(simulator)
        environment = .local
        #elseif MZ_INTERNAL
        environment = .internalTesting
        #else
        environment = .production
        #endif
        let bundle = Bundle.main
        let configuration = AppConfiguration(
            bundleIdentifier: bundle.bundleIdentifier ?? {swift_literal(config['bundle_id'])},
            urlScheme: {swift_literal(config['url_scheme'])}, environment: environment,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            preferences: .init(analytics: {analytics}, diagnostics: {diagnostics}))
        let schema = TelemetrySchema(events: {event_literal})
        #if MZ_LOCAL || targetEnvironment(simulator)
        return LocalServices.make(configuration: configuration, schema: schema)
        #else
        do {{
            let vendors = LiveConfiguration(revenueCatPublicKey: {key}, sentryDSN: {dsn})
            #if os(iOS)
            return try FirebaseServices.make(configuration: configuration, vendors: vendors, schema: schema,
                googleServiceInfoPath: {firebase_path})
            #else
            return try LiveServices.make(configuration: configuration, vendors: vendors, schema: schema)
            #endif
        }} catch {{
            let fallback = LocalServices.make(configuration: configuration, schema: schema, purchases: UnavailablePurchases())
            fallback.logger.error("Bootstrap configuration failed", error: error, category: "setup")
            return fallback
        }}
        #endif
    }}
}}
'''


def write(path, content):
    data = content.encode() if isinstance(content, str) else content
    if path.exists() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def configure_plist(path, config):
    values = plistlib.loads(path.read_bytes()) if path.exists() else {}
    values.update(SAFETY)
    if reporting_enabled(config): values.setdefault('NSMicrophoneUsageDescription', microphone_description(config))
    entries = values.setdefault('CFBundleURLTypes', [])
    if not any(config['url_scheme'] in item.get('CFBundleURLSchemes', []) for item in entries):
        entries.append({'CFBundleURLSchemes': [config['url_scheme']]})
    write(path, plistlib.dumps(values, sort_keys=True))


def mutate_xcodegen(root, config):
    import yaml
    path = within(root, config['project'])
    spec = yaml.safe_load(path.read_text())
    target = spec['targets'][config['target']]
    local_name = config['target'] + 'Local'
    spec.setdefault('configs', {'Debug': 'debug', 'Release': 'release'}).setdefault('Internal', 'release')
    package = {'path': config['package_path']} if config.get('package_path') else {
        'url': 'git@github.com:matteozajac/MZAppFoundation.git', 'version': config.get('package_version', '0.3.1')}
    spec.setdefault('packages', {})['MZAppFoundation'] = package
    live_product = 'MZAppFoundationFirebase' if config['platform'] == 'iOS' else 'MZAppFoundationLive'
    base_dependencies = [d for d in target.get('dependencies', []) if d.get('package') != 'MZAppFoundation' and d.get('product', d.get('package')) not in VENDOR_PRODUCTS]
    source = '.mzappfoundation/Generated'
    sources = target.setdefault('sources', [])
    if isinstance(sources, str):
        sources = [sources]; target['sources'] = sources
    if source not in [s if isinstance(s, str) else s.get('path') for s in sources]:
        sources.append({'path': source, 'excludes': ['upload_symbols.py', '*-Info.plist']})
    info = target.setdefault('info', {'path': f'.mzappfoundation/Generated/{config["target"]}-Info.plist'})
    props = info.setdefault('properties', {})
    props.update(SAFETY)
    if reporting_enabled(config):
        # Preserve purpose text already supplied by the app's actual plist.
        existing = {}
        if info.get('path') and within(root, info['path']).exists():
            existing = plistlib.loads(within(root, info['path']).read_bytes())
        purpose = existing.get('NSMicrophoneUsageDescription')
        purpose = purpose or target.get('settings', {}).get('base', {}).get('INFOPLIST_KEY_NSMicrophoneUsageDescription')
        purpose = purpose or spec.get('settings', {}).get('base', {}).get('INFOPLIST_KEY_NSMicrophoneUsageDescription')
        props.setdefault('NSMicrophoneUsageDescription', purpose or microphone_description(config))
    if config['platform'] == 'visionOS':
        scene = props.setdefault('UIApplicationSceneManifest', {})
        scene['UIApplicationSupportsMultipleScenes'] = True
        scene.setdefault('UIApplicationPreferredDefaultSceneSessionRole', 'UIWindowSceneSessionRoleApplication')
    urls = props.setdefault('CFBundleURLTypes', [])
    if not any(config['url_scheme'] in item.get('CFBundleURLSchemes', []) for item in urls):
        urls.append({'CFBundleURLSchemes': [config['url_scheme']]})
    base = target.setdefault('settings', {}).setdefault('base', {})
    base['PRODUCT_BUNDLE_IDENTIFIER'] = config['bundle_id']
    configs = target['settings'].setdefault('configs', {})
    flags = configs.setdefault('Internal', {}).get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '$(inherited)')
    if 'MZ_INTERNAL' not in flags: flags += ' MZ_INTERNAL'
    configs['Internal']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = flags
    local = copy.deepcopy(target)
    local['dependencies'] = base_dependencies + [{'package': 'MZAppFoundation', 'product': 'MZAppFoundation'}]
    local['settings']['base'].update({'SUPPORTED_PLATFORMS': 'iphonesimulator' if config['platform'] == 'iOS' else 'xrsimulator',
                                     'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) MZ_LOCAL'})
    local.setdefault('postBuildScripts', [])[:] = [s for s in local.get('postBuildScripts', []) if s.get('name') != 'MZ Sentry Symbols']
    target['dependencies'] = base_dependencies + [{'package': 'MZAppFoundation', 'product': live_product}]
    target['settings']['base']['SUPPORTED_PLATFORMS'] = 'iphoneos' if config['platform'] == 'iOS' else 'xros'
    target.setdefault('postBuildScripts', [])[:] = [s for s in target.get('postBuildScripts', []) if s.get('name') != 'MZ Sentry Symbols']
    if config.get('providers', {}).get('sentry_dsn'):
        target['postBuildScripts'].append({'name': 'MZ Sentry Symbols', 'script': 'python3 "$SRCROOT/.mzappfoundation/Generated/upload_symbols.py"', 'basedOnDependencyAnalysis': False})
        target['settings']['base']['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    spec['targets'][local_name] = local
    schemes = spec.setdefault('schemes', {})
    schemes[local_name] = {'build': {'targets': {local_name: 'all'}}, 'run': {'config': 'Debug'}}
    schemes.setdefault(config['target'], {'build': {'targets': {config['target']: 'all'}}, 'run': {'config': 'Internal'}})
    write(path, yaml.safe_dump(spec, sort_keys=False))
    subprocess.run(['xcodegen', 'generate', '--spec', str(path)], cwd=root, check=True)


def apply(root, config):
    generated = root / '.mzappfoundation/Generated'
    write(generated / 'MZBootstrap.swift', bootstrap(config))
    write(generated / 'upload_symbols.py', (REPO / 'scripts/upload_symbols.py').read_bytes())
    providers = config.get('providers', {})
    if providers.get('google_service_info'):
        source = within(root, providers['google_service_info'])
        info = plistlib.loads(source.read_bytes())
        if info.get('BUNDLE_ID') != config['bundle_id']:
            raise ValueError('Firebase configuration bundle ID mismatch')
        write(generated / 'GoogleService-Info.plist', source.read_bytes())
    elif (generated / 'GoogleService-Info.plist').exists():
        (generated / 'GoogleService-Info.plist').unlink()
    if config['project_type'] == 'xcodegen':
        mutate_xcodegen(root, config)
    else:
        subprocess.run([os.environ.get('RUBY', 'ruby'), str(REPO / 'scripts/configure_native.rb'), str(root), json.dumps(config)], check=True)
    report = {'configuration_sha256': hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
              'package_version': config.get('package_version', 'local'), 'local_wiring': 'applied',
              'entrypoint': 'Wire MZBootstrap.services and appDeveloperTools in app entrypoint; see integration.md',
              'remote_provisioning': 'not performed by this command'}
    write(root / '.mzappfoundation/state.json', json.dumps(report, indent=2) + '\n')
    return report


def verify(root, config):
    errors = []
    generated = root / '.mzappfoundation/Generated/MZBootstrap.swift'
    if not generated.exists() or generated.read_text() != bootstrap(config): errors.append('Generated bootstrap missing or stale')
    if config['project_type'] == 'xcodegen':
        import yaml
        project = yaml.safe_load(within(root, config['project']).read_text())
        for name, product in [(config['target'] + 'Local', 'MZAppFoundation'),
                              (config['target'], 'MZAppFoundationFirebase' if config['platform'] == 'iOS' else 'MZAppFoundationLive')]:
            target = project.get('targets', {}).get(name, {})
            if not any(d.get('package') == 'MZAppFoundation' and d.get('product') == product for d in target.get('dependencies', [])):
                errors.append(f'{name} is missing expected package product {product}')
            expected_platform = ('iphonesimulator' if name.endswith('Local') else 'iphoneos') if config['platform'] == 'iOS' else ('xrsimulator' if name.endswith('Local') else 'xros')
            if target.get('settings', {}).get('base', {}).get('SUPPORTED_PLATFORMS') != expected_platform:
                errors.append(f'{name} has incorrect supported platforms')
    if reporting_enabled(config):
        if config['project_type'] == 'xcodegen':
            for name in [config['target'], config['target'] + 'Local']:
                description = project.get('targets', {}).get(name, {}).get('info', {}).get('properties', {}).get('NSMicrophoneUsageDescription', '')
                if not isinstance(description, str) or not description.strip():
                    errors.append(f'{name} is missing NSMicrophoneUsageDescription')
        else:
            check = subprocess.run([os.environ.get('RUBY', 'ruby'), str(REPO / 'scripts/verify_microphone.rb'), str(root), json.dumps(config)], text=True, capture_output=True, check=True)
            errors.extend(json.loads(check.stdout))
    inventory_report = inventory(root, config)
    if inventory_report['vendor_imports']: errors.append('Direct vendor imports remain; migrate app-owned adapters before accepting local exclusion')
    app_sources = [p for p in root.rglob('*.swift') if '.mzappfoundation' not in p.parts and '.build' not in p.parts and 'DerivedData' not in p.parts]
    if not any('appDeveloperTools(' in p.read_text(errors='replace') for p in app_sources): errors.append('App entrypoint has no developer tools integration')
    if reporting_enabled(config) and not any(re.search(r'appDeveloperTools\([^)]*reporting\s*:', p.read_text(errors='replace'), re.S) for p in app_sources): errors.append('App entrypoint has no reporting-enabled developer tools integration')
    if config['platform'] == 'visionOS' and not any('DeveloperConsoleScene(' in p.read_text(errors='replace') for p in app_sources): errors.append('visionOS console scene is not registered')
    result = {'verified': not errors, 'errors': errors, 'build_verification': 'Run sample/app builds and audit_binary.py separately', **inventory_report}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['inspect', 'apply', 'verify'])
    parser.add_argument('--app-root', required=True, type=Path)
    parser.add_argument('--config', type=Path)
    args = parser.parse_args()
    root = args.app_root.resolve()
    config = load(root, args.config.resolve() if args.config else root / '.mzappfoundation/config.json')
    result = {'inspect': inventory, 'apply': apply, 'verify': verify}[args.mode](root, config)
    print(json.dumps(result, indent=2))
    if args.mode == 'verify' and not result['verified']: sys.exit(1)


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Setup failed: {error}', file=sys.stderr); sys.exit(1)
