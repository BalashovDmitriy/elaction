#!/usr/bin/env python3
"""Build: export a preset and check that something alive came out.

Godot can return 0 having built nothing: it writes export errors to the output
and leaves the return code at zero. So we judge by three signs at once: the return
code, error markers in the output and the file on disk.

The project is imported before export: without a ready `.godot` folder, export
hangs or packs resources that are no longer in the sources (godot#69511,
[ADR-0013](../docs/adr/0013-release-and-versioning.md), item 5).

Presets and paths are taken from `export_presets.cfg`: a second list of platforms
would drift from the first.

    python tools/export.py windows
    python tools/export.py linux
    python tools/export.py --list
"""

from __future__ import annotations

import configparser
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output
from godot_check import find_errors, import_resources
from version import PRESETS_FILE, PROJECT_FILE

# A build with embedded resources weighs tens of megabytes. Anything noticeably smaller
# is not the game but a stub, and there is no point in it going into the archive.
MIN_SIZE_MB: int = 5

# Godot reports an export failure in its own words, and none of the shared markers
# from godot_check.py catches them. Without this list the second sign of success,
# "error markers in the output", would not work for export at all.
EXPORT_FAILURE_MARKERS: tuple[str, ...] = (
    "Cannot export project",
    "Project export for preset",
    "No export template found",
)

# The engine runs export and import in editor mode, and on exit the editor
# rewrites its configs entirely: the comments in them disappear, and with them
# the decisions ADR-0002 and ADR-0013 (item 8) refer to.
# A build must not change the configs, so we restore them as they were.
GUARDED_FILES: tuple[Path, ...] = (PROJECT_FILE, PRESETS_FILE)


class Preset:
    """A preset from export_presets.cfg: what it is called and where it puts the result."""

    def __init__(self, name: str, platform: str, export_path: str) -> None:
        self.name = name
        self.platform = platform
        self.path = PROJECT_ROOT / export_path

    @property
    def alias(self) -> str:
        """Short name for the command line: `windows`, `linux`."""
        return self.platform.split()[0].lower()


def snapshot() -> dict[Path, bytes]:
    """Contents of the configs the engine tends to rewrite its own way."""
    return {path: path.read_bytes() for path in GUARDED_FILES if path.exists()}


def restore(saved: dict[Path, bytes]) -> None:
    """Restores the configs rewritten by the engine as they were."""
    for path, before in saved.items():
        if path.exists() and path.read_bytes() != before:
            path.write_bytes(before)
            print(f"  ..   {path.name} переписан движком — вернул как было")


def read_presets() -> list[Preset]:
    """Parses export_presets.cfg. Values there are quoted, as in Godot's ini."""
    # interpolation=None: preset values contain "%", and ConfigParser
    # by default would take it for interpolation and fail while parsing.
    config = configparser.ConfigParser(interpolation=None)
    config.read(PRESETS_FILE, encoding="utf-8")

    def value(section: str, key: str) -> str:
        return config.get(section, key, fallback='""').strip('"')

    presets: list[Preset] = []
    for section in config.sections():
        if not section.startswith("preset.") or section.endswith(".options"):
            continue
        presets.append(
            Preset(
                value(section, "name"),
                value(section, "platform"),
                value(section, "export_path"),
            )
        )
    return presets


def pick(presets: list[Preset], wanted: str) -> Preset | None:
    """Finds a preset by short name or by full name."""
    lowered = wanted.lower()
    for preset in presets:
        if lowered in (preset.alias, preset.name.lower()):
            return preset
    return None


def export_failures(output: str) -> list[str]:
    """Lines with which Godot reports an export failure."""
    return [
        line.strip()
        for line in output.splitlines()
        if any(marker in line for marker in EXPORT_FAILURE_MARKERS)
    ]


def export(preset: Preset) -> int:
    """Builds a preset. Returns the return code for the process."""
    saved = snapshot()
    try:
        return _build(preset)
    finally:
        restore(saved)


def _build(preset: Preset) -> int:
    """Import and export as they are, without watching the configs."""
    godot = require_godot()

    print("== импорт ресурсов перед сборкой ==", flush=True)
    code, output = import_resources(godot)
    errors = find_errors(output)
    if code != 0 or errors:
        print(f"Импорт провалился (код {code}).")
        for line in errors[:20]:
            print(f"  {line}")
        return 1

    preset.path.parent.mkdir(parents=True, exist_ok=True)
    if preset.path.exists():
        # Otherwise an old file would pass for a freshly built one if export silently failed.
        preset.path.unlink()

    print(f"== экспорт «{preset.name}» -> {preset.path.name} ==", flush=True)
    # --headless is required: without it export brings up a window and the whole renderer,
    # and the runner has neither a display nor a GPU, so the build fails on DisplayServer.
    code, output = run(godot, ["--headless", "--export-release", preset.name, str(preset.path)])
    print(output.strip())

    errors = find_errors(output) + export_failures(output)
    if code != 0 or errors:
        print(f"\nЭкспорт провалился (код {code}).")
        for line in errors[:20]:
            print(f"  {line}")
        return 1

    if not preset.path.exists():
        print(f"\nЭкспорт отчитался успехом, но файла {preset.path} нет.")
        return 1

    size_mb = preset.path.stat().st_size / (1024 * 1024)
    if size_mb < MIN_SIZE_MB:
        print(f"\n{preset.path.name} весит {size_mb:.1f} МБ — это не похоже на сборку.")
        return 1

    print(f"\nСобрано: {preset.path} ({size_mb:.1f} МБ)")
    return 0


def main(argv: list[str]) -> int:
    use_utf8_output()
    presets = read_presets()

    if not presets:
        print(f"В {PRESETS_FILE.name} нет ни одного пресета.")
        return 2

    if not argv or argv[0] == "--list":
        print("Пресеты:")
        for preset in presets:
            print(f"  {preset.alias:10} {preset.name} -> {preset.path.name}")
        return 0 if argv else 2

    preset = pick(presets, argv[0])
    if preset is None:
        known = ", ".join(known_preset.alias for known_preset in presets)
        print(f"Нет пресета «{argv[0]}». Есть: {known}.")
        return 2

    return export(preset)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
