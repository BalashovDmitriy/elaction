#!/usr/bin/env python3
"""Архив релиза: собранный билд плюс лицензии.

Что кладём — [ADR-0013](../docs/adr/0013-release-and-versioning.md), пункт 7:
исполняемый файл (ресурсы вшиты внутрь, `.pck` рядом нет), своя лицензия,
лицензии шрифтов — OFL требует прикладывать её к продукту — и `CREDITS.md`:
модели под CC-BY 3.0 требуют назвать авторов там, где их распространяют.
Что каждый шрифт `assets/fonts/` едет со своей лицензией, стережёт `test_release`.

Архив собирается кодом, а не командой `zip` в workflow: `zip` есть на ubuntu
и нет на windows, а разбираться с этим в YAML — плодить платформенные ветки
там, где их можно не заводить.

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

# Что едет вместе с игрой. Ключ — путь в репозитории, значение — имя в архиве.
EXTRAS: dict[str, str] = {
    "LICENSE": "LICENSE.txt",
    "CREDITS.md": "CREDITS.md",
    "assets/fonts/Exo2.LICENSE.txt": "Exo2.LICENSE.txt",
}

# Права на исполняемый файл внутри zip. Без них распакованная под Linux игра
# не запускается, пока игрок сам не сделает chmod +x, — а он не обязан знать.
EXECUTABLE_MODE: int = 0o755


# Папка внутри архива. Без неё `unzip` в Linux рассыпал бы файлы по текущему
# каталогу, а называть её как сам архив нельзя: проводник Windows на «Извлечь
# всё» и так заводит папку по имени архива, и путь выходил бы с удвоением —
# elaction-v0.9.0-windows\elaction-v0.9.0-windows\elaction.exe. Версия и
# платформа остаются в имени архива, внутри — просто игра.
INNER_DIR: str = "elaction"


def archive_name(preset: Preset) -> str:
    """Имя файла архива: `elaction-v0.9.0-windows`."""
    return f"elaction-v{project_version()}-{preset.alias}"


def add(archive: zipfile.ZipFile, source: Path, name: str, executable: bool = False) -> None:
    """Кладёт файл в архив, при надобности пометив его исполняемым."""
    info = zipfile.ZipInfo(name)
    info.compress_type = zipfile.ZIP_DEFLATED
    # На Windows ZipInfo ставит create_system=0 (FAT), и распаковщик тогда права
    # из external_attr не смотрит вовсе: собранный на Windows Linux-архив уехал
    # бы без права на запуск. Говорим «Unix» явно, от системы сборки не завися.
    info.create_system = 3
    info.external_attr = (EXECUTABLE_MODE if executable else 0o644) << 16
    archive.writestr(info, source.read_bytes())


def package(preset: Preset) -> int:
    """Собирает архив для пресета. Возвращает код возврата для процесса."""
    if not preset.path.exists():
        print(f"Нет собранного билда {preset.path} — сначала python tools/export.py {preset.alias}")
        return 1

    # Проверяем до того, как открыли архив: иначе на полпути в dist/ остаётся
    # обрезанный zip, который со стороны не отличить от готового.
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
