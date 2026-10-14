"""Non-GUI helpers of tools/control_gui.py (the window itself needs a display; it was checked with screenshots under Xvfb)."""
import csv, importlib, pathlib, sys, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

try:
    import tkinter  # noqa: F401
    HAVE_TK = True
except ImportError:
    HAVE_TK = False


@unittest.skipUnless(HAVE_TK, "tkinter is not installed for this Python")
class ControlGuiHelpers(unittest.TestCase):
    def setUp(self):
        self.g = importlib.import_module("control_gui")

    def test_startup_script_starts_panel_with_autostart(self):
        text = self.g.startup_script_text(sys.executable, "C:/x/tools/control_gui.py")
        self.assertIn("--autostart", text)
        self.assertIn("control_gui.py", text)
        self.assertTrue(text.startswith("@echo off"))

    def test_issued_rows_newest_first(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "issued.csv"
            with p.open("w", newline="") as f:
                w = csv.writer(f)
                w.writerow(["issued_utc", "nonce", "mode", "value", "note", "key"])
                w.writerow(["2026-01-01 00:00", "aa", "absolute", "1", "first", "K1"])
                w.writerow(["2026-01-02 00:00", "bb", "activation", "2", "second", "K2"])
            rows = self.g.read_issued(p)
            self.assertEqual([r["key"] for r in rows], ["K2", "K1"])
            self.assertEqual(self.g.read_issued(pathlib.Path(d) / "none.csv"), [])


if __name__ == "__main__":
    unittest.main()
