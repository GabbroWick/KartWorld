extends Node
## Headless test for portals and level transitions (Phase 4).
##
## Run:  godot --headless res://tools/tests/test_portal_runner.tscn
##
## Loads the real main scene (island hub), walks the player into the portal,
## checks the level scene replaced the hub with player and kart at the level's
## spawn, then walks into the return portal and checks the hub is back.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _manager: LevelManager
var _camera_rig: ThirdPersonCamera


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = "user://test_scratch_save.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_camera_rig = _scene.get_node("CameraRig")
	await _steps(20)

	_player = GameManager.get_player(0) as CharacterController
	_manager = get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	if _player == null or _manager == null:
		_fail("main scene did not provide a player and a LevelManager")
		_finish()
		return

	_test_hub_setup()
	await _test_grace()
	await _test_enter_level()
	await _test_kart_travels()
	await _test_return()
	await _test_drive_through()
	_finish()


func _test_hub_setup() -> void:
	_check(_manager.is_in_hub(), "game starts in the hub")
	var portals := _manager.world.find_children("*", "Portal", true, false)
	_check(portals.size() >= 1, "hub has at least one portal (%d)" % portals.size())
	if portals.size() > 0:
		var portal: Portal = portals[0]
		_check(portal.level != null and portal.level.id == &"forest_trail",
			"hub portal leads to the Forest Trail level")
		_check(not portal.returns_to_hub, "hub portal is an outbound portal")
		_check(portal.label.text == tr(&"LEVEL_FOREST_TRAIL_NAME"), "portal shows the level name")
	var site := _manager.world.find_children("*", "Marker3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group(&"portal_site"))
	_check(site.size() == 1, "hub still has its portal_site marker")


func _test_grace() -> void:
	# Right after a load portals are inert; dropping the player inside one
	# must not trigger it.
	var portal: Portal = _manager.world.find_children("*", "Portal", true, false)[0]
	_manager._loaded_at = Time.get_ticks_msec() / 1000.0
	_player.global_position = portal.global_position + Vector3.UP * 0.3
	await _steps(10)
	_check(_manager.is_in_hub(), "portal ignores the player during the grace period")
	_player.global_position = portal.global_position + Vector3(0, 0.3, 6.0)
	_player.motor.reset()
	await _steps(5)


func _test_enter_level() -> void:
	var portal: Portal = _manager.world.find_children("*", "Portal", true, false)[0]
	_manager._loaded_at = -1000.0
	var fired := [false]
	portal.activated.connect(func(_by: Node) -> void: fired[0] = true)
	var loaded := [null]
	var arrival := [Vector3.ZERO]
	_manager.level_loaded.connect(func(d: LevelDefinition) -> void:
		loaded[0] = d
		arrival[0] = _player.global_position)

	# Walk into it (camera facing -Z, portal is 6 m ahead at -Z).
	_camera_rig.set_yaw(0.0)
	await _hold(&"move_forward", 90)
	await _steps(10)
	_check(fired[0], "walking into the portal activates it")
	_check(loaded[0] != null and loaded[0].id == &"forest_trail", "LevelManager loaded the Forest Trail")
	_check(not _manager.is_in_hub() and _manager.current_level != null, "manager reports being in a level")
	_check(_manager.world != null and _manager.world.name == "ForestTrail", "world node is the level scene")
	_check(_manager.world.get_parent() == _scene, "level scene sits where the hub was")
	_check(_scene.get_child(0) == _manager.world, "level scene is first in the tree (camera updates last)")
	var hubs := _scene.find_children("IslandHub", "", true, false)
	_check(hubs.is_empty(), "hub scene was freed")

	await _steps(30)
	var spawn := _manager.find_spawn_point()
	_check(spawn != null, "level has a player_spawn marker")
	if spawn:
		_check(arrival[0].distance_to(spawn.global_position) < 1.0,
			"player arrives at the level spawn (%.1fm off)" % arrival[0].distance_to(spawn.global_position))
	_check(_player.is_on_floor(), "player is on the level's ground")
	_check(_camera_rig.target == _player, "camera follows the player in the level")


func _test_kart_travels() -> void:
	var kart := _player.driver.vehicle
	_check(kart != null and kart.get_parent() == _scene, "kart still exists after the swap")
	_check(kart.global_position.distance_to(_player.global_position) < 6.0,
		"kart came along and is parked near the level spawn (%.1fm)" % kart.global_position.distance_to(_player.global_position))
	_check(kart.is_on_floor(), "kart rests on the level ground")


func _test_return() -> void:
	var portals := _manager.world.find_children("*", "Portal", true, false)
	_check(portals.size() == 1, "level has one return portal")
	var portal: Portal = portals[0]
	_check(portal.returns_to_hub, "level portal returns to the hub")
	_manager._loaded_at = -1000.0
	var arrival := [Vector3.ZERO]
	_manager.hub_loaded.connect(func() -> void: arrival[0] = _player.global_position)
	_player.global_position = portal.global_position + Vector3(0, 0.3, 5.0)
	_player.motor.reset()
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	await _hold(&"move_forward", 80)
	await _steps(10)
	_check(_manager.is_in_hub(), "walking into the return portal brings the hub back")
	_check(_manager.world.name == "IslandHub", "world node is the island again")
	await _steps(30)
	var spawn := _manager.find_spawn_point()
	_check(spawn and arrival[0].distance_to(spawn.global_position) < 1.0,
		"player arrives back at the hub spawn")
	_check(_player.is_on_floor(), "player stands on the island")
	_check(_player.driver.vehicle.get_parent() == _scene, "kart survived the round trip")


func _test_drive_through() -> void:
	# Driving the kart into a portal must work too and eject the driver on arrival.
	var portal: Portal = _manager.world.find_children("*", "Portal", true, false)[0]
	_manager._loaded_at = -1000.0
	var kart := _player.driver.vehicle
	kart.place(Transform3D(Basis.IDENTITY, portal.global_position + Vector3(0, 0.3, 8.0)))
	_player.global_position = kart.global_position + Vector3(2.0, 0.3, 0.0)
	_player.motor.reset()
	await _steps(5)
	await _press(InputActions.INTERACT)
	await _steps(3)
	_check(_player.driver.is_driving, "player is driving toward the portal")
	await _hold(InputActions.ACCELERATE, 70)
	await _steps(10)
	_check(not _manager.is_in_hub(), "driving into the portal enters the level")
	_check(not _player.driver.is_driving, "driver is out of the kart on arrival")
	_check(_player.visible, "character is visible in the level")
	await _steps(20)
	_check(_player.is_on_floor(), "player is on the ground after arriving by kart")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
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


func _fail(description: String) -> void:
	_check(false, description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
