#!/usr/bin/env python3
"""Turn the owner's Trollface pictures (assets/trolls/*.jpg, supplied by the project owner) into stickers - white background
removed, a white sticker outline and soft shadow added - packed with the menu mascot into assets/fx/trolls.png, a 4x4 grid of
128 px cells (faces repeated to fill it) for random-face particles and billboards."""
import pathlib
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
CELL = 128


def sticker(path):
    im = Image.open(path).convert("RGB")
    im.thumbnail((360, 360), Image.LANCZOS)
    g = np.asarray(im.convert("L"), float) / 255
    H, W = g.shape
    bg = np.zeros((H, W), bool)
    q = deque([(0, x) for x in range(W)] + [(H - 1, x) for x in range(W)] + [(y, 0) for y in range(H)] + [(y, W - 1) for y in range(H)])
    while q:
        y, x = q.popleft()
        if 0 <= y < H and 0 <= x < W and not bg[y, x] and g[y, x] > 0.86:
            bg[y, x] = True
            q.extend([(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)])
    inside = Image.fromarray((~bg * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    pad = 22
    big = Image.new("L", (W + pad * 2, H + pad * 2), 0)
    big.paste(inside, (pad, pad))
    border = big.filter(ImageFilter.MaxFilter(15))
    shadow = border.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.4))
    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", big.size, (0, 0, 0, 0)); sh.putalpha(shadow)
    out.alpha_composite(sh, (0, 4))
    wb = Image.new("RGBA", big.size, (255, 255, 255, 0)); wb.putalpha(border)
    out.alpha_composite(wb)
    face = Image.new("RGBA", big.size, (0, 0, 0, 0))
    face.paste(im.convert("RGBA"), (pad, pad), inside)
    out.alpha_composite(face)
    out = out.crop(out.getbbox())
    out.thumbnail((CELL - 6, CELL - 6), Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.paste(out, ((CELL - out.width) // 2, (CELL - out.height) // 2), out)
    return cell


def main():
    faces = [Image.open(ROOT / "assets" / "ui" / "sticker.png").convert("RGBA")]
    faces[0].thumbnail((CELL - 6, CELL - 6), Image.LANCZOS)
    c0 = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)); c0.paste(faces[0], ((CELL - faces[0].width) // 2, (CELL - faces[0].height) // 2), faces[0])
    faces = [c0] + [sticker(p) for p in sorted((ROOT / "assets" / "trolls").glob("*.jpg"))]
    sheet = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))
    for i in range(16):
        sheet.paste(faces[i % len(faces)], ((i % 4) * CELL, (i // 4) * CELL))
    # mostly black and white line art (one red glint): 64 colours are plenty and keep the hub script small
    sheet.quantize(colors=64, method=Image.Quantize.FASTOCTREE).convert("RGBA").save(ROOT / "assets" / "fx" / "trolls.png", optimize=True)
    print(len(faces), "trollfaces")


if __name__ == "__main__":
    main()
