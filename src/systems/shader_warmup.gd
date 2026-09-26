class_name ShaderWarmup
extends RefCounted

## Прогрев шейдеров редких эффектов (ADR-0039, решение 8).
##
## Первый выстрел дёргал кадр: шейдеры вспышки, дыма, искр, крови и разряда
## молнии собираются в момент первого показа. Прогрев показывает каждый такой
## эффект один раз, пока кадр чёрный, — и убирает раньше, чем кадр откроется.
## Кэш конвейеров у движка общий на процесс, поэтому прогрев — один раз за
## запуск игры. Вторая половина решения — Shader Baker в пресетах экспорта.
##
## Эффект собирается конвейер, только если его и правда нарисовали, поэтому
## он ставится в кадр камеры, а не прячется: спрятанный ([member Node3D.visible]
## выключен) или вне кадра не рисуется и ничего не прогревает.

## Сколько кадр держится чёрным и живут эффекты прогрева, с. Сборка шейдеров
## уходит в первые кадры; дольше держать незачем.
const HOLD: float = 0.2
## Как далеко перед камерой встают эффекты, м.
const AHEAD: float = 4.0

static var _done: bool = false


## Прогревает, если ещё не прогревали и есть чем рисовать. Возвращает, начался
## ли прогрев: тогда вызвавший держит кадр чёрным [constant HOLD] секунд.
static func run(host: Node3D) -> bool:
	if _done or DisplayServer.get_name() == "headless" or host == null:
		return false
	var camera := host.get_viewport().get_camera_3d()
	if camera == null:
		return false
	_done = true
	var at := camera.global_position - camera.global_basis.z * AHEAD
	var shown := spawn(host, at)
	host.get_tree().create_timer(HOLD).timeout.connect(
		func() -> void:
			for node: Node in shown:
				if is_instance_valid(node):
					node.queue_free()
	)
	return true


## Ставит в точку [param at] под узлом [param host] по одному каждого редкого
## эффекта и отдаёт всё поставленное. Без проверок — тестам.
static func spawn(host: Node3D, at: Vector3) -> Array[Node]:
	var before := host.get_children()
	ShotFx.muzzle(host, at, 1.0)
	ShotFx.impact(host, at, -1.0, null)
	Sparks.burst(host, at)
	# Кровь прогревается и выключенная: включат её посреди партии — кадр не
	# должен дёрнуться и тогда.
	var blood := Blood.enabled
	Blood.enabled = true
	Blood.spray(host, at, 1.0)
	Blood.enabled = blood
	var bullet := BulletLook.make(1.0)
	host.add_child(bullet)
	bullet.global_position = at
	bullet.follow(BulletLook.TRAIL_LENGTH)
	var laser := AimLaser.make()
	laser.visible = true
	host.add_child(laser)
	laser.global_position = at
	var bolt := MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.mesh = QuadMesh.new()
	bolt.material_override = Lightning.bolt_look()
	host.add_child(bolt)
	bolt.global_position = at
	var shown: Array[Node] = []
	for child: Node in host.get_children():
		if not before.has(child):
			shown.append(child)
	return shown
