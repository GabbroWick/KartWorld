class_name RoadDressing
extends Node3D
## Track dressing along the island's roads: every `spacing` metres of a road
## a jump hump (`ramp_scene`) faces the driving direction, and an arc of
## stars hangs in the air after it so the jump has a reward. Placement is
## deterministic and data-driven (which roads, spacing, seed): no hand
## placed nodes. Ramps are skipped on steep or twisty stretches and near
## the terrain's flat zones (villages, spawn), where they would look wrong.
##
## Stars are persistent hub stars (`persistent_id` = prefix + index).

@export var ramp_scene: PackedScene
@export var star_scene: PackedScene
## Roads to dress: -1 = the main loop, 0.. = `extra_roads` index.
@export var roads: Array[int] = [-1]
@export_range(50.0, 3000.0, 10.0) var spacing := 400.0
## Start offset along each road, metres.
@export_range(0.0, 3000.0, 10.0) var offset := 120.0
@export_range(0, 6, 1) var stars_per_ramp := 3
@export var persistent_prefix := "road_star_"
## Skip stretches steeper than this (degrees, over 30 m).
@export_range(1.0, 30.0, 0.5) var max_grade_degrees := 7.0
## Skip stretches bending more than this (degrees, over 30 m).
@export_range(5.0, 90.0, 1.0) var max_bend_degrees := 18.0
@export_range(0.0, 100.0, 1.0) var flat_zone_clearance := 30.0
@export var dressing_seed := 4

var ramps: Array[Node3D] = []
var stars: Array[Node3D] = []


func _ready() -> void:
	call_deferred(&"build")


func build() -> void:
	for child in get_children():
		child.queue_free()
	ramps.clear()
	stars.clear()
	var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if terrain == null or ramp_scene == null:
		return
	if not terrain.is_node_ready():
		await terrain.ready
	var rng := RandomNumberGenerator.new()
	rng.seed = dressing_seed
	var star_index := 0
	for road in roads:
		var length := terrain.road_length_of(road)
		if length <= 0.0:
			continue
		var d := offset
		var guard := 0
		while d < length - 40.0 and guard < 400:
			guard += 1
			var at := _find_spot(terrain, road, d, length)
			var flip := rng.randf() < 0.5   # consume the RNG even when skipping
			if at < 0.0:
				d += spacing
				continue
			var pose := terrain.road_pose(road, at)
			# Alternate direction so both ways round the loop get jumps.
			if flip:
				pose.basis = pose.basis.rotated(Vector3.UP, PI)
			var ramp := ramp_scene.instantiate() as Node3D
			ramp.name = "Ramp%d" % ramps.size()
			add_child(ramp)
			Lod.register_deferred(ramp)
			ramp.global_transform = pose
			ramps.append(ramp)
			if star_scene and stars_per_ramp > 0:
				var forward := -pose.basis.z
				for k in stars_per_ramp:
					var t := float(k + 1) / (stars_per_ramp + 1)
					var ahead := 5.0 + 12.0 * t
					var lift := 2.0 + 1.4 * sin(t * PI)
					var p := pose.origin + forward * ahead
					p.y = terrain.sample_height(p.x, p.z) + lift
					var star := star_scene.instantiate() as Node3D
					star.name = "RoadStar%d" % star_index
					star.set(&"persistent_id", StringName(persistent_prefix + str(star_index)))
					add_child(star)
					star.global_position = p
					stars.append(star)
					star_index += 1
			d += spacing


## First distance from `from` (within half a spacing) whose stretch is
## flat, straight and away from flat zones; -1 if none.
func _find_spot(terrain: IslandTerrain, road: int, from: float, length: float) -> float:
	var step := 10.0
	var d := from
	while d < from + spacing * 0.5 and d < length - 40.0:
		if _stretch_ok(terrain, road, d):
			return d
		d += step
	return -1.0


func _stretch_ok(terrain: IslandTerrain, road: int, d: float) -> bool:
	var a := terrain.road_pose(road, d - 15.0)
	var b := terrain.road_pose(road, d + 15.0)
	var rise := absf(b.origin.y - a.origin.y)
	if rad_to_deg(atan2(rise, 30.0)) > max_grade_degrees:
		return false
	var fa := -a.basis.z
	var fb := -b.basis.z
	if rad_to_deg(fa.angle_to(fb)) > max_bend_degrees:
		return false
	var here := terrain.road_pose(road, d).origin
	for zone in terrain._all_flat_zones:
		if Vector2(here.x, here.z).distance_to(Vector2(zone.x, zone.y)) < zone.z + flat_zone_clearance:
			return false
	return true
