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
import shlex
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
VENDOR_PRODUCTS = {'RevenueCat', 'RevenueCatUI', 'Sentry', 'Sentry-Dynamic', 'FirebaseAnalytics', 'FirebaseAnalyticsCore', 'FirebaseCore', 'Pulse', 'PulseUI', 'PulseProxy'}
SAFETY = {'FirebaseAutomaticScreenReportingEnabled': False, 'FIREBASE_ANALYTICS_COLLECTION_ENABLED': False,
          'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED': False, 'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS': False}


DEFAULT_MICROPHONE = 'Record a voice message when you choose to describe a bug.'

def developer_settings_supported(config):
    return 'package_path' in config or tuple(map(int, config.get('package_version', '0.6.2').split('.'))) >= (0, 5, 0)

def short_developer_links_supported(config):
    return 'package_path' in config or tuple(map(int, config.get('package_version', '0.6.2').split('.'))) >= (0, 5, 1)

def supported_platforms(config, local=False):
    return {'iOS': ('iphonesimulator', 'iphoneos'), 'visionOS': ('xrsimulator', 'xros'),
            'macOS': ('macosx', 'macosx')}[config['platform']][0 if local else 1]

def build_metadata_script(config):
    command = 'python3 "$SRCROOT/.mzappfoundation/Generated/generate_build_metadata.py" --app-root "$SRCROOT"'
    if config.get('package_path'):
        command += ' --foundation-root ' + shlex.quote(config['package_path'])
    else:
        command += ' --foundation-version ' + shlex.quote(config.get('package_version', '0.6.2'))
    return command + ' --channel "$CONFIGURATION" --stamp-build-time --output "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/MZFoundationBuildMetadata.plist"'

def provider_products(config):
    if not developer_settings_supported(config):
        return ['MZAppFoundationFirebase' if config['platform'] == 'iOS' else 'MZAppFoundationLive']
    providers = config.get('providers', {})
    products = ['MZAppFoundation']
    if providers.get('revenuecat_public_key'): products.append('MZAppFoundationRevenueCat')
    if providers.get('sentry_dsn'): products.append('MZAppFoundationSentry')
    if config['platform'] == 'iOS' and providers.get('google_service_info'): products.append('MZAppFoundationFirebaseAnalytics')
    return products

def independent_device_bootstrap(config):
    providers = config.get('providers', {})
    def optional(key): return swift_literal(providers[key]) if providers.get(key) else 'nil'
    source = ['        var inventory = FoundationDiagnostics()',
              '        var purchases: any PurchaseProviding = UnavailablePurchases()',
              '        var analytics: [any AnalyticsEngine] = []',
              '        var diagnostics: [any DiagnosticsEngine] = []',
              '        let remoteAllowed = RuntimeSafety.permitsRemote(environment: configuration.environment)']
    if any(providers.get(key) for key in ['revenuecat_public_key', 'revenuecat_project_name', 'revenuecat_project_id', 'revenuecat_app_id']):
        source.append(f'''        let revenueCatProject = ProviderProjectIdentity(name: {optional('revenuecat_project_name')}, projectID: {optional('revenuecat_project_id')}, appID: {optional('revenuecat_app_id')})''')
    if any(providers.get(key) for key in ['sentry_dsn', 'sentry_project', 'sentry_project_id', 'sentry_org']):
        source.append(f'''        let sentryProject = ProviderProjectIdentity(name: {optional('sentry_project')}, projectID: {optional('sentry_project_id')}, organization: {optional('sentry_org')})''')
    for provider, credential, module_type, diagnostic_api, identity, constructor in [
        ('revenueCat', 'revenuecat_public_key', 'RevenueCatPurchases', 'RevenueCatProvider', 'revenueCatProject', 'key'),
        ('sentry', 'sentry_dsn', 'SentryDiagnostics', 'SentryProvider', 'sentryProject', 'dsn')]:
        if providers.get(credential):
            variable = 'revenueCat' if provider == 'revenueCat' else 'sentry'
            assignment = 'purchases = adapter' if provider == 'revenueCat' else 'diagnostics.append(adapter)'
            argument = 'publicKey' if provider == 'revenueCat' else 'dsn'
            owned_argument = 'purchases' if provider == 'revenueCat' else 'engine'
            source.append(f'''        let {variable}Credential: String? = {optional(credential)}
        var {variable}Adapter: {module_type}?
        var {variable}Failed = false
        if remoteAllowed, let credential = {variable}Credential {{
            do {{
                let adapter = try {module_type}({constructor}: credential, configuration: configuration)
                {variable}Adapter = adapter
                {assignment}
                inventory = inventory.recordingStartup([.init(provider: .{provider}, stage: .validation, status: .succeeded,
                    code: "{variable}.adapter_created", message: "The adapter accepted the supplied configuration.")])
            }} catch {{
                {variable}Failed = true
                inventory.bootstrapIssue = "A provider failed to start. Review Startup history."
                inventory = inventory.recordingStartup([.init(provider: .{provider}, stage: .initialization, status: .failed,
                    code: "{variable}.startup_failed", message: "The provider adapter could not be created.",
                    correction: "Check this app's provider configuration and whether another composition already owns the SDK.")])
            }}
        }} else {{
            inventory = inventory.recordingStartup([.init(provider: .{provider}, stage: .runtimeSafety, status: .skipped,
                code: "{variable}.runtime_blocked", message: "Remote provider startup was blocked by runtime safety.")])
        }}
        inventory = {diagnostic_api}.diagnostics({argument}: {variable}Credential, project: {identity},
            base: inventory, bootstrapFailure: {variable}Failed, {owned_argument}: {variable}Adapter)''')
        elif (provider == 'revenueCat' and any(providers.get(key) for key in ['revenuecat_project_name', 'revenuecat_project_id', 'revenuecat_app_id'])) or \
                (provider == 'sentry' and any(providers.get(key) for key in ['sentry_project', 'sentry_project_id', 'sentry_org'])):
            source.append(f'''        inventory = inventory.replacing(.{provider}) {{ _ in
            ProviderSnapshot(provider: .{provider}, details: {identity}.details,
                explanation: "Project labels were supplied, but this composition does not link the provider adapter.",
                identityAudit: .init(supplied: {identity}, ownership: .notInitialized))
        }}''')
    if config['platform'] == 'iOS' and providers.get('google_service_info'):
        source.append(f'''        #if os(iOS)
        let firebasePath = bundle.path(forResource: "GoogleService-Info", ofType: "plist")
        var firebaseAdapter: FirebaseAnalyticsEngine?
        var firebaseFailed = false
        if !remoteAllowed {{
            inventory = inventory.recordingStartup([.init(provider: .firebase, stage: .runtimeSafety, status: .skipped,
                code: "firebase.runtime_blocked", message: "Firebase startup was blocked by runtime safety.")])
        }} else if let firebasePath {{
            do {{
                let adapter = try FirebaseAnalyticsEngine(configuration: configuration, path: firebasePath)
                firebaseAdapter = adapter
                analytics.append(adapter)
                inventory = inventory.recordingStartup([.init(provider: .firebase, stage: .validation, status: .succeeded,
                    code: "firebase.adapter_created", message: "The adapter accepted the supplied Firebase configuration.")])
            }} catch {{
                firebaseFailed = true
                inventory.bootstrapIssue = "A provider failed to start. Review Startup history."
                inventory = inventory.recordingStartup([.init(provider: .firebase, stage: .initialization, status: .failed,
                    code: "firebase.startup_failed", message: "The Firebase adapter could not be created.",
                    correction: "Check GoogleService-Info.plist, its bundle ID and existing Firebase SDK ownership.")])
            }}
        }} else {{
            inventory.bootstrapIssue = "The expected Firebase configuration file is missing from this app bundle."
            inventory = inventory.recordingStartup([.init(provider: .firebase, stage: .validation, status: .failed,
                code: "firebase.file_missing", message: "GoogleService-Info.plist was not found in the app bundle.",
                correction: "Add this app's GoogleService-Info.plist to the application target's resources.")])
        }}
        if let firebaseAdapter {{
            inventory = FirebaseProvider.diagnostics(googleServiceInfoPath: firebasePath,
                projectName: {optional('firebase_project_name')}, engine: firebaseAdapter, base: inventory)
        }} else {{
            inventory = FirebaseProvider.diagnostics(googleServiceInfoPath: firebasePath,
                bootstrapFailure: firebaseFailed, projectName: {optional('firebase_project_name')}, base: inventory)
        }}
        #endif''')
    elif providers.get('firebase_project_name'):
        source.append(f'''        inventory = inventory.replacing(.firebase) {{ context in
            let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: context.configuration.bundleIdentifier,
                path: bundle.path(forResource: "GoogleService-Info", ofType: "plist"))
            return ProviderSnapshot(provider: .firebase, configuration: file.state,
                details: [.init("projectName", label: "Project name", value: {optional('firebase_project_name')})] + file.details,
                explanation: file.explanation + " The Firebase adapter is not linked to this composition.")
        }}''')
    source.append('''        return LocalServices.make(configuration: configuration, schema: schema, purchases: purchases,
            foundationDiagnostics: inventory, additionalAnalytics: analytics, additionalDiagnostics: diagnostics)''')
    return '\n'.join(source)

def url_schemes(config):
    schemes = [config['url_scheme']]
    if developer_settings_supported(config) and not short_developer_links_supported(config) and 'mzappfoundation' not in schemes:
        schemes.append('mzappfoundation')
    return schemes

def remove_shared_scheme(entries, config):
    if not short_developer_links_supported(config): return
    for entry in entries:
        entry['CFBundleURLSchemes'] = [scheme for scheme in entry.get('CFBundleURLSchemes', []) if scheme.lower() != 'mzappfoundation']
    entries[:] = [entry for entry in entries if entry.get('CFBundleURLSchemes')]

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
    if config['project_type'] not in ['xcodegen', 'native'] or config['platform'] not in ['iOS', 'visionOS', 'macOS']:
        raise ValueError('Unsupported project_type or platform')
    if config['platform'] == 'macOS' and not developer_settings_supported(config):
        raise ValueError('macOS setup requires MZAppFoundation 0.5.0 or a current local checkout')
    for key in ['target', 'bundle_id', 'url_scheme']:
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]*', config[key]):
            raise ValueError(f'Invalid {key}')
    if short_developer_links_supported(config) and config['url_scheme'].lower() == 'mzappfoundation':
        raise ValueError('url_scheme must identify this app; the shared mzappfoundation scheme cannot choose an installed app')
    within(root, config['project'])
    # Administrative secrets must never enter a source-generation manifest.
    for key in config.get('providers', {}):
        if key not in ['revenuecat_public_key', 'sentry_dsn', 'google_service_info', 'sentry_org', 'sentry_project',
                       'revenuecat_project_name', 'revenuecat_project_id', 'revenuecat_app_id', 'sentry_project_id', 'firebase_project_name']:
            raise ValueError(f'Unsupported provider setting: {key}; administrative tokens belong in environment/CI')
    public_key = config.get('providers', {}).get('revenuecat_public_key')
    if public_key and not public_key.startswith('appl_'):
        raise ValueError('RevenueCat configuration requires an Apple public SDK key')
    if 'package_path' not in config and not re.fullmatch(r'\d+\.\d+\.\d+', config.get('package_version', '0.6.2')):
        raise ValueError('package_version must be an exact semantic version')
    if config.get('developer_link_host') and not all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?', label)
                                                    for label in config['developer_link_host'].split('.')):
        raise ValueError('developer_link_host must be an app-specific URL host')
    metadata_keys = ['revenuecat_project_name', 'revenuecat_project_id', 'revenuecat_app_id', 'sentry_project_id', 'firebase_project_name']
    if (config.get('developer_link_host') or any(k in config.get('providers', {}) for k in metadata_keys)) and not developer_settings_supported(config):
        raise ValueError('Developer settings metadata requires MZAppFoundation 0.5.0 or a current local checkout')
    if not isinstance(config.get('bug_reporting', False), bool):
        raise ValueError('bug_reporting must be a boolean')
    if config.get('bug_reporting'):
        if 'package_path' not in config and tuple(map(int, config.get('package_version', '0.6.2').split('.'))) < (0, 3, 0):
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
    modern = developer_settings_supported(config)
    host = ',\n            developerLinkHost: ' + swift_literal(config.get('developer_link_host', config['bundle_id'])) if modern and not short_developer_links_supported(config) else ''
    if modern:
        device_bootstrap = independent_device_bootstrap(config)
    else:
        device_bootstrap = f'''        do {{
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
        }}'''
    reporting = ''
    if reporting_enabled(config):
        prefix = swift_literal(config.get('report_archive_prefix', 'bug-report'))
        context = 'services: services, ' if modern else ''
        reporting = f'    #if os(iOS)\n    static let reporting = DeveloperReporting({context}archivePrefix: {prefix})\n    #endif\n'
    provider_imports = 'import MZAppFoundationLive\n#if os(iOS)\nimport MZAppFoundationFirebase\n#endif'
    if modern:
        provider_imports = '\n'.join('import ' + product for product in provider_products(config) if product != 'MZAppFoundation')
    return f'''// Generated by mz-app-foundation-setup. App-specific event definitions remain in config.json.
import Foundation
import MZAppFoundation
import MZAppFoundationLocal
#if !MZ_LOCAL && !targetEnvironment(simulator)
{provider_imports}
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
            preferences: .init(analytics: {analytics}, diagnostics: {diagnostics}){host})
        let schema = TelemetrySchema(events: {event_literal})
        #if MZ_LOCAL || targetEnvironment(simulator)
        return LocalServices.make(configuration: configuration, schema: schema)
        #else
{device_bootstrap}
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
    remove_shared_scheme(entries, config)
    for scheme in url_schemes(config):
        if not any(scheme in item.get('CFBundleURLSchemes', []) for item in entries):
            entries.append({'CFBundleURLSchemes': [scheme]})
    write(path, plistlib.dumps(values, sort_keys=True))


def mutate_xcodegen(root, config):
    import yaml
    path = within(root, config['project'])
    spec = yaml.safe_load(path.read_text())
    target = spec['targets'][config['target']]
    local_name = config['target'] + 'Local'
    spec.setdefault('configs', {'Debug': 'debug', 'Release': 'release'}).setdefault('Internal', 'release')
    package = {'path': config['package_path']} if config.get('package_path') else {
        'url': 'git@github.com:matteozajac/MZAppFoundation.git', 'exactVersion': config.get('package_version', '0.6.2')}
    spec.setdefault('packages', {})['MZAppFoundation'] = package
    base_dependencies = [d for d in target.get('dependencies', []) if d.get('package') != 'MZAppFoundation' and d.get('product', d.get('package')) not in VENDOR_PRODUCTS]
    source = '.mzappfoundation/Generated'
    sources = target.setdefault('sources', [])
    if isinstance(sources, str):
        sources = [sources]; target['sources'] = sources
    if source not in [s if isinstance(s, str) else s.get('path') for s in sources]:
        sources.append({'path': source, 'excludes': ['*.py', '*-Info.plist']})
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
    remove_shared_scheme(urls, config)
    for scheme in url_schemes(config):
        if not any(scheme in item.get('CFBundleURLSchemes', []) for item in urls):
            urls.append({'CFBundleURLSchemes': [scheme]})
    base = target.setdefault('settings', {}).setdefault('base', {})
    base['PRODUCT_BUNDLE_IDENTIFIER'] = config['bundle_id']
    configs = target['settings'].setdefault('configs', {})
    flags = configs.setdefault('Internal', {}).get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '$(inherited)')
    if 'MZ_INTERNAL' not in flags: flags += ' MZ_INTERNAL'
    configs['Internal']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = flags
    if developer_settings_supported(config):
        base['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    local = copy.deepcopy(target)
    local['dependencies'] = base_dependencies + [{'package': 'MZAppFoundation', 'product': 'MZAppFoundation'}]
    local['settings']['base'].update({'SUPPORTED_PLATFORMS': supported_platforms(config, local=True),
                                     'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) MZ_LOCAL'})
    for name in spec.get('configs', {}):
        settings = local['settings'].setdefault('configs', {}).setdefault(name, {})
        conditions = settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '$(inherited)').split()
        if 'MZ_LOCAL' not in conditions: conditions.append('MZ_LOCAL')
        settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = ' '.join(conditions)
    local.setdefault('postBuildScripts', [])[:] = [s for s in local.get('postBuildScripts', []) if s.get('name') != 'MZ Sentry Symbols']
    target['dependencies'] = base_dependencies + [{'package': 'MZAppFoundation', 'product': product} for product in provider_products(config)]
    target['settings']['base']['SUPPORTED_PLATFORMS'] = supported_platforms(config)
    target.setdefault('postBuildScripts', [])[:] = [s for s in target.get('postBuildScripts', []) if s.get('name') != 'MZ Sentry Symbols']
    if config.get('providers', {}).get('sentry_dsn'):
        target['postBuildScripts'].append({'name': 'MZ Sentry Symbols', 'script': 'python3 "$SRCROOT/.mzappfoundation/Generated/upload_symbols.py"', 'basedOnDependencyAnalysis': False})
        target['settings']['base']['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    if developer_settings_supported(config):
        for composition in (target, local):
            scripts = composition.setdefault('postBuildScripts', [])
            scripts[:] = [script for script in scripts if script.get('name') != 'MZ Build Metadata']
            scripts.append({'name': 'MZ Build Metadata', 'script': build_metadata_script(config),
                            'basedOnDependencyAnalysis': False})
            composition['settings']['base']['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
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
    if developer_settings_supported(config):
        write(generated / 'generate_build_metadata.py', (REPO / 'scripts/generate_build_metadata.py').read_bytes())
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
        for name, products in [(config['target'] + 'Local', ['MZAppFoundation']),
                               (config['target'], provider_products(config))]:
            target = project.get('targets', {}).get(name, {})
            for product in products:
                if not any(d.get('package') == 'MZAppFoundation' and d.get('product') == product for d in target.get('dependencies', [])):
                    errors.append(f'{name} is missing expected package product {product}')
            expected_platform = supported_platforms(config, local=name == config['target'] + 'Local')
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
