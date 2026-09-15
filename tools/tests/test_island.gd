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
	await _test_home_life()
	await _test_kart_parked_still()
	await _test_kart_on_terrain()
	await _test_kart_climbs_mountain()
	await _test_road_jumps()
	await _test_npcs_alive()
	await _test_submarine()
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


func _test_road_jumps() -> void:
	# Ramps and star arcs along the road rings, placed by RoadDressing.
	var dressing := (_scene.get("world") as Node).get_node_or_null("RoadJumps") as RoadDressing
	_check(dressing != null, "hub has a RoadJumps dressing node")
	if dressing == null:
		return
	_check(dressing.ramps.size() >= 12, "road dressing placed ramps (%d)" % dressing.ramps.size())
	_check(dressing.stars.size() == dressing.ramps.size() * dressing.stars_per_ramp,
		"every ramp has its star arc (%d stars)" % dressing.stars.size())
	var on_road := 0
	var level := 0
	for ramp in dressing.ramps:
		var p := ramp.global_position
		if _terrain.is_on_road(p.x, p.z):
			on_road += 1
		var back := p + ramp.global_basis.z * 5.0
		var front := p - ramp.global_basis.z * 5.0
		if absf(_terrain.sample_height(back.x, back.z) - _terrain.sample_height(front.x, front.z)) < 2.0:
			level += 1
	_check(on_road == dressing.ramps.size(), "all ramps sit on the road (%d/%d)" % [on_road, dressing.ramps.size()])
	_check(level == dressing.ramps.size(), "all ramps on level stretches (%d/%d)" % [level, dressing.ramps.size()])
	var ids := {}
	for star in dressing.stars:
		ids[(star as Collectible).persistent_id] = true
	_check(ids.size() == dressing.stars.size(), "road stars have unique persistent ids")
	# Drive over the first ramp at speed: the kart must leave the ground.
	var ramp: Node3D = dressing.ramps[0]
	var forward := -ramp.global_basis.z
	var start := ramp.global_position - forward * 40.0
	start.y = _terrain.sample_height(start.x, start.z) + 0.3
	_ensure_ground(ramp.global_position)
	_ensure_ground(start)
	var kart := _player.driver.vehicle
	kart.place(Transform3D(Basis.looking_at(forward, Vector3.UP), start))
	_player.global_position = start + Vector3(2.0, 0.5, 0.0)
	_player.motor.reset()
	await _steps(10)
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.driver.is_driving, "in the kart before the ramp")
	var airborne := 0
	var top := -INF
	Input.action_press(InputActions.ACCELERATE)
	for i in 240:
		await _steps(1)
		if not kart.is_on_floor():
			airborne += 1
		var h := kart.global_position.y - _terrain.sample_height(kart.global_position.x, kart.global_position.z)
		top = maxf(top, h)
	Input.action_release(InputActions.ACCELERATE)
	var passed := (kart.global_position - ramp.global_position).dot(forward)
	_check(passed > 5.0, "kart drives over the ramp (%.1f m past it)" % passed)
	_check(airborne >= 8 and top > 1.4, "kart jumps off the ramp (%d frames in the air, %.1f m high)" % [airborne, top])
	await _hold(InputActions.BRAKE, 60)
	await _steps(20)
	await _hold(InputActions.INTERACT, 3)
	await _steps(20)
	_check(not _player.driver.is_driving, "out of the kart after the jump")


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
	# Spawners rotate NPC bodies at random: the visual must still face the
	# way it walks (villagers used to walk backwards).
	fox.rotation.y = 2.4
	var start := fox.global_position
	var moved := 0.0
	var facing_samples := 0
	var facing_ok := 0
	for i in 300:
		await _steps(1)
		moved = maxf(moved, fox.global_position.distance_to(start))
		var v := Vector3(fox.velocity.x, 0.0, fox.velocity.z)
		if v.length() > 1.0 and i > 30:
			facing_samples += 1
			if (-fox.visual_root.global_basis.z).dot(v.normalized()) > 0.6:
				facing_ok += 1
	_check(moved > 0.8, "fox wanders around on its own (%.1f m)" % moved)
	_check(facing_samples > 0 and facing_ok >= facing_samples * 0.8,
		"walking fox faces where it goes (%d/%d samples)" % [facing_ok, facing_samples])
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
		# The small orchard by the house is a fixed-count scatter (always
		# built: the player lives there); the big forests stream per tile.
		_check(scatter.density > 0.0 or scatter.name == "Orchard", "'%s' is a streaming scatter (density %.1f)" % [scatter.name, scatter.density])
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
	# Walk into the house front wall beside the door: it must block.
	_camera_rig.set_yaw(0.0)
	_player.global_position = Vector3(57.5, 4.5, 88.0)
	_player.motor.reset()
	await _steps(20)
	await _hold(&"move_forward", 120)
	# Body is 6.5 deep centred at z=80 -> front face at z=83.25.
	_check(_player.global_position.z > 83.4,
		"house wall blocks the player (z %.2f)" % _player.global_position.z)
	# Through the doorway the player gets inside.
	_player.global_position = Vector3(60.0, 4.5, 88.0)
	_player.motor.reset()
	await _steps(10)
	await _hold(&"move_forward", 90)
	_check(_player.global_position.z < 82.0 and _player.global_position.z > 77.0 and _player.is_on_floor(),
		"the doorway lets the player into the house (z %.2f)" % _player.global_position.z)
	await _steps(10)


func _test_home_life() -> void:
	var world: Node = _scene.get("world")
	ProgressionManager.inventory.clear()
	# Fruit: an orchard tree gives fruit, then regrows.
	var orchard := world.get_node_or_null("Orchard") as PropScatter
	_check(orchard != null, "hub has an orchard scatter")
	var trees := orchard.find_children("*", "FruitTree", false, false) if orchard else []
	_check(trees.size() >= 5, "orchard has fruit trees (%d)" % trees.size())
	if trees.is_empty():
		return
	var tree := trees[0] as FruitTree
	_player.global_position = tree.global_position + Vector3(1.5, 0.3, 0.0)
	_player.motor.reset()
	await _steps(10)
	_check(_player.interaction.get_prompt() == tr(&"PROMPT_PICK_FRUIT"), "prompt offers to pick fruit (%s)" % _player.interaction.get_prompt())
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(ProgressionManager.count_item(&"fruit") == tree.fruit_count and not tree.has_fruit,
		"picking adds fruit to the inventory (%d)" % ProgressionManager.count_item(&"fruit"))
	var hud: CanvasLayer = _scene.get_node("GameHUD")
	_check(hud.inventory_label.text.contains(tr(&"ITEM_FRUIT")), "HUD lists the fruit (%s)" % hud.inventory_label.text)
	tree._regrow_left = 0.01
	await _steps(3)
	_check(tree.has_fruit, "fruit grows back")
	# Meat: chickens run from the player; hitting one drops meat.
	var flock := world.get_node_or_null("Chickens") as AnimalSpawner
	_check(flock != null and flock.spawned.size() == 5, "five chickens near the house (%d)" % (flock.spawned.size() if flock else 0))
	if flock and flock.spawned.size() > 0:
		var chicken := flock.spawned[0] as Animal
		_player.global_position = chicken.global_position + Vector3(2.0, 0.3, 0.0)
		_player.motor.reset()
		var start := chicken.global_position
		await _steps(45)
		_check(chicken.global_position.distance_to(start) > 1.0 and chicken.global_position.distance_to(_player.global_position) > 2.0,
			"a chicken runs away from the player (%.1f m)" % chicken.global_position.distance_to(start))
		var hearts := _player.health.current_health
		chicken.take_damage(5.0, _player)
		await _steps(3)
		_check(ProgressionManager.count_item(&"meat") == 1, "a hit chicken drops meat (%d)" % ProgressionManager.count_item(&"meat"))
		_check(_player.health.current_health == hearts, "chickens never hurt the player")
		await _steps(40)
		_check(flock.spawned.size() == 4, "the flock is one short until it respawns (%d)" % flock.spawned.size())
	# Kitchen: fruit + meat = stew, heals and boosts.
	var kitchen := world.find_children("*", "Kitchen", true, false)[0] as Kitchen
	_player.health.take_damage(3.0)
	_player.invulnerable_left = 0.0
	_player.global_position = kitchen.global_position + Vector3(0.0, 0.3, 1.4)
	_player.motor.reset()
	await _steps(10)
	_check(_player.interaction.get_prompt() == tr(&"PROMPT_COOK_STEW"), "kitchen offers a stew (%s)" % _player.interaction.get_prompt())
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.health.current_health == _player.health.max_health, "the stew fills the hearts")
	_check(_player.motor.is_well_fed(), "the stew makes the character quick")
	_check(ProgressionManager.count_item(&"meat") == 0 and ProgressionManager.count_item(&"fruit") == tree.fruit_count - 1, "cooking uses one fruit and one meat")
	# Bed: sleep heals and brings the morning.
	var bed := world.find_children("*", "Bed", true, false)[0] as Bed
	var cycle := world.get_node("DayCycle") as DayCycle
	cycle.time_of_day = 0.9
	cycle._apply()
	_check(cycle.is_night(), "day cycle knows the night")
	_player.health.take_damage(2.0)
	_player.invulnerable_left = 0.0
	_player.global_position = bed.global_position + Vector3(1.4, 0.3, 0.0)
	_player.motor.reset()
	await _steps(10)
	_check(_player.interaction.get_prompt() == tr(&"PROMPT_SLEEP"), "bed offers to sleep (%s)" % _player.interaction.get_prompt())
	var slept := [false]
	bed.slept.connect(func() -> void: slept[0] = true)
	await _hold(InputActions.INTERACT, 3)
	await _steps(60)
	_check(slept[0], "sleeping in the bed works")
	_check(_player.health.current_health == _player.health.max_health, "sleeping refills the hearts")
	_check(not cycle.is_night() and cycle.time_of_day < 0.4, "sleeping brings the morning (%.2f)" % cycle.time_of_day)
	ProgressionManager.inventory.clear()


func _test_submarine() -> void:
	# A second island far out at sea, reached by kart: in deep water the
	# kart becomes a submarine and floats; on the beach it is a kart again.
	_check(_terrain.extra_islands.size() >= 1, "terrain has an extra island")
	var far := Vector2(1500.0, -350.0)
	_check(_terrain.sample_height(far.x, far.y) > 3.0 and _terrain.is_on_land(far.x, far.y), "second island has land at Porto (h %.1f)" % _terrain.sample_height(far.x, far.y))
	_check(_terrain.is_water(1000.0, -200.0) and _terrain.sample_height(1000.0, -200.0) < -20.0, "the sea between the islands is deep")
	var porto := _scene.get("world").get_node_or_null("Porto") as Village
	_check(porto != null and porto.plot_positions.size() == 5, "Porto village has five plots")
	# Drive off the main beach straight out to sea (+Z at x=0).
	var kart := _player.driver.vehicle
	var start := Vector3(0.0, _terrain.sample_height(0.0, 585.0) + 0.3, 585.0)
	_ensure_ground(start)
	_ensure_ground(Vector3(0.0, 0.0, 650.0))
	kart.place(Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), start))
	_player.global_position = start + Vector3(2.0, 0.5, 0.0)
	_player.motor.reset()
	await _steps(10)
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.driver.is_driving, "in the kart on the beach")
	_check(not kart.is_submarine, "on the beach it is a kart")
	Input.action_press(InputActions.ACCELERATE)
	var became := -1
	for i in 300:
		await _steps(1)
		if kart.is_submarine and became < 0:
			became = i
	Input.action_release(InputActions.ACCELERATE)
	_check(became >= 0, "driving into the sea turns the kart into a submarine (frame %d)" % became)
	_check(kart.global_position.z > 640.0, "the submarine keeps going out to sea (z %.0f)" % kart.global_position.z)
	var surface := _terrain.water_level
	_check(absf(kart.global_position.y - (surface - 0.45)) < 0.4, "the submarine floats at the surface (y %.2f)" % kart.global_position.y)
	var visual := kart.visual_root.get_children().filter(func(c: Node) -> bool: return c is AiVehicleVisual)
	if visual.size() == 1:
		_check((visual[0] as AiVehicleVisual).is_submarine() and (visual[0] as AiVehicleVisual)._canopy.visible, "canopy closed and propellers out")
	await _hold(InputActions.INTERACT, 3)
	await _steps(3)
	_check(_player.driver.is_driving, "you cannot get out at sea")
	# Turn round and drive back onto the beach.
	var back := kart.global_position
	kart.place(Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(back.x, back.y, back.z)))
	Input.action_press(InputActions.ACCELERATE)
	var landed := -1
	for i in 420:
		await _steps(1)
		if not kart.is_submarine and landed < 0:
			landed = i
	Input.action_release(InputActions.ACCELERATE)
	_check(landed >= 0 and kart.is_on_floor(), "back on the beach it is a kart again (frame %d, on floor %s)" % [landed, kart.is_on_floor()])
	await _hold(InputActions.BRAKE, 30)
	await _hold(InputActions.INTERACT, 3)
	await _steps(20)
	_check(not _player.driver.is_driving, "out of the kart on land")
	# Back home for the next test.
	_player.global_position = _player.spawn_transform.origin
	_player.motor.reset()
	_ensure_ground(_player.global_position)
	await _steps(10)


func _test_sea() -> void:
	# Beyond the shore the ground drops away; the player must respawn.
	var spawn := _player.spawn_transform.origin
	_ensure_ground(Vector3(0.0, 2.0, _terrain.shore_radius + 4.0))
	_player.global_position = Vector3(0.0, 2.0, _terrain.shore_radius + 4.0)
	_player.motor.reset()
	var respawned := false
	# Walk out to sea (+Z): the shore slope is gentle at first.
	_camera_rig.set_yaw(PI)
	Input.action_press(InputActions.MOVE_FORWARD)
	for i in 600:
		await _steps(1)
		if _player.global_position.distance_to(spawn) < 2.0:
			respawned = true
			break
	Input.action_release(InputActions.MOVE_FORWARD)
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
