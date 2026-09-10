class_name ReachDestinationObjective
extends Objective
## Complete when the player (on foot or in the kart) enters the goal zone.

## An Area3D in the level with a collision mask covering player and vehicle.
@export var goal_zone: NodePath

var _zone: Area3D


func _start() -> void:
	_zone = get_node_or_null(goal_zone) as Area3D
	if _zone == null:
		push_error("ReachDestinationObjective '%s': goal_zone not found." % name)
		return
	_zone.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterController and body.is_player_controlled:
		complete()
	elif body is VehicleController and body.driver is CharacterController:
		complete()
