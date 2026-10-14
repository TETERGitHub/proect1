# Working rules for this repository (MM2 Hub)

Standing rules from the project owner. They apply to every session.

* **No cubic / block-built 3D models, ever.** Weapons, knives, costumes and accessories must be real meshes (imported from the owner's files)
  or, where a model is genuinely missing, shown honestly as a placeholder. Do not present models assembled from Part primitives as finished
  work. The built-in primitive models (`src/data/Models*.luau`) are legacy placeholders only; real meshes go through `tools/convert_mesh.py`
  and `features/MeshModels`.
* Never claim that something passed, rendered or ran when it did not. The offline renderers (`tools/ui_render.py`, `tools/model_render.py`)
  are approximations, not Roblox. Nothing has been verified in Roblox Studio or an executor unless the owner reports it.
* Keep the existing architecture; do not delete working functions or start a new project. Work on branch `claude/youthful-cray-l6ypwp`.
* No drones (removed on the owner's request; `git revert 7b56500` restores them only if the owner asks again). No features that harm, fling
  or kill real players, give hidden information or tamper with other clients. Customisation is local to the player's own client.
* Never commit secrets. Third-party meshes keep their licence and attribution (see `docs/CREDITS.md`); do not redistribute meshes whose licence
  forbids it; do not embed third-party scripts without a full review.
* Answer the owner in Russian. Report honestly what was tested, how, and what was not.
