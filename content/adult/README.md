# Adult content

Everything that may only appear at the Suggestive or Full content level lives here, and only here.

- SFW export presets exclude this whole folder, so a SFW build can't contain any of it.
- Every adult asset is made with its censored layer in the same source file. The censored export goes in `content/sfw/`.
- Nothing outside this folder and `data/` may reference a path in here. Scenes reach adult assets through the scene data, which falls back to the SFW version when the content level is lower or the build is SFW. `tools/lint_content.py` checks this in CI.
- Ship SFW builds from CI only. Godot's UID and script class caches list every file in the project, so a SFW export made from a tree that still has this folder leaks the adult file names into the pack even though their contents are excluded. CI deletes the folder before the SFW exports, then `tools/check_pck.py` checks every SFW preset's pack.
- `ci_canary/` holds a stand-in adult image and scene. CI checks that the full pack has them, which proves the SFW check can see adult files at all. Leave it in place.
