import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('build_metadata', Path(__file__).with_name('generate_build_metadata.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class BuildMetadataTests(unittest.TestCase):
    def test_unstamped_metadata_is_deterministic_and_does_not_invent_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = metadata.generate(root, version='0.5.0', channel='Local')
            self.assertEqual(first, metadata.generate(root, version='0.5.0', channel='Local'))
            self.assertNotIn('appRevision', first)
            self.assertNotIn('foundationRevision', first)
            self.assertNotIn('buildDate', first)
            self.assertEqual(first['foundationVersion'], '0.5.0')

    def test_app_resolution_overrides_library_snapshot_and_omits_locations(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'app'; library = Path(directory) / 'library'
            app.mkdir(); library.mkdir()
            (library / 'VERSION').write_text('0.6.0-dev\n')
            (library / 'Package.resolved').write_text(json.dumps({'pins': [
                {'identity': 'pulse', 'state': {'version': '5.2.1'}}]}))
            revision = 'a' * 40
            (app / 'Package.resolved').write_text(json.dumps({'pins': [
                {'identity': 'pulse', 'location': 'https://secret@example.com/private', 'state': {'version': '5.3.0'}},
                {'identity': 'mzappfoundation', 'state': {'version': '0.5.0', 'revision': revision}}]}))
            result = metadata.generate(app, library, timestamp=123)
            self.assertEqual(result['resolvedPackageVersions']['pulse'], '5.3.0')
            self.assertEqual(result['foundationVersion'], '0.6.0-dev')
            self.assertNotIn('secret', str(result))
            self.assertNotIn('private', str(result))
            remote = metadata.generate(app)
            self.assertEqual(remote['foundationRevision'], revision)
            self.assertEqual(remote['foundationVersion'], '0.5.0')

    def test_generated_library_version_has_single_version_and_pin_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'VERSION').write_text('2.3.4-dev\n')
            (root / 'Package.resolved').write_text(json.dumps({'pins': [
                {'identity': 'sentry-cocoa', 'state': {'version': '1.2.3'}}]}))
            source = metadata.swift_source(root)
            self.assertIn('current = "2.3.4-dev"', source)
            self.assertIn('"sentry-cocoa": "1.2.3"', source)

    def test_checked_in_library_stamp_matches_authoritative_inputs(self):
        root = Path(__file__).resolve().parents[1]
        source = root / 'Packages/Core/Sources/MZAppFoundation/FoundationVersion.swift'
        self.assertEqual(source.read_text(), metadata.swift_source(root))

    def test_invalid_input_cannot_embed_arbitrary_source_or_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError): metadata.generate(root, version='bad/version')
            with self.assertRaises(ValueError): metadata.generate(root, version='0.5.0', channel='secret\nvalue')


if __name__ == '__main__': unittest.main()
