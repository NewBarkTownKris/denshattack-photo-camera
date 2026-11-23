import contextlib
import hashlib
import io
import os
from pathlib import Path, PureWindowsPath
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import photo_directory as folders


class DirectoryDiscoveryTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux Steam library discovery")
    def test_external_steam_library_and_installed_helper(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            client = home / "Steam client"
            (client / "steamapps").mkdir(parents=True)
            library = home / 'external "Photos"'
            escaped = str(library).replace('"', '\\"')
            (client / "steamapps/libraryfolders.vdf").write_text(f'"path" "{escaped}"\n', encoding="utf-8")
            prefix = library / "steamapps/compatdata/2524850/pfx"
            prefix.mkdir(parents=True)
            env = {"STEAM_COMPAT_CLIENT_INSTALL_PATH": str(client)}
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(Path, "home", return_value=home):
                self.assertIn(library / "steamapps", folders.steam_libraries())
                self.assertTrue(folders._saved_folder().is_relative_to(prefix))
                custom = home / "separate compatdata" / "2524850"
                with mock.patch.dict(os.environ, {"STEAM_COMPAT_DATA_PATH": str(custom)}):
                    self.assertTrue(folders._saved_folder().is_relative_to(custom / "pfx"))
                installed = library / "steamapps/common/Game/Binaries/Mod/photo_directory.py"
                with mock.patch.object(folders, "__file__", str(installed)):
                    self.assertEqual(folders.steam_libraries()[0], library / "steamapps")

    def test_native_saved_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(sys, "platform", "win32"), mock.patch.dict(os.environ, {"LOCALAPPDATA": tmp}):
                self.assertEqual(folders._saved_folder(), Path(tmp) / "Denshattack_Proto/Saved")

    def test_windows_junction_recognized_and_checked(self):
        alias = mock.Mock()
        tag = 0xA0000003  # IO_REPARSE_TAG_MOUNT_POINT
        target = PureWindowsPath(r"D:\Pictures\夜景")
        with (mock.patch.object(sys, "platform", "win32"),
              mock.patch.object(folders.stat, "IO_REPARSE_TAG_MOUNT_POINT", tag, create=True),
              mock.patch.object(os, "readlink", return_value="\\\\?\\" + str(target))):
            alias.lstat.return_value.st_reparse_tag = tag
            self.assertTrue(folders._alias_matches(alias, target))
            self.assertFalse(folders._alias_matches(alias, target.parent))
            alias.lstat.return_value.st_reparse_tag = 0
            self.assertFalse(folders._alias_matches(alias, target))

    @unittest.skipUnless(sys.platform == "win32", "uses native Windows junctions")
    def test_windows_picker_and_exporter_share_the_setting(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "Photos & pictures" / "夜景"
            target.mkdir(parents=True)
            env = {**os.environ, "LOCALAPPDATA": str(Path(tmp) / "Local"), "PYTHONIOENCODING": "utf-8"}
            command = [sys.executable, folders.__file__]
            subprocess.run([*command, "--set", str(target)], env=env, check=True, capture_output=True)
            result = subprocess.run([*command, "--show"], env=env,
                                    check=True, capture_output=True, encoding="utf-8")
            self.assertEqual(Path(result.stdout.strip()), target)


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux folder picker and watcher")
class PhotoDirectoryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.defaults = self.root / "Saved/Screenshots/Windows"
        override = mock.patch.object(folders, "DEFAULT_SHOTS", self.defaults)
        override.start()
        self.addCleanup(override.stop)

    def alias(self, directory):
        key = hashlib.sha256(os.fsencode(directory)).hexdigest()
        return self.root / "Saved/DenshattackPhotoFolders" / key

    def run_cli(self, *args):
        stdout = io.StringIO()
        with mock.patch.object(sys, "argv", ["photo_directory.py", *args]), contextlib.redirect_stdout(stdout):
            folders.main()
        return stdout.getvalue()

    def test_folder_switch_preserves_pending_shots_and_handles_linux_names(self):
        self.assertEqual(folders.selected_directory(), self.defaults)
        self.assertFalse(folders.settings_file().exists())
        a = self.root / '電車 "A|B": $shots'
        self.run_cli("--set", str(a))
        config = folders.settings_file()
        alias = self.alias(a)
        self.assertEqual(config.read_bytes(), f"{alias.name}\n{a}\n".encode())
        self.assertEqual(alias.readlink(), a)
        self.assertEqual(self.run_cli("--show").strip(), str(a))
        b = self.root / "Another folder"
        folders.set_directory(b, create=True)
        (alias / "pending.exr").write_bytes(b"test")
        self.assertEqual((a / "pending.exr").read_bytes(), b"test")
        self.assertEqual(folders.selected_directory(), b)
        folders.set_directory(a)
        self.run_cli("--reset")
        self.assertFalse(config.exists())
        self.assertEqual(folders.selected_directory(), self.defaults)
        self.assertTrue(alias.is_symlink())

    def test_picker_can_replace_an_unreadable_setting(self):
        config = folders.settings_file()
        config.parent.mkdir(parents=True)
        config.write_bytes(b"invalid setting")
        with mock.patch.object(folders, "choose_directory", return_value=self.root):
            self.run_cli()
        self.assertEqual(folders.selected_directory(), self.root)

    def test_invalid_destination_and_foreign_alias_leave_setting_intact(self):
        a = folders.set_directory(self.root / "A", create=True)
        initial = folders.settings_file().read_bytes()
        with self.assertRaisesRegex(ValueError, "newline"):
            folders.set_directory(self.root / "two\nlines", create=True)
        with self.assertRaisesRegex(ValueError, "unavailable"):
            folders.set_directory(self.root / "missing")
        target = self.root / "B"
        target.mkdir()
        self.alias(target).symlink_to(a, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "another location"):
            folders.set_directory(target)
        self.assertEqual(self.alias(target).readlink(), a)
        self.assertEqual(folders.settings_file().read_bytes(), initial)
        self.assertEqual(folders.selected_directory(), a)

    def test_atomic_configuration_failure_keeps_old_folder(self):
        a = folders.set_directory(self.root / "A", create=True)
        with mock.patch.object(os, "replace", side_effect=OSError("disk full")), self.assertRaises(OSError):
            folders.set_directory(self.root / "B", create=True)
        self.assertEqual(folders.selected_directory(), a)
        self.assertFalse(list(folders.settings_file().parent.glob(".densh-camera-dir-*")))

    def test_headless_hint_and_cancel(self):
        with mock.patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(ValueError, "--set PATH"):
            folders.choose_directory(self.root)
        env = {"DISPLAY": ":10", "XDG_CURRENT_DESKTOP": "KDE"}
        with (mock.patch.dict(os.environ, env, clear=True),
              mock.patch.object(folders.shutil, "which", return_value="/usr/bin/kdialog"),
              mock.patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"")) as dialog):
            self.run_cli()
        self.assertIn("--getexistingdirectory", dialog.call_args.args[0])
        self.assertFalse(folders.settings_file().exists())

    def wait_for(self, predicate):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.025)
        self.fail("Timed out waiting for simulated game or picker")

    def test_watcher_handles_f2_and_closes_open_dialog_on_game_exit(self):
        compat = self.root / "compatdata/2524850"
        saved = compat / "pfx/drive_c/users/steamuser/AppData/Local/Denshattack_Proto/Saved"
        saved.mkdir(parents=True)
        ready = saved / "DenshattackPhotoDirectoryPicker.ready"
        request = saved / "DenshattackPhotoDirectoryPicker.request"
        request.touch()  # Left behind by an earlier session.
        chosen = self.root / "撮影した写真"
        chosen.mkdir()
        opened = self.root / "opened"
        hold_open = self.root / "hold"
        hold_open.touch()
        dialog = self.root / "kdialog"
        dialog.write_text(f"#!{sys.executable}\n" + """
import os
from pathlib import Path
import time
with Path(os.environ['DIALOG_OPENED']).open('a') as log:
    print(os.getpid(), file=log)
while Path(os.environ['DIALOG_HOLD']).exists():
    time.sleep(0.02)
print(os.environ['DIALOG_CHOSEN'])
""")
        dialog.chmod(0o755)
        env = {**os.environ, "STEAM_COMPAT_DATA_PATH": str(compat), "DISPLAY": ":test", "XDG_CURRENT_DESKTOP": "KDE",
               "PATH": str(self.root) + os.pathsep + os.environ["PATH"], "DIALOG_OPENED": str(opened),
               "DIALOG_HOLD": str(hold_open), "DIALOG_CHOSEN": str(chosen)}
        game = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        self.addCleanup(game.wait)
        self.addCleanup(game.terminate)
        args = [sys.executable, folders.__file__, "--watch", "--parent-pid", str(game.pid)]
        watcher = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL)
        self.addCleanup(watcher.wait)
        self.addCleanup(watcher.terminate)
        self.wait_for(ready.exists)
        self.assertLess(abs(time.time() - int(ready.read_text())), 4)
        self.assertFalse(request.exists())
        self.assertFalse(opened.exists())
        duplicate = subprocess.run(args, env=env, capture_output=True, timeout=3)
        self.assertEqual(duplicate.returncode, 0)
        self.assertIn(b"already listening", duplicate.stderr)

        request.touch()
        self.wait_for(lambda: opened.exists() and bool(opened.read_text()))
        request.touch()
        self.wait_for(lambda: not request.exists())
        self.assertEqual(len(opened.read_text().splitlines()), 1)
        hold_open.unlink()
        config = saved / "DenshattackPhotoDirectory.txt"
        self.wait_for(config.exists)
        self.assertEqual(config.read_text().splitlines()[1], str(chosen))

        hold_open.touch()
        request.touch()
        self.wait_for(lambda: len(opened.read_text().splitlines()) == 2)
        dialog_pid = int(opened.read_text().splitlines()[1])
        game.terminate()
        game.wait(timeout=3)
        self.assertEqual(watcher.wait(timeout=4), 0)
        self.assertFalse(ready.exists())
        self.wait_for(lambda: folders._process_start(dialog_pid) is None)


if __name__ == "__main__":
    unittest.main()
