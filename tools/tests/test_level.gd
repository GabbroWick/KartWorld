extends Node
## Headless test for the first level's gameplay systems (Phase 5).
##
## Run:  godot --headless res://tools/tests/test_level_runner.tscn
##
## Loads the game, jumps straight into the Forest Trail through the
## LevelManager and checks: LevelController and objectives, HUD texts, star
## pickup, checkpoint changing the respawn point, dying by falling and coming
## back at the checkpoint, reaching the goal completing the level, and the
## automatic return to the hub with the level result.

const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL := "res://resources/levels/level_01_forest_trail.tres"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _manager: LevelManager
var _camera_rig: ThirdPersonCamera
var _hud: CanvasLayer
var _level: LevelController


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = "user://test_level_save.json"
	Settings.path = "user://test_settings.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_camera_rig = _scene.get_node("CameraRig")
	_hud = _scene.get_node("GameHUD")
	await _steps(20)
	_player = GameManager.get_player(0) as CharacterController
	_manager = get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager

	_test_hud_in_hub()
	await _test_load()
	await _test_star()
	await _test_checkpoint()
	await _test_death_respawn()
	await _test_health_hud()
	await _test_goal()
	await _test_pause()
	_finish()


func _test_pause() -> void:
	var menu: PauseMenu = _scene.get_node("PauseMenu")
	_check(not menu.root.visible, "pause menu hidden while playing")
	var before := _player.global_position
	_press_action(InputActions.PAUSE)
	await _steps(2)
	_check(GameManager.is_paused and get_tree().paused, "Esc pauses the game")
	_check(menu.root.visible, "pause menu is visible while paused")
	_check(menu.resume_button.text == tr(&"PAUSE_RESUME"), "pause menu is in Italian (%s)" % menu.resume_button.text)
	# Settings page: quality drives the sun's shadows, toggles are saved.
	menu.settings_button.pressed.emit()
	await _steps(2)
	_check(menu.settings_panel.visible and not menu.panel.visible, "Impostazioni opens the settings page")
	var sun := get_tree().get_first_node_in_group(&"sun") as DirectionalLight3D
	Settings.set_quality(&"low")
	_check(sun != null and not sun.shadow_enabled, "low quality turns the sun's shadows off")
	Settings.set_quality(&"high")
	_check(sun != null and sun.shadow_enabled and sun.directional_shadow_max_distance >= 100.0, "high quality: shadows on, long shadow distance")
	Settings.set_invert_fly_y(true)
	_check(FileAccess.get_file_as_string(Settings.path).contains("\"invert_fly_y\": true"), "settings are saved to disk")
	Settings.set_invert_fly_y(false)
	Settings.set_look_sensitivity(1.5)
	_check(is_equal_approx(_camera_rig.sensitivity_scale, 1.5), "camera speed reaches the camera rig")
	Settings.set_look_sensitivity(1.0)
	Settings.set_quality(&"medium")
	menu.settings_panel.back_button.pressed.emit()
	await _steps(2)
	_check(menu.panel.visible and not menu.settings_panel.visible, "Back returns to the pause menu")
	_check(not menu.hub_button.visible, "no 'back to the island' button while already in the hub")
	Input.action_press(&"move_forward")
	await _steps(20)
	Input.action_release(&"move_forward")
	_check(_player.global_position.distance_to(before) < 0.01, "the player does not move while paused")
	menu.resume_button.pressed.emit()
	await _steps(2)
	_check(not GameManager.is_paused and not get_tree().paused, "Resume unpauses")
	_check(not menu.root.visible, "pause menu hides on resume")
	get_tree().paused = false


## Feeds a press+release through the input system so _unhandled_input sees it.
func _press_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _test_hud_in_hub() -> void:
	_check(TranslationServer.get_locale().begins_with("it"), "game locale is Italian (%s)" % TranslationServer.get_locale())
	_check(tr(&"HUD_HUB_HINT") != "HUD_HUB_HINT" and tr(&"HUD_HUB_HINT").contains("isola"), "hub hint is translated to Italian (%s)" % tr(&"HUD_HUB_HINT"))
	_check(_hud.hearts.current == 5 and _hud.hearts.maximum == 5, "HUD shows five hearts in the hub (%d/%d)" % [_hud.hearts.current, _hud.hearts.maximum])
	_check(_hud.objective_label.text == tr(&"HUD_HUB_HINT"), "HUD shows the hub hint")
	_check(_hud.stars_label.text == "", "no star counter in the hub")


func _test_load() -> void:
	_manager.load_level(load(LEVEL))
	await _steps(10)
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	_check(_level != null, "level has a LevelController")
	if _level == null:
		_finish()
		return
	_check(_level.objectives.size() == 3, "three objectives configured (%d)" % _level.objectives.size())
	var current := _level.get_current_objective()
	_check(current != null and current is ReachDestinationObjective,
		"current objective is the required 'reach' one")
	_check(_level.stars_total == 2, "level counts its two stars (%d)" % _level.stars_total)
	_check(_hud.objective_label.text == tr(&"OBJ_REACH_CLEARING"),
		"HUD shows the objective (%s)" % _hud.objective_label.text)
	_check(_hud.stars_label.text == "0/2", "HUD shows 0/2 stars (%s)" % _hud.stars_label.text)
	var stars := get_tree().get_nodes_in_group(&"star")
	_check(stars.size() == 2, "two Star nodes in the scene")


func _test_star() -> void:
	var star: Star = get_tree().get_nodes_in_group(&"star")[0]
	var got := [false]
	star.collected.connect(func(_c: Collectible, _by: CharacterController) -> void: got[0] = true)
	_player.global_position = star.global_position + Vector3(0, 0.3, 3.0)
	_player.motor.reset()
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	Sfx.clear_log()
	await _hold(&"move_forward", 40)
	await _steps(5)
	_check(got[0], "walking into a star collects it")
	_check(Sfx.played.has(&"star"), "star pickup plays its sound")
	_check(get_tree().get_nodes_in_group(Burst.GROUP).size() >= 1, "star pickup spawns a particle burst")
	_check(_level.stars_collected == 1, "controller counts 1 star")
	_check(_hud.stars_label.text == "1/2", "HUD shows 1/2 stars (%s)" % _hud.stars_label.text)
	_check(not is_instance_valid(star) or star.is_queued_for_deletion(), "collected star disappears")
	var collect: CollectObjective = _level.objectives[1]
	_check(collect.get_status_text() == tr(&"OBJ_COLLECT_STARS") + " 1/2", "collect objective reports progress (%s)" % collect.get_status_text())
	_check(not collect.is_complete, "optional star objective is not complete yet")


func _test_checkpoint() -> void:
	var checkpoint: Checkpoint = get_tree().get_first_node_in_group(Checkpoint.GROUP)
	_check(checkpoint != null and not checkpoint.is_active, "checkpoint starts inactive")
	var before := _player.spawn_transform.origin
	_player.global_position = checkpoint.global_position + Vector3(0, 0.3, 0)
	_player.motor.reset()
	await _steps(5)
	_check(checkpoint.is_active, "touching the checkpoint activates it")
	_check(checkpoint.ring_color == checkpoint.active_color, "checkpoint ring turns green")
	_check(_player.spawn_transform.origin.distance_to(checkpoint.respawn_point.global_position) < 0.5,
		"respawn point moved to the checkpoint")
	_check(_player.spawn_transform.origin.distance_to(before) > 5.0, "respawn point actually changed")


func _test_death_respawn() -> void:
	var checkpoint: Checkpoint = get_tree().get_first_node_in_group(Checkpoint.GROUP)
	var died := [false]
	_player.died.connect(func() -> void: died[0] = true)
	_player.global_position = Vector3(20.0, -40.0, -44.0)
	await _steps(5)
	_check(died[0], "falling out of the level kills the character")
	_check(_player.global_position.distance_to(checkpoint.respawn_point.global_position) < 1.0,
		"character respawns at the checkpoint (%.1fm)" % _player.global_position.distance_to(checkpoint.respawn_point.global_position))
	_check(_level.stars_collected == 1, "collected stars are kept after dying")
	_check(not _manager.is_in_hub(), "dying does not leave the level")
	await _steps(20)


func _test_health_hud() -> void:
	_player.health.take_damage(2.0)
	await _steps(2)
	_check(_hud.hearts.current == 3, "HUD reflects damage (%d hearts)" % _hud.hearts.current)
	_player.health.heal(2.0)
	await _steps(2)
	_check(_hud.hearts.current == 5, "HUD reflects healing")


func _test_goal() -> void:
	var done := [-1]
	_level.completed.connect(func(stars: int) -> void: done[0] = stars)
	var result := [null, -1]
	_manager.level_completed.connect(func(d: LevelDefinition, stars: int) -> void:
		result[0] = d
		result[1] = stars)
	# Arrive hurt: finishing the level must send us home with full hearts.
	_player.take_damage(2.0, null)
	_player.invulnerable_left = 0.0
	# Stand on the yellow plinth first: that alone must not finish the level.
	_player.global_position = Vector3(20.0, 0.3, -46.0)
	_player.motor.reset()
	_camera_rig.set_yaw(0.0)
	await _steps(10)
	_check(done[0] == -1, "standing on the goal plinth does not complete the level")
	# Then walk into the finish portal.
	Sfx.clear_log()
	await _hold(&"move_forward", 60)
	await _steps(5)
	_check(done[0] == 1, "entering the finish portal completes the level with 1 star (got %d)" % done[0])
	_check(_hud.objective_label.text == tr(&"HUD_LEVEL_COMPLETE"), "HUD announces completion (%s)" % _hud.objective_label.text)
	_check(not _manager.is_in_hub(), "return home waits for the completion delay")
	_check(_hud.card.visible, "level-complete card is shown")
	_check(_hud.card.level_label.text == tr(&"LEVEL_FOREST_TRAIL_NAME"), "card names the level (%s)" % _hud.card.level_label.text)
	_check(_hud.card.shown_stars == 1 and _hud.card.shown_total == 2, "card shows 1 of 2 stars (%d/%d)" % [_hud.card.shown_stars, _hud.card.shown_total])
	_check(_hud.card.reward_label.visible and _hud.card.reward_label.text.contains(tr(&"ABILITY_ENHANCED_JUMP")),
		"card announces the reward ability (%s)" % _hud.card.reward_label.text)
	_check(Sfx.played.has(&"fanfare"), "completion plays the fanfare")
	_check(get_tree().paused and GameManager.is_frozen, "the world freezes while the card shows")
	# A slime touching the player now must not hurt: enemies are frozen.
	var slime := get_tree().get_first_node_in_group(&"enemy") as Node3D
	var hearts_before := _player.health.current_health
	if slime:
		slime.global_position = _player.global_position
	await _steps(30)
	_check(_player.health.current_health == hearts_before, "frozen enemies deal no damage (%.0f -> %.0f)" % [hearts_before, _player.health.current_health])
	_check(_player.global_position.distance_to(Vector3(20.0, _player.global_position.y, -49.0)) < 3.0, "the player stays put while frozen")
	_check(_hud.card.footer_label.text.begins_with(tr(&"CARD_RETURNING").substr(0, 8)), "card counts down the return (%s)" % _hud.card.footer_label.text)
	await _steps(210)
	_check(_manager.is_in_hub(), "party is back in the hub after the delay")
	_check(not get_tree().paused and not GameManager.is_frozen, "the world thaws back in the hub")
	_check(not _hud.card.visible, "card is dismissed back in the hub")
	await _steps(5)
	_check(not _hud.loading_label.visible and not _hud.fade_rect.visible, "the loading screen is gone once the island is back")
	_check(result[0] != null and result[0].id == &"forest_trail" and result[1] == 1,
		"LevelManager reported forest_trail completed with 1 star")
	_check(_hud.objective_label.text == tr(&"HUD_HUB_HINT"), "HUD shows the hub hint again")
	_check(_player.health.current_health == _player.health.max_health,
		"hearts are refilled when the level ends (%.0f)" % _player.health.current_health)
	_check(_hud.stars_label.text == "1", "hub shows the total stars earned (%s)" % _hud.stars_label.text)
	await _steps(20)
	_check(_player.is_on_floor(), "character stands on the island")
	ProgressionManager.reset()


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
