#!/usr/bin/env python3
"""Fails if a Godot .pck contains anything from content/adult/.

Used on the SFW export in CI (AC-6): the SFW presets exclude content/adult/,
and this proves it on the actual exported pack, including imported
textures, whose cache names start with the source file's name.

Run: python3 tools/check_pck.py build/sfw/check.pck
"""

from __future__ import annotations

import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADULT = ROOT / "content" / "adult"
SUPPORTED_PACK_FORMATS = {3}
FLAG_ENCRYPTED_DIRECTORY = 1


def list_pack(path: pathlib.Path) -> list[str]:
    data = path.read_bytes()
    if data[:4] != b"GDPC":
        raise ValueError(f"{path} is not a Godot pack")
    pack_format, _major, _minor, _patch, flags = struct.unpack_from("<5I", data, 4)
    if pack_format not in SUPPORTED_PACK_FORMATS:
        raise ValueError(f"unsupported pack format {pack_format}; update tools/check_pck.py")
    if flags & FLAG_ENCRYPTED_DIRECTORY:
        raise ValueError("encrypted pack directories can't be checked")
    _file_base, dir_offset = struct.unpack_from("<QQ", data, 24)
    pos = dir_offset
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    paths = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, pos)
        pos += 4
        paths.append(data[pos:pos + length].rstrip(b"\0").decode("utf-8"))
        pos += length + 8 + 8 + 16 + 4  # offset, size, md5, flags
    return paths


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    paths = list_pack(pathlib.Path(sys.argv[1]))
    adult_names = {p.name for p in ADULT.rglob("*") if p.is_file() and p.suffix != ".md"}
    problems = []
    for entry in paths:
        name = entry.rsplit("/", 1)[-1]
        if entry.startswith("content/adult/"):
            problems.append(entry)
        elif entry.startswith(".godot/imported/") and any(name.startswith(a + "-") for a in adult_names):
            problems.append(f"{entry} (imported from content/adult/)")
    for problem in problems:
        print(f"adult content in SFW pack: {problem}")
    print(f"check_pck: {len(paths)} files, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
