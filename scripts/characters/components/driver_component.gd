class_name DriverComponent
extends Node
## Lets a character summon, enter and leave a vehicle.
##
## Lives on the character, not on the vehicle, so each player (local co-op
## later) has its own kart and its own "am I driving" state. While driving the
## character body is hidden, its physics paused and it is carried along at the
## vehicle's position so anything that asks "where is the player" still works.

signal vehicle_summoned(vehicle: VehicleController)
signal entered_vehicle(vehicle: VehicleController)
signal exited_vehicle(vehicle: VehicleController)

## Distance within which `interact` gets into the vehicle.
@export var enter_radius := 4.5
## How far in front of the character the vehicle appears when summoned.
@export var summon_distance := 3.5

var vehicle: VehicleController
var is_driving := false

var _character: CharacterController


func _ready() -> void:
	_character = get_parent() as CharacterController
	# Run after the character has polled its input this tick.
	process_physics_priority = 10


func _physics_process(_delta: float) -> void:
	if _character == null or vehicle == null:
		return
	if is_driving:
		_character.global_position = vehicle.global_position
		if vehicle.input.interact_pressed and not vehicle.is_submarine:
			exit_vehicle()
	else:
		if _character.input.summon_pressed:
			summon()
		elif _character.input.interact_pressed and is_vehicle_in_reach():
			enter_vehicle()


func set_vehicle(new_vehicle: VehicleController) -> void:
	if vehicle and vehicle.fell_out_of_world.is_connected(_on_vehicle_fell_out):
		vehicle.fell_out_of_world.disconnect(_on_vehicle_fell_out)
	vehicle = new_vehicle
	if vehicle:
		vehicle.fell_out_of_world.connect(_on_vehicle_fell_out)


func is_vehicle_in_reach() -> bool:
	return vehicle != null and not vehicle.is_driven() \
		and _character.global_position.distance_to(vehicle.global_position) <= enter_radius


## Brings the vehicle to the ground near the character: in front if there is
## room, otherwise closer or to a side. Never on a roof, never inside a wall.
func summon() -> void:
	if vehicle == null or is_driving:
		return
	var forward := -_character.visual_root.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)

	var candidates: Array[Vector3] = [
		forward * summon_distance,
		forward * (summon_distance * 0.7),
		right * summon_distance * 0.8,
		-right * summon_distance * 0.8,
		-forward * summon_distance * 0.8,
	]
	for offset in candidates:
		var spot := _character.global_position + offset
		var ground := _ground_height_at(spot)
		if is_nan(ground):
			continue
		spot.y = ground + 0.2
		if _is_spot_free(spot):
			vehicle.place(Transform3D(Basis.looking_at(forward, Vector3.UP), spot))
			vehicle_summoned.emit(vehicle)
			return
	# Nowhere sensible nearby: drop it right on the character's feet.
	vehicle.place(Transform3D(Basis.looking_at(forward, Vector3.UP), _character.global_position))
	vehicle_summoned.emit(vehicle)


func enter_vehicle() -> void:
	if vehicle == null or is_driving or vehicle.is_driven():
		return
	is_driving = true
	vehicle.mount(_character, _character.input.reads_local_device)
	_character.input.clear()
	_character.set_physics_process(false)
	_character.collision.disabled = true
	# The character stays visible: its visual rides on the kart's seat, the
	# (now empty) body is hidden.
	var visual := _character.get_visual()
	if visual:
		vehicle.seat_visual(visual)
		if visual.has_method(&"set_seated"):
			visual.call(&"set_seated", true)
	_character.visible = false
	entered_vehicle.emit(vehicle)


func exit_vehicle() -> void:
	if not is_driving:
		return
	is_driving = false
	var visual := vehicle.unseat_visual(_character.visual_root, _character.definition.visual_scale)
	if visual and visual.has_method(&"set_seated"):
		visual.call(&"set_seated", false)
	vehicle.dismount()
	_character.global_position = vehicle.get_exit_position()
	_character.visual_root.global_rotation.y = vehicle.global_rotation.y
	_character.motor.reset()
	_character.collision.disabled = false
	_character.visible = true
	_character.set_physics_process(true)
	exited_vehicle.emit(vehicle)


func _on_vehicle_fell_out() -> void:
	# Losing the kart in the sea should never strand the player: both come back
	# to the spawn point, kart parked beside it.
	if is_driving:
		exit_vehicle()
	_character.respawn()
	var spot := _character.spawn_transform
	spot.origin += spot.basis.x * 3.0
	vehicle.place(spot)


## Ground height under `point`, searching from just above the character's own
## height so a roof or a bridge overhead is never mistaken for the ground.
## NaN when there is no ground within reach (a cliff, the sea).
func _ground_height_at(point: Vector3) -> float:
	var space := _character.get_world_3d().direct_space_state
	var from := Vector3(point.x, _character.global_position.y + 1.2, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit.position as Vector3).y


## True when the vehicle's collision box would not overlap world geometry.
func _is_spot_free(spot: Vector3) -> bool:
	var space := _character.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = vehicle.definition.collision_size * 0.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY,
		spot + Vector3.UP * (vehicle.definition.collision_size.y * 0.5 + 0.15))
	query.collision_mask = 1
	return space.intersect_shape(query, 1).is_empty()
