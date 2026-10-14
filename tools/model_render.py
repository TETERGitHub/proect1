#!/usr/bin/env python3
"""Offline renderer for the procedural customisation models (not Roblox).

tests/model_snapshot.luau prints plain part data ("@@MODEL <name> <json>") from data/ModelLib; this script draws each
model with a small painter's-algorithm rasteriser (orthographic camera, Lambert light, a fake metal highlight, neon
glow) so the SHAPES, proportions and colours can be judged without Studio. Block/Cylinder/Ball/Wedge follow the same
conventions as data/ModelKit. The result is an approximation: no real materials, shadows or Roblox lighting.

    python3 tools/model_render.py [--kind gun|knife|char] [--out dist/models] [--az 35] [--el 20]
"""
import argparse, json, math, pathlib, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SS = 2


def rot(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rx @ Ry @ Rz


def faces_of(part):
    """-> list of (vertices Nx3 in local space, ) polygons for the part's shape."""
    sx, sy, sz = part["size"]
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    shape = part["shape"]
    polys = []
    if shape == "Block":
        v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz), (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
        for f in ((0, 1, 2, 3), (5, 4, 7, 6), (4, 0, 3, 7), (1, 5, 6, 2), (3, 2, 6, 7), (4, 5, 1, 0)):
            polys.append([v[i] for i in f])
    elif shape == "Wedge":
        # triangle (y,z): (-h,-d) (-h,+d) (+h,+d): vertical face at +z, slope down to -z
        a0, a1 = (-hx, -hy, -hz), (hx, -hy, -hz)
        b0, b1 = (-hx, -hy, hz), (hx, -hy, hz)
        c0, c1 = (-hx, hy, hz), (hx, hy, hz)
        polys += [[a0, b0, c0], [a1, c1, b1], [a0, a1, b1, b0], [b0, b1, c1, c0], [a0, c0, c1, a1]]
    elif shape == "Cylinder":
        n = 16
        ring_a = [(-hx, math.cos(2 * math.pi * i / n) * hy, math.sin(2 * math.pi * i / n) * hz) for i in range(n)]
        ring_b = [(hx, y, z) for (_, y, z) in ring_a]
        for i in range(n):
            j = (i + 1) % n
            polys.append([ring_a[i], ring_a[j], ring_b[j], ring_b[i]])
        polys.append(list(reversed(ring_a)))
        polys.append(ring_b)
    elif shape == "Ball":
        nu, nv = 12, 8
        def pt(u, w):
            th, ph = 2 * math.pi * u / nu, math.pi * w / nv
            return (hx * math.sin(ph) * math.cos(th), hy * math.cos(ph), hz * math.sin(ph) * math.sin(th))
        for u in range(nu):
            for w in range(nv):
                polys.append([pt(u, w), pt(u + 1, w), pt(u + 1, w + 1), pt(u, w + 1)])
    return polys


def render(parts, size=520, az=35, el=20, title=None, bg=(34, 36, 42)):
    azr, elr = math.radians(az), math.radians(el)
    # camera basis: looks toward the origin from (sin az cos el, sin el, -cos az cos el): weapon barrels (-Z) point toward the viewer's left
    cam = np.array([math.sin(azr) * math.cos(elr), math.sin(elr), -math.cos(azr) * math.cos(elr)])
    fwd = -cam
    right = np.cross(fwd, np.array([0, 1, 0])); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([-0.4, 0.8, -0.5]); light /= np.linalg.norm(light)
    items = []
    allpts = []
    for p in parts:
        R = rot(*p["rot"])
        pos = np.array(p["pos"])
        base = np.array(p["color"], dtype=float)
        neon = p.get("neon")
        metal = p["material"] in ("Metal", "Foil", "DiamondPlate")
        for poly in faces_of(p):
            w = np.array([R @ np.array(v) + pos for v in poly])
            n = np.cross(w[1] - w[0], w[2] - w[0])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n /= ln
            c = w.mean(axis=0)
            # cull back faces for closed solids
            if np.dot(n, cam) < -0.02:
                continue
            lam = max(0.0, float(np.dot(n, light)))
            if neon:
                col = np.clip(base * 0.75 + 70, 0, 255)
            else:
                spec = 0.0
                if metal:
                    h = light + cam; h /= np.linalg.norm(h)
                    spec = max(0.0, float(np.dot(n, h))) ** 14 * 0.5
                col = np.clip(base * (0.42 + 0.7 * lam) + 255 * spec, 0, 255)
            proj = np.stack([w @ right, w @ up], axis=1)
            depth = float(c @ cam)
            allpts.append(proj)
            items.append((depth, proj, tuple(int(x) for x in col), p.get("transparency", 0), bool(neon)))
    allp = np.concatenate(allpts)
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    span = max(hi - lo)
    scale = (size * SS * 0.78) / span
    mid = (lo + hi) / 2
    W = size * SS
    img = Image.new("RGB", (W, W), bg)
    # soft backdrop gradient
    yy = np.linspace(0, 1, W)[:, None]
    grad = (np.array(bg) * (0.85 + 0.35 * (1 - yy))).clip(0, 255).astype("uint8")
    img = Image.fromarray(np.repeat(grad[:, None, :], W, axis=1).reshape(W, W, 3)) if False else img
    glow_layer = Image.new("RGB", (W, W), (0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    d = ImageDraw.Draw(img, "RGBA")
    def tp(pr):
        return [((x - mid[0]) * scale + W / 2, W / 2 - (y - mid[1]) * scale) for x, y in pr]
    items.sort(key=lambda t: -t[0])
    for depth, proj, col, trans, neon in items:
        pts = tp(proj)
        alpha = int(255 * (1 - trans))
        d.polygon(pts, fill=col + (alpha,))
        d.line(pts + [pts[0]], fill=tuple(int(c * 0.55) for c in col) + (alpha,), width=1)
        if neon:
            gd.polygon(pts, fill=col)
    glow = glow_layer.filter(ImageFilter.GaussianBlur(SS * 5))
    arr = np.clip(np.asarray(img, dtype=float) + np.asarray(glow, dtype=float) * 0.45, 0, 255).astype("uint8")
    img = Image.fromarray(arr).resize((size, size), Image.LANCZOS)
    if title:
        dd = ImageDraw.Draw(img)
        try:
            f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        except Exception:
            f = ImageFont.load_default()
        dd.text((12, 10), title, fill=(230, 230, 235), font=f)
    return img


def run_luau(kind, luau):
    from importlib import util
    sys.path.insert(0, str(ROOT / "tools"))
    import build
    p = build.build(True)
    text = p.read_text(encoding="utf-8").replace('return __import("tests/runner")', 'MODEL_KIND = "%s"\nreturn __import("tests/model_snapshot")' % kind)
    out = ROOT / "dist" / "model_snapshot.lua"
    out.write_text(text, encoding="utf-8")
    r = subprocess.run([luau, str(out)], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-2000:])
        sys.exit(1)
    models = []
    for line in r.stdout.splitlines():
        if line.startswith("@@MODEL "):
            _, rest = line.split(" ", 1)
            name, js = rest.split(" ", 1)
            models.append((name, json.loads(js)))
        elif line.startswith("@@ERR"):
            print(line)
    return models


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", default="gun")
    ap.add_argument("--out", default=str(ROOT / "dist" / "models"))
    ap.add_argument("--az", type=float, default=35)
    ap.add_argument("--el", type=float, default=14)
    ap.add_argument("--luau", default="/tmp/claude-0/luau/luau")
    ap.add_argument("--size", type=int, default=520)
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    models = run_luau(a.kind, a.luau)
    imgs = []
    for name, data in models:
        img = render(data["parts"], a.size, a.az, a.el, "%s  (%d parts)" % (name, len(data["parts"])))
        img.save(out / (name.replace("/", "_") + ".png"))
        imgs.append(img)
    if imgs:
        cols = 3 if len(imgs) > 3 else len(imgs)
        rows = (len(imgs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * a.size, rows * a.size))
        for i, im in enumerate(imgs):
            sheet.paste(im, ((i % cols) * a.size, (i // cols) * a.size))
        sheet.save(out / ("sheet_%s.png" % a.kind))
    print("rendered %d models into %s" % (len(imgs), out))


if __name__ == "__main__":
    main()
