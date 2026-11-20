import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SageAttentionScriptsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        (self.root / "venv" / "bin").mkdir(parents=True)
        (self.root / "bin").mkdir()
        self.home = self.root / "home"
        filebrowser_dir = self.home / ".local" / "share" / "filebrowser"
        filebrowser_dir.mkdir(parents=True)
        shutil.copy(ROOT / "install.sh", self.root)
        shutil.copy(ROOT / "scripts" / "run_services.sh", self.root / "scripts")
        self.log = self.root / "commands"
        self.env = {**os.environ, "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
                    "TEST_LOG": str(self.log), "HOME": str(self.home)}
        self.write_executable(self.root / "bin" / "python3", "#!/bin/bash\nexit 0\n")
        self.write_executable(
            self.root / "venv" / "bin" / "python",
            '#!/bin/bash\nprintf "python %s\\n" "$*" >> "$TEST_LOG"\n'
            'if [[ "$*" == *"git+https://github.com/thu-ml/SageAttention.git@"* ]]; then\n'
            '  exit "${FAIL_SAGE_BUILD:-0}"\nfi\n',
        )
        self.write_executable(
            self.root / "venv" / "bin" / "comfy",
            '#!/bin/bash\nprintf "comfy %s\\n" "$*" >> "$TEST_LOG"\n'
            'if [[ "$*" == *"launch"* ]]; then\n'
            '  trap "exit 0" TERM\n'
            '  while :; do sleep 0.1; done\nfi\n',
        )
        (filebrowser_dir / "filebrowser.db").touch()
        self.write_executable(
            filebrowser_dir / "filebrowser",
            '#!/bin/bash\nprintf "filebrowser %s\\n" "$*" >> "$TEST_LOG"\n'
            'while :; do sleep 1; done\n',
        )
        (self.root / "venv" / "bin" / "activate").write_text(
            f'export PATH="{self.root}/venv/bin:$PATH"\n'
        )
        (self.root / "ComfyUI").mkdir()
        self.addCleanup(self.stop_services)

    def write_executable(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def configure(self, sage):
        (self.root / "scripts" / "config.sh").write_text(
            f'INSTALL_DIR="{self.root}"\nVENV_DIR="$INSTALL_DIR/venv"\n'
            f'COMFYUI_DIR="$INSTALL_DIR/ComfyUI"\n'
            f'SAGE_ATTENTION="{sage}"\nCOMFYUI_PORT=8188\nFILEBROWSER_PORT=8080\n'
        )

    def stop_services(self):
        state_dir = self.root / ".run_services"
        for name in ("comfyui", "filebrowser"):
            pid_file = state_dir / f"{name}.pid"
            if not pid_file.exists():
                continue
            try:
                os.killpg(int(pid_file.read_text()), 15)
            except (ProcessLookupError, ValueError):
                pass

    def run_script(self, script, *args, **env):
        return subprocess.run(
            ["bash", str(self.root / script), *args], env={**self.env, **env},
            text=True, capture_output=True,
        )

    def test_nvidia_installs_and_enables_sage(self):
        self.configure("true")
        self.assertEqual(self.run_script("install.sh").returncode, 0)
        self.assertEqual(self.run_script("scripts/run_services.sh").returncode, 0)
        log = self.log.read_text()
        self.assertLess(log.index(" install --nvidia"), log.index("git+https://github.com/thu-ml/SageAttention.git@"))
        self.assertIn("--no-build-isolation", log)
        self.assertIn("from sageattention import sageattn, _qattn_sm80", log)
        self.assertIn("--use-sage-attention", log)

    def test_disabled_keeps_default_attention(self):
        self.configure("false")
        self.assertEqual(self.run_script("install.sh").returncode, 0)
        self.assertEqual(self.run_script("scripts/run_services.sh").returncode, 0)
        log = self.log.read_text()
        self.assertIn(" install --nvidia", log)
        self.assertNotIn("git+https://github.com/thu-ml/SageAttention.git@", log)
        self.assertNotIn("--use-sage-attention", log)

    def test_build_failure_is_not_reported_as_success(self):
        self.configure("true")
        result = self.run_script("install.sh", FAIL_SAGE_BUILD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("installation complete", result.stdout)

    def test_invalid_setting_fails(self):
        self.configure("yes")
        for script in ("install.sh", "scripts/run_services.sh"):
            result = self.run_script(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SAGE_ATTENTION must be true or false", result.stderr)

    def test_check_starts_services_and_service_argument_restarts_only_that_service(self):
        self.configure("false")
        result = self.run_script("scripts/run_services.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("comfyui: not running", result.stdout)
        self.assertIn("filebrowser: not running", result.stdout)

        result = self.run_script("scripts/run_services.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("comfyui: in process", result.stdout)
        self.assertIn("filebrowser: in process", result.stdout)

        comfy_runs_before = self.log.read_text().count("comfy --workspace=")
        filebrowser_runs_before = self.log.read_text().count("filebrowser -d")
        result = self.run_script("scripts/run_services.sh", "comfyui")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().count("comfy --workspace="), comfy_runs_before + 1)
        self.assertEqual(self.log.read_text().count("filebrowser -d"), filebrowser_runs_before)


if __name__ == "__main__":
    unittest.main()
