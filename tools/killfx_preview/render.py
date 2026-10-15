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

FX = S.parent.parent / "assets" / "fx"
OBJS, TEX = {}, {}

def obj(name):
    if name not in OBJS:
        vs, fs = [], []
        for l in (FX / name).read_text().splitlines():
            if l.startswith("v "):
                vs.append(list(map(float, l.split()[1:4])))
            elif l.startswith("f "):
                fs.append(tuple(int(x.split("/")[0]) - 1 for x in l.split()[1:4]))
        OBJS[name] = (np.array(vs), fs)
    return OBJS[name]

def tex(name):
    if name not in TEX:
        file, _, cell = name.partition("#")
        im = Image.open(FX / file).convert("LA")
        if cell:  # one frame of a 4x4 flipbook sheet
            c = int(cell)
            w, h = im.width // 4, im.height // 4
            im = im.crop(((c % 4) * w, (c // 4) * h, (c % 4 + 1) * w, (c // 4 + 1) * h))
        TEX[name] = im
    return TEX[name]

def load(name):
    frames, sprites = {}, {}
    trails, beams = {}, {}
    for line in (S / f"{name}.txt").read_text().splitlines():
        t = line.split()
        if line.startswith("P "):
            n = int(t[1])
            mesh = None
            if "M" in t[5:]:
                k = t.index("M", 5)
                mesh = (t[k + 1], np.array(list(map(float, t[k + 2:k + 5]))))
                t = t[:k]
            v = list(map(float, t[5:]))
            frames.setdefault(n, []).append((t[2], t[3], t[4], v, mesh))
        elif line.startswith("S "):
            n = int(t[1])
            sprites.setdefault(n, []).append((t[2][3:], np.array(list(map(float, t[3:6]))), float(t[6]), float(t[7]),
                np.array(list(map(float, t[8:11]))), float(t[11]), float(t[12]), int(t[13]), np.array(list(map(float, t[14:17])))))
        elif line.startswith("T "):
            n = int(t[1])
            v = list(map(float, t[3:]))
            trails.setdefault(n, []).append((int(t[2]), np.array(v[0:3]), np.array(v[3:6]), np.array(v[6:9]), np.array(v[9:12]), v[12], v[13], v[14], v[15]))
        elif line.startswith("B "):
            n = int(t[1])
            v = list(map(float, t[3:]))
            beams.setdefault(n, []).append((t[2], np.array(v[0:3]), np.array(v[3:6]), v[6], v[7], np.array(v[8:11]), v[11], v[12]))
        elif line.startswith("G "):
            n = int(t[1])
            v = list(map(float, t[2:9]))
            GUIS.setdefault(name, {}).setdefault(n, []).append((np.array(v[0:3]), v[3], int(v[4]), int(v[5]), v[6], t[9].replace("_", " "),
                                                                    t[10] if len(t) > 10 else "-"))
        elif line.startswith("F "):
            frames.setdefault(int(t[1]), [])
    LAST_FX[name] = (trails, beams)
    return frames, sprites

LAST_FX = {}
GUIS = {}
SHEETS = {}
SHEET = None


def draw_guis(im, guis):
    """BillboardGuis (always on top): sticker faces from their own sheet (troll_anim.png, trolls.png) and captions"""
    d = ImageDraw.Draw(im)
    for pos, studs, rx, ry, tr, cap, file in guis:
        (xy, z) = proj(pos[None])
        if z[0] < 0.5 or studs <= 0.05:
            continue
        px = int(studs / z[0] * FOC)
        if px < 4:
            continue
        if file not in SHEETS:
            path = S.parent.parent / "assets" / "fx" / file
            SHEETS[file] = Image.open(path if path.exists() else S.parent.parent / "assets" / "ui" / "sticker_anim.png").convert("LA")
        cell = SHEETS[file].crop((rx, ry, rx + 128, ry + 128)).resize((px, px if file == "trolls.png" else int(px * 0.8)))
        l, a = cell.split()
        a = a.point(lambda v: int(v * (1 - tr)))
        x0, y0 = int(xy[0][0] - px / 2), int(xy[0][1] - px / 2)
        im.paste(Image.merge("RGB", (l, l, l)), (x0, y0), a)
        if cap != "-" and tr < 0.95:
            fnt = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", max(8, int(px * 0.14)))
            w = d.textlength(cap, font=fnt)
            d.text((xy[0][0] - w / 2, y0 + px * 0.8), cap, fill=(255, 255, 255), font=fnt, stroke_width=2, stroke_fill=(0, 0, 0))
    return im


def fx_polys(trails, beams, n):
    """trail ribbons from the recorded history (head = now) and beam strips, as glowing polygons"""
    out = []
    hist = {}
    for k in range(max(0, n - 40), n + 1):
        for (tid, p0, p1, c0, c1, t0, t1, life, wt) in trails.get(k, ()):
            hist.setdefault(tid, []).append((k, p0, p1, c0, c1, t0, t1, life, wt))
    for tid, h in hist.items():
        if not h or h[-1][0] != n:
            continue
        life = h[-1][7]
        h = [e for e in h if (n - e[0]) / 30.0 <= life]
        for i in range(len(h) - 1):
            (ka, a0, a1, c0, c1, t0, t1, life, wt), (kb, b0, b1, *_r) = h[i], h[i + 1]
            age = (n - ka) / 30.0 / max(life, 1e-3)
            agen = (n - kb) / 30.0 / max(life, 1e-3)
            def shrink(p, q, f):
                m = (p + q) / 2
                return m + (p - m) * f, m + (q - m) * f
            wa, wb = 1 + (wt - 1) * age, 1 + (wt - 1) * agen
            a0s, a1s = shrink(a0, a1, wa)
            b0s, b1s = shrink(b0, b1, wb)
            quad = np.array([a0s, b0s, b1s, a1s])
            xy, z = proj(quad)
            if (z < 0.5).any():
                continue
            col = c0 + (c1 - c0) * age
            tr = t0 + (t1 - t0) * age
            out.append((z.mean(), "poly", [tuple(q) for q in xy], None, col, min(1, tr + 0.15), True))
    for (tex, p0, p1, w0, w1, col, t0, t1) in beams.get(n, ()):
        d = p1 - p0
        L = np.linalg.norm(d)
        if L < 1e-3:
            continue
        steps = 14
        pts = []
        rng = np.random.default_rng(int(abs(p0[0] * 1000)) + n)
        side = np.cross(d / L, (EYE - p0) / np.linalg.norm(EYE - p0))
        side /= max(np.linalg.norm(side), 1e-6)
        for i in range(steps + 1):
            f = i / steps
            jit = (rng.normal() * L * 0.04 if tex.endswith("bolt.png") and 0 < i < steps else 0)
            pts.append(p0 + d * f + side * jit)
        for i in range(steps):
            f0, f1 = i / steps, (i + 1) / steps
            wa, wb = (w0 + (w1 - w0) * f0) / 2, (w0 + (w1 - w0) * f1) / 2
            core = 0.35 if tex.endswith("bolt.png") else 1.0
            quad = np.array([pts[i] + side * wa * core, pts[i + 1] + side * wb * core, pts[i + 1] - side * wb * core, pts[i] - side * wa * core])
            xy, z = proj(quad)
            if (z < 0.5).any():
                continue
            out.append((z.mean(), "poly", [tuple(q) for q in xy], None, col, t0 + (t1 - t0) * f0, True))
    return out

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

def frame_image(parts, bg, sprites=(), extra=()):
    img = bg.copy().convert("RGB")  # RGB + an "RGBA" draw = real alpha blending
    glow = Image.new("RGB", (W, H))
    polys = []
    for cls, shape, mat, v, mesh in parts:
        size = np.array(v[0:3]); pos = np.array(v[3:6]); m = np.array(v[6:15]).reshape(3, 3)
        col = np.array(v[15:18]); tr = v[18]
        neon = mat == "Neon"
        if mesh is not None:
            mv, mf = obj(mesh[0])
            wv = (mv * mesh[1]) @ m.T + pos
            xy, z = proj(wv)
            if (z < 0.5).any(): continue
            for face in mf:
                pts = wv[list(face)]
                nrm = np.cross(pts[1] - pts[0], pts[2] - pts[0]); ln = np.linalg.norm(nrm)
                if ln < 1e-12: continue
                nrm /= ln
                if nrm @ (EYE - pts.mean(0)) < 0: nrm = -nrm   # meshes may be open/double sided
                shade = 1.0 if neon else 0.35 + 0.65 * max(0, nrm @ LIGHT)
                polys.append((z[list(face)].mean(), "poly", [tuple(xy[i]) for i in face], None, col * shade, tr, neon))
            continue
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
    polys.extend(extra)
    for texname, pos, size, tr, col, light, rot, squash, vel in sprites:
        (xy, z) = proj(pos[None])
        if z[0] < 0.5 or size <= 0.01: continue
        px = size / z[0] * FOC
        polys.append((z[0], "sprite", (texname, xy[0], px, rot, squash, vel, pos), None, col, tr, light > 0.5))
    polys.sort(key=lambda p: -p[0])
    d = ImageDraw.Draw(img, "RGBA"); g = ImageDraw.Draw(glow)
    for z, kind, a, b, col, tr, neon in polys:
        c = tuple(int(255 * min(1, x)) for x in col)
        alpha = int(255 * (1 - tr))
        if kind == "sprite":
            texname, (x, y), px, rot, squash, vel, wpos = a
            im = tex(texname)
            w = h = max(2, int(px))
            angle = rot
            if squash and np.linalg.norm(vel) > 0.1:
                # face the motion: stretch along the projected velocity
                (xy2, _) = proj((wpos + vel * 0.03)[None])
                dx, dy = xy2[0][0] - x, xy2[0][1] - y
                w = max(2, int(px * (1 + min(3, math.hypot(dx, dy) / 3))))
                angle = -math.degrees(math.atan2(dy, dx))
            l, al = im.resize((w, h)).split()
            spr = Image.merge("RGBA", (l, l, l, al)).rotate(angle, expand=True)
            arr = np.asarray(spr, np.float32) / 255
            rgb = arr[..., :3] * col[None, None, :] * 255
            al = arr[..., 3] * (1 - tr)
            x0, y0 = int(x - spr.width / 2), int(y - spr.height / 2)
            xa, ya, xb, yb = max(0, x0), max(0, y0), min(W, x0 + spr.width), min(H, y0 + spr.height)
            if xa >= xb or ya >= yb: continue
            sub_rgb = rgb[ya - y0:yb - y0, xa - x0:xb - x0]; sub_a = al[ya - y0:yb - y0, xa - x0:xb - x0, None]
            base_np = np.asarray(img, np.float32).copy()
            region = base_np[ya:yb, xa:xb, :3]
            if neon:
                region += sub_rgb * sub_a
            else:
                region[:] = region * (1 - sub_a) + sub_rgb * sub_a
            base_np[ya:yb, xa:xb, :3] = np.clip(region, 0, 255)
            img = Image.fromarray(base_np[..., :3].astype(np.uint8), "RGB")
            d = ImageDraw.Draw(img, "RGBA")
            continue
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
    out = np.clip(base + gl, 0, 255)
    # bloom: bright areas bleed light into their surroundings (a post effect Roblox applies with its own Bloom)
    bright = np.clip(out - 170, 0, 255) * 1.6
    bimg = Image.fromarray(bright.astype(np.uint8))
    bloom = np.asarray(bimg.filter(ImageFilter.GaussianBlur(6)), np.float32) * 0.7 + np.asarray(bimg.filter(ImageFilter.GaussianBlur(18)), np.float32) * 0.6
    return Image.fromarray(np.clip(out + bloom, 0, 255).astype(np.uint8))

FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
NAMES = {"Lightning": "Молния", "Explosion": "Взрыв", "Vaporize": "Испарение", "BlackHole": "Чёрная дыра", "Shatter": "Ледяной взрыв", "Troll": "Тролль"}
AURA_NAMES = {"InfernoCrown": "Огненная корона", "StormGod": "Бог грозы", "Galaxy": "Галактика", "FrostMonarch": "Ледяной монарх",
              "VoidWings": "Крылья пустоты", "Sakura": "Сакура", "Phoenix": "Феникс", "DragonSpirit": "Дух дракона",
              "HolyLight": "Святой свет", "ToxicRift": "Токсичный разлом", "ShadowReaper": "Тёмный жнец", "NeonCyber": "Кибер-неон", "Troll": "Тролль", "Burning": "Горение",
              "Burning_Layers": "Горение + слои (сферы, кольцо, звёзды)"}
if "--auras" in sys.argv:
    EYE[:] = [11.0, 6.5, 14.0]; TARGET[:] = [0.0, 3.0, 0.0]
    f = TARGET - EYE; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    bg = background()
    heroes = []
    ONLY = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
    for key, title in AURA_NAMES.items():
        if ONLY and key not in ONLY:
            continue
        frames, sprites = load("aura_" + key)
        trails, beams = LAST_FX["aura_" + key]
        imgs = []
        for n in sorted(frames):
            im = frame_image(frames[n], bg, sprites.get(n, ()), fx_polys(trails, beams, n))
            draw_guis(im, GUIS.get("aura_" + key, {}).get(n, ()))
            ImageDraw.Draw(im).text((12, 10), title, fill=(255, 255, 255), font=FONT)
            imgs.append(im)
        q = [im.convert("P", palette=Image.ADAPTIVE, colors=200) for im in imgs]
        q[0].save(S / f"aura_{key}.gif", save_all=True, append_images=q[1:], duration=33, loop=0)
        heroes.append(imgs[len(imgs) // 2])
        print(key, len(imgs))
    sheet = Image.new("RGB", (W * 3, H * ((len(heroes) + 2) // 3)))
    for i, im in enumerate(heroes):
        sheet.paste(im, ((i % 3) * W, (i // 3) * H))
    sheet.save(S / ("auras_sheet.png" if not ONLY else "auras_new.png"))
    sys.exit(0)

bg = background()
ONLY_K = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
for name in NAMES:
    if ONLY_K and name not in ONLY_K:
        continue
    frames, sprites = load(name)
    trails, beams = LAST_FX[name]
    imgs = []
    for n in sorted(frames):
        im = frame_image(frames[n], bg, sprites.get(n, ()), fx_polys(trails, beams, n))
        draw_guis(im, GUIS.get(name, {}).get(n, ()))
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
