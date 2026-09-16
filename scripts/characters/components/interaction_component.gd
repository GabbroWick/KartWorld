class_name InteractionComponent
extends Node
## Lets the character use things in the world with `interact`: NPCs, signs,
## switches... Anything in group "interactable" that implements
## `can_interact(player) -> bool`, `interact(player)` and `get_prompt() ->
## String`, plus `global_position`. Nearest one in range wins. The kart keeps
## its own path in DriverComponent; this runs first and consumes the press.

const GROUP := &"interactable"

@export var reach := 2.6

var _character: CharacterController


func _ready() -> void:
	_character = get_parent() as CharacterController
	# Before DriverComponent (10): an NPC in front of the kart gets the press.
	process_physics_priority = 5


func _physics_process(_delta: float) -> void:
	if _character == null or _character.driver.is_driving:
		return
	if not _character.input.interact_pressed:
		return
	var target := get_target()
	if target == null:
		return
	target.call(&"interact", _character)
	_character.input.interact_pressed = false


## Nearest usable interactable within reach, or null. `from_kart` keeps
## only the ones usable at the wheel (`can_use_from_kart()`), e.g. a race.
func get_target(from_kart := false) -> Node:
	var best: Node = null
	var best_distance := reach
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node.has_method(&"interact") or not node.has_method(&"get_prompt"):
			continue
		if from_kart and not (node.has_method(&"can_use_from_kart") and node.call(&"can_use_from_kart")):
			continue
		if node.has_method(&"can_interact") and not node.call(&"can_interact", _character):
			continue
		var position: Vector3 = node.call(&"get_interaction_position") if node.has_method(&"get_interaction_position") else (node as Node3D).global_position
		var distance := _character.global_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func get_prompt(from_kart := false) -> String:
	var target := get_target(from_kart)
	return target.call(&"get_prompt") if target else ""
