# Server-licensed build (the strongest protection this project offers)

A client-side key check can always be patched out. In the server-licensed build the **hub code is not in the file you distribute**:
users get `Loader.lua` (about 28 KB, no signing secret, no hub code). It sends the key to *your* server, which verifies it and returns the hub **encrypted for that key**; the loader authenticates (HMAC) and decrypts it in memory and runs it.

```
user ── Loader.lua ── POST /v1/activate {key, uid} ──▶  your server (HTTPS)
                                                         ├ verifies signature, expiry, revocation
                                                         ├ binds the key to the first Roblox account (optional)
                                                         └ encrypts dist/MM2Hub.lua for this key
user ◀── {expires, nonce, tag, payload} ─────────────────┘
        decrypt → loadstring → run;  heartbeat /v1/ping every 5 min (revocation + term)
```

## Steps

```bash
python3 tools/keygen.py init                         # secret stays on the server machine
python3 tools/build.py                               # hub bundle WITHOUT the secret  -> dist/MM2Hub.lua
python3 tools/build.py --loader --server-url https://licence.example.com   # -> dist/Loader.lua  (distribute this)
python3 tools/keygen.py gen --duration "1mo"         # make keys
python3 server/app.py --host 127.0.0.1 --port 8787   # run behind a TLS reverse proxy (Caddy / nginx / Cloudflare Tunnel)
```

Revoke a key: append its key id (`keygen.py info <key>` → "key id") to `.license/revoked.txt`.
Disable one-account binding with `--no-uid-binding`. Requests are rate-limited per address (12 / minute).

## What this does and does not give you

Raises the cost a lot:
- without a valid key nobody receives the hub code, so there is nothing to cut the check out of;
- the signing secret never leaves the server; users cannot mint keys;
- expiry, revocation and account binding are decided by the server clock and state;
- tampered or foreign payloads fail the HMAC before anything is executed.

Does **not** make it unbreakable:
- someone with one valid key can dump the decrypted code from memory in their executor;
- a modified loader can skip the heartbeat (the local term check in the loader can also be patched); a leaked key can be revoked but already-dumped code cannot be recalled;
- the server must be run over HTTPS and kept up to date; you are responsible for its availability, hosting and abuse handling.

Tested: the Python server logic and HTTP layer (`python3 -m unittest discover -s server/tests`, 12 tests) and the Luau loader flow against Python-encrypted vectors (`tests/t_license.luau`). **Not tested against a real executor or a live deployment.**

Executors must provide an HTTP request function (`request`/`http_request`/`syn.request`/…) and `loadstring`; the loader tells the user when they are missing.
