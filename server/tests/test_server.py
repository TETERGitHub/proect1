import base64
import hashlib
import hmac
import json
import os
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
os.environ["MM2_LICENSE_SECRET_HEX"] = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
import app  # noqa: E402
import licensing  # noqa: E402

keygen = licensing.keygen
SECRET = bytes.fromhex(os.environ["MM2_LICENSE_SECRET_HEX"])
ISSUED = 1767225600
KEY_ABS = "MM2H-0406J-NDS01-MS61P-0H9WC-YX3J1-A27ZD-05GPY-PSZ0"  # until 2026-02-16 12:00 UTC
KEY_ACT = "MM2H-040PJ-NDS00-02F38-0X2GH-RTFKS-HYBGE-X8KBA-1YSR"  # 30 days from first activation
BUNDLE = b"print('hub')\n" * 50


class Clock:
    def __init__(self, t):
        self.t = t

    def __call__(self):
        return self.t


def make_service(tmp, clock, bind=True):
    store = licensing.LicenseStore(pathlib.Path(tmp) / "state.json", pathlib.Path(tmp) / "revoked.txt")
    return licensing.LicenseService(SECRET, store, BUNDLE, bind_uid=bind, clock=clock), store


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.clock = Clock(ISSUED + 3600)

    def test_valid_key_returns_decryptable_payload(self):
        svc, _ = make_service(self.tmp, self.clock)
        res = svc.activate(KEY_ABS, 42)
        self.assertTrue(res["ok"])
        self.assertEqual(res["expires"], 1771243200)
        nonce, cipher = base64.b64decode(res["nonce"]), base64.b64decode(res["payload"])
        k = licensing.derive_key(KEY_ABS, nonce)
        self.assertEqual(res["tag"], hmac.new(k, nonce + cipher, hashlib.sha256).hexdigest()[:32])
        plain = bytearray()
        import struct
        for i, off in enumerate(range(0, len(cipher), 32)):
            ks = hashlib.sha256(k + struct.pack(">I", i)).digest()
            plain.extend(b ^ s for b, s in zip(cipher[off:off + 32], ks))
        self.assertEqual(bytes(plain), BUNDLE)

    def test_spelling_variants_accepted(self):
        svc, _ = make_service(self.tmp, self.clock)
        self.assertTrue(svc.activate(KEY_ABS.lower().replace("-", " "), 1)["ok"])

    def test_invalid_tampered_and_garbage_keys(self):
        svc, _ = make_service(self.tmp, self.clock)
        body = KEY_ABS[5:]
        for i, ch in enumerate(body):
            if ch == "-":
                continue
            bad = "MM2H-" + body[:i] + ("1" if ch == "0" else "0") + body[i + 1:]
            self.assertFalse(svc.activate(bad, 1)["ok"], bad)
        for junk in ["", "hello", "MM2H-", "MM2H-0000", "x" * 150]:
            self.assertFalse(svc.activate(junk, 1)["ok"])

    def test_expiry_is_enforced_by_server_time(self):
        svc, _ = make_service(self.tmp, self.clock)
        self.assertTrue(svc.activate(KEY_ABS, 1)["ok"])
        self.clock.t = 1771243200
        res = svc.activate(KEY_ABS, 1)
        self.assertFalse(res["ok"])
        self.assertIn("expired", res["error"])
        self.assertFalse(svc.ping(KEY_ABS, 1)["ok"])

    def test_activation_mode_counts_from_first_use(self):
        svc, _ = make_service(self.tmp, self.clock)
        self.clock.t = ISSUED + 10 * 86400
        self.assertEqual(svc.activate(KEY_ACT, 7)["expires"], ISSUED + 40 * 86400)
        self.clock.t = ISSUED + 39 * 86400
        self.assertTrue(svc.ping(KEY_ACT, 7)["ok"])
        self.clock.t = ISSUED + 40 * 86400
        self.assertFalse(svc.ping(KEY_ACT, 7)["ok"])

    def test_key_is_bound_to_first_account(self):
        svc, _ = make_service(self.tmp, self.clock)
        self.assertTrue(svc.activate(KEY_ABS, 100)["ok"])
        self.assertTrue(svc.activate(KEY_ABS, 100)["ok"])
        other = svc.activate(KEY_ABS, 200)
        self.assertFalse(other["ok"])
        self.assertIn("another account", other["error"])
        self.assertFalse(svc.activate(KEY_ABS, None)["ok"])

    def test_binding_can_be_disabled(self):
        svc, _ = make_service(self.tmp, self.clock, bind=False)
        self.assertTrue(svc.activate(KEY_ABS, 1)["ok"])
        self.assertTrue(svc.activate(KEY_ABS, 2)["ok"])

    def test_revoked_key(self):
        svc, store = make_service(self.tmp, self.clock)
        nonce = keygen.decode_key(SECRET, KEY_ABS)["nonce"]
        pathlib.Path(self.tmp, "revoked.txt").write_text("# revoked\n" + nonce.upper() + "\n")
        res = svc.activate(KEY_ABS, 1)
        self.assertFalse(res["ok"])
        self.assertIn("revoked", res["error"])

    def test_state_persists_across_restart(self):
        svc, _ = make_service(self.tmp, self.clock)
        svc.activate(KEY_ABS, 55)
        svc2, _ = make_service(self.tmp, self.clock)
        self.assertFalse(svc2.activate(KEY_ABS, 56)["ok"])

    def test_future_issue_date_rejected(self):
        svc, _ = make_service(self.tmp, Clock(ISSUED - 10 * 86400))
        self.assertFalse(svc.activate(KEY_ABS, 1)["ok"])


class RateLimitTests(unittest.TestCase):
    def test_blocks_after_limit_and_recovers(self):
        t = [0.0]
        rl = app.RateLimiter(limit=3, window=10, clock=lambda: t[0])
        self.assertTrue(all(rl.allow("a") for _ in range(3)))
        self.assertFalse(rl.allow("a"))
        self.assertTrue(rl.allow("b"))
        t[0] = 11
        self.assertTrue(rl.allow("a"))


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        svc, _ = make_service(self.tmp, Clock(ISSUED + 3600))
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), app.make_handler(svc, app.RateLimiter(limit=100)))
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()

    def post(self, path, obj, raw=None):
        data = raw if raw is not None else json.dumps(obj).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data, method="POST", headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_activate_ping_and_errors(self):
        status, body = self.post("/v1/activate", {"key": KEY_ABS, "uid": 9})
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertEqual(self.post("/v1/ping", {"key": KEY_ABS, "uid": 9})[0], 200)
        self.assertEqual(self.post("/v1/activate", {"key": "nope", "uid": 9})[0], 403)
        self.assertEqual(self.post("/v1/activate", None, raw=b"{bad json")[0], 400)
        self.assertEqual(self.post("/v1/activate", {"key": 5})[0], 400)
        self.assertEqual(self.post("/v1/nothing", {"key": KEY_ABS})[0], 404)
        self.assertEqual(self.post("/v1/activate", None, raw=b"x" * 5000)[0], 413)
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health") as r:
            self.assertEqual(json.loads(r.read()), {"ok": True})


if __name__ == "__main__":
    unittest.main()
