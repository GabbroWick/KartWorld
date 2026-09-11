class_name HitFlash
extends Node
## Blinks every mesh under `target` white for a moment: the universal "you
## hit it" cue. A material overlay, so the model's own materials are never
## touched. Component: add it under anything that gets hit and call `flash()`.

@export var target: NodePath = ^"../VisualRoot"
@export var duration := 0.09
@export var blinks := 2
@export var color := Color(1.0, 1.0, 1.0)

var is_flashing := false
var _material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = color
	_material.disable_receive_shadows = true


func flash() -> void:
	if is_flashing:
		return
	var root := get_node_or_null(target) as Node3D
	if root == null:
		return
	_meshes.clear()
	_collect(root)
	if _meshes.is_empty():
		return
	is_flashing = true
	_run()


func _run() -> void:
	for i in blinks:
		_set_overlay(_material)
		await get_tree().create_timer(duration).timeout
		_set_overlay(null)
		if i < blinks - 1:
			await get_tree().create_timer(duration * 0.6).timeout
	is_flashing = false


func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = material


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_collect(child)
