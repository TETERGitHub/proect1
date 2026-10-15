# KillFX offline preview

Records every frame of the real `src/features/KillFX.luau` (with a small Roblox-like world that has real rotation maths,
`prelude.luau`) and draws the frames with a flat-shaded software renderer (`render.py`), so the effects can be looked at
without Roblox. **It is an approximation**: no Roblox lighting, bloom, shadows or materials; the victim is a classic dummy.

    python3 tools/killfx_preview/make.py [path/to/luau]   # writes <Effect>.txt frame dumps
    python3 tools/killfx_preview/render.py                # writes <Effect>.gif and <Effect>_strip.png
