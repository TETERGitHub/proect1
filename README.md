# MM2 Hub

A modular client-side Lua/Luau hub for Roblox *Murder Mystery 2* and compatible executors: iOS-style glass UI,
profiles, search, hotkeys, local visual tools and a local training sandbox. Written from scratch; no code, assets
or images of other hubs are used (all icons, models and sounds are drawn/built or supplied by you).

## Boundaries (by design)
- Everything runs on **your client** and changes only what **you** see. It does not reveal hidden information
  (such as other players' roles), does not fire at, push, fling or kill real players, and does not alter MM2's hit registration.
- Training features (targets, dummy, hitbox lab, Select Aim) operate on **local test objects** only.
- Ghost (local invisibility) is a visual effect on your own screen; Roblox does not replicate it.

## One-click setup on your PC (Windows)
Double-click `START_WINDOWS.bat` (needs Python 3): a menu builds the hub, starts the licence server with a free HTTPS tunnel, builds `dist/Loader.lua` for it and creates time-limited keys. A ready-made prompt for an AI assistant in Visual Studio / VS Code is in [docs/SETUP_PROMPT.md](docs/SETUP_PROMPT.md).

## Build and use
```bash
python3 tools/build.py                 # dist/MM2Hub.lua  - one self-contained script, run it in your executor
python3 tools/run_tests.py             # builds the test bundle, runs it with the Luau CLI, writes docs/TESTING.md
python3 tools/gen_docs.py              # regenerates docs/FEATURES.md from the live registry
python3 tools/audit_registry.py        # regenerates docs/AUDIT.md (runs tests/audit_dump.luau: presses every button on the mock)
python3 -m unittest discover -s server/tests   # server, module-loader, build-reproducibility and loader<->server integration tests
python3 tools/count.py                 # line counts
python3 -m unittest discover -s server/tests    # licence-server tests
```
Tools needed: the standalone [Luau](https://github.com/luau-lang/luau) CLI (`luau`), Python 3.

## What is inside
| Area | Where |
|---|---|
| Core (events, cleanup, logging, settings, profiles, hotkeys, scheduler, search, diagnostics, lifecycle) | `src/core` |
| UI (theme engine, drawn icons, animation, components, window, pages, on-screen buttons, phone preset) | `src/ui` |
| Features (crosshair, camera, lighting, training range + hitbox lab + Select Aim, cosmetics, music, sounds, ghost, anti-fling, tools) | `src/features` |
| Data (settings schema, feature catalogue, themes, icons, strings) | `src/data` |
| Licence keys, loader, server | `tools/keygen.py`, `loader/`, `server/`, [docs/LICENSE.md](docs/LICENSE.md), [docs/SERVER.md](docs/SERVER.md) |

Documents: [FEATURES.md](docs/FEATURES.md) (119+ catalogued features with honest status), [TESTING.md](docs/TESTING.md)
(generated from real test runs), [RESEARCH.md](docs/RESEARCH.md) (competitor research and its gaps), [ARCHITECTURE.md](docs/ARCHITECTURE.md), [PROTOCOL.md](docs/PROTOCOL.md) (key format, wire protocol, cipher, loader state machine, known weaknesses), [AUDIT.md](docs/AUDIT.md) (generated file / feature / settings / button registry plus audit notes).

## Verification status - read this
- **Run and passing**: the logic layer and the Roblox-facing modules against a **mock** Roblox layer (`tests/mock_roblox.luau`),
  plus type-checking of the Roblox API usage against the official type definitions, plus the Python server/keygen tests.
- **Not run**: inside a real Roblox client or any specific executor (Xeno, Delta, ...). Rendering, real physics, real
  `Touched`/raycast behaviour, executor file/HTTP APIs and real MM2 behaviour are unverified. Features marked `env` or
  `partial` in the catalogue depend on that.
- Licence keys are signed and time-limited, but a client-side check can be patched out; real protection needs the
  server-delivered build described in docs/SERVER.md.
