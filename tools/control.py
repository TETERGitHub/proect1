#!/usr/bin/env python3
"""MM2 Hub control panel: one program for the whole licence setup on your own PC.

  python tools/control.py            # interactive menu
  python tools/control.py serve      # build + start server + HTTPS tunnel, then wait (Ctrl+C stops)
  python tools/control.py serve --no-tunnel --url https://your.domain     # you already have HTTPS in front

What "serve" does: creates your licence secret (once), builds dist/MM2Hub.lua (the hub, no secret inside),
starts the licence server, downloads and starts a free Cloudflare quick tunnel to give it an https:// address,
builds dist/Loader.lua for that address and prints what to distribute.
Quick-tunnel addresses change every run, so Loader.lua must be rebuilt (this program does it) and re-shared each time.
"""
import argparse
import os
import pathlib
import platform
import re
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "server"))
import build  # noqa: E402

LICENSE_DIR = ROOT / ".license"
BIN_DIR = ROOT / "tools" / "bin"
TUNNEL_URL = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
CLOUDFLARED = {
    ("windows", "amd64"): "cloudflared-windows-amd64.exe",
    ("linux", "x86_64"): "cloudflared-linux-amd64",
    ("linux", "amd64"): "cloudflared-linux-amd64",
    ("linux", "aarch64"): "cloudflared-linux-arm64",
    ("darwin", "x86_64"): "cloudflared-darwin-amd64.tgz",
    ("darwin", "arm64"): "cloudflared-darwin-arm64.tgz",
}


def say(msg=""):
    print(msg, flush=True)


def find_tunnel_url(text):
    """First quick-tunnel address in a line of cloudflared output, or None."""
    m = TUNNEL_URL.search(text)
    return m.group(0) if m else None


def duration_args(months=0, years=0, days=0, hours=0, minutes=0, seconds=0):
    """keygen.py arguments for a duration entered in the order: month, year, day, hour, minute, second."""
    values = dict(months=months, years=years, days=days, hours=hours, minutes=minutes, seconds=seconds)
    if any(v < 0 for v in values.values()):
        raise ValueError("durations cannot be negative")
    if not any(values.values()):
        raise ValueError("the duration is zero")
    args = []
    for name, v in values.items():
        if v:
            args += [f"--{name}", str(int(v))]
    return args


def ensure_secret():
    import keygen
    if not keygen.SECRET_FILE.exists():
        keygen.cmd_init(None)
    return keygen.SECRET_FILE


def build_hub():
    path = build.build(False)
    say(f"  hub bundle:     {path} ({path.stat().st_size // 1024} KB)")
    return path


def build_loader(url):
    path = build.build_loader(url)
    say(f"  loader:         {path} ({path.stat().st_size // 1024} KB) -> server {url}")
    return path


def cloudflared_path():
    key = (platform.system().lower(), platform.machine().lower())
    name = CLOUDFLARED.get(key)
    if not name:
        raise RuntimeError(f"no cloudflared build known for {key}; install it yourself or use --no-tunnel --url ...")
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    target = BIN_DIR / ("cloudflared.exe" if key[0] == "windows" else "cloudflared")
    if target.exists() and target.stat().st_size > 1_000_000:
        return target
    if name.endswith(".tgz"):
        raise RuntimeError("on macOS install cloudflared with: brew install cloudflared, then use --no-tunnel --url ...")
    url = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{name}"
    say(f"  downloading cloudflared (free tunnel program) from {url} ...")
    urllib.request.urlretrieve(url, target)
    if target.stat().st_size < 1_000_000:
        target.unlink()
        raise RuntimeError("cloudflared download looks incomplete")
    target.chmod(0o755)
    return target


class Stack:
    """The running server (+ tunnel). Safe to start once and stop once."""

    def __init__(self, port=8787):
        self.port = port
        self.server = None
        self.tunnel = None
        self.url = None

    def start_server(self):
        ensure_secret()
        build_hub()
        env = dict(os.environ)
        self.server = subprocess.Popen(
            [sys.executable, str(ROOT / "server" / "app.py"), "--port", str(self.port)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env, text=True,
        )
        deadline = time.time() + 15
        while time.time() < deadline:
            if self.server.poll() is not None:
                raise RuntimeError("server exited: " + (self.server.stderr.read() or "no output"))
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=1) as r:
                    if r.status == 200:
                        say(f"  licence server: running on http://127.0.0.1:{self.port}")
                        return
            except Exception:
                time.sleep(0.3)
        raise RuntimeError("server did not become ready in 15 s")

    def start_tunnel(self):
        exe = cloudflared_path()
        self.tunnel = subprocess.Popen(
            [str(exe), "tunnel", "--url", f"http://127.0.0.1:{self.port}", "--no-autoupdate"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        found = threading.Event()

        def pump():
            for line in self.tunnel.stdout:
                url = find_tunnel_url(line)
                if url and not self.url:
                    self.url = url
                    found.set()

        threading.Thread(target=pump, daemon=True).start()
        if not found.wait(40):
            raise RuntimeError("the tunnel did not report an address in 40 s (check your internet connection)")
        say(f"  https address:  {self.url}")

    def stop(self):
        for p in (self.tunnel, self.server):
            if p and p.poll() is None:
                p.terminate()
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    p.kill()
        self.tunnel = self.server = None


def start_stack(port, tunnel=True, url=None):
    stack = Stack(port)
    say("Starting...")
    stack.start_server()
    if tunnel:
        stack.start_tunnel()
        url = stack.url
    if not url:
        stack.stop()
        raise RuntimeError("no public address: use the tunnel or pass --url https://your.domain")
    stack.url = url
    build_loader(url)
    say("")
    say("READY.")
    say(f"  Give users:     {ROOT / 'dist' / 'Loader.lua'}")
    say("  Make keys:      menu option 2 (or: python tools/keygen.py gen --duration \"1mo\")")
    say("  Keep this window open - closing it stops the server.")
    return stack


def make_key(note=""):
    say("Key duration. Leave a field empty for 0.")

    def ask(label):
        raw = input(f"  {label}: ").strip()
        return int(raw) if raw else 0

    try:
        args = duration_args(ask("Months"), ask("Years"), ask("Days"), ask("Hours"), ask("Minutes"), ask("Seconds"))
    except ValueError as e:
        say(f"  {e}")
        return None
    mode = input("  Count the time from (1) now, or (2) the buyer's first activation? [1]: ").strip() or "1"
    cmd = [sys.executable, str(ROOT / "tools" / "keygen.py"), "gen", *args, "--mode", "activation" if mode == "2" else "absolute"]
    if note:
        cmd += ["--note", note]
    ensure_secret()
    res = subprocess.run(cmd, capture_output=True, text=True)
    say(res.stdout.strip())
    say(res.stderr.strip())
    return res.stdout.strip().splitlines()[0] if res.returncode == 0 and res.stdout.strip() else None


def revoke(key_text):
    import keygen
    ensure_secret()
    secret = keygen.load_secret()
    info = keygen.decode_key(secret, key_text)
    if not info["valid"]:
        raise ValueError("that is not a valid key for your secret")
    LICENSE_DIR.mkdir(exist_ok=True)
    with (LICENSE_DIR / "revoked.txt").open("a") as f:
        f.write(info["nonce"] + "\n")
    return info["nonce"]


def menu(args):
    stack = None
    try:
        while True:
            say("")
            say("=== MM2 Hub control ===" + ("   [server running]" if stack else ""))
            say(" 1) Start server + HTTPS tunnel and build Loader.lua")
            say(" 2) Create a licence key")
            say(" 3) Show issued keys")
            say(" 4) Revoke a key")
            say(" 5) Build the simple offline-key version (no server needed)")
            say(" 6) Quit")
            choice = input("Choose: ").strip()
            try:
                if choice == "1":
                    if stack:
                        say("Already running.")
                    else:
                        stack = start_stack(args.port)
                elif choice == "2":
                    make_key()
                elif choice == "3":
                    log = LICENSE_DIR / "issued.csv"
                    say(log.read_text() if log.exists() else "No keys issued yet.")
                elif choice == "4":
                    say("revoked key id: " + revoke(input("Paste the key: ").strip()))
                elif choice == "5":
                    ensure_secret()
                    p = build.build(False, (LICENSE_DIR / "secret.hex").read_text().strip(), True)
                    say(f"Built {p}. Keys are checked inside the script (see docs/LICENSE.md for the limits).")
                elif choice == "6":
                    return
            except Exception as e:  # keep the menu alive on any error
                say(f"  Error: {e}")
    finally:
        if stack:
            stack.stop()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", default="menu", choices=["menu", "serve"])
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--no-tunnel", action="store_true")
    ap.add_argument("--url", help="public https address when you do not use the free tunnel")
    args = ap.parse_args()
    if args.command == "menu":
        return menu(args)
    stack = start_stack(args.port, tunnel=not args.no_tunnel, url=args.url)
    try:
        while True:
            time.sleep(1)
            if stack.server.poll() is not None:
                raise RuntimeError("server stopped unexpectedly")
    except KeyboardInterrupt:
        pass
    finally:
        stack.stop()


if __name__ == "__main__":
    main()
