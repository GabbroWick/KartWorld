@tool
class_name Hazard
extends Area3D
## A dangerous surface: lava, spikes, acid. A character touching it takes
## `damage` (with the usual i-frames and knockback) or, when `lethal`,
## dies and respawns at the last checkpoint. A kart driven into a lethal
## hazard "falls out of the world": driver and kart come back at the
## checkpoint. Non-lethal hazards ignore karts (spikes do not pop tyres).
##
## One flat box per instance; size/colour are data. The glow makes lava
## read as lava even in the flat cartoon light.

@export var size := Vector3(10.0, 0.6, 10.0):
	set(value):
		size = value
		_apply()
@export var color := Color(1.0, 0.35, 0.08):
	set(value):
		color = value
		_apply()
@export_range(0.0, 2.0, 0.05) var glow := 0.9:
	set(value):
		glow = value
		_apply()
@export_range(0.0, 10.0, 0.5) var damage := 1.0
@export var lethal := false
## Re-apply damage while the character stays inside (spikes), seconds.
@export_range(0.2, 5.0, 0.1) var repeat_every := 1.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var shape: CollisionShape3D = $CollisionShape3D

var _inside: Array[Node3D] = []
var _timer := 0.0


func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _apply() -> void:
	if not is_node_ready():
		return
	var box := BoxMesh.new()
	box.size = size
	var material: Material
	if glow > 0.0:
		# Glowing = lava: the animated crust shader (top face reads best).
		var lava := ShaderMaterial.new()
		lava.shader = load("res://shaders/lava.gdshader")
		lava.set_shader_parameter(&"core_color", color)
		material = lava
	else:
		material = FlatMaterial.flat(color)
	box.material = material
	mesh_instance.mesh = box
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _inside.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = repeat_every
	for body in _inside.duplicate():
		if is_instance_valid(body):
			_hurt(body)


func _on_body_entered(body: Node3D) -> void:
	_inside.append(body)
	_timer = repeat_every
	_hurt(body)


func _on_body_exited(body: Node3D) -> void:
	_inside.erase(body)


func _hurt(body: Node3D) -> void:
	if body is VehicleController:
		if lethal:
			(body as VehicleController).fell_out_of_world.emit()
		return
	if not body is CharacterController:
		return
	var character := body as CharacterController
	if character.driver and character.driver.is_driving:
		return
	if lethal:
		if not character.health.is_dead:
			Sfx.play(&"hurt")
			character.health.kill()
	else:
		character.take_damage(damage, self)
