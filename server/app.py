#!/usr/bin/env python3
"""MM2 Hub licence server (standard library only).

  python3 tools/build.py                       # builds dist/MM2Hub.lua WITHOUT an embedded key secret
  python3 server/app.py --port 8787            # serve; put a TLS reverse proxy (Caddy / nginx / Cloudflare) in front

Endpoints (JSON):  POST /v1/activate {"key","uid"}   POST /v1/ping {"key","uid"}   GET /health
Revoke a key by appending its key id (shown by `keygen.py info`) to .license/revoked.txt.
"""
import argparse
import collections
import json
import pathlib
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import licensing  # noqa: E402

MAX_BODY = 4096
RATE_LIMIT = 12      # requests
RATE_WINDOW = 60.0   # seconds, per client address


class RateLimiter:
    def __init__(self, limit=RATE_LIMIT, window=RATE_WINDOW, clock=time.monotonic):
        self.limit, self.window, self.clock = limit, window, clock
        self.hits = collections.defaultdict(collections.deque)
        self.lock = threading.Lock()

    def allow(self, who: str) -> bool:
        now = self.clock()
        with self.lock:
            q = self.hits[who]
            while q and now - q[0] > self.window:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True


def make_handler(service, limiter):
    class Handler(BaseHTTPRequestHandler):
        server_version = "MM2HubLicense/1"

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                self._send(200, {"ok": True})
            else:
                self._send(404, {"ok": False, "error": "not found"})

        def do_POST(self):
            who = self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()
            if not limiter.allow(who):
                return self._send(429, {"ok": False, "error": "too many attempts, wait a minute"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > MAX_BODY:
                    return self._send(413, {"ok": False, "error": "bad request size"})
                data = json.loads(self.rfile.read(length))
                key, uid = data.get("key"), data.get("uid")
                if not isinstance(key, str) or len(key) > 200 or (uid is not None and not isinstance(uid, int)):
                    return self._send(400, {"ok": False, "error": "bad request"})
            except Exception:
                return self._send(400, {"ok": False, "error": "bad request"})
            if self.path == "/v1/activate":
                res = service.activate(key, uid)
            elif self.path == "/v1/ping":
                res = service.ping(key, uid)
            else:
                return self._send(404, {"ok": False, "error": "not found"})
            self._send(200 if res.get("ok") else 403, res)

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bundle", default=str(ROOT / "dist" / "MM2Hub.lua"))
    ap.add_argument("--no-uid-binding", action="store_true", help="do not bind keys to the first Roblox account that uses them")
    args = ap.parse_args()
    bundle = pathlib.Path(args.bundle)
    if not bundle.exists():
        sys.exit("Bundle missing. Run: python3 tools/build.py")
    secret = licensing.keygen.load_secret()
    if secret.hex().encode() in bundle.read_bytes():
        sys.exit("Refusing to serve a bundle that contains the licence secret. Build without --license.")
    lic = ROOT / ".license"
    lic.mkdir(exist_ok=True)
    store = licensing.LicenseStore(lic / "server_state.json", lic / "revoked.txt")
    service = licensing.LicenseService(secret, store, bundle.read_bytes(), bind_uid=not args.no_uid_binding)
    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(service, RateLimiter()))
    print(f"licence server on http://{args.host}:{args.port}  (bundle {bundle.stat().st_size} bytes) - put HTTPS in front of it")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
