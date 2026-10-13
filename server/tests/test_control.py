import os
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
os.environ["MM2_LICENSE_SECRET_HEX"] = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
import control  # noqa: E402


class ControlTests(unittest.TestCase):
    def test_tunnel_url_is_found_in_cloudflared_output(self):
        line = "2026-10-13T18:00:00Z INF |  https://quiet-river-1234.trycloudflare.com                |"
        self.assertEqual(control.find_tunnel_url(line), "https://quiet-river-1234.trycloudflare.com")
        self.assertIsNone(control.find_tunnel_url("INF Requesting new quick Tunnel on trycloudflare.com..."))
        self.assertIsNone(control.find_tunnel_url("https://example.com"))

    def test_duration_arguments(self):
        self.assertEqual(control.duration_args(months=1, days=15), ["--months", "1", "--days", "15"])
        self.assertEqual(control.duration_args(0, 1, 0, 0, 0, 30), ["--years", "1", "--seconds", "30"])
        with self.assertRaises(ValueError):
            control.duration_args()
        with self.assertRaises(ValueError):
            control.duration_args(days=-1)

    def test_revoke_writes_the_key_id(self):
        key = "MM2H-0406J-NDS01-MS61P-0H9WC-YX3J1-A27ZD-05GPY-PSZ0"
        old = control.LICENSE_DIR
        with tempfile.TemporaryDirectory() as tmp:
            control.LICENSE_DIR = pathlib.Path(tmp)
            try:
                nonce = control.revoke(key)
                self.assertEqual((pathlib.Path(tmp) / "revoked.txt").read_text().strip(), nonce)
                with self.assertRaises(ValueError):
                    control.revoke("MM2H-0406J-NDS01-MS61P-0H9WC-YX3J1-A27ZD-05GPY-PSZ1")
            finally:
                control.LICENSE_DIR = old


if __name__ == "__main__":
    unittest.main()
