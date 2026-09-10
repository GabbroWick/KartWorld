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


var _phase := 0.0
var _rest: Dictionary = {}

@onready var _leg_left: Node3D = get_node_or_null("LegLeft")
@onready var _leg_right: Node3D = get_node_or_null("LegRight")
@onready var _arm_left: Node3D = get_node_or_null("ArmLeft")
@onready var _arm_right: Node3D = get_node_or_null("ArmRight")
@onready var _tail: Node3D = get_node_or_null("Tail")
@onready var _body: Node3D = get_node_or_null("Body")
@onready var _head: Node3D = get_node_or_null("Head")


func _ready() -> void:
	_apply()
	for part in [_leg_left, _leg_right, _arm_left, _arm_right, _tail, _body, _head]:
		if part:
			_rest[part] = part.transform


## Procedural locomotion: called every physics tick by whoever owns the model.
## `speed_ratio` 0..1 (0 = standing), `grounded` false while in the air.
func animate(delta: float, speed_ratio: float, grounded: bool) -> void:
	if Engine.is_editor_hint() or _rest.is_empty():
		return
	_phase += delta * (4.0 + 10.0 * speed_ratio)
	var swing := sin(_phase) * 0.7 * speed_ratio
	var bob := absf(sin(_phase)) * 0.06 * speed_ratio
	if grounded:
		_pose(_leg_left, Vector3(swing, 0, 0), Vector3(0, -absf(swing) * 0.05, 0))
		_pose(_leg_right, Vector3(-swing, 0, 0), Vector3(0, -absf(swing) * 0.05, 0))
		_pose(_arm_left, Vector3(-swing * 0.8, 0, 0), Vector3.ZERO)
		_pose(_arm_right, Vector3(swing * 0.8, 0, 0), Vector3.ZERO)
	else:
		# Tucked legs, arms up: a happy little jump pose.
		_pose(_leg_left, Vector3(0.5, 0, 0), Vector3(0, 0.08, 0))
		_pose(_leg_right, Vector3(0.5, 0, 0), Vector3(0, 0.08, 0))
		_pose(_arm_left, Vector3(-2.2, 0, 0), Vector3.ZERO)
		_pose(_arm_right, Vector3(-2.2, 0, 0), Vector3.ZERO)
	_pose(_body, Vector3(0.12 * speed_ratio, 0, 0), Vector3(0, bob, 0))
	_pose(_head, Vector3(0, 0, sin(_phase * 0.5) * 0.05 * speed_ratio), Vector3(0, bob, 0))
	_pose(_tail, Vector3(0, sin(_phase * 0.7) * 0.5 * (0.4 + speed_ratio), 0), Vector3.ZERO)


func _pose(part: Node3D, euler: Vector3, offset: Vector3) -> void:
	if part == null or not _rest.has(part):
		return
	var rest: Transform3D = _rest[part]
	part.transform = Transform3D(rest.basis * Basis.from_euler(euler), rest.origin + offset)


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


func _material(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	return FlatMaterial.flat(color, roughness)
