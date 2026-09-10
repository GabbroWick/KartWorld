@tool
class_name CreaturePlaceholder
extends Node3D
## One primitive creature body reused by every placeholder character.
##
## The geometry is shared; each character variant is the same scene with
## different colours (see scenes/characters/visuals/*.tscn). This is throwaway
## art, but it is what proves the character system is not built around one
## specific animal.
##
## Mesh nodes declare their role with a group: creature_fur, creature_belly,
## creature_accent, creature_eye. Nodes in creature_spot can be hidden entirely.

const GROUP_FUR := &"creature_fur"
const GROUP_BELLY := &"creature_belly"
const GROUP_ACCENT := &"creature_accent"
const GROUP_EYE := &"creature_eye"
const GROUP_SPOT := &"creature_spot"

@export var fur_color := Color(0.93, 0.66, 0.28):
	set(value):
		fur_color = value
		_apply()
@export var belly_color := Color(0.98, 0.93, 0.82):
	set(value):
		belly_color = value
		_apply()
@export var accent_color := Color(0.32, 0.2, 0.12):
	set(value):
		accent_color = value
		_apply()
@export var eye_color := Color(0.08, 0.07, 0.07):
	set(value):
		eye_color = value
		_apply()
@export var show_spots := true:
	set(value):
		show_spots = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var materials := {
		GROUP_FUR: _material(fur_color),
		GROUP_BELLY: _material(belly_color),
		GROUP_ACCENT: _material(accent_color),
		GROUP_EYE: _material(eye_color, 0.4),
	}
	_paint(self, materials)


func _paint(node: Node, materials: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if child.is_in_group(GROUP_SPOT):
				child.visible = show_spots
			for group: StringName in materials:
				if child.is_in_group(group):
					child.set_surface_override_material(0, materials[group])
					break
		_paint(child, materials)


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
