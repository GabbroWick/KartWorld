@tool
class_name PlaceholderCone
extends StaticBody3D
## Low-poly cone: roofs, rocks, crystals, mountain peaks. Convex collision.

@export_range(0.1, 50.0, 0.1) var radius := 1.0:
	set(value):
		radius = value
		_apply()
@export_range(0.1, 50.0, 0.1) var height := 1.5:
	set(value):
		height = value
		_apply()
@export_range(3, 24, 1) var sides := 6:
	set(value):
		sides = value
		_apply()
@export var color := Color(0.55, 0.53, 0.5):
	set(value):
		color = value
		_apply()

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = sides
	cone.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	cone.material = material
	mesh_instance.mesh = cone
	mesh_instance.position.y = height * 0.5
	collision.shape = cone.create_convex_shape()
	collision.position.y = height * 0.5
