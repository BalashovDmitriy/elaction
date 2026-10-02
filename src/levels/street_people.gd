class_name StreetPeople
extends Node3D

## Прохожие у выезда (ADR-0054, решение 3): горожане из паков Quaternius идут
## по дальнему тротуару в обе стороны и уходят за край улицы, а оттуда
## приходят другие. Днём их больше, ночью — единицы; в дождь и снег у
## большинства зонт, в снег на зонте снег. Капли и хлопья гаснут о них
## ([Shelter]), а не идут насквозь.
##
## Прохожий — собран из частей моделей пака ([Passerby]) и идёт их же
## ходьбой: шаг подогнан к скорости, и ноги не скользят. Механики у прохожих
## нет: в игру они не вмешиваются.

## Снег на зонте — налёт, а не шапка: купол пологий, и шапкой он был бы
## белым целиком.
const UMBRELLA_SNOW: float = 0.2

## Сколько прохожих на улице по времени суток: утро, день, вечер, ночь.
const COUNT: Array[int] = [4, 7, 5, 2]
## Две полосы тротуара по глубине, м: ближе к бордюру идут налево, у витрин —
## направо.
const LANES := Vector2(-8.75, -9.75)
## Скорость шага, м/с, и та, под которую снята ходьба пака: под неё шаг
## подгоняется, иначе ноги скользили бы.
const SPEED := Vector2(1.05, 1.45)
const CLIP_SPEED: float = 1.05
## Рост прохожего — как у Otto: улица в том же масштабе.
const HEIGHT: float = Proportions.BODY
## Какая доля прохожих в непогоду идёт под зонтом.
const UMBRELLA_SHARE: float = 0.7
## Зонт: радиус и высота купола, длина ручки, м; цвета куполов.
const CANOPY := Vector2(0.5, 0.26)
const SHAFT: float = 0.8
const CANOPY_TONES: Array[Color] = [
	Color(0.06, 0.06, 0.07), Color(0.32, 0.05, 0.06), Color(0.08, 0.12, 0.22), Color(0.2, 0.2, 0.22)
]
## Насколько за край улицы прохожий уходит, прежде чем вернуться с другой
## стороны, м.
const BEYOND: float = 3.0


## Прохожий: узел, скорость со знаком и анимация.
class Walker:
	extends RefCounted
	var node: Node3D = null
	var speed: float = 0.0


var _walkers: Array[Walker] = []
var _span := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _dress := Passerby.Dress.LIGHT


## Выводит прохожих на тротуар от [param from] до [param to] по x сцены, на
## высоте тротуара [param walk] сцены, во время суток [param time] и погоду
## [param weather].
func build(
	from: float,
	to: float,
	walk: float,
	building_seed: int,
	time: TimeOfDay.Kind,
	weather: Weather.Kind
) -> void:
	name = "People"
	_span = Vector2(from - BEYOND, to + BEYOND)
	_rng.seed = hash([building_seed, "people"])
	var wet := Weather.is_raining(weather) or Weather.is_snowing(weather)
	_dress = Passerby.dress_for(weather)
	for index in COUNT[time]:
		var walker := Walker.new()
		var leftward := index % 2 == 0
		walker.speed = _rng.randf_range(SPEED.x, SPEED.y) * (-1.0 if leftward else 1.0)
		walker.node = _person(wet and _rng.randf() < UMBRELLA_SHARE, Weather.is_snowing(weather))
		walker.node.position = Vector3(
			_rng.randf_range(_span.x, _span.y), walk, LANES.x if leftward else LANES.y
		)
		walker.node.rotation.y = -PI * 0.5 if leftward else PI * 0.5
		add_child(walker.node)
		var player := walker.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null:
			# Ходьба пака приходит из glTF без петли: доиграв шаг, прохожий
			# застывал и плыл по тротуару статуей.
			player.get_animation(&"Walk").loop_mode = Animation.LOOP_LINEAR
			player.play(&"Walk")
			player.speed_scale = absf(walker.speed) / CLIP_SPEED
			# Каждый — со своей фазы шага: строем идущая толпа читается куклами.
			player.seek(_rng.randf() * player.current_animation_length, true)
		Outdoors.mark(walker.node)
		_walkers.append(walker)


## Сколько прохожих на улице — для теста.
func count() -> int:
	return _walkers.size()


func _process(delta: float) -> void:
	for walker in _walkers:
		var at := walker.node.position
		at.x += walker.speed * delta
		if walker.speed < 0.0 and at.x < _span.x:
			at.x = _span.y
		elif walker.speed > 0.0 and at.x > _span.y:
			at.x = _span.x
		walker.node.position = at


## Прохожий: собран из частей пака ростом с Otto, одет по погоде, под зонтом
## или без.
func _person(umbrella: bool, snowy: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Walker"
	var model := Passerby.make(_rng, HEIGHT, _dress)
	root.add_child(model)
	var cover := Vector3(Proportions.BODY_WIDTH, HEIGHT, WorldSpace.BODY_DEPTH)
	if umbrella:
		var canopy := _umbrella(snowy)
		root.add_child(canopy)
		cover = Vector3(CANOPY.x * 2.0, HEIGHT + CANOPY.y + 0.1, CANOPY.x * 2.0)
	Shelter.over(root, cover)
	return root


## Зонт над головой: купол и ручка, в руке у плеча. В снег на куполе снег.
func _umbrella(snowy: bool) -> Node3D:
	var umbrella := Node3D.new()
	umbrella.name = "Umbrella"
	var look := StandardMaterial3D.new()
	look.albedo_color = CANOPY_TONES[_rng.randi_range(0, CANOPY_TONES.size() - 1)]
	look.roughness = 0.6
	# Изнутри купол тоже виден: полусфера без дна.
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Купол — выпуклый, а не конус: конусом зонт читался соломенной шляпой.
	var dome := SphereMesh.new()
	dome.radius = CANOPY.x
	dome.height = CANOPY.y * 2.0
	dome.is_hemisphere = true
	dome.radial_segments = 12
	dome.rings = 4
	dome.material = look
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = dome
	canopy.position = Vector3(0.0, HEIGHT - 0.12, 0.0)
	umbrella.add_child(canopy)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.012
	stick.bottom_radius = 0.012
	stick.height = SHAFT
	stick.material = look
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = stick
	pole.position = Vector3(0.0, HEIGHT - 0.12 - SHAFT * 0.5, 0.12)
	umbrella.add_child(pole)
	if snowy:
		CarModel.snow_on(umbrella, UMBRELLA_SNOW)
	return umbrella
