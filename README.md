# Saikoro Bay

*A cozy, cheeky and sultry town-rebuilding game.*

A luck spirit has swallowed a fantasy-Japan beach town beneath the tide. You win it back one dice delve at a time.

## Two halves, one loop

| Above ground: the town | Below the tide: the delve |
| --- | --- |
| Rebuild the bay, house the people you rescue, and go on dates. | Dice-placement runs through the luck spirit's casino palace. |
| Makes your next delve luckier. | Brings back resources, landmarks and villagers. |

The two halves should feel like different games, and each one feeds the other.

## Status

Building the vertical slice. Milestone 0 (foundations) is in progress.

## Stack

- **Engine:** [Godot 4.6](https://godotengine.org/) (pinned to 4.6.x, standard build, not .NET), 2D, GL Compatibility renderer.
- **Language:** statically typed GDScript. Untyped declarations and unsafe access are errors, not warnings.
- **Git LFS** for large source art, audio, fonts and video (see `.gitattributes`). Git for Windows includes it; run `git lfs install` once per machine.

## Running it

Open the folder in the Godot 4.6 editor and press Play, or from a terminal:

```
godot --path .
```

## Checks

CI runs these on every pull request. To run them locally:

```
python3 tools/lint_sim.py                                   # sim/ stays seeded and headless
python3 tools/lint_content.py                               # adult assets only via the content system
godot --headless --path . --import                          # first run only
godot --headless --path . -s res://tools/check_scripts.gd   # every script compiles
godot --headless --path . -s res://addons/gut/gut_cmdln.gd  # tests (GUT)
```

Tests live in `tests/` and use [GUT](https://github.com/bitwes/Gut) (vendored in `addons/gut`, MIT). In the editor, the GUT panel runs them too.

## Builds

`export_presets.cfg` has Windows, Linux, macOS and Web presets, each in a full and a **SFW** variant. SFW presets add the `sfw` feature tag (content is capped at the SFW level) and leave out `content/adult/` entirely.

CI exports the full and SFW Windows builds on every pull request and push to `main`, checks the SFW pack contains nothing from `content/adult/` (`tools/check_pck.py`), and attaches both builds to the run for 14 days.

To export locally, install the Godot 4.6.3 export templates (Editor > Manage Export Templates), then use Project > Export or:

```
godot --headless --path . --export-release "Windows SFW" build/sfw/windows/SaikoroBay.exe
```

The `build/` folder holds a `.gdignore` so Godot never imports its own exports.

**itch.io:** the manual "Publish to itch.io" workflow pushes a commit's CI builds with butler to the `windows` and `windows-sfw` channels. It needs a `BUTLER_API_KEY` secret and an `ITCH_PROJECT` variable (for example `user/saikoro-bay`) in the repository's Actions settings.

## Repository layout

```
sim/            Game rules as plain classes with no scene or node references.
                Dice, delve, town economy, RNG. Runs headless for tests and the bot.
game/           Scenes, nodes and UI that present the sim to the player.
content/sfw/    Game data and assets that are safe for every build.
content/adult/  Adult-only assets. Excluded from SFW builds.
data/           Game data as JSON (villagers, perks, rooms...). Balancing is an edit here.
dialogue/       Dialogue and scene scripts.
tests/          Automated tests.
tools/          Scripts for CI, linting and the balance bot.
addons/         Third-party Godot plugins (GUT for tests).
.github/        PR and issue templates, labels, workflows.
```

## How work happens here

- `main` is always the source of truth. Nothing is pushed to it directly.
- Every change lands through a pull request, usually squash-merged.
- Issues are labeled by **type**, **area** and **priority** (see [`.github/labels.yml`](.github/labels.yml)).

## License

All rights reserved. The code, art, story and characters are proprietary; see [`LICENSE`](LICENSE). The repository is public to view, not to reuse.
