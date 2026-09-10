class_name CharacterMotor
extends Node
## All locomotion physics for a CharacterBody3D: gravity, acceleration,
## friction, jump, coyote time, jump buffering and air jumps.
##
## It knows nothing about input devices or cameras. It receives a world-space
## direction and a few booleans, and it moves the body. Values come from a
## CharacterDefinition, so tuning a character never means editing this file.

signal jumped(air_jump_index: int)  ## 0 = ground jump, 1+ = air jumps
signal landed(impact_speed: float)

var body: CharacterBody3D
var definition: CharacterDefinition
var abilities: AbilityComponent

var is_running := false
var air_jumps_used := 0

var _coyote_timer := 0.0
var _jump_buffer := 0.0
var _base_gravity := 26.0


func setup(character_body: CharacterBody3D, character_definition: CharacterDefinition,
		ability_component: AbilityComponent) -> void:
	body = character_body
	definition = character_definition
	abilities = ability_component
	_base_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))
	body.floor_snap_length = 0.5
	body.floor_stop_on_slope = true


## `wish_dir` is a world-space, y-less direction with length 0..1.
func move(delta: float, wish_dir: Vector3, want_run: bool, jump_requested: bool,
		jump_cut: bool) -> void:
	var was_on_floor := body.is_on_floor()

	if jump_requested:
		_jump_buffer = definition.jump_buffer_time
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	_apply_vertical(delta, was_on_floor, jump_cut)
	_try_jump()
	_apply_horizontal(delta, wish_dir, want_run)

	body.move_and_slide()

	if not was_on_floor and body.is_on_floor():
		landed.emit(absf(body.velocity.y))


func reset() -> void:
	is_running = false
	air_jumps_used = 0
	_coyote_timer = 0.0
	_jump_buffer = 0.0
	if body:
		body.velocity = Vector3.ZERO


func get_gravity_strength() -> float:
	return _base_gravity * definition.gravity_scale


func get_jump_velocity(scale: float = 1.0) -> float:
	return sqrt(2.0 * get_gravity_strength() * definition.jump_height) * scale


func _apply_vertical(delta: float, on_floor: bool, jump_cut: bool) -> void:
	if on_floor:
		air_jumps_used = 0
		_coyote_timer = definition.coyote_time
		if body.velocity.y < 0.0:
			# Small downward bias keeps the body glued to slopes and steps.
			body.velocity.y = -2.0
		return

	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	if jump_cut and body.velocity.y > 0.0:
		body.velocity.y *= definition.short_hop_damping
	var multiplier := 1.0 if body.velocity.y > 0.0 else definition.fall_gravity_multiplier
	body.velocity.y -= get_gravity_strength() * multiplier * delta
	body.velocity.y = maxf(body.velocity.y, -definition.terminal_velocity)


func _try_jump() -> void:
	if _jump_buffer <= 0.0:
		return
	if body.is_on_floor() or _coyote_timer > 0.0:
		_do_jump(1.0, 0)
	elif abilities.has(AbilityComponent.DOUBLE_JUMP) and air_jumps_used < definition.max_air_jumps:
		air_jumps_used += 1
		_do_jump(definition.air_jump_scale, air_jumps_used)


func _do_jump(scale: float, index: int) -> void:
	body.velocity.y = get_jump_velocity(scale)
	_jump_buffer = 0.0
	_coyote_timer = 0.0
	jumped.emit(index)


func _apply_horizontal(delta: float, wish_dir: Vector3, want_run: bool) -> void:
	var on_floor := body.is_on_floor()
	is_running = want_run and abilities.has(AbilityComponent.RUN)
	var top_speed := definition.run_speed if is_running else definition.walk_speed
	var target := Vector3(wish_dir.x, 0.0, wish_dir.z) * top_speed

	var rate: float
	if wish_dir.length_squared() > 0.0001:
		rate = definition.ground_acceleration if on_floor else definition.air_acceleration
	else:
		rate = definition.ground_friction if on_floor else definition.air_friction

	body.velocity.x = move_toward(body.velocity.x, target.x, rate * delta)
	body.velocity.z = move_toward(body.velocity.z, target.z, rate * delta)
