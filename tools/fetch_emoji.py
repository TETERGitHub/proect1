#!/usr/bin/env python3
"""Build assets/fx/smileys.png (4x4 grid of 128 px, used by the Troll aura and kill effect) from Twemoji.

Twemoji graphics: Copyright 2019 Twitter, Inc and other contributors (maintained fork: github.com/jdecked/twemoji),
licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Attribution is kept in docs/CREDITS.md and next to the
sheet (assets/fx/EMOJI_CREDITS.txt). The SVGs are downloaded and rendered here (needs cairosvg); only the rendered sheet is kept."""
import io, pathlib, urllib.request
from PIL import Image
import cairosvg

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = "https://raw.githubusercontent.com/jdecked/twemoji/main/assets/svg/%s.svg"
# laughing tears, rolling laughing, sunglasses, skull, devil, clown, angry, money, cold, tongue wink, zany, smirk, moai, nerd,
# loudly crying, fire
CODES = ["1f602", "1f923", "1f60e", "1f480", "1f608", "1f921", "1f621", "1f911", "1f976", "1f61c", "1f92a", "1f60f", "1f5ff", "1f913",
         "1f62d", "1f525"]
CELL = 128


def main():
    sheet = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))
    for i, code in enumerate(CODES):
        svg = urllib.request.urlopen(BASE % code, timeout=30).read()
        png = cairosvg.svg2png(bytestring=svg, output_width=CELL - 8, output_height=CELL - 8)
        im = Image.open(io.BytesIO(png)).convert("RGBA")
        sheet.paste(im, ((i % 4) * CELL + 4, (i // 4) * CELL + 4), im)
    sheet.save(ROOT / "assets" / "fx" / "smileys.png", optimize=True)
    (ROOT / "assets" / "fx" / "EMOJI_CREDITS.txt").write_text(
        "smileys.png: Twemoji graphics, Copyright 2019 Twitter, Inc and other contributors\n"
        "(github.com/jdecked/twemoji), licensed CC BY 4.0: https://creativecommons.org/licenses/by/4.0/\n"
        "Rendered from the original SVGs at 120 px into a 4x4 grid; not otherwise modified.\n"
        "Emoji used (in grid order): " + " ".join("U+" + c.upper() for c in CODES) + "\n")
    print("smileys.png from Twemoji:", len(CODES))


if __name__ == "__main__":
    main()
