#!/usr/bin/env python3
"""Keeps the export presets in full and SFW pairs (AC-6).

Every platform needs one full preset and one SFW preset. A SFW preset is
named "<Platform name> SFW", carries the "sfw" feature tag (Settings caps
the content level at SFW when it's there), excludes content/adult/*, and
exports under build/sfw/. A full preset has none of that. CI exports and
checks the SFW presets by name, so a renamed or new preset that breaks the
pattern fails here first.

Run: python3 tools/check_presets.py
"""

from __future__ import annotations

import configparser
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRESETS = ROOT / "export_presets.cfg"
SFW_SUFFIX = " SFW"
SFW_FEATURE = "sfw"
ADULT_FILTER = "content/adult/*"


def _value(section: configparser.SectionProxy, key: str) -> str:
    return section.get(key, "").strip().strip('"')


def _list(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]


def problems(text: str) -> list[str]:
    parser = configparser.ConfigParser(interpolation=None, comment_prefixes=(";", "#"), strict=False)
    parser.read_string(text)
    found: list[str] = []
    pairs: dict[str, dict[str, str]] = {}
    for section_name in parser.sections():
        if not section_name.startswith("preset.") or section_name.endswith(".options"):
            continue
        section = parser[section_name]
        name = _value(section, "name")
        platform = _value(section, "platform")
        features = _list(_value(section, "custom_features"))
        excludes = _list(_value(section, "exclude_filter"))
        path = _value(section, "export_path")
        sfw = name.endswith(SFW_SUFFIX)
        kind = "sfw" if sfw else "full"
        if sfw:
            if SFW_FEATURE not in features:
                found.append(f'"{name}" is a SFW preset without the "{SFW_FEATURE}" feature tag')
            if ADULT_FILTER not in excludes:
                found.append(f'"{name}" is a SFW preset that doesn\'t exclude {ADULT_FILTER}')
            if not path.startswith("build/sfw/"):
                found.append(f'"{name}" exports to {path}, not under build/sfw/')
        else:
            if SFW_FEATURE in features:
                found.append(f'"{name}" has the "{SFW_FEATURE}" tag but isn\'t named "... SFW"')
            if not path.startswith("build/full/"):
                found.append(f'"{name}" exports to {path}, not under build/full/')
        pair = pairs.setdefault(platform, {})
        if kind in pair:
            found.append(f'{platform} has two {kind} presets: "{pair[kind]}" and "{name}"')
        pair[kind] = name
    for platform, pair in sorted(pairs.items()):
        for kind in ("full", "sfw"):
            if kind not in pair:
                found.append(f"{platform} has no {kind} preset")
        if "full" in pair and "sfw" in pair and pair["sfw"] != pair["full"] + SFW_SUFFIX:
            found.append(f'"{pair["sfw"]}" should be named "{pair["full"]}{SFW_SUFFIX}"')
    return found


def main() -> int:
    found = problems(PRESETS.read_text(encoding="utf-8"))
    for problem in found:
        print(problem)
    print(f"check_presets: {len(found)} problem(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
