class_name MeshyCharacterVisual
extends Node3D
## Wraps an AI-generated character model (Meshy .glb) as a character visual.
##
## Implements the same `animate(delta, speed_ratio, grounded)` contract as the
## primitive placeholder, so CharacterController never knows which one it has.
## A static (unrigged) model gets whole-body procedural motion: a walk bob,
## a forward lean with speed, a stretch in the air and a squash on landing.
## A rigged model with animations can override `animate()` in a subclass and
## drive an AnimationTree instead.
##
## Meshy exports are centred on the origin with PBR materials; this puts the
## feet on the ground, turns the model to face -Z and flattens the material
## for the cartoon look (no metallic, no normal map) on the Compatibility
## renderer, which has no reflections to make metal read as anything but dark.

@export var model: PackedScene
## Applied before measuring. Mixamo re-exports come back in centimetres
## (100x too small in Godot); Meshy GLBs are already in metres.
@export_range(0.01, 200.0, 0.01) var model_scale := 1.0
## Meshy models face +Z; our characters face -Z.
@export var flip_forward := true
## Lift the model so its bind-pose bounds touch the ground. Off for rigged
## models whose clips already keep the feet at y = 0 (Mixamo).
@export var auto_ground := true
## Metallic 0 / roughness 1 / no normal map: matches the flat Kenney props.
@export var flatten_materials := true
## Procedural motion strength (0 = static model).
@export_range(0.0, 2.0, 0.05) var motion := 1.0

var _pivot: Node3D
var _instance: Node3D
var _phase := 0.0
var _was_grounded := true
var _squash := 0.0


func _ready() -> void:
	if model == null:
		return
	_pivot = Node3D.new()
	add_child(_pivot)
	_instance = model.instantiate() as Node3D
	_pivot.add_child(_instance)
	_instance.scale = Vector3.ONE * model_scale
	if flip_forward:
		_instance.rotation.y = PI
	var bounds := _measure(_instance, _instance.transform)
	# Feet on the ground, centred on the character's axis.
	if auto_ground:
		_instance.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	if flatten_materials:
		_flatten(_instance)


func animate(delta: float, speed_ratio: float, grounded: bool) -> void:
	if _pivot == null or motion <= 0.0:
		return
	_phase += delta * (3.0 + 11.0 * speed_ratio)
	if grounded and not _was_grounded:
		_squash = 1.0
	_was_grounded = grounded
	_squash = maxf(_squash - delta * 5.0, 0.0)

	var bob := absf(sin(_phase)) * 0.05 * speed_ratio * motion
	var lean := 0.18 * speed_ratio * motion
	var scale_y := 1.0
	var scale_xz := 1.0
	if not grounded:
		scale_y = 1.0 + 0.08 * motion
		scale_xz = 1.0 - 0.05 * motion
	elif _squash > 0.0:
		scale_y = 1.0 - 0.18 * _squash * motion
		scale_xz = 1.0 + 0.10 * _squash * motion
	_pivot.position.y = bob
	_pivot.rotation.x = -lean
	_pivot.rotation.z = sin(_phase * 0.5) * 0.03 * speed_ratio * motion
	_pivot.scale = Vector3(scale_xz, scale_y, scale_xz)


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


func _flatten(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if material == null:
				continue
			var flat := material.duplicate() as StandardMaterial3D
			flat.metallic = 0.0
			flat.metallic_texture = null
			flat.roughness = 1.0
			flat.roughness_texture = null
			flat.normal_enabled = false
			flat.metallic_specular = 0.0
			mesh_instance.set_surface_override_material(i, flat)
