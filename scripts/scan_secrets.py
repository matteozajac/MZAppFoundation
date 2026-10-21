#!/usr/bin/env python3
"""Scan publishable files (and optionally Git history) without printing matches."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def scan(arguments, report, label):
    result = subprocess.run(
        ["gitleaks", *arguments, "--redact=100", "--no-banner", "--no-color",
         "--ignore-gitleaks-allow", "--exit-code", "10",
         "--report-format", "json", "--report-path", str(report)],
        cwd=ROOT, capture_output=True,
    )
    if result.returncode not in (0, 10):
        raise RuntimeError(f"{label}: Gitleaks failed (exit {result.returncode}); scan incomplete")
    findings = json.loads(report.read_text()) if report.exists() else []
    print(f"{label}: {len(findings)} finding(s)")
    for item in findings:
        # Never print Match, Secret, commit messages, or raw scanner output.
        location = str(item.get("File", "unknown"))
        marker = "/snapshot/"
        if marker in location:
            location = location.split(marker, 1)[1]
        print(json.dumps({"file": location, "line": item.get("StartLine"),
                          "rule": item.get("RuleID"),
                          "commit": item.get("Commit", "")[:12]}))
    return bool(findings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="Also scan every locally available Git ref")
    args = parser.parse_args()
    if not shutil.which("gitleaks"):
        parser.exit(2, "Install Gitleaks first (macOS: brew install gitleaks).\n")
    try:
        with tempfile.TemporaryDirectory(prefix="mzfoundation-secret-scan-") as folder:
            temporary = Path(folder)
            snapshot = temporary / "snapshot"
            snapshot.mkdir()
            names = subprocess.check_output(
                ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
            ).split(b"\0")
            count = 0
            for name in set(names) - {b""}:
                relative = Path(name.decode("utf-8"))
                if relative.is_absolute() or ".." in relative.parts:
                    raise RuntimeError("Unsafe Git path; scan incomplete")
                source = ROOT / relative
                if source.is_symlink() or any(parent.is_symlink() for parent in source.parents if parent != ROOT):
                    raise RuntimeError(f"Symlink requires manual audit: {relative}")
                if not source.exists():
                    continue  # A tracked deletion is absent from the proposed tree.
                if not source.is_file():
                    raise RuntimeError(f"Non-file requires manual audit: {relative}")
                destination = snapshot / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                count += 1
            print(f"Scanning {count} tracked and non-ignored untracked files")
            found = scan(["dir", str(snapshot)], temporary / "files.json", "Working tree")
            if args.history:
                found |= scan(["git", str(ROOT), "--log-opts=--all --full-history"],
                              temporary / "history.json", "Local Git history")
            return 1 if found else 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        # Exception messages above contain only paths/status; raw subprocess output is never used.
        print(f"Secret scan incomplete: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
