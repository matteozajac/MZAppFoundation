#!/usr/bin/env python3
"""Inspect a BugReporter ZIP locally; never execute its contents or upload data."""
import argparse
import ctypes
from contextlib import closing
import datetime as dt
import json
import math
from pathlib import Path, PurePosixPath
import re
import shutil
import sqlite3
import stat
import sys
import uuid
import zipfile

MAX_FILES = 100
MAX_BYTES = 512 * 1024 * 1024
MAX_DECODED = 256 * 1024 * 1024
MAX_DIAGNOSTICS = 1024 * 1024
TABLES = (
    "ZLOGGERSESSIONENTITY", "ZLOGGERMESSAGEENTITY", "ZNETWORKTASKENTITY",
    "ZNETWORKREQUESTENTITY", "ZNETWORKRESPONSEENTITY",
    "ZNETWORKTRANSACTIONMETRICSENTITY", "ZLOGGERBLOBHANDLEENTITY",
)
LEVELS = {1: "trace", 2: "debug", 3: "info", 4: "notice", 5: "warning", 6: "error", 7: "critical"}


def extract(source, destination):
    """Validate the complete inventory before creating any extracted files."""
    with zipfile.ZipFile(source) as archive:
        members = archive.infolist()
        if len(members) > MAX_FILES or sum(item.file_size for item in members) > MAX_BYTES:
            raise ValueError("Archive exceeds report extraction limits")
        seen = set()
        for item in members:
            name = item.filename
            parts = PurePosixPath(name).parts
            mode = stat.S_IFMT(item.external_attr >> 16)
            if (not parts or name.startswith("/") or "\\" in name or ":" in name
                    or any(part in ("..", ".", "") for part in name.rstrip("/").split("/"))
                    or mode not in (0, stat.S_IFREG, stat.S_IFDIR) or item.flag_bits & 1):
                raise ValueError("Unsafe ZIP entry")
            normalized = name.rstrip("/").casefold()
            if normalized in seen:
                raise ValueError("Duplicate ZIP entry")
            seen.add(normalized)
        destination.mkdir(parents=True, exist_ok=False)
        try:
            for item in members:
                target = destination.joinpath(*PurePosixPath(item.filename).parts)
                if item.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(item) as incoming, target.open("xb") as outgoing:
                        shutil.copyfileobj(incoming, outgoing)
        except Exception:
            shutil.rmtree(destination)
            raise


def read_manifest(root):
    manifests = [p for p in root.rglob("report.json") if "__MACOSX" not in p.relative_to(root).parts]
    if len(manifests) != 1:
        raise ValueError("Expected exactly one report.json")
    path = manifests[0]
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("Report manifest is too large")
    report = json.loads(path.read_text())
    if not isinstance(report, dict):
        raise ValueError("Invalid report manifest")
    legacy = "format" not in report and "schemaVersion" not in report
    if not legacy and (report.get("format") != "bug-reporter" or report.get("schemaVersion") not in (1, 2)):
        raise ValueError("Unsupported report format/version; inspect manifest before updating the reader")
    uuid.UUID(report["id"])
    if not isinstance(report.get("metadata"), dict) or not isinstance(report.get("title"), str):
        raise ValueError("Missing report metadata/title")
    if not (path.parent / "report.txt").is_file():
        raise ValueError("Missing report.txt QA notes")
    names = report.get("attachments", [])
    if not isinstance(names, list) or any(not isinstance(n, str) or not n or n in (".", "..")
                                        or any(c in n for c in "/\\:") for n in names):
        raise ValueError("Invalid attachment names")
    if len(set(n.casefold() for n in names)) != len(names):
        raise ValueError("Duplicate attachment names")
    warnings = ["Legacy report: no versioned attachment status"] if legacy else []
    for name in names:
        if not (path.parent / name).is_file():
            warnings.append(f"Declared attachment is missing: {name}")
    statuses = report.get("attachmentStatus", {})
    if not isinstance(statuses, dict) or any(value not in ("included", "excluded", "unavailable") for value in statuses.values()):
        raise ValueError("Invalid attachment status")
    for kind, suffix in (("logs", ".pulse"), ("screenshot", ".png"), ("video", ".mp4")):
        present = any(n.endswith(suffix) and (path.parent / n).is_file() for n in names)
        if statuses.get(kind) == "included" and not present:
            warnings.append(f"{kind} marked included but no matching attachment exists")
        elif statuses.get(kind) in ("excluded", "unavailable") and present:
            warnings.append(f"{kind} status conflicts with attachment inventory")
    return path.parent, report, warnings


def inspect_voice_note(root, report, warnings):
    """Resolve only the explicit voice note; the silent ReplayKit MP4 is unrelated."""
    note = report.get("voiceNote")
    status = report.get("attachmentStatus", {}).get("audio")
    audio_names = [name for name in report.get("attachments", []) if name.lower().endswith(".m4a")]
    if note is None:
        if status == "included" or audio_names or (root / "voice-note.m4a").exists():
            warnings.append("Audio exists or is marked included but voiceNote metadata is missing; inspect before transcribing")
        elif status == "unavailable":
            warnings.append("Audio was unavailable; read attachmentErrors before interpreting missing speech")
        if not report["title"].strip():
            warnings.append("Report has no title or usable voice note; QA's issue description is missing")
        return None
    if not isinstance(note, dict):
        raise ValueError("Invalid voiceNote metadata")
    name = note.get("filename")
    if (not isinstance(name, str) or not name or name in (".", "..")
            or any(char in name for char in "/\\:") or not name.lower().endswith(".m4a")):
        raise ValueError("Invalid voiceNote filename; expected a local M4A basename")
    path = root / name
    available = True
    if name not in report.get("attachments", []) or not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        warnings.append("Voice note is missing, empty, or absent from the declared attachment inventory")
        available = False
    if status != "included":
        warnings.append("Voice note metadata conflicts with audio attachment status")
        available = False
    duration = note.get("duration")
    if (isinstance(duration, bool) or not isinstance(duration, (int, float))
            or not math.isfinite(duration) or not 0 < duration <= 300):
        warnings.append("Voice note duration is invalid; expected more than zero and at most 300 seconds")
        available = False
    if (note.get("codec") != "aac" or note.get("sampleRate") != 24000
            or note.get("channels") != 1):
        warnings.append("Voice note encoding metadata is unsupported; expected mono AAC at 24 kHz")
        available = False
    if note.get("transcriptionRequired") is not True:
        warnings.append("Voice note is missing transcriptionRequired=true; transcribe available speech before diagnosis")
    if not report["title"].strip() and not available:
        warnings.append("Report has no title or usable voice note; QA's issue description is missing")
    return {
        **note, "path": str(path), "available": available,
        "transcriptionRequired": True, "mediaVerified": False,
    }


def inspect_diagnostics(root, report, warnings):
    """Read a bounded technical snapshot separately from the bug-report manifest and QA input."""
    name = 'diagnostics.json'
    path = root / name
    declared = name in report.get('attachments', [])
    status = report.get('attachmentStatus', {}).get('diagnostics')
    present = path.is_file() and not path.is_symlink()
    if not declared and not present and status is None:
        return None
    result = {'path': str(path), 'available': False, 'formatValid': False, 'backendDeliveryVerified': False}
    if status == 'included' and not (declared and present):
        warnings.append('Diagnostics marked included but no declared snapshot exists')
    elif present and (status != 'included' or not declared):
        warnings.append('Diagnostics snapshot conflicts with its attachment status or inventory')
    elif status == 'unavailable':
        warnings.append('Diagnostics snapshot was unavailable; app/provider runtime state is not evidenced by this report')
    if not (declared and present and status == 'included'):
        return result
    try:
        if path.stat().st_size > MAX_DIAGNOSTICS:
            raise ValueError('Diagnostic size limit')
        def reject_constant(_):
            raise ValueError('Invalid JSON number')
        snapshot = json.loads(path.read_text(), parse_constant=reject_constant)
        if (not isinstance(snapshot, dict) or snapshot.get('format') != 'mzappfoundation-diagnostics'
                or type(snapshot.get('schemaVersion')) is not int or snapshot['schemaVersion'] != 1):
            raise ValueError('Unsupported diagnostic format')
        pending = [(snapshot, 0)]
        count = 0
        sensitive = ('token', 'password', 'secret', 'authorization', 'cookie', 'receipt', 'transaction',
                     'email', 'phone', 'userid', 'prompt', 'transcript', 'payload', 'apikey', 'dsn')
        while pending:
            value, depth = pending.pop()
            count += 1
            if depth > 16 or count > 20_000:
                raise ValueError('Diagnostic structure limit')
            if isinstance(value, dict):
                if len(value) > 128:
                    raise ValueError('Diagnostic object limit')
                for key, child in value.items():
                    if len(key) > 128 or any(word in key.lower().replace('_', '') for word in sensitive):
                        raise ValueError('Private diagnostic field')
                    pending.append((child, depth + 1))
            elif isinstance(value, list):
                if len(value) > 1000:
                    raise ValueError('Diagnostic array limit')
                pending.extend((child, depth + 1) for child in value)
            elif isinstance(value, str) and len(value) > 2048:
                raise ValueError('Diagnostic string limit')
        result.update(available=True, formatValid=True, schemaVersion=1)
    except (ValueError, OSError, UnicodeError, RecursionError):
        # Never echo an arbitrary payload or parser error containing report data.
        warnings.append('Diagnostics snapshot is malformed, unsupported, private, or exceeds limits; inspect locally before using it')
    return result


def lzfse(data, limit=MAX_DECODED):
    if sys.platform != "darwin":
        raise RuntimeError("Pulse LZFSE decoding requires macOS libcompression; ZIP and notes are still available")
    library = ctypes.CDLL("/usr/lib/libcompression.dylib")
    decode = library.compression_decode_buffer
    decode.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    decode.restype = ctypes.c_size_t
    source = ctypes.create_string_buffer(data)
    size = min(max(len(data) * 4, 65536), limit)
    while size:
        output = ctypes.create_string_buffer(size)
        count = decode(output, size, source, len(data), None, 0x801)  # COMPRESSION_LZFSE
        if 0 < count < size:
            return output.raw[:count]
        if size == limit:
            break
        size = min(size * 2, limit)
    raise ValueError("Invalid LZFSE data or decoded data exceeds limit")


def connect_readonly(path):
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
    connection.execute("PRAGMA query_only=ON")
    connection.execute("PRAGMA trusted_schema=OFF")
    connection.row_factory = sqlite3.Row
    return connection


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def inspect_pulse(source, output):
    output.mkdir()
    blobs = output / "blobs"
    blobs.mkdir()
    decoded_total = 0
    with closing(connect_readonly(source)) as archive:
        rows = archive.execute("SELECT ZKEY, ZDATA FROM ZPULSEBLOBENTITY")
        seen = set()
        for key, data in rows:
            if key in seen:
                raise ValueError("Duplicate Pulse archive key")
            seen.add(key)
            if key == "database":
                database = lzfse(data)
                decoded_total += len(database)
                (output / "logs.sqlite").write_bytes(database)
            elif key == "info":
                write_json(output / "info.json", json.loads(data))
            elif isinstance(key, str) and re.fullmatch(r"[0-9a-fA-F]{40}", key):
                (blobs / key.lower()).write_bytes(data)
        if "database" not in seen:
            raise ValueError("Pulse archive has no database")
    counts = {}
    warnings = []
    with closing(connect_readonly(output / "logs.sqlite")) as database:
        schema = database.execute("SELECT name, sql FROM sqlite_master WHERE type='table'").fetchall()
        write_json(output / "schema.json", [dict(row) for row in schema])
        available = {row["name"] for row in schema}
        if not {"ZLOGGERMESSAGEENTITY", "ZNETWORKTASKENTITY"} <= available:
            raise ValueError("Unsupported Pulse schema; inspect schema.json")
        for table in TABLES:
            if table not in available:
                continue
            count = database.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
            if count > 100000:
                raise ValueError("Pulse table exceeds inspection row limit; query logs.sqlite selectively")
            counts[table] = count
            with (output / (table.lower() + ".jsonl")).open("w") as stream:
                for row in database.execute(f'SELECT * FROM "{table}" ORDER BY Z_PK'):
                    record = dict(row)
                    if table == "ZLOGGERBLOBHANDLEENTITY":
                        key = bytes(record["ZKEY"]).hex()
                        raw = record.get("ZINLINEDATA")
                        if raw is None and (blobs / key).exists():
                            raw = (blobs / key).read_bytes()
                        if raw is not None:
                            body = bytes(raw) if record.get("ZISUNCOMPRESSED") else lzfse(raw)
                            decoded_total += len(body)
                            if decoded_total > MAX_DECODED:
                                raise ValueError("Decoded Pulse data exceeds inspection limit")
                            body_path = blobs / (key + ".body")
                            body_path.write_bytes(body)
                            record["decodedBody"] = str(body_path.relative_to(output))
                        else:
                            warnings.append(f"Missing Pulse body for handle {record['Z_PK']}")
                    if "ZCREATEDAT" in record and isinstance(record["ZCREATEDAT"], (float, int)):
                        record["createdAtUTC"] = (dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(seconds=record["ZCREATEDAT"])).isoformat()
                    if table == "ZLOGGERMESSAGEENTITY":
                        record["levelName"] = LEVELS.get(record.get("ZLEVEL"), "unknown")
                    for key, value in list(record.items()):
                        if isinstance(value, bytes):
                            # Preserve UUIDs/body keys; large blobs are available via SQLite/body files.
                            record[key] = {"hex": value.hex()} if len(value) <= 64 else {"byteCount": len(value)}
                    stream.write(json.dumps(record, ensure_ascii=False) + "\n")
    return {"directory": str(output), "tableCounts": counts, "warnings": warnings}


def inspect(source, output):
    if output.exists():
        raise ValueError("Output directory already exists; choose a fresh destination")
    extract(source, output / "attachments")
    root, report, warnings = read_manifest(output / "attachments")
    voice_note = inspect_voice_note(root, report, warnings)
    diagnostics = inspect_diagnostics(root, report, warnings)
    pulse_results = []
    for name in report.get("attachments", []):
        path = root / name
        if path.suffix == ".pulse" and path.is_file():
            try:
                pulse_results.append(inspect_pulse(path, output / ("pulse-" + str(len(pulse_results) + 1))))
            except (RuntimeError, ValueError, sqlite3.Error, OSError) as error:
                warnings.append(f"Pulse could not be fully decoded: {error}")
    summary = {
        "reportID": report["id"], "schemaVersion": report.get("schemaVersion", 0),
        "payloadDirectory": str(root), "metadata": report["metadata"],
        "capturedAt": report.get("capturedAt"), "screenshotCapturedAt": report.get("screenshotCapturedAt"),
        "recordingDuration": report.get("recordingDuration"), "logScope": report.get("logScope"),
        "attachmentStatus": report.get("attachmentStatus", {}), "attachmentErrors": report.get("attachmentErrors", {}),
        "files": [{"path": str(p.relative_to(root)), "bytes": p.stat().st_size} for p in sorted(root.rglob("*")) if p.is_file()],
        "pulse": pulse_results, "warnings": warnings,
        "voiceNote": voice_note,
        "diagnostics": diagnostics,
    }
    write_json(output / "summary.json", summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", required=True, type=Path, help="Fresh local directory (use the target project's ignored artifacts directory)")
    args = parser.parse_args()
    try:
        summary = inspect(args.archive.resolve(), args.output.resolve())
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Cannot inspect report: {error}\n")
    # Keep private QA text, headers, URLs and bodies out of the terminal by default.
    print(f"Report {summary['reportID']}: {len(summary['files'])} files, {len(summary['pulse'])} decoded Pulse archive(s)")
    print(f"Read {args.output.resolve() / 'summary.json'} and the report notes next.")
    if summary["voiceNote"] and summary["voiceNote"]["available"]:
        print("Voice note requires local Mac transcription; use the bundled transcribe_report.py helper.")
    if summary["warnings"]:
        print("Inspection has warnings; read summary.json before drawing conclusions.")


if __name__ == "__main__":
    main()
