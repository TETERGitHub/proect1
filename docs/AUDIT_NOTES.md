## 6. Audit notes (hand-written)

### 6.1 Defects found, by severity

Stage 1 (commit `5014f40`) and stage 2 (this commit). "Test" is the regression test that fails without the fix.

| Sev | Defect | Fix | Test |
|---|---|---|---|
| P1 | Bundle loader left a failing module marked as loading; a retry reported a false "circular import" (`tools/build.py`) | `pcall` + clear the flag | `server/tests/test_build.py` |
| P1 | Loader unloaded the hub on **any** `ok:false` ping answer, including the rate limit (429) | only definite refusals are fatal | `t_audit` Loader, `test_integration` rate-limit |
| P1 | Double click / re-entrant submit started the hub twice | `busy` guard | `t_audit` Loader |
| P1 | Wrongly typed `expires`/`now` killed the heartbeat thread silently | numeric validation | `t_audit` Loader |
| P1 | `loader/main` used `uid = 0` when `LocalPlayer` was nil: the key would be bound to a fake account and later refused as "bound to another account" | wait for the player, otherwise send no uid (server answers `account id required`) | `test_integration` |
| P1 | Server trusted `X-Forwarded-For` from anyone: a client could rotate it to dodge the rate limit; limiter memory grew without bound | forwarding headers only from a loopback peer, last XFF entry / `CF-Connecting-IP`, bounded table | `test_server` RateLimitTrust |
| P2 | Base64 decoder accepted non-canonical trailing bits | strict check | `t_audit` Codec |
| P2 | JSON numbers: `1.`, `1.e5`, `1e400` accepted; DEL in a string rejected; duplicate key after `null` accepted; BOM not tolerated; fractional numbers lost precision (`%.14g`) | strict grammar, shortest round-trip form | `t_audit` Json |
| P2 | `Json.Null` contract undefined | contract written in `core/Json`, `keepNull` / `keepShape` / `Json.array` added | `t_audit` Json contract |
| P2 | `Core` / `Actions` reported the string `"nil"` as an error text after a clean stop / successful action | `if ok then nil else ...` | `t_audit` Core/Actions |
| P2 | `I18n.set` assigned two **globals** (`cache`, `cacheSize`) because the locals were declared later | declarations moved | `t_audit` I18n |
| P2 | Settings `ui.screenButtons / Size / Opacity` had no control anywhere in the UI | section added to the Interface page | `t_audit` "every visible setting has a control" |
| P2 | Pressing a favourite star at the 24-favourite limit did nothing and said nothing | warning notification | `t_audit` favourite test |
| P2 | `PayloadCipher.decrypt` threw on wrongly typed arguments | returns `nil, err` | `t_audit` PayloadCipher |
| P3 | `LicenseText.remaining` printed garbage for NaN / non-numbers | guarded | `t_audit` |
| P3 | 31 unused imports, dead loops / handlers, unused helpers | removed | full suite |

### 6.2 What the button table (section 4) shows

370 buttons were pressed once each on the mock, with a fresh favourites list each time. Totals are in section 4. The 18 presses that
changed nothing observable were each judged:

* reset / clear / stop buttons with nothing to reset (`Reset stats`, `Reset counters`, `Reset counter`, `Clear log`, stopwatch
  `Start/Lap/Reset` text-only changes, `Previous/Next/Reset` target selection with no targets): **correct no-ops**;
* `Enable practice targets` when the range is already on, built-in model picks (`neon`, `blade`) when already selected: **correct**;
* dropdown triggers (`cosmetics.charAttach`) open a popover the harness does not observe: **not verified here**;
* three music buttons and the now-playing row with an empty or paused player: **not verified here**.

Value controls (sliders, colour swatches, key capture) cannot be driven by a plain click; they are covered by the settings contract
test (every setting accepts valid/extreme values and refuses invalid ones with no module failing and no logged error) and by the
per-feature tests, **not** by this table. 98 settings have no literal mention in any test (section 3, last column): for those the
only automated evidence is the contract test plus the fact that the owning module runs; whether each one visibly changes the game
was not verified.

### 6.3 The 13 `env` and 2 `partial` features

They depend on engine behaviour the mock cannot reproduce: `ui.sounds`, `xh.dynamic`, `xh.owncharacter`, `gfx.brightness`,
`gfx.time`, `cam.sensitivity`, `cam.zoomspeed`, `cam.rememberzoom`, `cam.mode`, `cam.bob`, `cam.fov`, `perf.ping`,
`def.noCollide` (env) and `cfg.migrate`, `cam.smoothing` (partial). What the tests prove: the code writes the documented property,
restores the original on disable / unload / respawn, and tolerates a missing property. What they cannot prove: that a given game
or executor lets the write stick, or that another script does not overwrite it. Their statuses stay `env` / `partial`.

### 6.4 Not verified (honest list)

* Nothing ran in a real Roblox client or a real executor; the Luau layer was exercised on the Luau CLI with a hand-written mock
  (no layout engine: sizes, overlaps, touch-target sizes, scaling and real rendering are **not** checked).
* Real HTTPS, the Cloudflare tunnel and an executor `request` function were not exercised; the integration test uses real HTTP on
  localhost between the Python server and a replay shim in front of the real Luau loader (see `test_integration.py`).
* Phone behaviour (touch input, small layout) only through the mock's platform switch.
* Behaviour of each of the 98 settings listed in section 3 as "no test mentions it".
* Pure-Luau SHA-256 speed on phones.
* Dropdown popovers and music transport buttons in the button table (above).

### 6.5 Analyzer warnings left (`luau-analyze src loader tools`, unknown executor globals excluded)

* 18 `LocalUnused`: loop variables and tuple results kept for readability (`row1`, `r1`, ...), not defects.
* 10 `ImplicitReturn` in `Schema.check` closures and `parseValue`: functions return nothing on the success path by design.
* 9 `TypeError`: inference noise in non-strict files (`Settings.get` returns an unknown type; `table.clone` / `math.abs` after a
  narrowing the analyzer does not follow). The code paths run in tests.
* 3 `UnknownType` (`Instance`, `RBXScriptConnection`, `Enums`): Roblox types unknown to the stand-alone analyzer.
* 2 `LocalShadow`: `request` in `loader/main` intentionally shadows the executor global it wraps.

### 6.6 Open problems and next actions

1. **Payload format is unversioned and `expires`/`now` are unauthenticated** (see `docs/PROTOCOL.md`). Next: implement the `proto: 2`
   migration described there (needs a server release and a rebuilt `Loader.lua`).
2. **Error codes**: the loader matches English message text. Next: add `error_code` to the server and match on it.
3. **Offline revocation** is invisible by design; `maxPingFailures` is available but off by default. Decision for the owner.
4. **98 settings without a behavioural test.** Next: one assertion per setting group in the owning feature's test file.
5. **Real-environment verification** (an executor run, TLS, phone layout) can only be done by running `Loader.lua` yourself and
   sending the `[MM2Hub]` console lines.
