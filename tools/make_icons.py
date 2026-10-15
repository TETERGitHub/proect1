#!/usr/bin/env python3
"""Draw the hub's icons as a detailed, anti-aliased sprite sheet (assets/ui/icons.png) plus its index (src/data/IconSheet.luau).

Own drawing, iOS-like line style: 1.6-unit strokes with round caps and joins on a 24-unit grid, small details (door and chimney,
lens glint, gauge ticks, bug legs...). Rendered with signed distance fields at 4x and box-filtered down, so edges are smooth.
White on transparent: the hub tints every icon with its colour token. The old primitive icons (data/IconData) stay as the fallback.
Deterministic. Run, then tools/pack_ui.py."""
import math, pathlib
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
CELL, SS, COLS = 96, 4, 6
R = CELL * SS
W = 1.6  # default stroke width in grid units


class Canvas:
    def __init__(self):
        g = (np.arange(R) + 0.5) / R * 24
        self.x, self.y = np.meshgrid(g, g)
        self.a = np.zeros((R, R))
        self.px = 24 / R

    def _cov(self, d):
        return np.clip(0.5 - d / self.px, 0, 1)

    def add(self, d):
        self.a = np.maximum(self.a, self._cov(d))

    def cut(self, d):
        self.a = np.minimum(self.a, 1 - self._cov(d))

    # signed distances -------------------------------------------------------
    def seg_d(self, p, q):
        px, py = self.x - p[0], self.y - p[1]
        vx, vy = q[0] - p[0], q[1] - p[1]
        t = np.clip((px * vx + py * vy) / max(1e-9, vx * vx + vy * vy), 0, 1)
        return np.hypot(px - vx * t, py - vy * t)

    def line(self, p, q, w=W):
        self.add(self.seg_d(p, q) - w / 2)

    def poly(self, pts, w=W, closed=False):
        n = len(pts)
        for i in range(n if closed else n - 1):
            self.line(pts[i], pts[(i + 1) % n], w)

    def circle(self, c, r, w=W):
        self.add(np.abs(np.hypot(self.x - c[0], self.y - c[1]) - r) - w / 2)

    def disc(self, c, r):
        self.add(np.hypot(self.x - c[0], self.y - c[1]) - r)

    def arc(self, c, r, a0, a1, w=W, steps=48):
        pts = [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)), c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps))) for i in range(steps + 1)]
        self.poly(pts, w)

    def bez(self, p0, p1, p2, p3, w=W, steps=32):
        pts = []
        for i in range(steps + 1):
            t = i / steps
            mt = 1 - t
            pts.append((mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
                        mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1]))
        self.poly(pts, w)

    def rrect_d(self, x, y, w, h, r):
        cx, cy = x + w / 2, y + h / 2
        qx, qy = np.abs(self.x - cx) - w / 2 + r, np.abs(self.y - cy) - h / 2 + r
        return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

    def rrect(self, x, y, w, h, r, sw=W):
        self.add(np.abs(self.rrect_d(x, y, w, h, r)) - sw / 2)

    def rfill(self, x, y, w, h, r):
        self.add(self.rrect_d(x, y, w, h, r))

    def fill(self, pts, round_=0.0):
        """filled polygon (even-odd), optionally with rounded outline"""
        inside = np.zeros_like(self.a, bool)
        n = len(pts)
        for i in range(n):
            (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
            cond = (y1 > self.y) != (y2 > self.y)
            xint = x1 + (self.y - y1) * (x2 - x1) / ((y2 - y1) if y2 != y1 else 1e-9)
            inside ^= cond & (self.x < xint)
        d = np.min([self.seg_d(pts[i], pts[(i + 1) % n]) for i in range(n)], axis=0)
        sd = np.where(inside, -d, d) - round_
        self.add(sd)

    def image(self):
        a = self.a.reshape(CELL, SS, CELL, SS).mean(axis=(1, 3))
        return a


ICONS = {}


def icon(fn):
    ICONS[fn.__name__.rstrip("_")] = fn
    return fn


@icon
def home(c):
    c.poly([(3, 11.2), (12, 3.6), (21, 11.2)])
    c.poly([(5.4, 9.4), (5.4, 20), (18.6, 20), (18.6, 9.4)])
    c.rrect(10, 13.6, 4, 6.4, 1.2)
    c.poly([(16.4, 7.3), (16.4, 4.4), (18.4, 4.4), (18.4, 9)])


@icon
def search(c):
    c.circle((10.4, 10.4), 6.4)
    c.line((15.2, 15.2), (20.6, 20.6), 2.4)
    c.arc((10.4, 10.4), 4.0, 200, 260, 1.2)


@icon
def sliders(c):
    for y, k in ((6, 15.5), (12, 8.5), (18, 13)):
        c.line((3.5, y), (20.5, y))
        c.disc((k, y), 2.6)
        c.cut(np.hypot(c.x - k, c.y - y) - 1.25)


@icon
def target(c):
    c.circle((12, 12), 8.4)
    c.circle((12, 12), 4.2, 1.4)
    c.disc((12, 12), 1.3)
    for a, b in (((12, 1.6), (12, 5.6)), ((12, 18.4), (12, 22.4)), ((1.6, 12), (5.6, 12)), ((18.4, 12), (22.4, 12))):
        c.line(a, b)


@icon
def camera(c):
    c.rrect(2.8, 7, 18.4, 12.6, 2.6)
    c.poly([(8, 7), (9.4, 4.6), (14.6, 4.6), (16, 7)])
    c.circle((12, 13.2), 3.9)
    c.circle((12, 13.2), 1.9, 1.0)
    c.arc((12, 13.2), 2.9, 200, 250, 0.9)
    c.disc((17.6, 9.8), 0.9)


@icon
def sun(c):
    c.circle((12, 12), 4.2)
    c.disc((12, 12), 1.8)
    for i in range(8):
        a = i * math.pi / 4
        c.line((12 + math.cos(a) * 7, 12 + math.sin(a) * 7), (12 + math.cos(a) * 9.6, 12 + math.sin(a) * 9.6))


@icon
def shirt(c):
    c.poly([(8.6, 3.6), (3, 6.8), (4.8, 11), (7.2, 10), (7.2, 20.4), (16.8, 20.4), (16.8, 10), (19.2, 11), (21, 6.8), (15.4, 3.6)], closed=False)
    c.bez((8.6, 3.6), (9.6, 6.6), (14.4, 6.6), (15.4, 3.6))
    c.line((12, 9.2), (12, 9.21), 1.3)


@icon
def gun(c):
    c.rrect(2.6, 6.4, 18.4, 4.6, 1.2)
    c.line((21, 7.4), (21.8, 7.4), 1.4)
    c.poly([(13.2, 11), (14.6, 19.2), (18.8, 19.2), (17.4, 11)], closed=False)
    c.arc((11.2, 12.2), 2.4, 0, 180, 1.4)
    c.line((5.2, 8.7), (11.2, 8.7), 1.0)
    c.disc((4.2, 6.4), 0.8)


@icon
def knife(c):
    # blade (filled) with a thin bevel line cut into it, a crossguard and a handle with two rivets
    c.fill([(3.0, 21.0), (13.6, 10.4), (15.6, 12.4), (6.2, 19.6)], 0.15)
    c.cut(c.seg_d((5.2, 19.2), (13.2, 11.2)) - 0.32)
    c.line((12.6, 9.4), (16.6, 13.4), 1.9)
    c.poly([(15.6, 10.4), (19.6, 6.4), (21.2, 4.8), (19.2, 2.8), (17.6, 4.4), (13.6, 8.4)], 1.4, closed=True)
    c.disc((18.2, 6.0), 0.7)
    c.disc((16.4, 7.8), 0.7)


@icon
def person(c):
    c.circle((12, 8), 4)
    c.bez((4.2, 21), (4.6, 15.2), (8, 13.6), (12, 13.6))
    c.bez((12, 13.6), (16, 13.6), (19.4, 15.2), (19.8, 21))
    c.line((4.2, 21), (19.8, 21))


@icon
def music(c):
    c.poly([(9.6, 17.2), (9.6, 5.2), (19.6, 3.2), (19.6, 15.2)])
    c.line((9.6, 8.6), (19.6, 6.6), 1.4)
    c.disc((7.4, 17.4), 2.6)
    c.disc((17.4, 15.4), 2.6)


@icon
def speaker(c):
    c.poly([(3.4, 9.2), (7.2, 9.2), (12, 4.8), (12, 19.2), (7.2, 14.8), (3.4, 14.8)], closed=True)
    c.arc((12.4, 12), 3.8, -45, 45)
    c.arc((12.4, 12), 7.2, -50, 50)


@icon
def gauge(c):
    c.arc((12, 13.4), 8.6, 150, 390)
    for i in range(7):
        a = math.radians(150 + i * 40)
        c.line((12 + math.cos(a) * 6.2, 13.4 + math.sin(a) * 6.2), (12 + math.cos(a) * 7.2, 13.4 + math.sin(a) * 7.2), 1.1)
    c.line((12, 13.4), (16.4, 8.6), 1.7)
    c.disc((12, 13.4), 1.7)


@icon
def timer(c):
    c.circle((12, 13.4), 7.8)
    c.line((12, 13.4), (12, 8.8))
    c.line((12, 13.4), (15.2, 15.2))
    c.line((9.6, 2.8), (14.4, 2.8), 1.8)
    c.line((12, 2.8), (12, 5.4))
    c.line((18.2, 6.2), (19.6, 4.8))


@icon
def keyboard(c):
    c.rrect(1.8, 6, 20.4, 12, 2.4)
    for row, y in enumerate((9.2, 12)):
        for i in range(6 if row == 0 else 5):
            x = 5 + i * 2.8 + (1.4 if row else 0)
            c.rfill(x - 0.75, y - 0.7, 1.5, 1.4, 0.4)
    c.line((7.4, 15), (16.6, 15), 1.5)


@icon
def folder(c):
    c.poly([(2.6, 18.6), (2.6, 5.4), (9, 5.4), (11, 7.8), (21.4, 7.8), (21.4, 18.6)], closed=True)
    c.line((2.6, 10.4), (21.4, 10.4), 1.2)


@icon
def bug(c):
    c.add(np.abs(np.hypot((c.x - 12) / 5.2, (c.y - 14) / 7.0) - 1) * 5.2 - W / 2)
    c.arc((12, 8.2), 3.2, 180, 360)
    c.line((12, 9.6), (12, 20.4), 1.2)
    for y, dx in ((11.4, 3.4), (14.6, 3.6), (17.8, 3.2)):
        c.line((6.8, y), (6.8 - dx, y - 1.2 + (y - 14.6) * 0.3), 1.4)
        c.line((17.2, y), (17.2 + dx, y - 1.2 + (y - 14.6) * 0.3), 1.4)
    c.line((10.2, 5.4), (8.6, 2.8), 1.3)
    c.line((13.8, 5.4), (15.4, 2.8), 1.3)


@icon
def alert(c):
    c.poly([(12, 3.2), (21.4, 19.8), (2.6, 19.8)], closed=True)
    c.line((12, 9.2), (12, 14), 2.0)
    c.disc((12, 16.9), 1.15)


@icon
def info(c):
    c.circle((12, 12), 9)
    c.line((12, 10.8), (12, 16.8), 2.0)
    c.disc((12, 7.6), 1.2)


@icon
def help_(c):
    c.circle((12, 12), 9)
    c.arc((12, 9.4), 2.9, 190, 360 + 40, 1.9)
    c.line((14.2, 11.3), (12, 13.2), 1.9)
    c.line((12, 13.2), (12, 13.9), 1.9)
    c.disc((12, 17), 1.15)


@icon
def star(c):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 9.4 if i % 2 == 0 else 4.1
        pts.append((12 + math.cos(a) * r, 12.6 + math.sin(a) * r))
    c.poly(pts, closed=True)


@icon
def close(c):
    c.line((6, 6), (18, 18), 2.0)
    c.line((18, 6), (6, 18), 2.0)


@icon
def minus(c):
    c.line((5.4, 12), (18.6, 12), 2.0)


@icon
def plus(c):
    c.line((5.4, 12), (18.6, 12), 2.0)
    c.line((12, 5.4), (12, 18.6), 2.0)


@icon
def check(c):
    c.poly([(4.6, 12.6), (9.6, 17.6), (19.4, 6.6)], 2.1)


@icon
def chevron(c):
    c.poly([(9, 4.8), (16.2, 12), (9, 19.2)], 2.1)


@icon
def play(c):
    c.fill([(8, 4.6), (19.4, 12), (8, 19.4)], 1.0)


@icon
def pause(c):
    c.rfill(6.2, 4.6, 4, 14.8, 1.4)
    c.rfill(13.8, 4.6, 4, 14.8, 1.4)


@icon
def skip(c):
    c.fill([(5, 5.2), (14.8, 12), (5, 18.8)], 0.9)
    c.rfill(16.4, 5, 2.8, 14, 1.2)


@icon
def shuffle(c):
    c.bez((2.8, 7), (9, 7), (13, 17), (19.6, 17))
    c.bez((2.8, 17), (9, 17), (13, 7), (19.6, 7))
    for y in (7, 17):
        c.poly([(17.2, y - 2.6), (20.2, y), (17.2, y + 2.6)], 1.6)


@icon
def shield(c):
    c.bez((12, 2.8), (15, 4.6), (18, 5), (20, 5))
    c.bez((20, 5), (20.4, 13.4), (17, 18.6), (12, 21.2))
    c.bez((12, 2.8), (9, 4.6), (6, 5), (4, 5))
    c.bez((4, 5), (3.6, 13.4), (7, 18.6), (12, 21.2))
    c.poly([(8.4, 12.2), (11, 14.8), (15.8, 9.4)], 1.7)


@icon
def trash(c):
    c.line((3.6, 6.2), (20.4, 6.2))
    c.poly([(9, 6.2), (9.6, 3.4), (14.4, 3.4), (15, 6.2)])
    c.poly([(5.6, 6.2), (6.8, 20.6), (17.2, 20.6), (18.4, 6.2)])
    for x in (9.6, 12, 14.4):
        c.line((x, 9.6), (x, 17.4), 1.3)


@icon
def bolt(c):
    c.fill([(13.8, 2.4), (5.2, 13.6), (11.2, 13.6), (9.8, 21.6), (18.8, 10), (12.6, 10)], 0.35)


def main():
    names = list(ICONS)
    rows = math.ceil(len(names) / COLS)
    sheet = np.zeros((rows * CELL, COLS * CELL))
    for i, name in enumerate(names):
        cv = Canvas()
        ICONS[name](cv)
        r, col = divmod(i, COLS)
        sheet[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL] = cv.image()
    a = (np.clip(sheet, 0, 1) * 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([np.full_like(a, 255), a]), "LA")
    img.save(ROOT / "assets" / "ui" / "icons.png", optimize=True)
    lines = ["--!nonstrict", "-- data/IconSheet: GENERATED by tools/make_icons.py. Where each icon sits in assets/ui/icons.png (bundled in data/UiPack).",
             "", "return {", "\tcell = %d," % CELL, "\tcols = %d," % COLS, "\tindex = {"]
    for i, n in enumerate(names):
        lines.append('\t\t%s = %d,' % (n, i))
    lines += ["\t},", "}"]
    (ROOT / "src" / "data" / "IconSheet.luau").write_text("\n".join(lines) + "\n")
    print(len(names), "icons ->", img.size)


if __name__ == "__main__":
    main()
