extends Node
## Headless test for hub content: persistent stars, the gated second portal
## and the Cliff Steps level.
##
## Run:  godot --headless res://tools/tests/test_hub_runner.tscn

const MAIN_SCENE := "res://scenes/main.tscn"
const SCRATCH_SAVE := "user://test_hub_save.json"

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

	_test_hub_setup()
	await _test_persistent_star()
	await _test_locked_portal()
	await _test_unlock_and_enter()
	await _test_cliff_steps()
	ProgressionManager.reset()
	_finish()


## The five hand-placed hub stars (road-jump stars are RoadDressing's).
func _hub_stars() -> Array:
	return get_tree().get_nodes_in_group(&"star").filter(
		func(s: Node) -> bool: return (s as Collectible).persistent_id.begins_with("hub_star_"))


func _portals() -> Array:
	return _manager.world.find_children("*", "Portal", true, false)


func _test_hub_setup() -> void:
	_check(_hub_stars().size() == 5, "island has five persistent stars (%d)" % _hub_stars().size())
	_check(_portals().size() == 3, "island has three portals (%d)" % _portals().size())
	var locked := _portals().filter(func(p: Portal) -> bool: return p.is_locked())
	_check(locked.size() == 1, "exactly one portal is locked at the start")
	if locked.size() == 1:
		var portal: Portal = locked[0]
		_check(portal.level.id == &"cliff_steps", "the locked portal leads to Cliff Steps")
		_check(portal.label.text.contains(tr(&"ABILITY_ENHANCED_JUMP")), "locked portal says what it needs (%s)" % portal.label.text.replace("\n", " / "))


func _test_persistent_star() -> void:
	var star: Star = _hub_stars()[0]
	var id := star.persistent_id
	_player.global_position = star.global_position + Vector3(0, 0.3, 0)
	_player.motor.reset()
	await _steps(5)
	_check(ProgressionManager.is_collected(id), "touching a hub star records it (%s)" % id)
	_check(ProgressionManager.get_total_stars() == 1, "hub star counts toward total stars")
	_check(_hud.stars_label.text == "1", "HUD shows the hub star (%s)" % _hud.stars_label.text)
	_check(FileAccess.get_file_as_string(SCRATCH_SAVE).contains(String(id)), "hub star is saved to disk")
	# Leave and come back: the star must not be there any more.
	_manager.load_level(load("res://resources/levels/level_01_forest_trail.tres"))
	await _steps(5)
	_manager.return_to_hub()
	await _steps(5)
	_check(_hub_stars().size() == 4, "collected hub star does not respawn (%d left)" % _hub_stars().size())
	_check(_hud.stars_label.text == "1", "HUD still shows 1 star back in the hub (%s)" % _hud.stars_label.text)


func _test_locked_portal() -> void:
	var portal: Portal = _portals().filter(func(p: Portal) -> bool: return p.is_locked())[0]
	_manager._loaded_at = -1000.0
	_player.global_position = portal.global_position + Vector3(0, 0.3, 0)
	_player.motor.reset()
	await _steps(10)
	_check(_manager.is_in_hub(), "walking into the locked portal does nothing")
	_check(not _player.driver.is_driving and _player.is_on_floor(), "player just stands on the plinth")
	_player.global_position = portal.global_position + Vector3(0, 0.3, 6.0)
	_player.motor.reset()
	await _steps(5)


func _test_unlock_and_enter() -> void:
	# Beat the Forest Trail: triple jump unlocks, the second portal opens.
	_manager.load_level(load("res://resources/levels/level_01_forest_trail.tres"))
	await _steps(5)
	_manager.complete_level(1)
	await _steps(5)
	_check(_manager.is_in_hub() and ProgressionManager.has_ability(&"enhanced_jump"), "Forest Trail beaten, triple jump unlocked")
	var portal: Portal = _portals().filter(func(p: Portal) -> bool: return p.level and p.level.id == &"cliff_steps")[0]
	_check(not portal.is_locked(), "Cliff Steps portal is now open")
	_check(portal.label.text == tr(&"LEVEL_CLIFF_STEPS_NAME"), "portal label no longer shows the requirement (%s)" % portal.label.text)
	_manager._loaded_at = -1000.0
	_player.global_position = portal.global_position + Vector3(0, 0.3, 0)
	_player.motor.reset()
	await _steps(10)
	_check(not _manager.is_in_hub() and _manager.current_level.id == &"cliff_steps", "walking in now loads Cliff Steps")


func _test_cliff_steps() -> void:
	await _steps(20)
	var level := get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	_check(level != null and level.stars_total == 3, "Cliff Steps has 3 stars")
	_check(get_tree().get_nodes_in_group(Enemy.GROUP).size() == 2, "Cliff Steps has 2 slimes")
	_check(_player.is_on_floor(), "player stands at the Cliff Steps spawn")
	# Triple jump is enough to reach Step1 (3 m top) from the base.
	_player.global_position = Vector3(0.0, 0.3, -7.0)
	_player.motor.reset()
	await _steps(5)
	var peak := 0.0
	Input.action_press(InputActions.JUMP)
	for i in 14:
		await _steps(1)
		peak = maxf(peak, _player.global_position.y)
	Input.action_release(InputActions.JUMP)
	await _steps(2)
	Input.action_press(InputActions.JUMP)
	for i in 14:
		await _steps(1)
		peak = maxf(peak, _player.global_position.y)
	Input.action_release(InputActions.JUMP)
	await _steps(2)
	Input.action_press(InputActions.JUMP)
	for i in 30:
		await _steps(1)
		peak = maxf(peak, _player.global_position.y)
	Input.action_release(InputActions.JUMP)
	_check(peak > 6.0, "triple jump reaches over 6 m (%.1f)" % peak)
	# Finish it through the summit portal to prove the level completes.
	_player.global_position = Vector3(7.0, 22.4, -50.0)
	_player.motor.reset()
	await _steps(10)
	_check(not _manager.is_in_hub(), "standing on the summit plinth does not complete the level")
	_player.global_position = Vector3(7.0, 22.4, -52.0)
	_player.motor.reset()
	await _steps(10)
	await _steps(240)
	_check(_manager.is_in_hub(), "entering the summit portal completes Cliff Steps and returns home")
	_check(ProgressionManager.is_level_completed(&"cliff_steps"), "Cliff Steps recorded as completed")


func _steps(count: int) -> void:
	for i in count:
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
