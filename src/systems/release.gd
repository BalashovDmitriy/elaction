class_name Release
extends RefCounted

## Версия игры и строка запуска.
##
## Версия живёт в одном месте — `config/version` в `project.godot`
## ([ADR-0013](../../docs/adr/0013-release-and-versioning.md), пункт 3). Отсюда её
## берут все, кому она нужна: угол главного меню, строка в логе и — через
## `tools/version.py` — пресеты экспорта и тег релиза.
##
## Класс без узлов и состояния: спрашивают его и из меню, и из точки входа,
## и из теста, а заводить ради двух строк автолоад незачем.

## Ключ настройки проекта, где лежит версия.
const SETTING := "application/config/version"

## На случай, если настройки нет вовсе: пусть лучше будет заведомо неигровая
## версия в углу экрана, чем пустое место, о котором никто не спросит.
const UNKNOWN := "0.0.0"


## Версия игры, например `0.9.0`.
static func version() -> String:
	var found: Variant = ProjectSettings.get_setting(SETTING, UNKNOWN)
	var text := str(found)
	return text if not text.is_empty() else UNKNOWN


## То же с буквой `v` — как в теге и в имени архива.
static func tag() -> String:
	return "v" + version()


## Строка, которую игра печатает в лог при запуске.
##
## Она же маркер для `tools/smoke.py`: собранный билд, который не напечатал её,
## не считается запустившимся, даже если процесс вышел с нулём (ADR-0013,
## пункт 6). Поэтому формат менять нельзя, не поправив smoke.
static func banner() -> String:
	return "elaction %s · %s" % [version(), OS.get_name()]
