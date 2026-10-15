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
    sway = (n - 0.5) * 0.42 * v ** 1.4
    # silhouette: a rounded, soft base (no flat cut), widest a quarter of the way up, tapering into tongues at the top
    vv = np.clip((v - 0.04) / 0.92, 0, 1)
    width = np.where(vv < 0.16, 0.5 * np.sqrt(np.clip(vv / 0.16, 0, 1)), 0.5 * np.clip(1 - (vv - 0.16) / 0.84, 0, 1) ** 0.6) + 0.02
    body = np.clip(1 - (np.abs(u + sway) / width) ** 2, 0, 1)
    # the turbulence eats the flame from the top down: solid near the base, licking tongues above
    erosion = np.clip(n * 2.0 - vv * 1.25 + 0.45, 0, 1)
    dens = np.clip(body * erosion * 1.7, 0, 1) * np.clip(vv / 0.12, 0, 1) ** 0.8
    a = np.asarray(Image.fromarray((dens * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), float) / 255
    # hot core: brightest low in the middle, dimmer toward edges and tips (the emitter colour is multiplied by this)
    core = np.clip(body ** 1.5 * (1 - vv * 0.9), 0, 1)
    lum = np.asarray(Image.fromarray(((0.5 + 0.5 * core) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), float) / 255
    frames.append((a, lum))
sheet = np.zeros((N * 4, N * 4))
lums = np.zeros((N * 4, N * 4))
for i, (a, lum) in enumerate(frames):
    sl = (slice((i // 4) * N, (i // 4 + 1) * N), slice((i % 4) * N, (i % 4 + 1) * N))
    sheet[sl], lums[sl] = a, lum
la = np.dstack([(lums * 255).astype(np.uint8), (sheet * 255).astype(np.uint8)])
Image.fromarray(la, "LA").save(ROOT / "assets" / "fx" / "fire.png", optimize=True)
print("fire flipbook", la.shape)


# ---- fire_puff.png: wisps of flame for volumetric fire (features/AuraFX Burning). Many of them stream upward, overlap and add
# up into one body of flame; the shape comes from the flow. Each frame: domain-warped turbulence (the warp makes the curling,
# licking structure of real flame), stretched upward, inside a tall teardrop that frays into tongues. 16 frames, seamless loop.
def fbm(px, py, t, octaves, seed):
    """periodic-in-time turbulence from random travelling waves (stays seamless over the 16 frames)"""
    r = np.random.default_rng(seed)
    out = np.zeros_like(px)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = 2.0 ** o
        for _ in range(5):
            ang = r.random() * 2 * np.pi
            kx, ky = np.cos(ang) * f * 1.0, np.sin(ang) * f * 0.55   # squeezed vertically: streaks run up
            ph = r.random() * 2 * np.pi
            spd = int(r.integers(1, 3)) * (1 if o < 2 else 2)
            out += amp * np.sin(2 * np.pi * (kx * px + ky * py + spd * t) + ph)
            tot += amp
        amp *= 0.55
    return out / tot * 0.5 + 0.5


PU = 256
py_, px_ = np.mgrid[0:PU, 0:PU].astype(float)
U = (px_ - PU / 2) / (PU / 2)        # -1..1
V = 1 - py_ / PU                     # 0 bottom .. 1 top
puffs = []
for f in range(FR):
    t = f / FR
    # domain warp: offset the sample point by another turbulence field, twice (curls inside curls)
    w1 = fbm(U * 1.2, V * 1.2 - t, t, 3, 11) - 0.5
    w2 = fbm(U * 1.2 + 3.1, V * 1.2 + 1.7 - t, t, 3, 12) - 0.5
    n = fbm(U * 1.6 + w1 * 1.4, V * 1.6 - t * 2 + w2 * 1.4, t, 5, 13)
    # shape: tall teardrop, rounded soft base low in the cell, tapering to a point near the top; it sways with the warp
    vv = np.clip((V - 0.06) / 0.9, 0, 1)
    half = np.where(vv < 0.22, 0.42 * np.sqrt(np.clip(vv / 0.22, 0, 1)), 0.42 * np.clip(1 - (vv - 0.22) / 0.78, 0, 1) ** 0.7) + 0.015
    xs = U + w1 * 0.55 * vv ** 1.2
    mask = np.clip(1 - (xs / half) ** 2, 0, 1)
    base = np.clip(vv / 0.1, 0, 1) ** 0.7
    # the turbulence eats away more of the flame the higher it gets: solid low, ragged tongues high
    dens = np.clip(mask * base * (n * 1.9 - vv * 0.9 + 0.12), 0, 1)
    dens = np.clip(dens * 1.6, 0, 1) ** 1.2
    a = np.asarray(Image.fromarray((dens * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.4)), float) / 255
    # brightness: hot inside and low down, darker streaks between the curls
    lum = np.clip(0.35 + 0.65 * (mask ** 0.6) * (1 - vv * 0.6) * (0.6 + 0.4 * n), 0, 1)
    puffs.append((a, lum))
sheet = np.zeros((PU * 4, PU * 4))
lums = np.zeros((PU * 4, PU * 4))
for i, (a, lum) in enumerate(puffs):
    sl = (slice((i // 4) * PU, (i // 4 + 1) * PU), slice((i % 4) * PU, (i % 4 + 1) * PU))
    sheet[sl], lums[sl] = a, lum
la = np.dstack([(lums * 255).astype(np.uint8), (sheet * 255).astype(np.uint8)])
Image.fromarray(la, "LA").save(ROOT / "assets" / "fx" / "fire_puff.png", optimize=True)
print("fire wisps", la.shape)
