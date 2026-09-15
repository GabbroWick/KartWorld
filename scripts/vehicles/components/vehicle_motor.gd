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
signal bumped(other: Node3D)

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


## Slope needed (tan) before a crest counts as a jump; ~7 deg.
const MIN_LAUNCH_TANGENT := 0.12
const MIN_LAUNCH_SPEED := 6.0

var _uphill_tangent := 0.0
var _shove := Vector3.ZERO

## Submarine: floating at `surface_y`, no gravity, no floor.
var is_submarine := false
var surface_y := 0.0
const SUB_SINK := 0.45        # hull below the surface (m)
const SUB_SPEED_FACTOR := 0.8

const SHOVE_DECAY := 12.0   # m/s^2 fade of a knock
const SHOVE_MAX := 14.0


func drive(delta: float, throttle: float, steer: float, jump_requested: bool,
		speed_multiplier: float = 1.0, acceleration_multiplier: float = 1.0) -> void:
	var was_on_floor := body.is_on_floor()

	_apply_throttle(delta, throttle, speed_multiplier * (SUB_SPEED_FACTOR if is_submarine else 1.0), acceleration_multiplier)
	_apply_steering(delta, steer, was_on_floor or is_submarine)
	if is_submarine:
		# Bob up to the surface and stay there; waves are cosmetic.
		var target := surface_y - SUB_SINK
		body.velocity.y = (target - body.global_position.y) * 4.0
		body.floor_snap_length = 0.0
	else:
		_apply_vertical(delta, was_on_floor, jump_requested)

	var forward := -body.global_basis.z
	body.velocity.x = forward.x * speed + _shove.x
	body.velocity.z = forward.z * speed + _shove.z
	if body.velocity.y <= 0.0 and not is_submarine:
		StepUp.try_step(body, Vector3(body.velocity.x, 0.0, body.velocity.z) * delta,
			definition.max_step_height)
	body.move_and_slide()
	_bump_other_karts(forward)
	_shove = _shove.move_toward(Vector3.ZERO, SHOVE_DECAY * delta)

	# Whatever a wall or a bump took away is gone; this is what stops the kart
	# when it drives into the house.
	var planar := Vector3(body.velocity.x, 0.0, body.velocity.z) - _shove
	speed = planar.dot(forward)

	if not was_on_floor and body.is_on_floor():
		landed.emit(absf(body.velocity.y))


## A knock from another kart (or anything else): extra planar velocity
## that fades out over a moment. Karts are solid to each other, so a hit
## moves the other one instead of passing through it.
func shove(impulse: Vector3) -> void:
	_shove += Vector3(impulse.x, 0.0, impulse.z)
	_shove = _shove.limit_length(SHOVE_MAX)


## After moving: every kart we ran into gets pushed along our motion
## (sideways on a T-bone, forward on a rear-end), and we lose a bit too.
func _bump_other_karts(forward: Vector3) -> void:
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var other := hit.get_collider() as VehicleController
		if other == null or other.motor == null:
			continue
		var along := -hit.get_normal()
		along.y = 0.0
		if along.length_squared() < 0.001:
			continue
		along = along.normalized()
		var strength := maxf(absf(speed) * 0.6, 3.0)
		other.motor.shove(along * strength)
		_shove -= along * strength * 0.25
		bumped.emit(other)


## Switch between wheels and propellers. `surface` is the water level.
func set_submarine(on: bool, surface: float = 0.0) -> void:
	is_submarine = on
	surface_y = surface
	_uphill_tangent = 0.0
	if not on:
		body.floor_snap_length = 0.8


func reset() -> void:
	speed = 0.0
	_shove = Vector3.ZERO
	_uphill_tangent = 0.0
	if body:
		body.velocity = Vector3.ZERO


## Ramps and crests: driving up a slope carries vertical momentum; when the
## ground flattens or drops away the kart keeps it and flies (arcade
## `launch_factor` on top). Floor snapping is off while rising so
## move_and_slide does not pull it back down. Returns true when launched.
func _crest_launch() -> bool:
	var forward := -body.global_basis.z
	var normal := body.get_floor_normal()
	var uphill := -forward.dot(normal) / maxf(normal.y, 0.2)   # tan(slope ahead)
	var launched := false
	if _uphill_tangent > MIN_LAUNCH_TANGENT and uphill < 0.04 \
			and absf(speed) > MIN_LAUNCH_SPEED:
		body.velocity.y = absf(speed) * minf(_uphill_tangent, 0.6) * definition.launch_factor
		launched = true
	_uphill_tangent = uphill if uphill > 0.0 else 0.0
	return launched


## Thrown upward by a Spring; snapping is released so the kart really flies.
func launch(vertical_speed: float) -> void:
	body.velocity.y = vertical_speed
	body.floor_snap_length = 0.0
	jumped.emit()


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
		elif _crest_launch():
			pass
		elif body.velocity.y < 0.0:
			body.velocity.y = -2.0
		# Floor snapping would glue a launched kart back to the slope.
		body.floor_snap_length = 0.0 if body.velocity.y > 0.5 else 0.8
		return
	body.floor_snap_length = 0.8
	body.velocity.y -= get_gravity_strength() * delta
	body.velocity.y = maxf(body.velocity.y, -definition.terminal_velocity)
