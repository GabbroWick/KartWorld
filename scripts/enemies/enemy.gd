class_name Enemy
extends CharacterBody3D
## Generic ground enemy: wanders near its start, chases a nearby player,
## hurts on contact, dies through the shared HealthComponent.
##
## Deliberately simple brain (idle / patrol / chase); bosses and smarter
## enemies extend or replace `_think()`, everything else stays.

signal died(enemy: Enemy)
signal damaged(amount: float, source: Node)

const GROUP := &"enemy"

enum State { IDLE, PATROL, CHASE }

@export var definition: EnemyDefinition

@onready var health: HealthComponent = $Health
@onready var visual_root: Node3D = $VisualRoot
@onready var collision: CollisionShape3D = $Collision
@onready var contact_area: Area3D = $ContactArea
@onready var hit_flash: HitFlash = $HitFlash

var state := State.IDLE
var home := Vector3.ZERO
var target: CharacterController
var _patrol_goal := Vector3.ZERO
var _idle_left := 0.0
var _gravity := 26.0
var _rng := RandomNumberGenerator.new()
var _visual_instance: Node3D
var _dying := false


func _ready() -> void:
	add_to_group(GROUP)
	if definition == null:
		push_error("Enemy '%s' has no EnemyDefinition." % name)
		set_physics_process(false)
		return
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))
	_rng.seed = hash(name) + int(global_position.x * 13.0 + global_position.z * 7.0)
	home = global_position
	_apply_definition()
	health.died.connect(_on_died)
	contact_area.body_entered.connect(_on_contact)
	_idle_left = _rng.randf_range(0.5, 1.5)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_think(delta)
	var wish := _wish_direction()
	var speed := definition.move_speed * (1.35 if state == State.CHASE else 1.0)
	velocity.x = move_toward(velocity.x, wish.x * speed, 20.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 20.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	if wish.length_squared() > 0.001:
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(-wish.x, -wish.z), 10.0 * delta)
	# Keep pressing damage on a player standing inside us.
	for body in contact_area.get_overlapping_bodies():
		_on_contact(body)


## Duck-typed damage entry point used by CharacterCombat and later by
## projectiles and kart weapons.
func take_damage(amount: float, source: Node = null) -> void:
	if _dying:
		return
	health.take_damage(amount, source)
	damaged.emit(amount, source)
	hit_flash.flash()
	Sfx.play(&"hit", 0.0, _rng.randf_range(0.9, 1.1))
	if source is Node3D and not health.is_dead:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			velocity += away.normalized() * 5.0 + Vector3.UP * 3.0


func _think(delta: float) -> void:
	target = _nearest_player()
	var distance := target.global_position.distance_to(global_position) if target else INF
	match state:
		State.CHASE:
			if target == null or distance > definition.lose_radius:
				state = State.IDLE
				_idle_left = 1.0
		_:
			if target and distance < definition.chase_radius:
				state = State.CHASE
			elif state == State.IDLE:
				_idle_left -= delta
				if _idle_left <= 0.0 and definition.patrol_radius > 0.0:
					var angle := _rng.randf_range(0.0, TAU)
					var radius := _rng.randf_range(0.3, 1.0) * definition.patrol_radius
					_patrol_goal = home + Vector3(cos(angle), 0.0, sin(angle)) * radius
					state = State.PATROL
			elif state == State.PATROL:
				if Vector2(_patrol_goal.x - global_position.x, _patrol_goal.z - global_position.z).length() < 0.4 \
						or is_on_wall():
					state = State.IDLE
					_idle_left = _rng.randf_range(0.8, 2.0)


func _wish_direction() -> Vector3:
	var goal: Vector3
	match state:
		State.CHASE:
			goal = target.global_position
		State.PATROL:
			goal = _patrol_goal
		_:
			return Vector3.ZERO
	var dir := goal - global_position
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.01 else Vector3.ZERO


func _nearest_player() -> CharacterController:
	var best: CharacterController = null
	var best_distance := INF
	for player in GameManager.players:
		var character := player as CharacterController
		if character == null or not character.visible or character.health.is_dead:
			continue
		var d := character.global_position.distance_to(global_position)
		if d < best_distance:
			best_distance = d
			best = character
	return best


func _on_contact(body: Node3D) -> void:
	if _dying:
		return
	if body is CharacterController and body.is_player_controlled:
		body.take_damage(definition.contact_damage, self)


func _apply_definition() -> void:
	health.setup(definition.max_health)
	var capsule := collision.shape as CapsuleShape3D
	if capsule:
		capsule = capsule.duplicate()
		capsule.radius = definition.body_radius
		capsule.height = maxf(definition.body_height, definition.body_radius * 2.0)
		collision.shape = capsule
		collision.position.y = capsule.height * 0.5
	var contact := contact_area.get_node("Shape") as CollisionShape3D
	var sphere := contact.shape as SphereShape3D
	if sphere:
		sphere = sphere.duplicate()
		sphere.radius = definition.body_radius + 0.25
		contact.shape = sphere
		contact.position.y = definition.body_height * 0.5
	if definition.visual_scene:
		_visual_instance = definition.visual_scene.instantiate() as Node3D
		_visual_instance.scale = Vector3.ONE * definition.visual_scale
		visual_root.add_child(_visual_instance)
		FlatMaterial.apply_fill(_visual_instance)


func _on_died() -> void:
	_dying = true
	collision.set_deferred(&"disabled", true)
	contact_area.set_deferred(&"monitoring", false)
	died.emit(self)
	Sfx.play(&"enemy_die")
	Burst.spawn(get_parent(), global_position + Vector3.UP * definition.body_height * 0.5, Color(0.5, 0.9, 0.4), 20, 5.0, 0.2)
	var tween := create_tween()
	tween.tween_property(visual_root, "scale", Vector3(1.3, 0.05, 1.3), 0.25)
	tween.tween_callback(queue_free)
