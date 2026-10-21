#!/usr/bin/env python3
"""Exercise report ingestion with real Codex in an isolated, disposable repository."""

import argparse
import datetime as dt
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Run a real read-only Codex investigation")
    parser.add_argument("--output", type=Path, default=ROOT / "output" / "inbox" / "verification")
    args = parser.parse_args()
    if not args.live:
        parser.error("Pass --live to explicitly run the Codex integration check.")
    base = args.output.resolve() / str(uuid.uuid4())
    repository = base / "repository"
    incoming = base / "Incoming"
    repository.mkdir(parents=True)
    incoming.mkdir()
    (repository / "AGENTS.md").write_text(
        "This is a disposable MZ Inbox integration-test repository. There is no app or bug to fix. "
        "When investigating the setup-check report, verify the supplied report files are readable "
        "and end with INBOX_PIPELINE_VERIFIED. Do not access other repositories, external providers, "
        "or make changes.\n")
    (repository / "README.md").write_text("MZ Inbox pipeline verification fixture.\n")
    subprocess.run(["git", "init", "--quiet", str(repository)], check=True)
    subprocess.run(["git", "-C", str(repository), "add", "AGENTS.md", "README.md"], check=True)
    subprocess.run(["git", "-C", str(repository), "-c", "user.name=MZ Inbox Test",
                    "-c", "user.email=inbox-test@example.invalid", "commit", "--quiet", "-m", "test fixture"], check=True)
    report_id = str(uuid.uuid4())
    manifest = {"format": "bug-reporter", "schemaVersion": 2, "id": report_id,
                "capturedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                "title": "MZ Inbox setup check", "description": "Synthetic delivery check. No product defect is reported.",
                "metadata": {"app": "MZ Inbox Setup Check", "bundleIdentifier": "com.example.mzinbox.verify",
                             "version": "1.0", "build": "1"}, "attachments": [], "attachmentStatus": {}}
    archive = incoming / f"bug-report-{report_id}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
        output.writestr("report.json", json.dumps(manifest))
        output.writestr("report.txt", "MZ Inbox setup check\nSynthetic delivery check; no product defect.\n")
    codex = shutil.which("codex")
    if not codex:
        raise RuntimeError("Codex CLI is not installed.")
    config = {"schemaVersion": 1, "inboxPath": str(incoming), "statusPath": str(base / "Status"),
              "statePath": str(base / "state"), "codexPath": codex, "pollSeconds": 1,
              "routes": [{"bundleIdentifier": "com.example.mzinbox.verify", "name": "Setup check",
                          "repository": str(repository), "mode": "diagnose", "enabled": True}]}
    config_path = base / "config.json"
    config_path.write_text(json.dumps(config, indent=2))
    worker = ROOT / "Tools" / "MZInbox" / "inbox.py"
    command = [shutil.which("python3"), str(worker), "--config", str(config_path), "scan"]
    for _ in range(2):
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
        time.sleep(1)
    snapshot = json.loads((base / "state" / "queue.json").read_text())
    jobs = [job for job in snapshot["jobs"] if job.get("reportID") == report_id]
    if len(jobs) != 1 or jobs[0]["status"] != "completed":
        raise RuntimeError(f"Report did not complete. Inspect {base / 'state' / 'queue.json'}")
    job = jobs[0]
    result = Path(job["resultPath"]).read_text()
    if "INBOX_PIPELINE_VERIFIED" not in result or not job.get("threadID"):
        raise RuntimeError("Codex did not return a verified result and thread ID.")
    original_thread = job["threadID"]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    repeated = json.loads((base / "state" / "queue.json").read_text())
    if len(repeated["jobs"]) != 1 or repeated["jobs"][0]["threadID"] != original_thread:
        raise RuntimeError("Duplicate scan changed the report or launched another thread.")
    dirty = subprocess.check_output(["git", "-C", str(repository), "status", "--porcelain"], text=True)
    if dirty:
        raise RuntimeError("The investigation changed the fixture repository.")
    statuses = list((base / "Status").glob("*.json"))
    if not statuses or not any(json.loads(path.read_text()).get("status") == "completed" for path in statuses):
        raise RuntimeError("No completed phone status receipt was written.")
    receipt = {"status": "passed", "reportID": report_id, "threadID": original_thread,
               "directory": str(base), "resultPath": job["resultPath"], "duplicateScan": "same-thread",
               "repository": "unchanged", "phoneStatus": "completed", "physicalPhone": "not-exercised"}
    (base / "verification-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
