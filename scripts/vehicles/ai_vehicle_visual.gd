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

## Wings: two panels that swing out of the sides when flying.
var _wings: Array[Node3D] = []
var _exhausts: Array[CPUParticles3D] = []
var _pylons: Array[MeshInstance3D] = []
var _fin: Node3D
var _fly_amount := 0.0
var _flying := false


static func _jet_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = FlatMaterial.flat(color)
	m.mesh = box
	return m


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


## Everything bolted on (canopy, propellers, wings, fin, turbines) hangs
## from `_kit`: the model instance is turned 180 deg (Kenney/AI karts face
## +Z), so inside it +Z is the kart's FRONT. The kit is turned back, so
## in kit space +Z is the rear again and the parts are designed naturally.
var _kit: Node3D


func _build_submarine_parts() -> void:
	_kit = Node3D.new()
	_kit.name = "Kit"
	_kit.rotation.y = PI
	_instance.add_child(_kit)
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
	_kit.add_child(_canopy)
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
		_kit.add_child(pivot)
		_props.append(pivot)
	# Jet kit: swept delta wings with red winglets, a tail fin, and two
	# turbines under the wings whose nozzles glow and trail fire in flight.
	var body_color := Color(0.85, 0.9, 1.0)
	var accent := Color(0.95, 0.35, 0.28)
	var dark := Color(0.28, 0.3, 0.36)
	for side in [-1.0, 1.0]:
		# A pylon fixed to the body side carries the folding wing.
		var pylon := _jet_box(Vector3(0.14, 0.12, 0.7), dark)
		pylon.position = Vector3(side * 0.47, 0.4, 0.15)
		pylon.visible = false
		_kit.add_child(pylon)
		_pylons.append(pylon)
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.5, 0.42, 0.15)
		# Swept wing: a wide root panel and a narrower, further-back tip panel.
		var root_panel := _jet_box(Vector3(0.55, 0.035, 0.55), body_color)
		root_panel.position = Vector3(side * 0.24, 0.0, 0.05)
		root_panel.rotation.y = side * deg_to_rad(-18.0)
		pivot.add_child(root_panel)
		var tip_panel := _jet_box(Vector3(0.6, 0.03, 0.34), body_color)
		tip_panel.position = Vector3(side * 0.8, 0.0, 0.2)
		tip_panel.rotation.y = side * deg_to_rad(-24.0)
		pivot.add_child(tip_panel)
		var stripe := _jet_box(Vector3(0.62, 0.036, 0.06), accent)
		stripe.position = Vector3(side * 0.8, 0.0, 0.05)
		stripe.rotation.y = side * deg_to_rad(-24.0)
		pivot.add_child(stripe)
		var winglet := _jet_box(Vector3(0.04, 0.2, 0.26), accent)
		winglet.position = Vector3(side * 1.1, 0.1, 0.32)
		winglet.rotation.z = side * deg_to_rad(-15.0)
		pivot.add_child(winglet)
		# Turbine under the wing: casing, intake ring, glowing nozzle.
		var engine := Node3D.new()
		engine.position = Vector3(side * 0.55, -0.16, 0.25)
		var casing := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.12
		cm.height = 0.5
		cm.radial_segments = 12
		cm.material = FlatMaterial.flat(dark)
		casing.mesh = cm
		casing.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		engine.add_child(casing)
		var intake := MeshInstance3D.new()
		var im := TorusMesh.new()
		im.inner_radius = 0.09
		im.outer_radius = 0.14
		im.rings = 12
		im.ring_segments = 8
		im.material = FlatMaterial.flat(body_color)
		intake.mesh = im
		intake.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		intake.position.z = -0.25
		engine.add_child(intake)
		var nozzle := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.09
		nm.bottom_radius = 0.07
		nm.height = 0.08
		nm.radial_segments = 12
		var glow := FlatMaterial.flat(Color(1.0, 0.55, 0.15))
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.45, 0.1)
		glow.emission_energy_multiplier = 1.6
		nm.material = glow
		nozzle.mesh = nm
		nozzle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		nozzle.position.z = 0.28
		engine.add_child(nozzle)
		var exhaust := CPUParticles3D.new()
		exhaust.emitting = false
		exhaust.amount = 40
		exhaust.lifetime = 0.28
		var em := QuadMesh.new()
		em.size = Vector2(0.1, 0.1)
		var flame := StandardMaterial3D.new()
		flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.vertex_color_use_as_albedo = true
		flame.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		em.material = flame
		exhaust.mesh = em
		exhaust.position.z = 0.34
		exhaust.direction = Vector3(0.0, 0.0, 1.0)
		exhaust.spread = 8.0
		exhaust.gravity = Vector3.ZERO
		exhaust.initial_velocity_min = 4.0
		exhaust.initial_velocity_max = 6.0
		exhaust.scale_amount_min = 0.5
		exhaust.scale_amount_max = 1.2
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		ramp.colors = PackedColorArray([Color(0.6, 0.85, 1.0, 1.0), Color(1.0, 0.6, 0.15, 0.9), Color(0.5, 0.1, 0.05, 0.0)])
		exhaust.color_ramp = ramp
		engine.add_child(exhaust)
		_exhausts.append(exhaust)
		pivot.add_child(engine)
		pivot.scale = Vector3(0.001, 1.0, 1.0)
		pivot.visible = false
		_kit.add_child(pivot)
		_wings.append(pivot)
	# Tail fin behind the seat.
	_fin = Node3D.new()
	_fin.position = Vector3(0.0, 0.62, 0.72)
	var fin_panel := _jet_box(Vector3(0.035, 0.34, 0.3), body_color)
	fin_panel.position = Vector3(0.0, 0.17, 0.05)
	fin_panel.rotation.x = deg_to_rad(-28.0)
	_fin.add_child(fin_panel)
	var fin_stripe := _jet_box(Vector3(0.04, 0.1, 0.32), accent)
	fin_stripe.position = Vector3(0.0, 0.3, 0.05)
	fin_stripe.rotation.x = deg_to_rad(-28.0)
	_fin.add_child(fin_stripe)
	_fin.scale = Vector3(1.0, 0.001, 1.0)
	_fin.visible = false
	_kit.add_child(_fin)
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
	_kit.add_child(_bubbles)


## Wings out (flying) or folded away.
func set_flying(on: bool) -> void:
	_flying = on
	for wing in _wings:
		wing.visible = true
	for pylon in _pylons:
		pylon.visible = true
	if _fin:
		_fin.visible = true
	# The cockpit closes in the air like it does at sea.
	_canopy.visible = true


func is_flying() -> bool:
	return _flying


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
	var canopy_amount := maxf(_sub_amount, _fly_amount)
	_canopy.scale = Vector3.ONE * maxf(smoothstep(0.0, 1.0, canopy_amount), 0.001)
	_canopy.visible = canopy_amount > 0.0
	if _sub_amount != before or _submarine:
		var t := smoothstep(0.0, 1.0, _sub_amount)
		for pivot in _props:
			pivot.position.z = lerpf(0.75, 1.15, t)
			var blades := pivot.get_node("Blades") as Node3D
			blades.rotate_z((absf(_speed) * 2.0 + (3.0 if _submarine else 0.0)) * delta)
		if _sub_amount <= 0.0:
			for pivot in _props:
				pivot.visible = false
	if _bubbles:
		_bubbles.emitting = _submarine and absf(_speed) > 1.0
	var fly_before := _fly_amount
	_fly_amount = move_toward(_fly_amount, 1.0 if _flying else 0.0, delta * 3.0)
	if _fly_amount != fly_before or _flying:
		var t := smoothstep(0.0, 1.0, _fly_amount)
		var i := 0
		for wing in _wings:
			var side := -1.0 if i == 0 else 1.0
			wing.scale = Vector3(maxf(t, 0.001), 1.0, 1.0)
			# Folded up along the body when stowed; bank into the steering.
			wing.rotation.z = side * (1.2 * (1.0 - t)) - _steer * 0.2 * t
			i += 1
		if _fin:
			_fin.scale = Vector3(1.0, maxf(t, 0.001), 1.0)
		for exhaust in _exhausts:
			exhaust.emitting = _flying and t > 0.6
		if _fly_amount <= 0.0:
			for wing in _wings:
				wing.visible = false
			for pylon in _pylons:
				pylon.visible = false
			if _fin:
				_fin.visible = false


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
