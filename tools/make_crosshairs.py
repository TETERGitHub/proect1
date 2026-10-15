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


def grid(cell, fit=0.8):
    """sets the pixel grid the drawing helpers work on: a cell of `cell` px, the -1..1 drawing in its middle `fit` part"""
    global CUR, FIT, PX, X, Y
    CUR, FIT = cell, fit
    PX = 2.0 / cell / fit  # one pixel in the drawing's -1..1 space
    yy, xx = np.mgrid[0:cell, 0:cell]
    X = ((xx + 0.5) / cell * 2 - 1) / fit
    Y = (1 - (yy + 0.5) / cell * 2) / fit  # up is +


grid(CELL)


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
    img = Image.new("L", (CUR * ss, CUR * ss), 0)
    ImageDraw.Draw(img).polygon([((x * FIT + 1) / 2 * CUR * ss, (1 - y * FIT) / 2 * CUR * ss) for x, y in points], fill=255)
    return np.asarray(img.resize((CUR, CUR), Image.LANCZOS), dtype=float) / 255


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


# ------------------------------------------------------------------------------------------------ animated crosshairs
# Each one is 16 frames in a 4 x 4 sheet (xa_<name>.png + _outline + _glow at half size); the hub steps through the frames.
# The order and cell sizes must match ANIMATED in src/features/CrosshairImage.luau.
ANIM = [("Radar", 128), ("Ripple", 128), ("Lock-on", 128), ("Orbit", 128), ("Breathe", 128), ("Menacing", 256)]
FRAMES = 16


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def rot_pts(pts, a):
    c, s_ = math.cos(a), math.sin(a)
    return [(x * c - y * s_, x * s_ + y * c) for x, y in pts]


def over(A, L, a, l):
    """composite coverage a with luminance l over (A, L)"""
    na = a + A * (1 - a)
    nl = np.where(na > 1e-6, (l * a + L * A * (1 - a)) / np.maximum(na, 1e-6), 0)
    return na, nl


_glyph = None


def glyph():
    """the JoJo-style 'ゴ' sound effect: bold, slanted, white with a dark rim (IPA Gothic, rendered to an image)"""
    global _glyph
    if _glyph is None:
        from PIL import ImageDraw, ImageFont
        size = 120
        font = None
        for f in ("/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf", "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",
                  "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"):
            try:
                font = ImageFont.truetype(f, size)
                break
            except OSError:
                pass
        img = Image.new("L", (size + 60, size + 60), 0)
        ImageDraw.Draw(img).text((30, 20), "ゴ", fill=255, font=font)
        img = img.filter(ImageFilter.MaxFilter(5))  # heavier strokes
        img = img.transform(img.size, Image.AFFINE, (1, 0.35, -20, 0, 1, 0), Image.BICUBIC)  # italic slant
        fill = np.asarray(img, dtype=float) / 255
        rim = np.asarray(img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1)), dtype=float) / 255
        _glyph = (fill, rim)
    return _glyph


def paste_glyph(A, L, cx, cy, scale, alpha):
    """puts one glyph centred at (cx, cy) in drawing units, `scale` of its natural size, faded by alpha"""
    fill, rim = glyph()
    n = max(4, int(fill.shape[0] * scale * CUR / 900))
    f = np.asarray(Image.fromarray((fill * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS), dtype=float) / 255
    r = np.asarray(Image.fromarray((rim * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS), dtype=float) / 255
    px = int(((cx * FIT + 1) / 2) * CUR - n / 2)
    py = int(((1 - cy * FIT) / 2) * CUR - n / 2)
    x0, y0, x1, y1 = max(px, 0), max(py, 0), min(px + n, CUR), min(py + n, CUR)
    if x1 <= x0 or y1 <= y0:
        return A, L
    sub = (slice(y0, y1), slice(x0, x1))
    gs = (slice(y0 - py, y1 - py), slice(x0 - px, x1 - px))
    a_rim, a_fill = np.zeros(A.shape), np.zeros(A.shape)
    a_rim[sub], a_fill[sub] = r[gs] * alpha, f[gs] * alpha
    A, L = over(A, L, a_rim, 0.12)
    return over(A, L, a_fill, 1.0)


def anim_frame(name, p):
    """(alpha, luminance) of one frame at phase p in 0..1"""
    lum = None
    if name == "Radar":  # ring with ticks and a sweeping beam that leaves a fading trail
        th = p * 2 * math.pi
        ang = (th - np.arctan2(Y, X)) % (2 * math.pi)
        r = np.hypot(X, Y)
        trail = np.clip(1 - ang / (math.pi * 0.6), 0, 1) ** 1.6 * (r < 0.84) * 0.55
        beam = stroke(seg(0, 0, 0.84 * math.cos(th), 0.84 * math.sin(th)), W * 0.8)
        ticks = union(*(stroke(seg(0.66 * math.cos(a), 0.66 * math.sin(a), 0.84 * math.cos(a), 0.84 * math.sin(a)), W * 0.7)
                        for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2)))
        a = union(stroke(ring(0.88), W), trail, beam, ticks, fill_in(r - 0.07))
    elif name == "Ripple":  # rings spreading out from the dot
        parts = [fill_in(np.hypot(X, Y) - 0.08)]
        for k in range(3):
            q = (p + k / 3) % 1
            parts.append(stroke(ring(0.12 + q * 0.8), W * (1.3 - q * 0.6)) * (1 - q) ** 1.2)
        a = union(*parts)
    elif name == "Lock-on":  # brackets close in and turn, then let go
        q = ease(1 - abs(2 * p - 1))
        s_, L_ = 0.78 - 0.32 * q, 0.26
        rot = q * math.pi / 4
        parts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                pts = rot_pts([(sx * s_, sy * (s_ - L_)), (sx * s_, sy * s_), (sx * (s_ - L_), sy * s_)], rot)
                parts.append(stroke(poly(pts, closed=False), W * 1.1))
        a = union(*parts, fill_in(np.hypot(X, Y) - 0.07 - 0.03 * q))
    elif name == "Orbit":  # three dots circling with light trails
        r = np.hypot(X, Y)
        ang = np.arctan2(Y, X)
        parts = [stroke(ring(0.62), W * 0.35) * 0.45, fill_in(r - 0.07)]
        for k in range(3):
            th = p * 2 * math.pi + k * 2 * math.pi / 3
            parts.append(fill_in(np.hypot(X - 0.62 * math.cos(th), Y - 0.62 * math.sin(th)) - 0.1))
            behind = (th - ang) % (2 * math.pi)
            parts.append(stroke(ring(0.62), W * 1.1) * np.clip(1 - behind / 1.4, 0, 1) ** 1.5)
        a = union(*parts)
    elif name == "Breathe":  # the arms slide in and out
        q = ease(1 - abs(2 * p - 1))
        g, L_ = 0.14 + 0.24 * q, 0.42
        a = union(*(stroke(seg(sx * g, sy * g, sx * (g + L_), sy * (g + L_)), W * 1.2) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))),
                  fill_in(np.hypot(X, Y) - 0.06) * (1 - 0.6 * q))
    elif name == "Menacing":  # sniper scope with the 'ゴゴゴ' sound effect throbbing up its side
        r = np.hypot(X, Y)
        ang = np.arctan2(Y, X)
        A, Lm = np.zeros(X.shape), np.zeros(X.shape)
        haze = np.clip((r - 0.62) / 0.28, 0, 1) ** 2 * (r < 0.95) * 0.2  # soft light inside the rim, clear in the middle
        A, Lm = over(A, Lm, haze, 1.0)
        rim = stroke(ring(0.92), 0.075)
        shade = 0.3 + 0.7 * (0.5 - 0.5 * np.cos(ang - math.radians(45)))  # darker towards the upper right, like the picture
        A, Lm = over(A, Lm, rim, 1 - shade + 0.3)
        thin = union(stroke(seg(-0.9, 0, 0.9, 0), W * 0.28), stroke(seg(0, -0.9, 0, 0.9), W * 0.28))
        posts = union(stroke(seg(-0.9, 0, -0.32, 0), W * 0.75), stroke(seg(0.32, 0, 0.9, 0), W * 0.75),
                      stroke(seg(0, -0.9, 0, -0.32), W * 0.75), stroke(seg(0, 0.32, 0, 0.9), W * 0.35))
        ticks = union(*(stroke(seg(t * sx - sy * 0.025, t * sy - sx * 0.025, t * sx + sy * 0.025, t * sy + sx * 0.025), W * 0.3)
                        for t in (0.06, 0.09, 0.12) for sx, sy in ((1, 0), (-1, 0))))
        A, Lm = over(A, Lm, union(thin, posts, ticks, fill_in(r - 0.025)), 0.85)
        spots = [(0.76, 0.6), (0.68, 0.3), (0.56, 0.02), (0.30, -0.26), (0.64, -0.26), (0.58, -0.58), (0.26, -0.64)]
        for k, (gx, gy) in enumerate(spots):
            q = (p * 2 + k * 0.37) % 1  # each glyph throbs and drifts up on its own beat
            sc = 0.95 + 0.25 * math.sin(q * 2 * math.pi)
            al = 0.55 + 0.45 * math.sin(q * 2 * math.pi + 1.0) ** 2
            A, Lm = paste_glyph(A, Lm, gx + 0.02 * math.sin(q * 6.28), gy + 0.05 * q, sc, al)
        return A, Lm
    else:
        raise ValueError(name)
    return a, lum


def save_sheet(path, alpha, lum=None):
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = 255 if lum is None else (np.clip(lum, 0, 1) * 255).astype(np.uint8)[..., None]
    rgba[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)
    print("wrote", path, path.stat().st_size // 1024, "KB")


def animated():
    for name, cell in ANIM:
        grid(cell, 0.86 if name == "Menacing" else 0.8)
        n = 4
        A, O, G, Lm = (np.zeros((n * cell, n * cell)) for _ in range(4))
        Gs = np.zeros((n * cell // 2, n * cell // 2))
        has_lum = False
        for f in range(FRAMES):
            a, lum = anim_frame(name, f / FRAMES)
            r, c = divmod(f, n)
            sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
            A[sl] = a
            if lum is not None:
                Lm[sl], has_lum = lum, True
            O[sl] = grow(np.where(a > 0.5, a, 0), 3 if cell <= 128 else 4)  # the faint haze gets no dark rim
            g = Image.fromarray((grow(np.where(a > 0.5, a, 0), 3) * 255).astype(np.uint8)).resize((cell // 2, cell // 2), Image.LANCZOS)
            g = np.asarray(g.filter(ImageFilter.GaussianBlur(cell / 40)), dtype=float) / 255
            h = cell // 2
            Gs[r * h:(r + 1) * h, c * h:(c + 1) * h] = np.clip(g * 1.7, 0, 1)
        base = "xa_" + name.lower().replace("-", "")
        save_sheet(OUT / (base + ".png"), A, Lm if has_lum else None)
        save_sheet(OUT / (base + "_outline.png"), O)
        save_sheet(OUT / (base + "_glow.png"), Gs)
    grid(CELL)


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
    animated()
    if "--no-pack" not in sys.argv:
        sys.path.insert(0, str(pathlib.Path(__file__).parent))
        import make_fx_assets
        make_fx_assets.pack()


if __name__ == "__main__":
    main()
