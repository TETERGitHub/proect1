# Importing real 3D models (meshes)

The built-in primitive shapes are placeholders. Real models come from files **you** download (for example from Sketchfab, a Blender
export or your own work) and convert with `tools/convert_mesh.py`. The hub never downloads models and ships none of its own; check the
licence of every model before use (most free models need attribution: put it in `--credit`, it is kept in `index.json` and shown as a tooltip).

## Steps

1. Download the model as **glTF/GLB** (best) or OBJ. From Blender: *File > Export > glTF 2.0 (.glb)*. FBX/BLEND: export glTF or OBJ first.
2. Convert:

   ```
   python3 tools/convert_mesh.py awp.glb --id awp --name "AWP" --kind gun --forward=-z \
       --credit "Title by Author, Sketchfab, CC BY 4.0"
   python3 tools/convert_mesh.py katana.glb --id katana --kind knife --forward=-z
   python3 tools/convert_mesh.py tung.glb --id tung --kind char --group costume --forward +z --length 5.5
   python3 tools/convert_mesh.py halo.glb --id halo --kind char --group accessory --slot head
   # models made with docs/PROMPT_VS_MODELS.md (1 unit = 1 stud, origin at the grip): keep both with --as-is
   python3 tools/convert_mesh.py gun_pistol.glb --id gun_pistol --name "Pistol" --kind gun --as-is
   python3 tools/convert_mesh.py knife_katana.glb --id knife_katana --name "Katana" --kind knife --as-is
   ```

   (write negative axes as `--forward=-z` or `--forward z-`)
   `--forward` is the axis of the SOURCE model that points to the barrel / blade tip / the character's front (try `+x`, `-x`, `+z`... until the
   preview picture shows the right direction); `--up` defaults to `+y`. Output goes to `dist/imports/`: one OBJ + PNG per material, `index.json`
   and `<id>_preview.png` (a rough check of size and direction, not a Roblox render).
3. Copy the contents of `dist/imports/` into `MM2Hub/models/` in your executor's workspace folder.
4. In the hub open *Custom gun / knife / character*, press **Rescan imports**, pick the card under "Your imported models (real meshes)", then Apply.

## What the converter does

Applies node transforms (skins and animations are ignored, the bind pose is used), splits per material (a MeshPart holds one texture), orients
the model (-Z forward, +Y up), scales the longest side to `--length` studs, centres it, decimates above `--max-tris` (default 15000 per mesh; UVs of
new vertices come from the nearest original vertex, so seams may look slightly off) and writes OBJ/PNG. Needs `numpy`, `Pillow` and, only for
decimation, `fast-simplification` (`pip install fast-simplification`).

## Limits and what is NOT verified

* Local files are loaded with `getcustomasset`; the hub then sets `MeshPart.MeshId`/`TextureID`. Both depend on the executor (not verified here).
  Alternatively upload the mesh yourself and put its asset id into `index.json` (`"assetId"`, `"textureId"` per part).
* Roblox limits uploaded meshes to roughly 10k triangles; the hub accepts up to 60k per part / 120k per model and at most 8 parts.
* Textured meshes keep their own colours; the colour pickers do not tint them. The light/sparkle effects and scale/offset still apply.
* Imported costumes are static (welded to the root part), like the built-in ones.
* `index.json` entries are validated (id, kind, file names without paths, sizes, triangle budget); a bad entry is reported and skipped, and a model
  that fails to load leaves no temporary objects behind.
* The converter was tested with a synthetic GLB only (see `tests`); no real downloaded model was available in the build environment.
