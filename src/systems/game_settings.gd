class_name GameSettings
extends RefCounted

## Настройки игрока: громкости, язык, окно, графика.
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

## Сколько уровней сложности: столько положений у переключателя автомата.
const DIFFICULTIES: int = 4

var master: float = 1.0
var music: float = 0.7
var sfx: float = 1.0
var locale: String = ""
## Режим окна — [enum DisplayModes.Mode]: окно, без рамки, полный экран.
var window_mode: int = DisplayModes.Mode.WINDOWED
## Размер окна в режиме окна. Полный экран и окно без рамки — в разрешении экрана.
var resolution: Vector2i = DisplayModes.DEFAULT_RESOLUTION
## Масштаб 3D-рендера, доля разрешения окна (FSR ниже единицы).
var render_scale: float = 1.0
## Уровень сложности — DIP-переключатель автомата, 0–3: стартовый навык партии,
## к которому прибавляются пройденные здания (ADR-0027, решение 8).
var difficulty: int = 0
## Качество графики — [enum Graphics.Quality] (ADR-0030, решение 5).
var quality: int = Graphics.Quality.HIGH
## Выбран ли уровень качества — игроком или замером первого запуска
## ([QualityProbe], ADR-0034, решение 3). Пока нет, первое здание его мерит.
var quality_measured: bool = false
## Показывать ли кровь при попадании пули (ADR-0031).
var blood: bool = true


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
	# До M22 окно было флажком «полный экран»: он и становится режимом.
	var legacy_full := bool(file.get_value(SECTION, "fullscreen", false))
	settings.window_mode = clampi(
		int(
			file.get_value(
				SECTION,
				"window_mode",
				DisplayModes.Mode.FULLSCREEN if legacy_full else settings.window_mode
			)
		),
		0,
		DisplayModes.Mode.size() - 1
	)
	var size: Variant = file.get_value(SECTION, "resolution", settings.resolution)
	if size is Vector2i:
		settings.resolution = size
	settings.render_scale = clampf(
		float(file.get_value(SECTION, "render_scale", settings.render_scale)),
		DisplayModes.RENDER_SCALES[-1],
		1.0
	)
	settings.blood = bool(file.get_value(SECTION, "blood", settings.blood))
	settings.difficulty = clampi(
		int(file.get_value(SECTION, "difficulty", settings.difficulty)), 0, DIFFICULTIES - 1
	)

	settings.quality = clampi(
		int(file.get_value(SECTION, "quality", settings.quality)), 0, Graphics.Quality.size() - 1
	)
	# Уровень, сохранённый до M22, выбран игроком: мерить поверх него незачем.
	settings.quality_measured = bool(
		file.get_value(SECTION, "quality_measured", file.has_section_key(SECTION, "quality"))
	)

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
	file.set_value(SECTION, "window_mode", window_mode)
	file.set_value(SECTION, "resolution", resolution)
	file.set_value(SECTION, "render_scale", render_scale)
	file.set_value(SECTION, "difficulty", difficulty)
	file.set_value(SECTION, "quality", quality)
	file.set_value(SECTION, "quality_measured", quality_measured)
	file.set_value(SECTION, "blood", blood)
	file.save(path)


## Применяет настройки к игре: шины, язык, окно и графику.
##
## Один метод на всё, потому что применять их надо вместе и в одном порядке:
## иначе меню меняет громкость, а язык остаётся от прошлого запуска.
func apply() -> void:
	Sounds.set_level(Sounds.MASTER_BUS, master)
	Sounds.set_level(Sounds.MUSIC_BUS, music)
	Sounds.set_level(Sounds.SFX_BUS, sfx)
	TranslationServer.set_locale(locale)
	# Окно не трогается в headless-прогонах: там его нет, и тесты настроек
	# меняли бы размер несуществующего окна.
	if DisplayServer.get_name() != "headless":
		var tree := Engine.get_main_loop() as SceneTree
		DisplayModes.apply(
			window_mode as DisplayModes.Mode,
			resolution,
			render_scale,
			tree.root if tree != null else null
		)
	Graphics.broadcast(quality as Graphics.Quality)
	Blood.enabled = blood


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
