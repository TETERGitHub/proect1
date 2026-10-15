#!/usr/bin/env python3
"""Draws the hub's own textured crosshairs (features/Crosshair, setting crosshair.design) and packs them with the effect textures.

  python3 tools/make_crosshairs.py

Writes three sheets of 12 designs (4 x 3 cells of 256 px, white on transparent, anti-aliased from distance fields) into assets/fx:
  crosshairs.png          the crosshair itself (tinted in game with the chosen colour)
  crosshairs_outline.png  the same shapes grown by a few pixels (drawn dark behind it for readability)
  crosshairs_glow.png     a soft blurred halo (drawn in the crosshair colour behind it when Glow is on)
then re-packs assets/fx into src/data/FxPack.luau. Original drawings made for this project.
"""
import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fx"
CELL = 256
COLS, ROWS = 4, 3
# order = cell index; must match DESIGNS in src/features/Crosshair.luau
NAMES = ["Sniper", "Tactical", "Diamond", "Chevron", "Hexagon", "Star", "Brackets", "Tri", "Segments", "Scope", "Heart", "X"]

FIT = 0.8  # the drawings use -1..1, shown in the middle 80% of the cell so the outline and glow fit inside it
PX = 2.0 / CELL / FIT  # one pixel in the drawing's -1..1 space
yy, xx = np.mgrid[0:CELL, 0:CELL]
X = ((xx + 0.5) / CELL * 2 - 1) / FIT
Y = (1 - (yy + 0.5) / CELL * 2) / FIT  # up is +


def seg(ax, ay, bx, by):
    """distance from every pixel to the segment a-b"""
    px, py = X - ax, Y - ay
    dx, dy = bx - ax, by - ay
    t = np.clip((px * dx + py * dy) / max(dx * dx + dy * dy, 1e-12), 0, 1)
    return np.hypot(px - t * dx, py - t * dy)


def ring(r):
    return np.abs(np.hypot(X, Y) - r)


def poly(points, closed=True):
    d = np.full(X.shape, 9.0)
    n = len(points)
    for i in range(n if closed else n - 1):
        a, b = points[i], points[(i + 1) % n]
        d = np.minimum(d, seg(a[0], a[1], b[0], b[1]))
    return d


def stroke(d, w):
    """coverage of a line of width w (in -1..1 units) around distance field d"""
    return np.clip((w / 2 - d) / PX + 0.5, 0, 1)


def fill_in(inside_d):
    """coverage of a filled shape from a signed distance (negative inside)"""
    return np.clip(-inside_d / PX + 0.5, 0, 1)


def arc_mask(a0, a1):
    ang = np.degrees(np.arctan2(Y, X)) % 360
    a0, a1 = a0 % 360, a1 % 360
    return (ang >= a0) & (ang <= a1) if a0 <= a1 else (ang >= a0) | (ang <= a1)


def fill_poly(points, ss=4):
    """anti-aliased filled polygon (supersampled), for shapes that are not convex"""
    from PIL import ImageDraw
    img = Image.new("L", (CELL * ss, CELL * ss), 0)
    ImageDraw.Draw(img).polygon([((x * FIT + 1) / 2 * CELL * ss, (1 - y * FIT) / 2 * CELL * ss) for x, y in points], fill=255)
    return np.asarray(img.resize((CELL, CELL), Image.LANCZOS), dtype=float) / 255


def union(*alphas):
    out = np.zeros(X.shape)
    for a in alphas:
        out = np.maximum(out, a)
    return out


W = 0.056  # standard line width (~6 px at 256)


def design(name):
    if name == "Sniper":  # thin cross with a gap, outer ring and mil-dot ticks
        lines = union(*(stroke(seg(sx * 0.16, sy * 0.16, sx * 0.92, sy * 0.92), W * 0.7) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
        ticks = union(*(stroke(seg(t * sx - sy * 0.05, t * sy - sx * 0.05, t * sx + sy * 0.05, t * sy + sx * 0.05), W * 0.6)
                        for t in (0.35, 0.55) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
        return union(lines, ticks, stroke(ring(0.72), W * 0.7), fill_in(np.hypot(X, Y) - 0.035))
    if name == "Tactical":  # four tapered arms pointing at the centre + dot
        arms = []
        for k in range(4):
            a = k * math.pi / 2
            c, s_ = math.cos(a), math.sin(a)
            tip, base, half = 0.22, 0.78, 0.075
            pts = [(c * tip, s_ * tip), (c * base - s_ * half, s_ * base + c * half), (c * base + s_ * half, s_ * base - c * half)]
            d = poly(pts)
            # inside the triangle: the same side of all three edges
            crosses = [(x1 - x0) * (Y - y0) - (y1 - y0) * (X - x0) for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])]
            inside = np.all([c_ >= 0 for c_ in crosses], axis=0) | np.all([c_ <= 0 for c_ in crosses], axis=0)
            sd = np.where(inside, -d, d)
            arms.append(fill_in(sd))
        return union(*arms, fill_in(np.hypot(X, Y) - 0.06))
    if name == "Diamond":
        r = 0.55
        return union(stroke(poly([(r, 0), (0, r), (-r, 0), (0, -r)]), W), fill_in(np.hypot(X, Y) - 0.06))
    if name == "Chevron":  # red-dot style chevron under the point + dot
        return union(stroke(poly([(-0.45, -0.55), (0, -0.12), (0.45, -0.55)], closed=False), W * 1.2), fill_in(np.hypot(X, Y) - 0.06))
    if name == "Hexagon":
        pts = [(0.62 * math.cos(math.radians(90 + 60 * i)), 0.62 * math.sin(math.radians(90 + 60 * i))) for i in range(6)]
        ticks = union(*(stroke(seg(0.18 * math.cos(math.radians(a)), 0.18 * math.sin(math.radians(a)), 0.36 * math.cos(math.radians(a)),
                                   0.36 * math.sin(math.radians(a))), W * 0.8) for a in (90, 210, 330)))
        return union(stroke(poly(pts), W * 0.8), ticks)
    if name == "Star":  # four-point sparkle in a thin ring
        pts = []
        for i in range(8):
            a = math.radians(90 + 45 * i)
            r = 0.5 if i % 2 == 0 else 0.13
            pts.append((r * math.cos(a), r * math.sin(a)))
        return union(fill_poly(pts), stroke(ring(0.74), W * 0.55))
    if name == "Brackets":  # four corner brackets around the centre + dot
        s = 0.5
        L = 0.24
        parts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                parts.append(stroke(poly([(sx * s, sy * (s - L)), (sx * s, sy * s), (sx * (s - L), sy * s)], closed=False), W))
        return union(*parts, fill_in(np.hypot(X, Y) - 0.055))
    if name == "Tri":  # three ticks at 120 degrees and a broken ring
        ticks = union(*(stroke(seg(0.2 * math.cos(math.radians(a)), 0.2 * math.sin(math.radians(a)), 0.62 * math.cos(math.radians(a)),
                                   0.62 * math.sin(math.radians(a))), W) for a in (90, 210, 330)))
        arcs = union(*(stroke(ring(0.62), W * 0.6) * arc_mask(a + 20, a + 100) for a in (90, 210, 330)))
        return union(ticks, arcs, fill_in(np.hypot(X, Y) - 0.05))
    if name == "Segments":  # ring broken into four arcs + dot
        arcs = union(*(stroke(ring(0.5), W) * arc_mask(a + 15, a + 75) for a in (0, 90, 180, 270)))
        return union(arcs, fill_in(np.hypot(X, Y) - 0.06))
    if name == "Scope":  # duplex reticle: thick outer posts, thin centre lines, big circle
        thin = union(*(stroke(seg(0, 0, sx * 0.55, sy * 0.55), W * 0.45) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
        thick = union(*(stroke(seg(sx * 0.55, sy * 0.55, sx * 0.9, sy * 0.9), W * 1.6) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
        return union(thin, thick, stroke(ring(0.9), W * 0.7))
    if name == "Heart":
        # the classic parametric heart, sampled into a closed outline
        ts = np.linspace(0, 2 * math.pi, 120, endpoint=False)
        pts = [(0.034 * 16 * math.sin(t) ** 3, 0.034 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) + 0.06)
               for t in ts]
        return union(stroke(poly(pts), W), fill_in(np.hypot(X, Y) - 0.05))
    if name == "X":  # diagonal cross with a gap + dot
        r = 0.7071
        return union(*(stroke(seg(sx * 0.14 * r, sy * 0.14 * r, sx * 0.62 * r * 1.2, sy * 0.62 * r * 1.2), W) for sx in (-1, 1) for sy in (-1, 1)),
                     fill_in(np.hypot(X, Y) - 0.05))
    raise ValueError(name)


def grow(alpha, px):
    """alpha grown outward by px pixels (for the dark outline)"""
    img = Image.fromarray((alpha * 255).astype(np.uint8))
    for _ in range(px):
        img = img.filter(ImageFilter.MaxFilter(3))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), dtype=float) / 255


def main():
    sheet, outline, glow = (np.zeros((ROWS * CELL, COLS * CELL)) for _ in range(3))
    for i, name in enumerate(NAMES):
        a = design(name)
        o = grow(a, 4)  # per cell, so nothing bleeds into the neighbouring design
        g = np.asarray(Image.fromarray((grow(a, 6) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12)), dtype=float) / 255
        r, c = divmod(i, COLS)
        cell = (slice(r * CELL, (r + 1) * CELL), slice(c * CELL, (c + 1) * CELL))
        sheet[cell], outline[cell], glow[cell] = a, o, np.clip(g * 1.6, 0, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, a in (("crosshairs.png", sheet), ("crosshairs_outline.png", outline), ("crosshairs_glow.png", glow)):
        rgba = np.zeros(a.shape + (4,), np.uint8)
        rgba[..., :3] = 255
        rgba[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(rgba, "RGBA").save(OUT / name, optimize=True)
        print("wrote", OUT / name, (OUT / name).stat().st_size // 1024, "KB")
    if "--no-pack" not in sys.argv:
        sys.path.insert(0, str(pathlib.Path(__file__).parent))
        import make_fx_assets
        make_fx_assets.pack()


if __name__ == "__main__":
    main()
