class_name KenneyVehicleVisual
extends Node3D
## Wraps a Kenney Car Kit model as a vehicle visual: instantiates it and spins
## every node whose name starts with "wheel" according to the vehicle's speed.
##
## VehicleController calls `update_visual(speed, delta)` each tick when the
## visual offers it; any future model with the same call works unchanged.

@export var model: PackedScene
## Kenney cars face +Z; our vehicles drive toward -Z.
@export var flip_forward := true
@export_range(0.05, 2.0, 0.01) var wheel_radius := 0.3

var _wheels: Array[Node3D] = []
var _instance: Node3D


func _ready() -> void:
	if model == null:
		return
	_instance = model.instantiate() as Node3D
	if flip_forward:
		_instance.rotation.y = PI
	add_child(_instance)
	FlatMaterial.apply_fill(_instance)
	_collect_wheels(_instance)


func _collect_wheels(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and String(child.name).begins_with("wheel"):
			_wheels.append(child)
		_collect_wheels(child)


func update_visual(speed: float, delta: float) -> void:
	if _wheels.is_empty():
		return
	var angle := speed / wheel_radius * delta
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, -angle)
