class_name AiVehicleVisual
extends KenneyVehicleVisual
## An AI-generated kart (tools/blender/split_wheels.py output): the body is
## the model, the wheels are rebuilt as clean procedural tyres at the hub
## nodes, because the mesh chunks the splitter cuts out are lumpy. The
## front wheels yaw with the steering; every wheel rolls with the speed.
##
## Hub nodes are found by name (Wheel_*); "Wheel_F*" steer.

@export var procedural_wheels := true
## Tyre width in model units (before `model_scale`).
@export_range(0.05, 1.0, 0.01) var wheel_width := 0.2
@export var tyre_color := Color(0.1, 0.1, 0.11)
@export var hub_color := Color(0.95, 0.8, 0.2)
@export_range(0.0, 60.0, 1.0) var steer_degrees := 28.0

var _spinners: Array[Node3D] = []
var _steerers: Array[Node3D] = []
var _steer := 0.0


func _ready() -> void:
	super()
	if _instance == null or not procedural_wheels:
		return
	for hub in _wheels:
		for child in hub.get_children():
			if child is VisualInstance3D:
				(child as VisualInstance3D).visible = false
		var spin := Node3D.new()
		spin.name = "Spin"
		hub.add_child(spin)
		var tyre := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_radius
		cyl.bottom_radius = wheel_radius
		cyl.height = wheel_width
		cyl.radial_segments = 20
		cyl.material = FlatMaterial.flat(tyre_color)
		tyre.mesh = cyl
		tyre.rotation_degrees = Vector3(0.0, 0.0, 90.0)   # axle along X
		spin.add_child(tyre)
		var cap := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = wheel_radius * 0.55
		disc.bottom_radius = wheel_radius * 0.55
		disc.height = wheel_width * 1.08
		disc.radial_segments = 12
		disc.material = FlatMaterial.flat(hub_color)
		cap.mesh = disc
		cap.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		spin.add_child(cap)
		_spinners.append(spin)
		if String(hub.name).to_lower().begins_with("wheel_f"):
			_steerers.append(hub)
	# The base class spins the hubs themselves; we spin the inner node.
	_wheels.clear()


## Steering input -1..1 from the controller (front wheels yaw with it).
func set_steer(steer: float) -> void:
	_steer = steer


func update_visual(speed: float, delta: float) -> void:
	super.update_visual(speed, delta)
	if _spinners.is_empty():
		return
	# Rolling forward: the model faces +Z inside the flipped instance, so a
	# point on top of the tyre must move toward +Z = positive rotation about +X.
	var angle := speed / (wheel_radius * model_scale) * delta
	for spin in _spinners:
		spin.rotate_object_local(Vector3.RIGHT, angle)
	var yaw := -_steer * deg_to_rad(steer_degrees)
	for hub in _steerers:
		hub.rotation.y = lerp_angle(hub.rotation.y, yaw, 10.0 * delta)
