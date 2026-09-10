class_name CharacterCombat
extends Node
## Melee attack for a character: a hitbox in front of the model that is live
## for a few frames, with damage and cooldown from the CharacterDefinition.
##
## Anything the hitbox overlaps that has a `take_damage(amount, source)`
## method gets hit once per swing. Ranged attacks will be a sibling component
## that spawns projectiles; this one never needs to know about them.

signal attacked
signal hit(target: Node)

var character: CharacterController
var definition: CharacterDefinition

var is_attacking := false
var cooldown_left := 0.0
var _active_left := 0.0
var _hit_this_swing: Array[Node] = []

## The hitbox lives under the character's VisualRoot so it sits in front of
## wherever the model faces (an Area3D under a plain Node would be stuck at
## the world origin).
@export var hitbox_path: NodePath = ^"../VisualRoot/Hitbox"

@onready var hitbox: Area3D = get_node(hitbox_path)
@onready var swipe: MeshInstance3D = hitbox.get_node("Swipe")


func _ready() -> void:
	set_physics_process(false)
	hitbox.monitoring = false
	swipe.visible = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)


func setup(owner_character: CharacterController, character_definition: CharacterDefinition) -> void:
	character = owner_character
	definition = character_definition
	var shape := hitbox.get_node("Shape") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	if box:
		box = box.duplicate()
		box.size = Vector3(definition.melee_width, 1.2, definition.melee_range)
		shape.shape = box
	hitbox.position = Vector3(0.0, definition.capsule_height * 0.55, -definition.melee_range * 0.5 - 0.2)


## Called by the character every physics tick.
func tick(delta: float, attack_requested: bool) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if is_attacking:
		_active_left -= delta
		_sweep_overlaps()
		if _active_left <= 0.0:
			_end_swing()
	elif attack_requested:
		try_attack()


func try_attack() -> bool:
	if is_attacking or cooldown_left > 0.0 or definition == null:
		return false
	is_attacking = true
	_active_left = definition.melee_active_time
	cooldown_left = definition.melee_cooldown
	_hit_this_swing.clear()
	hitbox.monitoring = true
	swipe.visible = true
	attacked.emit()
	return true


func _end_swing() -> void:
	is_attacking = false
	hitbox.monitoring = false
	swipe.visible = false


## Bodies already inside the box when it switches on do not fire body_entered.
func _sweep_overlaps() -> void:
	for body in hitbox.get_overlapping_bodies():
		_try_hit(body)


func _on_hitbox_body_entered(body: Node3D) -> void:
	_try_hit(body)


func _try_hit(body: Node) -> void:
	if body == character or body in _hit_this_swing:
		return
	if not body.has_method(&"take_damage"):
		return
	_hit_this_swing.append(body)
	body.call(&"take_damage", definition.melee_damage, character)
	hit.emit(body)
