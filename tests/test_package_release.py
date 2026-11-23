import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from package_release import build_release


class ReleaseTests(unittest.TestCase):
    def test_rebuilds_match_and_platforms_contain_their_installers(self):
        with tempfile.TemporaryDirectory() as directory:
            batches = [build_release(ROOT, Path(directory) / run, "0.1.0") for run in ("a", "b")]
            self.assertEqual([p.read_bytes() for p in batches[0]], [p.read_bytes() for p in batches[1]])
            windows, linux, checksum = batches[0]
            self.assertEqual(checksum.read_text().splitlines(), [
                f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}" for path in (windows, linux)
            ])
            for path, entry in ((windows, "Install-Windows.cmd"), (linux, "Install-Linux.sh")):
                with zipfile.ZipFile(path) as bundle:
                    self.assertIsNone(bundle.testzip())
                    names = [x.removeprefix("DenshattackPhotoCamera-0.1.0/") for x in bundle.namelist()]
                    self.assertIn(entry, names)
                    self.assertIn("mod/Scripts/main.lua", names)
                    self.assertIn("requirements.txt", names)
                    self.assertEqual(len(names), len(set(names)))
                    self.assertFalse(any(name.endswith((".dll", ".exe", ".exr", ".png", ".zip"))
                                         or "__pycache__" in name for name in names))
                    if path == linux:
                        self.assertFalse(any(name.startswith("windows/") for name in names))
                        mode = bundle.getinfo(f"DenshattackPhotoCamera-0.1.0/{entry}").external_attr >> 16
                        self.assertTrue(mode & 0o111)
                    else:
                        self.assertIn("windows/photo_camera.py", names)
                        self.assertNotIn("tools/install.py", names)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux/Proton installer requires Linux")
    def test_packaged_linux_install_repeat_and_remove(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            _, archive, _ = build_release(ROOT, temp / "release", "0.1.0")
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(temp / "extracted")
            checkout = temp / "extracted/DenshattackPhotoCamera-0.1.0"
            game = temp / "Steam Library/common/Denshattack"
            binaries = game / "Denshattack_Proto/Binaries/Win64"
            binaries.mkdir(parents=True)
            (binaries / "Denshattack_Proto-Win64-Shipping.exe").touch()
            def run(action, *args, expect=0):
                result = subprocess.run(["sh", str(checkout / "Install-Linux.sh"), action,
                                         "--game", str(game), *args], cwd=temp,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
                return result.stdout + result.stderr

            bad = temp / "incorrect-loader.zip"
            bad.write_bytes(b"wrong loader")
            self.assertIn("SHA-256", run("install", "--loader-zip", str(bad), expect=1))
            self.assertFalse((binaries / "ue4ss").exists())
            mods = binaries / "ue4ss/Mods"
            mods.mkdir(parents=True)
            (mods.parent / "UE4SS.dll").touch()
            neighbor = mods / "mods.txt"
            neighbor.write_text("OtherMod : 1\n")
            self.assertIn("Published", run("install", "--download-loader"))
            camera = mods / "DenshattackPhotoCamera"
            self.assertTrue((camera / "Scripts/main.lua").is_file())
            self.assertTrue((camera / "enabled.txt").is_file())
            self.assertTrue((camera / "launch_dx12.py").is_file())
            self.assertIn("Already installed", run("install"))
            self.assertIn("Camera present: True", run("status"))
            run("remove")
            self.assertFalse(camera.exists())
            self.assertEqual(neighbor.read_text(), "OtherMod : 1\n")
            self.assertTrue((mods.parent / "UE4SS.dll").is_file())


if __name__ == "__main__":
    unittest.main()
