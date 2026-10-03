#!/usr/bin/env python3
"""The game version: one place from which the script spreads it.

The version lives in `config/version` in `project.godot` — that is the single source
of truth ([ADR-0013](../docs/adr/0013-release-and-versioning.md), item 3). From here
it goes into the export presets, the archive name and the tag.

Why a script rather than editing by hand: the version is needed in three places in
a couple of files at once, and `application/file_version` on Windows cannot be
empty — since Godot 4.2 `rcedit` crashes on an empty version and the export does
not build. Once they drift apart, the places stay apart forever.

Run:
    python tools/version.py                 # print the version
    python tools/version.py --set 0.9.0     # set it everywhere
    python tools/version.py --check v0.9.0  # check the tag against the version
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, use_utf8_output

PROJECT_FILE = PROJECT_ROOT / "project.godot"
PRESETS_FILE = PROJECT_ROOT / "export_presets.cfg"

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")

_PROJECT_VERSION = re.compile(r'^(config/version=")([^"]*)(")$', re.MULTILINE)
# Windows expects a four-number version, so in the presets it has a zero at the end.
_PRESET_VERSION = re.compile(r'^(application/(?:file|product)_version=")([^"]*)(")$', re.MULTILINE)


def read() -> str:
    """The version from project.godot."""
    found = _PROJECT_VERSION.search(PROJECT_FILE.read_text(encoding="utf-8"))
    if found is None:
        raise SystemExit("project.godot has no config/version line — fix it by hand.")
    return found.group(2)


def windows_form(version: str) -> str:
    """A four-number version: `0.9.0` -> `0.9.0.0`."""
    return f"{version}.0"


def write(version: str) -> list[str]:
    """Sets the version everywhere. Returns the list of changed files."""
    changed: list[str] = []

    project = PROJECT_FILE.read_text(encoding="utf-8")
    patched = _PROJECT_VERSION.sub(rf"\g<1>{version}\g<3>", project)
    if patched != project:
        PROJECT_FILE.write_text(patched, encoding="utf-8", newline="\n")
        changed.append(PROJECT_FILE.name)

    if PRESETS_FILE.exists():
        presets = PRESETS_FILE.read_text(encoding="utf-8")
        patched, count = _PRESET_VERSION.subn(rf"\g<1>{windows_form(version)}\g<3>", presets)
        # A preset must not be silently skipped: on an empty version rcedit crashes, and the Windows
        # build will not build at all — and only CI will tell about it.
        if count == 0:
            raise SystemExit(
                f"{PRESETS_FILE.name} has no application/file_version "
                "and application/product_version fields — the Windows build does not work without them."
            )
        if patched != presets:
            PRESETS_FILE.write_text(patched, encoding="utf-8", newline="\n")
            changed.append(PRESETS_FILE.name)

    return changed


def check(tag: str) -> int:
    """Checks the tag against the project version. Tag `v0.9.0` requires version `0.9.0`."""
    wanted = tag[1:] if tag.startswith("v") else tag
    current = read()
    if wanted != current:
        print(f"Tag {tag} does not match the project version {current}.")
        print(f"Fix one of the two: python tools/version.py --set {wanted}")
        return 1
    print(f"Tag {tag} matches the project version {current}.")
    return 0


def main(argv: list[str]) -> int:
    use_utf8_output()

    if not argv:
        print(read())
        return 0

    command, rest = argv[0], argv[1:]
    if command == "--check":
        if not rest:
            print("A tag is needed: python tools/version.py --check v0.9.0")
            return 2
        return check(rest[0])

    if command == "--set":
        if not rest:
            print("A version is needed: python tools/version.py --set 0.9.0")
            return 2
        version = rest[0]
        if not SEMVER.match(version):
            print(f"'{version}' does not look like a version. Format: MAJOR.MINOR.PATCH, e.g. 0.9.0.")
            return 2
        changed = write(version)
        print(f"Version {version} set: {', '.join(changed)}" if changed else "Nothing to change.")
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
