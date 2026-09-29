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
            self.assertEqual(project['targets']['Demo']['dependencies'][0]['product'], 'MZAppFoundationFirebase')
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
            self.assertEqual(len(properties['CFBundleURLTypes']), 2)

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
            self.assertEqual(targets[0][1], ['MZAppFoundationFirebase'])
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
