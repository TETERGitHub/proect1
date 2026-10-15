#!/usr/bin/env python3
"""Generate the menu's own image assets into assets/ui (then run tools/pack_ui.py):
bg_chrome.jpg  liquid-chrome waves on black (window background; tinted in the hub by theme / own menu colour)
grain.png      tileable fine noise (frosted-glass grain overlay)
sheen.png      soft diagonal highlight (glass specular)
shadow.png     soft rounded-rectangle shadow for 9-slice scaling (window drop shadow)
All procedural and deterministic; nothing third-party."""
import pathlib
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "ui"


def chrome(w=1024, h=640):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    u, v = x / w * 6.0, y / h * 3.8
    # flowing folds: a few interfering waves, warped so the ridges curve like poured metal
    warp = 0.9 * np.sin(v * 1.3 + u * 0.4) + 0.5 * np.sin(u * 0.7 - v * 0.9)
    hgt = (np.sin(u * 1.1 + warp * 1.4) * 0.55 + np.sin(u * 0.45 + v * 1.6 + warp) * 0.35
           + np.sin(u * 2.3 - v * 0.8 + warp * 0.6) * 0.12)
    gy, gx = np.gradient(hgt * 26)
    n = np.dstack([-gx, -gy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    # reflect the view ray (0,0,-1) and look it up in a studio environment: bright soft-box above, dark horizon band, grey floor
    ry = 2 * n[..., 2] * n[..., 1]
    rx = 2 * n[..., 2] * n[..., 0]
    env = np.where(ry > 0.08, 0.55 + 0.45 * np.clip((ry - 0.08) * 3, 0, 1), np.where(ry > -0.06, 0.03, 0.18 + 0.25 * np.clip(-ry - 0.06, 0, 1)))
    soft = np.exp(-((rx - 0.35) / 0.12) ** 2 - ((ry - 0.45) / 0.18) ** 2)   # a key light highlight
    rim = np.exp(-((ry - 0.1) / 0.025) ** 2) * 0.6                          # thin hot line at the horizon
    img = np.clip(env + soft * 0.8 + rim, 0, 1)
    # deep gaps between the folds go dark so it reads as separate ribbons of metal on black
    depth = np.clip((hgt + 0.55) * 1.6, 0, 1)
    img = img * (0.15 + 0.85 * depth ** 1.6)
    # vignette
    vx, vy = (x / w - 0.5) * 2, (y / h - 0.5) * 2
    img *= np.clip(1.15 - 0.45 * (vx ** 2 + vy ** 2), 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.6))
    im.save(OUT / "bg_chrome.jpg", quality=86, optimize=True)


def grain(n=128):
    rng = np.random.default_rng(4)
    a = rng.random((n, n))
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), float) / 255
    a = (a - a.mean()) / (a.std() + 1e-6)
    alpha = np.clip(0.5 + a * 0.5, 0, 1)
    Image.fromarray(np.dstack([np.full((n, n), 255, np.uint8), (alpha * 255).astype(np.uint8)]), "LA").save(OUT / "grain.png", optimize=True)


def sheen(w=512, h=256):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    t = (x / w * 0.8 + y / h * 0.6)
    a = np.exp(-((t - 0.38) / 0.12) ** 2) * 0.9 + np.exp(-((t - 0.62) / 0.05) ** 2) * 0.5
    a *= np.clip(1.2 - y / h, 0, 1)
    Image.fromarray(np.dstack([np.full((h, w), 255, np.uint8), (np.clip(a, 0, 1) * 255).astype(np.uint8)]), "LA").save(OUT / "sheen.png", optimize=True)


def shadow(n=128, r=34, blur=14):
    im = Image.new("L", (n, n), 0)
    pad = blur * 2
    ImageDraw.Draw(im).rounded_rectangle((pad, pad, n - pad, n - pad), r, fill=255)
    im = im.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(im, float) / 255 * 0.9
    Image.fromarray(np.dstack([np.zeros((n, n), np.uint8), (a * 255).astype(np.uint8)]), "LA").save(OUT / "shadow.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    chrome(); grain(); sheen(); shadow()
    print("ok")
