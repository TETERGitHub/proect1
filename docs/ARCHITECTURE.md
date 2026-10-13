# Architecture

One composition root (`src/app/Hub.luau`) defines the settings, registers actions and hotkeys, registers every feature as a
lifecycle module and starts them in dependency order through `core/Core`. Each module receives a `ctx.maid`; whatever it
gives to the maid (connections, instances, scheduler handles, restore callbacks) is released in reverse order on stop, so a
module can be stopped, restarted or unloaded without leaks. `Hub.unload()` also resets every singleton, so the hub can start again.

```
main ─▶ app/Hub ─▶ core/Core (modules, deps, restart)      core/Settings ◀─ UI controls, features, Config
                    ├ services  (RenderStepped → Perf.frame; the only per-frame pump)
                    ├ input     (core/Input ─ UserInputService)
                    ├ window    (ui/Window + Pages + Framework + Theme + Motion + Icons)
                    └ crosshair camera lighting training drone cosmetics music sounds screenbuttons antifling selectaim ghost
```

Design rules
- **One settings store** (`core/Settings`, schema in `data/Schema`): validated, observable, resettable by key/page/module, exported with a checksum by `core/Config`. UI pages are generated from the schema, so a control cannot exist without real state.
- **One scheduler** (`core/Perf`): modules call `Perf.every(name, hz, fn)`; no private loops. Per-task timing, error isolation (a task that fails five times is disabled), visual-rate cap and a low-load profile.
- **Pure logic is separate from engine code** (`*Logic`, `*Math`, `Geometry`, `CrosshairLayout`, `Sources`, `Playlist` ...) so it is unit-tested with real assertions; the engine adapters are thin.
- **No Roblox access at load time** (`core/Services` is lazy), so every module can be imported and tested without a game.
- **Restore what you change**: camera, lighting, collisions, transparency, mouse icon and name-tag values are captured before use and restored on disable or unload.
- **Layers are never conflated** in the hitbox lab: visual hitbox (cosmetic), physical geometry (real collisions between local parts), server registration (not available - stated in the UI).
