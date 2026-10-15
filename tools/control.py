#!/usr/bin/env python3
"""Панель управления MM2 Hub: одна программа для всей настройки лицензий на вашем ПК.

  python tools/control.py            # меню
  python tools/control.py serve      # собрать, запустить сервер и HTTPS-туннель и ждать (Ctrl+C - остановка)
  python tools/control.py serve --no-tunnel --url https://ваш.домен     # если HTTPS у вас уже настроен

Что делает "serve": создаёт секрет ключей (один раз), собирает dist/MM2Hub.lua (хаб, секрета внутри нет),
запускает сервер лицензий, скачивает и запускает бесплатный туннель Cloudflare, чтобы получить https:// адрес,
собирает dist/Loader.lua под этот адрес и показывает, что раздавать.
Адрес быстрого туннеля меняется при каждом запуске, поэтому Loader.lua нужно пересобирать (программа делает это сама) и раздавать заново.
"""
import argparse
import collections
import os
import pathlib
import platform
import re
import socket
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


try:  # Cyrillic must print correctly in any Windows console or redirected log
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


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
        raise ValueError("срок не может быть отрицательным")
    if not any(values.values()):
        raise ValueError("срок равен нулю")
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
    say(f"  хаб собран:        {path} ({path.stat().st_size // 1024} КБ)")
    return path


def build_loader(url):
    path = build.build_loader(url)
    say(f"  загрузчик собран:  {path} ({path.stat().st_size // 1024} КБ), сервер {url}")
    return path


def cloudflared_path():
    key = (platform.system().lower(), platform.machine().lower())
    name = CLOUDFLARED.get(key)
    if not name:
        raise RuntimeError(f"для {key} нет готовой сборки cloudflared; установите её сами и запустите с --no-tunnel --url ...")
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    target = BIN_DIR / ("cloudflared.exe" if key[0] == "windows" else "cloudflared")
    if target.exists() and target.stat().st_size > 1_000_000:
        return target
    if name.endswith(".tgz"):
        raise RuntimeError("на macOS установите cloudflared командой: brew install cloudflared, затем используйте --no-tunnel --url ...")
    url = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{name}"
    say(f"  скачиваю cloudflared (бесплатная программа для туннеля): {url} ...")
    urllib.request.urlretrieve(url, target)
    if target.stat().st_size < 1_000_000:
        target.unlink()
        raise RuntimeError("cloudflared скачался не полностью")
    target.chmod(0o755)
    return target


def port_free(port):
    """True when nothing listens on 127.0.0.1:port (e.g. a server left over from a closed window would block it)."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) != 0


def free_port(port):
    """port itself, or the next free one: an old server still holding 8787 no longer stops a new start."""
    for p in range(port, port + 20):
        if port_free(p):
            if p != port:
                say(f"  порт {port} занят (старый сервер ещё работает?), использую порт {p}")
            return p
    raise RuntimeError(f"порты {port}-{port + 19} заняты; перезагрузите компьютер или закройте старые окна сервера")


def drain(stream, keep):
    """Reads a child's output to the end, keeping the last lines. Without this the pipe fills up (on Windows after a few KB of
    request log) and the server or tunnel stops answering."""
    try:
        for line in stream:
            keep.append(line.rstrip())
    except Exception:
        pass


class Stack:
    """The running server (+ tunnel). Safe to start once and stop once."""

    def __init__(self, port=8787):
        self.port = free_port(port)
        self.server = None
        self.tunnel = None
        self.url = None
        self.server_log = collections.deque(maxlen=30)
        self.tunnel_log = collections.deque(maxlen=30)

    def start_server(self):
        ensure_secret()
        build_hub()
        env = dict(os.environ)
        self.server = subprocess.Popen(
            [sys.executable, str(ROOT / "server" / "app.py"), "--port", str(self.port)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env, text=True, encoding="utf-8", errors="replace",
        )
        reader = threading.Thread(target=drain, args=(self.server.stderr, self.server_log), daemon=True)
        reader.start()
        deadline = time.time() + 15
        while time.time() < deadline:
            if self.server.poll() is not None:
                reader.join(2)
                raise RuntimeError("сервер завершился: " + ("\n".join(list(self.server_log)[-8:]) or "без сообщения"))
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=1) as r:
                    if r.status == 200:
                        say(f"  сервер лицензий:   работает на http://127.0.0.1:{self.port}")
                        return
            except Exception:
                time.sleep(0.3)
        raise RuntimeError("сервер не запустился за 15 секунд")

    def start_tunnel(self):
        self.launch_tunnel()
        self.wait_tunnel()

    def launch_tunnel(self):
        """Starts cloudflared without waiting for its address: it can connect while the hub is built and the server starts
        (the tunnel only needs the port, not a running server), which removes most of the start-up wait."""
        exe = cloudflared_path()
        self.tunnel = subprocess.Popen(
            [str(exe), "tunnel", "--url", f"http://127.0.0.1:{self.port}", "--no-autoupdate", "--protocol", "http2"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
        )  # http2 вместо QUIC: у многих провайдеров UDP заблокирован, и туннель отвечает ошибкой 1033
        found = threading.Event()

        def pump():  # reads ALL output (a full pipe would freeze cloudflared) and picks up the address
            try:
                for line in self.tunnel.stdout:
                    self.tunnel_log.append(line.rstrip())
                    url = find_tunnel_url(line)
                    if url and not self.url:
                        self.url = url
                        found.set()
            except Exception:
                pass
            found.set()  # the tunnel ended: stop waiting at once

        threading.Thread(target=pump, daemon=True).start()
        self._found = found

    def wait_tunnel(self):
        found = self._found
        if not found.wait(40) or not self.url:
            tail = "\n".join(l for l in list(self.tunnel_log)[-6:] if l)
            why = "туннель (cloudflared) закрылся" if self.tunnel and self.tunnel.poll() is not None else "туннель не сообщил адрес за 40 секунд"
            raise RuntimeError(why + " (проверьте интернет, антивирус/брандмауэр для cloudflared.exe)" + ("\nПоследние строки:\n" + tail if tail else ""))
        say(f"  https-адрес:       {self.url}")

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
    say("Запуск...")
    if tunnel:
        stack.launch_tunnel()  # in parallel with the build and the server below
    try:
        stack.start_server()
        if tunnel:
            stack.wait_tunnel()
            url = stack.url
    except Exception:
        stack.stop()
        raise
    if not url:
        stack.stop()
        raise RuntimeError("нет публичного адреса: используйте туннель или укажите --url https://ваш.домен")
    stack.url = url
    build_loader(url)
    say("")
    say("ГОТОВО.")
    say(f"  Раздавайте файл:   {ROOT / 'dist' / 'Loader.lua'}")
    say("  Создать ключ:      пункт 2 меню (или: python tools/keygen.py gen --duration \"1mo\")")
    say("  Не закрывайте это окно: при закрытии сервер остановится.")
    return stack


def make_key(note=""):
    say("Срок действия ключа. Пустое поле = 0.")

    def ask(label):
        raw = input(f"  {label}: ").strip()
        return int(raw) if raw else 0

    try:
        args = duration_args(ask("Месяцы"), ask("Годы"), ask("Дни"), ask("Часы"), ask("Минуты"), ask("Секунды"))
    except ValueError as e:
        say(f"  {e}")
        return None
    mode = input("  Считать срок: (1) с этого момента или (2) с первой активации покупателем? [1]: ").strip() or "1"
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
        raise ValueError("это не действительный ключ для вашего секрета")
    LICENSE_DIR.mkdir(exist_ok=True)
    with (LICENSE_DIR / "revoked.txt").open("a") as f:
        f.write(info["nonce"] + "\n")
    return info["nonce"]


def menu(args):
    stack = None
    try:
        while True:
            say("")
            say("=== Панель управления MM2 Hub ===" + ("   [сервер работает]" if stack else ""))
            say(" 1) Запустить сервер + HTTPS-туннель и собрать Loader.lua")
            say(" 2) Создать ключ лицензии")
            say(" 3) Показать выданные ключи")
            say(" 4) Отозвать ключ")
            say(" 5) Собрать простую версию с проверкой ключа внутри (сервер не нужен)")
            say(" 6) Выход")
            try:
                choice = input("Выберите пункт: ").strip()
            except EOFError:  # input stream closed: leave instead of looping forever
                return
            try:
                if choice == "1":
                    if stack:
                        say("Уже запущено.")
                    else:
                        stack = start_stack(args.port)
                elif choice == "2":
                    make_key()
                elif choice == "3":
                    log = LICENSE_DIR / "issued.csv"
                    say(log.read_text(encoding="utf-8") if log.exists() else "Ключи ещё не выдавались.")
                elif choice == "4":
                    say("ключ отозван, его номер: " + revoke(input("Вставьте ключ: ").strip()))
                elif choice == "5":
                    ensure_secret()
                    p = build.build(False, (LICENSE_DIR / "secret.hex").read_text().strip(), True)
                    say(f"Собрано: {p}. Ключ проверяется внутри скрипта (ограничения: docs/LICENSE.md).")
                elif choice == "6":
                    return
            except Exception as e:  # keep the menu alive on any error
                say(f"  Ошибка: {e}")
    finally:
        if stack:
            stack.stop()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", default="menu", choices=["menu", "serve"])
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--no-tunnel", action="store_true")
    ap.add_argument("--url", help="публичный https-адрес, если вы не используете бесплатный туннель")
    args = ap.parse_args()
    if args.command == "menu":
        return menu(args)
    stack = start_stack(args.port, tunnel=not args.no_tunnel, url=args.url)
    try:
        while True:
            time.sleep(1)
            if stack.server.poll() is not None:
                raise RuntimeError("сервер неожиданно остановился")
    except KeyboardInterrupt:
        pass
    finally:
        stack.stop()


if __name__ == "__main__":
    main()
