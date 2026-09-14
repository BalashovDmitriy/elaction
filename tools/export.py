#!/usr/bin/env python3
"""Сборка: экспорт пресета и проверка, что получилось что-то живое.

Godot умеет вернуть 0, ничего не собрав: об ошибках экспорта он пишет в вывод,
а код возврата оставляет нулевым. Поэтому судим по трём признакам сразу — код
возврата, маркеры ошибок в выводе и файл на диске.

Перед экспортом проект импортируется: без готовой папки `.godot` экспорт
подвисает или собирает ресурсы, которых в исходниках уже нет (godot#69511,
[ADR-0013](../docs/adr/0013-release-and-versioning.md), пункт 5).

Пресеты и пути берутся из `export_presets.cfg` — второй список платформ
разъехался бы с первым.

    python tools/export.py windows
    python tools/export.py linux
    python tools/export.py --list
"""

from __future__ import annotations

import configparser
import sys

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output
from godot_check import find_errors, import_resources

PRESETS_FILE = PROJECT_ROOT / "export_presets.cfg"

# Сборка с вшитыми ресурсами весит десятки мегабайт. Всё, что заметно меньше, —
# не игра, а огрызок, и до архива ему ехать незачем.
MIN_SIZE_MB: int = 5


class Preset:
    """Пресет из export_presets.cfg: как его зовут и куда он кладёт результат."""

    def __init__(self, name: str, platform: str, export_path: str) -> None:
        self.name = name
        self.platform = platform
        self.path = PROJECT_ROOT / export_path

    @property
    def alias(self) -> str:
        """Короткое имя для командной строки: `windows`, `linux`."""
        return self.platform.split()[0].lower()


def read_presets() -> list[Preset]:
    """Разбирает export_presets.cfg. Значения там в кавычках, как в ini от Godot."""
    config = configparser.ConfigParser()
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
    """Ищет пресет по короткому имени или по полному названию."""
    lowered = wanted.lower()
    for preset in presets:
        if lowered in (preset.alias, preset.name.lower()):
            return preset
    return None


def export(preset: Preset) -> int:
    """Собирает пресет. Возвращает код возврата для процесса."""
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
        # Иначе старый файл сойдёт за свежесобранный, если экспорт молча не удался.
        preset.path.unlink()

    print(f"== экспорт «{preset.name}» -> {preset.path.name} ==", flush=True)
    code, output = run(godot, ["--export-release", preset.name, str(preset.path)])
    print(output.strip())

    errors = find_errors(output)
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
