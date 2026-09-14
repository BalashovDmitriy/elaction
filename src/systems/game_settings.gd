class_name GameSettings
extends RefCounted

## Настройки игрока: громкости, язык, полный экран.
##
## Первое, что игра пишет на диск (ADR-0012). Лежат в `user://`, а не рядом
## с игрой: у собранной игры своя папка данных, и писать в неё — единственный
## переносимый способ ничего не потерять при обновлении.
##
## Класс без узлов: он читает, применяет и сохраняет, а кто его позовёт —
## меню или автозапуск — ему всё равно. Поэтому проверяется без сцены.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Языки интерфейса. Первый — запасной, если у системы язык незнакомый.
const LOCALES: PackedStringArray = ["en", "ru"]

var master: float = 1.0
var music: float = 0.7
var sfx: float = 1.0
var locale: String = ""
var fullscreen: bool = false


## Настройки с диска. Файла нет — значения по умолчанию, язык по локали системы.
static func load_from(path: String = PATH) -> GameSettings:
	var settings := GameSettings.new()
	settings.locale = settings.system_locale()

	var file := ConfigFile.new()
	if file.load(path) != OK:
		return settings

	settings.master = clampf(float(file.get_value(SECTION, "master", settings.master)), 0.0, 1.0)
	settings.music = clampf(float(file.get_value(SECTION, "music", settings.music)), 0.0, 1.0)
	settings.sfx = clampf(float(file.get_value(SECTION, "sfx", settings.sfx)), 0.0, 1.0)
	settings.fullscreen = bool(file.get_value(SECTION, "fullscreen", settings.fullscreen))

	var saved := String(file.get_value(SECTION, "locale", settings.locale))
	settings.locale = saved if LOCALES.has(saved) else settings.locale
	return settings


## Язык системы, если он нам знаком. Иначе английский: незнакомый язык лучше
## показать понятной латиницей, чем кириллицей наугад.
func system_locale() -> String:
	var system := OS.get_locale_language()
	return system if LOCALES.has(system) else LOCALES[0]


func save_to(path: String = PATH) -> void:
	var file := ConfigFile.new()
	file.set_value(SECTION, "master", master)
	file.set_value(SECTION, "music", music)
	file.set_value(SECTION, "sfx", sfx)
	file.set_value(SECTION, "locale", locale)
	file.set_value(SECTION, "fullscreen", fullscreen)
	file.save(path)


## Применяет настройки к игре: шины, язык и окно.
##
## Один метод на всё, потому что применять их надо вместе и в одном порядке:
## иначе меню меняет громкость, а язык остаётся от прошлого запуска.
func apply() -> void:
	Sounds.set_level(Sounds.MASTER_BUS, master)
	Sounds.set_level(Sounds.MUSIC_BUS, music)
	Sounds.set_level(Sounds.SFX_BUS, sfx)
	TranslationServer.set_locale(locale)
	var mode := (
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Громкость шины по её имени. Нужна меню: ползунков три, а полей тоже три,
## и связывать их по одному значило бы написать один и тот же код трижды.
func level_of(bus: String) -> float:
	match bus:
		Sounds.MUSIC_BUS:
			return music
		Sounds.SFX_BUS:
			return sfx
		_:
			return master


func set_level(bus: String, value: float) -> void:
	var level := clampf(value, 0.0, 1.0)
	match bus:
		Sounds.MUSIC_BUS:
			music = level
		Sounds.SFX_BUS:
			sfx = level
		_:
			master = level
	Sounds.set_level(bus, level)
