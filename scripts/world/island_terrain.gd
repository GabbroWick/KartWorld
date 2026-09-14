@tool
class_name IslandTerrain
extends StaticBody3D
## Procedural low-poly island: flat-shaded height field + trimesh collision.
##
## The island is an analytic height function (radial profile, a list of
## mountains, an optional lake, noise, flat pads, a smoothed kart road), so
## everything else (prop scatter, spawn points, tests) queries
## `sample_height()` instead of raycasting, which also works in the editor.
##
## Two mesh modes:
##  * `streaming = false`: one mesh for the whole island (small worlds, the
##    level scenes, tests).
##  * `streaming = true`: the island is cut into `chunk_size` tiles built on
##    demand around `focus` (the player). Tiles within `near_distance` use
##    `cell_size`; farther ones use `far_cell_size` and no collision. Tiles
##    beyond `far_distance` are freed. Call `set_focus()` every frame or let
##    Main do it; the editor builds the tiles around the origin.
##
## Beyond `shore_radius` the ground plunges to `sea_floor_height`: the slope is
## steeper than the character's floor angle, so walking into the sea means
## sliding down until the fall limit triggers a respawn.

const GROUP := &"terrain"
## Nodes in this group provide extra flat pads: `get_flat_zones() -> Array[Vector4]`.
const FLATTEN_GROUP := &"terrain_flatten"

## Streaming: a detailed (collidable) tile appeared / went away.
signal near_chunk_built(tile: Vector2i, x0: float, z0: float, size: float)
signal near_chunk_freed(tile: Vector2i)
const ROAD_STEP := 2.0
const ROAD_GRID := 32.0   # metres per bucket of the road spatial hash

@export_group("Island")
@export_range(10.0, 2000.0, 1.0) var plateau_radius := 40.0:
	set(value):
		plateau_radius = value
		_request_rebuild()
@export_range(10.0, 2200.0, 1.0) var shore_radius := 54.0:
	set(value):
		shore_radius = value
		_request_rebuild()
@export_range(0.0, 20.0, 0.1) var beach_height := 0.5:
	set(value):
		beach_height = value
		_request_rebuild()
@export_range(0.0, 30.0, 0.1) var plateau_height := 3.5:
	set(value):
		plateau_height = value
		_request_rebuild()
@export_range(-100.0, 0.0, 1.0) var sea_floor_height := -45.0:
	set(value):
		sea_floor_height = value
		_request_rebuild()
@export_range(1.0, 60.0, 0.5) var drop_width := 6.0:
	set(value):
		drop_width = value
		_request_rebuild()
## Areas forced flat for buildings and spawn points: (x, z, radius, height).
@export var flat_zones: Array[Vector4] = []:
	set(value):
		flat_zones = value
		_request_rebuild()

@export_group("Mountains")
## Kept for the first mountain (old scenes/tests); `mountains` adds more.
@export var mountain_center := Vector2(-22.0, -20.0):
	set(value):
		mountain_center = value
		_request_rebuild()
@export_range(0.0, 400.0, 0.5) var mountain_radius := 22.0:
	set(value):
		mountain_radius = value
		_request_rebuild()
@export_range(0.0, 120.0, 0.5) var mountain_height := 13.0:
	set(value):
		mountain_height = value
		_request_rebuild()
## Extra rounded peaks: (x, z, radius, height).
@export var mountains: Array[Vector4] = []:
	set(value):
		mountains = value
		_request_rebuild()
## Lake: (x, z, radius, depth below plateau). Radius 0 = none.
@export var lake := Vector4(0, 0, 0, 0):
	set(value):
		lake = value
		_request_rebuild()

@export_group("Road")
## Closed dirt loop for the kart, as (x, z) waypoints. The terrain is
## levelled across `road_width` along a smoothed version of its own profile,
## with a soft `road_shoulder` blend, and coloured `road_color`. Empty = none.
@export var road_points: PackedVector2Array = PackedVector2Array():
	set(value):
		road_points = value
		_request_rebuild()
## More roads: each entry is a polyline (x0, z0, x1, z1, ...). Closed when
## `road_closed[i]` is true (default), else an open connector.
@export var extra_roads: Array[PackedVector2Array] = []:
	set(value):
		extra_roads = value
		_request_rebuild()
@export var extra_roads_closed: Array[bool] = []:
	set(value):
		extra_roads_closed = value
		_request_rebuild()
@export_range(2.0, 20.0, 0.5) var road_width := 7.0:
	set(value):
		road_width = value
		_request_rebuild()
@export_range(0.0, 10.0, 0.5) var road_shoulder := 3.0:
	set(value):
		road_shoulder = value
		_request_rebuild()
## Metres of road profile averaged for the smoothing (bigger = gentler).
@export_range(2.0, 200.0, 1.0) var road_smoothing := 24.0:
	set(value):
		road_smoothing = value
		_request_rebuild()
@export var road_color := Color(0.62, 0.5, 0.34)

@export_group("Detail")
@export var noise_seed := 7:
	set(value):
		noise_seed = value
		_request_rebuild()
@export_range(0.0, 30.0, 0.1) var noise_amplitude := 1.4:
	set(value):
		noise_amplitude = value
		_request_rebuild()
@export_range(0.0005, 0.2, 0.0005) var noise_frequency := 0.035:
	set(value):
		noise_frequency = value
		_request_rebuild()
## Metres per grid cell near the player. Lower = smoother and heavier.
@export_range(0.5, 8.0, 0.25) var cell_size := 1.5:
	set(value):
		cell_size = value
		_request_rebuild()

@export_group("Streaming")
@export var streaming := false:
	set(value):
		streaming = value
		_request_rebuild()
@export_range(16.0, 256.0, 8.0) var chunk_size := 64.0:
	set(value):
		chunk_size = value
		_request_rebuild()
## Tiles closer than this get full detail and collision.
@export_range(32.0, 600.0, 8.0) var near_distance := 160.0
## Tiles farther than this are not built at all.
@export_range(64.0, 2400.0, 8.0) var far_distance := 700.0
@export_range(2.0, 32.0, 1.0) var far_cell_size := 8.0
## Tiles built per frame while catching up (keeps the frame time smooth).
@export_range(1, 32, 1) var builds_per_frame := 2
## Build tile meshes on WorkerThreadPool threads (main thread only inserts).
@export var use_threads := true

@export_group("Colours")
@export var sand_color := Color(0.9, 0.82, 0.58)
@export var grass_color := Color(0.42, 0.68, 0.32)
@export var rock_color := Color(0.5, 0.48, 0.46)
@export var snow_color := Color(0.95, 0.95, 0.97)

var _noise := FastNoiseLite.new()
var _rebuild_queued := false
## flat_zones + every provider's zones, gathered at rebuild (read by workers).
var _all_flat_zones: Array[Vector4] = []
## Fetched on the main thread; worker builds only read it.
var _terrain_material: Material
## Dense samples along the road: position (x, z) and smoothed height.
var _road_samples: PackedVector3Array = PackedVector3Array()
## Spatial hash of road sample indices: Vector2i bucket -> PackedInt32Array.
var _road_buckets: Dictionary = {}
var _focus := Vector3.ZERO
## Vector2i tile -> {"node": MeshInstance3D, "near": bool}
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
## Tiles being built on worker threads: tile -> {"task": id, "near": bool, "result": Dictionary}
var _in_flight: Dictionary = {}

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


func _process(_delta: float) -> void:
	if streaming:
		_stream_step()


func _exit_tree() -> void:
	# Worker builds reference this node: never let them outlive it.
	_wait_in_flight()



func _wait_in_flight() -> void:
	for tile in _in_flight.keys():
		var task: int = _in_flight[tile]["task"]
		if not WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			WorkerThreadPool.wait_for_task_completion(task)
	_in_flight.clear()


## Where detail should be (the player). Main calls this every frame.
func set_focus(position: Vector3) -> void:
	_focus = position


## Height of the terrain surface at world (x, z).
func sample_height(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()

	# Radial island profile: plateau, then a beach easing down to the shore.
	var inland := 1.0 - smoothstep(plateau_radius, shore_radius, distance)
	var height := beach_height + (plateau_height - beach_height) * pow(inland, 0.8)

	# Rounded mountains.
	height += _mountain(x, z, mountain_center, mountain_radius, mountain_height)
	for m in mountains:
		height += _mountain(x, z, Vector2(m.x, m.y), m.z, m.w)

	# Rolling detail, fading out toward the beach.
	height += _noise.get_noise_2d(x, z) * noise_amplitude * inland

	# Lake: a soft bowl below the plateau.
	if lake.z > 0.0:
		var l := 1.0 - smoothstep(lake.z * 0.4, lake.z, Vector2(x, z).distance_to(Vector2(lake.x, lake.y)))
		height -= lake.w * l

	# Past the shore, plunge to the sea floor.
	if distance > shore_radius:
		var t := clampf((distance - shore_radius) / drop_width, 0.0, 1.0)
		height = lerpf(beach_height, sea_floor_height, t * t)

	# Flatten pads for buildings; blended edge so there is no visible seam.
	for zone in _all_flat_zones:
		var zone_distance := Vector2(x, z).distance_to(Vector2(zone.x, zone.y))
		var weight := 1.0 - smoothstep(zone.z * 0.55, zone.z, zone_distance)
		height = lerpf(height, zone.w, weight)

	# The kart road: levelled to its smoothed profile across the width, then
	# blended back into the land over the shoulder.
	if _road_samples.size() > 0:
		var road := _nearest_road_sample(x, z)
		var half := road_width * 0.5
		if road.x < half + road_shoulder:
			var weight := 1.0 - smoothstep(half, half + road_shoulder, road.x)
			height = lerpf(height, road.y, weight)
	return height


func _mountain(x: float, z: float, centre: Vector2, radius: float, peak: float) -> float:
	if radius <= 0.0:
		return 0.0
	var m := 1.0 - smoothstep(0.0, radius, Vector2(x, z).distance_to(centre))
	return peak * m * m * (3.0 - 2.0 * m)


## Approximate surface normal at world (x, z).
func sample_normal(x: float, z: float) -> Vector3:
	var step := 0.5
	var dx := sample_height(x + step, z) - sample_height(x - step, z)
	var dz := sample_height(x, z + step) - sample_height(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Slope in degrees at world (x, z).
func sample_slope_degrees(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(sample_normal(x, z).y, -1.0, 1.0)))


## True when (x, z) is on the walkable island (not on the drop into the sea).
func is_on_land(x: float, z: float) -> bool:
	return Vector2(x, z).length() <= shore_radius


## Distance (m) from (x, z) to the road centreline; INF without a road.
func road_distance(x: float, z: float) -> float:
	return _nearest_road_sample(x, z).x if _road_samples.size() > 0 else INF


## True when (x, z) lies on the road surface (inside the width, no shoulder).
func is_on_road(x: float, z: float) -> bool:
	return _road_samples.size() > 0 and _nearest_road_sample(x, z).x <= road_width * 0.5


## Length of the road loop in metres (0 without a road).
func road_length() -> float:
	var total := 0.0
	for entry in _all_roads():
		var pts: PackedVector2Array = entry[0]
		var closed: bool = entry[1]
		var n := pts.size()
		for i in (n if closed else n - 1):
			total += pts[i].distance_to(pts[(i + 1) % n])
	return total


## [[points, closed], ...] for the main loop and the extra roads.
func _all_roads() -> Array:
	var result := []
	if road_points.size() >= 2:
		result.append([road_points, true])
	for i in extra_roads.size():
		if extra_roads[i].size() >= 2:
			var closed := extra_roads_closed[i] if i < extra_roads_closed.size() else true
			result.append([extra_roads[i], closed])
	return result


## Builds the detailed tile under (x, z) right now, leaving every other
## tile alone (for spawning things far from the player). The streamer
## frees it again later when it is out of range.
func ensure_built_at(x: float, z: float) -> void:
	if not streaming or is_built_at(x, z):
		return
	var tile := _tile_of(x, z)
	if _chunks.has(tile):
		_free_chunk(_chunks[tile])
		_chunks.erase(tile)
	if _in_flight.has(tile):
		WorkerThreadPool.wait_for_task_completion(_in_flight[tile]["task"])
		_in_flight.erase(tile)
	_build_chunk(tile, true, true)


## True when the terrain has a mesh (and collision) at this point right now.
func is_built_at(x: float, z: float) -> bool:
	if not streaming:
		return true
	var tile := _tile_of(x, z)
	return _chunks.has(tile) and _chunks[tile]["near"]


## (distance to the road centreline, smoothed road height there), via the
## spatial hash: only the buckets around (x, z) are scanned.
func _nearest_road_sample(x: float, z: float) -> Vector2:
	var best_d2 := INF
	var best_h := 0.0
	var p := Vector2(x, z)
	var bx := int(floor(x / ROAD_GRID))
	var bz := int(floor(z / ROAD_GRID))
	var reach := 1
	while true:
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if reach > 1 and absi(dx) < reach and absi(dz) < reach:
					continue  # inner ring already scanned
				var key := Vector2i(bx + dx, bz + dz)
				if not _road_buckets.has(key):
					continue
				for index in _road_buckets[key]:
					var sample: Vector3 = _road_samples[index]
					var d2 := p.distance_squared_to(Vector2(sample.x, sample.z))
					if d2 < best_d2:
						best_d2 = d2
						best_h = sample.y
		# A hit in this ring beats anything in the next one only if it is
		# closer than the ring's inner edge; otherwise scan one ring more.
		var ring_inner := (reach - 0.5) * ROAD_GRID
		if best_d2 < ring_inner * ring_inner or reach >= 6:
			break
		reach += 1
	return Vector2(sqrt(best_d2) if best_d2 < INF else INF, best_h)


## Resamples the road polyline every ROAD_STEP metres and smooths the raw
## terrain height along it, so the kart gets gentle, continuous grades.
func _rebuild_road() -> void:
	_road_samples = PackedVector3Array()
	_road_buckets = {}
	for entry in _all_roads():
		var pts: PackedVector2Array = entry[0]
		var closed: bool = entry[1]
		var dense := PackedVector2Array()
		var count := pts.size()
		var segments := count if closed else count - 1
		for i in segments:
			var a := pts[i]
			var b := pts[(i + 1) % count]
			var steps := maxi(1, int(a.distance_to(b) / ROAD_STEP))
			for k in steps:
				dense.append(a.lerp(b, float(k) / steps))
		if not closed:
			dense.append(pts[count - 1])
		# Raw heights of the land under this road (other roads already in
		# _road_samples do affect it, so connectors meet the rings' height).
		var raw := PackedFloat32Array()
		for q in dense:
			raw.append(sample_height(q.x, q.y))
		var window := maxi(1, int(road_smoothing / ROAD_STEP))
		var n := dense.size()
		var smoothed := PackedFloat32Array()
		smoothed.resize(n)
		for i in n:
			var sum := 0.0
			var used := 0
			for k in range(-window, window + 1):
				var j := i + k
				if closed:
					j = (j + n) % n
				elif j < 0 or j >= n:
					continue
				sum += raw[j]
				used += 1
			smoothed[i] = sum / used
		var base := _road_samples.size()
		for i in n:
			_road_samples.append(Vector3(dense[i].x, smoothed[i], dense[i].y))
			var key := Vector2i(int(floor(dense[i].x / ROAD_GRID)), int(floor(dense[i].y / ROAD_GRID)))
			if not _road_buckets.has(key):
				_road_buckets[key] = PackedInt32Array()
			_road_buckets[key].append(base + i)


func rebuild() -> void:
	if not is_node_ready():
		return
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_material = FlatMaterial.flat_vertex_colored()
	# Workers read the road samples: finish them before replacing the data.
	_wait_in_flight()
	_all_flat_zones = flat_zones.duplicate()
	if is_inside_tree():
		for provider in get_tree().get_nodes_in_group(FLATTEN_GROUP):
			if provider.has_method(&"get_flat_zones"):
				_all_flat_zones.append_array(provider.call(&"get_flat_zones"))
	# Any parameter can move the land under the road: always resample (cheap).
	_rebuild_road()
	_clear_chunks()
	if streaming:
		mesh_instance.mesh = null
		collision.shape = null
		_pending.clear()
		# Detailed tiles around the focus right away (the player needs ground
		# under their feet); the far ring streams in over the next frames.
		_stream_step(false, true)
		return
	var extent := shore_radius + drop_width
	var array_mesh := _build_mesh(-extent, -extent, extent * 2.0, cell_size)
	mesh_instance.mesh = array_mesh
	collision.shape = array_mesh.create_trimesh_shape()


## Heights on the (cells+1)^2 grid of a tile: pure maths, safe on a worker.
func _sample_grid(x0: float, z0: float, size: float, cell: float) -> Dictionary:
	var cells := maxi(1, int(ceil(size / cell)))
	var step := size / cells
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	var road := PackedByteArray()
	road.resize(cells * cells)
	for iz in cells + 1:
		for ix in cells + 1:
			heights[iz * (cells + 1) + ix] = sample_height(x0 + ix * step, z0 + iz * step)
	for iz in cells:
		for ix in cells:
			road[iz * cells + ix] = 1 if is_on_road(x0 + (ix + 0.5) * step, z0 + (iz + 0.5) * step) else 0
	return {"x0": x0, "z0": z0, "cells": cells, "step": step, "heights": heights, "road": road}


## One flat-shaded height-field mesh from a sampled grid (main thread).
func _assemble_mesh(grid: Dictionary) -> ArrayMesh:
	var cells: int = grid["cells"]
	var step: float = grid["step"]
	var x0: float = grid["x0"]
	var z0: float = grid["z0"]
	var heights: PackedFloat32Array = grid["heights"]
	var road: PackedByteArray = grid["road"]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in cells:
		for ix in cells:
			var xa := x0 + ix * step
			var za := z0 + iz * step
			var xb := xa + step
			var zb := za + step
			var a := Vector3(xa, heights[iz * (cells + 1) + ix], za)
			var b := Vector3(xb, heights[iz * (cells + 1) + ix + 1], za)
			var c := Vector3(xb, heights[(iz + 1) * (cells + 1) + ix + 1], zb)
			var d := Vector3(xa, heights[(iz + 1) * (cells + 1) + ix], zb)
			var on_road := road[iz * cells + ix] == 1
			# Alternate the diagonal so slopes do not show a directional grain.
			# Godot front faces wind clockwise: these orders give up-facing normals.
			if (ix + iz) % 2 == 0:
				_add_triangle(surface, a, b, c, on_road)
				_add_triangle(surface, a, c, d, on_road)
			else:
				_add_triangle(surface, a, b, d, on_road)
				_add_triangle(surface, b, c, d, on_road)
	var array_mesh := surface.commit()
	array_mesh.surface_set_material(0, _terrain_material)
	return array_mesh


func _build_mesh(x0: float, z0: float, size: float, cell: float) -> ArrayMesh:
	return _assemble_mesh(_sample_grid(x0, z0, size, cell))


## Flat-shaded triangle: one normal and one colour for the whole face.
## The normal comes from Plane() so it always matches Godot's winding rule.
func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, on_road := false) -> void:
	var normal := Plane(a, b, c).normal
	var centre := (a + b + c) / 3.0
	surface.set_normal(normal)
	var color := road_color if on_road else _color_for(centre.y, normal)
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _color_for(height: float, normal: Vector3) -> Color:
	var slope := 1.0 - normal.y  # 0 flat, 1 vertical
	var color := sand_color.lerp(grass_color, smoothstep(beach_height + 0.3, beach_height + 1.6, height))
	var tallest := mountain_height
	for m in mountains:
		tallest = maxf(tallest, m.w)
	var snow_line := plateau_height + tallest * 0.72
	color = color.lerp(snow_color, smoothstep(snow_line, snow_line + 2.5, height))
	color = color.lerp(rock_color, smoothstep(0.35, 0.6, slope))
	return color


# ---------------------------------------------------------------------------
# Streaming
# ---------------------------------------------------------------------------

func _tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / chunk_size)), int(floor(z / chunk_size)))


func _tile_centre(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * chunk_size, (tile.y + 0.5) * chunk_size)


func _clear_chunks() -> void:
	_wait_in_flight()
	for tile in _chunks:
		if _chunks[tile]["near"]:
			near_chunk_freed.emit(tile)
		_free_chunk(_chunks[tile])
	_chunks.clear()


func _free_chunk(chunk: Dictionary) -> void:
	for key in ["node", "shape"]:
		var n: Node = chunk.get(key)
		if is_instance_valid(n):
			n.queue_free()


## Builds/frees tiles around the focus. `all` builds everything at once
## (rebuild, tests); otherwise a few tiles per frame.
func _stream_step(all := false, near_only_now := false) -> void:
	_collect_finished()
	var focus_xz := Vector2(_focus.x, _focus.z)
	var extent := shore_radius + drop_width
	var reach := int(ceil(far_distance / chunk_size))
	var centre_tile := _tile_of(_focus.x, _focus.z)
	# 1. Free tiles out of range or with a stale LOD.
	for tile in _chunks.keys():
		var d := _tile_centre(tile).distance_to(focus_xz)
		var want_near := d < near_distance
		if d > far_distance + chunk_size or _chunks[tile]["near"] != want_near:
			if _chunks[tile]["near"]:
				near_chunk_freed.emit(tile)
			_free_chunk(_chunks[tile])
			_chunks.erase(tile)
	# 2. Queue missing tiles, nearest first.
	if _pending.is_empty():
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var tile := centre_tile + Vector2i(dx, dz)
				if _chunks.has(tile) or _in_flight.has(tile):
					continue
				var c := _tile_centre(tile)
				if c.distance_to(focus_xz) > far_distance:
					continue
				# Skip tiles entirely in deep sea.
				if c.length() - chunk_size * 0.75 > extent:
					continue
				_pending.append(tile)
		_pending.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
			return _tile_centre(p).distance_squared_to(focus_xz) < _tile_centre(q).distance_squared_to(focus_xz))
	# 3. Build: nearest first. Near tiles (collision) are the expensive ones,
	# so only one of those per frame; far tiles are cheap and batch better.
	var budget := _pending.size() if (all or near_only_now) else builds_per_frame
	var sync := all or near_only_now
	while budget > 0 and not _pending.is_empty() and (sync or _in_flight.size() < builds_per_frame * 2):
		var tile: Vector2i = _pending[0]
		if _chunks.has(tile) or _in_flight.has(tile):
			_pending.pop_front()
			continue
		var near := _tile_centre(tile).distance_to(focus_xz) < near_distance
		if near_only_now and not near:
			break
		_pending.pop_front()
		budget -= 1
		_build_chunk(tile, near, sync)


## Kicks off a background build; `_finish_chunk` inserts it when done.
## In the editor and for synchronous builds (`_stream_step(all)`) it runs inline.
func _build_chunk(tile: Vector2i, near: bool, inline := false) -> void:
	var x0 := tile.x * chunk_size
	var z0 := tile.y * chunk_size
	var cell := cell_size if near else far_cell_size
	if inline or Engine.is_editor_hint() or not use_threads:
		_finish_chunk(tile, near, _build_mesh(x0, z0, chunk_size, cell))
		return
	# Only the height sampling runs on the worker (pure maths on immutable
	# data); mesh assembly and collision cooking touch engine servers and
	# stay on the main thread, one tile per frame.
	var entry := {"near": near, "grid": null}
	entry["task"] = WorkerThreadPool.add_task(func() -> void:
		entry["grid"] = _sample_grid(x0, z0, chunk_size, cell))
	_in_flight[tile] = entry


## Main thread: collect finished background builds.
func _collect_finished() -> void:
	for tile in _in_flight.keys():
		var entry: Dictionary = _in_flight[tile]
		if not WorkerThreadPool.is_task_completed(entry["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry["task"])
		_in_flight.erase(tile)
		if _chunks.has(tile):
			continue
		_finish_chunk(tile, entry["near"], _assemble_mesh(entry["grid"]))
		if entry["near"]:
			break   # one collision cook per frame


func _finish_chunk(tile: Vector2i, near: bool, mesh: ArrayMesh, cooked: Shape3D = null) -> void:
	var x0 := tile.x * chunk_size
	var z0 := tile.y * chunk_size
	var node := MeshInstance3D.new()
	node.name = "Chunk_%d_%d" % [tile.x, tile.y]
	node.mesh = mesh
	add_child(node)
	var shape: CollisionShape3D = null
	if near:
		# CollisionShape3D must be a direct child of the body to count.
		shape = CollisionShape3D.new()
		shape.name = "Col_%d_%d" % [tile.x, tile.y]
		shape.shape = cooked if cooked else mesh.create_trimesh_shape()
		add_child(shape)
	_chunks[tile] = {"node": node, "shape": shape, "near": near}
	if near:
		near_chunk_built.emit(tile, x0, z0, chunk_size)


func _request_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()
