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
	add_to_group(&"main")
	_build_world()
	_spawn_player()
	_spawn_vehicle()
	level_manager.setup(self, world_scene, player, vehicle, camera_rig)
	_wire_progression()
	if game_hud:
		game_hud.bind_player(player)
		game_hud.bind_level_manager(level_manager)
	level_manager.level_loading.connect(func(_d: LevelDefinition) -> void: Sfx.play(&"portal"))
	# A level's world (forest, mountain, volcano...) gets its own track when
	# a file exists, else the generic level music.
	level_manager.level_loaded.connect(func(d: LevelDefinition) -> void:
		Sfx.play_music(d.world if Sfx.has_music(d.world) else &"level"))
	level_manager.hub_loaded.connect(func() -> void: Sfx.play_music(&"hub"))
	Sfx.play_music(&"hub")


func _process(_delta: float) -> void:
	# Streaming terrain follows whoever the camera follows (player or kart).
	var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if terrain and terrain.streaming:
		var focus: Node3D = vehicle if (vehicle and player and player.driver.is_driving) else player
		if focus:
			terrain.set_focus(focus.global_position)


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
	# The saved choice wins over the scene's default (character select).
	player.definition = CharacterRoster.player_definition()
	player.view_node = camera_rig
	add_child(player)

	var spawn := _find_spawn_point()
	if spawn:
		player.set_spawn_transform(spawn.global_transform)

	camera_rig.set_target(player)
	if hud.has_method(&"bind_player"):
		hud.call(&"bind_player", player)


## Character select: the hero becomes `id`; NPCs are re-cast on the next
## world build, so the hub reloads right away (nobody is a duplicate).
func set_character(id: StringName) -> void:
	# Black "Caricamento..." screen first: the world rebuild freezes a
	# moment, and without it the change looked like a hang.
	if game_hud and game_hud.has_method(&"show_loading"):
		game_hud.call(&"show_loading", true)
		await get_tree().process_frame
		await get_tree().process_frame
	ProgressionManager.set_character(id)
	if player.driver.is_driving:
		player.driver.exit_vehicle()
	player.set_definition(CharacterRoster.player_definition())
	ProgressionManager.apply_to(player.abilities)
	if level_manager.is_in_hub():
		level_manager.return_to_hub()
	await get_tree().process_frame
	await get_tree().process_frame
	if game_hud and game_hud.has_method(&"show_loading"):
		game_hud.call(&"show_loading", false)


## Progression grants abilities on top of the definitions' starters, now and
## whenever something new gets unlocked, and records level results.
func _wire_progression() -> void:
	ProgressionManager.apply_to(player.abilities)
	if vehicle:
		ProgressionManager.apply_to(vehicle.abilities)
	ProgressionManager.ability_unlocked.connect(func(id: StringName) -> void:
		player.abilities.unlock(id)
		if vehicle:
			vehicle.abilities.unlock(id))
	level_manager.level_completed.connect(ProgressionManager.record_level_completion)


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
