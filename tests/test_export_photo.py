import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import OpenEXR

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from export_photo import main


def write_master(path):
    OpenEXR.File({"colorInteropID": "lin_rec709_scene"},
                 {"RGB": np.full((4, 4, 3), 300, np.float16)}).write(str(path))
    return path


def run_cli(*args):
    output, errors = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
        status = main([str(arg) for arg in args])
    return status, output.getvalue(), errors.getvalue()


class CompanionTests(unittest.TestCase):
    def test_default_develops_older_and_partial_shots_without_overwriting(self):
        with tempfile.TemporaryDirectory() as folder:
            d = Path(folder)
            older = write_master(d / "Denshattack_20261122_185455_0001.exr")
            renamed = write_master(d / "電車 panoramic shot.EXR")
            finished = d / "already-developed.exr"
            finished.write_bytes(b"the decoder must never open this file")

            kept = d / (older.stem + "_logc3.tiff")
            kept.write_bytes(b"existing grade")
            for ext in (".dng", "_logc3.tiff", "_flog.tiff"):
                (d / (finished.stem + ext)).touch()
            for scratch in ("capture.source.exr", "capture.exr.partial", ".temporary.exr"):
                (d / scratch).touch()
            with patch("photo_directory.selected_directory", return_value=d):
                status, output, errors = run_cli()

            self.assertEqual(status, 0, errors)
            self.assertIn("Checked 3 EXR(s). Saved 5 companion(s), kept 4 existing", output)
            self.assertIn("0 high channel samples clipped", output)
            self.assertEqual(kept.read_bytes(), b"existing grade")
            for source in (older, renamed):
                for ext in (".dng", "_logc3.tiff", "_flog.tiff"):
                    self.assertTrue((d / (source.stem + ext)).is_file())

            status, output, errors = run_cli(d)
            self.assertEqual(status, 0, errors)
            self.assertIn("Saved 0 companion(s), kept 9 existing", output)

    def test_scan_continues_after_bad_shot_and_single_file_stays_scoped(self):
        with tempfile.TemporaryDirectory() as folder:
            d = Path(folder)
            bad = d / "00-broken.exr"
            bad.write_bytes(b"not an EXR")
            valid = write_master(d / "01-good.exr")

            status, output, errors = run_cli("--directory", d, "--format", "logc3")
            self.assertEqual(status, 1)
            self.assertIn(bad.name, errors)
            self.assertIn("Saved 1 companion(s)", output)
            self.assertTrue((d / "01-good_logc3.tiff").is_file())
            self.assertFalse(valid.with_suffix(".dng").exists())

            status, output, errors = run_cli(valid, "--format", "dng")
            self.assertEqual(status, 0, errors)
            self.assertIn("Checked 1 EXR(s)", output)
            self.assertTrue(valid.with_suffix(".dng").is_file())
            self.assertFalse((d / "01-good_flog.tiff").exists())


if __name__ == "__main__":
    unittest.main()
