#!/usr/bin/env python3
"""Proves a Godot .pck has nothing from content/adult/ (AC-6).

A SFW pack fails if any of these is true:
  - it holds a file under content/adult/,
  - it holds an imported or exported copy of one (.godot/imported/ and
    .godot/exported/ name their cache files after the source file),
  - its project.binary lacks the "sfw" feature tag, which is what makes
    Settings cap the content level at SFW,
  - any file in it, apart from game data in data/, mentions content/adult/.
    That catches the UID cache and the script class cache, which list
    every file the project had when it was exported, so a pack made from a
    tree that still has the folder leaks the adult file names even though
    their contents are excluded. CI deletes the folder before SFW exports.

content/adult/ci_canary/ always holds a tiny stand-in adult asset, so the
check is never vacuous: `--expect-adult` runs it on a full pack and fails
unless the canary is found there.

Run:
  python3 tools/check_pck.py build/sfw/windows.pck [more.pck ...]
  python3 tools/check_pck.py --expect-adult build/full/windows.pck
"""

from __future__ import annotations

import pathlib
import struct
import sys
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADULT = ROOT / "content" / "adult"
NEEDLE = b"content/adult/"
SFW_FEATURE = "sfw"
CANARY = "content/adult/ci_canary/"
CANARY_NAMES = ("adult_canary.png", "adult_canary.scn")
## Files allowed to mention adult paths: scene data picks a variant by
## content level and falls back to the SFW one (tools/lint_content.py).
DATA_PREFIX = "data/"
SUPPORTED_PACK_FORMATS = {3}
FLAG_ENCRYPTED_DIRECTORY = 1
FLAG_REL_FILEBASE = 2
FILE_ENCRYPTED = 1


@dataclass
class Entry:
    path: str
    offset: int
    size: int
    flags: int


def read_pack(path: pathlib.Path) -> tuple[bytes, list[Entry]]:
    data = path.read_bytes()
    if data[:4] != b"GDPC":
        raise ValueError(f"{path} is not a Godot pack")
    pack_format, _major, _minor, _patch, flags = struct.unpack_from("<5I", data, 4)
    if pack_format not in SUPPORTED_PACK_FORMATS:
        raise ValueError(f"unsupported pack format {pack_format}; update tools/check_pck.py")
    if flags & FLAG_ENCRYPTED_DIRECTORY:
        raise ValueError("encrypted pack directories can't be checked")
    file_base, dir_offset = struct.unpack_from("<QQ", data, 24)
    if not flags & FLAG_REL_FILEBASE:
        file_base = 0
    pos = dir_offset
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    entries = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, pos)
        pos += 4
        name = data[pos:pos + length].rstrip(b"\0").decode("utf-8")
        pos += length
        offset, size = struct.unpack_from("<QQ", data, pos)
        pos += 8 + 8 + 16  # offset, size, md5
        (entry_flags,) = struct.unpack_from("<I", data, pos)
        pos += 4
        name = name.removeprefix("res://")
        entries.append(Entry(name, file_base + offset, size, entry_flags))
    return data, entries


def list_pack(path: pathlib.Path) -> list[str]:
    return [entry.path for entry in read_pack(path)[1]]


def custom_features(data: bytes, entries: list[Entry]) -> list[str]:
    """The export's feature tags, from project.binary's _custom_features."""
    for entry in entries:
        if entry.path != "project.binary":
            continue
        binary = data[entry.offset:entry.offset + entry.size]
        key = binary.find(b"_custom_features")
        if key < 0:
            return []
        pos = key + len(b"_custom_features")
        _size, variant_type, length = struct.unpack_from("<III", binary, pos)
        if variant_type != 4:  # Variant::STRING
            return []
        text = binary[pos + 12:pos + 12 + length].decode("utf-8")
        return [part.strip() for part in text.split(",") if part.strip()]
    return []


def _cache_name(entry: str) -> str:
    """The source file name a .godot/imported or .godot/exported file was made from."""
    name = entry.rsplit("/", 1)[-1]
    if entry.startswith(".godot/imported/"):
        return name.rsplit("-", 1)[0]  # adult_canary.png-<md5>.ctex
    if entry.startswith(".godot/exported/"):
        return name.split("-", 2)[-1]  # export-<md5>-adult_canary.scn
    return ""


def sfw_problems(path: pathlib.Path) -> list[str]:
    data, entries = read_pack(path)
    adult_names = {p.name for p in ADULT.rglob("*") if p.is_file() and p.suffix not in {".md", ".import"}}
    adult_names |= {p.with_suffix(".scn").name for p in ADULT.rglob("*.tscn")}
    problems = []
    if SFW_FEATURE not in custom_features(data, entries):
        problems.append(f'project.binary has no "{SFW_FEATURE}" feature tag, so the content level isn\'t capped')
    for entry in entries:
        if entry.path.startswith("content/adult/"):
            problems.append(entry.path)
            continue
        source = _cache_name(entry.path)
        if source and source in adult_names:
            problems.append(f"{entry.path} (made from a file in content/adult/)")
            continue
        if entry.path.startswith(DATA_PREFIX):
            continue
        if entry.flags & FILE_ENCRYPTED:
            problems.append(f"{entry.path} is encrypted and can't be checked")
            continue
        if NEEDLE in data[entry.offset:entry.offset + entry.size]:
            problems.append(f"{entry.path} mentions content/adult/")
    return problems


def canary_found(path: pathlib.Path) -> bool:
    paths = list_pack(path)
    if not any(p.startswith(CANARY) for p in paths):
        return False
    return all(any(_cache_name(p) == name for p in paths) for name in CANARY_NAMES)


def main(argv: list[str]) -> int:
    expect_adult = "--expect-adult" in argv
    packs = [pathlib.Path(a) for a in argv if a != "--expect-adult"]
    if not packs:
        print(__doc__)
        return 2
    failed = False
    for pack in packs:
        if expect_adult:
            found = canary_found(pack)
            print(f"check_pck: {pack}: canary {'found' if found else 'MISSING'}")
            if not found:
                print("  the full pack should carry content/adult/ci_canary/; if it doesn't, this check can't see adult files")
                failed = True
            continue
        problems = sfw_problems(pack)
        for problem in problems:
            print(f"adult content in SFW pack {pack}: {problem}")
        print(f"check_pck: {pack}: {len(list_pack(pack))} files, {len(problems)} problem(s)")
        failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
