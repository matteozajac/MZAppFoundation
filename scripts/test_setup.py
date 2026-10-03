import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

spec = importlib.util.spec_from_file_location('setup', Path(__file__).with_name('setup.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

class SetupTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory).resolve()
        (root / 'Sources').mkdir()
        (root / 'Sources/App.swift').write_text('import SwiftUI\n@main struct Demo: App { var body: some Scene { WindowGroup { Text("Demo") } } }\n')
        project = {'name': 'Demo', 'targets': {'Demo': {'type': 'application', 'platform': 'iOS', 'deploymentTarget': '26.0', 'sources': ['Sources'], 'settings': {'base': {'GENERATE_INFOPLIST_FILE': True}}}}}
        (root / 'project.yml').write_text(yaml.safe_dump(project))
        return root, {'project': 'project.yml', 'project_type': 'xcodegen', 'target': 'Demo', 'bundle_id': 'com.example.demo',
                      'url_scheme': 'demo', 'platform': 'iOS', 'package_path': str(setup.REPO), 'events': {'opened': ['count']}}

    def test_new_and_repeated_xcodegen_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            setup.apply(root, config)
            before = (root / 'project.yml').read_bytes()
            bootstrap = (root / '.mzappfoundation/Generated/MZBootstrap.swift').read_bytes()
            setup.apply(root, config)
            self.assertEqual(before, (root / 'project.yml').read_bytes())
            self.assertEqual(bootstrap, (root / '.mzappfoundation/Generated/MZBootstrap.swift').read_bytes())
            project = yaml.safe_load(before)
            self.assertEqual(project['targets']['DemoLocal']['dependencies'][0]['product'], 'MZAppFoundation')
            self.assertEqual(project['targets']['Demo']['dependencies'][0]['product'], 'MZAppFoundation')
            for name in ('Debug', 'Internal', 'Release'):
                self.assertIn('MZ_LOCAL', project['targets']['DemoLocal']['settings']['configs'][name]['SWIFT_ACTIVE_COMPILATION_CONDITIONS'])
            for target in ('Demo', 'DemoLocal'):
                scripts = project['targets'][target]['postBuildScripts']
                self.assertEqual([script['name'] for script in scripts].count('MZ Build Metadata'), 1)
                self.assertIn('MZFoundationBuildMetadata.plist', scripts[-1]['script'])
            self.assertIn('absent', setup.inventory(root, config)['catalog'])
            self.assertFalse(setup.verify(root, config)['verified'])

    def test_partial_setup_preserves_unrelated_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            project = yaml.safe_load((root / 'project.yml').read_text())
            project['targets']['Demo']['info'] = {'path': 'Info.plist', 'properties': {'CustomSetting': 'keep', 'CFBundleURLTypes': [{'CFBundleURLSchemes': ['existing']}]}}
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            setup.apply(root, config)
            properties = yaml.safe_load((root / 'project.yml').read_text())['targets']['Demo']['info']['properties']
            self.assertEqual(properties['CustomSetting'], 'keep')
            schemes = [scheme for entry in properties['CFBundleURLTypes'] for scheme in entry['CFBundleURLSchemes']]
            self.assertEqual(set(schemes), {'existing', 'demo'})

    def test_short_links_remove_shared_registration_and_preserve_app_schemes(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            project = yaml.safe_load((root / 'project.yml').read_text())
            urls = [{'CFBundleURLName': 'app routes', 'CFBundleURLSchemes': ['existing', 'MZAPPFOUNDATION']},
                    {'CFBundleURLSchemes': ['mzappfoundation']}]
            project['targets']['Demo']['info'] = {'path': 'Info.plist', 'properties': {'CFBundleURLTypes': urls}}
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            setup.apply(root, config)
            for target in ('Demo', 'DemoLocal'):
                entries = yaml.safe_load((root / 'project.yml').read_text())['targets'][target]['info']['properties']['CFBundleURLTypes']
                self.assertEqual(entries, [{'CFBundleURLName': 'app routes', 'CFBundleURLSchemes': ['existing']},
                                           {'CFBundleURLSchemes': ['demo']}])
            setup.configure_plist(root / 'Info.plist', config)
            import plistlib
            entries = plistlib.loads((root / 'Info.plist').read_bytes())['CFBundleURLTypes']
            self.assertEqual([scheme for entry in entries for scheme in entry['CFBundleURLSchemes']], ['existing', 'demo'])
            self.assertEqual(setup.url_schemes(dict(config, package_version='0.5.1')), ['demo'])

    def test_native_short_links_prune_shared_scheme_from_concrete_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            import plistlib
            project = yaml.safe_load((root / 'project.yml').read_text())
            project['targets']['Demo']['info'] = {'path': 'Info.plist'}
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            subprocess.run(['xcodegen', 'generate'], cwd=root, check=True, capture_output=True)
            (root / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleURLTypes': [
                {'CFBundleURLSchemes': ['existing', 'mzappfoundation']},
                {'CFBundleURLSchemes': ['MZAPPFOUNDATION']}]}))
            config.update(project_type='native', project='Demo.xcodeproj')
            setup.apply(root, config)
            entries = plistlib.loads((root / 'Info.plist').read_bytes())['CFBundleURLTypes']
            self.assertEqual([scheme for entry in entries for scheme in entry['CFBundleURLSchemes']], ['existing', 'demo'])

    def test_developer_settings_generation_preserves_old_version_compatibility(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config['developer_link_host'] = 'demo'
            config['providers'] = {'revenuecat_project_name': 'Demo Project', 'sentry_org': 'example', 'sentry_project': 'demo'}
            source = setup.bootstrap(config)
            self.assertNotIn('developerLinkHost:', source)
            self.assertIn('revenueCatProject = ProviderProjectIdentity(name: "Demo Project"', source)
            self.assertNotIn('import MZAppFoundationFirebase', source)
            self.assertIn('LocalServices.make', source)
            old = dict(config)
            old.pop('package_path')
            old.pop('developer_link_host')
            old['providers'] = {}
            old['package_version'] = '0.3.1'
            self.assertNotIn('makeRecovering', setup.bootstrap(old))
            self.assertEqual(setup.url_schemes(old), ['demo'])
            old['package_version'] = '0.5.0'
            self.assertIn('developerLinkHost: "com.example.demo"', setup.bootstrap(old))
            self.assertEqual(setup.url_schemes(old), ['demo', 'mzappfoundation'])

    def test_default_remote_release_pins_current_version_and_settings_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config.pop('package_path')
            setup.apply(root, config)
            project = yaml.safe_load((root / 'project.yml').read_text())
            self.assertEqual(project['packages']['MZAppFoundation']['version'], '0.5.1')
            self.assertEqual(project['targets']['Demo']['dependencies'][0]['product'], 'MZAppFoundation')
            self.assertIn('--foundation-version 0.5.1', setup.build_metadata_script(config))
            self.assertEqual(setup.url_schemes(dict(config, package_version='0.5.1')), ['demo'])
            self.assertFalse(setup.developer_settings_supported(dict(config, package_version='0.4.0')))
            self.assertTrue(setup.developer_settings_supported(dict(config, package_version='0.5.1')))

            subprocess.run(['xcodegen', 'generate'], cwd=root, check=True, capture_output=True)
            config.update(project_type='native', project='Demo.xcodeproj')
            setup.apply(root, config)
            ruby = os.environ.get('RUBY', 'ruby')
            result = subprocess.run([ruby, '-rxcodeproj', '-rjson', '-e',
                'p = Xcodeproj::Project.open(ARGV[0]); puts JSON.generate(p.root_object.package_references.map { |r| r.requirement })',
                str(root / 'Demo.xcodeproj')], check=True, text=True, capture_output=True)
            self.assertEqual(json.loads(result.stdout), [{'kind': 'exactVersion', 'version': '0.5.1'}])

    def test_macos_setup_has_native_platforms_and_build_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config['platform'] = 'macOS'
            project = yaml.safe_load((root / 'project.yml').read_text())
            project['targets']['Demo'].update(platform='macOS', deploymentTarget='15.0')
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            setup.apply(root, config)
            configured = yaml.safe_load((root / 'project.yml').read_text())
            for target in ('Demo', 'DemoLocal'):
                self.assertEqual(configured['targets'][target]['settings']['base']['SUPPORTED_PLATFORMS'], 'macosx')
                self.assertEqual(len(configured['targets'][target]['postBuildScripts']), 1)
            self.assertEqual(configured['targets']['Demo']['dependencies'][0]['product'], 'MZAppFoundation')

    def test_provider_products_follow_supplied_configuration_without_umbrella_linkage(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config['providers'] = {'sentry_dsn': 'https://public@example.invalid/12'}
            self.assertEqual(setup.provider_products(config), ['MZAppFoundation', 'MZAppFoundationSentry'])
            source = setup.bootstrap(config)
            self.assertIn('import MZAppFoundationSentry', source)
            self.assertNotIn('import MZAppFoundationRevenueCat', source)
            self.assertNotIn('import MZAppFoundationFirebase', source)
            self.assertNotIn('import MZAppFoundationLive', source)
            config['providers'].update(revenuecat_public_key='appl_example_public', google_service_info='GoogleService-Info.plist')
            self.assertEqual(setup.provider_products(config), ['MZAppFoundation', 'MZAppFoundationRevenueCat',
                                                              'MZAppFoundationSentry', 'MZAppFoundationFirebaseAnalytics'])
            config['platform'] = 'visionOS'
            self.assertNotIn('MZAppFoundationFirebaseAnalytics', setup.provider_products(config))

    def test_native_setup_is_semantically_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            subprocess.run(['xcodegen', 'generate'], cwd=root, check=True, capture_output=True)
            config.update(project_type='native', project='Demo.xcodeproj')
            setup.apply(root, config)
            before = (root / 'Demo.xcodeproj/project.pbxproj').read_bytes()
            setup.apply(root, config)
            self.assertEqual(before, (root / 'Demo.xcodeproj/project.pbxproj').read_bytes())
            ruby = os.environ.get('RUBY', 'ruby')
            result = subprocess.run([ruby, '-rxcodeproj', '-rjson', '-e',
                'p = Xcodeproj::Project.open(ARGV[0]); puts JSON.generate(p.targets.map { |t| [t.name, t.package_product_dependencies.map(&:product_name), t.source_build_phase.files.count] })', str(root / 'Demo.xcodeproj')], check=True, text=True, capture_output=True)
            targets = json.loads(result.stdout)
            self.assertEqual(len(targets), 2)
            self.assertEqual(targets[0][1], ['MZAppFoundation'])
            self.assertEqual(targets[1][1], ['MZAppFoundation'])
            self.assertTrue(all(t[2] == 2 for t in targets))

    def test_rejects_path_escape_and_administrative_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            path = root / 'config.json'
            config['providers'] = {'auth_token': 'not-a-real-token'}
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError): setup.load(root, path)
            with self.assertRaises(ValueError): setup.within(root, '../outside')

    def test_native_synchronized_source_groups_survive_repeat_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            ruby = os.environ.get('RUBY', 'ruby')
            subprocess.run([ruby, '-rxcodeproj', '-e',
                'p = Xcodeproj::Project.new(ARGV[0]); t = p.new_target(:application, "Demo", :ios, "26.0"); '
                'g = p.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup); g.path = "Sources"; '
                'g.source_tree = "<group>"; p.main_group.children << g; t.file_system_synchronized_groups << g; p.save',
                str(root / 'Demo.xcodeproj')], check=True, capture_output=True)
            config.update(project_type='native', project='Demo.xcodeproj')
            setup.apply(root, config)
            before = (root / 'Demo.xcodeproj/project.pbxproj').read_bytes()
            setup.apply(root, config)
            self.assertEqual(before, (root / 'Demo.xcodeproj/project.pbxproj').read_bytes())
            result = subprocess.run([ruby, '-rxcodeproj', '-rjson', '-e',
                'p = Xcodeproj::Project.open(ARGV[0]); puts JSON.generate(p.targets.map { |t| t.file_system_synchronized_groups.map(&:uuid) })',
                str(root / 'Demo.xcodeproj')], check=True, text=True, capture_output=True)
            groups = json.loads(result.stdout)
            self.assertEqual(len(groups), 2)
            self.assertEqual(len(groups[0]), 1)
            self.assertEqual(groups[0], groups[1])

    def test_sdk_imports_block_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            (root / 'Sources/Legacy.swift').write_text('import RevenueCat\n')
            self.assertEqual(setup.inventory(root, config)['vendor_imports'][0]['modules'], ['RevenueCat'])

    def test_reporting_preserves_microphone_text_and_verifies_wiring(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config['bug_reporting'] = True
            project = yaml.safe_load((root / 'project.yml').read_text())
            project['targets']['Demo']['info'] = {'path': 'Info.plist', 'properties': {'NSMicrophoneUsageDescription': 'Record album messages and bug reports.'}}
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            setup.apply(root, config)
            (root / 'Sources/App.swift').write_text('import SwiftUI\nimport MZAppFoundationLocal\n@main struct Demo: App { var body: some Scene { WindowGroup { Text("Demo").appDeveloperTools(MZBootstrap.services.developerOptions, reporting: MZBootstrap.reporting) } } }')
            self.assertTrue(setup.verify(root, config)['verified'])
            project = yaml.safe_load((root / 'project.yml').read_text())
            self.assertEqual(project['targets']['DemoLocal']['info']['properties']['NSMicrophoneUsageDescription'], 'Record album messages and bug reports.')
            del project['targets']['DemoLocal']['info']['properties']['NSMicrophoneUsageDescription']
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            self.assertIn('DemoLocal is missing NSMicrophoneUsageDescription', setup.verify(root, config)['errors'])

    def test_reporting_preserves_generated_microphone_build_setting(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config['bug_reporting'] = True
            project = yaml.safe_load((root / 'project.yml').read_text())
            project['targets']['Demo']['settings']['base']['INFOPLIST_KEY_NSMicrophoneUsageDescription'] = 'Record existing app audio.'
            (root / 'project.yml').write_text(yaml.safe_dump(project))
            setup.apply(root, config)
            project = yaml.safe_load((root / 'project.yml').read_text())
            for target in ('Demo', 'DemoLocal'):
                self.assertEqual(project['targets'][target]['info']['properties']['NSMicrophoneUsageDescription'], 'Record existing app audio.')

    def test_reporting_native_generated_plist_and_repeat_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            subprocess.run(['xcodegen', 'generate'], cwd=root, check=True, capture_output=True)
            config.update(project_type='native', project='Demo.xcodeproj', bug_reporting=True)
            setup.apply(root, config)
            (root / 'Sources/App.swift').write_text('import SwiftUI\nimport MZAppFoundationLocal\n@main struct Demo: App { var body: some Scene { WindowGroup { Text("Demo").appDeveloperTools(MZBootstrap.services.developerOptions, reporting: MZBootstrap.reporting) } } }')
            self.assertTrue(setup.verify(root, config)['verified'])
            before = (root / 'Demo.xcodeproj/project.pbxproj').read_bytes()
            setup.apply(root, config)
            self.assertEqual(before, (root / 'Demo.xcodeproj/project.pbxproj').read_bytes())
            import plistlib
            plist = root / '.mzappfoundation/Generated/App-Info.plist'
            data = plistlib.loads(plist.read_bytes())
            self.assertEqual(data['NSMicrophoneUsageDescription'], setup.DEFAULT_MICROPHONE)
            del data['NSMicrophoneUsageDescription']
            plist.write_bytes(plistlib.dumps(data))
            self.assertFalse(setup.verify(root, config)['verified'])

    def test_reporting_upgrades_existing_native_remote_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            subprocess.run(['xcodegen', 'generate'], cwd=root, check=True, capture_output=True)
            config.update(project_type='native', project='Demo.xcodeproj', package_version='0.2.0')
            del config['package_path']
            setup.apply(root, config)
            config.update(package_version='0.3.0', bug_reporting=True)
            setup.apply(root, config)
            result = subprocess.run([os.environ.get('RUBY', 'ruby'), '-rxcodeproj', '-rjson', '-e',
                'p = Xcodeproj::Project.open(ARGV[0]); puts JSON.generate(p.root_object.package_references.map(&:requirement))',
                str(root / 'Demo.xcodeproj')], check=True, text=True, capture_output=True)
            self.assertEqual(json.loads(result.stdout), [{'kind': 'exactVersion', 'version': '0.3.0'}])

    def test_reporting_configuration_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root, config = self.fixture(directory)
            config.update(bug_reporting=True, report_archive_prefix='../escape')
            path = root / 'config.json'
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError): setup.load(root, path)
            config.update(report_archive_prefix='demo', microphone_usage_description=' ')
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError): setup.load(root, path)
            config.update(microphone_usage_description='Record bugs.', platform='visionOS')
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError): setup.load(root, path)
            config.update(platform='iOS', package_version='0.2.0')
            del config['package_path']
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError): setup.load(root, path)

if __name__ == '__main__': unittest.main()
