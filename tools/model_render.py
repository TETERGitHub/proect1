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


def tri_list(parts, cam, light):
    """-> (V Nx3x3 world vertices, normals, base colours, flags) for every triangle of every part."""
    tris = []
    for pid, p in enumerate(parts):
        R = rot(*p["rot"])
        if p.get("flip"):
            R = R @ rot(0, 180, 0)
        pos = np.array(p["pos"])
        base = np.array(p["color"], dtype=float)
        neon = bool(p.get("neon"))
        metal = p["material"] in ("Metal", "Foil", "DiamondPlate")
        glass = p["material"] == "Glass"
        alpha = 1.0 - float(p.get("transparency", 0))
        if glass:
            alpha = min(alpha, 0.55)
        for poly in faces_of(p):
            w = np.array([R @ np.array(v) + pos for v in poly])
            for k in range(1, len(w) - 1):
                tris.append((np.array([w[0], w[k], w[k + 1]]), pid, base, neon, metal, alpha))
    return tris


def render(parts, size=520, az=35, el=20, title=None, bg=(38, 40, 48), floor=False):
    return raster(tri_list(parts, None, None), size, az, el, title, bg)


def raster(tris, size=520, az=35, el=20, title=None, bg=(38, 40, 48)):
    """tris: (3x3 world vertices, part id, base rgb, neon, metal, alpha) -> PIL image (z-buffer, light, outlines)."""
    SSR = 3
    azr, elr = math.radians(az), math.radians(el)
    cam = np.array([math.sin(azr) * math.cos(elr), math.sin(elr), -math.cos(azr) * math.cos(elr)])
    fwd = -cam
    right = np.cross(fwd, np.array([0, 1, 0])); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    key = np.array([-0.35, 0.85, -0.4]) + 0.6 * cam; key /= np.linalg.norm(key)
    fill = -right * 0.6 + up * 0.2 + cam * 0.5; fill /= np.linalg.norm(fill)
    allv = np.concatenate([t[0].reshape(-1, 3) for t in tris])
    proj_all = np.stack([allv @ right, allv @ up], axis=1)
    lo, hi = proj_all.min(axis=0), proj_all.max(axis=0)
    span = max(hi - lo)
    W = size * SSR
    scale = W * 0.8 / span
    mid = (lo + hi) / 2
    # buffers
    zbuf = np.full((W, W), 1e9)
    col = np.zeros((W, W, 3))
    ids = np.full((W, W), -1, dtype=np.int32)
    nrm = np.zeros((W, W, 3))
    emit = np.zeros((W, W))
    late = []
    for t, pid, base, neon, metal, alpha in tris:
        v0, v1, v2 = t
        n = np.cross(v1 - v0, v2 - v0)
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        n /= ln
        if np.dot(n, cam) < 0:
            n = -n
        P = np.stack([t @ right, t @ up], axis=1)
        sx = (P[:, 0] - mid[0]) * scale + W / 2
        sy = W / 2 - (P[:, 1] - mid[1]) * scale
        d = t @ cam * -1.0  # smaller = nearer to the camera (cam points toward the viewer)
        d = -(t @ cam)
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(W - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(W - 1, math.ceil(sy.max())))
        if x1 < x0 or y1 < y0:
            continue
        den = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
        if abs(den) < 1e-9:
            continue
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        l0 = ((sy[1] - sy[2]) * (X - sx[2]) + (sx[2] - sx[1]) * (Y - sy[2])) / den
        l1 = ((sy[2] - sy[0]) * (X - sx[2]) + (sx[0] - sx[2]) * (Y - sy[2])) / den
        l2 = 1 - l0 - l1
        m = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        if not m.any():
            continue
        z = l0 * d[0] + l1 * d[1] + l2 * d[2]
        lam = max(0.0, float(np.dot(n, key)))
        lam2 = max(0.0, float(np.dot(n, fill)))
        if neon:
            c = np.clip(base * 0.8 + 70, 0, 255)
        else:
            c = base * (0.5 + 0.55 * lam + 0.22 * lam2) + 14
            if metal:
                h = key + cam; h /= np.linalg.norm(h)
                c = c + 255 * (max(0.0, float(np.dot(n, h))) ** 18) * 0.45
            c = np.clip(c, 0, 255)
        if alpha < 0.99:
            late.append((z, m, x0, y0, c, alpha, pid, n))
            continue
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = m & (z < sub)
        sub[win] = z[win]
        col[y0:y1 + 1, x0:x1 + 1][win] = c
        ids[y0:y1 + 1, x0:x1 + 1][win] = pid
        nrm[y0:y1 + 1, x0:x1 + 1][win] = n
        emit[y0:y1 + 1, x0:x1 + 1][win] = 1.0 if neon else 0.0
    covered = ids >= 0
    # outlines: where the part id or the surface direction changes
    edge = np.zeros((W, W), dtype=bool)
    edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
    edge[1:, :] |= ids[1:, :] != ids[:-1, :]
    ndiff = np.zeros((W, W))
    ndiff[:, 1:] += np.abs(nrm[:, 1:] - nrm[:, :-1]).sum(axis=2)
    ndiff[1:, :] += np.abs(nrm[1:, :] - nrm[:-1, :]).sum(axis=2)
    soft = (ndiff > 0.9) & covered
    col[edge & covered] *= 0.45
    col[soft & ~edge] *= 0.78
    # background, floor shadow, glow
    yy = np.linspace(0, 1, W)[:, None, None]
    bgc = np.array(bg, dtype=float)[None, None, :] * (1.15 - 0.4 * yy) * np.ones((W, W, 1))
    img = np.where(covered[:, :, None], col, bgc)
    # transparent surfaces (glass, decor): blended over what is behind them, depth-tested against the opaque model
    late.sort(key=lambda t: -float(np.mean(t[0][t[1]])))
    for z, m, x0, y0, c, alpha, pid, n in late:
        h, w_ = m.shape
        sub = zbuf[y0:y0 + h, x0:x0 + w_]
        win = m & (z < sub)
        reg = img[y0:y0 + h, x0:x0 + w_]
        reg[win] = reg[win] * (1 - alpha) + c * alpha
    emitm = (emit > 0).astype(float)
    glow = np.asarray(Image.fromarray((emitm * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(SSR * 6)), dtype=float) / 255.0
    tint = np.zeros((W, W, 3))
    tint[covered & (emit > 0)] = col[covered & (emit > 0)]
    tint_b = np.asarray(Image.fromarray(tint.astype("uint8")).filter(ImageFilter.GaussianBlur(SSR * 6)), dtype=float)
    img = np.clip(img + tint_b * 1.4, 0, 255)
    out = Image.fromarray(img.astype("uint8")).resize((size, size), Image.LANCZOS)
    if title:
        dd = ImageDraw.Draw(out)
        try:
            f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        except Exception:
            f = ImageFont.load_default()
        dd.text((12, 10), title, fill=(230, 230, 235), font=f)
    return out


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
    ap.add_argument("--az1", type=float, default=38)
    ap.add_argument("--az2", type=float, default=90)
    ap.add_argument("--el1", type=float, default=14)
    ap.add_argument("--el2", type=float, default=0)
    ap.add_argument("--pair", action="store_true", help="one sheet: every model as 3/4 view + side view, side by side")
    ap.add_argument("--views", action="store_true", help="one sheet per model: 3/4, side, front and top views")
    ap.add_argument("--only", default="", help="comma separated model ids")
    ap.add_argument("--size", type=int, default=520)
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    models = run_luau(a.kind, a.luau)
    if a.only:
        keep = set(a.only.split(","))
        models = [m for m in models if m[0] in keep]
    if a.pair:
        rows = []
        for name, data in models:
            parts = data["parts"]
            rows.append([render(parts, a.size, az, el, "%s" % name if i == 0 else None) for i, (az, el) in enumerate(((a.az1, a.el1), (a.az2, a.el2)))])
        sheet = Image.new("RGB", (2 * a.size, len(rows) * a.size))
        for r, pair in enumerate(rows):
            for c, im in enumerate(pair):
                sheet.paste(im, (c * a.size, r * a.size))
        sheet.save(out / ("pairs_%s.png" % a.kind))
        print("pair sheet with %d models" % len(rows))
        return
    if a.views:
        for name, data in models:
            parts = data["parts"]
            shots = [render(parts, a.size, az, el, "%s  az=%d el=%d" % (name, az, el)) for az, el in ((35, 14), (90, 0), (0, 0), (35, 80))]
            sheet = Image.new("RGB", (2 * a.size, 2 * a.size))
            for i, im in enumerate(shots):
                sheet.paste(im, ((i % 2) * a.size, (i // 2) * a.size))
            sheet.save(out / ("views_%s.png" % name))
        print("view sheets written for %d models" % len(models))
        return
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
