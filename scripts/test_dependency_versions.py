import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('versions', Path(__file__).with_name('check_dependency_versions.py'))
versions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versions)


class DependencyVersionsTests(unittest.TestCase):
    def test_only_explicit_current_exceptions_are_accepted(self):
        manifest = (Path(__file__).resolve().parents[1] / 'Package.swift').read_text()
        releases = {repo: {'tag_name': pin} for repo, (pin, _) in versions.PROVIDERS.items()}
        releases['kean/Pulse']['tag_name'] = '5.2.3'
        releases['firebase/firebase-ios-sdk']['tag_name'] = '13.0.1'
        self.assertTrue(all(item['accepted'] for item in versions.check(manifest, releases)))
        releases['kean/Pulse']['tag_name'] = '5.2.4'
        self.assertFalse(versions.check(manifest, releases)[0]['accepted'])

    def test_manifest_drift_and_missing_dependency_fail(self):
        releases = {repo: {'tag_name': pin} for repo, (pin, _) in versions.PROVIDERS.items()}
        manifest = (Path(__file__).resolve().parents[1] / 'Package.swift').read_text()
        self.assertFalse(versions.check(manifest.replace('9.30.1', '9.27.0'), releases)[1]['accepted'])
        self.assertFalse(any(item['accepted'] for item in versions.check('', releases)))
