@tool
class_name PlaceholderTree
extends StaticBody3D
## Cartoon placeholder tree: trunk cylinder + cone canopy, collision on the
## trunk only so the player can brush past the leaves.

@export var trunk_height := 2.0:
	set(value):
		trunk_height = value
		_apply()
@export var trunk_radius := 0.25:
	set(value):
		trunk_radius = value
		_apply()
@export var canopy_radius := 1.5:
	set(value):
		canopy_radius = value
		_apply()
@export var canopy_height := 2.6:
	set(value):
		canopy_height = value
		_apply()
@export var canopy_color := Color(0.24, 0.6, 0.3):
	set(value):
		canopy_color = value
		_apply()

@onready var trunk: MeshInstance3D = $Trunk
@onready var canopy: MeshInstance3D = $Canopy
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_radius * 0.85
	trunk_mesh.bottom_radius = trunk_radius
	trunk_mesh.height = trunk_height
	trunk_mesh.radial_segments = 8
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.42, 0.28, 0.17)
	trunk_material.roughness = 1.0
	trunk_mesh.material = trunk_material
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_height * 0.5

	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.0
	canopy_mesh.bottom_radius = canopy_radius
	canopy_mesh.height = canopy_height
	canopy_mesh.radial_segments = 10
	var canopy_material := StandardMaterial3D.new()
	canopy_material.albedo_color = canopy_color
	canopy_material.roughness = 0.95
	canopy_mesh.material = canopy_material
	canopy.mesh = canopy_mesh
	canopy.position.y = trunk_height + canopy_height * 0.4

	var shape := CylinderShape3D.new()
	shape.radius = trunk_radius
	shape.height = trunk_height
	collision.shape = shape
	collision.position.y = trunk_height * 0.5
