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

@export var definition: VehicleDefinition
## Below this height the vehicle is considered fallen out of the world.
@export var fall_limit := -25.0

@onready var input: VehicleInput = $InputSource
@onready var motor: VehicleMotor = $Motor
@onready var health: HealthComponent = $Health
@onready var abilities: AbilityComponent = $Abilities
@onready var ability_nodes: Node = $AbilityNodes
@onready var visual_root: Node3D = $VisualRoot
@onready var collision: CollisionShape3D = $Collision

var driver: Node = null
var turbo: TurboAbility
var _visual_instance: Node3D
var _camera_reversed := false


func _ready() -> void:
	if definition == null:
		push_error("VehicleController '%s' has no VehicleDefinition assigned." % name)
		set_physics_process(false)
		return
	_apply_definition()


func _physics_process(delta: float) -> void:
	input.poll()

	var speed_multiplier := 1.0
	var acceleration_multiplier := 1.0
	if turbo:
		if input.turbo_pressed:
			turbo.try_activate()
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

	if global_position.y < fall_limit:
		fell_out_of_world.emit()


## The physics body stays an upright box; the model is a visual suspension:
## four rays at the wheel corners find the ground, pitch and roll come from
## the height differences and the model is lowered onto the average contact
## height, so the wheels sit on the terrain even where the box rests on an
## edge (crests, slope changes).
func _tilt_to_ground(delta: float) -> void:
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

	_spawn_visual()


func _spawn_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	if definition.visual_scene == null:
		return
	_visual_instance = definition.visual_scene.instantiate() as Node3D
	visual_root.add_child(_visual_instance)
