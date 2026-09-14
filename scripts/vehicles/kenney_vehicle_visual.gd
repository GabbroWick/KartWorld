class_name KenneyVehicleVisual
extends Node3D
## Wraps a car model (Kenney Car Kit or an AI kart split by
## tools/blender/split_wheels.py) as a vehicle visual: instantiates it and
## spins every node whose name starts with "wheel" (any case) with the speed.
##
## VehicleController calls `update_visual(speed, delta)` each tick when the
## visual offers it; any future model with the same call works unchanged.

@export var model: PackedScene
## Kenney cars face +Z; our vehicles drive toward -Z.
@export var flip_forward := true
@export_range(0.05, 2.0, 0.01) var wheel_radius := 0.3
## Uniform scale of the model (AI karts are 1 m tall; the game kart is ~1.6 m).
@export_range(0.1, 5.0, 0.01) var model_scale := 1.0

var _wheels: Array[Node3D] = []
var _instance: Node3D


func _ready() -> void:
	if model == null:
		return
	_instance = model.instantiate() as Node3D
	if flip_forward:
		_instance.rotation.y = PI
	_instance.scale = Vector3.ONE * model_scale
	add_child(_instance)
	FlatMaterial.apply_fill(_instance)
	_collect_wheels(_instance)


func _collect_wheels(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and String(child.name).to_lower().begins_with("wheel"):
			_wheels.append(child)
		_collect_wheels(child)


func update_visual(speed: float, delta: float) -> void:
	if _wheels.is_empty():
		return
	var angle := speed / (wheel_radius * model_scale) * delta
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, -angle)
