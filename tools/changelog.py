#!/usr/bin/env python3
"""Release notes: the `CHANGELOG.md` section for a version.

The release workflow prints them into the GitHub description, so that the notes are
written in the same place as everything else about the version, not by hand on the web
([ADR-0013](../docs/adr/0013-release-and-versioning.md), item 10).

A missing section is a failure, not empty notes: a release without a description goes
out silently, and people notice it only after publication.

    python tools/changelog.py v0.9.0
    python tools/changelog.py           # version from project.godot
"""

from __future__ import annotations

import re
import sys

from godot_bin import PROJECT_ROOT, use_utf8_output
from version import read as project_version

CHANGELOG = PROJECT_ROOT / "CHANGELOG.md"

# The file tail per Keep a Changelog: link definitions like `[0.9.0]: https://…`.
# Nothing separates the oldest version's section from them, and they have no business
# in release notes.
_LINK_DEFINITION = re.compile(r"^\[[^\]]+\]:\s")


def section(version: str) -> str | None:
    """Text of the version section without its heading. None if the section is missing or empty."""
    heading = f"## [{version}]"
    lines = CHANGELOG.read_text(encoding="utf-8").splitlines()

    start: int | None = None
    for number, line in enumerate(lines):
        if line.startswith(heading):
            start = number + 1
            break
    if start is None:
        return None

    end = len(lines)
    for number in range(start, len(lines)):
        if lines[number].startswith("## ") or _LINK_DEFINITION.match(lines[number]):
            end = number
            break

    # An empty section is as much a failure as a missing one: the heading is there,
    # but the release still goes out without a description.
    return "\n".join(lines[start:end]).strip() or None


def main(argv: list[str]) -> int:
    use_utf8_output()
    wanted = argv[0] if argv else project_version()
    version = wanted[1:] if wanted.startswith("v") else wanted

    text = section(version)
    if text is None:
        print(
            f"В CHANGELOG.md нет заметок для {version}: секции «## [{version}]» "
            "нет или она пуста, а релиз без описания выходит молча."
        )
        return 1

    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
