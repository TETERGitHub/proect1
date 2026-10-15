#!/usr/bin/env python3
"""Generate the hub's own kill-effect assets (no third-party or Roblox stock content):
assets/fx/*.png  particle textures, white on transparent (the effect tints them): glow, spark, smoke, flame, star, ring, arc
assets/fx/*.obj  small meshes, unit size, centred: ring (shock wave), swirl (vortex), crystal (ice shard), rock (debris), flame
Then packs them into src/data/FxPack.luau (base64) so the hub can install them with writefile + getcustomasset.
Deterministic (fixed seeds): running it again gives the same files."""
import base64, math, pathlib
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fx"
PACK = ROOT / "src" / "data" / "FxPack.luau"
N = 128


def save(name, alpha, light=None):
    a = np.clip(alpha, 0, 1)
    l = np.ones_like(a) if light is None else np.clip(light, 0, 1)
    img = Image.fromarray(np.dstack([(l * 255).astype(np.uint8), (a * 255).astype(np.uint8)]), "LA")
    img.save(OUT / name, optimize=True)


def grid():
    y, x = np.mgrid[0:N, 0:N]
    return (x - N / 2 + 0.5) / (N / 2), (y - N / 2 + 0.5) / (N / 2)


def fbm(seed, octaves=5):
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        s = 2 ** (o + 2)
        small = rng.random((s, s))
        big = np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC), float) / 255
        out += big * amp
        amp *= 0.5
    return out / out.max()


def textures():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    # glow: soft core + wide halo
    save("glow.png", np.exp(-(r / 0.22) ** 2) * 0.9 + np.exp(-(r / 0.6) ** 2) * 0.45)
    # spark: a long thin streak with a hot head
    streak = np.exp(-(y / 0.07) ** 2) * np.clip(1 - np.abs(x), 0, 1) ** 0.6
    head = np.exp(-((x - 0.45) / 0.18) ** 2 - (y / 0.12) ** 2)
    save("spark.png", streak + head * 0.8)
    # smoke: billowy noise inside a soft round mask, darker edges
    n = fbm(11)
    mask = np.clip(1 - r, 0, 1) ** 1.4
    a = np.clip((n - 0.12) * 2.2, 0, 1) * mask ** 0.8
    save("smoke.png", a, 0.7 + 0.3 * n)
    # flame: a teardrop pointing up (round bottom, flickering tip), hot bright core
    fy = (y + 1) / 2  # 0 top .. 1 bottom
    n2 = fbm(23)
    width = 0.62 * np.sin(np.pi * np.clip(fy, 0, 1) ** 0.65) + 1e-3
    sway = (n2 - 0.5) * 0.35 * (1 - fy)
    edge = np.clip(1 - np.abs(x + sway) / width, 0, 1)
    a = edge ** 0.7 * np.clip(fy * 3, 0, 1) * (0.55 + 0.6 * n2)
    core = np.exp(-(x / 0.18) ** 2 - ((fy - 0.32) / 0.18) ** 2)
    save("flame.png", np.flipud(a + core * 0.6))  # built tip-down, flipped so the tip points up
    # star: four-point twinkle with a round glow
    ang = np.arctan2(y, x)
    rays = np.maximum(np.exp(-(np.abs(x) / 0.035)) * np.exp(-np.abs(y) / 0.6), np.exp(-(np.abs(y) / 0.035)) * np.exp(-np.abs(x) / 0.6))
    save("star.png", rays + np.exp(-(r / 0.16) ** 2))
    # ring: a thin bright circle with a soft inner glow (shock-wave sprite)
    save("ring.png", np.exp(-((r - 0.78) / 0.05) ** 2) + np.exp(-((r - 0.78) / 0.22) ** 2) * 0.35)
    # arc: a jagged electric crackle across the sprite
    rng = np.random.default_rng(5)
    img = Image.new("L", (N, N), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for k in range(3):
        pts = [(4, N / 2 + rng.normal() * 10)]
        for i in range(1, 12):
            pts.append((4 + i * (N - 8) / 11, N / 2 + rng.normal() * 14))
        d.line(pts, fill=255 if k == 0 else 150, width=3 if k == 0 else 1)
    core = np.asarray(img, float) / 255
    glow = np.asarray(img.filter(ImageFilter.GaussianBlur(4)), float) / 255
    save("arc.png", core + glow * 1.6)


def write_obj(name, verts, faces):
    v = np.array(verts, float)
    v -= (v.min(0) + v.max(0)) / 2
    v /= np.abs(v).max() * 2  # fits a 1x1x1 box
    lines = ["# made by tools/make_fx_assets.py", "o " + name]
    lines += ["v %.5f %.5f %.5f" % tuple(p) for p in v]
    lines += ["f %d %d %d" % (a + 1, b + 1, c + 1) for a, b, c in faces]
    (OUT / (name + ".obj")).write_text("\n".join(lines) + "\n")
    return len(faces)


def quad(f, a, b, c, d):
    f += [(a, b, c), (a, c, d)]


def meshes():
    # ring: flat band torus (shock wave), thicker inner edge so it reads at any angle
    V, F = [], []
    seg, rad = 64, 6
    for i in range(seg):
        a = i / seg * 2 * math.pi
        for j in range(rad):
            b = j / rad * 2 * math.pi
            R = 1 + 0.08 * math.cos(b)
            V.append((R * math.cos(a), 0.035 * math.sin(b), R * math.sin(a)))
    for i in range(seg):
        for j in range(rad):
            a0, a1 = i * rad, ((i + 1) % seg) * rad
            quad(F, a0 + j, a1 + j, a1 + (j + 1) % rad, a0 + (j + 1) % rad)
    write_obj("ring", V, F)
    # swirl: three spiral arms, thin ribbons, getting wider outwards (vortex / accretion disc)
    V, F = [], []
    for arm in range(3):
        base = len(V)
        steps = 48
        for i in range(steps):
            t = i / (steps - 1)
            a = arm * 2 * math.pi / 3 + t * 2.6 * math.pi
            r = 0.15 + t * 0.85
            w = 0.03 + t * 0.12
            for s in (-1, 1):
                rr = r + s * w
                V.append((rr * math.cos(a), 0.02 * s * (1 - t), rr * math.sin(a)))
        for i in range(steps - 1):
            a0 = base + i * 2
            quad(F, a0, a0 + 2, a0 + 3, a0 + 1)
            quad(F, a0, a0 + 1, a0 + 3, a0 + 2)  # both sides
    write_obj("swirl", V, F)
    # crystal: hexagonal prism with a pointed top and a short pointed bottom, slightly irregular
    rng = np.random.default_rng(3)
    V, F = [(0, 1.0, 0), (0, -0.35, 0)], []
    for k in range(2):
        for i in range(6):
            a = i / 6 * 2 * math.pi
            r = 0.22 * (1 + rng.normal() * 0.08)
            V.append((r * math.cos(a), 0.55 if k == 0 else -0.15, r * math.sin(a)))
    for i in range(6):
        t0, t1 = 2 + i, 2 + (i + 1) % 6
        b0, b1 = 8 + i, 8 + (i + 1) % 6
        F.append((0, t1, t0))
        quad(F, t0, t1, b1, b0)
        F.append((1, b0, b1))
    write_obj("crystal", V, F)
    # rock: noisy icosphere (debris chunk)
    t = (1 + 5 ** 0.5) / 2
    V = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
         (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    V = [np.array(p) / np.linalg.norm(p) for p in V]
    cache = {}
    def mid(a, b):
        key = (min(a, b), max(a, b))
        if key not in cache:
            m = (V[a] + V[b]) / 2
            V.append(m / np.linalg.norm(m))
            cache[key] = len(V) - 1
        return cache[key]
    for _ in range(1):
        nf = []
        for a, b, c in F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        F = nf
    rng = np.random.default_rng(9)
    V = [p * (1 + rng.normal() * 0.13) * np.array([1.0, 0.75, 0.9]) for p in V]
    write_obj("rock", V, F)
    # flame: a curved, tapering tongue (cone bent sideways near the tip)
    V, F = [], []
    rings, sides = 12, 10
    for i in range(rings):
        t = i / (rings - 1)
        r = 0.35 * (1 - t) ** 1.2 + 0.01
        bend = 0.25 * t * t
        for j in range(sides):
            a = j / sides * 2 * math.pi
            V.append((bend + r * math.cos(a), t * 1.6, r * math.sin(a) * 0.8))
    for i in range(rings - 1):
        for j in range(sides):
            a0, a1 = i * sides, (i + 1) * sides
            quad(F, a0 + j, a0 + (j + 1) % sides, a1 + (j + 1) % sides, a1 + j)
    V.append((0, 0, 0))
    for j in range(sides):
        F.append((len(V) - 1, (j + 1) % sides, j))
    write_obj("flame", V, F)


def pack():
    lines = ["--!nonstrict", "-- data/FxPack: GENERATED by tools/make_fx_assets.py (do not edit by hand).",
             "-- The kill effects' own particle textures (PNG) and meshes (OBJ), made procedurally for this project.", "", "return {"]
    for f in sorted(OUT.iterdir()):
        if f.suffix in (".png", ".obj"):
            raw = f.read_bytes()
            lines.append('\t["%s"] = { bytes = %d, data = "%s" },' % (f.name, len(raw), base64.b64encode(raw).decode()))
    lines.append("}")
    PACK.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("packed", PACK, PACK.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    textures()
    meshes()
    pack()
