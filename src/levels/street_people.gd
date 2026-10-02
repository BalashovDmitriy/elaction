class_name StreetPeople
extends Node3D

## Прохожие у выезда (ADR-0054, решение 3): горожане из паков Quaternius идут
## по дальнему тротуару в обе стороны и уходят за край улицы, а оттуда
## приходят другие. Днём их больше, ночью — единицы; в дождь у большинства
## зонт, в снег — шапки и шарфы, без зонтов. Капли и хлопья гаснут о них
## ([Shelter]), а не идут насквозь.
##
## Прохожий — собран из частей моделей пака ([Passerby]) и идёт их же
## ходьбой: шаг подогнан к скорости, и ноги не скользят. Механики у прохожих
## нет: в игру они не вмешиваются.

## Сколько прохожих на улице по времени суток: утро, день, вечер, ночь.
const COUNT: Array[int] = [4, 7, 5, 2]
## Две полосы тротуара по глубине, м: ближе к бордюру идут налево, у витрин —
## направо.
const LANES := Vector2(-9.2, -9.68)
## Скорость шага, м/с, и та, под которую снята ходьба пака: под неё шаг
## подгоняется, иначе ноги скользили бы.
const SPEED := Vector2(1.05, 1.45)
const CLIP_SPEED: float = 1.05
## Рост прохожего — как у Otto: улица в том же масштабе.
const HEIGHT: float = Proportions.BODY
## Какая доля прохожих в дождь идёт под зонтом.
const UMBRELLA_SHARE: float = 0.7
## Зонт: радиус и высота купола, длина трости от кисти, м; цвета куполов.
const CANOPY := Vector2(0.47, 0.26)
const SHAFT: float = 0.82
## На сколько основание купола выше кисти, м: кисть у груди, купол над головой.
const ABOVE_HAND: float = 0.62
const CANOPY_TONES: Array[Color] = [
	Color(0.06, 0.06, 0.07), Color(0.32, 0.05, 0.06), Color(0.08, 0.12, 0.22), Color(0.2, 0.2, 0.22)
]
## С какого зазора по ходу встречные уже поднимают зонт, м: заранее, а не
## когда купола сошлись.
const PASSING: float = 0.9
## Насколько купол сплющен по высоте и на какой высоте над тротуаром кисть,
## что его держит, м.
const CANOPY_FLATTEN: float = 0.75
const HAND_HEIGHT: float = 1.05
## Насколько за край улицы прохожий уходит, прежде чем вернуться с другой
## стороны, м.
const BEYOND: float = 3.0


## Прохожий: узел, скорость со знаком, его ходьба и хват зонта — или null.
class Walker:
	extends RefCounted
	var node: Node3D = null
	var speed: float = 0.0
	var player: AnimationPlayer = null
	var grip: UmbrellaGrip = null


var _walkers: Array[Walker] = []
var _span := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _dress := Passerby.Dress.LIGHT
var _active: bool = true


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
	# Зонты — только в дождь: в снег под зонтом не ходят (просьба пользователя).
	var rainy := Weather.is_raining(weather)
	_dress = Passerby.dress_for(weather, time)
	for index in COUNT[time]:
		var walker := Walker.new()
		var leftward := index % 2 == 0
		walker.speed = _rng.randf_range(SPEED.x, SPEED.y) * (-1.0 if leftward else 1.0)
		walker.node = _person(rainy and _rng.randf() < UMBRELLA_SHARE, leftward)
		walker.node.position = Vector3(
			_rng.randf_range(_span.x, _span.y), walk, LANES.x if leftward else LANES.y
		)
		walker.node.rotation.y = -PI * 0.5 if leftward else PI * 0.5
		add_child(walker.node)
		walker.grip = walker.node.find_child("Grip", true, false) as UmbrellaGrip
		var player := walker.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		walker.player = player
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


## Идут прохожие, только пока выезд в кадре, как поток машин
## ([method StreetTraffic.set_active]): ходьба скелетов и хват зонта на каждый
## кадр — работа на всё здание, а улицу видно только у выезда (авторевью
## M24l). Зовёт улица каждый кадр, поэтому — только по смене.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_process(on)
	for walker in _walkers:
		if walker.player != null:
			walker.player.active = on
		if walker.grip != null:
			walker.grip.active = on


## Идут ли прохожие — для теста.
func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	_make_way()
	for walker in _walkers:
		var at := walker.node.position
		at.x += walker.speed * delta
		if walker.speed < 0.0 and at.x < _span.x:
			at.x = _span.y
		elif walker.speed > 0.0 and at.x > _span.y:
			at.x = _span.x
		walker.node.position = at


## Встречные под зонтами расходятся: идущий у витрин поднимает свой зонт над
## соседним, пока купола перекрываются по ходу, — потом опускает.
func _make_way() -> void:
	for walker in _walkers:
		if walker.grip == null or walker.speed < 0.0:
			continue
		var near := false
		for other in _walkers:
			if other.grip == null or other.speed > 0.0:
				continue
			if absf(other.node.position.x - walker.node.position.x) < CANOPY.x * 2.0 + PASSING:
				near = true
				break
		walker.grip.raised = near


## Прохожий: собран из частей пака ростом с Otto, одет по погоде, под зонтом
## или без.
func _person(umbrella: bool, leftward: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Walker"
	var model := Passerby.make(_rng, HEIGHT, _dress)
	root.add_child(model)
	var cover := Vector3(Proportions.BODY_WIDTH, HEIGHT, WorldSpace.BODY_DEPTH)
	if umbrella:
		var canopy := _umbrella()
		root.add_child(canopy)
		# Зонт в руке: кисть держит ручку, зонт идёт за кистью ([UmbrellaGrip]).
		var grip := UmbrellaGrip.new()
		grip.name = "Grip"
		grip.umbrella = canopy
		grip.forward = Vector3.LEFT if leftward else Vector3.RIGHT
		# Ближняя к камере рука: идущему налево — левая, направо — правая.
		grip.side = "L" if leftward else "R"
		(model.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(grip)
		# Под зонтом сухо от купола до земли: ловец едет с зонтом, а не стоит
		# серединой тела — купол у руки, сбоку от неё.
		var top := ABOVE_HAND + CANOPY.y * CANOPY_FLATTEN
		var dry := Shelter.over(canopy, Vector3(CANOPY.x * 2.0, top + HAND_HEIGHT, CANOPY.x * 2.0))
		dry.size = Vector3(CANOPY.x * 2.0, top + HAND_HEIGHT, CANOPY.x * 2.0)
		dry.position = Vector3(0.0, top - dry.size.y * 0.5, 0.0)
		return root
	Shelter.over(root, cover)
	return root


## Зонт в дождь: начало — ручка в кисти, над ней трость и купол над головой.
func _umbrella() -> Node3D:
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
	dome.radial_segments = 28
	dome.rings = 10
	dome.material = look
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = dome
	canopy.position = Vector3(0.0, ABOVE_HAND, 0.0)
	canopy.scale = Vector3(1.0, CANOPY_FLATTEN, 1.0)
	umbrella.add_child(canopy)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.012
	stick.bottom_radius = 0.012
	stick.height = SHAFT
	stick.material = look
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = stick
	pole.position = Vector3(0.0, SHAFT * 0.5, 0.0)
	umbrella.add_child(pole)
	return umbrella
