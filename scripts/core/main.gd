extends Node3D
## Entry point scene. Builds the runtime graph: world + player + camera.
##
## The player is spawned here rather than being hard-placed in the world scene,
## so levels stay character-agnostic and a different character (or a second
## local player) is a spawn call, not a scene edit.

@export var world_scene: PackedScene
@export var character_scene: PackedScene
@export var character_definition: CharacterDefinition

var world: Node3D
var player: CharacterController

@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	_build_world()
	_spawn_player()


func _build_world() -> void:
	if world_scene == null:
		push_error("Main: no world_scene assigned.")
		return
	world = world_scene.instantiate() as Node3D
	add_child(world)
	# Keep the world first in the tree so the camera still updates last.
	move_child(world, 0)


func _spawn_player() -> void:
	if character_scene == null:
		push_error("Main: no character_scene assigned.")
		return
	player = character_scene.instantiate() as CharacterController
	if character_definition:
		player.definition = character_definition
	player.view_node = camera_rig
	add_child(player)

	var spawn := _find_spawn_point()
	if spawn:
		player.set_spawn_transform(spawn.global_transform)

	camera_rig.set_target(player)
	if hud.has_method(&"bind_player"):
		hud.call(&"bind_player", player)


func _find_spawn_point() -> Node3D:
	if world == null:
		return null
	var candidates := world.find_children("*", "Marker3D", true, false)
	for node in candidates:
		if node.is_in_group(&"player_spawn"):
			return node as Node3D
	return candidates[0] as Node3D if not candidates.is_empty() else null
