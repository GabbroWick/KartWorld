@tool
class_name MovingPlatform
extends AnimatableBody3D
## A block that glides back and forth between its start and start +
## `travel`, pausing `pause` seconds at each end. Characters and karts
## standing on it ride along (AnimatableBody3D with sync_to_physics).
##
## Level data, not animation: one node, size/colour/travel/period.

@export var size := Vector3(4.0, 0.6, 4.0):
	set(value):
		size = value
		_apply()
@export var color := Color(0.5, 0.45, 0.42):
	set(value):
		color = value
		_apply()
## Offset of the far end, relative to the start position.
@export var travel := Vector3(0.0, 0.0, -10.0)
## Seconds for one way.
@export_range(0.5, 30.0, 0.1) var period := 4.0
@export_range(0.0, 10.0, 0.1) var pause := 0.8
## Start somewhere along the cycle (0..1) so neighbours are out of step.
@export_range(0.0, 1.0, 0.01) var phase := 0.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var _start := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	sync_to_physics = true
	_apply()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_start = position
	_time = phase * (period + pause) * 2.0


func _physics_process(delta: float) -> void:
	_time += delta
	var cycle := (period + pause) * 2.0
	var t := fmod(_time, cycle)
	var f := 0.0
	if t < period:
		f = t / period
	elif t < period + pause:
		f = 1.0
	elif t < period * 2.0 + pause:
		f = 1.0 - (t - period - pause) / period
	else:
		f = 0.0
	# Ease in/out so riders are not jolted at the ends.
	f = 0.5 - 0.5 * cos(f * PI)
	position = _start + travel * f


func _apply() -> void:
	if not is_node_ready():
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = FlatMaterial.flat(color)
	mesh_instance.mesh = box
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
