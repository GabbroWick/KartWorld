class_name Portal
extends Area3D
## A door: it swings open when the player comes close (unless the level is
## locked) and walking (or driving) through the doorway travels: to a level
## from the hub, or back to the hub.
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
## The doors open when the player is closer than this (metres).
@export_range(1.0, 20.0, 0.5) var open_radius := 6.0
@export_range(30.0, 120.0, 1.0) var open_degrees := 100.0

@onready var door_left: Node3D = $DoorLeft
@onready var door_right: Node3D = $DoorRight
@onready var label: Label3D = $Label

## 0 = shut, 1 = wide open.
var open_amount := 0.0

var _used := false
var _label_refresh_left := 0.0


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
	return not get_missing_abilities().is_empty() or _blocking_objective() != null


## The finish door stays shut while a required objective (other than
## reaching it) is open: "kill the boss first". Null when free.
func _blocking_objective() -> Objective:
	if not completes_level:
		return null
	var controller := get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	if controller == null:
		return null
	for objective in controller.objectives:
		if not objective.optional and not objective.is_complete and not objective is ReachDestinationObjective:
			return objective
	return null


func _refresh_label() -> void:
	if label == null:
		return
	if completes_level:
		var blocking := _blocking_objective()
		if blocking:
			label.text = "%s
%s" % [tr(&"PORTAL_GOAL"), tr(&"PORTAL_FIRST") % blocking.get_status_text()]
			label.modulate = Color(1.0, 0.6, 0.5)
		else:
			label.text = tr(&"PORTAL_GOAL")
			label.modulate = Color.WHITE
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
	if completes_level:
		# The blocking objective changes as enemies die: keep the sign fresh.
		_label_refresh_left -= delta
		if _label_refresh_left <= 0.0:
			_label_refresh_left = 0.5
			_refresh_label()
	var player := GameManager.get_player(0) as Node3D
	var want_open := false
	if player and not is_locked():
		var focus := player
		if player is CharacterController and player.driver.is_driving and player.driver.vehicle:
			focus = player.driver.vehicle
		want_open = focus.global_position.distance_to(global_position) < open_radius
	var before := open_amount
	open_amount = move_toward(open_amount, 1.0 if want_open else 0.0, delta * 2.5)
	if open_amount != before:
		var angle := deg_to_rad(open_degrees) * open_amount
		door_left.rotation.y = -angle
		door_right.rotation.y = angle
		if before == 0.0:
			Sfx.play(&"ui", -10.0)
	# Label3D's billboard is a no-op on Compatibility: face the camera by hand.
	var camera := get_viewport().get_camera_3d()
	if camera and label:
		var to_camera := camera.global_position - label.global_position
		to_camera.y = 0.0
		if to_camera.length_squared() > 0.001:
			label.global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP)


func is_open() -> bool:
	return open_amount > 0.5


func _on_body_entered(body: Node3D) -> void:
	if _used:
		return
	var traveller := _traveller_from(body)
	if traveller == null:
		return
	var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	if manager == null or not manager.portals_armed():
		return
	if not get_missing_abilities(traveller).is_empty() or _blocking_objective() != null:
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
