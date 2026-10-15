#!/usr/bin/env python3
"""Animated fire texture for ParticleEmitter flipbooks: assets/fx/fire.png, a 4x4 grid of 256 px frames (Grid4x4, loop).
Each frame is turbulent noise scrolled upward and squeezed into a flame silhouette: a dense base breaking into licking
tongues. Brightness only (white on transparent): the effect colours it over each particle's life (white-yellow core ->
orange -> dark red tips). Procedural, deterministic, nothing third-party."""
import pathlib
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
N, FR = 256, 16
rng = np.random.default_rng(31)
# a tileable 3-D-ish noise volume: several octaves of random grids, upsampled; the third axis is time (frames)
def layer(scale, seed):
    r = np.random.default_rng(seed)
    g = r.random((scale, scale, FR))
    out = np.zeros((N, N, FR))
    for f in range(FR):
        im = Image.fromarray((g[:, :, f] * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        out[:, :, f] = np.asarray(im, float) / 255
    return out

y, x = np.mgrid[0:N, 0:N].astype(float)
u = (x - N / 2) / (N / 2)          # -1 .. 1
v = 1 - y / N                      # 0 bottom .. 1 top
# seamless turbulence: a sum of random waves, all periodic in time over the 16 frames, travelling upward at different speeds
waves = []
for k in range(48):
    cyc = rng.integers(2, 11)
    ang = np.pi / 2 + rng.normal() * 0.35   # mostly vertical ridges: long licking tongues
    kx, ky = np.sin(ang) * cyc, np.cos(ang) * cyc * 0.6
    spd = rng.integers(1, 4)            # whole cycles per loop: keeps the loop seamless
    waves.append((kx, ky, spd, rng.random() * 2 * np.pi, 1.0 / cyc ** 0.75))
frames = []
for f in range(FR):
    t = f / FR
    n = np.zeros((N, N))
    for kx, ky, spd, ph, amp in waves:
        n += amp * np.sin(2 * np.pi * (kx * x / N + ky * y / N + spd * t) + ph)
    n = (n - n.min()) / (n.max() - n.min())
    sway = (n - 0.5) * 0.55 * v ** 1.2
    width = 0.5 * (1 - v) ** 0.75 + 0.03
    body = np.clip(1 - np.abs(u + sway) / width, 0, 1) ** 0.8
    dens = body * np.clip(n * 1.9 - v * 1.25 + 0.05, 0, 1)
    dens = np.clip(dens * 1.8, 0, 1)
    dens = dens ** 1.15 * (0.55 + 0.45 * np.clip(1 - v * 1.3, 0, 1))   # thinner, more see-through toward the tips
    a = np.asarray(Image.fromarray((dens * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), float) / 255
    frames.append(a)
sheet = np.zeros((N * 4, N * 4))
for i, a in enumerate(frames):
    sheet[(i // 4) * N:(i // 4 + 1) * N, (i % 4) * N:(i % 4 + 1) * N] = a
la = np.dstack([np.full(sheet.shape, 255, np.uint8), (sheet * 255).astype(np.uint8)])
Image.fromarray(la, "LA").save(ROOT / "assets" / "fx" / "fire.png", optimize=True)
print("fire flipbook", la.shape)
