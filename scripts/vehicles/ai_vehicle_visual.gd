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

## Submarine dressing: a glass canopy over the seat, two propellers that
## slide out of the back, bubbles while moving.
var _canopy: MeshInstance3D
var _props: Array[Node3D] = []
var _bubbles: CPUParticles3D
var _sub_amount := 0.0
var _submarine := false
var _speed := 0.0


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
	_build_submarine_parts()


func _build_submarine_parts() -> void:
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 0.55
	canopy_mesh.height = 0.8
	canopy_mesh.radial_segments = 16
	canopy_mesh.rings = 8
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
	glass.metallic_specular = 0.2
	glass.roughness = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy_mesh.material = glass
	_canopy = MeshInstance3D.new()
	_canopy.mesh = canopy_mesh
	_canopy.position = Vector3(0.0, 0.62, 0.15)   # over the seat (model units)
	_canopy.scale = Vector3(0.001, 0.001, 0.001)
	_canopy.visible = false
	_instance.add_child(_canopy)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.22, 0.22, 0.75)   # rear, retracted
		var shaft := MeshInstance3D.new()
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.03
		shaft_mesh.bottom_radius = 0.03
		shaft_mesh.height = 0.3
		shaft_mesh.material = FlatMaterial.flat(Color(0.3, 0.3, 0.32))
		shaft.mesh = shaft_mesh
		shaft.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		shaft.position.z = 0.15
		pivot.add_child(shaft)
		var blades := Node3D.new()
		blades.name = "Blades"
		blades.position.z = 0.32
		for k in 3:
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.28, 0.02)
			bm.material = FlatMaterial.flat(Color(0.95, 0.8, 0.2))
			blade.mesh = bm
			blade.position.y = 0.12
			var holder := Node3D.new()
			holder.rotation_degrees = Vector3(0.0, 0.0, 120.0 * k)
			holder.add_child(blade)
			blades.add_child(holder)
		pivot.add_child(blades)
		pivot.visible = false
		_instance.add_child(pivot)
		_props.append(pivot)
	_bubbles = CPUParticles3D.new()
	_bubbles.emitting = false
	_bubbles.amount = 30
	_bubbles.lifetime = 1.2
	var bubble := SphereMesh.new()
	bubble.radius = 0.05
	bubble.height = 0.1
	bubble.radial_segments = 6
	bubble.rings = 3
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	bubble.material = bubble_mat
	_bubbles.mesh = bubble
	_bubbles.position = Vector3(0.0, 0.2, 0.9)
	_bubbles.direction = Vector3(0.0, 1.0, 1.0)
	_bubbles.spread = 25.0
	_bubbles.gravity = Vector3(0.0, 1.5, 0.0)
	_bubbles.initial_velocity_min = 1.0
	_bubbles.initial_velocity_max = 2.5
	_instance.add_child(_bubbles)


## Kart <-> submarine. The parts animate in `_process`.
func set_submarine(on: bool) -> void:
	_submarine = on
	_canopy.visible = true
	for pivot in _props:
		pivot.visible = true


func is_submarine() -> bool:
	return _submarine


func _process(delta: float) -> void:
	if _canopy == null:
		return
	var before := _sub_amount
	_sub_amount = move_toward(_sub_amount, 1.0 if _submarine else 0.0, delta * 2.0)
	if _sub_amount != before or _submarine:
		var t := smoothstep(0.0, 1.0, _sub_amount)
		_canopy.scale = Vector3.ONE * maxf(t, 0.001)
		for pivot in _props:
			pivot.position.z = lerpf(0.75, 1.15, t)
			var blades := pivot.get_node("Blades") as Node3D
			blades.rotate_z((absf(_speed) * 2.0 + (3.0 if _submarine else 0.0)) * delta)
		if _sub_amount <= 0.0:
			_canopy.visible = false
			for pivot in _props:
				pivot.visible = false
	if _bubbles:
		_bubbles.emitting = _submarine and absf(_speed) > 1.0


## Steering input -1..1 from the controller (front wheels yaw with it).
func set_steer(steer: float) -> void:
	_steer = steer


func update_visual(speed: float, delta: float) -> void:
	super.update_visual(speed, delta)
	_speed = speed
	if _spinners.is_empty() or _submarine:
		return
	# Rolling forward: the model faces +Z inside the flipped instance, so a
	# point on top of the tyre must move toward +Z = positive rotation about +X.
	var angle := speed / (wheel_radius * model_scale) * delta
	for spin in _spinners:
		spin.rotate_object_local(Vector3.RIGHT, angle)
	var yaw := -_steer * deg_to_rad(steer_degrees)
	for hub in _steerers:
		hub.rotation.y = lerp_angle(hub.rotation.y, yaw, 10.0 * delta)
