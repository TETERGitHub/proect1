#!/usr/bin/env python3
# Trollface head from the owner's drawing: the outline of the drawing is extruded with a short bevelled rim (flat face, not a ball),
# dark lines are engraved a little, the mouth is recessed. Front (hub -Z) carries the drawing, the rest is white.
# usage: make_head.py face.jpg out_dir width_studs
import sys, pathlib, math
import numpy as np
from PIL import Image, ImageFilter

src, out, W = sys.argv[1], pathlib.Path(sys.argv[2]), float(sys.argv[3])
G = 90
img = Image.open(src).convert("RGB")
iw, ih = img.size
g = np.asarray(img.convert("L").resize((G, G), Image.LANCZOS), dtype=float) / 255
dark = g < 0.5
bg = np.zeros((G, G), bool)
stack = [(0, x) for x in range(G)] + [(G - 1, x) for x in range(G)] + [(y, 0) for y in range(G)] + [(y, G - 1) for y in range(G)]
while stack:
    y, x = stack.pop()
    if 0 <= y < G and 0 <= x < G and not bg[y, x] and not dark[y, x]:
        bg[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
inside = ~bg
# distance to the outline (in cells), smoothed
dist = np.zeros((G, G)); cur = inside.copy(); k = 0
while cur.any() and k < 80:
    k += 1; dist[cur] = k
    nxt = cur.copy()
    nxt[1:, :] &= cur[:-1, :]; nxt[:-1, :] &= cur[1:, :]; nxt[:, 1:] &= cur[:, :-1]; nxt[:, :-1] &= cur[:, 1:]
    cur = nxt
for _ in range(2):
    pad = np.pad(dist, 1, mode="edge")
    dist = sum(pad[1 + dy:G + 1 + dy, 1 + dx:G + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9.0
dist *= inside
band = G * 0.07
rim = np.sin(np.clip((dist - 0.5) / band, 0, 1) * math.pi / 2)          # 0 at the outline, 1 on the flat face
back_band = G * 0.34
rimb = np.sin(np.clip((dist - 0.5) / back_band, 0, 1) * math.pi / 2)
# the mouth = the big dark area; small dark areas = lines
mask = Image.fromarray((dark & inside).astype("uint8") * 255)
lines = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.9)), dtype=float) / 255
mouth = np.asarray(mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5)), dtype=float) / 255
cell = W / (G - 1)
depth_f, depth_b = W * 0.20, W * 0.40
# slight forward bulge of the cheeks/forehead so the face is not a plank (still flat compared to a ball)
yy, xx = np.mgrid[0:G, 0:G]
bulge = 1 - ((xx / (G - 1) - 0.5) ** 2 + (yy / (G - 1) - 0.5) ** 2) * 1.2
zf = depth_f * rim * (0.85 + 0.15 * bulge) - W * 0.012 * lines * rim - W * 0.05 * mouth * rim
zb = depth_b * rimb * (0.9 + 0.1 * bulge)
idx, P, UV, F = {}, [], [], []
def vert(side, y, x):
    ring = dist[y, x] <= 1.0
    key = (0 if ring else side, y, x)
    if key not in idx:
        px = -(x / (G - 1) - 0.5) * W            # viewer's right on the drawing = the head's -X (it faces -Z)
        py = (0.5 - y / (G - 1)) * W * ih / iw
        pz = 0.0 if ring else (-zf[y, x] if side == 1 else zb[y, x])
        idx[key] = len(P); P.append((px, py, pz))
        if side == 1 or ring:
            UV.append((x / (G - 1), y / (G - 1)))   # top-down, flipped when written
        else:
            UV.append((0.01, 0.01))                  # white corner of the drawing
    return idx[key]
for y in range(G - 1):
    for x in range(G - 1):
        if inside[y, x] and inside[y, x + 1] and inside[y + 1, x] and inside[y + 1, x + 1]:
            for side in (1, -1):
                a, b, c, d = vert(side, y, x), vert(side, y, x + 1), vert(side, y + 1, x), vert(side, y + 1, x + 1)
                F += [(a, c, b), (b, c, d)]
P = np.array(P)
centre = (P.min(0) + P.max(0)) / 2
P -= centre
# outward winding
out_f = []
for f in F:
    p0, p1, p2 = P[list(f)]
    n = np.cross(p1 - p0, p2 - p0)
    if np.dot(n, (p0 + p1 + p2) / 3) < 0:
        f = (f[0], f[2], f[1])
    out_f.append(f)
out.mkdir(parents=True, exist_ok=True)
L = ["# trollface head, made by make_head.py from the owner's drawing", "o Head"]
L += ["v %.5f %.5f %.5f" % tuple(p) for p in P]
L += ["vt %.5f %.5f" % (u, 1 - v) for u, v in UV]
L += ["f %d/%d %d/%d %d/%d" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1) for a, b, c in out_f]
(out / "head.obj").write_text("\n".join(L) + "\n")
tex = img.copy(); tex.thumbnail((1024, 1024)); tex.save(out / "head.png")
size = P.max(0) - P.min(0)
print("tris", len(out_f), "size", [round(float(s), 4) for s in size])
