#!/usr/bin/env python3
"""Release archive: the built binary plus licences.

What goes in — [ADR-0013](../docs/adr/0013-release-and-versioning.md), point 7:
the executable (resources are embedded inside, no `.pck` next to it), our own licence,
font licences — OFL requires shipping it with the product — and `CREDITS.md`:
models under CC-BY 3.0 require naming the authors where they are distributed.
That every font in `assets/fonts/` ships with its licence is guarded by `test_release`.

The archive is built by code, not by the `zip` command in the workflow: `zip` exists on ubuntu
and not on windows, and dealing with that in YAML means breeding platform branches
where they can be avoided.

    python tools/package.py windows   # dist/elaction-v0.9.0-windows.zip
    python tools/package.py linux
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

from export import Preset, pick, read_presets
from godot_bin import PROJECT_ROOT, use_utf8_output
from version import read as project_version

DIST_DIR = PROJECT_ROOT / "dist"

# What ships with the game. Key — path in the repository, value — name in the archive.
EXTRAS: dict[str, str] = {
    "LICENSE": "LICENSE.txt",
    "CREDITS.md": "CREDITS.md",
    "assets/fonts/Exo2.LICENSE.txt": "Exo2.LICENSE.txt",
}

# Permissions of the executable inside the zip. Without them a game unpacked under Linux
# does not start until the player runs chmod +x himself — and he is not obliged to know that.
EXECUTABLE_MODE: int = 0o755


# A folder inside the archive. Without it `unzip` on Linux would scatter files into the current
# directory, and it cannot be named like the archive itself: Windows Explorer on "Extract
# All" already creates a folder named after the archive, and the path would come out doubled —
# elaction-v0.9.0-windows\elaction-v0.9.0-windows\elaction.exe. Version and
# platform stay in the archive name, inside — just the game.
INNER_DIR: str = "elaction"


def archive_name(preset: Preset) -> str:
    """Archive file name: `elaction-v0.9.0-windows`."""
    return f"elaction-v{project_version()}-{preset.alias}"


def add(archive: zipfile.ZipFile, source: Path, name: str, executable: bool = False) -> None:
    """Puts a file into the archive, marking it executable if needed."""
    info = zipfile.ZipInfo(name)
    info.compress_type = zipfile.ZIP_DEFLATED
    # On Windows ZipInfo sets create_system=0 (FAT), and then the unpacker does not look at
    # permissions from external_attr at all: a Linux archive built on Windows would ship
    # without the execute permission. We say "Unix" explicitly, independent of the build system.
    info.create_system = 3
    info.external_attr = (EXECUTABLE_MODE if executable else 0o644) << 16
    archive.writestr(info, source.read_bytes())


def package(preset: Preset) -> int:
    """Builds the archive for a preset. Returns the exit code for the process."""
    if not preset.path.exists():
        print(f"Нет собранного билда {preset.path} — сначала python tools/export.py {preset.alias}")
        return 1

    # Checked before the archive is opened: otherwise a truncated zip is left halfway in dist/,
    # which from the outside cannot be told apart from a finished one.
    missing = [source for source in EXTRAS if not (PROJECT_ROOT / source).exists()]
    if missing:
        print(f"Не нашёл {', '.join(missing)} — архив без них не собираю.")
        return 1

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    name = archive_name(preset)
    target = DIST_DIR / f"{name}.zip"
    target.unlink(missing_ok=True)

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        add(archive, preset.path, f"{INNER_DIR}/{preset.path.name}", executable=True)
        for source, inside in EXTRAS.items():
            add(archive, PROJECT_ROOT / source, f"{INNER_DIR}/{inside}")

    size_mb = target.stat().st_size / (1024 * 1024)
    print(f"Архив: {target} ({size_mb:.1f} МБ)")
    return 0


def main(argv: list[str]) -> int:
    use_utf8_output()
    if not argv:
        print("Нужна платформа: python tools/package.py windows|linux")
        return 2

    presets = read_presets()
    preset = pick(presets, argv[0])
    if preset is None:
        known = ", ".join(known_preset.alias for known_preset in presets)
        print(f"Нет пресета «{argv[0]}». Есть: {known}.")
        return 2

    return package(preset)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
