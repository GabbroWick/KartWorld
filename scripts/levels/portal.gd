class_name Portal
extends Area3D
## Walk (or drive) in to travel: to a level from the hub, or back to the hub.
##
## Detection only; the LevelManager does the loading. The portal is inert for
## a short grace period after any load so the player never bounces.

signal activated(by: CharacterController)

## Level to enter. Ignored when `returns_to_hub` or `completes_level` is set.
@export var level: LevelDefinition
@export var returns_to_hub := false
## A level's finish line: entering it completes the level (through a
## ReachDestinationObjective whose goal_zone is this portal) instead of
## travelling. The LevelController then shows the card and brings us home.
@export var completes_level := false
## Cosmetic ring spin, radians per second.
@export var spin_speed := 0.6

@onready var ring: Node3D = $Ring
@onready var label: Label3D = $Label

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_refresh_label()
	ProgressionManager.changed.connect(_refresh_label)


## Abilities the level needs that the given (or any registered) player lacks.
func get_missing_abilities(traveller: CharacterController = null) -> PackedStringArray:
	var missing := PackedStringArray()
	if returns_to_hub or completes_level or level == null:
		return missing
	var who := traveller if traveller else (GameManager.get_player(0) as CharacterController)
	for ability in level.required_abilities:
		var has := who != null and who.abilities.has(StringName(ability))
		if not has and ProgressionManager.has_ability(StringName(ability)):
			has = true
		if not has:
			missing.append(ability)
	return missing


func is_locked() -> bool:
	return not get_missing_abilities().is_empty()


func _refresh_label() -> void:
	if label == null:
		return
	if completes_level:
		label.text = tr(&"PORTAL_GOAL")
		return
	if returns_to_hub:
		label.text = tr(&"PORTAL_HOME")
		return
	if level == null:
		label.text = "?"
		return
	var missing := get_missing_abilities()
	if missing.is_empty():
		label.text = tr(level.display_name)
		label.modulate = Color.WHITE
	else:
		label.text = "%s\n%s" % [tr(level.display_name), tr(&"PORTAL_NEEDS") % AbilityComponent.display_name(StringName(missing[0]))]
		label.modulate = Color(1.0, 0.6, 0.5)


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
	if not get_missing_abilities(traveller).is_empty():
		_refresh_label()
		return
	_used = true
	activated.emit(traveller)
	if completes_level:
		# The objective listening to body_entered completes the level.
		return
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
