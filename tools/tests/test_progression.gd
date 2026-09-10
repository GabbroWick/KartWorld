extends Node
## Headless test for progression and saving (Phase 7).
##
## Run:  godot --headless res://tools/tests/test_progression_runner.tscn
##
## Uses a scratch save file. Checks: fresh state, completing the Forest Trail
## records stars and grants the reward ability live (triple jump works), best
## stars are kept per level, the save file round-trips, the HUD shows total
## stars in the hub and announces the unlock.

const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL := "res://resources/levels/level_01_forest_trail.tres"
const SCRATCH_SAVE := "user://test_progression_save.json"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _manager: LevelManager
var _hud: CanvasLayer


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = SCRATCH_SAVE
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_hud = _scene.get_node("GameHUD")
	await _steps(20)
	_player = GameManager.get_player(0) as CharacterController
	_manager = get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager

	_test_fresh()
	await _test_first_completion()
	await _test_triple_jump()
	await _test_best_stars()
	await _test_save_roundtrip()
	ProgressionManager.reset()
	_finish()


func _test_fresh() -> void:
	_check(ProgressionManager.get_total_stars() == 0, "fresh save has 0 stars")
	_check(not ProgressionManager.is_level_completed(&"forest_trail"), "forest trail not completed yet")
	_check(not _player.abilities.has(&"enhanced_jump"), "player starts without enhanced_jump")
	_check(_player.motor.get_max_air_jumps() == 1, "one air jump at start")
	_check(_hud.stars_label.text == "", "hub HUD shows no stars when there are none")
	var definition: LevelDefinition = load(LEVEL)
	_check(definition.reward_abilities.has("enhanced_jump"), "Forest Trail rewards enhanced_jump")


func _test_first_completion() -> void:
	var recorded := [null]
	ProgressionManager.level_recorded.connect(func(id: StringName, stars: int, first: bool) -> void:
		recorded[0] = [id, stars, first])
	var unlocked := [null]
	ProgressionManager.ability_unlocked.connect(func(id: StringName) -> void: unlocked[0] = id)

	_manager.load_level(load(LEVEL))
	await _steps(10)
	_manager.complete_level(1)
	await _steps(10)
	_check(recorded[0] != null and recorded[0][0] == &"forest_trail" and recorded[0][1] == 1 and recorded[0][2],
		"completion recorded as forest_trail, 1 star, first time")
	_check(ProgressionManager.is_level_completed(&"forest_trail"), "level marked completed")
	_check(ProgressionManager.get_total_stars() == 1, "total stars is 1")
	_check(unlocked[0] == &"enhanced_jump", "enhanced_jump unlocked on first completion")
	_check(_player.abilities.has(&"enhanced_jump"), "player's AbilityComponent received it live")
	_check(_player.motor.get_max_air_jumps() == 2, "two air jumps now")
	_check(_manager.is_in_hub(), "party is back in the hub")
	_check(_hud.stars_label.text == "1", "hub HUD shows the total stars (%s)" % _hud.stars_label.text)
	_check(_hud.notice_label.text.contains("jump"), "HUD announces the new ability (%s)" % _hud.notice_label.text)
	_check(FileAccess.file_exists(SCRATCH_SAVE), "save file written")


func _test_triple_jump() -> void:
	# On the island: jump, air jump, second air jump.
	await _steps(30)
	_player.motor.reset()
	await _steps(10)
	await _press(InputActions.JUMP)
	await _steps(12)
	await _press(InputActions.JUMP)
	await _steps(12)
	await _press(InputActions.JUMP)
	await _steps(2)
	_check(_player.motor.air_jumps_used == 2, "triple jump: two air jumps consumed (%d)" % _player.motor.air_jumps_used)
	await _press(InputActions.JUMP)
	_check(_player.motor.air_jumps_used == 2, "a fourth jump is refused")
	for i in 200:
		await _steps(1)
		if _player.is_on_floor() and i > 5:
			break
	_check(_player.is_on_floor(), "lands again")


func _test_best_stars() -> void:
	var unlocked_again := [false]
	ProgressionManager.ability_unlocked.connect(func(_id: StringName) -> void: unlocked_again[0] = true)
	_manager.load_level(load(LEVEL))
	await _steps(10)
	_manager.complete_level(2)
	await _steps(10)
	_check(ProgressionManager.get_best_stars(&"forest_trail") == 2, "best stars rises to 2")
	_check(ProgressionManager.get_total_stars() == 2, "total counts best per level, not the sum of runs")
	_check(not unlocked_again[0], "reward is not granted twice")
	_manager.load_level(load(LEVEL))
	await _steps(10)
	_manager.complete_level(0)
	await _steps(10)
	_check(ProgressionManager.get_best_stars(&"forest_trail") == 2, "a worse run does not lower the best")
	_check(_hud.stars_label.text == "2", "hub HUD shows 2 stars (%s)" % _hud.stars_label.text)


func _test_save_roundtrip() -> void:
	var text := FileAccess.get_file_as_string(SCRATCH_SAVE)
	_check(text.contains("forest_trail") and text.contains("enhanced_jump"), "save file contains the progress")
	# Wipe memory only, then reload from disk.
	ProgressionManager.best_stars.clear()
	ProgressionManager.unlocked_abilities.clear()
	ProgressionManager.load_from_disk()
	_check(ProgressionManager.get_best_stars(&"forest_trail") == 2, "best stars survive a reload")
	_check(ProgressionManager.has_ability(&"enhanced_jump"), "unlocked ability survives a reload")
	var fresh := AbilityComponent.new()
	add_child(fresh)
	fresh.setup(PackedStringArray(["run"]))
	ProgressionManager.apply_to(fresh)
	_check(fresh.has(&"enhanced_jump") and fresh.has(&"run"), "apply_to grants progression abilities to a new component")
	ProgressionManager.reset()
	_check(not FileAccess.file_exists(SCRATCH_SAVE), "reset removes the save file")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


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
