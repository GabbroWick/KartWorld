class_name LevelManager
extends Node
## Swaps the world between the hub and adventure levels.
##
## Owned by Main. It knows the hub scene, the current level and how to move
## the player (and their kart) to a scene's spawn point. Levels are loaded from
## LevelDefinition data, never by name, so adding a level is a .tres + a scene.
## Progress recording (completed levels, stars) is emitted as signals for the
## progression system to pick up in a later phase.

signal level_loading(definition: LevelDefinition)
signal level_loaded(definition: LevelDefinition)
signal hub_loaded
signal level_completed(definition: LevelDefinition, stars: int)

const GROUP := &"level_manager"

## The hub scene (island). Set by Main.
var hub_scene: PackedScene
## Definition of the level currently loaded; null while in the hub.
var current_level: LevelDefinition
## Where the world node gets added, and what it replaces. Set by Main.
var world_parent: Node
var world: Node3D
## Seconds after a load during which portals stay inert, so arriving next to
## one never bounces the player straight back.
var portal_grace := 1.0

var _player: CharacterController
var _vehicle: VehicleController
var _camera_rig: ThirdPersonCamera
var _loaded_at := -1000.0


func _ready() -> void:
	add_to_group(GROUP)


func setup(parent: Node, hub: PackedScene, player: CharacterController,
		vehicle: VehicleController, camera_rig: ThirdPersonCamera) -> void:
	world_parent = parent
	hub_scene = hub
	_player = player
	_vehicle = vehicle
	_camera_rig = camera_rig


func is_in_hub() -> bool:
	return current_level == null


func portals_armed() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _loaded_at >= portal_grace


## Builds the hub for the first time (no player relocation yet).
func build_hub() -> Node3D:
	_swap_world(hub_scene)
	return world


func load_level(definition: LevelDefinition) -> void:
	if definition == null or definition.scene == null:
		push_error("LevelManager: level '%s' has no scene." % (definition.id if definition else "null"))
		return
	level_loading.emit(definition)
	current_level = definition
	_swap_world(definition.scene)
	_relocate_party()
	level_loaded.emit(definition)


func return_to_hub() -> void:
	current_level = null
	_swap_world(hub_scene)
	_relocate_party()
	hub_loaded.emit()


## Called by a level when its objectives are done. Records the result and
## brings the party home.
func complete_level(stars: int) -> void:
	if current_level == null:
		return
	level_completed.emit(current_level, stars)
	return_to_hub()


func find_spawn_point() -> Node3D:
	if world == null:
		return null
	for node in world.find_children("*", "Marker3D", true, false):
		if node.is_in_group(&"player_spawn"):
			return node as Node3D
	return null


func _swap_world(scene: PackedScene) -> void:
	if is_instance_valid(world):
		world_parent.remove_child(world)
		world.queue_free()
	world = scene.instantiate() as Node3D
	world_parent.add_child(world)
	# Keep the world first in the tree so the camera still updates last.
	world_parent.move_child(world, 0)
	_loaded_at = Time.get_ticks_msec() / 1000.0


func _relocate_party() -> void:
	var spawn := find_spawn_point()
	var at := spawn.global_transform if spawn else Transform3D.IDENTITY
	if _player.driver.is_driving:
		_player.driver.exit_vehicle()
	_player.set_spawn_transform(at, true)
	_player.motor.reset()
	# A fresh start every time the world changes: full hearts, no i-frames.
	_player.health.restore_full()
	_player.invulnerable_left = 0.0
	_player.visual_root.visible = true
	_player.visual_root.global_rotation.y = at.basis.get_euler().y
	if _vehicle:
		var parked := at
		parked.origin += at.basis.x * 4.0
		_vehicle.place(parked)
	if _camera_rig:
		_camera_rig.set_yaw(at.basis.get_euler().y)
		_camera_rig.set_target(_player, true)
