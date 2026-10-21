"""Exercise the real scanner's file selection, redaction, and history coverage."""

from pathlib import Path
import secrets
import shutil
import string
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("scan_secrets.py")


@unittest.skipUnless(shutil.which("gitleaks"), "Gitleaks is required for scanner integration checks")
class SecretScanTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(SCRIPT, self.root / "scripts/scan_secrets.py")
        self.git("init", "-q")
        # Generated nonfunctional fixture; never use a real credential in tests.
        alphabet = string.ascii_letters + string.digits
        self.credential = "ghp_" + "".join(secrets.choice(alphabet) for _ in range(36))

    def git(self, *arguments):
        subprocess.run(["git", "-c", "user.name=Scanner Test", "-c",
                        "user.email=scanner@example.invalid", *arguments],
                       cwd=self.root, check=True, capture_output=True)

    def scan(self, *arguments):
        result = subprocess.run(["python3", "scripts/scan_secrets.py", *arguments],
                                cwd=self.root, capture_output=True, text=True)
        self.assertNotIn(self.credential, result.stdout + result.stderr)
        return result

    def test_untracked_file_with_spaces_is_scanned_and_redacted(self):
        (self.root / "private config.txt").write_text(self.credential)
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("private config.txt", result.stdout)

    def test_ignored_local_file_is_excluded_but_tracked_ignored_file_is_scanned(self):
        (self.root / ".gitignore").write_text(".env\n")
        (self.root / ".env").write_text(self.credential)
        self.assertEqual(self.scan().returncode, 0)
        self.git("add", "-f", ".env")
        self.assertEqual(self.scan().returncode, 1)

    def test_deleted_secret_is_detected_in_history(self):
        fixture = self.root / "removed.txt"
        fixture.write_text(self.credential)
        self.git("add", "removed.txt")
        self.git("commit", "-qm", "Fixture")
        fixture.unlink()
        self.git("add", "-u")
        self.git("commit", "-qm", "Remove fixture")
        self.assertEqual(self.scan().returncode, 0)
        result = self.scan("--history")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Local Git history", result.stdout)


if __name__ == "__main__":
    unittest.main()
