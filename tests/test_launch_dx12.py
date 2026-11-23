import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform.startswith("linux"), "Proton launch wrapper runs on Linux")
class LauncherTests(unittest.TestCase):
    def test_wrapper_preserves_steam_process_and_arguments(self):
        source = Path(__file__).resolve().parents[1] / "mod/launch_dx12.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            launcher = Path(shutil.copy(source, root))
            game = root / "Denshattack_Proto.exe"
            game.write_text(f"#!{sys.executable}\n" + """
import json, os, sys
from pathlib import Path
Path(os.environ['GAME_LOG']).write_text(json.dumps([os.getpid(), *sys.argv[1:]]))
sys.exit(37)
""")
            game.chmod(0o755)
            picker = root / "photo_directory.py"
            picker.write_text("""
import json, os, sys
from pathlib import Path
Path(os.environ['PICKER_LOG']).write_text(json.dumps(sys.argv[1:]))
""")
            for switches, expected in (([], ["-dx12", "-sm5"]), (["--keep-renderer"], ["-dx11", "-sm6"])):
                with self.subTest(switches=switches):
                    game_log = root / "game"
                    picker_log = root / "picker"
                    env = {**os.environ, "GAME_LOG": str(game_log), "PICKER_LOG": str(picker_log)}
                    child = subprocess.Popen([sys.executable, str(launcher), *switches, str(game),
                                              "-dx11", "-sm6", "spaces and $quotes"], env=env)
                    self.assertEqual(child.wait(timeout=4), 37)
                    self.assertEqual(json.loads(game_log.read_text()), [child.pid, *expected, "spaces and $quotes"])
                    deadline = time.monotonic() + 3
                    while not picker_log.exists() and time.monotonic() < deadline:
                        time.sleep(0.025)
                    self.assertEqual(json.loads(picker_log.read_text()), ["--watch", "--parent-pid", str(child.pid)])
                    picker_log.unlink()

    def test_unrelated_command_passes_through(self):
        launcher = Path(__file__).resolve().parents[1] / "mod/launch_dx12.py"
        result = subprocess.run([sys.executable, str(launcher), "--keep-renderer", sys.executable,
                                 "-c", "import sys; print(sys.argv[1])", "-sm6"],
                                capture_output=True, text=True, timeout=3)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-sm6\n", ""))


if __name__ == "__main__":
    unittest.main()
