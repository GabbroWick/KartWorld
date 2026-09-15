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
var _hud: GameHUD


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
	await _test_map()
	await _test_character_select()
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


func _test_translations() -> void:
	# Every CSV row must have exactly key, en, it: an unquoted comma inside
	# a sentence shifted the columns once ("you just did." showed up alone).
	var file := FileAccess.open("res://translations/text.csv", FileAccess.READ)
	file.get_csv_line()
	var broken := PackedStringArray()
	var rows := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		rows += 1
		if row.size() != 3 or row[2].strip_edges() == "":
			broken.append(row[0])
		elif tr(row[0]) != row[2]:
			broken.append(row[0] + " (tr mismatch)")
	_check(rows > 40 and broken.is_empty(), "every translation row has key/en/it and resolves in Italian (%d rows, broken: %s)" % [rows, ", ".join(broken)])


func _test_character_select() -> void:
	# The pause menu cycles the hero; NPCs never duplicate the hero.
	var menu: PauseMenu = _scene.get_node("PauseMenu")
	var main: Node = _scene
	_check(_player.definition.id == &"leopard", "default hero is the leopard")
	var fox_before := _manager.world.get_node("NPCs/Fox") as CharacterController
	_check(fox_before and fox_before.definition.id == &"fox", "the hand-placed fox NPC is a fox while the hero is the leopard")
	menu.character_button.pressed.emit()
	await _steps(2)
	_check(menu.picker.visible and menu.cards.get_child_count() == 3, "Personaggio opens a picker with three portrait cards")
	var fox_card: Button = menu.cards.get_child(1)
	_check(fox_card.get_meta(&"id") == &"fox" and fox_card.find_children("*", "TextureRect", true, false)[0].texture != null, "fox card carries a portrait")
	fox_card.pressed.emit()
	await _steps(15)
	_player = GameManager.get_player(0) as CharacterController
	_check(_player.definition.id == &"fox", "hero becomes the fox (%s)" % _player.definition.id)
	_check(_player.get_visual() != null and _player.get_visual().scene_file_path.contains("fox"), "hero wears the fox model")
	_check(ProgressionManager.character == &"fox" and FileAccess.get_file_as_string(SCRATCH_SAVE).contains("\"fox\""), "choice is saved")
	var fox_after := _manager.world.get_node("NPCs/Fox") as CharacterController
	_check(fox_after and fox_after.definition.id == &"leopard", "the fox NPC is re-cast as the leopard (%s)" % (fox_after.definition.id if fox_after else "-"))
	_check(menu.character_button.text == tr(&"PAUSE_CHARACTER") % tr(&"CHAR_FOX"), "pause menu shows the current hero (%s)" % menu.character_button.text)
	_check(not menu.picker.visible, "picking a card closes the picker")
	main.set_character(&"leopard")
	await _steps(15)
	_player = GameManager.get_player(0) as CharacterController
	_check(_player.definition.id == &"leopard", "back to the leopard")


func _test_map() -> void:
	# Minimap in the hub, full map on M, painted from the terrain.
	_check(_hud.minimap.visible, "minimap is shown in the hub")
	var waited := 0
	while not _hud.world_map.is_ready and waited < 900:
		await _steps(1)
		waited += 1
	_check(_hud.world_map.is_ready and _hud.world_map.texture != null, "world map is painted (%d frames)" % waited)
	var tex_size: Vector2i = _hud.world_map.texture.get_size()
	_check(tex_size.x > 200 and tex_size.y > 100, "map covers both islands (%dx%d)" % [tex_size.x, tex_size.y])
	var uv: Vector2 = _hud.world_map.to_uv(Vector3(1500.0, 0.0, -350.0))
	_check(uv.x > 0.7 and uv.y > 0.1 and uv.y < 0.6, "Porto lands on the right of the map (%.2f, %.2f)" % [uv.x, uv.y])
	var kinds := {}
	for m in _hud.world_map.markers():
		kinds[m["kind"]] = kinds.get(m["kind"], 0) + 1
	_check(kinds.get("door", 0) == 3 and kinds.get("home", 0) == 1 and kinds.get("village", 0) == 3,
		"map markers: 3 doors, the house, 3 villages (%s)" % str(kinds))
	_press_action(InputActions.MAP)
	await _steps(2)
	_check(_hud.full_map.visible, "M opens the full map")
	_press_action(InputActions.MAP)
	await _steps(2)
	_check(not _hud.full_map.visible, "M again closes it")


func _press_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _test_hub_setup() -> void:
	_test_translations()
	_check(_hub_stars().size() == 6, "island has six persistent stars (%d)" % _hub_stars().size())
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
	_check(_hub_stars().size() == 5, "collected hub star does not respawn (%d left)" % _hub_stars().size())
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
