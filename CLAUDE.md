# CLAUDE.md

Context and working rules for Claude when working in this repository.

## The game

**Saikoro Bay** is a cozy, cheeky and sultry town-rebuilding game. The player wins back a sunken fantasy-Japan beach town from a luck spirit, one dice delve at a time.

The game has two halves that should feel like different games:

- **The town (above ground).** Rebuild the bay, house rescued villagers, and go on dates. Cozy pacing, relationship building, light management.
- **The delve (below the tide).** Dice-placement runs through the luck spirit's casino palace. Roguelite structure, risk and reward, short sessions.

Each half feeds the other. Delves bring back resources, landmarks and villagers. The town makes the next delve luckier (better dice, rerolls, perks).

### Tone

Cozy first, with a cheeky and sultry edge. Flirty and suggestive, never crude. The luck spirit is a rival with charm, not a horror villain. Japanese seaside-town flavour (festivals, shrines, onsen, pachinko glitter) filtered through fantasy.

*Saikoro* (サイコロ) means "dice".

## Stack

Not chosen yet. When the engine is picked, update this section with:

- Engine and version
- How to run the project and its tests locally
- Code style and formatter
- Folder layout for scenes, scripts and assets

## How to work in this repo

- **Never push to `main`.** Work on a branch and open a pull request. PRs are squash-merged.
- **Keep PRs small and focused**, one feature or fix each. Fill in the PR template.
- **Link issues** with `Closes #123` in the PR body when a PR finishes one.
- **Label PRs and issues** with one `type:` label and any `area:` labels that fit. The canonical label list lives in `.github/labels.yml`; edit that file rather than creating labels by hand.
- **Run the project's checks before pushing** once CI exists. Never skip or disable a test to get green.
- **Binary assets** (art, audio, fonts): do not edit or regenerate them unless asked. Keep source files (e.g. `.psd`, `.kra`, `.aseprite`) out of the build folders.
- **Design decisions** that are not obvious from the code go in `docs/` as short Markdown notes, one topic per file.

## Glossary

| Term | Meaning |
| --- | --- |
| Town | The above-ground rebuilding and social half of the game |
| Delve | One dice-placement run below the tide |
| Luck spirit | The antagonist who sank the town; runs the casino palace |
| Landmark | A special building recovered from a delve and placed in town |
| Villager | A rescued resident who can be housed and, for some, dated |
