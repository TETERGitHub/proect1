"""Licence server logic (no networking here, so it is unit-testable).

Verifies keys produced by tools/keygen.py, enforces expiry / revocation / one-account binding,
and encrypts the hub bundle for a verified key with the construction in src/core/PayloadCipher.luau.
"""
import hashlib
import hmac
import json
import os
import pathlib
import struct
import sys
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import keygen  # noqa: E402


def canonical_key(text: str) -> str:
    """Normalise any accepted spelling of a key to the canonical grouped form."""
    import re
    body = re.sub(r"^\s*MM2H[-\s]*", "", text.upper())
    raw = keygen.b32decode(body, 24)
    return keygen.group(keygen.b32encode(raw))


def derive_key(canonical: str, nonce: bytes) -> bytes:
    return hashlib.sha256(b"MM2HUB-PAYLOAD" + canonical.encode() + nonce).digest()


def encrypt_payload(canonical: str, nonce: bytes, plaintext: bytes):
    k = derive_key(canonical, nonce)
    out = bytearray()
    for i, off in enumerate(range(0, len(plaintext), 32)):
        ks = hashlib.sha256(k + struct.pack(">I", i)).digest()
        chunk = plaintext[off:off + 32]
        out.extend(b ^ s for b, s in zip(chunk, ks))
    cipher = bytes(out)
    tag = hmac.new(k, nonce + cipher, hashlib.sha256).hexdigest()[:32]
    return cipher, tag


class LicenseStore:
    """Tiny JSON-file store: first-activation time and bound Roblox user id per key id."""

    def __init__(self, path: pathlib.Path, revoked_path: pathlib.Path, seats_path: pathlib.Path = None):
        self.path = path
        self.revoked_path = revoked_path
        # how many Roblox accounts may use each key (key id -> number), written by keygen.py --users; 1 when not listed
        self.seats_path = seats_path if seats_path is not None else path.parent / "seats.json"
        self._seats = (None, {})
        self.lock = threading.Lock()
        self.data = {}
        if path.exists():
            self.data = json.loads(path.read_text() or "{}")

    def revoked(self) -> set:
        if not self.revoked_path.exists():
            return set()
        return {l.strip().lower() for l in self.revoked_path.read_text().splitlines() if l.strip() and not l.startswith("#")}

    def seats(self, nonce: str) -> int:
        """accounts allowed for this key id (re-read when keygen adds keys while the server runs)"""
        try:
            mtime = self.seats_path.stat().st_mtime
        except OSError:
            return 1
        if self._seats[0] != mtime:
            try:
                self._seats = (mtime, {k.lower(): int(v) for k, v in json.loads(self.seats_path.read_text() or "{}").items()})
            except (ValueError, TypeError, OSError):
                self._seats = (mtime, {})
        return max(1, self._seats[1].get(nonce.lower(), 1))

    def _save(self):
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=1))
        os.replace(tmp, self.path)


class LicenseService:
    def __init__(self, secret: bytes, store: LicenseStore, bundle: bytes, bind_uid: bool = True, clock=time.time):
        self.secret = secret
        self.store = store
        self.bundle = bundle
        self.bind_uid = bind_uid
        self.clock = clock

    def check(self, key_text: str, uid, commit: bool):
        """Returns (ok, info_or_error). commit=True records first activation / uid binding."""
        try:
            canonical = canonical_key(key_text)
            info = keygen.decode_key(self.secret, canonical)
        except Exception:
            return False, "invalid key"
        if not info["valid"]:
            return False, "invalid key"
        if info["nonce"] in self.store.revoked():
            return False, "this key has been revoked"
        now = int(self.clock())
        if info["issued"] - now > 2 * 86400:
            return False, "key is not valid yet"
        with self.store.lock:
            rec = self.store.data.get(info["nonce"], {})
            uids = list(rec.get("uids") or ([rec["uid"]] if rec.get("uid") is not None else []))
            if self.bind_uid:
                if uid is None:
                    return False, "account id required"
                seats = self.store.seats(info["nonce"])
                if uid not in uids and len(uids) >= seats:
                    # the first `seats` accounts that used the key keep it; everyone after them is refused
                    return False, "key is already bound to another account" if seats == 1 else "this key has no free places left"
            if info["mode"] == 0:
                expires = info["value"]
            else:
                first = rec.get("first", now)
                expires = first + info["value"]
            if now >= expires:
                return False, "key expired"
            if commit:
                rec.setdefault("first", now)
                if self.bind_uid:
                    if uid not in uids:
                        uids.append(uid)
                    rec["uids"] = uids
                    rec["uid"] = uids[0]  # older servers / tools read the first account here
                rec["last"] = now
                self.store.data[info["nonce"]] = rec
                self.store._save()
        return True, {"expires": expires, "now": now, "canonical": canonical, "nonce": info["nonce"]}

    def activate(self, key_text: str, uid):
        ok, res = self.check(key_text, uid, commit=True)
        if not ok:
            return {"ok": False, "error": res}
        nonce = os.urandom(12)
        cipher, tag = encrypt_payload(res["canonical"], nonce, self.bundle)
        import base64
        return {
            "ok": True,
            "expires": res["expires"],
            "now": res["now"],
            "nonce": base64.b64encode(nonce).decode(),
            "tag": tag,
            "payload": base64.b64encode(cipher).decode(),
        }

    def ping(self, key_text: str, uid):
        ok, res = self.check(key_text, uid, commit=False)
        if not ok:
            return {"ok": False, "error": res}
        return {"ok": True, "expires": res["expires"], "now": res["now"]}
