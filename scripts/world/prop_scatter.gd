@tool
class_name PropScatter
extends Node3D
## Deterministically scatters a prop scene over an IslandTerrain.
##
## Forests, rocks and bushes are placement rules, not hand-placed nodes: seed +
## region + filters. Regenerating never changes the layout unless the seed or
## the terrain does. Generated children are not saved into the scene file.

@export var prop_scene: PackedScene:
	set(value):
		prop_scene = value
		_request_rebuild()
## Optional model variants. When set, `prop_scene` must be a ModelProp template
## and each placed prop gets one of these (seeded), so one rule scatters a
## mixed forest.
@export var models: Array[PackedScene] = []:
	set(value):
		models = value
		_request_rebuild()
## False for decoration the player walks through (flowers, grass): tests and
## pathing may ignore these props.
@export var blocks_movement := true
## Terrain to scatter on. Empty = first node in the "terrain" group.
@export var terrain_path: NodePath:
	set(value):
		terrain_path = value
		_request_rebuild()
@export var scatter_seed := 1:
	set(value):
		scatter_seed = value
		_request_rebuild()
@export_range(0, 500, 1) var count := 30:
	set(value):
		count = value
		_request_rebuild()

@export_group("Region")
## Centre of the scatter disc, in world XZ.
@export var center := Vector2.ZERO:
	set(value):
		center = value
		_request_rebuild()
@export_range(0.0, 200.0, 0.5) var radius := 20.0:
	set(value):
		radius = value
		_request_rebuild()
## Zones to keep clear: (x, z, radius) each.
@export var exclusion_zones: Array[Vector3] = []:
	set(value):
		exclusion_zones = value
		_request_rebuild()

@export_group("Filters")
@export var min_height := -1000.0:
	set(value):
		min_height = value
		_request_rebuild()
@export var max_height := 1000.0:
	set(value):
		max_height = value
		_request_rebuild()
@export_range(0.0, 90.0, 1.0) var max_slope_degrees := 28.0:
	set(value):
		max_slope_degrees = value
		_request_rebuild()
@export_range(0.0, 50.0, 0.5) var min_spacing := 3.0:
	set(value):
		min_spacing = value
		_request_rebuild()

@export_group("Variation")
@export_range(0.1, 5.0, 0.05) var scale_min := 0.85:
	set(value):
		scale_min = value
		_request_rebuild()
@export_range(0.1, 5.0, 0.05) var scale_max := 1.3:
	set(value):
		scale_max = value
		_request_rebuild()
## Sink props slightly into the ground so they never float on slopes.
@export_range(0.0, 2.0, 0.05) var sink := 0.15:
	set(value):
		sink = value
		_request_rebuild()

var placed_positions: PackedVector3Array = []
var terrain: IslandTerrain
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if not is_node_ready():
		return
	_clear()
	placed_positions = []
	terrain = _resolve_terrain()
	if prop_scene == null or terrain == null:
		if not Engine.is_editor_hint():
			push_warning("PropScatter '%s': prop_scene or terrain missing, nothing placed." % name)
		return
	if not terrain.is_node_ready():
		await terrain.ready

	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	# Separate stream for picking variants, so adding or reordering models
	# never moves the props themselves.
	var variant_rng := RandomNumberGenerator.new()
	variant_rng.seed = scatter_seed * 7919 + 1
	var attempts := count * 12
	while placed_positions.size() < count and attempts > 0:
		attempts -= 1
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * radius
		var x := center.x + cos(angle) * distance
		var z := center.y + sin(angle) * distance
		if not _accepts(x, z):
			continue
		var y := terrain.sample_height(x, z) - sink
		var position_3d := Vector3(x, y, z)
		placed_positions.append(position_3d)

		var prop := prop_scene.instantiate() as Node3D
		prop.position = position_3d
		prop.rotation.y = rng.randf_range(0.0, TAU)
		prop.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		prop.set_meta(&"scattered", true)
		if not models.is_empty() and prop is ModelProp:
			(prop as ModelProp).model = models[variant_rng.randi_range(0, models.size() - 1)]
		add_child(prop)


func _resolve_terrain() -> IslandTerrain:
	if not terrain_path.is_empty():
		return get_node_or_null(terrain_path) as IslandTerrain
	return get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain


func _accepts(x: float, z: float) -> bool:
	if not terrain.is_on_land(x, z):
		return false
	var height := terrain.sample_height(x, z)
	if height < min_height or height > max_height:
		return false
	if terrain.sample_slope_degrees(x, z) > max_slope_degrees:
		return false
	for zone in exclusion_zones:
		if Vector2(x, z).distance_to(Vector2(zone.x, zone.y)) < zone.z:
			return false
	var spacing_squared := min_spacing * min_spacing
	for other in placed_positions:
		if Vector2(x, z).distance_squared_to(Vector2(other.x, other.z)) < spacing_squared:
			return false
	return true


func _clear() -> void:
	for child in get_children():
		if child.has_meta(&"scattered"):
			remove_child(child)
			child.queue_free()


func _request_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()
