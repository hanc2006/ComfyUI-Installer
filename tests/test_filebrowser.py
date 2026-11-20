import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FileBrowserInstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.workspace = self.root / "workspace"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        source = (ROOT / "scripts/install_filebrowser.sh").read_text()
        self.script = self.root / "install.sh"
        self.script.write_text(source.replace('workspace="/workspace"', f'workspace="{self.workspace}"'))

        fake_browser = b"""#!/usr/bin/env bash
if [ "$3" = config ]; then
    printf 'database' > "$2"
elif [ "$3" = users ]; then
    printf '%s:%s\\n' "$5" "$6" > "$TEST_USER"
fi
"""
        archive = self.root / "linux-amd64-filebrowser.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            info = tarfile.TarInfo("filebrowser")
            info.size = len(fake_browser)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(fake_browser))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.root / "filebrowser_2.63.23_checksums.txt").write_text(
            f"{digest}  {archive.name}\n"
        )
        self.write_executable(
            "curl",
            '#!/usr/bin/env bash\n'
            'for arg in "$@"; do case "$arg" in https://*) url="$arg";; esac; done\n'
            'cp "$TEST_FIXTURES/${url##*/}" "${@: -1}"\n',
        )
        self.write_executable("uname", '#!/bin/sh\nprintf "x86_64\\n"\n')
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_FIXTURES": str(self.root),
            "TEST_USER": str(self.root / "user"),
        }

    def write_executable(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def run_installer(self):
        return subprocess.run(
            ["bash", str(self.script)], env=self.env, text=True, capture_output=True
        )

    def test_installs_and_preserves_existing_credentials(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        credentials = self.workspace / "filebrowser-credentials.txt"
        self.assertEqual(credentials.read_text(), (self.root / "user").read_text())
        self.assertIn(credentials.read_text().strip(), result.stdout)
        self.assertEqual(credentials.stat().st_mode & 0o777, 0o600)
        database = self.workspace / ".filebrowser/filebrowser.db"
        self.assertEqual(database.stat().st_mode & 0o777, 0o600)
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace", result.stderr)
        self.assertEqual(credentials.read_text(), (self.root / "user").read_text())

    def test_rejects_bad_checksum_without_creating_credentials(self):
        (self.root / "filebrowser_2.63.23_checksums.txt").write_text(
            f"{'0' * 64}  linux-amd64-filebrowser.tar.gz\n"
        )
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum verification failed", result.stderr)
        self.assertFalse((self.workspace / "filebrowser-credentials.txt").exists())
        self.assertFalse((self.workspace / ".filebrowser/filebrowser.db").exists())


if __name__ == "__main__":
    unittest.main()
