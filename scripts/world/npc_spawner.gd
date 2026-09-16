class_name NpcSpawner
extends Node3D
## Populates the island: walking NPCs around this node (or around a
## Village's plots) and kart-driving NPCs spread along the road network.
##
## Walkers = character scene + a definition picked from `definitions` +
## an NpcBehaviour with lines from `dialogue_pool`. Karts = vehicle scene +
## NpcDriver + a seated NPC visual, one every `kart_spacing` metres of the
## chosen roads. Deterministic from `spawn_seed`. Runtime only (no @tool):
## NPCs are gameplay, not scenery.

@export var character_scene: PackedScene
@export var definitions: Array[CharacterDefinition] = []
## Translation keys, one line each; every walker gets 2-3 of them.
@export var dialogue_pool: PackedStringArray = PackedStringArray()
@export_range(0, 40, 1) var walkers := 6
@export_range(2.0, 80.0, 0.5) var walk_radius := 14.0
## Take walker spots from this Village's plots (in front of the houses).
@export var village_path: NodePath

@export_group("Karts")
@export var vehicle_scene: PackedScene
@export var vehicle_definition: VehicleDefinition
## Roads to populate: -1 = main loop, 0.. = extra road index.
@export var kart_roads: Array[int] = [-1]
@export_range(0, 40, 1) var karts_per_road := 3
@export_range(0.3, 1.0, 0.05) var kart_speed_factor := 0.65
@export var spawn_seed := 5

var spawned_walkers: Array[CharacterController] = []
var spawned_karts: Array[VehicleController] = []


func _ready() -> void:
	call_deferred(&"_spawn")


func _spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if terrain and not terrain.is_node_ready():
		await terrain.ready
	_spawn_walkers(rng, terrain)
	_spawn_karts(rng, terrain)


func _spawn_walkers(rng: RandomNumberGenerator, terrain: IslandTerrain) -> void:
	if character_scene == null or definitions.is_empty():
		return
	var village := get_node_or_null(village_path) as Village
	var spots: Array[Vector3] = []
	if village and village.plot_positions.size() > 0:
		# In front of each house, a bit toward the village centre.
		for p in village.plot_positions:
			var toward := (village.global_position - p)
			toward.y = 0.0
			spots.append(p + toward.normalized() * 5.0)
	while spots.size() < walkers:
		var a := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf()) * walk_radius
		spots.append(global_position + Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in walkers:
		var spot := spots[i % spots.size()]
		if terrain:
			spot.y = terrain.sample_height(spot.x, spot.z) + 0.3
			_ensure_tile(terrain, spot)
		var npc := character_scene.instantiate() as CharacterController
		npc.name = "Npc%d" % i
		npc.definition = definitions[i % definitions.size()]
		npc.is_player_controlled = false
		var behaviour := NpcBehaviour.new()
		behaviour.name = "Behaviour"
		behaviour.wander_radius = rng.randf_range(3.0, 7.0)
		var lines := PackedStringArray()
		if dialogue_pool.size() > 0:
			var start := rng.randi_range(0, dialogue_pool.size() - 1)
			for k in 3:
				lines.append(dialogue_pool[(start + k) % dialogue_pool.size()])
		behaviour.dialogue_lines = lines
		npc.add_child(behaviour)
		add_child(npc)
		Lod.register_deferred(npc)
		npc.global_position = spot
		npc.rotation.y = rng.randf_range(0.0, TAU)
		spawned_walkers.append(npc)


func _spawn_karts(rng: RandomNumberGenerator, terrain: IslandTerrain) -> void:
	if vehicle_scene == null or terrain == null or karts_per_road <= 0:
		return
	var index := 0
	for road in kart_roads:
		var length := _road_length(terrain, road)
		if length <= 0.0:
			continue
		for k in karts_per_road:
			var kart := vehicle_scene.instantiate() as VehicleController
			kart.name = "NpcKart%d" % index
			if vehicle_definition:
				kart.definition = vehicle_definition
			var driver := NpcDriver.new()
			driver.name = "NpcDriver"
			driver.road_index = road
			driver.distance = length * (k + rng.randf_range(0.1, 0.9)) / karts_per_road
			driver.reverse = rng.randf() < 0.5
			driver.speed_factor = kart_speed_factor * rng.randf_range(0.85, 1.1)
			driver.lane_offset = 2.0   # right-hand traffic: opposite karts never meet head-on
			kart.add_child(driver)
			add_child(kart)
			# A passenger: the NPC's visual on the seat (no character body).
			if not definitions.is_empty():
				var definition := CharacterRoster.for_npc(definitions[index % definitions.size()])
				if definition.visual_scene:
					var visual := definition.visual_scene.instantiate() as Node3D
					visual.scale = Vector3.ONE * definition.visual_scale
					kart.seat_visual(visual)
					if visual.has_method(&"set_seated"):
						visual.call(&"set_seated", true)
			spawned_karts.append(kart)
			Lod.register_deferred(kart)
			index += 1


## Streaming terrain: a walker placed on an unbuilt tile would fall through.
## Villages far from the player get their tiles built once, here; the
## streamer frees them again when nobody is around (NPCs freeze meanwhile:
## CharacterBody3D with no floor just falls, so the behaviour also parks
## itself, see NpcBehaviour).
func _ensure_tile(terrain: IslandTerrain, at: Vector3) -> void:
	terrain.ensure_built_at(at.x, at.z)


func _road_length(terrain: IslandTerrain, road: int) -> float:
	var pts: PackedVector2Array
	var closed := true
	if road < 0:
		pts = terrain.road_points
	elif road < terrain.extra_roads.size():
		pts = terrain.extra_roads[road]
		closed = terrain.extra_roads_closed[road] if road < terrain.extra_roads_closed.size() else true
	else:
		return 0.0
	var n := pts.size()
	if n < 2:
		return 0.0
	var total := 0.0
	for i in (n if closed else n - 1):
		total += pts[i].distance_to(pts[(i + 1) % n])
	return total
