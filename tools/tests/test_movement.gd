extends Node
## Headless gameplay test for the character prototype.
##
## Run:  godot --headless res://tools/tests/test_runner.tscn
##
## It runs as a scene (not with --script) so the autoloads and the global script
## class cache are available exactly like in the real game.
##
## Drives the real main scene with simulated input and asserts the movement
## contract: idle, walk, run, gravity, jump height, double jump, air-jump limit,
## collision with the ground, and fall respawn.

const MAIN_SCENE := "res://scenes/main.tscn"
const TICK := 1.0 / 60.0
## Frames needed to reach the apex of a full jump, at 60 Hz physics.
const ASCENT_FRAMES := 26

var _failures: Array[String] = []
var _checks := 0
var _player: CharacterController
var _camera_rig: ThirdPersonCamera


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	_camera_rig = scene.get_node("CameraRig")
	await _steps(10)

	_check(GameManager.get_player(0) != null, "player registered with GameManager")
	_player = GameManager.get_player(0) as CharacterController
	if _player == null:
		_fail("main scene did not spawn a player")
		_finish()
		return

	_check(_player.definition != null, "player has a CharacterDefinition")
	_check(_player.definition.display_name == "Leopard", "loaded character is the Leopard")
	_check(_player.abilities.has(&"double_jump"), "leopard starts with double_jump")
	_check(_player.health.current_health == _player.definition.max_health, "health initialised")
	_check(_player.visual_root.get_child_count() == 1, "placeholder visual instantiated")

	await _test_input_map()
	await _test_grounding()
	await _test_walk()
	await _test_run()
	await _test_jump()
	await _test_short_hop()
	await _test_double_jump()
	await _test_camera()
	await _test_collision()
	await _test_fall_respawn()
	_finish()


func _test_input_map() -> void:
	for action in InputActions.ALL:
		_check(InputMap.has_action(action), "input action '%s' exists" % action)
		if InputMap.has_action(action):
			_check(not InputMap.action_get_events(action).is_empty(),
				"input action '%s' is bound" % action)


func _test_grounding() -> void:
	await _steps(40)
	_check(_player.is_on_floor(), "character rests on the ground (collision works)")
	_check(absf(_player.global_position.y) < 0.2,
		"character stands at ground level, got y=%.2f" % _player.global_position.y)


func _test_walk() -> void:
	var start := _player.global_position
	await _hold(&"move_forward", 60)
	var travelled := start.distance_to(_player.global_position)
	var expected := _player.definition.walk_speed * 1.0
	_check(travelled > expected * 0.6, "walking moved %.2fm in 1s (walk_speed %.1f)"
		% [travelled, _player.definition.walk_speed])
	_check(travelled < expected * 1.15, "walking did not exceed walk speed (%.2fm)" % travelled)
	await _steps(30)
	_check(_horizontal_speed() < 0.2, "character stops when input is released")


func _test_run() -> void:
	Input.action_press(InputActions.RUN)
	var start := _player.global_position
	await _hold(&"move_forward", 60)
	var travelled := start.distance_to(_player.global_position)
	Input.action_release(InputActions.RUN)
	_check(travelled > _player.definition.walk_speed * 1.2,
		"running (%.2fm/s) is clearly faster than walking (%.1f)"
		% [travelled, _player.definition.walk_speed])
	_check(travelled < _player.definition.run_speed * 1.15,
		"running does not exceed run_speed (%.2fm)" % travelled)
	await _steps(30)


func _test_jump() -> void:
	var ground_y := _player.global_position.y
	Input.action_press(InputActions.JUMP)
	# Simulated input needs one tick to reach the character's poll, so give the
	# jump two frames before inspecting the result.
	await _steps(2)
	_check(_player.velocity.y > 0.0, "jump gives upward velocity (%.1f)" % _player.velocity.y)

	# Hold through the whole ascent: releasing early is a deliberate short hop.
	await _steps(ASCENT_FRAMES - 2)
	Input.action_release(InputActions.JUMP)

	var result := await _fall_to_ground(ground_y)
	_check(result.y > 0.0, "gravity pulls the character back down")
	_check(absf(result.x - _player.definition.jump_height) < 0.35,
		"full jump peaked at %.2fm (definition asks %.2fm)"
		% [result.x, _player.definition.jump_height])
	_check(_player.is_on_floor(), "character lands back on the ground")


func _test_short_hop() -> void:
	await _steps(10)
	var ground_y := _player.global_position.y
	await _jump(1)
	var result := await _fall_to_ground(ground_y)
	_check(result.x < _player.definition.jump_height * 0.75,
		"tapping jump gives a short hop (%.2fm vs %.2fm)"
		% [result.x, _player.definition.jump_height])
	_check(result.x > 0.4, "short hop still clears a low step (%.2fm)" % result.x)


func _test_double_jump() -> void:
	await _steps(10)
	var ground_y := _player.global_position.y
	await _jump(ASCENT_FRAMES)
	_check(not _player.is_on_floor(), "character is airborne before the second jump")

	var velocity_before := _player.velocity.y
	Input.action_press(InputActions.JUMP)
	await _steps(2)
	_check(_player.velocity.y > velocity_before, "double jump adds upward velocity (%.1f -> %.1f)"
		% [velocity_before, _player.velocity.y])
	_check(_player.motor.air_jumps_used == 1, "one air jump consumed")
	await _steps(ASCENT_FRAMES - 2)
	Input.action_release(InputActions.JUMP)

	await _jump(2)
	_check(_player.motor.air_jumps_used == 1, "a third jump is refused (max_air_jumps respected)")

	var result := await _fall_to_ground(ground_y)
	_check(result.x > _player.definition.jump_height * 1.3,
		"double jump reaches higher than a single jump (%.2fm)" % result.x)
	await _steps(3)
	_check(_player.motor.air_jumps_used == 0, "air jumps refill on landing")


func _test_camera() -> void:
	await _steps(10)
	_check(_camera_rig.target == _player, "camera rig targets the player")
	_check(_camera_rig.camera.current, "the rig camera is the active camera")

	var head := _player.global_position + Vector3.UP * _camera_rig.target_height
	_check(_camera_rig.global_position.distance_to(head) < 0.5,
		"camera pivot follows the character (%.2fm off)"
		% _camera_rig.global_position.distance_to(head))
	_check(_camera_rig.camera.global_position.distance_to(head) > 1.0,
		"camera sits behind the character, not inside it")

	var yaw_before := _camera_rig.rotation.y
	await _hold(InputActions.CAMERA_RIGHT, 30)
	var yaw_after := _camera_rig.rotation.y
	_check(absf(yaw_after - yaw_before) > 0.1,
		"camera_right rotates the camera (%.2f -> %.2f rad)" % [yaw_before, yaw_after])
	await _hold(InputActions.CAMERA_UP, 20)
	_check(_camera_rig.pitch_pivot.rotation.x != 0.0, "camera_up tilts the camera")

	# Movement must follow the camera, not world axes.
	var start := _player.global_position
	await _hold(&"move_forward", 40)
	var moved := _player.global_position - start
	moved.y = 0.0
	var camera_forward := -_camera_rig.global_basis.z
	camera_forward.y = 0.0
	_check(moved.length() > 0.5, "character moved while testing the camera")
	if moved.length() > 0.5:
		_check(moved.normalized().dot(camera_forward.normalized()) > 0.9,
			"forward input follows the camera direction (dot %.2f)"
			% moved.normalized().dot(camera_forward.normalized()))
	await _steps(20)


func _test_collision() -> void:
	# Walk straight into the arena wall and check we do not pass through it.
	# Movement is camera-relative, so face the camera down -Z first.
	_camera_rig.set_yaw(0.0)
	_player.global_position = Vector3(-6.0, 0.2, -5.5)
	_player.motor.reset()
	await _steps(20)
	Input.action_press(InputActions.RUN)
	await _hold(&"move_forward", 90)
	Input.action_release(InputActions.RUN)
	_check(_player.global_position.z > -7.6,
		"wall blocks the character (stopped at z=%.2f, wall at z=-8)"
		% _player.global_position.z)
	await _steps(20)


func _test_fall_respawn() -> void:
	var spawn := _player.spawn_transform.origin
	_player.global_position = Vector3(0.0, -40.0, 0.0)
	await _steps(5)
	_check(_player.global_position.distance_to(spawn) < 1.0,
		"falling out of the world respawns the character at the spawn point")
	_check(not _player.health.is_dead, "health is restored after respawn")


func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## Presses jump, holds it for `frames` physics frames, then releases.
func _jump(frames: int) -> void:
	Input.action_press(InputActions.JUMP)
	await _steps(frames)
	Input.action_release(InputActions.JUMP)


## Follows the character until it lands. Returns (peak height above `ground_y`,
## 1.0 if a real fall was observed).
func _fall_to_ground(ground_y: float) -> Vector2:
	var peak := ground_y
	var falling := 0.0
	for i in 240:
		await _steps(1)
		peak = maxf(peak, _player.global_position.y)
		if _player.velocity.y < -0.5:
			falling = 1.0
		if _player.is_on_floor() and i > 5:
			break
	return Vector2(peak - ground_y, falling)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _steps(frames)
	Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		_failures.append(description)


func _fail(description: String) -> void:
	_check(false, description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
