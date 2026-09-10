extends Node
## Headless test for the island hub (Phase 2).
##
## Run:  godot --headless res://tools/tests/test_island_runner.tscn
##
## Loads the real main scene and checks: terrain generation and collision,
## the player landing on the flattened spawn pad, NPCs being real characters
## that are not players, prop scattering respecting its rules, the house being
## solid, walking across the island without falling through, and the sea
## respawning the player.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _terrain: IslandTerrain
var _camera_rig: ThirdPersonCamera


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_camera_rig = _scene.get_node("CameraRig")
	await _steps(10)

	_player = GameManager.get_player(0) as CharacterController
	if _player == null:
		_fail("main scene did not spawn a player")
		_finish()
		return

	var world: Node = _scene.get("world")
	_terrain = world.get_node_or_null("IslandTerrain") as IslandTerrain
	if _terrain == null:
		_fail("island has no IslandTerrain")
		_finish()
		return

	_test_terrain()
	await _test_spawn()
	_test_npcs(world)
	_test_scatter(world)
	await _test_walk()
	await _test_house()
	await _test_sea()
	_finish()


func _test_terrain() -> void:
	_check(_terrain.is_in_group(&"terrain"), "terrain is in the 'terrain' group")
	var mesh := _terrain.mesh_instance.mesh as ArrayMesh
	_check(mesh != null and mesh.get_surface_count() == 1, "terrain mesh generated")
	if mesh:
		var faces := mesh.get_faces().size() / 3
		_check(faces > 5000, "terrain has a real triangle count (%d)" % faces)
	_check(_terrain.collision.shape is ConcavePolygonShape3D, "terrain collision is a trimesh")
	if mesh:
		var faces := mesh.get_faces()
		var pad_faces := 0
		var up_faces := 0
		for i in range(0, faces.size(), 3):
			var centre := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			if Vector2(centre.x, centre.z).distance_to(Vector2(14.0, 12.0)) < 4.0:
				pad_faces += 1
				if Plane(faces[i], faces[i + 1], faces[i + 2]).normal.y > 0.9:
					up_faces += 1
		_check(pad_faces > 0 and up_faces == pad_faces,
			"terrain faces wind clockwise / face up (%d/%d on the pad)" % [up_faces, pad_faces])

	var pad := _terrain.sample_height(14.0, 12.0)
	_check(absf(pad - 3.5) < 0.05, "house pad is flattened to 3.5 (got %.2f)" % pad)
	var peak := _terrain.sample_height(_terrain.mountain_center.x, _terrain.mountain_center.y)
	_check(peak > 12.0, "mountain peak is high (%.1f)" % peak)
	var beach := _terrain.sample_height(0.0, 52.0)
	_check(beach > 0.2 and beach < 1.6, "beach is low and above water (%.2f)" % beach)
	var sea := _terrain.sample_height(0.0, _terrain.shore_radius + _terrain.drop_width + 1.0)
	_check(sea < -30.0, "terrain plunges past the shore (%.1f)" % sea)
	_check(_terrain.is_on_land(10.0, 10.0) and not _terrain.is_on_land(0.0, 70.0),
		"is_on_land distinguishes island from sea")
	var slope_flat := _terrain.sample_slope_degrees(14.0, 12.0)
	_check(slope_flat < 3.0, "house pad is level (%.1f deg)" % slope_flat)


func _test_spawn() -> void:
	await _steps(60)
	_check(_player.is_on_floor(), "player lands on the terrain")
	var expected := _terrain.sample_height(_player.global_position.x, _player.global_position.z)
	_check(absf(_player.global_position.y - expected) < 0.35,
		"player stands on the terrain surface (y %.2f vs terrain %.2f)"
		% [_player.global_position.y, expected])
	_check(_player.global_position.y > 2.5, "spawn is on the plateau, not in the sea")


func _test_npcs(world: Node) -> void:
	var npcs := world.find_children("*", "CharacterController", true, false)
	npcs = npcs.filter(func(n: Node) -> bool: return not (n as CharacterController).is_player_controlled)
	_check(npcs.size() >= 2, "island has at least two NPC characters (%d)" % npcs.size())
	_check(GameManager.players.size() == 1, "NPCs are not registered as players")

	var ids := {}
	for npc: CharacterController in npcs:
		ids[npc.definition.id] = true
		_check(npc.definition.id != _player.definition.id,
			"NPC '%s' uses a different definition than the player" % npc.definition.display_name)
		_check(npc.visual_root.get_child_count() == 1,
			"NPC '%s' has its placeholder visual" % npc.definition.display_name)
		_check(not npc.input.reads_local_device,
			"NPC '%s' ignores the local device" % npc.definition.display_name)
	_check(ids.size() == npcs.size(), "every NPC is a distinct character")

	# Same creature body, different colours: proves visuals are data too.
	var fox := _find_visual(npcs, &"fox")
	var panda := _find_visual(npcs, &"panda")
	if fox and panda:
		_check(fox.fur_color != panda.fur_color, "fox and panda share geometry but not colours")


func _find_visual(npcs: Array, id: StringName) -> CreaturePlaceholder:
	for npc: CharacterController in npcs:
		if npc.definition.id == id and npc.visual_root.get_child_count() > 0:
			return npc.visual_root.get_child(0) as CreaturePlaceholder
	return null


func _test_scatter(world: Node) -> void:
	var scatters := world.find_children("*", "PropScatter", true, false)
	_check(scatters.size() >= 3, "island has scatter groups (%d)" % scatters.size())
	var total := 0
	for scatter: PropScatter in scatters:
		var placed := scatter.placed_positions.size()
		total += placed
		_check(placed >= scatter.count * 0.6,
			"'%s' placed %d/%d props" % [scatter.name, placed, scatter.count])
		var all_ok := true
		for p in scatter.placed_positions:
			if not _terrain.is_on_land(p.x, p.z):
				all_ok = false
			if _terrain.sample_slope_degrees(p.x, p.z) > scatter.max_slope_degrees + 0.01:
				all_ok = false
			for zone in scatter.exclusion_zones:
				if Vector2(p.x, p.z).distance_to(Vector2(zone.x, zone.y)) < zone.z:
					all_ok = false
		_check(all_ok, "'%s' respects land, slope and exclusion rules" % scatter.name)
	_check(total > 80, "island is populated (%d props)" % total)

	# Nothing scattered on the house pad.
	var house_hits := 0
	for scatter: PropScatter in scatters:
		for p in scatter.placed_positions:
			if Vector2(p.x, p.z).distance_to(Vector2(14.0, 12.0)) < 8.0:
				house_hits += 1
	_check(house_hits == 0, "house pad is clear of props (%d)" % house_hits)


func _test_walk() -> void:
	# Run from the house pad down to the beach (camera facing +Z) and make sure
	# we never fall through the mesh on the way.
	_camera_rig.set_yaw(PI)
	var start := Vector3(14.0, 4.5, 24.0)
	_player.global_position = start
	_player.motor.reset()
	await _steps(20)
	Input.action_press(InputActions.RUN)
	var airborne_frames := 0
	var lowest := 1000.0
	Input.action_press(&"move_forward")
	for i in 200:
		await _steps(1)
		if not _player.is_on_floor():
			airborne_frames += 1
		lowest = minf(lowest, _player.global_position.y)
	Input.action_release(&"move_forward")
	Input.action_release(InputActions.RUN)
	var travelled := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(travelled > 10.0, "ran down toward the beach (%.1fm)" % travelled)
	_check(airborne_frames < 60, "stayed grounded while running (%d airborne frames)" % airborne_frames)
	_check(lowest > 0.3, "never fell through the terrain (lowest y %.2f)" % lowest)
	await _steps(20)


func _test_house() -> void:
	# Walk into the house front wall: it must block.
	_camera_rig.set_yaw(0.0)
	_player.global_position = Vector3(14.0, 4.0, 20.0)
	_player.motor.reset()
	await _steps(20)
	await _hold(&"move_forward", 120)
	# Body is 6.5 deep centred at z=12 -> front face at z=15.25.
	_check(_player.global_position.z > 15.4,
		"house wall blocks the player (z %.2f)" % _player.global_position.z)
	await _steps(10)


func _test_sea() -> void:
	# Beyond the shore the ground drops away; the player must respawn.
	var spawn := _player.spawn_transform.origin
	_player.global_position = Vector3(0.0, 2.0, _terrain.shore_radius + 4.0)
	_player.motor.reset()
	var respawned := false
	for i in 600:
		await _steps(1)
		if _player.global_position.distance_to(spawn) < 2.0:
			respawned = true
			break
	_check(respawned, "walking into the sea respawns the player")


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


func _fail(description: String) -> void:
	_check(false, description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
