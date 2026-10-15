#!/usr/bin/env python3
"""MM2 Hub licence server (standard library only).

  python3 tools/build.py                       # builds dist/MM2Hub.lua WITHOUT an embedded key secret
  python3 server/app.py --port 8787            # serve; put a TLS reverse proxy (Caddy / nginx / Cloudflare) in front

Endpoints (JSON):  POST /v1/activate {"key","uid"}   POST /v1/ping {"key","uid"}   GET /health
                   POST /v1/models {"key","uid"} -> the models pack listing (index.json text + file names and sizes)
                   POST /v1/models/file {"key","uid","name"} -> one file of the pack (base64)
The models pack is the folder given by --models (default: models/ next to this project, the same files as MM2Hub/models);
only files named in its index.json are served, and only to a valid key.
Revoke a key by appending its key id (shown by `keygen.py info`) to .license/revoked.txt.
"""
import argparse
import base64
import collections
import re
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
MAX_TRACKED = 10000  # distinct client addresses kept by the rate limiter
MODEL_RATE = 900     # model file requests per minute per address (a whole pack is a few hundred files)
MODEL_FILE_MAX = 16 * 1024 * 1024
MODEL_NAME = re.compile(r"^[A-Za-z0-9 _\-.()]{1,64}\.(obj|png|jpg|jpeg)$")


class ModelStore:
    """The models pack served to licensed clients: index.json and the OBJ/PNG files it names, nothing else."""

    def __init__(self, folder):
        self.folder = pathlib.Path(folder)
        self.lock = threading.Lock()
        self.cache = None  # (mtime, listing, allowed names)

    def _load(self):
        idx = self.folder / "index.json"
        if not idx.exists():
            return None
        mtime = idx.stat().st_mtime
        with self.lock:
            if self.cache and self.cache[0] == mtime:
                return self.cache
            text = idx.read_text(encoding="utf-8")
            data = json.loads(text)
            names = []
            for m in data.get("models", []):
                for p in m.get("parts", []):
                    for n in (p.get("mesh"), p.get("texture")):
                        if isinstance(n, str) and MODEL_NAME.match(n) and ".." not in n and n not in names:
                            names.append(n)
            files = []
            for n in names:
                f = self.folder / n
                if f.is_file() and f.stat().st_size <= MODEL_FILE_MAX:
                    files.append({"name": n, "bytes": f.stat().st_size})
            self.cache = (mtime, {"index": text, "files": files}, {f["name"] for f in files})
            return self.cache

    def listing(self):
        c = self._load()
        return c[1] if c else None

    def read(self, name):
        c = self._load()
        if not c or not isinstance(name, str) or name not in c[2]:
            return None
        return (self.folder / name).read_bytes()


class RateLimiter:
    def __init__(self, limit=RATE_LIMIT, window=RATE_WINDOW, clock=time.monotonic):
        self.limit, self.window, self.clock = limit, window, clock
        self.hits = collections.defaultdict(collections.deque)
        self.lock = threading.Lock()

    def allow(self, who: str) -> bool:
        now = self.clock()
        with self.lock:
            if len(self.hits) > MAX_TRACKED:
                # forget addresses whose window has fully passed so a flood of distinct addresses cannot grow memory
                for k in [k for k, v in self.hits.items() if not v or now - v[-1] > self.window]:
                    del self.hits[k]
            q = self.hits[who]
            while q and now - q[0] > self.window:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True


def client_address(peer: str, headers) -> str:
    """The address to rate-limit. Forwarding headers are believed only when the TCP peer is this machine (the
    tunnel / reverse proxy); otherwise any client could rotate a header value to dodge the limit.
    CF-Connecting-IP is set by Cloudflare itself; for other proxies the LAST X-Forwarded-For entry is the one the
    proxy appended."""
    if peer in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
        cf = headers.get("CF-Connecting-IP")
        if cf:
            return cf.strip()
        xff = headers.get("X-Forwarded-For")
        if xff:
            return xff.split(",")[-1].strip()
    return peer


def make_handler(service, limiter, models=None, model_limiter=None):
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
            who = client_address(self.client_address[0], self.headers)
            is_models = self.path.startswith("/v1/models")
            if not (model_limiter if is_models and model_limiter else limiter).allow(who):
                return self._send(429, {"ok": False, "error": "too many attempts, wait a minute"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > MAX_BODY:
                    return self._send(413, {"ok": False, "error": "bad request size"})
                data = json.loads(self.rfile.read(length))
                key, uid = data.get("key"), data.get("uid")
                if not isinstance(key, str) or len(key) > 200 or (uid is not None and (isinstance(uid, bool) or not isinstance(uid, int))):
                    return self._send(400, {"ok": False, "error": "bad request"})
            except Exception:
                return self._send(400, {"ok": False, "error": "bad request"})
            if is_models:
                return self._models(key, uid, data.get("name"))
            if self.path == "/v1/activate":
                res = service.activate(key, uid)
            elif self.path == "/v1/ping":
                res = service.ping(key, uid)
            else:
                return self._send(404, {"ok": False, "error": "not found"})
            self._send(200 if res.get("ok") else 403, res)

        def _models(self, key, uid, name):
            if models is None:
                return self._send(404, {"ok": False, "error": "no models pack on this server"})
            check = service.ping(key, uid)
            if not check.get("ok"):
                return self._send(403, check)
            if self.path == "/v1/models":
                listing = models.listing()
                if listing is None:
                    return self._send(404, {"ok": False, "error": "no models pack on this server"})
                return self._send(200, dict(listing, ok=True))
            if self.path == "/v1/models/file":
                raw = models.read(name)
                if raw is None:
                    return self._send(404, {"ok": False, "error": "no such model file"})
                return self._send(200, {"ok": True, "name": name, "bytes": len(raw), "data": base64.b64encode(raw).decode()})
            return self._send(404, {"ok": False, "error": "not found"})

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bundle", default=str(ROOT / "dist" / "MM2Hub.lua"))
    ap.add_argument("--models", default=str(ROOT / "models"), help="models pack folder (index.json + files) served to licensed clients")
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
    models = ModelStore(args.models)
    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(service, RateLimiter(), models, RateLimiter(limit=MODEL_RATE)))
    print(f"licence server on http://{args.host}:{args.port}  (bundle {bundle.stat().st_size} bytes) - put HTTPS in front of it")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
