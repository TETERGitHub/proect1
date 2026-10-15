#!/usr/bin/env python3
"""Render previews of converted models from a models folder (index.json + OBJ + PNG), assembled the way features/MeshModels
places the parts (part centre minus the model's hold point). Checks the files the hub will load, not the source model.

  python3 tools/render_index.py <models folder> [--out folder] [--only id,id]
Approximation (software renderer), not Roblox.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import convert_mesh as cm  # noqa: E402


def main():
    args = sys.argv[1:]
    folder = pathlib.Path(args[0])
    out = pathlib.Path(args[args.index("--out") + 1]) if "--out" in args else folder
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    index = json.loads((folder / "index.json").read_text())
    for e in index["models"]:
        if only and e["id"] not in only:
            continue
        meshes, texes = [], []
        hold = np.array(e.get("hold", [0, 0, 0]), dtype=float)
        for p in e["parts"]:
            m = cm.meshes_from_obj(folder / p["mesh"])[0]
            m.pos = m.pos + np.array(p["center"]) - hold
            m.uv = np.c_[m.uv[:, 0], 1.0 - m.uv[:, 1]]  # OBJ v points up; the renderer samples images top-down like glTF
            meshes.append(m)
            texes.append(Image.open(folder / p["texture"]).convert("RGB") if p.get("texture") else Image.new("RGB", (8, 8), (200, 200, 200)))
        imgs = [cm.render_view(meshes, texes, 460, az, el) for az, el in [(38, 14), (90, 0), (160, 14)]]
        sheet = Image.new("RGB", (460 * 3, 460))
        for i, im in enumerate(imgs):
            sheet.paste(im, (i * 460, 0))
        out.mkdir(parents=True, exist_ok=True)
        sheet.save(out / f"{e['id']}_check.png")
        print(e["id"], len(e["parts"]), "parts", e["tris"], "tris")


if __name__ == "__main__":
    main()
