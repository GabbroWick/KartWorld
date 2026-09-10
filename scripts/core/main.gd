extends Node3D
## Entry point scene. Builds the runtime graph: world + player + kart + camera.
##
## The player is spawned here rather than being hard-placed in the world scene,
## so levels stay character-agnostic and a different character (or a second
## local player) is a spawn call, not a scene edit. `world_scene` is the hub;
## the LevelManager swaps it for adventure levels and back.

@export var world_scene: PackedScene
@export var character_scene: PackedScene
@export var character_definition: CharacterDefinition
@export var vehicle_scene: PackedScene
@export var vehicle_definition: VehicleDefinition

## Camera framing on foot and at the wheel: (distance, pivot height).
const CHARACTER_FRAMING := Vector2(5.5, 1.15)
const VEHICLE_FRAMING := Vector2(8.5, 1.6)

var world: Node3D
var player: CharacterController
var vehicle: VehicleController

@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var hud: CanvasLayer = $HUD
@onready var game_hud: CanvasLayer = $GameHUD
@onready var level_manager: LevelManager = $LevelManager


func _ready() -> void:
	_build_world()
	_spawn_player()
	_spawn_vehicle()
	level_manager.setup(self, world_scene, player, vehicle, camera_rig)
	if game_hud:
		game_hud.bind_player(player)
		game_hud.bind_level_manager(level_manager)


func _build_world() -> void:
	if world_scene == null:
		push_error("Main: no world_scene assigned.")
		return
	level_manager.hub_scene = world_scene
	level_manager.world_parent = self
	world = level_manager.build_hub()


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


## One vehicle per player, parked beside the spawn until summoned. It is a
## world entity: the player only holds a reference through DriverComponent.
func _spawn_vehicle() -> void:
	if vehicle_scene == null or player == null:
		return
	vehicle = vehicle_scene.instantiate() as VehicleController
	if vehicle_definition:
		vehicle.definition = vehicle_definition
	add_child(vehicle)
	var parked := player.spawn_transform
	parked.origin += parked.basis.x * 4.0
	vehicle.place(parked)

	player.driver.set_vehicle(vehicle)
	player.driver.entered_vehicle.connect(_on_entered_vehicle)
	player.driver.exited_vehicle.connect(_on_exited_vehicle)


func _on_entered_vehicle(driven: VehicleController) -> void:
	camera_rig.set_framing(VEHICLE_FRAMING.x, VEHICLE_FRAMING.y)
	camera_rig.set_target(driven, false)
	camera_rig.auto_align = true


func _on_exited_vehicle(_left: VehicleController) -> void:
	camera_rig.set_framing(CHARACTER_FRAMING.x, CHARACTER_FRAMING.y)
	camera_rig.set_target(player, false)
	camera_rig.auto_align = false


func _find_spawn_point() -> Node3D:
	return level_manager.find_spawn_point()
