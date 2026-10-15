#!/usr/bin/env python3
"""Генератор ключей лицензии MM2 Hub (запускайте на СВОЁМ компьютере; не раздавайте этот файл и папку .license/).

  python3 tools/keygen.py init
  python3 tools/keygen.py gen --duration "1mo 15d 12h"           # key valid for that long, counted from NOW
  python3 tools/keygen.py gen --years 1 --months 2 --days 3 --hours 4 --minutes 5 --seconds 6
  python3 tools/keygen.py gen -i                                  # asks month / year / day / hour / minute / second
  python3 tools/keygen.py gen --duration 30d --mode activation    # 30 days counted from the buyer's first activation
  python3 tools/keygen.py gen --forever                           # key without a time limit (any number of years also works)
  python3 tools/keygen.py info MM2H-XXXXX-...
  python3 tools/keygen.py list

Duration tokens: y/yr/year(s), mo/month(s), w/week(s), d/day(s), h/hour(s), m/min(ute)(s), s/sec(ond)(s).
Months and years are calendar-aware in 'absolute' mode. In 'activation' mode they are approximated
(1 month = 30 days, 1 year = 365 days) because the real start date is not known yet.

The secret is stored in .license/secret.hex. Build the hub with `python3 tools/build.py --license` to
embed it. Keys are signed with HMAC-SHA256; see the SECURITY NOTE in src/core/License.luau.
"""
import argparse
import calendar
import csv
import datetime as dt
import hashlib
import hmac
import os
import pathlib
import re
import struct
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
LICENSE_DIR = ROOT / ".license"
SECRET_FILE = LICENSE_DIR / "secret.hex"
LOG_FILE = LICENSE_DIR / "issued.csv"

VERSION = 1
MAC_BYTES = 10
B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
MAX_U32 = 2**32 - 1
FOREVER = MAX_U32  # "valid until" the last second the key format can hold (year 2106): a key without a time limit


def b32encode(data: bytes) -> str:
    out, acc, bits = [], 0, 0
    for byte in data:
        acc = (acc << 8) | byte
        bits += 8
        while bits >= 5:
            out.append(B32[(acc >> (bits - 5)) & 31])
            bits -= 5
    if bits:
        out.append(B32[(acc << (5 - bits)) & 31])
    return "".join(out)


def b32decode(text: str, nbytes: int) -> bytes:
    text = re.sub(r"[\s-]", "", text.upper()).replace("O", "0")
    text = re.sub(r"[IL]", "1", text)
    acc = bits = 0
    out = bytearray()
    for ch in text:
        v = B32.find(ch)
        if v < 0:
            raise ValueError(f"invalid character {ch!r}")
        acc = (acc << 5) | v
        bits += 5
        if bits >= 8:
            out.append((acc >> (bits - 8)) & 0xFF)
            bits -= 8
    # strict canonical form: exact length and zero padding bits (one valid spelling per key)
    if len(out) != nbytes or (acc & ((1 << bits) - 1)) != 0:
        raise ValueError("key has the wrong length or non-canonical padding")
    return bytes(out)


def group(raw: str) -> str:
    return "MM2H-" + "-".join(raw[i:i + 5] for i in range(0, len(raw), 5))


def load_secret() -> bytes:
    env = os.environ.get("MM2_LICENSE_SECRET_HEX")
    if env:
        return bytes.fromhex(env)
    if not SECRET_FILE.exists():
        sys.exit("Секрета ещё нет. Выполните: python3 tools/keygen.py init")
    return bytes.fromhex(SECRET_FILE.read_text().strip())


def add_months(d: dt.datetime, months: int) -> dt.datetime:
    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1
    day = min(d.day, calendar.monthrange(year, month)[1])
    return d.replace(year=year, month=month, day=day)


UNITS = {
    "y": "years", "yr": "years", "yrs": "years", "year": "years", "years": "years",
    "mo": "months", "mon": "months", "month": "months", "months": "months",
    "w": "weeks", "week": "weeks", "weeks": "weeks",
    "d": "days", "day": "days", "days": "days",
    "h": "hours", "hr": "hours", "hrs": "hours", "hour": "hours", "hours": "hours",
    "m": "minutes", "min": "minutes", "mins": "minutes", "minute": "minutes", "minutes": "minutes",
    "s": "seconds", "sec": "seconds", "secs": "seconds", "second": "seconds", "seconds": "seconds",
}


def parse_duration(text: str) -> dict:
    parts = dict(years=0, months=0, weeks=0, days=0, hours=0, minutes=0, seconds=0)
    tokens = re.findall(r"(\d+)\s*([a-zA-Z]+)", text)
    rest = re.sub(r"(\d+)\s*([a-zA-Z]+)", "", text).strip(" ,;")
    if not tokens or rest:
        raise ValueError(f"cannot parse duration {text!r}; example: '1y 2mo 3d 4h 5m 6s'")
    for number, unit in tokens:
        key = UNITS.get(unit.lower())
        if key is None:
            raise ValueError(f"unknown unit {unit!r}")
        parts[key] += int(number)
    return parts


def expiry_absolute(issued: dt.datetime, parts: dict) -> dt.datetime:
    d = add_months(issued, parts["years"] * 12 + parts["months"])
    return d + dt.timedelta(weeks=parts["weeks"], days=parts["days"], hours=parts["hours"], minutes=parts["minutes"], seconds=parts["seconds"])


def duration_seconds(parts: dict) -> int:
    return (parts["years"] * 365 + parts["months"] * 30 + parts["weeks"] * 7 + parts["days"]) * 86400 \
        + parts["hours"] * 3600 + parts["minutes"] * 60 + parts["seconds"]


def make_key(secret: bytes, mode: int, issued: int, value: int, nonce: bytes) -> str:
    if not (0 <= issued <= MAX_U32 and 0 <= value <= MAX_U32):
        raise ValueError("value does not fit the key format (maximum year 2106)")
    payload = struct.pack(">BBII", VERSION, mode, issued, value) + nonce
    mac = hmac.new(secret, payload, hashlib.sha256).digest()[:MAC_BYTES]
    return group(b32encode(payload + mac))


def decode_key(secret: bytes, key: str) -> dict:
    body = re.sub(r"^\s*MM2H[-\s]*", "", key.upper())
    raw = b32decode(body, 14 + MAC_BYTES)
    payload, mac = raw[:14], raw[14:]
    ok = hmac.compare_digest(mac, hmac.new(secret, payload, hashlib.sha256).digest()[:MAC_BYTES])
    version, mode, issued, value = struct.unpack(">BBII", payload[:10])
    return dict(valid=ok, version=version, mode=mode, issued=issued, value=value, nonce=payload[10:].hex())


def fmt_ts(ts: int) -> str:
    return dt.datetime.fromtimestamp(ts, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def interactive() -> dict:
    print("Срок ключа (пусто = 0). Порядок: месяц, год, день, час, минута, секунда.")
    labels = [("months", "Месяцы"), ("years", "Годы"), ("days", "Дни"), ("hours", "Часы"), ("minutes", "Минуты"), ("seconds", "Секунды")]
    parts = dict(years=0, months=0, weeks=0, days=0, hours=0, minutes=0, seconds=0)
    for key, label in labels:
        raw = input(f"  {label}: ").strip()
        parts[key] = int(raw) if raw else 0
    return parts


def cmd_init(_args):
    LICENSE_DIR.mkdir(exist_ok=True)
    if SECRET_FILE.exists():
        print(f"Секрет уже есть: {SECRET_FILE} (не перезаписан)")
        return
    SECRET_FILE.write_text(os.urandom(32).hex() + "\n")
    os.chmod(SECRET_FILE, 0o600)
    print(f"Создан {SECRET_FILE}. Сделайте копию: потеряете его, и все ключи перестанут работать; утечка позволит любому выпускать ключи.")


def cmd_gen(args):
    secret = load_secret()
    if args.interactive:
        parts = interactive()
    elif args.duration:
        parts = parse_duration(args.duration)
    else:
        parts = dict(years=args.years, months=args.months, weeks=args.weeks, days=args.days, hours=args.hours, minutes=args.minutes, seconds=args.seconds)
    if not any(parts.values()) and not args.forever:
        sys.exit("Срок равен нулю. Укажите --duration '30d', отдельные флаги, --forever или используйте -i.")
    if any(v < 0 for v in parts.values()):
        sys.exit("Отрицательный срок недопустим.")
    now = int(args.now) if args.now else int(time.time())
    issued = dt.datetime.fromtimestamp(now, dt.timezone.utc)
    mode = 1 if args.mode == "activation" else 0
    value = None
    if not args.forever:
        if mode == 0:
            try:
                value = int(expiry_absolute(issued, parts).timestamp())
            except (OverflowError, ValueError):  # past year 9999: Python's dates end there
                value = None
        else:
            value = duration_seconds(parts)
        if value is not None and (value > MAX_U32 or (mode == 1 and now + value > MAX_U32)):
            value = None  # any number of years is allowed: past what the format holds the key simply has no limit
    if value is None:
        mode, args.mode, value = 0, "absolute", FOREVER
        summary = "бессрочный (навсегда)"
    elif mode == 0:
        summary = f"действует до {fmt_ts(value)}"
    else:
        summary = f"действует {value} секунд ({value / 86400:.2f} дн.) с момента первой активации"
    LICENSE_DIR.mkdir(exist_ok=True)
    new_file = not LOG_FILE.exists()
    with LOG_FILE.open("a", newline="") as f:
        w = csv.writer(f)
        if new_file:
            w.writerow(["issued_utc", "nonce", "mode", "value", "note", "key"])
        for _ in range(args.count):
            nonce = os.urandom(4)
            key = make_key(secret, mode, now, value, nonce)
            w.writerow([fmt_ts(now), nonce.hex(), args.mode, value, args.note, key])
            print(key)
    print(f"# ключей: {args.count}, режим: {'с первой активации' if args.mode == 'activation' else 'с момента выдачи'}, {summary}", file=sys.stderr)


def cmd_info(args):
    info = decode_key(load_secret(), args.key)
    print("подпись  :", "ВЕРНА" if info["valid"] else "НЕВЕРНА")
    print("версия   :", info["version"])
    print("выдан    :", fmt_ts(info["issued"]))
    if info["mode"] == 0 and info["value"] == FOREVER:
        print("режим    : бессрочный (навсегда)")
    elif info["mode"] == 0:
        print("режим    : с момента выдачи, действует до", fmt_ts(info["value"]))
        left = info["value"] - int(time.time())
        print("осталось :", f"{left // 86400} дн {(left % 86400) // 3600} ч {(left % 3600) // 60} мин" if left > 0 else "срок истёк")
    else:
        print("режим    : с первой активации, срок", info["value"], "секунд", f"({info['value'] / 86400:.2f} дн.)")
    print("номер    :", info["nonce"])


def cmd_list(_args):
    if not LOG_FILE.exists():
        print("Ключи ещё не выдавались.")
        return
    print(LOG_FILE.read_text())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init").set_defaults(fn=cmd_init)
    g = sub.add_parser("gen")
    g.add_argument("-i", "--interactive", action="store_true")
    g.add_argument("--duration", help="e.g. '1y 2mo 3d 4h 5m 6s'")
    for name in ("years", "months", "weeks", "days", "hours", "minutes", "seconds"):
        g.add_argument(f"--{name}", type=int, default=0)
    g.add_argument("--mode", choices=["absolute", "activation"], default="absolute")
    g.add_argument("--forever", action="store_true", help="key without a time limit")
    g.add_argument("--count", type=int, default=1)
    g.add_argument("--note", default="")
    g.add_argument("--now", help="override the issue time (unix seconds); for tests")
    g.set_defaults(fn=cmd_gen)
    i = sub.add_parser("info")
    i.add_argument("key")
    i.set_defaults(fn=cmd_info)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
