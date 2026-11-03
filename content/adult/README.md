# Adult content

Everything that may only appear at the Suggestive or Full content level lives here, and only here.

- SFW export presets exclude this whole folder, so a SFW build can't contain any of it.
- Every adult asset is made with its censored layer in the same source file. The censored export goes in `content/sfw/`.
- Nothing outside this folder and `data/` may reference a path in here. Scenes reach adult assets through the scene data, which falls back to the SFW version when the content level is lower or the build is SFW. `tools/lint_content.py` checks this in CI.
