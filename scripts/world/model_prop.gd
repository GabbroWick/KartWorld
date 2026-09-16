@tool
class_name ModelProp
extends StaticBody3D
## A real model (an imported .glb scene) with collision built from its bounds.
##
## One script serves every Kenney prop: trees get a narrow trunk cylinder so
## the player brushes past the canopy, rocks get a box, flowers get nothing.
## `PropScatter` swaps `model` per instance, so one template scene yields a
## whole forest of different trees.

enum CollisionMode { NONE, BOX, CYLINDER, TRUNK }

@export var model: PackedScene:
	set(value):
		model = value
		_rebuild()
## Kenney units are ~1/3 of ours; 2.5–3 makes trees and rocks life-size.
@export_range(0.05, 10.0, 0.05) var model_scale := 1.0:
	set(value):
		model_scale = value
		_rebuild()
@export var collision_mode := CollisionMode.BOX:
	set(value):
		collision_mode = value
		_rebuild()
## Trunk radius in metres (after scaling), for CollisionMode.TRUNK.
@export_range(0.05, 3.0, 0.01) var trunk_radius := 0.25:
	set(value):
		trunk_radius = value
		_rebuild()
## Fraction of the model height covered by the trunk collider.
@export_range(0.1, 1.0, 0.05) var trunk_height_ratio := 0.6:
	set(value):
		trunk_height_ratio = value
		_rebuild()
## Shrinks box/cylinder collision so the player is not blocked by thin air
## around leaves and corners.
@export_range(0.3, 1.0, 0.05) var collision_shrink := 0.85:
	set(value):
		collision_shrink = value
		_rebuild()
## Recolour Kenney Nature Kit materials to the island palette (see
## KenneyPalette). Off for kits that use textures.
@export var apply_palette := true:
	set(value):
		apply_palette = value
		_rebuild()

var bounds := AABB()
var _instance: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	if is_instance_valid(_instance):
		remove_child(_instance)
		_instance.queue_free()
		_instance = null
	if is_instance_valid(_shape):
		remove_child(_shape)
		_shape.queue_free()
		_shape = null
	if model == null:
		return
	_instance = model.instantiate() as Node3D
	_instance.scale = Vector3.ONE * model_scale
	add_child(_instance)
	if apply_palette:
		KenneyPalette.apply(_instance)
	FlatMaterial.apply_fill(_instance)
	bounds = _measure(_instance, _instance.transform)
	_build_collision()
	if not Engine.is_editor_hint() and is_inside_tree():
		Lod.register(self)


## Merged AABB of every mesh under `node`, in this body's local space.
func _measure(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = xf * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var child_xf := xf * (child as Node3D).transform if child is Node3D else xf
		var box := _measure(child, child_xf)
		if box.size != Vector3.ZERO:
			result = box if not found else result.merge(box)
			found = true
	return result


func _build_collision() -> void:
	if collision_mode == CollisionMode.NONE or bounds.size == Vector3.ZERO:
		return
	_shape = CollisionShape3D.new()
	var centre := bounds.get_center()
	match collision_mode:
		CollisionMode.BOX:
			var box := BoxShape3D.new()
			box.size = bounds.size * Vector3(collision_shrink, 1.0, collision_shrink)
			_shape.shape = box
			_shape.position = centre
		CollisionMode.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = maxf(bounds.size.x, bounds.size.z) * 0.5 * collision_shrink
			cylinder.height = bounds.size.y
			_shape.shape = cylinder
			_shape.position = centre
		CollisionMode.TRUNK:
			var trunk := CylinderShape3D.new()
			trunk.radius = trunk_radius
			trunk.height = bounds.size.y * trunk_height_ratio
			_shape.shape = trunk
			_shape.position = Vector3(centre.x, bounds.position.y + trunk.height * 0.5, centre.z)
	add_child(_shape)
