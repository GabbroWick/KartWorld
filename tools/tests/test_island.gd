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
	# Never let the player's real progress (triple jump!) leak into a suite.
	ProgressionManager.save_path = "user://test_scratch_save.json"
	ProgressionManager.reset()
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
	await _test_kart_parked_still()
	await _test_kart_on_terrain()
	await _test_kart_climbs_mountain()
	await _test_npcs_alive()
	await _test_sea()
	_finish()


func _test_kart_climbs_mountain() -> void:
	# From the foot of the mountain straight at the peak: the kart must gain
	# real height and lean with the slope while doing it.
	var kart := _player.driver.vehicle
	var peak := Vector3(_terrain.mountain_center.x, 0.0, _terrain.mountain_center.y)
	# Start on the steep flank (the huge mountain is nearly flat near its top).
	var foot := peak + Vector3(0.0, 0.0, _terrain.mountain_radius * 0.6)
	foot.y = _terrain.sample_height(foot.x, foot.z) + 0.3
	_ensure_ground(foot)
	var heading := (peak - foot)
	heading.y = 0.0
	kart.place(Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), foot))
	_player.global_position = foot + Vector3(2.0, 0.5, 0.0)
	_player.motor.reset()
	await _steps(10)
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.driver.is_driving, "in the kart at the mountain foot")
	var start_y := kart.global_position.y
	var max_tilt := 0.0
	Input.action_press(InputActions.ACCELERATE)
	for i in 180:
		await _steps(1)
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(kart.visual_root.global_basis.y.dot(Vector3.UP), -1.0, 1.0))))
	Input.action_release(InputActions.ACCELERATE)
	var climbed := kart.global_position.y - start_y
	_check(climbed > 5.0, "kart climbs the mountain (%.1f m up in 3 s, slope max %.0f deg)"
		% [climbed, max_tilt])
	_check(max_tilt > 12.0, "kart model leans with the slope (max %.0f deg)" % max_tilt)
	# The lean must follow the ground, not mirror it (a sign bug once did).
	# Compare with the terrain's analytic normal: the sphere collider's contact
	# normal is one triangle of a 1.5 m grid, the visual averages four rays.
	var kp := kart.global_position
	var agreement := kart.visual_root.global_basis.y.dot(_terrain.sample_normal(kp.x, kp.z))
	# The visual pitch is clamped (~35 deg) for readability, so on a 55 deg
	# flank it cannot match fully; it must still lean the right way.
	_check(agreement > 0.85, "kart model's up follows the terrain normal (dot %.3f)" % agreement)
	_check(kart.is_on_floor(), "kart still on the ground on the hillside")
	await _hold(InputActions.INTERACT, 3)
	await _steps(20)


func _test_npcs_alive() -> void:
	# The hand-placed fox by the house (villagers far away may be parked on
	# unbuilt terrain tiles, by design).
	var fox := _scene.get("world").get_node_or_null("NPCs/Fox") as CharacterController
	_check(fox != null and fox.definition.id == &"fox", "fox NPC found")
	if fox == null:
		return
	var behaviour := fox.get_node_or_null("Behaviour") as NpcBehaviour
	_check(behaviour != null, "fox has an NpcBehaviour")
	# Stand far away so it wanders instead of staring at us.
	_player.global_position = Vector3(60.0, 5.0, 98.0)
	_player.motor.reset()
	var start := fox.global_position
	var moved := 0.0
	for i in 300:
		await _steps(1)
		moved = maxf(moved, fox.global_position.distance_to(start))
	_check(moved > 0.8, "fox wanders around on its own (%.1f m)" % moved)
	_check(fox.global_position.distance_to(behaviour.home) < behaviour.wander_radius + 1.5,
		"fox stays near its home (%.1f m)" % fox.global_position.distance_to(behaviour.home))

	# Walk up: prompt says talk, E shows a speech bubble.
	_player.global_position = fox.global_position + Vector3(0.0, 0.3, 1.8)
	_player.motor.reset()
	await _steps(20)
	var prompt: String = _player.interaction.get_prompt()
	_check(prompt == tr(&"PROMPT_TALK") % tr(&"CHAR_FOX"), "prompt offers to talk (%s)" % prompt)
	var said := [""]
	behaviour.spoke.connect(func(line: String) -> void: said[0] = line)
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(said[0] != "", "pressing E makes the fox talk (%s)" % said[0])
	_check(behaviour._bubble != null and behaviour._bubble.visible, "speech bubble is visible")
	_check(not _player.driver.is_driving, "talking did not put the player in the kart")


func _test_kart_parked_still() -> void:
	# A parked kart on the (slightly sloped) pad must not creep on its own.
	var kart := _player.driver.vehicle
	var before := kart.global_position
	await _steps(90)
	_check(kart.global_position.distance_to(before) < 0.05,
		"parked kart stays put (%.3f m in 1.5 s)" % kart.global_position.distance_to(before))


func _test_kart_on_terrain() -> void:
	# The kart suite runs on flat ground; here it has to cope with the island's
	# slopes and trimesh collision: drive from the house pad down to the beach.
	var start_point := Vector3(60.0, 5.0, 92.0)
	var heading := _clear_heading(start_point, 32.0)
	_check(heading != Vector3.ZERO, "found a tree-free corridor to drive along")
	_player.global_position = start_point
	_player.motor.reset()
	_player.visual_root.global_rotation.y = atan2(-heading.x, -heading.z)
	await _steps(20)
	Input.action_press(InputActions.SUMMON_KART)
	await _steps(3)
	Input.action_release(InputActions.SUMMON_KART)
	await _steps(15)
	var kart := _player.driver.vehicle
	_check(kart != null and kart.is_on_floor(), "summoned kart sits on the island terrain")
	_check(kart.global_position.y < _player.global_position.y + 1.0,
		"summoned kart is at ground level, not on something (y %.2f vs player %.2f)"
		% [kart.global_position.y, _player.global_position.y])
	Input.action_press(InputActions.INTERACT)
	await _steps(3)
	Input.action_release(InputActions.INTERACT)
	await _steps(3)
	_check(_player.driver.is_driving, "entered the kart on the island")

	var start := kart.global_position
	var airborne := 0
	var top_speed := 0.0
	# Two seconds: enough to prove the descent, short of the shore drop now
	# that the kart keeps its speed on slopes.
	Input.action_press(InputActions.ACCELERATE)
	for i in 110:
		await _steps(1)
		if not kart.is_on_floor():
			airborne += 1
		top_speed = maxf(top_speed, kart.get_speed())
	Input.action_release(InputActions.ACCELERATE)
	var travelled := Vector2(kart.global_position.x - start.x, kart.global_position.z - start.z).length()
	_check(travelled > 15.0, "kart drove down the slope (%.1fm, top speed %.1f, from %s to %s, facing %s)"
		% [travelled, top_speed, start, kart.global_position, -kart.global_basis.z])
	_check(airborne < 55, "kart mostly kept contact with the terrain (%d airborne frames)" % airborne)
	_check(kart.global_position.y > 0.0, "kart did not fall through the terrain (y %.2f)" % kart.global_position.y)

	Input.action_press(InputActions.INTERACT)
	await _steps(3)
	Input.action_release(InputActions.INTERACT)
	await _steps(30)
	_check(not _player.driver.is_driving and _player.is_on_floor(),
		"left the kart and landed on the terrain")


func _test_terrain() -> void:
	_check(_terrain.is_in_group(&"terrain"), "terrain is in the 'terrain' group")
	_check(_terrain.streaming, "hub terrain streams in chunks")
	var house := Vector2(60.0, 80.0)
	# The tile under the house must be built with collision (the player spawns there).
	_check(_terrain.is_built_at(house.x, house.y), "terrain tile under the house is built with collision")
	var near_tiles := 0
	var near_faces := 0
	var pad_faces := 0
	var up_faces := 0
	for tile in _terrain._chunks:
		var chunk: Dictionary = _terrain._chunks[tile]
		if not chunk["near"]:
			continue
		near_tiles += 1
		var mesh := (chunk["node"] as MeshInstance3D).mesh as ArrayMesh
		var faces := mesh.get_faces()
		near_faces += faces.size() / 3
		_check(chunk["shape"] != null and (chunk["shape"] as CollisionShape3D).shape is ConcavePolygonShape3D,
			"near tile %s has a trimesh collision" % tile) if near_tiles == 1 else null
		for i in range(0, faces.size(), 3):
			var centre := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			if Vector2(centre.x, centre.z).distance_to(house) < 5.0:
				pad_faces += 1
				if Plane(faces[i], faces[i + 1], faces[i + 2]).normal.y > 0.9:
					up_faces += 1
	_check(near_tiles >= 9, "detailed tiles around the spawn (%d)" % near_tiles)
	_check(near_faces > 5000, "near terrain has a real triangle count (%d)" % near_faces)
	_check(pad_faces > 0 and up_faces == pad_faces,
		"terrain faces wind clockwise / face up (%d/%d on the pad)" % [up_faces, pad_faces])

	var pad := _terrain.sample_height(house.x, house.y)
	_check(absf(pad - 4.0) < 0.05, "house pad is flattened to 4.0 (got %.2f)" % pad)
	var peak := _terrain.sample_height(_terrain.mountain_center.x, _terrain.mountain_center.y)
	_check(peak > 50.0, "main mountain peak is high (%.1f)" % peak)
	var beach := _terrain.sample_height(0.0, _terrain.shore_radius - 2.0)
	_check(beach > 0.2 and beach < 1.6, "beach is low and above water (%.2f)" % beach)
	var sea := _terrain.sample_height(0.0, _terrain.shore_radius + _terrain.drop_width + 1.0)
	_check(sea < -30.0, "terrain plunges past the shore (%.1f)" % sea)
	_check(_terrain.is_on_land(10.0, 10.0) and not _terrain.is_on_land(0.0, _terrain.shore_radius + 16.0),
		"is_on_land distinguishes island from sea")
	var slope_flat := _terrain.sample_slope_degrees(house.x, house.y)
	_check(slope_flat < 3.0, "house pad is level (%.1f deg)" % slope_flat)
	_check(_terrain.road_length() > 9000.0, "kart road network is over 9 km (%.0f m)" % _terrain.road_length())
	var on_road := _terrain.is_on_road(570.0, 0.0)
	_check(on_road, "the coast road passes the east beach star")
	_check(_terrain.sample_slope_degrees(570.0, 0.0) < 8.0, "road is gentle there (%.1f deg)" % _terrain.sample_slope_degrees(570.0, 0.0))


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
		_check(npc.visual_root.get_children().any(func(c: Node) -> bool: return c.has_method(&"animate")),
			"NPC '%s' has an animatable visual" % npc.definition.display_name)
		_check(not npc.input.reads_local_device,
			"NPC '%s' ignores the local device" % npc.definition.display_name)
	_check(ids.size() >= 2, "NPCs use at least two different characters (%d kinds over %d NPCs)" % [ids.size(), npcs.size()])

	# Same creature body, different colours: proves visuals are data too.
	var fox := _find_visual(npcs, &"fox")
	var panda := _find_visual(npcs, &"panda")
	if fox and panda:
		_check(fox.fur_color != panda.fur_color, "fox and panda share geometry but not colours")


func _find_visual(npcs: Array, id: StringName) -> CreaturePlaceholder:
	for npc: CharacterController in npcs:
		if npc.definition.id == id:
			for child in npc.visual_root.get_children():
				if child is CreaturePlaceholder:
					return child
	return null


func _test_scatter(world: Node) -> void:
	var scatters := world.find_children("*", "PropScatter", true, false)
	_check(scatters.size() >= 3, "island has scatter groups (%d)" % scatters.size())
	var total := 0
	for scatter: PropScatter in scatters:
		# Streaming scatters own their props per tile; collect what exists now.
		var placed := PackedVector3Array()
		for child in scatter.get_children():
			if child.has_meta(&"scattered"):
				placed.append((child as Node3D).position)
		scatter.placed_positions = placed
		total += placed.size()
		_check(scatter.density > 0.0, "'%s' is a streaming scatter (density %.1f)" % [scatter.name, scatter.density])
		var all_ok := true
		for p in placed:
			if not _terrain.is_on_land(p.x, p.z):
				all_ok = false
			if _terrain.sample_slope_degrees(p.x, p.z) > scatter.max_slope_degrees + 0.01:
				all_ok = false
			for zone in scatter.exclusion_zones:
				if Vector2(p.x, p.z).distance_to(Vector2(zone.x, zone.y)) < zone.z:
					all_ok = false
			if scatter.road_clearance >= 0.0 and _terrain.road_distance(p.x, p.z) < _terrain.road_width * 0.5:
				all_ok = false
		_check(all_ok, "'%s' respects land, slope, road and exclusion rules" % scatter.name)
	_check(total > 80, "area around the spawn is populated (%d props)" % total)

	# Nothing scattered on the house pad.
	var house_hits := 0
	for scatter: PropScatter in scatters:
		for p in scatter.placed_positions:
			if Vector2(p.x, p.z).distance_to(Vector2(60.0, 80.0)) < 8.0:
				house_hits += 1
	_check(house_hits == 0, "house pad is clear of props (%d)" % house_hits)


func _test_walk() -> void:
	# Run from the house pad down to the beach (camera facing +Z) and make sure
	# we never fall through the mesh on the way.
	_camera_rig.set_yaw(PI)
	var start := Vector3(60.0, 5.0, 92.0)
	_player.global_position = start
	_player.motor.reset()
	await _steps(20)
	Input.action_press(InputActions.RUN)
	var airborne_frames := 0
	var lowest := 1000.0
	# 2 s at run speed reaches the beach but stays short of the shore drop.
	Input.action_press(&"move_forward")
	for i in 120:
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
	_player.global_position = Vector3(60.0, 4.5, 88.0)
	_player.motor.reset()
	await _steps(20)
	await _hold(&"move_forward", 120)
	# Body is 6.5 deep centred at z=80 -> front face at z=83.25.
	_check(_player.global_position.z > 83.4,
		"house wall blocks the player (z %.2f)" % _player.global_position.z)
	await _steps(10)


func _test_sea() -> void:
	# Beyond the shore the ground drops away; the player must respawn.
	var spawn := _player.spawn_transform.origin
	_ensure_ground(Vector3(0.0, 2.0, _terrain.shore_radius + 4.0))
	_player.global_position = Vector3(0.0, 2.0, _terrain.shore_radius + 4.0)
	_player.motor.reset()
	var respawned := false
	for i in 600:
		await _steps(1)
		if _player.global_position.distance_to(spawn) < 2.0:
			respawned = true
			break
	_check(respawned, "walking into the sea respawns the player")


## A horizontal unit vector from `from` along which a `length` metre corridor
## (4 m wide) stays on land and contains no scattered prop. ZERO if none.
func _clear_heading(from: Vector3, length: float) -> Vector3:
	var props: PackedVector3Array = []
	for scatter: PropScatter in _scene.get("world").find_children("*", "PropScatter", true, false):
		if scatter.blocks_movement:
			props.append_array(scatter.placed_positions)
	for i in 24:
		var angle := TAU * i / 24.0
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var side := dir.cross(Vector3.UP)
		var blocked := false
		for step in range(0, int(length) + 1, 2):
			var p := from + dir * step
			if not _terrain.is_on_land(p.x, p.z) or _terrain.sample_height(p.x, p.z) < 1.0:
				blocked = true
				break
			for prop in props:
				var d := Vector3(prop.x - p.x, 0.0, prop.z - p.z)
				if absf(d.dot(side)) < 2.5 and absf(d.dot(dir)) < 2.5:
					blocked = true
					break
			if blocked:
				break
		if not blocked:
			return dir
	return Vector3.ZERO


## Streaming terrain: teleporting somewhere far needs the detailed tiles
## there before physics runs. Builds them synchronously.
func _ensure_ground(at: Vector3) -> void:
	_terrain.set_focus(at)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			_terrain.ensure_built_at(at.x + dx * _terrain.chunk_size, at.z + dz * _terrain.chunk_size)


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
