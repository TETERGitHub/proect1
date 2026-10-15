#!/usr/bin/env python3
"""Textures for features/HitFX (hit markers and bullet tracers), drawn for this project from distance fields.

  python3 tools/make_hitfx.py

assets/fx/hitmarkers.png   4 x 2 cells of 256 px: Classic, Burst, Diamond, Skull, Cross, Spark, Ring, Heart (white, tinted in game)
assets/fx/hitmarkers_outline.png   the same grown by a few pixels (drawn dark behind for readability)
assets/fx/tracer.png       a bullet streak for Beams: hot thin core, soft glow edges (white; along X)
assets/fx/tracer_energy.png  a tileable energy band (twisting strands) for the Energy tracer
then re-packs assets/fx into src/data/FxPack.luau.
"""
import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fx"
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import make_crosshairs as X  # noqa: E402  (same distance-field helpers)

MARKERS = ["Classic", "Burst", "Diamond", "Skull", "Cross", "Spark", "Ring", "Heart"]  # order = cells (features/HitFX)


def marker(name):
    seg, stroke, ring, union, fill_in, poly, fill_poly = X.seg, X.stroke, X.ring, X.union, X.fill_in, X.poly, X.fill_poly
    W = 0.11
    if name == "Classic":  # the four diagonal slashes with a gap, like most shooters
        return union(*(stroke(seg(sx * 0.28, sy * 0.28, sx * 0.85, sy * 0.85), W) for sx in (-1, 1) for sy in (-1, 1)))
    if name == "Burst":  # eight tapered spikes
        parts = []
        for k in range(8):
            a = k * math.pi / 4 + math.pi / 8
            r0, r1 = (0.3, 0.95) if k % 2 == 0 else (0.35, 0.7)
            c, s = math.cos(a), math.sin(a)
            h = 0.07
            parts.append(fill_poly([(c * r0 - s * h, s * r0 + c * h), (c * r1, s * r1), (c * r0 + s * h, s * r0 - c * h)]))
        return union(*parts)
    if name == "Diamond":
        r = 0.7
        return union(stroke(poly([(r, 0), (0, r), (-r, 0), (0, -r)]), W), stroke(poly([(0.35, 0), (0, 0.35), (-0.35, 0), (0, -0.35)]), W * 0.6))
    if name == "Skull":  # cartoon skull: head + jaw, eye and nose holes cut out
        head = np.clip(1 - np.hypot(X.X / 0.62, (X.Y - 0.12) / 0.56), 0, 1) > 0
        jaw = (np.abs(X.X) < 0.36) & (X.Y > -0.62) & (X.Y < -0.2)
        eyes = (np.hypot(X.X - 0.24, X.Y - 0.06) < 0.16) | (np.hypot(X.X + 0.24, X.Y - 0.06) < 0.16)
        nose = (np.abs(X.X) < 0.07 - (X.Y + 0.2) * 0.2) & (X.Y < -0.08) & (X.Y > -0.24)
        teeth = (np.abs(X.X) < 0.36) & (X.Y < -0.38) & (X.Y > -0.62) & (np.abs(((X.X + 0.36) / 0.18) % 1 - 0.5) > 0.42)
        m = (head | jaw) & ~eyes & ~nose & ~teeth
        img = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        return np.asarray(img, float) / 255
    if name == "Cross":  # thick plus with a hollow centre
        return union(*(stroke(seg(sx * 0.25, sy * 0.25, sx * 0.85, sy * 0.85), W * 1.3) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
    if name == "Spark":  # four-point sparkle
        pts = []
        for i in range(8):
            a = math.radians(45 + 45 * i)
            r = 0.9 if i % 2 == 0 else 0.18
            pts.append((r * math.cos(a), r * math.sin(a)))
        return fill_poly(pts)
    if name == "Ring":  # ring with four ticks
        return union(stroke(ring(0.55), W * 0.8), *(stroke(seg(sx * 0.65, sy * 0.65, sx * 0.92, sy * 0.92), W) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
    if name == "Heart":
        ts = np.linspace(0, 2 * math.pi, 120, endpoint=False)
        pts = [(0.05 * 16 * math.sin(t) ** 3, 0.05 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) + 0.1)
               for t in ts]
        return fill_poly(pts)
    raise ValueError(name)


def save(path, alpha, lum=None):
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = 255 if lum is None else (np.clip(lum, 0, 1) * 255).astype(np.uint8)[..., None]
    rgba[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)
    print("wrote", path, path.stat().st_size // 1024, "KB")


def main():
    X.grid(256, 0.8)
    sheet, outline = np.zeros((512, 1024)), np.zeros((512, 1024))
    for i, n in enumerate(MARKERS):
        a = marker(n)
        r, c = divmod(i, 4)
        sl = (slice(r * 256, (r + 1) * 256), slice(c * 256, (c + 1) * 256))
        sheet[sl], outline[sl] = a, X.grow(a, 6)
    save(OUT / "hitmarkers.png", sheet)
    save(OUT / "hitmarkers_outline.png", outline)
    # tracer: along X (Beam texture runs from Attachment0 to Attachment1), across Y: thin hot core + soft glow
    w, h = 256, 64
    yy = np.linspace(-1, 1, h)[:, None] * np.ones((1, w))
    xx = np.linspace(0, 1, w)[None, :] * np.ones((h, 1))
    core = np.exp(-(yy / 0.12) ** 2)
    glow = np.exp(-(yy / 0.45) ** 2) * 0.55
    a = np.clip(core + glow, 0, 1)
    save(OUT / "tracer.png", a, np.clip(0.6 + 0.4 * core, 0, 1))
    # energy: two twisting strands around the core, tileable along X (whole number of turns)
    strands = np.zeros((h, w))
    for ph in (0, math.pi):
        yc = 0.45 * np.sin(xx * 2 * math.pi * 3 + ph)
        strands = np.maximum(strands, np.exp(-((yy - yc) / 0.1) ** 2) * (0.6 + 0.4 * np.cos(xx * 2 * math.pi * 3 + ph)))
    a = np.clip(np.exp(-(yy / 0.1) ** 2) + strands + np.exp(-(yy / 0.6) ** 2) * 0.3, 0, 1)
    save(OUT / "tracer_energy.png", a)
    if "--no-pack" not in sys.argv:
        import make_fx_assets
        make_fx_assets.pack()


if __name__ == "__main__":
    main()
