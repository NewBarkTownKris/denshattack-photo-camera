import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform.startswith("linux"), "Proton launch wrapper runs on Linux")
class LauncherTests(unittest.TestCase):
    def test_steam_reaper_can_exit_with_picker_running(self):
        source = Path(__file__).resolve().parents[1] / "mod/launch_dx12.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            launcher = Path(shutil.copy(source, root))
            reaper = root / "reaper.py"
            reaper.write_text("""
import os, subprocess, sys
status = subprocess.run(sys.argv[1:]).returncode
while True:
    try:
        os.waitpid(-1, 0)
    except ChildProcessError:
        break
sys.exit(status)
""")
            game = root / "Denshattack_Proto.exe"
            game.write_text(f"#!{sys.executable}\n" + """
import json, os, sys
from pathlib import Path
Path(os.environ['GAME_LOG']).write_text(json.dumps([os.getppid(), *sys.argv[1:]]))
sys.exit(37)
""")
            game.chmod(0o755)
            picker = root / "photo_directory.py"
            picker.write_text("""
import json, os, sys, time
from pathlib import Path
Path(os.environ['PICKER_LOG']).write_text(json.dumps([os.getpid(), *sys.argv[1:]]))
watched = Path('/proc') / sys.argv[-1]
deadline = time.monotonic() + 8
while watched.exists() and time.monotonic() < deadline:
    time.sleep(0.02)
""")
            for switches, expected in (([], ["-dx12", "-sm5"]), (["--keep-renderer"], ["-dx11", "-sm6"])):
                with self.subTest(switches=switches):
                    game_log = root / "game"
                    picker_log = root / "picker"
                    env = {**os.environ, "GAME_LOG": str(game_log), "PICKER_LOG": str(picker_log)}
                    child = subprocess.Popen([sys.executable, str(launcher), *switches, sys.executable, str(reaper), str(game),
                                              "-dx11", "-sm6", "spaces and $quotes"], env=env)
                    try:
                        self.assertEqual(child.wait(timeout=4), 37)
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait()
                    reaper_pid, *game_args = json.loads(game_log.read_text())
                    watcher_pid, *watcher_args = json.loads(picker_log.read_text())
                    self.assertEqual(game_args, [*expected, "spaces and $quotes"])
                    self.assertEqual(watcher_args, ["--watch", "--parent-pid", str(reaper_pid)])
                    self.assertNotEqual(reaper_pid, child.pid)
                    self.assertFalse(Path(f"/proc/{watcher_pid}").exists())
                    picker_log.unlink()

    def test_steam_stop_signal_reaches_game_and_reaps_watcher(self):
        source = Path(__file__).resolve().parents[1] / "mod/launch_dx12.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            launcher = Path(shutil.copy(source, root))
            game = root / "Denshattack_Proto.exe"
            game.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(8)\n")
            game.chmod(0o755)
            (root / "photo_directory.py").write_text("""
import os, sys, time
from pathlib import Path
Path("pids").write_text(f"{sys.argv[-1]} {os.getpid()}")
deadline = time.monotonic() + 8
while Path("/proc", sys.argv[-1]).exists() and time.monotonic() < deadline:
    time.sleep(0.02)
""")
            child = subprocess.Popen([sys.executable, str(launcher), str(game)], cwd=root)
            try:
                deadline = time.monotonic() + 3
                while not (root / "pids").exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                game_pid, watcher_pid = (root / "pids").read_text().split()
                child.terminate()
                self.assertEqual(child.wait(timeout=3), -signal.SIGTERM)
                self.assertFalse(Path("/proc", game_pid).exists())
                self.assertFalse(Path("/proc", watcher_pid).exists())
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()

    def test_unrelated_command_passes_through(self):
        launcher = Path(__file__).resolve().parents[1] / "mod/launch_dx12.py"
        result = subprocess.run([sys.executable, str(launcher), "--keep-renderer", sys.executable,
                                 "-c", "import sys; print(sys.argv[1])", "-sm6"],
                                capture_output=True, text=True, timeout=3)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-sm6\n", ""))


if __name__ == "__main__":
    unittest.main()
