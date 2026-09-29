import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
import wave

SCRIPTS = Path(__file__).resolve().parents[1] / 'skills/app-bug-report/scripts'
with patch.object(sys, 'path', [str(SCRIPTS), *sys.path]):
    SPEC = importlib.util.spec_from_file_location('bug_report_transcription', SCRIPTS / 'transcribe_report.py')
    transcription = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(transcription)


class BugReportTranscriptionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = self.root / 'payload'
        self.payload.mkdir()
        self.output = self.root / 'transcription'
        self.model = self.root / 'ggml-small.bin'
        self.model.write_bytes(b'model')
        self.note = {'filename': 'voice-note.m4a', 'duration': 1, 'codec': 'aac', 'sampleRate': 24000,
                     'channels': 1, 'bitRate': 48000, 'transcriptionRequired': True}
        self.report = {'format': 'bug-reporter', 'schemaVersion': 2, 'id': str(uuid.uuid4()),
                       'title': '', 'metadata': {}, 'voiceNote': self.note,
                       'attachments': ['voice-note.m4a'], 'attachmentStatus': {'audio': 'included'}}
        (self.payload / 'report.json').write_text(json.dumps(self.report))
        (self.payload / 'report.txt').write_text('Voice note describes the issue.')
        (self.payload / 'voice-note.m4a').write_bytes(b'compressed AAC fixture')
        self.probe = {'streams': [{'codec_type': 'audio', 'codec_name': 'aac', 'sample_rate': '24000',
                                   'channels': 1, 'duration': '1.0'}]}

    def fake_tool(self, command, log_path, timeout, stdout_path=None):
        log_path.write_text('local tool log')
        if command[0] == 'ffprobe':
            stdout_path.write_text(json.dumps(self.probe))
        elif command[0] == 'ffmpeg':
            with wave.open(command[-1], 'wb') as audio:
                audio.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                audio.writeframes(bytes(32000))
        elif command[0] == 'whisper-cli':
            prefix = Path(command[command.index('-of') + 1])
            prefix.with_suffix('.txt').write_text('Saving the guest list fails.')
            prefix.with_suffix('.json').write_text('{"result":{"language":"en"}}')
            prefix.with_suffix('.srt').write_text('1\n00:00:00,000 --> 00:00:01,000\nSaving fails.\n')

    def transcribe(self):
        with patch.object(transcription, 'tool_path', side_effect=lambda name: name):
            return transcription.transcribe(self.payload, self.output, self.model)

    def test_success_preserves_original_and_emits_provenance_and_timestamped_transcript(self):
        with patch.object(transcription, 'run_tool', side_effect=self.fake_tool) as command:
            result = self.transcribe()
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['media']['duration'], 1)
        self.assertEqual(result['languageRequested'], 'auto')
        self.assertEqual(len(result['sourceSHA256']), 64)
        self.assertTrue((self.output / 'transcript.srt').is_file())
        self.assertFalse((self.output / 'voice-note-16khz.wav').exists())
        self.assertEqual((self.payload / 'voice-note.m4a').read_bytes(), b'compressed AAC fixture')
        whisper = command.call_args_list[-1].args[0]
        self.assertIn('-oj', whisper)
        self.assertNotIn('-tr', whisper)  # Preserve Polish or other original speech.

    def test_failed_whisper_is_not_reported_as_completed_and_removes_pcm(self):
        def failing_tool(command, *args):
            if command[0] == 'whisper-cli':
                raise RuntimeError('whisper-cli failed (exit 1)')
            self.fake_tool(command, *args)
        with patch.object(transcription, 'run_tool', side_effect=failing_tool), self.assertRaises(RuntimeError):
            self.transcribe()
        status = json.loads((self.output / 'transcription-status.json').read_text())
        self.assertEqual(status['status'], 'failed')
        self.assertNotIn('transcript', status)
        self.assertFalse((self.output / 'voice-note-16khz.wav').exists())

    def test_empty_transcript_is_failure(self):
        def empty_tool(command, *args):
            self.fake_tool(command, *args)
            if command[0] == 'whisper-cli':
                (self.output / 'transcript.txt').write_text(' \n')
        with patch.object(transcription, 'run_tool', side_effect=empty_tool), self.assertRaisesRegex(ValueError, 'no text'):
            self.transcribe()
        self.assertEqual(json.loads((self.output / 'transcription-status.json').read_text())['status'], 'failed')

    def test_invalid_real_media_rejected_before_whisper(self):
        for key, value in (('codec_type', 'video'), ('codec_name', 'pcm'), ('channels', 2),
                           ('duration', 'nan'), ('duration', '301'), ('duration', '3')):
            with self.subTest(key=key, value=value):
                probe = json.loads(json.dumps(self.probe))
                probe['streams'][0][key] = value
                with self.assertRaises(ValueError):
                    transcription.verify_media(probe, self.note)

    def test_aac_frame_padding_allowed_at_five_minute_limit(self):
        self.note['duration'] = 300
        self.probe['streams'][0]['duration'] = '300.085'
        self.assertEqual(transcription.verify_media(self.probe, self.note)['duration'], 300.085)

    def test_missing_model_or_tool_does_not_create_output(self):
        self.model.unlink()
        with self.assertRaisesRegex(ValueError, 'model is missing'):
            self.transcribe()
        self.assertFalse(self.output.exists())
        with patch.object(transcription.shutil, 'which', return_value=None), self.assertRaisesRegex(ValueError, 'tool is missing'):
            transcription.tool_path('whisper-cli')

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        (self.output / 'keep').write_text('user work')
        with self.assertRaises(FileExistsError):
            self.transcribe()
        self.assertEqual((self.output / 'keep').read_text(), 'user work')

    def test_cli_exit_error_is_captured_locally_without_exposing_speech(self):
        log = self.root / 'tool.log'
        with self.assertRaisesRegex(RuntimeError, 'failed .exit 7.') as error:
            transcription.run_tool([sys.executable, '-c', 'print("private speech"); raise SystemExit(7)'], log, 10)
        self.assertNotIn('private speech', str(error.exception))
        self.assertIn('private speech', log.read_text())

    def test_cli_timeout_is_reported(self):
        with patch.object(transcription.subprocess, 'run', side_effect=subprocess.TimeoutExpired('whisper-cli', 10)):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                transcription.run_tool(['whisper-cli'], self.root / 'tool.log', 10)


if __name__ == '__main__':
    unittest.main()
