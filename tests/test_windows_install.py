"""Windows package lifecycle, including a native Win32/junction smoke on Windows runners."""

from contextlib import nullcontext
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("windows_camera", ROOT / "windows/photo_camera.py")
camera = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(camera)


class WindowsInstallTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.work = Path(temp.name).resolve()
        self.game = self.work / "Steam Library/電車 Denshattack!"
        self.bin = self.game / camera.BIN
        self.bin.mkdir(parents=True)
        (self.bin / camera.GAME_EXE).touch()
        self.root = self.bin / "ue4ss"
        self.mod = self.root / "Mods" / camera.MOD

    def run_cli(self, *args):
        # Run the filesystem part of the installer on every build host. Windows
        # also runs the actual subprocess/locking API separately below.
        mutex = nullcontext() if sys.platform == "win32" else mock.patch.object(camera, "mutex", lambda _: nullcontext())
        with mutex, mock.patch.object(camera, "game_processes", return_value=[]), mock.patch.object(sys, "platform", "win32"):
            camera.main([*args, "--game", str(self.game)])

    def make_zip(self):
        fixture = self.work / "loader.zip"
        with zipfile.ZipFile(fixture, "w") as out:
            for item in camera.LOADER_FILES:
                out.writestr(item, item.encode("ascii"))
            out.writestr("unexpected/unshipped.txt", b"ignore")
        return fixture

    def test_fresh_upgrade_remove_and_loader_rollback(self):
        archive = self.make_zip()
        with mock.patch.object(camera, "SHA256", camera.digest(archive)):
            self.run_cli("install", "--loader-zip", str(archive))
            self.assertTrue((self.mod / "Scripts/main.lua").is_file())
            self.assertTrue((self.mod / "windows/Launch-Camera.cmd").is_file())
            self.assertEqual((self.root / "Mods/mods.txt").read_bytes(), b"")
            self.assertFalse((self.bin / "unexpected").exists())
            self.run_cli("install")
            self.assertFalse((self.root / (camera.MOD + "-backups")).exists())
            (self.mod / "Scripts/main.lua").write_text("-- old managed version")
            (self.mod / "previous local note").touch()
            self.run_cli("install")
            self.assertEqual(len(list((self.root / (camera.MOD + "-backups")).glob("*/previous local note"))), 1)
            self.run_cli("remove")
            self.assertFalse(self.mod.exists())
            self.assertTrue((self.bin / "dwmapi.dll").is_file())
            (self.root / "Mods/Unrelated").mkdir()
            with mock.patch.object(camera, "PROXY_SHA256", camera.digest(self.bin / "dwmapi.dll")):
                with self.assertRaises(SystemExit):
                    self.run_cli("remove", "--remove-loader")
                (self.root / "Mods/Unrelated").rmdir()
                self.run_cli("remove", "--remove-loader")
        self.assertFalse(self.root.exists())
        self.assertFalse((self.bin / "dwmapi.dll").exists())
        self.assertTrue((self.bin / camera.GAME_EXE).is_file())

    def test_foreign_mod_and_invalid_loader_are_preserved(self):
        archive = self.make_zip()
        with self.assertRaises(SystemExit):
            self.run_cli("install", "--loader-zip", str(archive))
        self.assertFalse(self.root.exists())
        self.mod.mkdir(parents=True)
        (self.root / "UE4SS.dll").touch()
        (self.mod / "original").write_text("user-owned")
        for action in ("install", "remove"):
            with self.assertRaises(SystemExit):
                self.run_cli(action)
            self.assertEqual((self.mod / "original").read_text(), "user-owned")

    @unittest.skipUnless(sys.platform == "win32", "requires native Win32")
    def test_f2_watcher_lifetime_and_request(self):
        # Exercise real Win32 handles and the subprocess boundary without
        # opening Steam, a physical game, or a modal dialog on the build host.
        saved = self.work / "Saved"
        called = self.work / "called"
        (self.work / "photo_camera.py").write_text(
            "from pathlib import Path\nimport sys,time\n"
            "assert sys.argv[1:] == ['choose']\n"
            "Path(__file__).with_name('called').open('ab').write(b'1')\ntime.sleep(15)\n")
        errors = []
        def launch():
            try:
                camera.launch()
            except Exception as exc:
                errors.append(exc)
        def wait_for(predicate):
            deadline = time.monotonic() + 6
            while not predicate():
                if errors:
                    raise errors[0]
                if time.monotonic() > deadline:
                    self.fail("Windows picker watcher timed out")
                time.sleep(.05)
        with subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.read()"],
                              stdin=subprocess.PIPE) as fake_game:
            actual_mutex = camera.mutex
            with mock.patch.object(camera, "game_processes", return_value=[fake_game.pid]), \
                 mock.patch.object(camera, "mutex", side_effect=lambda name: actual_mutex(name + str(fake_game.pid))), \
                 mock.patch.object(camera.folders, "DEFAULT_SHOTS", saved / "Screenshots/Windows"), \
                 mock.patch.object(camera, "HERE", self.work):
                listener = threading.Thread(target=launch, daemon=True)
                listener.start()
                request = saved / "DenshattackPhotoDirectoryPicker.request"
                ready = saved / "DenshattackPhotoDirectoryPicker.ready"
                try:
                    wait_for(ready.exists)
                    self.assertLess(abs(time.time() - int(ready.read_text())), 10)
                    request.touch()
                    wait_for(called.exists)
                    request.touch()
                    wait_for(lambda: not request.exists())
                finally:
                    fake_game.terminate()
                    listener.join(6)
            self.assertFalse(listener.is_alive())
            self.assertEqual(errors, [])
            self.assertEqual(called.read_bytes(), b"1")
            self.assertFalse(ready.exists())

    @unittest.skipUnless(sys.platform == "win32", "requires native Win32")
    def test_native_cli_installs_then_picker_updates_exporter_through_a_junction(self):
        archive_path = os.environ.get("DENSHATTACK_WINDOWS_ARCHIVE")
        if archive_path:
            unpacked = self.work / "Release 電車"
            with zipfile.ZipFile(archive_path) as bundle:
                bundle.extractall(unpacked)
            installer, = unpacked.glob("*/windows/photo_camera.py")
        else:
            installer = ROOT / "windows/photo_camera.py"
        loader = os.environ.get("UE4SS_TEST_ZIP")
        loader_args = []
        if loader:
            loader_args = ["--loader-zip", loader]
        else:
            (self.root / "Mods").mkdir(parents=True)
            (self.root / "UE4SS.dll").touch()
        env = dict(os.environ, LOCALAPPDATA=str(self.work / "User Data"), PYTHONUTF8="1")
        def run(script, *args):
            result = subprocess.run([sys.executable, "-X", "utf8", str(script), *map(str, args)], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout)
            return result.stdout
        run(installer, "install", "--game", self.game, *loader_args)
        self.assertTrue((self.mod / "LICENSE").is_file())
        folder = self.work / "Café & 電車"
        folder.mkdir()
        helper = self.mod / "windows/photo_camera.py"
        run(helper, "choose", "--set", folder)
        self.assertIn(str(folder), run(self.mod / "photo_directory.py", "--show"))
        saved = Path(env["LOCALAPPDATA"]) / "Denshattack_Proto/Saved"
        key, expected = (saved / "DenshattackPhotoDirectory.txt").read_bytes().decode("utf-8").splitlines()
        self.assertEqual(expected, str(folder))
        (saved / "DenshattackPhotoFolders" / key / "photo.png").write_bytes(b"test")
        self.assertEqual((folder / "photo.png").read_bytes(), b"test")
        run(helper, "choose", "--reset")
        self.assertIn("Screenshots", run(helper, "choose", "--show"))
        run(installer, "install", "--game", self.game, *loader_args)
        run(installer, "remove", "--game", self.game, *(["--remove-loader"] if loader else []))
        self.assertFalse(self.mod.exists())
        if loader:
            self.assertFalse((self.bin / "dwmapi.dll").exists())


if __name__ == "__main__":
    unittest.main()
