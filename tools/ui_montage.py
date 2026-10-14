#!/usr/bin/env python3
"""Tile cropped window screenshots from dist/shots into contact sheets: python3 tools/ui_montage.py name1 name2 ... -o out.png"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
args = sys.argv[1:]
out = ROOT / "dist" / "shots" / "montage.png"
if "-o" in args:
    i = args.index("-o")
    out = pathlib.Path(args[i + 1])
    args = args[:i] + args[i + 2:]
box = (250, 95, 1030, 635)  # the window and its shadow at the default 1280x720 viewport
imgs = [Image.open(ROOT / "dist" / "shots" / f"{n}.png").crop(box) for n in args]
cols = 2
rows = (len(imgs) + cols - 1) // cols
w, h = imgs[0].size
sheet = Image.new("RGB", (w * cols, h * rows), (20, 20, 20))
for i, im in enumerate(imgs):
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
sheet.save(out)
print(out, sheet.size)
