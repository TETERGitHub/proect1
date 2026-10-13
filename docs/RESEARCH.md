# Competitor research

## What could and could not be checked

| Source | Result |
|---|---|
| shitaro.lol | **Not reachable** from the build environment (DNS lookup failed) and the web search returned nothing about it. Nothing in this project is derived from it. |
| kiti.rock | Same: DNS failed, no search results. |
| headshot.pulse | No search results; the name could not be resolved to a site. |
| Generic MM2 hub listings | A web search surfaced aggregator pages and Scribd uploads describing *categories* of features (role ESP, speed/FOV sliders, tab menus, "kill all"). They were only used as a feature-category overview; no code was copied or read. |
| Public UI libraries | Rayfield, Orion, Fluent, Kavo are widely used by such hubs. The comparison below is based on **general knowledge of their public documentation, not verified in this session**. |

No closed-source code, private API or asset of any competitor was viewed, copied or imitated. The visual style (iOS-inspired glass) and every component were designed from scratch.

## Capability comparison (generic hub UI libraries vs this project)

| Function | Typical approach (from public library docs, unverified here) | Strength | Weakness | What this project does |
|---|---|---|---|---|
| Tabs / categories | Top or side tab bar, one scroll frame per tab | Simple | No search across tabs; many tabs get crowded | Sliding-pill sidebar + global ranked search over names, descriptions, categories and Russian names; compact icon sidebar on small windows |
| Toggles / sliders / dropdowns | Prebuilt components writing to a flag table | Quick to script | State often lives in the component, not in a settings store, so configs and UI can drift | All controls bind to one validated settings store; UI is generated from the schema so a control cannot exist without real state |
| Config saving | JSON file per config | Persistent | Often no validation, checksum or migration; breaks on corrupt files | Checksummed profiles, strict import validation, migration framework, integrity check, graceful fallback to session memory without file APIs |
| Notifications | Corner toasts | Visible | Fixed duration, no queue limits | Queue with visible cap, per-level colours, pooled cards, spring animations |
| Keybinds | Keybind component per feature | Familiar | Conflicts undetected, no typing guard | Central binding table, conflict detection, typing/focus guards, capture cancel on focus loss |
| Search | Rare | - | - | Fuzzy-ish AND search, filters (active, favourites, category), `>` command palette |
| Mobile | Often desktop-only | - | Tiny touch targets, no keyboard hotkeys | Device detection, compact preset, floating launcher, draggable on-screen feature buttons, touch drone controls |
| Cleanup | `:Destroy()` of the ScreenGui | - | Connections and loops leak on re-execute | Maid ownership everywhere, single scheduler, re-init detection, full restore of changed engine properties |

## Ideas deliberately **not** taken
- Role/player ESP, hidden-information readouts, kill/fling of real players, silent aim: these change other people's game or expose data the game withholds, so they are excluded. The training range, dummy and drone sandbox cover the visible/physics side of those categories on your own objects.
- Remote asset scrapers / "load from random site" content lists: content comes only from asset ids or files the user supplies.
