class_name VehicleController
extends CharacterBody3D
## Generic drivable vehicle. The kart is one VehicleDefinition of it.
##
## A vehicle is its own entity in the world: it exists whether or not anyone
## is driving, and it is never a child of the character. A driver mounts it,
## input flows through VehicleInput, VehicleMotor moves the body, ability nodes
## under Abilities add behaviour (turbo today, more later).

signal driver_entered(driver: Node)
signal driver_exited(driver: Node)
signal fell_out_of_world
signal honked
signal submarine_changed(on: bool)
signal flying_changed(on: bool)

@export var definition: VehicleDefinition
## Below this height the vehicle is considered fallen out of the world.
@export var fall_limit := -25.0

@onready var input: VehicleInput = $InputSource
@onready var motor: VehicleMotor = $Motor
@onready var health: HealthComponent = $Health
@onready var abilities: AbilityComponent = $Abilities
@onready var ability_nodes: Node = $AbilityNodes
@onready var visual_root: Node3D = $VisualRoot
@onready var seat: Node3D = $VisualRoot/Seat
@onready var turbo_flames: CPUParticles3D = get_node_or_null("VisualRoot/TurboFlames")
@onready var collision: CollisionShape3D = $Collision

var driver: Node = null
var turbo: TurboAbility
var _seated: Node3D
var _visual_instance: Node3D
var _camera_reversed := false
var _terrain: IslandTerrain
var is_submarine := false
var _was_flying := false


func _ready() -> void:
	add_to_group(&"vehicle")
	motor.bumped.connect(_on_bumped)
	if definition == null:
		push_error("VehicleController '%s' has no VehicleDefinition assigned." % name)
		set_physics_process(false)
		return
	_apply_definition()


## Beep beep. NPC drivers may use it too.
func honk() -> void:
	Sfx.play(&"horn", -4.0)
	honked.emit()


func _on_bumped(_other: Node3D) -> void:
	Sfx.play(&"hit", -8.0)


func _physics_process(delta: float) -> void:
	# Parked on a streamed-out tile (the player walked far away): wait for
	# the ground to come back instead of falling through it, which would
	# "lose" the kart and drag the player back to the spawn.
	if driver == null and _is_ground_unloaded():
		velocity = Vector3.ZERO
		return
	input.poll()
	_check_water()

	var speed_multiplier := 1.0
	var acceleration_multiplier := 1.0
	if input.horn_pressed:
		honk()
	motor.has_wings = driver != null and driver is CharacterController and ProgressionManager.owns_upgrade(&"wings")
	if motor.is_flying != _was_flying:
		_was_flying = motor.is_flying
		if _visual_instance and _visual_instance.has_method(&"set_flying"):
			_visual_instance.call(&"set_flying", motor.is_flying)
		if motor.is_flying:
			Sfx.play(&"turbo", -10.0)
			var hud := get_tree().get_first_node_in_group(&"hud")
			if hud and hud.has_method(&"show_notice"):
				hud.call(&"show_notice", tr(&"HUD_FLYING"))
		flying_changed.emit(motor.is_flying)
	if turbo:
		turbo.set_boosting(input.turbo_held)
		speed_multiplier = turbo.get_speed_multiplier()
		acceleration_multiplier = turbo.get_acceleration_multiplier()
	for ability in ability_nodes.get_children():
		if ability is VehicleAbility:
			ability.tick(delta)

	motor.drive(delta, input.throttle, input.steer, input.jump_pressed,
		speed_multiplier, acceleration_multiplier)
	_tilt_to_ground(delta)
	if _visual_instance and _visual_instance.has_method(&"update_visual"):
		_visual_instance.call(&"update_visual", motor.speed, delta)
	_bump_bodies()
	if turbo_flames:
		turbo_flames.emitting = turbo != null and turbo.is_active
	if _visual_instance and _visual_instance.has_method(&"set_steer"):
		_visual_instance.call(&"set_steer", input.steer)
	# Seated driver leans into the steering and keeps its idle clip running.
	seat.rotation.z = lerp_angle(seat.rotation.z, -input.steer * definition.seat_lean, 8.0 * delta)
	if _seated and _seated.has_method(&"animate"):
		_seated.call(&"animate", delta, 0.0, true)

	if global_position.y < fall_limit:
		fell_out_of_world.emit()


## The physics collider is a small sphere (slopes); the body is a long
## box. So karts push each other apart at the box, not at the sphere: two
## discs per kart (front and rear axle) repel the discs of every kart in
## the "npc_kart" / player group that overlaps them. Also keeps walkers
## from being run through.
const BUMPER_RADIUS := 0.8
const BUMPER_AXLE := 0.7
const BUMPER_PUSH := 0.6
const BUMPER_STEP := 0.12

func _bumper_points() -> Array[Vector3]:
	var forward := -global_basis.z
	return [global_position + forward * BUMPER_AXLE, global_position - forward * BUMPER_AXLE]


func _bump_bodies() -> void:
	var mine := _bumper_points()
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var other := node as VehicleController
		if other == null or other == self or not other.is_physics_processing():
			continue
		if other.global_position.distance_squared_to(global_position) > 25.0:
			continue
		var theirs := other._bumper_points()
		var push := Vector3.ZERO
		for a in mine:
			for b in theirs:
				var d := a - b
				d.y = 0.0
				var dist := d.length()
				var overlap := BUMPER_RADIUS * 2.0 - dist
				if overlap > 0.0:
					var dir := d.normalized() if dist > 0.001 else -global_basis.z
					push += dir * overlap
		if push.length_squared() > 0.0:
			# Each kart moves itself out of the overlap (the other does the
			# same in its own tick) plus a small knock so the hit is felt.
			global_position += push.limit_length(BUMPER_STEP) * 0.5
			motor.shove(push * BUMPER_PUSH)


## Water: over deep ground below the surface the kart becomes a
## submarine (cockpit closes, propellers out); back over the beach it is
## a kart again. NPC karts on gliding tiles never get here.
func _check_water() -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
		if _terrain == null:
			return
	var ground := _terrain.sample_height(global_position.x, global_position.z)
	var surface := _terrain.water_level
	motor.ground_height_hint = maxf(ground, surface)
	if motor.is_flying:
		# Flying over the sea: only splash down when the hull touches it.
		if ground < surface - 1.2 and global_position.y < surface - 0.2 and not is_submarine:
			motor.is_flying = false
			set_submarine(true)
		return
	var want := ground < surface - 1.2 and global_position.y < surface + 0.6 if not is_submarine \
		else ground < surface - 0.4
	if want != is_submarine:
		set_submarine(want)


func is_flying() -> bool:
	return motor.is_flying


func set_submarine(on: bool) -> void:
	if on == is_submarine:
		return
	is_submarine = on
	if on:
		motor.is_flying = false
	motor.set_submarine(on, _terrain.water_level if _terrain else 0.0)
	if _visual_instance and _visual_instance.has_method(&"set_submarine"):
		_visual_instance.call(&"set_submarine", on)
	if on:
		Sfx.play(&"portal", -6.0)
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and driver != null and hud.has_method(&"show_notice"):
			hud.call(&"show_notice", tr(&"HUD_SUBMARINE"))
	submarine_changed.emit(on)


func _is_ground_unloaded() -> bool:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
		if _terrain == null:
			return false
	return _terrain.streaming and not _terrain.is_built_at(global_position.x, global_position.z)


## The physics body stays an upright box; the model is a visual suspension:
## four rays at the wheel corners find the ground, pitch and roll come from
## the height differences and the model is lowered onto the average contact
## height, so the wheels sit on the terrain even where the box rests on an
## edge (crests, slope changes).
func _tilt_to_ground(delta: float) -> void:
	if motor.is_flying:
		# Nose follows the flight pitch (loops included), bank with the steering.
		var target := Basis.from_euler(Vector3(motor.fly_pitch, 0.0, -input.steer * 0.45))
		visual_root.basis = visual_root.basis.slerp(target, minf(8.0 * delta, 1.0))
		visual_root.position.y = lerpf(visual_root.position.y, 0.0, minf(4.0 * delta, 1.0))
		return
	if is_submarine:
		# Afloat: a gentle bob and roll with the waves instead of the rays.
		var t := Time.get_ticks_msec() / 1000.0
		var bob := Basis.from_euler(Vector3(sin(t * 1.3) * 0.03, 0.0, sin(t * 0.9) * 0.04))
		visual_root.basis = visual_root.basis.slerp(bob, minf(3.0 * delta, 1.0))
		visual_root.position.y = lerpf(visual_root.position.y, sin(t * 1.1) * 0.06, minf(3.0 * delta, 1.0))
		return
	var size := definition.collision_size
	var half_w := size.x * 0.45
	var half_l := size.z * 0.42
	var corners: Array[Vector3] = [
		Vector3(-half_w, 0.0, -half_l), Vector3(half_w, 0.0, -half_l),
		Vector3(-half_w, 0.0, half_l), Vector3(half_w, 0.0, half_l),
	]
	var space := get_world_3d().direct_space_state
	var heights: Array[float] = []
	for corner: Vector3 in corners:
		# Start high: on a steep climb the front corners' ground is above the body.
		var origin := global_transform * (corner + Vector3.UP * (size.y + 2.5))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * (size.y + 5.5), 1)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			heights.append(NAN)
		else:
			heights.append((hit.position as Vector3).y - global_position.y)

	var target_basis := Basis.IDENTITY
	var target_y := 0.0
	var grounded := heights.all(func(h: float) -> bool: return not is_nan(h))
	if grounded and is_on_floor():
		var front := (heights[0] + heights[1]) * 0.5
		var back := (heights[2] + heights[3]) * 0.5
		var left := (heights[0] + heights[2]) * 0.5
		var right := (heights[1] + heights[3]) * 0.5
		var pitch := atan2(front - back, half_l * 2.0)
		# +Z rotation lifts the right side, so a higher left means negative roll.
		var roll := atan2(right - left, half_w * 2.0)
		target_basis = Basis.from_euler(Vector3(pitch, 0.0, roll))
		var mean := (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25
		target_y = clampf(mean, -0.9, 0.6)
	var weight := minf(definition.tilt_speed * delta, 1.0)
	visual_root.basis = visual_root.basis.slerp(target_basis, weight)
	visual_root.position.y = lerpf(visual_root.position.y, target_y, weight)


func is_driven() -> bool:
	return driver != null


## Puts `new_driver` at the wheel. The driver decides what happens to its own
## body (hide, disable physics); the vehicle only takes over input.
func mount(new_driver: Node, local_device: bool) -> void:
	if driver != null:
		return
	driver = new_driver
	input.clear()
	input.reads_local_device = local_device
	driver_entered.emit(driver)


func dismount() -> Node:
	if driver == null:
		return null
	var leaving := driver
	driver = null
	input.clear()
	input.reads_local_device = false
	motor.reset()
	driver_exited.emit(leaving)
	return leaving


## World position where a leaving driver should stand.
func get_exit_position() -> Vector3:
	return global_transform * definition.exit_offset


## Teleports the vehicle to a new place, at rest.
func place(at: Transform3D) -> void:
	global_transform = at
	motor.reset()
	_camera_reversed = false
	if turbo:
		turbo.reset()


func get_speed() -> float:
	return motor.speed


## Yaw the camera should settle on: behind the kart when going forward, in
## front of it (looking at the tail) when reversing. Hysteresis so the view
## does not flip back and forth around a standstill.
func get_heading_yaw() -> float:
	# Front view only while actually reversing; at a standstill go back behind.
	if _camera_reversed and motor.speed > -0.3:
		_camera_reversed = false
	elif not _camera_reversed and motor.speed < -1.0:
		_camera_reversed = true
	return global_rotation.y + (PI if _camera_reversed else 0.0)


## Parks a character's visual on the seat (driver stays visible). The
## visual keeps animating through `animate()` from the vehicle's speed.
func seat_visual(visual: Node3D) -> void:
	if visual.get_parent():
		visual.get_parent().remove_child(visual)
	seat.add_child(visual)
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	visual.scale = Vector3.ONE * definition.seat_scale
	_seated = visual


## Returns the seated visual to `parent` (or frees nothing if none).
func unseat_visual(parent: Node3D, scale: float) -> Node3D:
	var visual := _seated
	_seated = null
	if visual == null:
		return null
	seat.remove_child(visual)
	parent.add_child(visual)
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	visual.scale = Vector3.ONE * scale
	return visual


func _apply_definition() -> void:
	abilities.setup(definition.starting_abilities)
	health.setup(definition.max_health)
	motor.setup(self, definition, abilities)

	# A sphere, not a box: a box on a steep slope rests on its front edge well
	# above the ground and stalls, a sphere just rolls on and up. The visual
	# suspension makes the model sit on the terrain regardless.
	var sphere := SphereShape3D.new()
	sphere.radius = definition.collision_size.y * 0.75
	collision.shape = sphere
	collision.position.y = sphere.radius

	for ability in ability_nodes.get_children():
		if ability is VehicleAbility:
			ability.setup(self)
			if ability is TurboAbility:
				turbo = ability

	seat.position = definition.seat_offset
	_spawn_visual()


func _spawn_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	if definition.visual_scene == null:
		return
	_visual_instance = definition.visual_scene.instantiate() as Node3D
	visual_root.add_child(_visual_instance)
