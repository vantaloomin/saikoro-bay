# Adult content

**This folder is local-only.** Everything in it except this README is gitignored, because the repo is public. The files live on the maintainer's PC with backups, and full (non-SFW) builds are only made there. A clone, CI or any other machine has an empty folder here, and the game plays every scene at SFW. The only tracked files are this README and `ci_canary/` (a placeholder CI uses to prove the SFW pack check works).

**SFW builds ship from CI only.** Godot's UID cache lists every file in the project, so a SFW export made on a machine that has adult files here would leak their file names into the SFW pack.

Everything that may only appear at the Suggestive or Full content level lives here, and only here.

- SFW export presets exclude this whole folder, so a SFW build can't contain any of it.
- Every adult asset is made with its censored layer in the same source file. The censored export goes in `content/sfw/`.
- Nothing outside this folder and `data/` may reference a path in here. Scenes reach adult assets through the scene data, which falls back to the SFW version when the content level is lower or the build is SFW. `tools/lint_content.py` checks this in CI.
