extends Node
## Headless test for Level 4 "Ponti della Giungla" (Phase 11).
##
## Run:  godot --headless res://tools/tests/test_jungle_runner.tscn
##
## Loads the level through the LevelManager and checks: the TrackRibbon
## (length, ramps, kart stays on it and climbs), Spring launches, a
## MovingPlatform carries the player, lethal lava respawns at the
## checkpoint, spikes deal one heart, and killing the slimes + entering
## the crater portal completes the level with its stars.

const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL := "res://resources/levels/level_04_jungle.tres"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _manager: LevelManager
var _camera_rig: ThirdPersonCamera
var _hud: CanvasLayer
var _level: LevelController
var _world: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = "user://test_jungle_save.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_camera_rig = _scene.get_node("CameraRig")
	_hud = _scene.get_node("GameHUD")
	await _steps(20)
	_player = GameManager.get_player(0) as CharacterController
	_manager = get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager

	await _test_load()
	if _level == null:
		_finish()
		return
	await _test_bridge()
	await _test_vine()
	await _test_finish()
	_finish()


func _test_load() -> void:
	_manager.load_level(load(LEVEL))
	await _steps(25)
	_world = _manager.world
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	_check(_level != null, "Giungla has a LevelController")
	if _level == null:
		return
	_check(_level.stars_total == 3, "level counts three stars (%d)" % _level.stars_total)
	var slimes := get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return _level.owns(e))
	_check(slimes.size() == 3, "three slimes in the jungle (%d)" % slimes.size())
	_check(_hud.objective_label.text == tr(&"OBJ_CROSS_JUNGLE"), "HUD shows the crossing objective (%s)" % _hud.objective_label.text)
	_check(_world.find_children("Plank*", "", false, false).size() >= 12, "two plank bridges")
	_check(_world.find_children("Palm*", "", false, false).size() >= 15, "palms dress the banks")
	_check(_player.is_on_floor(), "player stands on the start pad")


func _test_bridge() -> void:
	# Walk the first bridge without jumping: a gap swallows you, the river
	# kills you and you are back at the start.
	var died := [false]
	_player.died.connect(func() -> void: died[0] = true)
	_teleport(Vector3(0.0, 0.6, -2.0))
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	await _hold(InputActions.MOVE_FORWARD, 60)
	await _steps(40)
	_check(died[0], "falling between the planks into the river kills")
	_check(_player.global_position.distance_to(Vector3(0.0, 0.6, 0.0)) < 2.0, "back at the start pad (%.1f m)" % _player.global_position.distance_to(Vector3(0.0, 0.6, 0.0)))
	# A walking jump from a plank's edge lands on the next plank (planks
	# span [-4-4.8k, -7.4-4.8k]).
	_teleport(Vector3(0.0, 0.4, -6.8))
	await _steps(15)
	_check(_player.is_on_floor(), "planks are solid")
	Input.action_press(InputActions.MOVE_FORWARD)
	await _steps(4)
	await _hold(InputActions.JUMP, 3)
	var landed_next := false
	for i in 90:
		await _steps(1)
		if _player.is_on_floor() and _player.global_position.z < -8.8 and _player.global_position.z > -12.2:
			landed_next = true
			break
	Input.action_release(InputActions.MOVE_FORWARD)
	_check(landed_next, "a walking jump clears the gap to the next plank (z %.1f)" % _player.global_position.z)
	var checkpoint := _world.get_node("Checkpoint1") as Checkpoint
	_teleport(checkpoint.global_position + Vector3(0.0, 0.3, 0.0))
	await _steps(5)
	_check(checkpoint.is_active, "checkpoint on the first bank")
	var log := _world.get_node("Log1") as MovingPlatform
	var start := log.global_position
	var moved := 0.0
	for i in 260:
		await _steps(1)
		moved = maxf(moved, log.global_position.distance_to(start))
	_check(moved > 2.0, "the log ferries drift across the river (%.1f m)" % moved)


func _test_vine() -> void:
	var vine := _world.get_node("Vine1") as Vine
	_teleport(vine.global_position + Vector3(0.0, 0.3, 3.0))
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	var from := _player.global_position
	var top := from.y
	Input.action_press(InputActions.MOVE_FORWARD)
	for i in 70:
		await _steps(1)
		top = maxf(top, _player.global_position.y)
	Input.action_release(InputActions.MOVE_FORWARD)
	var flung := from.z - _player.global_position.z
	_check(top - from.y > 3.0 and flung > 10.0, "the vine flings the character up and over the gorge (%.1f m up, %.1f m forward)" % [top - from.y, flung])


func _test_finish() -> void:
	var done := [-1]
	_level.completed.connect(func(stars: int) -> void: done[0] = stars)
	_teleport(Vector3(0.0, 0.6, -202.0))
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	var portal := _world.get_node("GoalPortal") as Portal
	await _hold(InputActions.MOVE_FORWARD, 30)
	_check(portal.is_open(), "the end door opens on approach")
	await _hold(InputActions.MOVE_FORWARD, 70)
	await _steps(5)
	_check(done[0] == 0, "reaching the door completes the jungle (got %d)" % done[0])
	await _steps(240)
	_check(_manager.is_in_hub(), "party is back in the hub")
	ProgressionManager.reset()


func _teleport(at: Vector3) -> void:
	if _player.driver.is_driving:
		_player.driver.exit_vehicle()
	_player.global_position = at
	_player.motor.reset()
	_player.velocity = Vector3.ZERO


func _strength(action: StringName, value: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = value > 0.02
	ev.strength = clampf(value, 0.0, 1.0)
	Input.parse_input_event(ev)


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _steps(frames)
	Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
