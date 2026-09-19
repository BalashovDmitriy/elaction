class_name Bullet
extends Area2D

## Пуля.
##
## Летит по горизонтали и гаснет о геометрию, о жертву или на дальности. Высота
## полёта задана точкой выстрела: от высокой пули приседают, низкую перепрыгивают.
## Отдельного правила для уклонения не нужно — всё решают формы коллизии, а они
## у Otto разные стоя и в приседе (ADR-0006, пункт 3).
##
## В кого попадать, решает маска: пуля Otto не задевает его самого, вражеская —
## не задевает других врагов.

## Пуля во что-то попала. Разбирается с этим тот, кто её выпустил: он знает, свои
## это или чужие, и ему же идут очки.
signal hit_target(target: Node2D)

## Во что попадает пуля. Слои: 1 — геометрия, 2 — Otto, 4 — враги, 8 — лампы.
##
## Названы по стрелявшему, а не по мишени: пуля Otto бьёт и по агентам, и по
## лампам, и одним словом это не назвать.
const FROM_OTTO: int = 1 | 4 | 8
const FROM_ENEMY: int = 1 | 2

## Слои, попадание в которые слышно ударом по телу, а не стуком по стене.
const LIVING: int = 2 | 4

## Вспышка выстрела: пуля несёт свой свет и гасит его за первые пиксели полёта.
##
## Живёт здесь, а не у стрелков: пуля у Otto и у агентов одна и та же, и вспышка,
## написанная в каждом из них, разъехалась бы при первой же правке.
##
## Гаснет по пройденному пути, а не по времени: так вспышка одинаковой длины
## у быстрой и медленной пули, и её не надо подбирать под каждую скорость.
const FLASH_RADIUS: float = 156.0
const FLASH_COLOR := Color(1.0, 0.86, 0.55)
const FLASH_ENERGY: float = 2.4
const FLASH_RANGE: float = 192.0

## Группа пуль: по ней агент находит то, от чего уклоняется. Перебирать детей
## уровня ему нельзя — их под три сотни, а пуль на экране от силы четыре.
const GROUP := &"bullets"

@export var speed: float = 660.0

## Дальше этого пуля гаснет сама, даже не встретив преграды.
@export var max_range: float = 1440.0

## Куда летит: -1 влево, +1 вправо.
var direction: float = 1.0

var _travelled: float = 0.0
var _flash: PointLight2D = null
## Пуля уже во что-то попала и доживает до конца кадра.
var _spent: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	# Пуля летит всегда вправо-влево, и текстура у неё одна: направление
	# показывает сам полёт, а не картинка.
	($Visual as Sprite2D).texture = SpriteTextures.tile("bullet")
	_flash = PointLight2D.new()
	_flash.texture = LightTextures.spot()
	_flash.color = FLASH_COLOR
	_flash.energy = FLASH_ENERGY
	_flash.scale = Vector2.ONE * (FLASH_RADIUS * 2.0 / float(LightTextures.SIZE))
	LightTextures.raise(_flash, LightTextures.FLASH_HEIGHT)
	add_child(_flash)


## Половина длины пули, px.
##
## По ней считают, вышла ли пуля из габарита тела: миновав его середину, она
## ещё перекрывает грудь на эту половину, и распрямившийся под ней всё равно
## её ловит. Берётся у самой формы, а не записывается числом рядом, — иначе
## правка сцены молча разошлась бы с теми, кто от неё уклоняется.
func half_length() -> float:
	return (($Shape as CollisionShape2D).shape as RectangleShape2D).size.x * 0.5


func _physics_process(delta: float) -> void:
	var step := speed * delta * signf(direction)
	position.x += step
	_travelled += absf(step)
	_fade_the_flash()
	if _travelled >= max_range:
		queue_free()


func _fade_the_flash() -> void:
	var left := 1.0 - _travelled / FLASH_RANGE
	_flash.visible = left > 0.0
	if _flash.visible:
		_flash.energy = FLASH_ENERGY * left


func _on_body_entered(body: Node2D) -> void:
	# queue_free() убирает узел только в конце кадра, а тел за один кадр можно
	# задеть несколько: без этой отметки одна пуля убивала бы двоих сразу и
	# приносила очки за каждого.
	if _spent:
		return
	_spent = true
	# Слой, а не класс: [Otto] и [Enemy] сами грузят сцену пули, и ссылка отсюда
	# на них замкнула бы загрузку в кольцо — сцена переставала бы читаться вовсе.
	var target := body as CollisionObject2D
	if target != null and (target.collision_layer & LIVING) != 0:
		Sounds.play(Sounds.HIT)
	# Геометрия просто гасит пулю, живых разбирает стрелявший.
	hit_target.emit(body)
	queue_free()
