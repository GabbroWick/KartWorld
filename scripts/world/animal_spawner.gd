class_name AnimalSpawner
extends Node3D
## A flock: `count` animals of `definition` scattered within `radius`,
## each with its own home. Killed animals come back after `respawn_time`
## so there is always something to hunt. Deterministic from `spawn_seed`.

@export var animal_scene: PackedScene
@export var definition: EnemyDefinition
@export_range(1, 30, 1) var count := 5
@export_range(2.0, 60.0, 0.5) var radius := 8.0
@export_range(5.0, 600.0, 1.0) var respawn_time := 60.0
@export var spawn_seed := 9

var spawned: Array[Enemy] = []
var _pending: Array[float] = []   # seconds until each missing animal returns
var _rng := RandomNumberGenerator.new()
var _terrain: IslandTerrain


func _ready() -> void:
	_rng.seed = spawn_seed
	call_deferred(&"_spawn_all")


func _spawn_all() -> void:
	_terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if _terrain and not _terrain.is_node_ready():
		await _terrain.ready
	for i in count:
		_spawn_one()


func _spawn_one() -> void:
	if animal_scene == null or definition == null:
		return
	var a := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf()) * radius
	var spot := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if _terrain:
		spot.y = _terrain.sample_height(spot.x, spot.z) + 0.3
		_terrain.ensure_built_at(spot.x, spot.z)
	var animal := animal_scene.instantiate() as Enemy
	animal.name = "%s%d" % [definition.id, spawned.size()]
	animal.definition = definition
	add_child(animal)
	animal.global_position = spot
	animal.died.connect(_on_animal_died)
	spawned.append(animal)


func _on_animal_died(animal: Enemy) -> void:
	spawned.erase(animal)
	_pending.append(respawn_time)


func _process(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i] -= delta
		if _pending[i] <= 0.0:
			_pending.remove_at(i)
			_spawn_one()
