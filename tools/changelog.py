#!/usr/bin/env python3
"""Заметки к релизу: секция `CHANGELOG.md` для версии.

Workflow релиза печатает их в описание на GitHub, чтобы заметки писались
там же, где всё остальное про версию, а не руками в вебе
([ADR-0013](../docs/adr/0013-release-and-versioning.md), пункт 10).

Отсутствующая секция — это провал, а не пустые заметки: релиз без описания
выходит молча, и замечают это уже после публикации.

    python tools/changelog.py v0.9.0
    python tools/changelog.py           # версия из project.godot
"""

from __future__ import annotations

import re
import sys

from godot_bin import PROJECT_ROOT, use_utf8_output
from version import read as project_version

CHANGELOG = PROJECT_ROOT / "CHANGELOG.md"

# Хвост файла по Keep a Changelog — определения ссылок вида `[0.9.0]: https://…`.
# Секцию самой старой версии от них ничего не отделяет, а в заметках к релизу
# им делать нечего.
_LINK_DEFINITION = re.compile(r"^\[[^\]]+\]:\s")


def section(version: str) -> str | None:
    """Текст секции версии без её заголовка. None, если секции нет или она пуста."""
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

    # Пустая секция — такой же провал, как отсутствующая: заголовок есть,
    # а релиз всё равно выходит без описания.
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
