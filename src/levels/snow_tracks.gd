class_name SnowTracks
extends Node3D

## Следы на снегу крыши и скользкий настил (ADR-0054, решения 2 и 4).
##
## Каждый шаг физики смотрит, кто стоит на заснеженном настиле: Otto и
## агенты. Тот скользит ([member Otto.icy], [member Enemy.icy] — сцепление в
## [Footing]) и оставляет отпечатки — подошва с каблуком, вдавленная в снег,
## левой и правой ногой по очереди. Следы лежат до конца здания; когда их
## набирается [constant LIMIT], новые встают на место самых старых.
##
## Отпечаток — наклейка на слой крыши [constant RoofCatch.LAYER], поверх
## покрова: техника и парапеты следов не получают — по ним не ходят.

## Шаг: столько метров между отпечатками одной цепочки, и на сколько левая
## и правая нога расходятся по глубине.
const STRIDE: float = 0.55
const GAIT: float = 0.07
## Отпечаток: длина, ширина, м; цвет вдавленного снега — темнее и холоднее
## покрова, он в тени своих краёв.
const PRINT := Vector2(0.3, 0.14)
const PRESSED := Color(0.36, 0.41, 0.5, 0.9)
## Сколько отпечатков лежит разом.
const LIMIT: int = 240
## Насколько ступни могут быть выше или ниже настила, м, чтобы стоять на нём.
const ON_DECK: float = 0.2

## Картинка подошвы — одна на все отпечатки.
static var _sole: ImageTexture = null

var _deck: float = 0.0
var _span := Vector2.ZERO
## Проёмы шахт в настиле, по x: над ними под ногами кабина — её пол или крыша
## вровень с настилом, — металл, а не снег.
var _shafts: Array[Vector2] = []
var _prints: Array[Decal] = []
var _next: int = 0
## Где каждый шёл последний отпечаток и какой ногой: по id тела.
var _last: Dictionary = {}
var _left_foot: Dictionary = {}


## Следит за настилом крыши на высоте [param deck] сцены, от [param from] до
## [param to] по x. [param shafts] — проёмы шахт в настиле: кто стоит над
## проёмом, стоит на кабине — не скользит и следов не оставляет.
func watch(deck: float, from: float, to: float, shafts: Array[Vector2] = []) -> void:
	name = "Tracks"
	_deck = deck
	_span = Vector2(from, to)
	_shafts = shafts


## Сколько отпечатков уже лежит — для теста.
func count() -> int:
	return _prints.size()


func _physics_process(_delta: float) -> void:
	var tree := get_tree()
	var walkers := tree.get_nodes_in_group(Footing.OTTO_GROUP)
	walkers.append_array(tree.get_nodes_in_group(Enemy.GROUP))
	for node: Node in walkers:
		var body := node as CharacterBody3D
		if body == null:
			continue
		var feet := body.global_position
		var dead: bool = body.call(&"is_dead")
		var on_deck := (
			not dead
			and body.is_on_floor()
			and absf(feet.y - _deck) < ON_DECK
			and feet.x >= _span.x
			and feet.x <= _span.y
			and not _over_a_shaft(feet.x)
		)
		body.set(&"icy", on_deck)
		var id := body.get_instance_id()
		if not on_deck:
			_last.erase(id)
			continue
		if not _last.has(id):
			_last[id] = feet
			continue
		var from: Vector3 = _last[id]
		if absf(feet.x - from.x) < STRIDE:
			continue
		var left: bool = not bool(_left_foot.get(id, false))
		_left_foot[id] = left
		_last[id] = feet
		_stamp(feet, signf(feet.x - from.x), left)


## Над проёмом ли шахты [param x]: там под ногами кабина, а не настил.
func _over_a_shaft(x: float) -> bool:
	for gap in _shafts:
		if x > gap.x and x < gap.y:
			return true
	return false


func _stamp(at: Vector3, heading: float, left: bool) -> void:
	var print_here: Decal = null
	if _prints.size() < LIMIT:
		print_here = Decal.new()
		print_here.name = "Print"
		print_here.size = Vector3(PRINT.x, 0.3, PRINT.y)
		print_here.texture_albedo = sole()
		print_here.cull_mask = RoofCatch.LAYER
		print_here.upper_fade = 0.05
		print_here.lower_fade = 0.05
		add_child(print_here)
		_prints.append(print_here)
	else:
		print_here = _prints[_next]
		_next = (_next + 1) % LIMIT
	var side := GAIT if left else -GAIT
	print_here.global_position = Vector3(at.x, _deck, at.z + side)
	# Носок — по ходу: картинка носком к +X, налево — разворот.
	print_here.rotation = Vector3(0.0, 0.0 if heading >= 0.0 else PI, 0.0)


## Подошва с каблуком носком к +X: вдавленный снег с мягким краем.
static func sole() -> ImageTexture:
	if _sole != null:
		return _sole
	var size := Vector2i(64, 26)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var u := (float(x) + 0.5) / float(size.x)
			var v := ((float(y) + 0.5) / float(size.y)) * 2.0 - 1.0
			# Подошва — овал от середины к носку, каблук — овал у пятки.
			var toe := Vector2((u - 0.66) / 0.33, v / 0.95).length()
			var heel := Vector2((u - 0.17) / 0.15, v / 0.8).length()
			var shape := maxf(1.0 - smoothstep(0.75, 1.0, toe), 1.0 - smoothstep(0.7, 1.0, heel))
			image.set_pixel(x, y, Color(PRESSED, PRESSED.a * shape))
	_sole = ImageTexture.create_from_image(image)
	return _sole
