#!/usr/bin/env python3
"""Convert a downloaded 3D model (.glb / .gltf / .obj) into files the hub can load as REAL meshes.

The hub draws imported models as MeshParts with MeshId = getcustomasset("MM2Hub/models/<file>.obj") and the texture next to it, or with a
Roblox asset id you uploaded yourself. This tool prepares those files and an entry for MM2Hub/models/index.json:

    python3 tools/convert_mesh.py ~/Downloads/awp.glb --id awp --name "AWP" --kind gun --forward=-z \\
        --credit "Artic Warfare Police (AWP) by Franck-Allen_Nguyen, Sketchfab, CC BY 4.0 (check the licence yourself)"

What it does: reads the model (node transforms applied; skins/animations are ignored, the bind pose is used), splits it per material
(each material becomes one mesh + one texture, because a MeshPart holds one texture), orients it (weapon barrel / blade tip toward -Z,
up = +Y), scales the longest side to --length studs, centres it, decimates it when it is above --max-tris (quadric decimation; UVs of new
vertices are taken from the nearest original vertex, so seams can look slightly off), writes OBJ + PNG and merges an entry into index.json.
It does NOT download anything, does not touch licences, and never runs code from the model file.

Environment limits to know: getcustomasset-based MeshIds depend on the executor (unverified here); Roblox uploads limit meshes to
about 10k triangles each; recolouring does not tint textured meshes.
"""
import argparse, base64, io, json, math, os, pathlib, re, struct, sys
import numpy as np
from PIL import Image

AXES = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0), "+z": (0, 0, 1), "-z": (0, 0, -1)}
COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
NPDT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


class Mesh:
    """One material's worth of triangles: positions (N,3), uvs (N,2), normals (N,3) per VERTEX, faces (M,3), a PIL texture or colour."""
    def __init__(self, name):
        self.name = name
        self.pos = np.zeros((0, 3)); self.uv = np.zeros((0, 2)); self.nrm = np.zeros((0, 3)); self.faces = np.zeros((0, 3), dtype=np.int64)
        self.image = None
        self.color = (255, 255, 255)
        self.bone = None


# Roblox R15 body parts: a costume whose objects are named after them (Blender object = glTF node name, e.g. "LeftUpperArm" or
# "RightHand_Bat") is kept split per part, so every piece follows its own limb in the hub.
R15 = ["Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
       "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]


def bone_of(name):
    """R15 part a node name belongs to (longest prefix match, case-insensitive), or None."""
    n = (name or "").lower()
    best = None
    for b in R15:
        if n.startswith(b.lower()) and (best is None or len(b) > len(best)):
            best = b
    return best


# ---------------------------------------------------------------------------------------------------------- glTF
def read_gltf(path):
    path = pathlib.Path(path)
    data = path.read_bytes()
    bins = []
    if data[:4] == b"glTF":
        ver, length = struct.unpack_from("<II", data, 4)
        off, js = 12, None
        while off < len(data):
            clen, ctype = struct.unpack_from("<II", data, off)
            chunk = data[off + 8: off + 8 + clen]
            if ctype == 0x4E4F534A:
                js = json.loads(chunk.decode("utf-8"))
            elif ctype == 0x004E4942:
                bins.append(chunk)
            off += 8 + clen + (-clen % 4)
        if js is None:
            raise ValueError("GLB has no JSON chunk")
        gltf = js
    else:
        gltf = json.loads(data.decode("utf-8"))
    buffers = []
    for i, b in enumerate(gltf.get("buffers", [])):
        uri = b.get("uri")
        if uri is None:
            buffers.append(bins[0] if bins else b"")
        elif uri.startswith("data:"):
            buffers.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            buffers.append((path.parent / uri.replace("%20", " ")).read_bytes())
    return gltf, buffers


def accessor(gltf, buffers, index):
    a = gltf["accessors"][index]
    n, nc = a["count"], NCOMP[a["type"]]
    dtype = NPDT[a["componentType"]]
    if "bufferView" not in a:
        return np.zeros((n, nc), dtype=np.float64)
    bv = gltf["bufferViews"][a["bufferView"]]
    buf = buffers[bv["buffer"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    esize = np.dtype(dtype).itemsize * nc
    stride = bv.get("byteStride") or esize
    if stride == esize:
        arr = np.frombuffer(buf, dtype=dtype, count=n * nc, offset=start).reshape(n, nc)
    else:
        arr = np.zeros((n, nc), dtype=dtype)
        for i in range(n):
            arr[i] = np.frombuffer(buf, dtype=dtype, count=nc, offset=start + i * stride)
    arr = arr.astype(np.float64)
    if a.get("normalized"):
        arr /= {5120: 127.0, 5121: 255.0, 5122: 32767.0, 5123: 65535.0}.get(a["componentType"], 1.0)
    return arr


def load_image(gltf, buffers, base, index):
    img = gltf["images"][index]
    if "bufferView" in img:
        bv = gltf["bufferViews"][img["bufferView"]]
        raw = buffers[bv["buffer"]][bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    elif img["uri"].startswith("data:"):
        raw = base64.b64decode(img["uri"].split(",", 1)[1])
    else:
        raw = (base / img["uri"].replace("%20", " ")).read_bytes()
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), dtype=np.float64)
    q = node.get("rotation", [0, 0, 0, 1])
    s = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    x, y, z, w = q
    R = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    M = np.eye(4)
    M[:3, :3] = R * s[None, :]
    M[:3, 3] = t
    return M


def meshes_from_gltf(path, by_bone=False):
    gltf, buffers = read_gltf(path)
    base = pathlib.Path(path).parent
    mats = gltf.get("materials", [])
    out = {}  # (bone, material index) -> Mesh
    images = {}

    def material_mesh(mi, bone=None):
        key = (bone, mi)
        if key not in out:
            m = Mesh("mat%d" % (mi if mi is not None else 0) if bone is None else "%s_mat%d" % (bone, mi if mi is not None else 0))
            m.bone = bone
            if mi is not None and mi < len(mats):
                pbr = mats[mi].get("pbrMetallicRoughness", {})
                f = pbr.get("baseColorFactor", [1, 1, 1, 1])
                m.color = tuple(int(round(max(0, min(1, c)) * 255)) for c in f[:3])
                tex = pbr.get("baseColorTexture")
                if tex is not None:
                    src = gltf["textures"][tex["index"]].get("source")
                    if src is not None:
                        if src not in images:
                            images[src] = load_image(gltf, buffers, base, src)
                        m.image = images[src]
            out[key] = m
        return out[key]

    def visit(ni, parent, pbone=None):
        node = gltf["nodes"][ni]
        M = parent @ node_matrix(node)
        bone = (bone_of(node.get("name")) or pbone) if by_bone else None
        if "mesh" in node:
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                if prim.get("mode", 4) != 4:
                    print("  skipped a non-triangle primitive (mode %s)" % prim.get("mode"))
                    continue
                attrs = prim["attributes"]
                pos = accessor(gltf, buffers, attrs["POSITION"])
                nrm = accessor(gltf, buffers, attrs["NORMAL"]) if "NORMAL" in attrs else None
                uv = accessor(gltf, buffers, attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else np.zeros((len(pos), 2))
                idx = accessor(gltf, buffers, prim["indices"]).astype(np.int64).reshape(-1) if "indices" in prim else np.arange(len(pos))
                P = (np.c_[pos, np.ones(len(pos))] @ M.T)[:, :3]
                if nrm is None:
                    nn = np.zeros_like(P)
                else:
                    nn = nrm @ np.linalg.inv(M[:3, :3]).T
                    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
                m = material_mesh(prim.get("material"), bone)
                off = len(m.pos)
                m.pos = np.vstack([m.pos, P]); m.nrm = np.vstack([m.nrm, nn]); m.uv = np.vstack([m.uv, uv[:, :2]])
                m.faces = np.vstack([m.faces, idx.reshape(-1, 3) + off])
        for c in node.get("children", []):
            visit(c, M, bone)

    scene = gltf["scenes"][gltf.get("scene", 0)] if gltf.get("scenes") else {"nodes": list(range(len(gltf["nodes"])))}
    for n in scene["nodes"]:
        visit(n, np.eye(4))
    return list(out.values())


# ------------------------------------------------------------------------------------------------------------ obj
def meshes_from_obj(path):
    path = pathlib.Path(path)
    pos, uvs, nrms, faces = [], [], [], []
    m = Mesh(path.stem)
    verts = {}
    P, U, N, F = [], [], [], []
    for line in path.read_text(errors="ignore").splitlines():
        if line.startswith("v "):
            pos.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            uvs.append([float(x) for x in line.split()[1:3]])
        elif line.startswith("vn "):
            nrms.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("f "):
            ids = []
            for tok in line.split()[1:]:
                a = tok.split("/")
                vi = int(a[0]); vi = vi - 1 if vi > 0 else len(pos) + vi
                ti = (int(a[1]) - 1 if int(a[1]) > 0 else len(uvs) + int(a[1])) if len(a) > 1 and a[1] else -1
                ni = (int(a[2]) - 1 if int(a[2]) > 0 else len(nrms) + int(a[2])) if len(a) > 2 and a[2] else -1
                key = (vi, ti, ni)
                if key not in verts:
                    verts[key] = len(P)
                    P.append(pos[vi]); U.append(uvs[ti] if ti >= 0 else [0.5, 0.5]); N.append(nrms[ni] if ni >= 0 else [0, 0, 0])
                ids.append(verts[key])
            for k in range(1, len(ids) - 1):
                F.append([ids[0], ids[k], ids[k + 1]])
    m.pos, m.uv, m.nrm, m.faces = np.array(P), np.array(U), np.array(N), np.array(F, dtype=np.int64)
    # a texture with the same name next to the file, when present
    for ext in (".png", ".jpg", ".jpeg"):
        t = path.with_suffix(ext)
        if t.exists():
            m.image = Image.open(t).convert("RGBA")
            break
    return [m]


# ----------------------------------------------------------------------------------------------- transform + decimate
def orient(meshes, forward, up):
    """Rotate so `forward` becomes -Z and `up` becomes +Y (a proper rotation, right-handed)."""
    f = np.array(AXES[forward], dtype=float); u = np.array(AXES[up], dtype=float)
    # target basis: z_new = -forward, y_new = up, x_new = y x z
    z = -f
    y = u
    x = np.cross(y, z)
    if np.linalg.norm(x) < 1e-6:
        raise SystemExit("--forward and --up must be different axes")
    R = np.stack([x, y, z])  # rows: new axes expressed in old coordinates
    for m in meshes:
        m.pos = m.pos @ R.T
        if len(m.nrm):
            m.nrm = m.nrm @ R.T


def bounds(meshes):
    allp = np.vstack([m.pos for m in meshes])
    return allp.min(axis=0), allp.max(axis=0)


def normalize(meshes, length, keep_scale=False):
    """Centres the model on its bounding box and scales the longest side to `length` (or keeps the scale).
    Returns (size, k, origin): origin is where the SOURCE origin (0,0,0) ended up, i.e. the grip when the file was made that way."""
    lo, hi = bounds(meshes)
    size = hi - lo
    k = 1.0 if keep_scale else length / max(size)
    centre = (lo + hi) / 2
    for m in meshes:
        m.pos = (m.pos - centre) * k
    lo, hi = (lo - centre) * k, (hi - centre) * k
    return (hi - lo), k, -centre * k


def decimate(m, target):
    n = len(m.faces)
    if n <= target:
        return m
    try:
        import fast_simplification
    except ImportError:
        raise SystemExit("this mesh has %d triangles (limit %d); install the decimator with:  pip install fast-simplification" % (n, target))
    red = 1.0 - target / n
    pts, faces = fast_simplification.simplify(m.pos.astype(np.float32), m.faces.astype(np.int32), target_reduction=red)
    pts = pts.astype(np.float64)
    # nearest original vertex for UV / normal (brute force in chunks)
    uv = np.zeros((len(pts), 2)); nr = np.zeros((len(pts), 3))
    for i in range(0, len(pts), 512):
        d = ((pts[i:i + 512, None, :] - m.pos[None, :, :]) ** 2).sum(axis=2)
        j = d.argmin(axis=1)
        uv[i:i + 512], nr[i:i + 512] = m.uv[j], m.nrm[j]
    out = Mesh(m.name)
    out.pos, out.uv, out.nrm, out.faces, out.image, out.color = pts, uv, nr, faces.astype(np.int64), m.image, m.color
    out.bone = m.bone
    return out


def write_obj(m, path):
    lines = ["# written by tools/convert_mesh.py", "o " + m.name]
    for p in m.pos:
        lines.append("v %.5f %.5f %.5f" % tuple(p))
    for t in m.uv:
        lines.append("vt %.5f %.5f" % (t[0] % 1.0 if False else t[0], 1.0 - t[1]))
    have_n = len(m.nrm) and np.abs(m.nrm).sum() > 0
    if have_n:
        for n in m.nrm:
            lines.append("vn %.4f %.4f %.4f" % tuple(n))
    for f in m.faces:
        a, b, c = (int(x) + 1 for x in f)
        if have_n:
            lines.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % (a, a, a, b, b, b, c, c, c))
        else:
            lines.append("f %d/%d %d/%d %d/%d" % (a, a, b, b, c, c))
    pathlib.Path(path).write_text("\n".join(lines) + "\n")


def texture_for(m, maxpx):
    if m.image is not None:
        img = m.image.copy()
        if max(img.size) > maxpx:
            img.thumbnail((maxpx, maxpx), Image.LANCZOS)
        if m.color != (255, 255, 255):
            arr = np.asarray(img, dtype=np.float64)
            arr[:, :, :3] *= np.array(m.color) / 255.0
            img = Image.fromarray(arr.astype("uint8"), "RGBA")
        return img.convert("RGB")
    return Image.new("RGB", (8, 8), m.color)


def sample_color(m, tex):
    """average colour per triangle for the preview"""
    w, h = tex.size
    arr = np.asarray(tex, dtype=np.float64)
    cu = m.uv[m.faces].mean(axis=1)
    x = np.clip((cu[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    y = np.clip((cu[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    return arr[y, x]


def preview(meshes, texes, path, views):
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    import model_render as mr
    tris, pid = [], 0
    for m, tex in zip(meshes, texes):
        cols = sample_color(m, tex)
        for f, c in zip(m.faces, cols):
            tris.append((m.pos[f], pid, np.array(c), False, False, 1.0))
        pid += 1
    imgs = [mr.raster(tris, 460, az, el) for az, el in views]
    from PIL import Image as I
    sheet = I.new("RGB", (460 * len(imgs), 460))
    for i, im in enumerate(imgs):
        sheet.paste(im, (i * 460, 0))
    sheet.save(path)


def axis_arg(text):
    """+z, -z, z+, z-, or plain z (= +z). Write negative axes as --forward=-z (a bare "-z" looks like an option to the shell parser) or as z-."""
    t = text.strip().lower()
    if len(t) == 2 and t[1] in "+-" and t[0] in "xyz":
        t = t[1] + t[0]
    if len(t) == 1 and t in "xyz":
        t = "+" + t
    if t not in AXES:
        raise argparse.ArgumentTypeError("axis must be one of +x -x +y -y +z -z (or x- z+ ...)")
    return t


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("--id", required=True, help="short id: letters, digits, underscore (max 24)")
    ap.add_argument("--name", default="")
    ap.add_argument("--kind", choices=["gun", "knife", "char"], required=True)
    ap.add_argument("--group", choices=["costume", "accessory"], default="costume", help="char only")
    ap.add_argument("--slot", choices=["head", "back", "aura"], default="head", help="char accessories only")
    ap.add_argument("--forward", default="-z", type=axis_arg, help="axis of the SOURCE model that points to the barrel / blade tip / the character's front")
    ap.add_argument("--up", default="+y", type=axis_arg, help="axis of the SOURCE model that points up")
    ap.add_argument("--length", type=float, default=0, help="longest side in studs (default: gun 2.8, knife 3.0, costume 5.5, accessory 3.0)")
    ap.add_argument("--as-is", action="store_true", help="keep the file's scale (1 unit = 1 stud) and use its origin as the grip / root point "
                    "(for models exported by docs/PROMPT_VS_MODELS.md); without it the model is scaled to --length and held at its centre")
    ap.add_argument("--max-tris", type=int, default=15000, help="triangle budget per mesh")
    ap.add_argument("--max-texture", type=int, default=1024)
    ap.add_argument("--credit", default="", help="author / title / licence text kept next to the model")
    ap.add_argument("--out", default=str(pathlib.Path("dist") / "imports"), help="output folder (copy its contents to MM2Hub/models/)")
    ap.add_argument("--no-preview", action="store_true")
    a = ap.parse_args()
    if not re.match(r"^[A-Za-z0-9_]{1,24}$", a.id):
        raise SystemExit("--id must be 1-24 letters, digits or underscores")
    src = pathlib.Path(a.source)
    if not src.exists():
        raise SystemExit("no such file: %s" % src)
    ext = src.suffix.lower()
    by_bone = a.kind == "char" and a.group == "costume"
    meshes = meshes_from_gltf(src, by_bone) if ext in (".glb", ".gltf") else meshes_from_obj(src) if ext == ".obj" else None
    if meshes is None:
        raise SystemExit("unsupported format %s (use .glb, .gltf or .obj; for .fbx / .blend export glTF or OBJ from Blender first)" % ext)
    meshes = [m for m in meshes if len(m.faces)]
    if not meshes:
        raise SystemExit("the file contains no triangles")
    total_in = sum(len(m.faces) for m in meshes)
    orient(meshes, a.forward, a.up)
    length = a.length or {"gun": 2.8, "knife": 3.0}.get(a.kind, 5.5 if a.group == "costume" else 3.0)
    size, k, origin = normalize(meshes, length, keep_scale=a.as_is)
    # split the budget between materials in proportion to their size
    budget = a.max_tris
    out_meshes = []
    for m in meshes:
        floor = min(500, budget // len(meshes))  # a small part keeps some detail, but many parts must still fit the budget
        share = max(floor, int(budget * len(m.faces) / total_in)) if len(meshes) > 1 else budget
        out_meshes.append(decimate(m, share))
    outdir = pathlib.Path(a.out)
    outdir.mkdir(parents=True, exist_ok=True)
    parts, texes = [], []
    for i, m in enumerate(out_meshes):
        lo, hi = m.pos.min(axis=0), m.pos.max(axis=0)
        centre, psize = (lo + hi) / 2, hi - lo
        m.pos = m.pos - centre
        base = "%s_%d" % (a.id, i)
        write_obj(m, outdir / (base + ".obj"))
        tex = texture_for(m, a.max_texture)
        tex.save(outdir / (base + ".png"))
        texes.append(tex)
        part = {"mesh": base + ".obj", "texture": base + ".png", "center": [round(float(c), 4) for c in centre], "size": [round(max(float(s), 0.05), 4) for s in psize], "tris": int(len(m.faces))}
        if m.bone:
            part["bone"] = m.bone
        parts.append(part)
    entry = {
        "id": a.id, "name": a.name or a.id, "kind": a.kind, "parts": parts, "size": [round(float(s), 3) for s in size],
        "tris": int(sum(p["tris"] for p in parts)), "credit": a.credit,
        "hold": [round(float(c), 4) for c in origin] if a.as_is else [0, 0, 0],
    }
    if a.kind == "char":
        entry["group"] = a.group
        if a.group == "accessory":
            entry["slot"] = a.slot
    idx_path = outdir / "index.json"
    index = {"version": 1, "models": []}
    if idx_path.exists():
        try:
            index = json.loads(idx_path.read_text())
        except Exception:
            pass
    index["models"] = [e for e in index.get("models", []) if e.get("id") != a.id] + [entry]
    idx_path.write_text(json.dumps(index, indent=1))
    if not a.no_preview:
        preview(out_meshes, texes, outdir / (a.id + "_preview.png"), [(38, 14), (90, 0), (160, 14)])
    print("wrote %d mesh(es), %d -> %d triangles, size %s studs into %s" % (len(parts), total_in, entry["tris"], entry["size"], outdir))
    print("copy the folder's contents (index.json, *.obj, *.png) to MM2Hub/models/ in your executor's workspace.")


if __name__ == "__main__":
    main()
