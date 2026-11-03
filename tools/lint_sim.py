#!/usr/bin/env python3
"""Rules the GDScript compiler can't enforce, checked in CI.

sim/ holds the game rules. It must stay deterministic and headless, so:
  - no global random calls (randi, randf, randomize, ...): use the seeded
    RNG streams instead, so every run can be replayed from its seed;
  - no scene tree or node references, so the bot can run it without a scene;
  - no wall-clock time or OS calls, which would break replays.

Run: python3 tools/lint_sim.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SIM = ROOT / "sim"

# A bare call, not a method on an object (rng.randi() is fine).
# Third item True: match against the line with string contents blanked out.
BANNED = [
    (re.compile(r"(?<![\w.])(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|seed)\s*\("),
     "global random call; use an RngStreams stream"),
    (re.compile(r"\bextends\s+(Node|Node2D|Control|CanvasItem|SceneTree)\b"),
     "sim classes must not be nodes; extend RefCounted or Resource"),
    (re.compile(r"\b(get_tree|get_node|get_parent|add_child)\s*\("),
     "scene tree access in sim/"),
    (re.compile(r"\$[A-Za-z_\"]"), "node path access in sim/", True),
    (re.compile(r"\b(Time|OS)\s*\."), "wall-clock or OS access in sim/"),
    (re.compile(r"(pre)?load\s*\(\s*\"[^\"]+\.(tscn|scn)\""), "scene loading in sim/"),
]


def strip_comment(line: str) -> str:
    # Good enough for our code: drop everything after a # that isn't in a string.
    out = []
    quote = ""
    for ch in line:
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        out.append(ch)
    return "".join(out)


STRING = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')


def main() -> int:
    problems: list[str] = []
    for path in sorted(SIM.rglob("*.gd")):
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            line = strip_comment(raw)
            no_strings = STRING.sub('""', line)
            for pattern, why, *flags in BANNED:
                if pattern.search(no_strings if flags else line):
                    rel = path.relative_to(ROOT).as_posix()
                    problems.append(f"{rel}:{number}: {why}\n    {raw.strip()}")
    for problem in problems:
        print(problem)
    print(f"lint_sim: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
