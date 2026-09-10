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

	var forward := -body.global_basis.z
	body.velocity.x = forward.x * speed
	body.velocity.z = forward.z * speed
	if body.velocity.y <= 0.0:
		StepUp.try_step(body, Vector3(body.velocity.x, 0.0, body.velocity.z) * delta,
			definition.max_step_height)
	body.move_and_slide()

	# Whatever a wall or a bump took away is gone; this is what stops the kart
	# when it drives into the house.
	var planar := Vector3(body.velocity.x, 0.0, body.velocity.z)
	speed = planar.dot(forward)

	if not was_on_floor and body.is_on_floor():
		landed.emit(absf(body.velocity.y))


func reset() -> void:
	speed = 0.0
	if body:
		body.velocity = Vector3.ZERO


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
	body.rotate_y(-steer * definition.steer_rate * authority * signf(speed) * delta)


func _apply_vertical(delta: float, on_floor: bool, jump_requested: bool) -> void:
	if on_floor:
		if jump_requested and abilities.has(&"vehicle_jump"):
			body.velocity.y = get_jump_velocity()
			jumped.emit()
		elif body.velocity.y < 0.0:
			body.velocity.y = -2.0
		return
	body.velocity.y -= get_gravity_strength() * delta
	body.velocity.y = maxf(body.velocity.y, -definition.terminal_velocity)
