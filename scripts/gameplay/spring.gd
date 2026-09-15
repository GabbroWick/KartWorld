@tool
class_name Spring
extends Area3D
## A bounce pad: whoever steps on it (character or kart) is thrown up to
## `height` metres. The pad squashes for feedback. Anything with a
## `launch(vertical_speed)` method can use it; the character and vehicle
## motors both offer one.

@export_range(1.0, 40.0, 0.5) var height := 8.0
@export_range(0.5, 6.0, 0.1) var radius := 1.2
@export var color := Color(0.95, 0.55, 0.15)

@onready var pad: MeshInstance3D = $Pad
@onready var base: MeshInstance3D = $Base
@onready var shape: CollisionShape3D = $Shape

var _squash := 0.0


func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _apply() -> void:
	if not is_node_ready():
		return
	var top := CylinderMesh.new()
	top.top_radius = radius
	top.bottom_radius = radius
	top.height = 0.25
	top.material = FlatMaterial.flat(color)
	pad.mesh = top
	pad.position.y = 0.35
	var bottom := CylinderMesh.new()
	bottom.top_radius = radius * 0.7
	bottom.bottom_radius = radius * 0.9
	bottom.height = 0.25
	bottom.material = FlatMaterial.flat(color.darkened(0.45))
	base.mesh = bottom
	base.position.y = 0.12
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = 0.6


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_squash = maxf(_squash - delta * 4.0, 0.0)
	pad.scale = Vector3(1.0 + _squash * 0.3, 1.0 - _squash * 0.6, 1.0 + _squash * 0.3)


func _on_body_entered(body: Node3D) -> void:
	var motor: Node = body.get(&"motor") if body else null
	if motor == null or not motor.has_method(&"launch"):
		return
	var gravity: float = motor.call(&"get_gravity_strength")
	motor.call(&"launch", sqrt(2.0 * gravity * height))
	_squash = 1.0
	Sfx.play(&"jump", 2.0)
