@tool
class_name PlaceholderBlock
extends StaticBody3D
## Box of solid geometry: ground, platforms, ramps, walls.
##
## Placeholder art on purpose (see CLAUDE_CODE_MASTER_PROMPT.md section 25-26).
## Size/colour are per-instance so one scene builds a whole test arena, and the
## mesh + collision shape can never drift apart.

@export var size := Vector3(4.0, 1.0, 4.0):
	set(value):
		size = value
		_apply()
@export var color := Color(0.45, 0.68, 0.35):
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
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = FlatMaterial.flat(color)
	mesh_instance.mesh = box_mesh

	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
