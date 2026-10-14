# Visual system ("glass" interface, an original design concept)

This is the project's own design language, inspired by translucent iOS-style interfaces. It is not an official or actual iOS spec. Roblox gives scripts no background blur, so "glass" here means translucency, a thin light edge and a faint sheen. Nothing is blurred or refracted.

## Where it lives
| Piece | Module |
|---|---|
| Palette, glass amount, surface levels, edges, sheen, radii, type scale, spacing | `src/ui/Theme.luau` |
| Motion classes (`fast .12 / std .22 / slow .4` s), tween conflict cancellation, reduced-effects easing | `src/ui/Motion.luau` |
| Components: surface, button (states), icon button, toggle, slider, segmented, input, popover, confirm, page header/cards | `src/ui/Framework.luau` |
| Window, title bar, grouped navigation, toasts, launcher | `src/ui/Window.luau` |
| Licence key window (shared by the in-script gate and the loader) | `src/ui/KeyCard.luau` |
| On-screen pinned buttons | `src/ui/ScreenButtons.luau` |

## Rules
- Surface levels: window, rail, card, control, popover, modal, toast. Components ask `F.surface(parent, level)` and do not pick transparencies themselves.
- `Theme.glassAmount()` is 0 when `ui.reduceEffects` is on, the low load profile is active, or the theme has no glass. Then surfaces are solid and sheen and gradients are hidden. Spring/bounce easing becomes plain smooth easing.
- Settings: `ui.glass` (0-1), `ui.opacity`, `ui.reduceEffects`, `ui.cornerRadius`, `ui.animSpeed` (0 turns animations off).
- Button states: default, hover, pressed, disabled, loading, plus a brief success/error flash.
- A new tween on a property cancels the running one, so animations do not pile up; `Motion.cancel(inst)` before destroying.

## Checking the look
`python3 tools/ui_render.py [--jobs a,b]` renders PNGs to `dist/shots` plus `issues.txt` (text overflow, small buttons). It is a proxy: its own layout, Inter standing in for Gotham, no real blur. It is not Roblox. Real appearance must be checked in an executor.
