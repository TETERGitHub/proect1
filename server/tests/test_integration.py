"""Integration: the real Luau loader (loader/Loader.luau on the Luau CLI) against the real Python licence server
over a real localhost HTTP socket.

Level of realism (so nobody mistakes this for more than it is):
  * server side: the real handler, rate limiter, licence logic and encryption, reached by real HTTP requests;
  * client side: the real Loader state machine and crypto, run by the Luau CLI;
  * the bridge: the Luau CLI has no network or stdin, so each run replays the responses collected so far and, at the
    first request it has no answer for, prints that request. This harness sends it to the server over HTTP, stores
    the answer and re-runs the whole script from the start. Loader time is virtual (deps.wait/clock).
  * NOT covered: a real executor's `request` function, TLS, the Cloudflare tunnel, the Roblox engine.
Only dummy keys made with a throw-away test secret are used. Skipped when no Luau CLI is available (set LUAU)."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "tools"))
TEST_SECRET_HEX = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
os.environ["MM2_LICENSE_SECRET_HEX"] = TEST_SECRET_HEX
import app  # noqa: E402
import build  # noqa: E402
import licensing  # noqa: E402

keygen = licensing.keygen
SECRET = bytes.fromhex(TEST_SECRET_HEX)
LUAU = os.environ.get("LUAU") or shutil.which("luau") or ("/tmp/claude-0/luau/luau" if os.path.exists("/tmp/claude-0/luau/luau") else None)
BASE = 1_800_000_000  # virtual "now" of the server at virtual loader time 0
HUB = "HUB_RAN = (HUB_RAN or 0) + 1\nreturn { unload = function() HUB_UNLOADED = (HUB_UNLOADED or 0) + 1 end }\n"

DRIVER = r'''
local Json = __import("core/Json")
local Loader = __import("loader/Loader")
local CFG = Json.decode([==[@@CFG@@]==])
HUB_RAN, HUB_UNLOADED = nil, nil
local n, pending, T, waits = 0, nil, 0, 0
local prompts, notes, logs = {}, {}, {}
local deps = {
	request = function(req)
		n += 1
		local r = CFG.responses[n]
		if r then
			if r.status == 0 then error("transport: connection refused") end
			return { Success = r.status >= 200 and r.status < 300, StatusCode = r.status, Body = r.body }
		end
		if not pending then pending = { method = req.Method, url = req.Url, body = req.Body, t = T } end
		error("transport: awaiting response")
	end,
	loadstring = loadstring,
	readKey = function() return CFG.stored and CFG.key or nil end,
	writeKey = function() end,
	prompt = function(cb, err) table.insert(prompts, { cb = cb, err = err }) end,
	uid = CFG.uid,
	notify = function(_, text) table.insert(notes, text) end,
	clock = function() return T end,
	spawn = function(fn) pcall(fn) end,
	wait = function(s) waits += 1; T += s; if waits > CFG.maxWaits then error("virtual time limit") end end,
	log = function(t) table.insert(logs, t) end,
	serverUrl = CFG.url,
	heartbeat = CFG.heartbeat,
}
local h = Loader.run(deps)
if not CFG.stored and #prompts == 1 then prompts[1].cb(CFG.key) end
local lastErr = prompts[#prompts] and prompts[#prompts].err
print("@@" .. Json.encode({ pending = pending, final = { running = h.running, stopped = h.stopped, prompts = #prompts, promptError = lastErr, notes = notes, hubRan = HUB_RAN or 0, hubUnloaded = HUB_UNLOADED or 0, pingFailures = h.pingFailures, requests = n, logs = logs } }))
'''


def make_driver(cfg: dict) -> str:
    mods = build.collect(ROOT / "src")
    wanted = ["core/Hash", "core/Codec", "core/Json", "core/PayloadCipher"]
    parts = [build.HEADER]
    for name in wanted:
        parts.append(f'__modules["{name}"] = function(...)\nlocal __args = ...\n{mods[name]}\nend\n')
    loader = (ROOT / "loader" / "Loader.luau").read_text(encoding="utf-8")
    parts.append(f'__modules["loader/Loader"] = function(...)\nlocal __args = ...\n{loader}\nend\n')
    parts.append(DRIVER.replace("@@CFG@@", json.dumps(cfg)))
    return "\n".join(parts)


class Harness:
    def __init__(self, tmp, bundle=HUB, limit=1000, bind=True):
        self.now = [BASE]
        store = licensing.LicenseStore(pathlib.Path(tmp) / "state.json", pathlib.Path(tmp) / "revoked.txt")
        self.store = store
        self.service = licensing.LicenseService(SECRET, store, bundle.encode(), bind_uid=bind, clock=lambda: self.now[0])
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), app.make_handler(self.service, app.RateLimiter(limit=limit, window=60, clock=lambda: 0.0)))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.tmp = tmp
        self.requests = []

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def http(self, method, url, body):
        req = urllib.request.Request(url, data=body.encode() if body else None, method=method, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()
        except urllib.error.URLError:
            return 0, ""  # transport failure: the Luau side raises instead of returning a response

    def run(self, key, *, stored=True, uid=7, max_waits=3, heartbeat=100, mutate=None):
        responses = []
        for _ in range(40):
            cfg = {"responses": responses, "key": key, "stored": stored, "uid": uid, "maxWaits": max_waits, "heartbeat": heartbeat, "url": self.url}
            path = pathlib.Path(self.tmp) / "driver.lua"
            path.write_text(make_driver(cfg), encoding="utf-8")
            res = subprocess.run([LUAU, str(path)], capture_output=True, text=True, timeout=120)
            line = [l for l in res.stdout.splitlines() if l.startswith("@@")]
            if not line:
                raise AssertionError("driver failed:\n" + res.stdout + res.stderr)
            out = json.loads(line[-1][2:])
            if not out.get("pending"):
                return out["final"]
            p = out["pending"]
            self.now[0] = BASE + int(p["t"])
            status, body = self.http(p["method"], p["url"], p["body"])
            if mutate:
                body = mutate(len(responses) + 1, body)
            self.requests.append((p["url"].rsplit("/", 1)[-1], status))
            responses.append({"status": status, "body": body})
        raise AssertionError("loader did not settle")

    def key(self, *, mode=0, ttl=86400, issued=None):
        issued = BASE - 100 if issued is None else issued
        value = issued + ttl if mode == 0 else ttl
        return keygen.make_key(SECRET, mode, issued, value, os.urandom(4))

    def revoke(self, key):
        nonce = keygen.decode_key(SECRET, key)["nonce"]
        with open(pathlib.Path(self.tmp) / "revoked.txt", "a") as f:
            f.write(str(nonce) + "\n")


@unittest.skipUnless(LUAU, "luau CLI not available")
class LoaderAgainstServer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.h = Harness(self.tmp)

    def tearDown(self):
        self.h.close()

    def test_success_runs_the_hub_and_keeps_pinging(self):
        out = self.h.run(self.h.key())
        self.assertTrue(out["running"])
        self.assertEqual((out["hubRan"], out["hubUnloaded"]), (1, 0))
        self.assertEqual(self.h.requests[0], ("activate", 200))
        self.assertTrue(all(r == ("ping", 200) for r in self.h.requests[1:]) and len(self.h.requests) >= 3)

    def test_first_run_through_the_prompt(self):
        out = self.h.run(self.h.key(), stored=False)
        self.assertTrue(out["running"])
        self.assertEqual(out["prompts"], 1)

    def test_forged_key_is_refused_and_prompt_shows_the_server_message(self):
        forged = keygen.make_key(b"\x01" * 32, 0, BASE - 100, BASE + 86400, os.urandom(4))
        out = self.h.run(forged, stored=False)
        self.assertFalse(out["running"])
        self.assertEqual(out["hubRan"], 0)
        self.assertEqual(out["promptError"], "invalid key")
        self.assertEqual(out["prompts"], 2)

    def test_expired_key(self):
        out = self.h.run(self.h.key(ttl=-10), stored=False)
        self.assertEqual((out["running"], out["promptError"], out["hubRan"]), (False, "key expired", 0))

    def test_revocation_after_start_unloads_the_hub(self):
        key = self.h.key()
        original = self.h.http
        calls = {"n": 0}

        def http(method, url, body):
            calls["n"] += 1
            if calls["n"] == 3:  # the second ping
                self.h.revoke(key)
            return original(method, url, body)

        self.h.http = http
        out = self.h.run(key, max_waits=6)
        self.assertFalse(out["running"])
        self.assertEqual(out["hubUnloaded"], 1)
        self.assertTrue(any("revoked" in n for n in out["notes"]))

    def test_term_end_is_enforced_locally_and_by_the_server(self):
        out = self.h.run(self.h.key(ttl=150), heartbeat=100, max_waits=6)
        self.assertFalse(out["running"])
        self.assertEqual(out["hubUnloaded"], 1)

    def test_rate_limit_is_transient_not_fatal(self):
        self.h.close()
        self.h = Harness(self.tmp, limit=1)  # the activation uses the whole allowance, every ping gets 429
        out = self.h.run(self.h.key(), max_waits=4)
        self.assertTrue(out["running"], out)
        self.assertEqual(out["hubUnloaded"], 0)
        self.assertIn(("ping", 429), self.h.requests)

    def test_corrupted_payload_is_rejected_before_the_hub_runs(self):
        def flip(n, body):
            if n != 1:
                return body
            data = json.loads(body)
            raw = bytearray(__import__("base64").b64decode(data["payload"]))
            raw[3] ^= 1
            data["payload"] = __import__("base64").b64encode(bytes(raw)).decode()
            return json.dumps(data)

        out = self.h.run(self.h.key(), stored=False, mutate=flip)
        self.assertEqual((out["running"], out["hubRan"]), (False, 0))
        self.assertIn("authentication failed", out["promptError"])

    def test_garbage_and_empty_answers(self):
        for body, expect in (("<html>502</html>", "unreadable"), ("", "empty response"), ("[]", None)):
            out = self.h.run(self.h.key(), stored=False, mutate=lambda n, b, body=body: body if n == 1 else b)
            self.assertFalse(out["running"], body)
            self.assertEqual(out["hubRan"], 0)
            if expect:
                self.assertIn(expect, out["promptError"], body)

    def test_missing_fields_in_a_successful_answer(self):
        def strip(n, body):
            data = json.loads(body)
            if n == 1 and data.get("ok"):
                data.pop("tag")
            return json.dumps(data)

        out = self.h.run(self.h.key(), stored=False, mutate=strip)
        self.assertEqual((out["running"], out["hubRan"]), (False, 0))
        self.assertIn("malformed", out["promptError"])

    def test_activation_bound_to_the_first_account(self):
        key = self.h.key()
        self.assertTrue(self.h.run(key, uid=7)["running"])
        out = self.h.run(key, uid=8, stored=False)
        self.assertFalse(out["running"])
        self.assertEqual(out["promptError"], "key is already bound to another account")

    def test_no_account_id_is_refused_not_bound(self):
        out = self.h.run(self.h.key(), uid=None, stored=False)
        self.assertEqual((out["running"], out["promptError"]), (False, "account id required"))

    def test_server_down_is_a_network_error_not_a_licence_verdict(self):
        key = self.h.key()
        self.h.close()
        port = self.h.server.server_port
        self.h.url = f"http://127.0.0.1:{port}"  # nothing listens any more
        out = self.h.run(key, stored=False)
        self.assertFalse(out["running"])
        self.assertIn("could not reach", out["promptError"])


if __name__ == "__main__":
    unittest.main()
