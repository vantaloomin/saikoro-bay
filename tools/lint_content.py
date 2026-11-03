#!/usr/bin/env python3
"""Keeps adult assets reachable only through the content system.

SFW builds exclude content/adult/ entirely. If a scene, script or resource
outside that folder referenced an adult file directly, the SFW build would
break, or worse, the full build would show it without checking the content
level. So only these may mention content/adult/:
  - files inside content/adult/ itself,
  - game data in data/ (scene definitions pick a variant by content level),
  - export presets (to exclude the folder).

Run: python3 tools/lint_content.py
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECKED_SUFFIXES = {".gd", ".tscn", ".tres", ".res", ".gdshader", ".json", ".cfg", ".godot", ".import"}
ALLOWED_DIRS = ("content/adult/", "data/")
ALLOWED_FILES = {"export_presets.cfg"}
SKIPPED_DIRS = (".godot/", ".git/", "addons/")
NEEDLE = "content/adult/"


def main() -> int:
    problems: list[str] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in CHECKED_SUFFIXES:
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(SKIPPED_DIRS) or rel.startswith(ALLOWED_DIRS) or rel in ALLOWED_FILES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if line.lstrip().startswith(("#", ";")):
                continue  # comments may talk about the folder
            if NEEDLE in line:
                problems.append(f"{rel}:{number}: references {NEEDLE} directly\n    {line.strip()}")
    for problem in problems:
        print(problem)
    print(f"lint_content: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
