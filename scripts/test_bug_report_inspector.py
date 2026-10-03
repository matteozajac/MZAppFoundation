import importlib.util
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import stat
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'skills/app-bug-report/scripts/inspect_report.py'
SPEC = importlib.util.spec_from_file_location('bug_report_inspector', SCRIPT)
inspector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspector)


class BugReportInspectorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.report = {
            'format': 'bug-reporter', 'schemaVersion': 1, 'id': str(uuid.uuid4()),
            'title': 'QA observed a failed save', 'metadata': {'version': '2.0', 'build': '42'},
            'attachments': [], 'attachmentStatus': {'logs': 'unavailable', 'video': 'excluded', 'screenshot': 'excluded'},
            'attachmentErrors': {'logs': 'Export failed'},
        }

    def archive(self, entries=None, wrapper=''):
        path = self.root / 'renamed.zip'
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(wrapper + 'report.json', json.dumps(self.report))
            archive.writestr(wrapper + 'report.txt', 'Steps: tap Save. Expected: saved.')
            for name, data in entries or []:
                archive.writestr(name, data)
        return path

    def test_renamed_wrapped_archive_and_unavailable_logs(self):
        result = inspector.inspect(self.archive(wrapper='jod-ios-ID/'), self.root / 'output')
        self.assertEqual(result['reportID'], self.report['id'])
        self.assertEqual(result['attachmentErrors'], {'logs': 'Export failed'})
        self.assertEqual(len(result['files']), 2)
        self.assertEqual(result['warnings'], [])
        self.assertEqual(result['pulse'], [])

    def test_path_traversal_absolute_backslash_and_duplicate_paths_rejected(self):
        for name in ('../escape.txt', '/escape.txt', 'foo/../../escape', 'foo\\escape', 'report.JSON'):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    inspector.extract(self.archive([(name, 'bad')]), self.root / 'extracted')
                self.assertFalse((self.root / 'extracted').exists())
                self.assertFalse((self.root / 'escape.txt').exists())

    def test_symbolic_link_rejected(self):
        link = zipfile.ZipInfo('link')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(ValueError):
            inspector.extract(self.archive([(link, '/tmp/target')]), self.root / 'out')

    def test_size_and_count_limits(self):
        source = self.archive()
        with patch.object(inspector, 'MAX_BYTES', 1), self.assertRaises(ValueError):
            inspector.extract(source, self.root / 'out')
        with patch.object(inspector, 'MAX_FILES', 1), self.assertRaises(ValueError):
            inspector.extract(source, self.root / 'out')

    def test_never_overwrite_existing_destination(self):
        output = self.root / 'output'
        output.mkdir()
        marker = output / 'keep'
        marker.write_text('user work')
        with self.assertRaises(ValueError):
            inspector.inspect(self.archive(), output)
        self.assertEqual(marker.read_text(), 'user work')

    def test_missing_declared_media_warns(self):
        self.report['attachments'] = ['recording.mp4']
        self.report['attachmentStatus']['video'] = 'included'
        result = inspector.inspect(self.archive(), self.root / 'output')
        self.assertEqual(len(result['warnings']), 2)
        self.assertEqual(result['attachmentStatus']['video'], 'included')

    def add_voice_note(self, title=''):
        self.report.update(schemaVersion=2, title=title, attachments=['voice-note.m4a'], voiceNote={
            'filename': 'voice-note.m4a', 'duration': 12.5, 'codec': 'aac',
            'sampleRate': 24000, 'channels': 1, 'bitRate': 48000, 'transcriptionRequired': True,
        })
        self.report['attachmentStatus']['audio'] = 'included'

    def test_audio_only_and_title_plus_audio_require_transcription(self):
        for index, title in enumerate(('', '   ', 'Save failed')):
            with self.subTest(title=title):
                self.add_voice_note(title)
                result = inspector.inspect(self.archive([('voice-note.m4a', b'fake AAC')]), self.root / str(index))
                self.assertTrue(result['voiceNote']['available'])
                self.assertTrue(result['voiceNote']['transcriptionRequired'])
                self.assertFalse(result['voiceNote']['mediaVerified'])
                self.assertEqual(result['warnings'], [])

    def test_automatic_encoder_bitrate_remains_transcribable(self):
        for index, bitrate in enumerate((None, 64000)):
            self.add_voice_note()
            if bitrate is None:
                del self.report['voiceNote']['bitRate']
            else:
                self.report['voiceNote']['bitRate'] = bitrate
            result = inspector.inspect(self.archive([('voice-note.m4a', b'fake AAC')]), self.root / str(index))
            self.assertTrue(result['voiceNote']['available'])
            self.assertTrue(result['voiceNote']['transcriptionRequired'])
            self.assertEqual(result['warnings'], [])

    def test_schema_two_title_only_needs_no_transcription(self):
        self.report['schemaVersion'] = 2
        self.report['attachmentStatus']['audio'] = 'excluded'
        result = inspector.inspect(self.archive(), self.root / 'output')
        self.assertIsNone(result['voiceNote'])
        self.assertEqual(result['warnings'], [])

    def test_silent_replay_video_is_never_a_voice_note(self):
        self.report.update(schemaVersion=2, title='', attachments=['recording.mp4'])
        self.report['attachmentStatus']['video'] = 'included'
        result = inspector.inspect(self.archive([('recording.mp4', b'video')]), self.root / 'output')
        self.assertIsNone(result['voiceNote'])
        self.assertIn('no title or usable voice note', result['warnings'][0])

    def test_missing_empty_undeclared_or_unavailable_voice_note_warns(self):
        for index, failure in enumerate(('missing', 'empty', 'undeclared', 'unavailable')):
            with self.subTest(failure=failure):
                self.add_voice_note()
                entries = [('voice-note.m4a', b'voice')]
                if failure == 'missing':
                    entries = []
                elif failure == 'empty':
                    entries = [('voice-note.m4a', b'')]
                elif failure == 'undeclared':
                    self.report['attachments'] = []
                else:
                    self.report['attachmentStatus']['audio'] = 'unavailable'
                result = inspector.inspect(self.archive(entries), self.root / str(index))
                self.assertFalse(result['voiceNote']['available'])
                self.assertTrue(any('no title or usable voice note' in warning for warning in result['warnings']))

    def test_audio_without_metadata_is_not_automatically_transcribed(self):
        self.report.update(schemaVersion=2, attachments=['voice-note.m4a'])
        self.report['attachmentStatus']['audio'] = 'included'
        result = inspector.inspect(self.archive([('voice-note.m4a', b'audio')]), self.root / 'output')
        self.assertIsNone(result['voiceNote'])
        self.assertIn('metadata is missing', result['warnings'][0])

    def test_unavailable_audio_warns_even_when_title_is_present(self):
        self.report['schemaVersion'] = 2
        self.report['attachmentStatus']['audio'] = 'unavailable'
        self.report['attachmentErrors']['audio'] = 'Copy failed'
        result = inspector.inspect(self.archive(), self.root / 'output')
        self.assertIsNone(result['voiceNote'])
        self.assertEqual(result['attachmentErrors']['audio'], 'Copy failed')
        self.assertIn('Audio was unavailable', result['warnings'][0])

    def test_invalid_voice_note_metadata_is_unavailable(self):
        for index, (key, value) in enumerate((('duration', 301), ('duration', 0), ('duration', True),
                                             ('duration', float('nan')), ('codec', 'pcm'), ('sampleRate', 48000))):
            with self.subTest(key=key, value=value):
                self.add_voice_note()
                self.report['voiceNote'][key] = value
                result = inspector.inspect(self.archive([('voice-note.m4a', b'audio')]), self.root / str(index))
                self.assertFalse(result['voiceNote']['available'])
                self.assertTrue(result['warnings'])

    def test_unsafe_voice_note_references_rejected(self):
        for index, name in enumerate(('../outside.m4a', '/outside.m4a', 'http:voice.m4a', 'foo\\voice.m4a', 'recording.mp4')):
            self.add_voice_note()
            self.report['voiceNote']['filename'] = name
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'voiceNote filename'):
                inspector.inspect(self.archive(), self.root / str(index))

    def test_legacy_title_report_still_readable(self):
        del self.report['format']
        del self.report['schemaVersion']
        result = inspector.inspect(self.archive(), self.root / 'output')
        self.assertEqual(result['schemaVersion'], 0)
        self.assertIsNone(result['voiceNote'])
        self.assertEqual(len(result['warnings']), 1)

    def test_unknown_schema_and_manifest_paths_rejected(self):
        self.report['schemaVersion'] = 99
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            inspector.inspect(self.archive(), self.root / 'out1')
        self.report['schemaVersion'] = 1
        self.report['attachments'] = ['../outside.pulse']
        with self.assertRaisesRegex(ValueError, 'attachment names'):
            inspector.inspect(self.archive(), self.root / 'out2')

    def test_corrupt_pulse_keeps_notes_and_reports_incomplete_inspection(self):
        self.report['attachments'] = ['logs.pulse']
        self.report['attachmentStatus']['logs'] = 'included'
        result = inspector.inspect(self.archive([('logs.pulse', b'not a database')]), self.root / 'out')
        self.assertEqual(result['pulse'], [])
        self.assertTrue(result['warnings'][0].startswith('Pulse could not be fully decoded'))
        self.assertTrue((Path(result['payloadDirectory']) / 'report.txt').exists())

    def test_pulse_relationships_dates_and_external_and_inline_bodies(self):
        # The native iOS integration fixture separately verifies real LZFSE bytes.
        db_path = self.root / 'logs.sqlite'
        with closing(sqlite3.connect(db_path)) as db, db:
            db.execute('CREATE TABLE ZLOGGERMESSAGEENTITY (Z_PK INTEGER, ZTEXT TEXT, ZLEVEL INTEGER, ZCREATEDAT REAL)')
            db.execute("INSERT INTO ZLOGGERMESSAGEENTITY VALUES (1, 'Save failed', 6, 0)")
            db.execute('CREATE TABLE ZNETWORKTASKENTITY (Z_PK INTEGER, ZSTATUSCODE INTEGER, ZREQUESTBODY INTEGER, ZRESPONSEBODY INTEGER)')
            db.execute('INSERT INTO ZNETWORKTASKENTITY VALUES (1, 500, 1, 2)')
            db.execute('CREATE TABLE ZLOGGERBLOBHANDLEENTITY (Z_PK INTEGER, ZKEY BLOB, ZINLINEDATA BLOB, ZISUNCOMPRESSED INTEGER)')
            db.execute('INSERT INTO ZLOGGERBLOBHANDLEENTITY VALUES (1, ?, NULL, 0)', (bytes.fromhex('aa' * 20),))
            db.execute('INSERT INTO ZLOGGERBLOBHANDLEENTITY VALUES (2, ?, ?, 1)', (bytes.fromhex('bb' * 20), b'response'))
        pulse = self.root / 'logs.pulse'
        with closing(sqlite3.connect(pulse)) as db, db:
            db.execute('CREATE TABLE ZPULSEBLOBENTITY (ZKEY TEXT, ZDATA BLOB)')
            db.executemany('INSERT INTO ZPULSEBLOBENTITY VALUES (?, ?)', [('database', db_path.read_bytes()), ('aa' * 20, b'compressed-request')])
        with patch.object(inspector, 'lzfse', side_effect=lambda data: b'request' if data == b'compressed-request' else data):
            result = inspector.inspect_pulse(pulse, self.root / 'pulse')
        self.assertEqual(result['tableCounts']['ZNETWORKTASKENTITY'], 1)
        message = json.loads((self.root / 'pulse/zloggermessageentity.jsonl').read_text())
        self.assertEqual(message['createdAtUTC'], '2001-01-01T00:00:00+00:00')
        self.assertEqual(message['levelName'], 'error')
        self.assertEqual((self.root / ('pulse/blobs/' + 'aa' * 20 + '.body')).read_bytes(), b'request')
        self.assertEqual((self.root / ('pulse/blobs/' + 'bb' * 20 + '.body')).read_bytes(), b'response')

    def test_invalid_lzfse_is_bounded(self):
        if inspector.sys.platform != 'darwin':
            self.skipTest('Native macOS decoder')
        with self.assertRaises(ValueError):
            inspector.lzfse(b'garbage', limit=65536)

    def test_diagnostics_snapshot_has_separate_schema_and_no_backend_verification_claim(self):
        snapshot = {'format': 'mzappfoundation-diagnostics', 'schemaVersion': 1,
                    'app': {'bundleIdentifier': 'test.foundation'}, 'providers': [{'projectID': 'proj_fixture'}]}
        self.report['attachments'] = ['diagnostics.json']
        self.report['attachmentStatus']['diagnostics'] = 'included'
        result = inspector.inspect(self.archive([('diagnostics.json', json.dumps(snapshot))]), self.root / 'out')
        self.assertTrue(result['diagnostics']['available'])
        self.assertTrue(result['diagnostics']['formatValid'])
        self.assertFalse(result['diagnostics']['backendDeliveryVerified'])
        self.assertEqual(result['diagnostics']['schemaVersion'], 1)
        self.assertEqual(result['warnings'], [])

    def test_invalid_or_private_diagnostics_warn_without_discarding_qa_notes(self):
        snapshots = [b'not JSON', json.dumps({'format': 'mzappfoundation-diagnostics', 'schemaVersion': True}),
                     json.dumps({'format': 'mzappfoundation-diagnostics', 'schemaVersion': 2}),
                     json.dumps({'format': 'mzappfoundation-diagnostics', 'schemaVersion': 1, 'apiKey': 'private'}),
                     b' ' * (inspector.MAX_DIAGNOSTICS + 1)]
        self.report['attachments'] = ['diagnostics.json']
        self.report['attachmentStatus']['diagnostics'] = 'included'
        for index, snapshot in enumerate(snapshots):
            with self.subTest(index=index):
                result = inspector.inspect(self.archive([('diagnostics.json', snapshot)]), self.root / str(index))
                self.assertFalse(result['diagnostics']['available'])
                self.assertTrue(result['warnings'])
                self.assertFalse(any('apiKey' in warning or 'private' == warning for warning in result['warnings']))
                self.assertTrue((Path(result['payloadDirectory']) / 'report.txt').exists())

    def test_diagnostics_status_conflicts_and_missing_snapshots_are_explicit(self):
        for index, failure in enumerate(('missing', 'excluded', 'unavailable', 'undeclared')):
            self.report['attachments'] = ['diagnostics.json'] if failure != 'undeclared' else []
            self.report['attachmentStatus']['diagnostics'] = failure if failure in ('excluded', 'unavailable') else 'included'
            entries = [] if failure == 'missing' else [('diagnostics.json', '{}')]
            result = inspector.inspect(self.archive(entries), self.root / str(index))
            self.assertFalse(result['diagnostics']['available'])
            self.assertTrue(result['warnings'])

    def test_deep_diagnostics_structure_is_bounded(self):
        snapshot = {'format': 'mzappfoundation-diagnostics', 'schemaVersion': 1,
                    'nested': [[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]}
        self.report['attachments'] = ['diagnostics.json']
        self.report['attachmentStatus']['diagnostics'] = 'included'
        result = inspector.inspect(self.archive([('diagnostics.json', json.dumps(snapshot))]), self.root / 'out')
        self.assertFalse(result['diagnostics']['available'])
        self.assertTrue(result['warnings'])


if __name__ == '__main__':
    unittest.main()
