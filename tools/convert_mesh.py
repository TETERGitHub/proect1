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


def srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


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


# rest centres of the R15 parts in root space for a 5.5-stud avatar (same numbers as src/data/Rig.luau)
RIG_REST = {
    "Head": (0, 1.9, 0), "UpperTorso": (0, 0.75, 0), "LowerTorso": (0, -0.35, 0),
    "RightUpperArm": (1.5, 0.9, 0), "RightLowerArm": (1.5, 0.1, 0), "RightHand": (1.5, -0.55, 0),
    "LeftUpperArm": (-1.5, 0.9, 0), "LeftLowerArm": (-1.5, 0.1, 0), "LeftHand": (-1.5, -0.55, 0),
    "RightUpperLeg": (0.5, -1.15, 0), "RightLowerLeg": (0.5, -2.0, 0), "RightFoot": (0.5, -2.75, 0),
    "LeftUpperLeg": (-0.5, -1.15, 0), "LeftLowerLeg": (-0.5, -2.0, 0), "LeftFoot": (-0.5, -2.75, 0),
}


def split_by_position(meshes):
    """--auto-bones: cut each mesh into R15 body parts by where its triangles are (for models without a skeleton or names).
    Positions are in the hub's space (front -Z, up +Y, 5.5 studs tall, centred). The arms are found from the model's own width so a
    wide or thin body still gets its arms; the legs are split at the crotch. Returns new meshes with .bone set."""
    allp = np.vstack([m.pos for m in meshes])
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    h = hi[1] - lo[1]
    out = []
    for m in meshes:
        cen = m.pos[m.faces].mean(axis=1)
        t = (cen[:, 1] - lo[1]) / h          # 0 feet .. 1 top
        x = cen[:, 0]
        # torso half-width at chest height: the body without the arms (the narrowest 60 % of points at 55-75 % height)
        band = allp[((allp[:, 1] - lo[1]) / h > 0.55) & ((allp[:, 1] - lo[1]) / h < 0.75)]
        torso_half = np.percentile(np.abs(band[:, 0]), 60) if len(band) else 0.6
        names = np.empty(len(cen), dtype=object)
        for i in range(len(cen)):
            ti, xi = t[i], x[i]
            side = "Right" if xi > 0 else "Left"   # facing -Z, the avatar's right is +X
            if ti > 0.82:
                names[i] = "Head"
            elif (abs(xi) > torso_half * 1.05 and ti > 0.33) or (abs(xi) > torso_half * 0.82 and 0.66 < ti <= 0.82):
                # the shoulder cap belongs to the arm, so it lifts with it instead of staying behind as a flap
                names[i] = side + ("UpperArm" if ti > 0.62 else "LowerArm" if ti > 0.47 else "Hand")
            elif ti > 0.58:
                names[i] = "UpperTorso"
            elif ti > 0.47:
                names[i] = "LowerTorso"
            else:
                names[i] = side + ("UpperLeg" if ti > 0.27 else "LowerLeg" if ti > 0.07 else "Foot")
        for bone in sorted(set(names)):
            sel = np.where(names == bone)[0]
            used = np.unique(m.faces[sel])
            remap = -np.ones(len(m.pos), dtype=np.int64); remap[used] = np.arange(len(used))
            n = Mesh(m.name + "_" + bone)
            n.pos, n.uv = m.pos[used], m.uv[used]
            n.nrm = m.nrm[used] if len(m.nrm) == len(m.pos) else m.nrm
            n.faces = remap[m.faces[sel]]
            n.image, n.color, n.bone = m.image, m.color, bone
            out.append(n)
    return out


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


def meshes_from_gltf(path, by_bone=False, skip=None, anim=None):
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
                # glTF colour factors are LINEAR; textures and Roblox colours are sRGB
                m.color = tuple(int(round(srgb(max(0, min(1, c))) * 255)) for c in f[:3])
                tex = pbr.get("baseColorTexture")
                if tex is not None:
                    src = gltf["textures"][tex["index"]].get("source")
                    if src is not None:
                        if src not in images:
                            images[src] = load_image(gltf, buffers, base, src)
                        m.image = images[src]
            out[key] = m
        return out[key]

    # optional pose from an animation's first keyframe (some models rest "exploded" and are assembled by their animation)
    if anim is not None and gltf.get("animations"):
        an = gltf["animations"][min(anim, len(gltf["animations"]) - 1)]
        for ch in an["channels"]:
            tgt = ch["target"]
            if "node" not in tgt or tgt.get("path") not in ("translation", "rotation", "scale"):
                continue
            smp = an["samplers"][ch["sampler"]]
            vals = accessor(gltf, buffers, smp["output"])
            node = gltf["nodes"][tgt["node"]]
            node.pop("matrix", None)
            node[tgt["path"]] = [float(v) for v in vals[0]]
    # world matrices of every node first: skinned meshes are posed by their joints, not by their own node
    world = {}

    def walk(ni, parent):
        world[ni] = parent @ node_matrix(gltf["nodes"][ni])
        for c in gltf["nodes"][ni].get("children", []):
            walk(c, world[ni])

    scene0 = gltf["scenes"][gltf.get("scene", 0)] if gltf.get("scenes") else {"nodes": list(range(len(gltf["nodes"])))}
    for n in scene0["nodes"]:
        walk(n, np.eye(4))

    def skin_matrices(node):
        sk = gltf["skins"][node["skin"]]
        joints = sk["joints"]
        ibm = accessor(gltf, buffers, sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1) if "inverseBindMatrices" in sk else np.tile(np.eye(4), (len(joints), 1, 1))
        return np.stack([world.get(j, np.eye(4)) @ ibm[k] for k, j in enumerate(joints)])

    def visit(ni, parent, pbone=None):
        node = gltf["nodes"][ni]
        M = parent @ node_matrix(node)
        bone = (bone_of(node.get("name")) or pbone) if by_bone else None
        if skip and re.search(skip, node.get("name", ""), re.I):
            print("  skipped node %r (and its children)" % node.get("name"))
            return
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
                if "skin" in node and "JOINTS_0" in attrs and "WEIGHTS_0" in attrs:
                    # rest pose of a skinned mesh: sum of weight * (joint world @ inverse bind) per vertex
                    J = accessor(gltf, buffers, attrs["JOINTS_0"]).astype(np.int64)
                    Wt = accessor(gltf, buffers, attrs["WEIGHTS_0"])
                    Wt = Wt / np.maximum(Wt.sum(axis=1, keepdims=True), 1e-9)
                    SM = skin_matrices(node)
                    VM = np.einsum("vk,vkij->vij", Wt, SM[J])  # per-vertex blended matrix
                    P = np.einsum("vij,vj->vi", VM, np.c_[pos, np.ones(len(pos))])[:, :3]
                    if nrm is None:
                        nn = np.zeros_like(P)
                    else:
                        nn = np.einsum("vij,vj->vi", VM[:, :3, :3], nrm)
                        nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
                else:
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
                    # OBJ texture v points up; internally (as in glTF) v counts from the top of the image
                    P.append(pos[vi]); U.append([uvs[ti][0], 1.0 - uvs[ti][1]] if ti >= 0 else [0.5, 0.5]); N.append(nrms[ni] if ni >= 0 else [0, 0, 0])
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


def render_view(meshes, texes, size, az, el):
    """Textured, smooth-shaded software render (orthographic) for previews; an approximation of how the mesh looks, not Roblox."""
    a, e = math.radians(az), math.radians(el)
    Ry = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(e), -math.sin(e)], [0, math.sin(e), math.cos(e)]])
    R = Rx @ Ry
    allp = np.vstack([m.pos for m in meshes]) @ R.T
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    scale = 0.86 * size / max(hi[0] - lo[0], hi[1] - lo[1], 1e-6)
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    img = np.zeros((size, size, 3))
    for i in range(size):
        t = i / size
        img[i, :, :] = np.array([44, 48, 60]) * (1 - t) + np.array([20, 22, 28]) * t
    zbuf = np.full((size, size), -1e9)
    light = np.array([-0.45, 0.75, 0.5]); light /= np.linalg.norm(light)
    for m, tex in zip(meshes, texes):
        P = m.pos @ R.T
        N = m.nrm @ R.T if len(m.nrm) and np.abs(m.nrm).sum() > 0 else None
        sx = (P[:, 0] - cx) * scale + size / 2
        sy = size / 2 - (P[:, 1] - cy) * scale
        tarr = np.asarray(tex, dtype=np.float64)
        th, tw = tarr.shape[:2]
        for f in m.faces:
            x0, x1, x2 = sx[f]; y0, y1, y2 = sy[f]
            minx, maxx = int(max(0, math.floor(min(x0, x1, x2)))), int(min(size - 1, math.ceil(max(x0, x1, x2))))
            miny, maxy = int(max(0, math.floor(min(y0, y1, y2)))), int(min(size - 1, math.ceil(max(y0, y1, y2))))
            if minx > maxx or miny > maxy:
                continue
            den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(den) < 1e-12:
                continue
            gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
            w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
            w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            z = w0 * P[f[0], 2] + w1 * P[f[1], 2] + w2 * P[f[2], 2]
            region = zbuf[miny:maxy + 1, minx:maxx + 1]
            vis = inside & (z > region)
            if not vis.any():
                continue
            uv = m.uv[f]
            u = (w0 * uv[0, 0] + w1 * uv[1, 0] + w2 * uv[2, 0])[vis] % 1.0
            v = (w0 * uv[0, 1] + w1 * uv[1, 1] + w2 * uv[2, 1])[vis] % 1.0
            col = tarr[(v * (th - 1)).astype(int), (u * (tw - 1)).astype(int), :3]
            if N is not None:
                n = (w0[..., None] * N[f[0]] + w1[..., None] * N[f[1]] + w2[..., None] * N[f[2]])[vis]
            else:
                fn = np.cross(P[f[1]] - P[f[0]], P[f[2]] - P[f[0]]); fn /= max(np.linalg.norm(fn), 1e-9)
                n = np.tile(fn, (int(vis.sum()), 1))
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            if np.mean(n[:, 2]) < 0:
                n = -n  # back faces of thin parts are lit like front faces
            d = np.clip(n @ light, 0, 1)
            spec = np.clip(n @ (light + np.array([0, 0, 1])) / np.linalg.norm(light + np.array([0, 0, 1])), 0, 1) ** 24
            shade = col * (0.32 + 0.78 * d[:, None]) + 90 * spec[:, None]
            sub = img[miny:maxy + 1, minx:maxx + 1]
            sub[vis] = shade
            region[vis] = z[vis]
    return Image.fromarray(np.clip(img, 0, 255).astype("uint8"))


def preview(meshes, texes, path, views):
    placed = []
    for m in meshes:
        c = Mesh(m.name)
        c.pos, c.uv, c.nrm, c.faces = m.pos + getattr(m, "centre", 0), m.uv, m.nrm, m.faces
        placed.append(c)
    imgs = [render_view(placed, texes, 460, az, el) for az, el in views]
    sheet = Image.new("RGB", (460 * len(imgs), 460))
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
    ap.add_argument("--skip", default="", help="regular expression: nodes whose name matches are left out with their children "
                    "(stands, signs, extra copies in a showcase scene)")
    ap.add_argument("--anim-pose", type=int, default=None, help="pose the model as in the first keyframe of animation N (0 = first)")
    ap.add_argument("--auto-bones", action="store_true", help="costume only: cut the model into R15 body parts by position, so every "
                    "part follows its limb (arms raise with a held knife or gun, legs walk)")
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
    meshes = meshes_from_gltf(src, by_bone, a.skip or None, a.anim_pose) if ext in (".glb", ".gltf") else meshes_from_obj(src) if ext == ".obj" else None
    if meshes is None:
        raise SystemExit("unsupported format %s (use .glb, .gltf or .obj; for .fbx / .blend export glTF or OBJ from Blender first)" % ext)
    meshes = [m for m in meshes if len(m.faces)]
    if not meshes:
        raise SystemExit("the file contains no triangles")
    total_in = sum(len(m.faces) for m in meshes)
    orient(meshes, a.forward, a.up)
    length = a.length or {"gun": 2.8, "knife": 3.0}.get(a.kind, 5.5 if a.group == "costume" else 3.0)
    size, k, origin = normalize(meshes, length, keep_scale=a.as_is)
    if a.auto_bones:
        if a.kind != "char" or a.group != "costume":
            raise SystemExit("--auto-bones is for costumes (--kind char --group costume)")
        meshes = split_by_position(meshes)
        print("  cut into body parts: " + ", ".join(sorted({m.bone for m in meshes})))
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
        m.centre = centre  # the part is written centred; the preview puts it back where it belongs
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
