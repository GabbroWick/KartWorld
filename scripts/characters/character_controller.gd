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
signal hurt(amount: float, source: Node)

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
@onready var driver: DriverComponent = $Driver
@onready var combat: CharacterCombat = $Combat
@onready var interaction: InteractionComponent = $Interaction
@onready var visual_root: Node3D = $VisualRoot
@onready var collision: CollisionShape3D = $Collision

var spawn_transform: Transform3D
var invulnerable_left := 0.0
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

	var wish_dir := input.world_direction.limit_length(1.0) if input.uses_world_direction \
		else _get_wish_direction(input.move_axis)
	motor.move(delta, wish_dir, input.run_held, input.jump_pressed, input.jump_released)
	_face_direction(wish_dir, delta)
	combat.tick(delta, input.attack_pressed)
	if input.emote_pressed and is_on_floor() and not combat.is_attacking 			and _visual_instance and _visual_instance.has_method(&"play_action"):
		_visual_instance.call(&"play_action", &"emote", 1.0)
	_tick_invulnerability(delta)
	_animate_visual(delta)

	if global_position.y < fall_limit and not health.is_dead:
		health.kill()


## Applies the data resource to every component. Called again if the definition
## is swapped at runtime (character selection later on).
func _apply_definition() -> void:
	abilities.setup(definition.starting_abilities)
	health.setup(definition.max_health)
	motor.setup(self, definition, abilities)
	combat.setup(self, definition)

	var shape := collision.shape as CapsuleShape3D
	if shape:
		# Unique per instance so different characters can have different sizes.
		shape = shape.duplicate()
		shape.height = definition.capsule_height
		shape.radius = definition.capsule_radius
		collision.shape = shape
		collision.position.y = definition.capsule_height * 0.5

	_spawn_visual()
	combat.attacked.connect(_on_attacked)
	hurt.connect(_on_hurt_visual)
	if is_player_controlled and not motor.jumped.is_connected(_on_jumped_sound):
		motor.jumped.connect(_on_jumped_sound)
		motor.landed.connect(_on_landed_sound)


func _spawn_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	if definition.visual_scene == null:
		return
	_visual_instance = definition.visual_scene.instantiate() as Node3D
	_visual_instance.scale = Vector3.ONE * definition.visual_scale
	visual_root.add_child(_visual_instance)
	# A model with a real attack clip does not need the placeholder swipe arc.
	combat.show_swipe = not (_visual_instance.has_method(&"has_action")
		and _visual_instance.call(&"has_action", &"attack"))


func _on_attacked() -> void:
	if is_player_controlled:
		Sfx.play(&"attack", -4.0, randf_range(0.9, 1.1))
	if _visual_instance and _visual_instance.has_method(&"play_action"):
		_visual_instance.call(&"play_action", &"attack", 1.4)


func _on_hurt_visual(_amount: float, _source: Node) -> void:
	if is_player_controlled:
		Sfx.play(&"hurt")
	if _visual_instance and _visual_instance.has_method(&"play_action"):
		_visual_instance.call(&"play_action", &"hurt", 1.2)


func _on_jumped_sound(air_jump_index: int) -> void:
	Sfx.play(&"double_jump" if air_jump_index > 0 else &"jump", -6.0, 1.0 + 0.1 * air_jump_index)


func _on_landed_sound(impact_speed: float) -> void:
	if impact_speed > 4.0:
		Sfx.play(&"land", -10.0)


func _animate_visual(delta: float) -> void:
	if _visual_instance == null or not _visual_instance.has_method(&"animate"):
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var ratio := clampf(horizontal / maxf(definition.run_speed, 0.1), 0.0, 1.0)
	_visual_instance.call(&"animate", delta, ratio, is_on_floor())


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


## Duck-typed damage entry point (enemies, hazards, projectiles call this).
## Ignored while invulnerable or driving; shoves the character away from
## `source` and grants invulnerability frames.
func take_damage(amount: float, source: Node = null) -> void:
	if health.is_dead or invulnerable_left > 0.0 or driver.is_driving:
		return
	health.take_damage(amount, source)
	hurt.emit(amount, source)
	if health.is_dead:
		return
	invulnerable_left = definition.hurt_invulnerability
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			away = away.normalized()
			velocity.x = away.x * definition.hurt_knockback.x
			velocity.z = away.z * definition.hurt_knockback.x
			velocity.y = definition.hurt_knockback.y


func is_invulnerable() -> bool:
	return invulnerable_left > 0.0


func _tick_invulnerability(delta: float) -> void:
	if invulnerable_left <= 0.0:
		return
	invulnerable_left = maxf(invulnerable_left - delta, 0.0)
	# Blink while invulnerable, solid again when it ends.
	visual_root.visible = invulnerable_left <= 0.0 or fmod(invulnerable_left, 0.16) < 0.08


func set_spawn_transform(new_transform: Transform3D, teleport: bool = true) -> void:
	spawn_transform = new_transform
	if teleport:
		global_transform = new_transform


func respawn() -> void:
	global_transform = spawn_transform
	motor.reset()
	health.restore_full()
	invulnerable_left = 0.0
	visual_root.visible = true
	respawned.emit()


func _on_died() -> void:
	died.emit()
	# Checkpoints arrive in a later phase; for now the spawn point is the
	# respawn point so falling off the arena is recoverable.
	respawn()
