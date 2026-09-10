class_name Portal
extends Area3D
## Walk (or drive) in to travel: to a level from the hub, or back to the hub.
##
## Detection only; the LevelManager does the loading. The portal is inert for
## a short grace period after any load so the player never bounces.

signal activated(by: CharacterController)

## Level to enter. Ignored when `returns_to_hub` is set.
@export var level: LevelDefinition
@export var returns_to_hub := false
## Cosmetic ring spin, radians per second.
@export var spin_speed := 0.6

@onready var ring: Node3D = $Ring
@onready var label: Label3D = $Label

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if label:
		label.text = "Home" if returns_to_hub else (level.display_name if level else "?")


func _process(delta: float) -> void:
	if ring:
		ring.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if _used:
		return
	var traveller := _traveller_from(body)
	if traveller == null:
		return
	var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	if manager == null or not manager.portals_armed():
		return
	if not returns_to_hub and level != null:
		for ability in level.required_abilities:
			if not traveller.abilities.has(StringName(ability)):
				return
	_used = true
	activated.emit(traveller)
	# Deferred: we are inside a physics callback and about to free the world.
	if returns_to_hub:
		manager.call_deferred(&"return_to_hub")
	else:
		manager.call_deferred(&"load_level", level)


func _traveller_from(body: Node3D) -> CharacterController:
	if body is CharacterController and body.is_player_controlled:
		return body
	if body is VehicleController and body.driver is CharacterController:
		return body.driver
	return null
