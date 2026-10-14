#!/usr/bin/env python3
"""Proxy renderer for the hub's GUI tree: layout (a subset of Roblox rules) + painting with Pillow.

  python3 tools/ui_render.py [--out dist/shots] [--jobs name,name] [--luau path]

tests/ui_snapshot.luau boots the hub on the mock, drives it into states and prints the GUI tree; this script lays
the tree out and paints PNGs. IMPORTANT: this is NOT the Roblox renderer. Fonts are Inter standing in for Gotham, there is no
real blur, text metrics differ, and only the features this project uses are implemented (UIListLayout, UIGridLayout,
UIPadding, UIScale, UICorner, UIStroke, UIGradient, ScrollingFrame, CanvasGroup, AutomaticSize, ClipsDescendants, ZIndex
siblings). It exists to expose layout defects, overlaps, clipped text, weak contrast and poor hierarchy."""
import json
import pathlib
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build  # noqa: E402

SS = 2  # supersampling factor for anti-aliased shapes
FONT_FILES = {
    "regular": ["/usr/share/fonts/opentype/inter/Inter-Regular.otf"],
    "medium": ["/usr/share/fonts/opentype/inter/Inter-Medium.otf"],
    "bold": ["/usr/share/fonts/opentype/inter/Inter-Bold.otf"],
    "black": ["/usr/share/fonts/opentype/inter/Inter-Black.otf"],
}
_font_cache = {}


MONTSERRAT = "/usr/share/fonts/truetype/montserrat/Montserrat-%s.ttf"


def font_for(name: str, size: float):
    weight = "black" if "Black" in name else "bold" if "Bold" in name else "medium" if "Medium" in name else "regular"
    fam = "montserrat" if "Montserrat" in name else "inter"
    key = (weight, int(round(size * SS)), fam)
    if key not in _font_cache:
        files = ([MONTSERRAT % weight.capitalize()] if fam == "montserrat" else []) + FONT_FILES[weight]
        for path in files + ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
            try:
                _font_cache[key] = ImageFont.truetype(path, max(6, key[1]))
                break
            except OSError:
                continue
    return _font_cache[key]


def enum_name(v, default=""):
    if isinstance(v, dict) and "en" in v:
        return v["en"].split(".")[-1]
    return default


class N:
    __slots__ = ("cls", "name", "p", "kids", "parent", "x", "y", "w", "h", "order", "visible", "mods", "cw", "ch", "tb")

    def __init__(self, d, parent=None, order=0):
        self.cls, self.name, self.p = d["c"], d["n"], d["p"]
        self.parent = parent
        self.order = order
        self.kids = [N(k, self, i) for i, k in enumerate(d.get("k") or [])]
        self.x = self.y = self.w = self.h = 0.0
        self.cw = self.ch = 0.0  # content size (for automatic sizing / canvas)
        self.tb = None
        self.mods = {}
        for k in self.kids:
            if k.cls.startswith("UI"):
                self.mods.setdefault(k.cls, []).append(k)

    def mod(self, cls):
        m = self.mods.get(cls)
        return m[0] if m else None

    def is_gui(self):
        return self.cls in ("Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "CanvasGroup", "ImageLabel", "ImageButton")

    def get(self, key, default=None):
        return self.p.get(key, default)


def u2(v, default=(0, 0, 0, 0)):
    if isinstance(v, dict) and "u2" in v:
        return v["u2"]
    return default


def color(v, default=(1, 1, 1)):
    if isinstance(v, dict) and "c3" in v:
        return tuple(v["c3"])
    return default


def ud(v, default=(0, 0)):
    if isinstance(v, dict) and "ud" in v:
        return tuple(v["ud"])
    return default


def v2(v, default=(0, 0)):
    if isinstance(v, dict) and "v2" in v:
        return tuple(v["v2"])
    return default


def padding(n: N, w, h):
    p = n.mod("UIPadding")
    if not p:
        return 0, 0, 0, 0
    l, t, r, b = (ud(p.get(k))[0] * (w if k in ("PaddingLeft", "PaddingRight") else h) + ud(p.get(k))[1] for k in ("PaddingLeft", "PaddingTop", "PaddingRight", "PaddingBottom"))
    return l, t, r, b


def text_lines(n: N, width: float, text=None):
    text = str(n.get("Text", "") or "") if text is None else text
    size = float(n.get("TextSize", 14))
    f = font_for(enum_name(n.get("Font"), "GothamMedium"), size)
    wrapped = n.get("TextWrapped") is True
    lines = []
    for para in text.split("\n"):
        if not wrapped or width <= 0:
            lines.append(para)
            continue
        words, cur = para.split(" "), ""
        for wd in words:
            trial = (cur + " " + wd).strip()
            if cur and f.getlength(trial) / SS > width:
                lines.append(cur)
                cur = wd
            else:
                cur = trial
        lines.append(cur)
    lh = size * 1.18
    maxw = max((f.getlength(l) / SS for l in lines), default=0)
    return lines, maxw, lh * max(1, len(lines))


def resolve_size(n: N, aw, ah):
    sx, ox, sy, oy = u2(n.get("Size"))
    return sx * aw + ox, sy * ah + oy


def layout_children(n: N, aw, ah):
    """Lay out the GUI children of n inside a content area of size (aw, ah). Sets child x,y,w,h relative to the area."""
    kids = [k for k in n.kids if k.is_gui() and k.get("Visible", True) is not False]
    lay = n.mod("UIListLayout")
    grid = n.mod("UIGridLayout")
    maxx = maxy = 0.0
    if lay or grid:
        kids.sort(key=lambda k: (k.get("LayoutOrder", 0), k.order))
    if lay:
        vertical = enum_name(lay.get("FillDirection"), "Vertical") != "Horizontal"
        pad = ud(lay.get("Padding"))
        gap = pad[0] * (ah if vertical else aw) + pad[1]
        ha, va = enum_name(lay.get("HorizontalAlignment"), "Left"), enum_name(lay.get("VerticalAlignment"), "Top")
        cursor = 0.0
        sizes = []
        for k in kids:
            size_node(k, aw, ah)
            sizes.append((k.w, k.h))
        for k in kids:
            if vertical:
                k.y = cursor
                k.x = {"Center": (aw - k.w) / 2, "Right": aw - k.w}.get(ha, 0)
                cursor += k.h + gap
            else:
                k.x = cursor
                k.y = {"Center": (ah - k.h) / 2, "Bottom": ah - k.h}.get(va, 0)
                cursor += k.w + gap
            maxx, maxy = max(maxx, k.x + k.w), max(maxy, k.y + k.h)
        return maxx, maxy
    if grid:
        cs = u2(grid.get("CellSize"))
        cp = u2(grid.get("CellPadding"))
        cw, ch = cs[0] * aw + cs[1], cs[2] * ah + cs[3]
        px, py = cp[0] * aw + cp[1], cp[2] * ah + cp[3]
        per_row = max(1, int((aw + px) // (cw + px)))
        for i, k in enumerate(kids):
            k.w, k.h = cw, ch
            col, row = i % per_row, i // per_row
            k.x, k.y = col * (cw + px), row * (ch + py)
            size_node(k, aw, ah, fixed=(cw, ch))
            maxx, maxy = max(maxx, k.x + cw), max(maxy, k.y + ch)
        return maxx, maxy
    for k in kids:
        size_node(k, aw, ah)
        ax, ay = v2(k.get("AnchorPoint"))
        sx, ox, sy, oy = u2(k.get("Position"))
        k.x = sx * aw + ox - ax * k.w
        k.y = sy * ah + oy - ay * k.h
        maxx, maxy = max(maxx, k.x + k.w), max(maxy, k.y + k.h)
    return maxx, maxy


def size_node(n: N, aw, ah, fixed=None):
    """Resolve n's own size against the parent's content area, lay out its subtree, apply AutomaticSize."""
    w, h = fixed if fixed else resolve_size(n, aw, ah)
    auto = enum_name(n.get("AutomaticSize"), "None")
    pl, pt, pr, pb = padding(n, w, h)
    # text-driven sizes
    if n.cls in ("TextLabel", "TextButton", "TextBox") and auto != "None":
        inner_w = (w if "X" not in auto else 1e9) - pl - pr
        lines, tw, th = text_lines(n, inner_w if n.get("TextWrapped") is True else 0)
        if "X" in auto:
            w = max(w, tw + pl + pr)
        if "Y" in auto:
            h = max(h if "Y" not in auto else 0, th + pt + pb) if h == 0 else max(h, th + pt + pb)
    area_w, area_h = max(0, w - pl - pr), max(0, h - pt - pb)
    n.w, n.h = w, h
    if n.cls == "ScrollingFrame":
        cs = u2(n.get("CanvasSize"))
        cx, cy = layout_children(n, area_w, area_h)
        n.cw, n.ch = max(area_w, cx), max(area_h, cy)
    else:
        cx, cy = layout_children(n, area_w, area_h)
        n.cw, n.ch = cx, cy
    if n.cls != "ScrollingFrame" and auto != "None" and n.cls not in ("TextLabel", "TextButton", "TextBox"):
        if "X" in auto:
            n.w = cx + pl + pr
        if "Y" in auto:
            n.h = cy + pt + pb
        # a list layout's fill children may depend on the auto size: second pass keeps relative children consistent
    elif n.cls in ("TextLabel", "TextButton", "TextBox") and auto != "None" and n.kids:
        pass
    # children of an auto-sized frame were laid out with the pre-auto area; re-run once with the final size
    if auto != "None" and n.cls not in ("TextLabel", "TextButton", "TextBox", "ScrollingFrame"):
        area_w, area_h = max(0, n.w - pl - pr), max(0, n.h - pt - pb)
        layout_children(n, area_w, area_h)
    # offset children by padding so (x, y) of a child is relative to the parent's border box
    for k in n.kids:
        if k.is_gui() and k.get("Visible", True) is not False:
            k.x += pl
            k.y += pt


def absolutize(n: N, ox, oy):
    n.x += ox
    n.y += oy
    for k in n.kids:
        if k.is_gui():
            absolutize(k, n.x, n.y)


# Painting ----------------------------------------------------------------------------------------------------------


def seq_value(seq, t):
    """Evaluate a NumberSequence / ColorSequence dict at t in 0..1 (the mock keeps the constructor arguments)."""
    if not seq or "pts" not in seq:
        return None
    pts = seq["pts"]
    vals = []
    for p in pts:
        if isinstance(p, dict) and "kp" in p:
            vals.append((p["kp"][0], p["kp"][1]))
        else:
            vals.append((None, p))
    if len(vals) == 1:
        return vals[0][1]
    if vals[0][0] is None:
        step = 1.0 / (len(vals) - 1)
        vals = [(i * step, v) for i, (_, v) in enumerate(vals)]
    for (t0, v0), (t1, v1) in zip(vals, vals[1:]):
        if t <= t1 or (t1, v1) == vals[-1]:
            f = 0 if t1 == t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            return lerp_val(v0, v1, f)
    return vals[-1][1]


def lerp_val(a, b, f):
    if isinstance(a, dict) and "c3" in a:
        return {"c3": [a["c3"][i] + (b["c3"][i] - a["c3"][i]) * f for i in range(3)]}
    return a + (b - a) * f


class Painter:
    """Canvas at SS x resolution. All shape work happens on cropped regions (a full-canvas mask per shape is far too slow)."""

    def __init__(self, w, h, base: Image.Image):
        self.w, self.h = int(w), int(h)
        self.img = base.convert("RGBA").resize((self.w * SS, self.h * SS), Image.LANCZOS)

    def region(self, box, pad=0.0):
        x0, y0, x1, y1 = box
        W, H = self.img.size
        return (max(0, int((x0 - pad) * SS)), max(0, int((y0 - pad) * SS)), min(W, int((x1 + pad) * SS) + 1), min(H, int((y1 + pad) * SS) + 1))

    def shape(self, box, radius, rot=0.0, grow=0.0, hole=0.0):
        """Anti-aliased rounded-rect mask cropped to its bounding region -> (mask, (rx0, ry0)). grow/hole make rings."""
        x0, y0, x1, y1 = box
        diag = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 if rot else 0
        reg = self.region((x0, y0, x1, y1), pad=grow + (diag / 2 if rot else 0) + 1)
        rw, rh = reg[2] - reg[0], reg[3] - reg[1]
        if rw <= 0 or rh <= 0:
            return None, reg
        m = Image.new("L", (rw, rh), 0)
        d = ImageDraw.Draw(m)

        def rr(g, fill):
            bx = [(x0 - g) * SS - reg[0], (y0 - g) * SS - reg[1], (x1 + g) * SS - reg[0] - 1, (y1 + g) * SS - reg[1] - 1]
            if bx[2] < bx[0] or bx[3] < bx[1]:
                return
            r = max(0, min((radius + g) * SS, (bx[2] - bx[0]) / 2, (bx[3] - bx[1]) / 2))
            if r > 0:
                d.rounded_rectangle(bx, radius=r, fill=fill)
            else:
                d.rectangle(bx, fill=fill)

        rr(grow, 255)
        if hole:
            rr(0, 0)
        if rot:
            m = m.rotate(-rot, resample=Image.BICUBIC, center=(((x0 + x1) / 2) * SS - reg[0], ((y0 + y1) / 2) * SS - reg[1]))
        return m, reg

    def put(self, mask, reg, rgb, alpha, clip=None, grad=None, box=None):
        if mask is None or alpha <= 0.003:
            return
        if clip is not None:
            mask = ImageChops.multiply(mask, clip.crop(reg))
        a = mask.point(lambda v: int(v * alpha))
        layer = Image.new("RGBA", mask.size, tuple(int(c * 255) for c in rgb) + (255,))
        if grad is not None and box is not None:
            layer, a = apply_gradient(layer, a, grad, box, reg)
        layer.putalpha(a)
        self.img.alpha_composite(layer, dest=(reg[0], reg[1]))


def apply_gradient(layer, alpha, grad: N, box, reg):
    """Apply a UIGradient (colour and/or transparency ramp) to a cropped fill layer. `box` is the object's box in px."""
    import math
    import numpy as np
    x0, y0, x1, y1 = [v * SS for v in box]
    w, h = max(1.0, x1 - x0), max(1.0, y1 - y0)
    ang = math.radians(float(grad.get("Rotation", 0)))
    dx, dy = math.cos(ang), math.sin(ang)
    csq, tsq = grad.get("Color"), grad.get("Transparency")
    off = grad.get("Offset")
    ox = v2(off)[0] if off else 0
    rw, rh = layer.size
    yy, xx = np.mgrid[0:rh, 0:rw]
    px, py = xx + reg[0] - x0, yy + reg[1] - y0
    half = (abs(dx) * w + abs(dy) * h) / 2 or 1
    t = np.clip(((px - w / 2) * dx + (py - h / 2) * dy) / (2 * half) + 0.5 - ox * 0.5, 0, 1)
    ramp = 128
    idx = (t * (ramp - 1)).astype(np.int32)
    out_rgb = layer
    if csq:
        cols = [seq_value(csq, i / (ramp - 1)) for i in range(ramp)]
        lut = np.array([[255 * (c["c3"][k] if c else 1) for k in range(3)] for c in cols], dtype=np.uint8)
        arr = np.dstack([lut[idx], np.full((rh, rw), 255, dtype=np.uint8)])
        out_rgb = Image.fromarray(arr, "RGBA")
    if tsq:
        trs = np.array([255 * (1 - max(0.0, min(1.0, float(seq_value(tsq, i / (ramp - 1)))))) for i in range(ramp)], dtype=np.float32)
        a = np.asarray(alpha, dtype=np.float32) * trs[idx] / 255.0
        alpha = Image.fromarray(a.astype(np.uint8), "L")
    return out_rgb, alpha


def paint(n: N, pt: Painter, clip, inherited_alpha=1.0):
    if not n.is_gui() or n.get("Visible", True) is False:
        return
    box = (n.x, n.y, n.x + n.w, n.y + n.h)
    corner = n.mod("UICorner")
    radius = 0.0
    if corner:
        sc, off = ud(corner.get("CornerRadius"))
        radius = sc * min(n.w, n.h) + off
    rot = float(n.get("Rotation", 0) or 0)
    group = n.get("GroupTransparency", 0) if n.cls == "CanvasGroup" else 0
    sub_img = saved = None
    if n.cls == "CanvasGroup" and group and group > 0.01:
        sub_img = Image.new("RGBA", pt.img.size, (0, 0, 0, 0))
        saved, pt.img = pt.img, sub_img
    bg_t = n.get("BackgroundTransparency", 0)
    grads = n.mods.get("UIGradient", [])
    stroke = n.mod("UIStroke")
    if n.w > 0 and n.h > 0:
        if stroke:
            th = float(stroke.get("Thickness", 1))
            st = float(stroke.get("Transparency", 0))
            if th > 0 and st < 0.995:
                ring, reg = pt.shape(box, radius, rot, grow=th, hole=1)
                # a UIGradient parented to the stroke tints the stroke; one parented to the object tints the fill
                sgrad = stroke.mod("UIGradient")
                pt.put(ring, reg, color(stroke.get("Color")), (1 - st) * inherited_alpha, clip, sgrad, (n.x - th, n.y - th, n.x + n.w + th, n.y + n.h + th) if sgrad else None)
        if bg_t < 0.999:
            m, reg = pt.shape(box, radius, rot)
            pt.put(m, reg, color(n.get("BackgroundColor3"), (0.63, 0.63, 0.63)), (1 - bg_t) * inherited_alpha, clip, grads[0] if grads else None, box)
    if n.cls in ("TextLabel", "TextButton", "TextBox"):
        text = str(n.get("Text", "") or "")
        placeholder = False
        if n.cls == "TextBox" and text == "":
            text = str(n.get("PlaceholderText", "") or "")
            placeholder = True
        if text:
            draw_text(n, pt, text, clip, inherited_alpha, placeholder)
    child_clip = clip
    if n.get("ClipsDescendants") is True or n.cls in ("ScrollingFrame", "CanvasGroup"):
        m, reg = pt.shape(box, radius, rot)
        full = Image.new("L", pt.img.size, 0)
        if m is not None:
            full.paste(m, (reg[0], reg[1]))
        child_clip = full if clip is None else ImageChops.multiply(full, clip)
    kids = [k for k in n.kids if k.is_gui()]
    kids.sort(key=lambda k: (k.get("ZIndex", 1), k.order))
    for k in kids:
        paint(k, pt, child_clip, inherited_alpha)
    if sub_img is not None:
        pt.img = saved
        sub_img.putalpha(sub_img.getchannel("A").point(lambda v: int(v * (1 - group))))
        pt.img.alpha_composite(sub_img)


def draw_text(n: N, pt: Painter, text, clip, alpha, placeholder):
    size = float(n.get("TextSize", 14))
    f = font_for(enum_name(n.get("Font"), "GothamMedium"), size)
    pl, ptp, pr, pb = padding(n, n.w, n.h)
    aw = n.w - pl - pr
    lines, tw, th = text_lines(n, aw if n.get("TextWrapped") is True else 0, text)
    col = color(n.get("PlaceholderColor3" if placeholder else "TextColor3"), (0, 0, 0))
    a = (1 - float(n.get("TextTransparency", 0))) * alpha
    xa = enum_name(n.get("TextXAlignment"), "Center")
    ya = enum_name(n.get("TextYAlignment"), "Center")
    lh = size * 1.18
    total = lh * len(lines)
    y0 = n.y + ptp + {"Top": 0, "Bottom": (n.h - ptp - pb) - total}.get(ya, ((n.h - ptp - pb) - total) / 2)
    truncate = enum_name(n.get("TextTruncate"), "None") == "AtEnd"
    reg = pt.region((n.x, n.y, n.x + n.w, n.y + n.h), pad=4)
    rw, rh = reg[2] - reg[0], reg[3] - reg[1]
    if rw <= 0 or rh <= 0 or a <= 0.003:
        return
    layer = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, line in enumerate(lines):
        if truncate and f.getlength(line) / SS > aw and aw > 4:
            while line and f.getlength(line + "\u2026") / SS > aw:
                line = line[:-1]
            line += "\u2026"
        lw = f.getlength(line) / SS
        x = n.x + pl + {"Left": 0, "Right": aw - lw}.get(xa, (aw - lw) / 2)
        d.text((x * SS - reg[0], (y0 + i * lh) * SS - reg[1]), line, font=f, fill=tuple(int(c * 255) for c in col) + (255,))
    mask = layer.getchannel("A").point(lambda v: int(v * a))
    if clip is not None:
        mask = ImageChops.multiply(mask, clip.crop(reg))
    layer.putalpha(mask)
    pt.img.alpha_composite(layer, dest=(reg[0], reg[1]))


def scene_background(w, h):
    """A neutral game-like backdrop (sky gradient, ground, a few blocks) so transparency can be judged."""
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(96 + 70 * (1 - t)), int(142 + 60 * (1 - t)), int(190 + 40 * (1 - t))) if y < h * 0.62 else (92 + int(30 * t), 120 + int(20 * t), 74))
    d.rectangle([w * 0.08, h * 0.35, w * 0.28, h * 0.66], fill=(176, 120, 86))
    d.rectangle([w * 0.62, h * 0.28, w * 0.9, h * 0.66], fill=(120, 124, 140))
    d.polygon([(w * 0.45, h * 0.66), (w * 0.52, h * 0.5), (w * 0.6, h * 0.66)], fill=(70, 80, 100))
    return img


def fit_scaled(n: N):
    """TextScaled + UITextSizeConstraint like Roblox: the largest size <= MaxTextSize that fits the box (single line)."""
    for k in n.kids:
        if not k.is_gui():
            continue
        if k.cls in ("TextLabel", "TextButton", "TextBox") and k.get("TextScaled") is True and k.w > 0 and k.h > 0:
            cons = (k.mods.get("UITextSizeConstraint") or [None])[0]
            mx = float(cons.get("MaxTextSize", 100)) if cons else 100.0
            mn = float(cons.get("MinTextSize", 1)) if cons else 1.0
            pl, ptp, pr, pb = padding(k, k.w, k.h)
            size = min(mx, (k.h - ptp - pb) / 1.18)
            text = str(k.get("Text", "") or "")
            while size > mn:
                f = font_for(enum_name(k.get("Font"), "GothamMedium"), size)
                if f.getlength(text) / SS <= k.w - pl - pr:
                    break
                size -= 0.5
            k.p["TextSize"] = max(mn, size)
        fit_scaled(k)


def render(snapshot: dict, out_path: pathlib.Path):
    vw, vh = snapshot["viewport"]
    base = scene_background(int(vw), int(vh))
    pt = Painter(vw, vh, base)
    issues = []
    for tree in snapshot["trees"]:
        root = N(tree)
        # ScreenGui: children laid out against the viewport
        root.w, root.h = vw, vh
        gui = [k for k in root.kids if k.is_gui()]
        wrapper = N({"c": "Frame", "n": "ScreenGui:" + root.name, "p": {"BackgroundTransparency": 1}, "k": []})
        wrapper.kids = root.kids
        wrapper.w, wrapper.h = vw, vh
        layout_children(wrapper, vw, vh)
        for k in wrapper.kids:
            if k.is_gui():
                absolutize(k, 0, 0)
        fit_scaled(wrapper)
        ks = sorted(gui, key=lambda k: (k.get("ZIndex", 1), k.order))
        for k in ks:
            paint(k, pt, None)
        collect_issues(wrapper, issues, vw, vh)
    img = pt.img.resize((int(vw), int(vh)), Image.LANCZOS).convert("RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    return issues


def collect_issues(n: N, issues, vw, vh, path=""):
    """Cheap automatic checks: text wider than its box, objects outside the viewport, tiny interactive boxes."""
    for k in n.kids:
        if not k.is_gui() or k.get("Visible", True) is False:
            continue
        here = path + "/" + k.name
        if k.cls in ("TextLabel", "TextButton") and k.get("Text") and k.w > 0:
            size = float(k.get("TextSize", 14))
            f = font_for(enum_name(k.get("Font"), "GothamMedium"), size)
            lines, tw, th = text_lines(k, k.w if k.get("TextWrapped") is True else 0)
            pl, pt_, pr, pb = padding(k, k.w, k.h)
            if tw > k.w - pl - pr + 1:
                kind = "truncated" if enum_name(k.get("TextTruncate")) == "AtEnd" else "overflows"
                issues.append(f"text {kind}: {here.split('/')[-3:]} '{str(k.get('Text'))[:40]}' {tw:.0f}>{k.w - pl - pr:.0f}")
            if th > k.h - pt_ - pb + 2 and k.h > 0:
                issues.append(f"text taller than box: {here} '{str(k.get('Text'))[:30]}' {th:.0f}>{k.h - pt_ - pb:.0f}")
        if k.cls == "TextButton" and 0 < min(k.w, k.h) < 20 and k.get("Active", True) is not False:
            issues.append(f"small button: {here} {k.w:.0f}x{k.h:.0f}")
        collect_issues(k, issues, vw, vh, here)


def main():
    out = ROOT / "dist" / "shots"
    luau = "/tmp/claude-0/luau/luau"
    only = None
    args = sys.argv[1:]
    while args:
        a = args.pop(0)
        if a == "--out":
            out = pathlib.Path(args.pop(0))
        elif a == "--luau":
            luau = args.pop(0)
        elif a == "--jobs":
            only = set(args.pop(0).split(","))
    jobs_path = ROOT / "tools" / "ui_jobs.json"
    jobs = json.loads(jobs_path.read_text(encoding="utf-8"))["jobs"]
    if only:
        jobs = [j for j in jobs if j["name"] in only]
    text = build.build(True).read_text(encoding="utf-8")
    cfg = json.dumps({"jobs": jobs})
    text = text.replace('return __import("tests/runner")', 'SNAP_CFG_JSON = [==[' + cfg + ']==]\nreturn __import("tests/ui_snapshot")')
    script = ROOT / "dist" / "snapshot.lua"
    script.write_text(text, encoding="utf-8")
    res = subprocess.run([luau, str(script)], capture_output=True, text=True, timeout=1200)
    report = []
    for line in res.stdout.splitlines():
        if line.startswith("@@ERR "):
            print(line)
        if line.startswith("@@SNAP "):
            _, name, payload = line.split(" ", 2)
            snap = json.loads(payload)
            issues = render(snap, out / f"{name}.png")
            report.append((name, issues))
            print(f"{name}: {len(issues)} layout notes")
    (out / "issues.txt").write_text("\n".join(f"## {n}\n" + "\n".join(i[:60]) for n, i in report), encoding="utf-8")
    if not report:
        print(res.stdout[-1500:], res.stderr[-1500:])


if __name__ == "__main__":
    main()
