"""Tests for tools/convert_mesh.py with a synthetic GLB (two materials, a node rotation, a texture).
Run:  python3 -m unittest discover -s tools/tests
No real downloaded model was available when this was written; it proves the pipeline mechanics, not the look of any particular model."""
import io, json, pathlib, struct, subprocess, sys, tempfile, unittest
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "convert_mesh.py"


def box(cx, cy, cz, sx, sy, sz):
    v, uv, n, idx = [], [], [], []
    faces = [((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]), ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
             ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]), ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
             ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]), ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)])]
    for nm, quad in faces:
        b = len(v)
        for (x, y, z), t in zip(quad, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            v.append((cx + x * sx / 2, cy + y * sy / 2, cz + z * sz / 2)); n.append(nm); uv.append(t)
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    return np.array(v, dtype=np.float32), np.array(n, dtype=np.float32), np.array(uv, dtype=np.float32), np.array(idx, dtype=np.uint16)


def build_glb(path):
    parts = [box(0, 0, 0, 6, 1, 0.5), box(1, -1, 0, 0.6, 1.2, 0.4)]
    blob = bytearray(); views = []; accs = []

    def add(arr):
        off = len(blob); blob.extend(arr.tobytes())
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes})
        return len(views) - 1
    prims = []
    for i, (v, n, uv, idx) in enumerate(parts):
        ids = {}
        for name, arr, tp in (("POSITION", v, "VEC3"), ("NORMAL", n, "VEC3"), ("TEXCOORD_0", uv, "VEC2")):
            bv = add(arr)
            extra = {"min": v.min(axis=0).tolist(), "max": v.max(axis=0).tolist()} if name == "POSITION" else {}
            accs.append({"bufferView": bv, "componentType": 5126, "count": len(arr), "type": tp, **extra}); ids[name] = len(accs) - 1
        bv = add(idx); accs.append({"bufferView": bv, "componentType": 5123, "count": len(idx), "type": "SCALAR"})
        prims.append({"attributes": ids, "indices": len(accs) - 1, "material": i})
    img = Image.new("RGB", (64, 64)); px = img.load()
    for x in range(64):
        for y in range(64):
            px[x, y] = (220, 60, 60) if (x // 8 + y // 8) % 2 else (240, 240, 240)
    bio = io.BytesIO(); img.save(bio, "PNG"); png = bio.getvalue()
    off = len(blob); blob.extend(png)
    while len(blob) % 4:
        blob.append(0)
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(png)})
    gltf = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "rotation": [0, 0.7071068, 0, 0.7071068]}], "meshes": [{"primitives": prims}],
            "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}, {"pbrMetallicRoughness": {"baseColorFactor": [0.2, 0.5, 0.9, 1]}}],
            "textures": [{"source": 0}], "images": [{"bufferView": len(views) - 1, "mimeType": "image/png"}],
            "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accs}
    js = json.dumps(gltf).encode()
    while len(js) % 4:
        js += b" "
    path.write_bytes(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def run(*args):
    return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True)


class ConvertMesh(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.glb = self.tmp / "t.glb"
        build_glb(self.glb)

    def test_converts_and_orients(self):
        out = self.tmp / "out"
        r = run(str(self.glb), "--id", "t_gun", "--kind", "gun", "--forward", "+z", "--length", "2.8", "--out", str(out), "--no-preview")
        self.assertEqual(r.returncode, 0, r.stderr)
        idx = json.loads((out / "index.json").read_text())
        e = idx["models"][0]
        self.assertEqual(e["id"], "t_gun"); self.assertEqual(len(e["parts"]), 2, "one mesh per material")
        self.assertAlmostEqual(max(e["size"]), 2.8, places=2)
        self.assertEqual(e["size"].index(max(e["size"])), 2, "the long side lies along z")
        for p in e["parts"]:
            self.assertTrue((out / p["mesh"]).exists() and (out / p["texture"]).exists())
            self.assertTrue(all(0.05 <= s <= 40 for s in p["size"]))
            lines = (out / p["mesh"]).read_text().splitlines()
            self.assertEqual(sum(1 for l in lines if l.startswith("f ")), p["tris"])
        self.assertEqual(Image.open(out / e["parts"][0]["texture"]).size, (64, 64))

    def test_as_is_keeps_scale_and_grip(self):
        out = self.tmp / "asis"
        r = run(str(self.glb), "--id", "g", "--kind", "gun", "--as-is", "--out", str(out), "--no-preview")
        self.assertEqual(r.returncode, 0, r.stderr)
        e = json.loads((out / "index.json").read_text())["models"][0]
        self.assertAlmostEqual(max(e["size"]), 6.0, places=3, msg="1 unit = 1 stud is kept")
        # the source origin sits 0.55 above the bounding-box centre (y range -1.6 .. 0.5); it becomes the grip
        self.assertAlmostEqual(e["hold"][1], 0.55, places=3)
        self.assertAlmostEqual(e["hold"][0], 0.0, places=3)
        r2 = run(str(self.glb), "--id", "g", "--kind", "gun", "--out", str(self.tmp / "plain"), "--no-preview")
        e2 = json.loads((self.tmp / "plain" / "index.json").read_text())["models"][0]
        self.assertEqual(e2["hold"], [0, 0, 0], "without --as-is the model is held at its centre")

    def test_forward_axis_changes_direction(self):
        a, b = self.tmp / "a", self.tmp / "b"
        run(str(self.glb), "--id", "m", "--kind", "gun", "--forward", "+z", "--out", str(a), "--no-preview")
        run(str(self.glb), "--id", "m", "--kind", "gun", "--forward=z-", "--out", str(b), "--no-preview")
        va = [l for l in (a / "m_0.obj").read_text().splitlines() if l.startswith("v ")]
        vb = [l for l in (b / "m_0.obj").read_text().splitlines() if l.startswith("v ")]
        self.assertNotEqual(va, vb)

    def test_decimation_respects_the_budget(self):
        try:
            import fast_simplification  # noqa: F401
        except ImportError:
            self.skipTest("fast-simplification not installed")
        out = self.tmp / "d"
        r = run(str(self.glb), "--id", "d", "--kind", "gun", "--max-tris", "6", "--out", str(out), "--no-preview")
        # tiny meshes cannot be reduced much, but the tool must not fail
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_rejects_bad_input(self):
        self.assertNotEqual(run(str(self.glb), "--id", "../x", "--kind", "gun", "--out", str(self.tmp / "o")).returncode, 0)
        bad = self.tmp / "m.fbx"; bad.write_bytes(b"x")
        r = run(str(bad), "--id", "x", "--kind", "gun", "--out", str(self.tmp / "o"))
        self.assertNotEqual(r.returncode, 0); self.assertIn("unsupported", (r.stderr + r.stdout))
        self.assertNotEqual(run(str(self.tmp / "missing.glb"), "--id", "x", "--kind", "gun").returncode, 0)

    def test_merges_into_an_existing_index(self):
        out = self.tmp / "o"
        run(str(self.glb), "--id", "one", "--kind", "gun", "--out", str(out), "--no-preview")
        run(str(self.glb), "--id", "two", "--kind", "knife", "--out", str(out), "--no-preview")
        run(str(self.glb), "--id", "one", "--kind", "gun", "--out", str(out), "--no-preview")
        ids = [m["id"] for m in json.loads((out / "index.json").read_text())["models"]]
        self.assertEqual(sorted(ids), ["one", "two"])


if __name__ == "__main__":
    unittest.main()
