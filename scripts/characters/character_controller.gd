class_name CharacterController
extends CharacterBody3D
## Generic playable character. NOT the leopard.
##
## Thin orchestrator: it gathers intent from CharacterInput, converts it to a
## camera-relative world direction, hands it to CharacterMotor, and turns the
## visual. Everything character-specific lives in the CharacterDefinition
## resource, so a new character = new .tres + new model.

signal respawned
signal died

@export var definition: CharacterDefinition
## Node whose basis defines "forward" for the player (usually the active camera).
## Falls back to the viewport camera so the scene also runs standalone.
@export var view_node: Node3D
@export var is_player_controlled := true
## Below this height the character is considered fallen out of the world.
@export var fall_limit := -25.0

@onready var input: CharacterInput = $InputSource
@onready var motor: CharacterMotor = $Motor
@onready var health: HealthComponent = $Health
@onready var abilities: AbilityComponent = $Abilities
@onready var visual_root: Node3D = $VisualRoot
@onready var collision: CollisionShape3D = $Collision

var spawn_transform: Transform3D
var _visual_instance: Node3D


func _ready() -> void:
	if definition == null:
		push_error("CharacterController '%s' has no CharacterDefinition assigned." % name)
		set_physics_process(false)
		return

	_apply_definition()
	spawn_transform = global_transform
	health.died.connect(_on_died)

	# NPCs and remote/AI characters share this scene; only a local player
	# reads the device.
	input.reads_local_device = is_player_controlled
	if is_player_controlled:
		GameManager.register_player(self)


func _physics_process(delta: float) -> void:
	input.poll()

	var wish_dir := _get_wish_direction(input.move_axis)
	motor.move(delta, wish_dir, input.run_held, input.jump_pressed, input.jump_released)
	_face_direction(wish_dir, delta)

	if global_position.y < fall_limit and not health.is_dead:
		health.kill()


## Applies the data resource to every component. Called again if the definition
## is swapped at runtime (character selection later on).
func _apply_definition() -> void:
	abilities.setup(definition.starting_abilities)
	health.setup(definition.max_health)
	motor.setup(self, definition, abilities)

	var shape := collision.shape as CapsuleShape3D
	if shape:
		# Unique per instance so different characters can have different sizes.
		shape = shape.duplicate()
		shape.height = definition.capsule_height
		shape.radius = definition.capsule_radius
		collision.shape = shape
		collision.position.y = definition.capsule_height * 0.5

	_spawn_visual()


func _spawn_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	if definition.visual_scene == null:
		return
	_visual_instance = definition.visual_scene.instantiate() as Node3D
	visual_root.add_child(_visual_instance)


func _get_wish_direction(axis: Vector2) -> Vector3:
	if axis.length_squared() < 0.0001:
		return Vector3.ZERO
	var basis_source := _get_view_basis()
	var forward := -basis_source.z
	var right := basis_source.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var dir := right.normalized() * axis.x + forward.normalized() * -axis.y
	return dir.limit_length(1.0)


func _get_view_basis() -> Basis:
	if is_instance_valid(view_node):
		return view_node.global_basis
	var camera := get_viewport().get_camera_3d()
	return camera.global_basis if camera else global_basis


func _face_direction(wish_dir: Vector3, delta: float) -> void:
	if wish_dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-wish_dir.x, -wish_dir.z)
	visual_root.rotation.y = lerp_angle(
		visual_root.rotation.y, target_yaw, minf(definition.turn_speed * delta, 1.0)
	)


func set_spawn_transform(new_transform: Transform3D, teleport: bool = true) -> void:
	spawn_transform = new_transform
	if teleport:
		global_transform = new_transform


func respawn() -> void:
	global_transform = spawn_transform
	motor.reset()
	health.restore_full()
	respawned.emit()


func _on_died() -> void:
	died.emit()
	# Checkpoints arrive in a later phase; for now the spawn point is the
	# respawn point so falling off the arena is recoverable.
	respawn()
