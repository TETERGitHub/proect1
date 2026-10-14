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

Tested: the Python server logic and HTTP layer (`python3 -m unittest discover -s server/tests`, 19 tests; the 4 module-loader tests need the Luau CLI and are skipped without it) and the Luau loader flow against Python-encrypted vectors (`tests/t_license.luau`). **Not tested against a real executor or a live deployment.**

## Loader behaviour (what the audit pinned down by tests)

- Dependencies are checked up front; a missing one raises `loader: missing dependency '<name>'`.
- Executor response shapes differ: `Body`/`body`/`Response`, a bare string and `nil` are all handled; the console line `[MM2Hub] http: no body (status …)` shows what the executor returned.
- A second activation while one is running or in flight is ignored, so the hub can never start twice.
- Heartbeat: only a definite refusal (revoked, expired, invalid key, bound to another account, not valid yet) unloads the hub. A rate limit, a malformed request or an unknown message is logged and ignored. Network failures are counted in `handle.pingFailures` and logged; the local term check keeps running, so an offline hub still stops when its term ends.
- A wrongly typed `expires`/`now` from the server is ignored instead of killing the heartbeat thread.
- `unload` and `notify` errors are contained; `stop()` is idempotent.
- The loader clock is `os.time()` (wall clock), not `os.clock()` (process CPU time).

## Payload cipher: honest assessment

`core/PayloadCipher` is a home-made encrypt-then-MAC construction (SHA-256 counter keystream + truncated HMAC-SHA256 tag, one key `k` for both roles). Properties checked by tests: the tag is verified before any decryption; every single-byte change, truncation or other nonce is refused; Luau output is byte-identical to Python. Weaknesses that remain and are **not** fixed because they need a coordinated change of server and every distributed Loader: no version byte, no key separation between keystream and MAC (HKDF with separate labels would be cleaner), a 128-bit truncated tag, and security that depends on the server never repeating a nonce (it draws 12 random bytes per request). It is adequate against casual tampering; it is not a substitute for a reviewed AEAD, and anyone who holds a valid key can always decrypt their own payload, because the client must.

Executors must provide an HTTP request function (`request`/`http_request`/`syn.request`/…) and `loadstring`; the loader tells the user when they are missing.

## Permanent hosting (a VPS or any always-on Linux machine)

The quick tunnel is for testing: its address changes on every start. For a fixed address:

1. Rent a small VPS (1 vCPU / 512 MB is plenty) and point a domain or sub-domain at its IP.
2. On the VPS: `git clone -b claude/youthful-cray-l6ypwp https://github.com/TETERGitHub/proect1.git && cd proect1`
3. `python3 tools/keygen.py init` (or copy your existing `.license/secret.hex` so the keys you already issued keep working), then `python3 tools/build.py`.
4. Run the server as a service (`/etc/systemd/system/mm2hub.service`):
   ```
   [Unit]
   Description=MM2 Hub licence server
   After=network.target
   [Service]
   WorkingDirectory=/home/YOURUSER/proect1
   ExecStart=/usr/bin/python3 server/app.py --host 127.0.0.1 --port 8787
   Restart=always
   User=YOURUSER
   [Install]
   WantedBy=multi-user.target
   ```
   `sudo systemctl enable --now mm2hub`
5. HTTPS with Caddy (obtains certificates automatically). `/etc/caddy/Caddyfile`:
   ```
   licence.your-domain.example {
       reverse_proxy 127.0.0.1:8787
   }
   ```
   `sudo systemctl reload caddy`
6. On any machine with the project: `python3 tools/build.py --loader --server-url https://licence.your-domain.example` and distribute `dist/Loader.lua` once; it stays valid as long as the address stays the same.
7. Keep `.license/` backed up (secret, issued keys, activation state) and out of git.

## First run in an executor - checklist

1. Run `Loader.lua` in the executor. Open its console (F9 / the executor's output window): the loader prints `[MM2Hub] step 1/5 ... step 5/5 hub started`.
2. Paste the test key into the window that appears and press Activate.
3. If it stops, the last `step N/5 FAILED` line says where:
   - step 2: the server could not be reached or refused the key (check the tunnel is up, the key is not expired, the key is not bound to another account);
   - step 3: authentication failed (the hub bundle on the server was rebuilt after the key was activated, or the data was altered) or decrypting was too slow;
   - step 4: the executor's `loadstring` rejected the code;
   - step 5: the hub raised an error while starting; open the hub's Diagnostics page or export the report.
4. Report the console lines (never the key itself) when asking for help.
