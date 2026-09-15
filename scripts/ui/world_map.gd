class_name WorldMap
extends Node
## Paints the island (and its neighbours) from above into a texture, once
## per world, on a worker thread: sea, beach, grass, rock, snow and roads,
## straight from IslandTerrain's analytic height (no scene rendering).
## The minimap and the full map both draw from it. Also lists the map
## markers: doors, houses, villages, the kart, the player.
##
## Coordinates: `bounds` (world x/z rect) <-> texture pixels; `to_uv()`.

signal ready_changed(ready: bool)

const METRES_PER_PIXEL := 8.0

var bounds := Rect2(-700.0, -700.0, 2500.0, 1400.0)
var texture: ImageTexture
var is_ready := false

var _terrain: IslandTerrain
var _task_id := -1
var _image: Image
var _painted_ok := false
var _cancel := false
var _started_ms := 0


func build_for(terrain: IslandTerrain) -> void:
	_finish_task()
	is_ready = false
	texture = null
	_terrain = terrain
	if terrain == null:
		ready_changed.emit(false)
		return
	# The world may be swapped while we paint: stop before the terrain dies.
	terrain.tree_exiting.connect(_finish_task, CONNECT_ONE_SHOT)
	_cancel = false
	# Frame the islands with a margin.
	var min_x := -terrain.shore_radius
	var max_x := terrain.shore_radius
	var min_z := -terrain.shore_radius
	var max_z := terrain.shore_radius
	for island in terrain.extra_islands:
		min_x = minf(min_x, island.x - island.w)
		max_x = maxf(max_x, island.x + island.w)
		min_z = minf(min_z, island.y - island.w)
		max_z = maxf(max_z, island.y + island.w)
	var margin := 80.0
	bounds = Rect2(min_x - margin, min_z - margin, max_x - min_x + margin * 2.0, max_z - min_z + margin * 2.0)
	var size := Vector2i(int(bounds.size.x / METRES_PER_PIXEL), int(bounds.size.y / METRES_PER_PIXEL))
	_image = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	_started_ms = Time.get_ticks_msec()
	_task_id = WorkerThreadPool.add_task(_paint, false, "WorldMap paint")


func _process(_delta: float) -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		_finish_task()
		if _painted_ok:
			texture = ImageTexture.create_from_image(_image)
			is_ready = true
			ready_changed.emit(true)


## Never leave a worker painting from a terrain that may be freed (world
## swap): wait for it before starting another build or leaving the tree.
func _finish_task() -> void:
	if _task_id >= 0:
		_cancel = true
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _exit_tree() -> void:
	_finish_task()


func _paint() -> void:
	_painted_ok = false
	var t := _terrain
	if not is_instance_valid(t):
		return
	var sea := Color(0.16, 0.42, 0.7)
	var shallow := Color(0.3, 0.65, 0.82)
	var w := _image.get_width()
	var h := _image.get_height()
	# Pass 1: heights (the expensive analytic sampling, once per pixel).
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for py in h:
		var z := bounds.position.y + (py + 0.5) * METRES_PER_PIXEL
		for px in w:
			var x := bounds.position.x + (px + 0.5) * METRES_PER_PIXEL
			heights[py * w + px] = t.sample_height(x, z)
		if _cancel:
			return
	# Pass 2: colours; slope from neighbouring pixels, roads only on land.
	for py in h:
		var z := bounds.position.y + (py + 0.5) * METRES_PER_PIXEL
		for px in w:
			var x := bounds.position.x + (px + 0.5) * METRES_PER_PIXEL
			var height := heights[py * w + px]
			var color: Color
			if height < t.water_level - 0.4:
				color = sea.lerp(shallow, clampf((height + 12.0) / 12.0, 0.0, 1.0))
			elif t.is_on_road(x, z):
				color = t.road_color
			else:
				var hx := heights[py * w + mini(px + 1, w - 1)] - heights[py * w + maxi(px - 1, 0)]
				var hz := heights[mini(py + 1, h - 1) * w + px] - heights[maxi(py - 1, 0) * w + px]
				var normal := Vector3(-hx, 2.0 * METRES_PER_PIXEL, -hz).normalized()
				color = t._color_for(height, normal)
				color = color.darkened(clampf((height - t.plateau_height) / 200.0, 0.0, 0.25))
			_image.set_pixel(px, py, color)
		if _cancel:
			return
	_painted_ok = true


## World (x, z) -> 0..1 across the texture.
func to_uv(world: Vector3) -> Vector2:
	return Vector2((world.x - bounds.position.x) / bounds.size.x, (world.z - bounds.position.y) / bounds.size.y)


## Points of interest: [{position, kind, label}], kind in door/home/village/kart/star.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree := get_tree()
	for portal in tree.get_nodes_in_group(&"portal"):
		var p := portal as Portal
		if p == null or p.returns_to_hub or p.completes_level:
			continue
		var label := tr(p.level.display_name) if p.level else "?"
		out.append({"position": p.global_position, "kind": "door", "label": label, "locked": p.is_locked()})
	for home in tree.get_nodes_in_group(&"map_home"):
		out.append({"position": (home as Node3D).global_position, "kind": "home", "label": tr(&"MAP_HOME")})
	for village in tree.get_nodes_in_group(&"map_village"):
		var key := StringName("PLACE_" + String(village.name).to_upper())
		var label := tr(key) if TranslationServer.get_translation_object(TranslationServer.get_locale()) and tr(key) != String(key) else String(village.name)
		out.append({"position": (village as Node3D).global_position, "kind": "village", "label": label})
	for shop in tree.get_nodes_in_group(&"map_shop"):
		out.append({"position": (shop as Node3D).global_position, "kind": "shop", "label": tr(&"SHOP_SIGN")})
	for star in tree.get_nodes_in_group(&"star"):
		var s := star as Collectible
		if s and s.persistent_id.begins_with("hub_star_"):
			out.append({"position": s.global_position, "kind": "star", "label": ""})
	var player := GameManager.get_player(0) as CharacterController
	if player and player.driver and player.driver.vehicle and not player.driver.is_driving:
		out.append({"position": player.driver.vehicle.global_position, "kind": "kart", "label": tr(&"MAP_KART")})
	return out
