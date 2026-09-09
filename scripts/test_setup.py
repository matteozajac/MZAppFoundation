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

if __name__ == '__main__': unittest.main()
