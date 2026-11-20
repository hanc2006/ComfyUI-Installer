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
        shutil.copy(ROOT / "install.sh", self.root)
        shutil.copy(ROOT / "scripts" / "run_comfyui.sh", self.root / "scripts")
        self.log = self.root / "commands"
        self.env = {**os.environ, "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
                    "TEST_LOG": str(self.log)}
        self.write_executable(self.root / "bin" / "python3", "#!/bin/bash\nexit 0\n")
        self.write_executable(
            self.root / "venv" / "bin" / "python",
            '#!/bin/bash\nprintf "python %s\\n" "$*" >> "$TEST_LOG"\n'
            'if [[ "$*" == *"git+https://github.com/thu-ml/SageAttention.git@"* ]]; then\n'
            '  exit "${FAIL_SAGE_BUILD:-0}"\nfi\n',
        )
        self.write_executable(
            self.root / "venv" / "bin" / "comfy",
            '#!/bin/bash\nprintf "comfy %s\\n" "$*" >> "$TEST_LOG"\n',
        )
        (self.root / "venv" / "bin" / "activate").write_text(
            f'export PATH="{self.root}/venv/bin:$PATH"\n'
        )
        (self.root / "ComfyUI").mkdir()

    def write_executable(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def configure(self, sage):
        (self.root / "scripts" / "config.sh").write_text(
            f'INSTALL_DIR="{self.root}"\nVENV_DIR="$INSTALL_DIR/venv"\n'
            f'COMFYUI_DIR="$INSTALL_DIR/ComfyUI"\n'
            f'SAGE_ATTENTION="{sage}"\nCOMFYUI_PORT=8188\n'
        )

    def run_script(self, script, **env):
        return subprocess.run(
            ["bash", str(self.root / script)], env={**self.env, **env},
            text=True, capture_output=True,
        )

    def test_nvidia_installs_and_enables_sage(self):
        self.configure("true")
        self.assertEqual(self.run_script("install.sh").returncode, 0)
        self.assertEqual(self.run_script("scripts/run_comfyui.sh").returncode, 0)
        log = self.log.read_text()
        self.assertLess(log.index(" install --nvidia"), log.index("git+https://github.com/thu-ml/SageAttention.git@"))
        self.assertIn("--no-build-isolation", log)
        self.assertIn("from sageattention import sageattn, _qattn_sm80", log)
        self.assertIn("--use-sage-attention", log)

    def test_disabled_keeps_default_attention(self):
        self.configure("false")
        self.assertEqual(self.run_script("install.sh").returncode, 0)
        self.assertEqual(self.run_script("scripts/run_comfyui.sh").returncode, 0)
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
        for script in ("install.sh", "scripts/run_comfyui.sh"):
            result = self.run_script(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SAGE_ATTENTION must be true or false", result.stderr)


if __name__ == "__main__":
    unittest.main()
