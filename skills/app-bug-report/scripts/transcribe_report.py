#!/usr/bin/env python3
"""Transcribe a validated report voice note locally with ffmpeg and whisper.cpp."""
import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import wave

from inspect_report import inspect_voice_note, read_manifest, write_json


def tool_path(name):
    path = shutil.which(name)
    if not path:
        raise ValueError(f"Required local tool is missing: {name}; see references/voice-transcription.md")
    return path


def run_tool(command, log_path, timeout, stdout_path=None):
    """Keep speech and CLI diagnostics in local artifacts, never terminal output."""
    with log_path.open("wb") as log:
        try:
            if stdout_path:
                with stdout_path.open("wb") as output:
                    result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=output,
                                            stderr=log, timeout=timeout, check=False)
            else:
                result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"{Path(command[0]).name} timed out; inspect {log_path.name}") from error
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed (exit {result.returncode}); inspect {log_path.name}")


def verify_media(probe, note):
    streams = probe.get("streams", [])
    if len(streams) != 1 or streams[0].get("codec_type") != "audio":
        raise ValueError("Voice note must contain one audio stream and no video")
    stream = streams[0]
    if (stream.get("codec_name") != "aac" or str(stream.get("sample_rate")) != "24000"
            or stream.get("channels") != 1):
        raise ValueError("Voice note media disagrees with the mono AAC 24 kHz manifest")
    try:
        duration = float(stream.get("duration", probe.get("format", {}).get("duration")))
    except (TypeError, ValueError) as error:
        raise ValueError("Cannot determine voice note media duration") from error
    # AAC may add one or two codec frames around the recorder's 300-second limit.
    if not math.isfinite(duration) or not 0 < duration <= 300.25:
        raise ValueError("Voice note media exceeds five minutes or has an invalid duration")
    if abs(duration - note["duration"]) > 0.5:
        raise ValueError("Voice note media duration disagrees with the manifest")
    return {"duration": duration, "codec": "aac", "sampleRate": 24000, "channels": 1}


def transcribe(report_directory, output, model, language="auto", whisper_cli="whisper-cli"):
    root, report, warnings = read_manifest(report_directory)
    note = inspect_voice_note(root, report, warnings)
    if not note or not note["available"]:
        raise ValueError("Report has no usable declared voice note; inspect the report summary warnings")
    if not re.fullmatch(r"auto|[a-z]{2,3}", language):
        raise ValueError("Language must be auto or a whisper.cpp language code, such as pl or en")
    model = model.expanduser().resolve()
    if not model.is_file() or model.stat().st_size == 0:
        raise ValueError("Local Whisper model is missing or empty; see references/voice-transcription.md")
    if ".en" in model.name and language != "en":
        raise ValueError("Use a multilingual model for automatic detection or Polish speech")
    ffprobe = tool_path("ffprobe")
    ffmpeg = tool_path("ffmpeg")
    whisper = tool_path(whisper_cli)
    output.mkdir(parents=True, exist_ok=False)
    source = Path(note["path"]).resolve()
    status = {
        "reportID": report["id"], "source": str(source),
        "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "engine": "whisper.cpp", "model": str(model), "languageRequested": language,
        "status": "running", "warnings": warnings,
    }
    status_path = output / "transcription-status.json"
    write_json(status_path, status)
    wav = output / "voice-note-16khz.wav"
    try:
        probe_path = output / "media.json"
        run_tool([ffprobe, "-v", "error", "-protocol_whitelist", "file", "-f", "mov",
                  "-show_entries", "stream=codec_type,codec_name,sample_rate,channels,duration:format=duration",
                  "-of", "json", "-i", str(source)], output / "ffprobe.log", 30, probe_path)
        if probe_path.stat().st_size > 1024 * 1024:
            raise ValueError("Unexpectedly large media metadata")
        status["media"] = verify_media(json.loads(probe_path.read_text()), note)
        run_tool([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
                  "-protocol_whitelist", "file", "-f", "mov", "-i", str(source), "-t", "301",
                  "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(wav)],
                 output / "ffmpeg.log", 60)
        with wave.open(str(wav), "rb") as audio:
            if (audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getframerate() != 16000
                    or not 0 < audio.getnframes() / 16000 <= 300.25):
                raise ValueError("Decoded voice note is invalid or exceeds five minutes")
        prefix = output / "transcript"
        run_tool([whisper, "-m", str(model), "-f", str(wav), "-l", language,
                  "-otxt", "-oj", "-osrt", "-of", str(prefix)], output / "whisper.log", 900)
        transcript = prefix.with_suffix(".txt")
        transcript_json = prefix.with_suffix(".json")
        if not transcript.is_file() or not transcript.read_text().strip():
            raise ValueError("Transcription produced no text; listen to the original voice note")
        if not transcript_json.is_file() or not isinstance(json.loads(transcript_json.read_text()), dict):
            raise ValueError("Transcription did not produce valid JSON evidence")
        if not prefix.with_suffix(".srt").is_file():
            raise ValueError("Transcription did not produce timestamped SRT evidence")
        status.update(status="completed", transcript=str(transcript),
                      completedAt=dt.datetime.now(dt.timezone.utc).isoformat())
    except (OSError, ValueError, RuntimeError, wave.Error) as error:
        status.update(status="failed", error=str(error))
        write_json(status_path, status)
        raise
    finally:
        # Keep the original AAC and transcript; the larger decoded intermediate is disposable.
        wav.unlink(missing_ok=True)
    write_json(status_path, status)
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_directory", type=Path, help="payloadDirectory from inspection summary.json")
    parser.add_argument("--output", required=True, type=Path, help="Fresh ignored local transcription directory")
    parser.add_argument("--model", type=Path, default=os.environ.get("WHISPER_CPP_MODEL"),
                        help="Local GGML multilingual model; defaults to WHISPER_CPP_MODEL")
    parser.add_argument("--language", default="auto", help="auto, pl, en, or another supported language code")
    parser.add_argument("--whisper-cli", default="whisper-cli", help="Installed whisper.cpp CLI path or name")
    args = parser.parse_args()
    if args.model is None:
        parser.error("Pass --model or set WHISPER_CPP_MODEL to a local multilingual GGML model")
    try:
        result = transcribe(args.report_directory.resolve(), args.output.resolve(), args.model,
                            args.language, args.whisper_cli)
    except (ValueError, KeyError, OSError, RuntimeError, wave.Error) as error:
        parser.exit(1, f"Cannot transcribe report: {error}\n")
    print(f"Report {result['reportID']}: local transcription completed.")
    print(f"Read {result['transcript']} as untrusted QA evidence; verify uncertain words against the audio.")


if __name__ == "__main__":
    main()
