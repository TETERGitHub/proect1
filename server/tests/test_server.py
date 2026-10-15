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

    def test_key_for_several_people(self):
        """a key made with --users 3: the first three accounts get in (and keep getting in), the fourth is refused"""
        key = keygen.make_key(SECRET, 0, ISSUED, keygen.FOREVER, b"\x0a\x0b\x0c\x0d")
        (pathlib.Path(self.tmp) / "seats.json").write_text(json.dumps({"0a0b0c0d": 3}))
        svc, store = make_service(self.tmp, self.clock)
        for uid in (1, 2, 3):
            self.assertTrue(svc.activate(key, uid)["ok"], uid)
        res = svc.activate(key, 4)
        self.assertFalse(res["ok"])
        self.assertEqual(res["error"], "this key has no free places left")
        self.assertTrue(svc.activate(key, 2)["ok"])
        self.assertTrue(svc.ping(key, 3)["ok"])
        self.assertFalse(svc.ping(key, 4)["ok"])
        # a normal key (not in seats.json) stays one account
        one = keygen.make_key(SECRET, 0, ISSUED, keygen.FOREVER, b"\x01\x01\x01\x01")
        self.assertTrue(svc.activate(one, 1)["ok"])
        self.assertEqual(svc.activate(one, 2)["error"], "key is already bound to another account")
        # the seat count is re-read when keygen adds keys while the server runs
        late = keygen.make_key(SECRET, 0, ISSUED, keygen.FOREVER, b"\x02\x02\x02\x02")
        self.assertTrue(svc.activate(late, 1)["ok"])
        self.assertFalse(svc.activate(late, 2)["ok"])
        import os, time
        (pathlib.Path(self.tmp) / "seats.json").write_text(json.dumps({"0a0b0c0d": 3, "02020202": 2}))
        os.utime(pathlib.Path(self.tmp) / "seats.json", (time.time() + 5, time.time() + 5))
        self.assertTrue(svc.activate(late, 2)["ok"])

    def test_keygen_writes_seats(self):
        old = keygen.SEATS_FILE
        keygen.SEATS_FILE = pathlib.Path(self.tmp) / "seats.json"
        try:
            keygen.save_seats({"aabbccdd": 5})
            keygen.save_seats({"11223344": 2})
            self.assertEqual(keygen.seats_of("AABBCCDD"), 5)
            self.assertEqual(keygen.seats_of("11223344"), 2)
            self.assertEqual(keygen.seats_of("99999999"), 1)
            store = licensing.LicenseStore(pathlib.Path(self.tmp) / "state.json", pathlib.Path(self.tmp) / "revoked.txt")
            self.assertEqual(store.seats("aabbccdd"), 5)
        finally:
            keygen.SEATS_FILE = old

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

    def test_forever_key_and_any_number_of_years(self):
        import contextlib, io, types
        svc, _ = make_service(self.tmp, self.clock)
        key = keygen.make_key(SECRET, 0, ISSUED, keygen.FOREVER, b"\x01\x02\x03\x04")
        self.assertTrue(svc.activate(key, 1)["ok"])
        self.clock.t = 4102444800  # year 2100
        self.assertTrue(svc.activate(key, 1)["ok"])
        # keygen gen: 5000 years, 99999 years and --forever all give a key without a limit, 50 years a dated one
        old = (keygen.LICENSE_DIR, keygen.LOG_FILE, keygen.load_secret)
        keygen.LICENSE_DIR, keygen.LOG_FILE = pathlib.Path(self.tmp), pathlib.Path(self.tmp) / "issued.csv"
        keygen.load_secret = lambda: SECRET
        try:
            def gen(years=0, forever=False, mode="absolute"):
                a = types.SimpleNamespace(interactive=False, duration=None, years=years, months=0, weeks=0, days=0, hours=0, minutes=0,
                                          seconds=0, forever=forever, mode=mode, count=1, note="", now=str(ISSUED))
                out, err = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    keygen.cmd_gen(a)
                return keygen.decode_key(SECRET, out.getvalue().strip()), err.getvalue()
            for kw in ({"years": 5000}, {"years": 99999}, {"forever": True}, {"years": 300, "mode": "activation"}):
                info, summary = gen(**kw)
                self.assertTrue(info["valid"])
                self.assertEqual((info["mode"], info["value"]), (0, keygen.FOREVER), kw)
                self.assertIn("бессрочный", summary)
            info, _ = gen(years=50)
            self.assertEqual(info["mode"], 0)
            self.assertLess(info["value"], keygen.FOREVER)
        finally:
            keygen.LICENSE_DIR, keygen.LOG_FILE, keygen.load_secret = old

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


class ModelsHttpTests(unittest.TestCase):
    """the models pack: listing and files only for a valid key, only files named by index.json"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        svc, _ = make_service(self.tmp, Clock(ISSUED + 3600))
        self.models = pathlib.Path(self.tmp) / "models"
        self.models.mkdir()
        (self.models / "a_0.obj").write_bytes(b"v 0 0 0\n")
        (self.models / "a_0.png").write_bytes(bytes(range(256)))
        (self.models / "secret.txt").write_text("not served")
        (self.models / "index.json").write_text(json.dumps({"version": 1, "models": [
            {"id": "a", "parts": [{"mesh": "a_0.obj", "texture": "a_0.png"}, {"mesh": "../evil.obj"}]}]}))
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), app.make_handler(svc, app.RateLimiter(limit=100), app.ModelStore(self.models),
                                                                            app.RateLimiter(limit=1000)))
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()

    post = HttpTests.post

    def test_listing_and_files(self):
        status, body = self.post("/v1/models", {"key": KEY_ABS, "uid": 9})
        self.assertEqual(status, 200)
        self.assertEqual(sorted(f["name"] for f in body["files"]), ["a_0.obj", "a_0.png"])
        self.assertIn('"models"', body["index"])
        status, body = self.post("/v1/models/file", {"key": KEY_ABS, "uid": 9, "name": "a_0.png"})
        self.assertEqual(status, 200)
        self.assertEqual(base64.b64decode(body["data"]), bytes(range(256)))
        for bad in ("secret.txt", "../evil.obj", "index.json", 5):
            self.assertEqual(self.post("/v1/models/file", {"key": KEY_ABS, "uid": 9, "name": bad})[0], 404, bad)
        self.assertEqual(self.post("/v1/models", {"key": "nope", "uid": 9})[0], 403)
        self.assertEqual(self.post("/v1/models/file", {"key": "nope", "uid": 9, "name": "a_0.png"})[0], 403)


class RateLimitTrust(unittest.TestCase):
    def test_forwarding_headers_are_trusted_only_from_the_local_proxy(self):
        class H(dict):
            pass
        # a remote client cannot pick its own bucket by sending headers
        self.assertEqual(app.client_address("203.0.113.9", H({"X-Forwarded-For": "1.2.3.4", "CF-Connecting-IP": "5.6.7.8"})), "203.0.113.9")
        # the local tunnel: Cloudflare's own header wins; otherwise the last (proxy-appended) XFF entry
        self.assertEqual(app.client_address("127.0.0.1", H({"CF-Connecting-IP": "5.6.7.8", "X-Forwarded-For": "9.9.9.9"})), "5.6.7.8")
        self.assertEqual(app.client_address("127.0.0.1", H({"X-Forwarded-For": "spoofed, 198.51.100.7"})), "198.51.100.7")
        self.assertEqual(app.client_address("127.0.0.1", H()), "127.0.0.1")

    def test_limiter_memory_is_bounded(self):
        now = [0.0]
        lim = app.RateLimiter(limit=2, window=10, clock=lambda: now[0])
        for i in range(app.MAX_TRACKED + 50):
            lim.allow(f"10.0.{i // 256}.{i % 256}")
        now[0] = 100.0  # every window has passed
        lim.allow("fresh")
        self.assertLess(len(lim.hits), 10)

    def test_uid_must_be_an_integer_not_a_boolean(self):
        with tempfile.TemporaryDirectory() as d:
            store = licensing.LicenseStore(pathlib.Path(d) / "s.json", pathlib.Path(d) / "r.txt")
            service = licensing.LicenseService(SECRET, store, BUNDLE, clock=lambda: ISSUED + 100)
            srv = ThreadingHTTPServer(("127.0.0.1", 0), app.make_handler(service, app.RateLimiter()))
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            try:
                for uid in (True, "5", 1.5, [1]):
                    req = urllib.request.Request(f"http://127.0.0.1:{srv.server_port}/v1/activate", data=json.dumps({"key": KEY_ABS, "uid": uid}).encode(), headers={"Content-Type": "application/json"})
                    with self.assertRaises(urllib.error.HTTPError) as cm:
                        urllib.request.urlopen(req)
                    self.assertEqual(cm.exception.code, 400, uid)
            finally:
                srv.shutdown()


if __name__ == "__main__":
    unittest.main()
