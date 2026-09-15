class_name Boomerang
extends Area3D
## The thrown weapon: flies `range` metres forward from the thrower, then
## comes back to them; anything with `take_damage` it touches is hit once
## per throw. Spins for looks. Frees itself when it returns (or after
## `max_time` if the thrower is gone).

signal hit(body: Node)

@export_range(2.0, 40.0, 0.5) var range := 12.0
@export_range(2.0, 40.0, 0.5) var speed := 16.0
@export_range(0.0, 20.0, 0.5) var damage := 1.0

var thrower: Node3D
var _direction := Vector3.FORWARD
var _travelled := 0.0
var _returning := false
var _hit: Array[Node] = []
var _time := 0.0
var _visual: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 | 2   # enemies (layer 3) and players (layer 2, filtered)
	monitoring = true
	body_entered.connect(_on_body_entered)
	_visual = MeshInstance3D.new()
	_visual.mesh = Weapons.make_mesh(&"boomerang")
	_visual.scale = Vector3.ONE * 1.6
	add_child(_visual)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	add_child(shape)


func launch(from: Node3D, direction: Vector3) -> void:
	thrower = from
	_direction = direction.normalized()
	global_position = from.global_position + Vector3.UP * 0.9 + _direction * 0.6


func _physics_process(delta: float) -> void:
	_time += delta
	_visual.rotate_y(18.0 * delta)
	if not _returning:
		var step := speed * delta
		global_position += _direction * step
		_travelled += step
		if _travelled >= range:
			_returning = true
	else:
		if not is_instance_valid(thrower) or _time > 6.0:
			queue_free()
			return
		var target := thrower.global_position + Vector3.UP * 0.9
		var to_target := target - global_position
		if to_target.length() < 0.8:
			queue_free()
			return
		global_position += to_target.normalized() * speed * 1.2 * delta


func _on_body_entered(body: Node3D) -> void:
	if body == thrower or body in _hit or not body.has_method(&"take_damage"):
		return
	_hit.append(body)
	body.call(&"take_damage", damage, thrower)
	hit.emit(body)
	Sfx.play(&"hit")
