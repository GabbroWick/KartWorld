@tool
class_name Village
extends Node3D
## A hamlet: buildings placed on a ring around `global_position`, each on
## its own flattened pad (the terrain's `flat_zones` are extended at
## runtime), facing the centre, with a random model per plot.
##
## Data, not hand placement: `plots` = how many buildings, `radius` = ring
## radius, `models` = Kenney building scenes. Deterministic from `seed`.
## Buildings are ModelProp instances with BOX collision (no palette: the
## Modular Buildings kit is textured). Emits `built` when done, so NPC
## spawners can use the plots.

signal built

@export var models: Array[PackedScene] = []:
	set(value):
		models = value
		_request_rebuild()
@export_range(1, 24, 1) var plots := 6:
	set(value):
		plots = value
		_request_rebuild()
@export_range(6.0, 120.0, 0.5) var radius := 16.0:
	set(value):
		radius = value
		_request_rebuild()
@export var village_seed := 3:
	set(value):
		village_seed = value
		_request_rebuild()
@export_range(1.0, 6.0, 0.1) var model_scale := 3.0:
	set(value):
		model_scale = value
		_request_rebuild()
## Pad radius around each building that the terrain flattens.
@export_range(2.0, 20.0, 0.5) var pad_radius := 6.0
## Leave the arc facing this direction open (a plaza / the road side).
@export var gap_direction := Vector2(0.0, 1.0)
@export_range(0.0, 180.0, 5.0) var gap_degrees := 70.0
## Terrain to flatten and to stand on. Empty = first in the "terrain" group.
@export var terrain_path: NodePath

var plot_positions: PackedVector3Array = PackedVector3Array()
var _rebuild_queued := false


func _ready() -> void:
	add_to_group(IslandTerrain.FLATTEN_GROUP)
	rebuild()


func _exit_tree() -> void:
	remove_from_group(IslandTerrain.FLATTEN_GROUP)


## Flat pads for the terrain (one per plot + the plaza). Deterministic, so
## the terrain can ask for them before or after the buildings exist.
func get_flat_zones() -> Array[Vector4]:
	var terrain := _resolve_terrain()
	if terrain == null:
		return []
	var zones: Array[Vector4] = []
	var height := _base_height(terrain)
	for p in _plot_layout():
		zones.append(Vector4(p.x, p.y, pad_radius, height))
	zones.append(Vector4(global_position.x, global_position.z, radius * 0.6, height))
	return zones


## Terrain height at the centre, ignoring our own pads (they are not applied
## yet the first time; afterwards they are flat at this same value).
func _base_height(terrain: IslandTerrain) -> float:
	return terrain.sample_height(global_position.x, global_position.z)


func _plot_layout() -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = village_seed
	var centre := global_position
	var gap_angle := atan2(gap_direction.y, gap_direction.x)
	var usable := TAU - deg_to_rad(gap_degrees)
	var start := gap_angle + deg_to_rad(gap_degrees) * 0.5
	var out := PackedVector2Array()
	for i in plots:
		var angle := start + usable * (i + 0.5) / plots
		var r := radius * rng.randf_range(0.9, 1.1)
		out.append(Vector2(centre.x + cos(angle) * r, centre.z + sin(angle) * r))
	return out


func rebuild() -> void:
	if not is_node_ready():
		return
	for child in get_children():
		if child.has_meta(&"village_building"):
			remove_child(child)
			child.queue_free()
	plot_positions = PackedVector3Array()
	var terrain := _resolve_terrain()
	if terrain == null or models.is_empty():
		return
	if not terrain.is_node_ready():
		await terrain.ready
	# Make sure the terrain knows our pads (first build happens before we
	# joined the group when the village is later in the tree).
	var wanted := get_flat_zones()
	var missing := false
	for zone in wanted:
		if not terrain._all_flat_zones.has(zone):
			missing = true
			break
	if missing:
		terrain.rebuild()
	var height := _base_height(terrain)
	var rng := RandomNumberGenerator.new()
	rng.seed = village_seed * 31 + 7
	var centre := global_position
	for q in _plot_layout():
		plot_positions.append(Vector3(q.x, height, q.y))
	for i in plots:
		var p := plot_positions[i]
		var prop := ModelProp.new()
		prop.model = models[rng.randi_range(0, models.size() - 1)]
		prop.model_scale = model_scale
		prop.collision_mode = ModelProp.CollisionMode.BOX
		prop.collision_shrink = 0.95
		prop.apply_palette = false
		prop.set_meta(&"village_building", true)
		prop.set_meta(&"scattered", true)
		add_child(prop)
		prop.global_position = p
		var to_centre := Vector2(centre.x - p.x, centre.z - p.z)
		# Kenney buildings face +Z; ModelProp keeps the model as is.
		prop.rotation.y = atan2(to_centre.x, to_centre.y)
	built.emit()


func _resolve_terrain() -> IslandTerrain:
	if not terrain_path.is_empty():
		return get_node_or_null(terrain_path) as IslandTerrain
	return get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain


func _request_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()
