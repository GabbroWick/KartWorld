class_name VehicleMotor
extends Node
## Arcade driving physics for a CharacterBody3D vehicle.
##
## Not a wheel simulation: a signed forward speed, a yaw rate that depends on
## speed, gravity and a jump. Walls kill the speed component they block. It
## knows nothing about input devices, drivers or cameras. Values come from a
## VehicleDefinition.

signal jumped
signal landed(impact_speed: float)

var body: CharacterBody3D
var definition: VehicleDefinition
var abilities: AbilityComponent

## Smoothed ground normal the body is aligned to. An upright box on a steep
## slope rests on its front edge, metres above the ground, and stalls; a box
## that lies flat on the slope climbs it and reads as driving on it.
var ground_up := Vector3.UP
## Yaw of the vehicle, radians. Steering changes this and the basis is built
## from it every tick: deriving yaw back from a tilted basis drifts.
var heading := 0.0
var _jumped := false

## Signed speed along the vehicle's forward axis (m/s). Negative = reversing.
var speed := 0.0

var _base_gravity := 26.0


func setup(vehicle_body: CharacterBody3D, vehicle_definition: VehicleDefinition,
		ability_component: AbilityComponent) -> void:
	body = vehicle_body
	definition = vehicle_definition
	abilities = ability_component
	_base_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))
	body.floor_snap_length = 0.8
	body.floor_stop_on_slope = true
	body.floor_max_angle = deg_to_rad(definition.max_slope_degrees)
	# Keep the same ground speed up and down hills (arcade, not physics).
	body.floor_constant_speed = true


func drive(delta: float, throttle: float, steer: float, jump_requested: bool,
		speed_multiplier: float = 1.0, acceleration_multiplier: float = 1.0) -> void:
	var was_on_floor := body.is_on_floor()

	_apply_throttle(delta, throttle, speed_multiplier, acceleration_multiplier)
	_apply_steering(delta, steer, was_on_floor)
	_apply_vertical(delta, was_on_floor, jump_requested)

	_align_to_ground(delta, was_on_floor)
	var forward := -body.global_basis.z
	if was_on_floor and not _jumped:
		# Drive along the slope plane, pressed onto it so a crest or a kerb
		# never lifts the box off the floor for a frame.
		body.velocity = forward * speed - ground_up * 2.0
	else:
		body.velocity.x = forward.x * speed
		body.velocity.z = forward.z * speed
	# On a slope the plane velocity points slightly up; kerbs still count.
	if was_on_floor and not _jumped:
		StepUp.try_step(body, Vector3(body.velocity.x, 0.0, body.velocity.z) * delta,
			definition.max_step_height)
	body.move_and_slide()

	# Whatever a wall or a bump took away is gone; this is what stops the kart
	# when it drives into the house.
	# `forward` lies in the slope plane on the ground and is flat in the air,
	# so this keeps the full speed on hills instead of the horizontal share.
	speed = body.velocity.dot(forward)
	_jumped = false

	if not was_on_floor and body.is_on_floor():
		landed.emit(absf(body.velocity.y))


func reset() -> void:
	speed = 0.0
	ground_up = Vector3.UP
	if body:
		var forward := -body.global_basis.z
		heading = atan2(-forward.x, -forward.z)
		body.velocity = Vector3.ZERO
		body.up_direction = Vector3.UP
		_set_up(Vector3.UP)


## Horizontal forward direction for the current heading.
func get_flat_forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


## Eases the body's up axis toward the floor normal (or back to world up in
## the air) while keeping its yaw, and tells move_and_slide which way is up.
func _align_to_ground(delta: float, on_floor: bool) -> void:
	var target := body.get_floor_normal() if on_floor else Vector3.UP
	if target.dot(Vector3.UP) < cos(deg_to_rad(definition.max_slope_degrees)):
		target = Vector3.UP
	var weight := minf(definition.tilt_speed * delta, 1.0)
	ground_up = ground_up.slerp(target, weight).normalized()
	_set_up(ground_up)
	body.up_direction = ground_up


func _set_up(up: Vector3) -> void:
	var flat := get_flat_forward()
	var right := flat.cross(up).normalized()
	var forward := up.cross(right).normalized()
	body.global_basis = Basis(right, up, -forward)


func get_gravity_strength() -> float:
	return _base_gravity * definition.gravity_scale


func get_jump_velocity() -> float:
	return sqrt(2.0 * get_gravity_strength() * definition.jump_height)


func _apply_throttle(delta: float, throttle: float, speed_multiplier: float,
		acceleration_multiplier: float) -> void:
	var top := definition.max_speed * speed_multiplier
	if throttle > 0.01:
		speed = move_toward(speed, top * throttle,
			definition.acceleration * acceleration_multiplier * delta)
	elif throttle < -0.01:
		if speed > 0.3:
			speed = move_toward(speed, 0.0, definition.brake_deceleration * delta)
		else:
			speed = move_toward(speed, -definition.reverse_speed * -throttle,
				definition.acceleration * 0.6 * delta)
	else:
		speed = move_toward(speed, 0.0, definition.coast_deceleration * delta)
	# Turbo may have pushed us past the normal top speed; bleed it off gently.
	if absf(speed) > top:
		speed = move_toward(speed, signf(speed) * top, definition.coast_deceleration * delta)


func _apply_steering(delta: float, steer: float, on_floor: bool) -> void:
	if absf(steer) < 0.01 or absf(speed) < 0.05:
		return
	var authority := clampf(absf(speed) / definition.steer_full_speed, 0.0, 1.0)
	if not on_floor:
		authority *= definition.air_steer_factor
	# Reversing steers the other way, like a real car.
	heading -= steer * definition.steer_rate * authority * signf(speed) * delta


func _apply_vertical(delta: float, on_floor: bool, jump_requested: bool) -> void:
	if on_floor:
		if jump_requested and abilities.has(&"vehicle_jump"):
			body.velocity.y = get_jump_velocity()
			jumped.emit()
			_jumped = true
			body.up_direction = Vector3.UP
		elif body.velocity.y < 0.0:
			body.velocity.y = -2.0
		return
	body.velocity.y -= get_gravity_strength() * delta
	body.velocity.y = maxf(body.velocity.y, -definition.terminal_velocity)
