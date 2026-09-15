extends Node
## Headless test for Level 3 "Vulcano" and its new mechanics (Phase 9).
##
## Run:  godot --headless res://tools/tests/test_volcano_runner.tscn
##
## Loads the level through the LevelManager and checks: the TrackRibbon
## (length, ramps, kart stays on it and climbs), Spring launches, a
## MovingPlatform carries the player, lethal lava respawns at the
## checkpoint, spikes deal one heart, and killing the slimes + entering
## the crater portal completes the level with its stars.

const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL := "res://resources/levels/level_03_volcano.tres"

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
	ProgressionManager.save_path = "user://test_volcano_save.json"
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
	await _test_track()
	await _test_spring()
	await _test_platform()
	await _test_lava()
	await _test_spikes()
	await _test_finish()
	_finish()


func _test_load() -> void:
	_manager.load_level(load(LEVEL))
	await _steps(10)
	_world = _manager.world
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	_check(_level != null, "Vulcano has a LevelController")
	if _level == null:
		return
	_check(_level.objectives.size() == 3, "three objectives (%d)" % _level.objectives.size())
	_check(_level.stars_total == 3, "level counts three stars (%d)" % _level.stars_total)
	var slimes := get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return _level.owns(e))
	_check(slimes.size() == 3, "three slimes in the crater (%d)" % slimes.size())
	_check(_hud.objective_label.text.begins_with(tr(&"OBJ_DEFEAT_SLIMES")), "HUD shows the slime objective (%s)" % _hud.objective_label.text)
	var kart := _player.driver.vehicle
	_check(kart.global_position.distance_to(_player.global_position) < 8.0, "kart parked next to the spawn (%.1f m)" % kart.global_position.distance_to(_player.global_position))
	_check(_player.is_on_floor(), "player stands on the start pad")


func _test_track() -> void:
	var track := _world.get_node("Track") as TrackRibbon
	_check(track != null and track.length() > 600.0, "track ribbon is long (%.0f m)" % (track.length() if track else 0.0))
	var ramps := track.find_children("*", "Ramp", false, false)
	_check(ramps.size() == 3, "track carries three ramps (%d)" % ramps.size())
	# Put the kart on the track a bit before the first ramp and floor it.
	var kart := _player.driver.vehicle
	var pose := track.global_transform * track.pose_at(0.2)
	pose.origin.y += 0.4
	kart.place(pose)
	_player.global_position = pose.origin + pose.basis.x * 2.0 + Vector3.UP * 0.5
	_player.motor.reset()
	await _steps(10)
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.driver.is_driving, "in the kart on the track")
	var start := kart.global_position
	var airborne := 0
	var off_track := 0
	Input.action_press(InputActions.ACCELERATE)
	var curve := track.get_curve()
	for i in 420:
		await _steps(1)
		if not kart.is_on_floor():
			airborne += 1
		var local := track.global_transform.affine_inverse() * kart.global_position
		var nearest := INF
		var nearest_i := 0
		for k in curve.size():
			var p := curve[k]
			var d := Vector2(p.x - local.x, p.z - local.z).length()
			if d < nearest:
				nearest = d
				nearest_i = k
		if nearest > track.width * 0.5 + 1.0:
			off_track += 1
		# Steer like a driver would: toward a point a few samples ahead.
		var target := track.global_transform * curve[mini(nearest_i + 3, curve.size() - 1)]
		var forward := -kart.global_basis.z
		var to_target := target - kart.global_position
		var angle := Vector2(forward.x, forward.z).angle_to(Vector2(to_target.x, to_target.z))
		_strength(InputActions.MOVE_RIGHT, clampf(angle / 0.5, 0.0, 1.0))
		_strength(InputActions.MOVE_LEFT, clampf(-angle / 0.5, 0.0, 1.0))
	Input.action_release(InputActions.ACCELERATE)
	_strength(InputActions.MOVE_RIGHT, 0.0)
	_strength(InputActions.MOVE_LEFT, 0.0)
	var travelled := start.distance_to(kart.global_position)
	_check(travelled > 60.0, "kart drives along the ribbon (%.0f m in 7 s)" % travelled)
	_check(off_track == 0, "kart never leaves the ribbon (%d frames off)" % off_track)
	_check(kart.global_position.y > start.y + 1.0, "track climbs (%.1f m up)" % (kart.global_position.y - start.y))
	_check(airborne >= 6, "kart jumps off the track ramp (%d frames in the air)" % airborne)
	await _hold(InputActions.INTERACT, 3)
	await _steps(10)


func _test_spring() -> void:
	var spring := _world.get_node("Spring1") as Spring
	var from := spring.global_position + Vector3(4.0, 0.5, 0.0)
	_teleport(from)
	await _steps(5)
	var y0 := _player.global_position.y
	_camera_rig.set_yaw(PI * 0.5)   # face -X
	Input.action_press(InputActions.MOVE_FORWARD)
	var top := y0
	var launched := false
	for i in 90:
		await _steps(1)
		top = maxf(top, _player.global_position.y)
		if _player.global_position.y > y0 + 4.0:
			launched = true
	Input.action_release(InputActions.MOVE_FORWARD)
	_check(launched, "spring throws the character up (%.1f m)" % (top - y0))
	_check(top - y0 > spring.height * 0.8, "spring reaches its height (%.1f of %.1f m)" % [top - y0, spring.height])
	await _steps(30)


func _test_platform() -> void:
	var ferry := _world.get_node("Ferry1") as MovingPlatform
	_teleport(ferry.global_position + Vector3(0.0, 0.8, 0.0))
	await _steps(5)
	var before := _player.global_position
	var ferry_before := ferry.global_position
	var carried := 0.0
	var moved := 0.0
	for i in 240:
		await _steps(1)
		carried = maxf(carried, _player.global_position.distance_to(before))
		moved = maxf(moved, ferry.global_position.distance_to(ferry_before))
	_check(moved > 2.0, "moving platform travels (%.1f m)" % moved)
	_check(carried > 2.0 and _player.is_on_floor(), "character rides the moving platform (%.1f m)" % carried)


func _test_lava() -> void:
	var checkpoint := _world.get_node("Checkpoint1") as Checkpoint
	_teleport(checkpoint.global_position + Vector3(0.0, 0.3, 0.0))
	await _steps(5)
	_check(checkpoint.is_active, "checkpoint on the top pad activates")
	var died := [false]
	_player.died.connect(func() -> void: died[0] = true)
	var lava := _world.get_node("LavaLake") as Hazard
	_teleport(lava.global_position + Vector3(0.0, 1.5, 0.0))
	await _steps(40)
	_check(died[0], "lava kills the character")
	_check(_player.global_position.distance_to(checkpoint.respawn_point.global_position) < 1.5,
		"character respawns at the checkpoint after lava (%.1f m)" % _player.global_position.distance_to(checkpoint.respawn_point.global_position))
	# A kart in lava comes back too.
	var kart := _player.driver.vehicle
	kart.place(Transform3D(Basis.IDENTITY, lava.global_position + Vector3(4.0, 1.5, 0.0)))
	await _steps(40)
	_check(kart.global_position.distance_to(checkpoint.respawn_point.global_position) < 8.0,
		"kart driven into lava is brought back to the checkpoint (%.1f m)" % kart.global_position.distance_to(checkpoint.respawn_point.global_position))
	await _steps(10)


func _test_spikes() -> void:
	var spikes := _world.get_node("Spikes") as Hazard
	_player.health.restore_full()
	_player.invulnerable_left = 0.0
	var hearts := _player.health.current_health
	_teleport(spikes.global_position + Vector3(0.0, 0.8, 0.0))
	await _steps(30)
	_check(_player.health.current_health == hearts - 1.0, "spikes cost one heart (%.0f -> %.0f)" % [hearts, _player.health.current_health])
	_check(not _player.health.is_dead, "spikes are not lethal")
	await _steps(20)


func _test_finish() -> void:
	var done := [-1]
	_level.completed.connect(func(stars: int) -> void: done[0] = stars)
	# Grab the crater star, kill the slimes, walk into the portal.
	var star := _world.get_node("StarCrater") as Star
	_teleport(star.global_position + Vector3(0.0, -0.5, 0.0))
	await _steps(5)
	_check(_level.stars_collected == 1, "crater star collected (%d)" % _level.stars_collected)
	_teleport(Vector3(-56.0, 33.3, -150.0))
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if _level.owns(e):
			(e as Enemy).take_damage(10.0, _player)
	await _steps(10)
	_check(done[0] == -1, "level not complete before reaching the crater portal")
	_check(_hud.objective_label.text == tr(&"OBJ_REACH_CRATER"), "HUD moves on to the portal objective (%s)" % _hud.objective_label.text)
	_camera_rig.set_yaw(PI * 0.5)
	await _hold(InputActions.MOVE_FORWARD, 60)
	await _steps(5)
	_check(done[0] == 1, "entering the crater portal completes Vulcano with 1 star (got %d)" % done[0])
	_check(_hud.card.visible and _hud.card.level_label.text == tr(&"LEVEL_VOLCANO_NAME"), "card names Vulcano (%s)" % _hud.card.level_label.text)
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
