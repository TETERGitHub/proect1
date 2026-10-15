# Offline approximation of the recorded KillFX frames: flat-shaded parts, additive glow for Neon. Not Roblox's renderer.
import sys, math, pathlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = pathlib.Path(sys.argv[0]).resolve().parent
W, H = 560, 400
EYE = np.array([15.0, 8.0, 19.0]); TARGET = np.array([0.0, 4.0, 0.0]); FOV = 55
f = TARGET - EYE; f /= np.linalg.norm(f)
r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
u = np.cross(r, f)
FOC = (H / 2) / math.tan(math.radians(FOV / 2))
LIGHT = np.array([0.4, 0.8, 0.45]); LIGHT /= np.linalg.norm(LIGHT)

def proj(p):
    d = p - EYE
    z = d @ f
    return np.stack([W / 2 + (d @ r) / z * FOC, H / 2 - (d @ u) / z * FOC], -1), z

BOX = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
BOXF = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
# WedgePart: slope from the top back edge (+Z) down to the bottom front edge (-Z)
WED = np.array([[-.5, -.5, -.5], [.5, -.5, -.5], [-.5, -.5, .5], [.5, -.5, .5], [-.5, .5, .5], [.5, .5, .5]])
WEDF = [(0, 2, 3, 1), (0, 1, 5, 4), (2, 4, 5, 3), (0, 4, 2), (1, 3, 5)]
CYL = []
for i in range(14):
    a = i / 14 * 2 * math.pi
    CYL.append([-.5, .5 * math.cos(a), .5 * math.sin(a)])
for i in range(14):
    a = i / 14 * 2 * math.pi
    CYL.append([.5, .5 * math.cos(a), .5 * math.sin(a)])
CYL = np.array(CYL)
CYLF = [tuple(range(14)), tuple(range(14, 28))[::-1]] + [(i, (i + 1) % 14, 14 + (i + 1) % 14, 14 + i) for i in range(14)]

def load(name):
    frames = {}
    for line in (S / f"{name}.txt").read_text().splitlines():
        if not line.startswith("P "):
            continue
        t = line.split()
        n = int(t[1])
        v = list(map(float, t[5:]))
        frames.setdefault(n, []).append((t[2], t[3], t[4], v))
    return frames

def background():
    img = Image.new("RGB", (W, H))
    a = np.zeros((H, W, 3), np.float32)
    sky = np.linspace(0, 1, H)[:, None]
    a[:] = (np.array([22, 24, 34]) * (1 - sky) + np.array([48, 50, 62]) * sky)[:, None, :][:, 0][:, None, :]
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(-20, 21, 2):   # floor grid
        for p0, p1 in (((i, 0, -20), (i, 0, 20)), ((-20, 0, i), (20, 0, i))):
            (xy, z) = proj(np.array([p0, p1], float))
            if (z > 0.5).all():
                d.line([tuple(xy[0]), tuple(xy[1])], fill=(62, 66, 80), width=1)
    return img

def frame_image(parts, bg):
    img = bg.copy().convert("RGBA")
    glow = Image.new("RGB", (W, H))
    polys = []
    for cls, shape, mat, v in parts:
        size = np.array(v[0:3]); pos = np.array(v[3:6]); m = np.array(v[6:15]).reshape(3, 3)
        col = np.array(v[15:18]); tr = v[18]
        neon = mat == "Neon"
        if shape == "Ball":
            (xy, z) = proj(pos[None])
            if z[0] < 0.5: continue
            rad = size.max() / 2 / z[0] * FOC
            polys.append((z[0], "ball", xy[0], rad, col, tr, neon))
            continue
        if cls == "WedgePart":
            V, F = WED, WEDF
        elif shape == "Cylinder":
            V, F = CYL, CYLF
        else:
            V, F = BOX, BOXF
        wv = (V * size) @ m.T + pos
        xy, z = proj(wv)
        if (z < 0.5).any(): continue
        for face in F:
            pts = wv[list(face)]
            nrm = np.cross(pts[1] - pts[0], pts[2] - pts[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-9: continue
            nrm /= ln
            ctr = pts.mean(0)
            if nrm @ (EYE - ctr) <= 0: continue
            shade = 1.0 if neon else 0.35 + 0.65 * max(0, nrm @ LIGHT)
            polys.append((z[list(face)].mean(), "poly", [tuple(xy[i]) for i in face], None, col * shade, tr, neon))
    polys.sort(key=lambda p: -p[0])
    d = ImageDraw.Draw(img, "RGBA"); g = ImageDraw.Draw(glow)
    for z, kind, a, b, col, tr, neon in polys:
        c = tuple(int(255 * min(1, x)) for x in col)
        alpha = int(255 * (1 - tr))
        if kind == "ball":
            x, y = a
            box = (x - b, y - b, x + b, y + b)
            d.ellipse(box, fill=c + (alpha,))
            if neon:
                g.ellipse(box, fill=tuple(int(v * (1 - tr)) for v in c))
        else:
            d.polygon(a, fill=c + (alpha,))
            if neon:
                g.polygon(a, fill=tuple(int(v * (1 - tr)) for v in c))
    base = np.asarray(img.convert("RGB"), np.float32)
    gl = np.asarray(glow.filter(ImageFilter.GaussianBlur(9)), np.float32) * 1.3 + np.asarray(glow.filter(ImageFilter.GaussianBlur(3)), np.float32) * 0.6
    return Image.fromarray(np.clip(base + gl, 0, 255).astype(np.uint8))

FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
NAMES = {"Lightning": "Молния", "Explosion": "Взрыв", "Vaporize": "Испарение", "BlackHole": "Чёрная дыра", "Shatter": "Ледяной взрыв"}
bg = background()
for name in NAMES:
    frames = load(name)
    imgs = []
    for n in sorted(frames):
        im = frame_image(frames[n], bg)
        ImageDraw.Draw(im).text((12, 10), NAMES[name], fill=(255, 255, 255), font=FONT)
        imgs.append(im)
    q = [im.convert("P", palette=Image.ADAPTIVE, colors=200) for im in imgs]
    q[0].save(S / f"{name}.gif", save_all=True, append_images=q[1:] + [q[-1]] * 10, duration=33, loop=0)
    # strip: 6 moments
    idx = [int(i) for i in np.linspace(5, len(imgs) * 0.75, 6)]
    strip = Image.new("RGB", (W * 3, H * 2))
    for k, i in enumerate(idx):
        fr = imgs[i].copy()
        ImageDraw.Draw(fr).text((W - 90, H - 30), f"{(i - 6) / 30:+.2f} с", fill=(220, 220, 230), font=FONT)
        strip.paste(fr, ((k % 3) * W, (k // 3) * H))
    strip.save(S / f"{name}_strip.png")
    print(name, len(imgs))
