class_name Collectible
extends Area3D
## Base for anything the player picks up by touching it: stars, coins, keys,
## power-ups. Detection and bookkeeping only; what the pickup *means* is up to
## the listener (LevelController, progression, an ability system...).

signal collected(collectible: Collectible, by: CharacterController)

const GROUP := &"collectible"

## Kind of pickup, e.g. "star". Objectives filter on it.
@export var kind: StringName = &"item"
## Worth of this pickup toward its kind's count.
@export_range(1, 100, 1) var amount := 1
## Non-empty = remembered forever once picked up (hub stars, secrets). Levels
## leave it empty: their collectibles reset every run.
@export var persistent_id: StringName = &""

var is_collected := false


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	if persistent_id != &"" and ProgressionManager.is_collected(persistent_id):
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if is_collected:
		return
	var collector := _collector_from(body)
	if collector == null:
		return
	is_collected = true
	if persistent_id != &"":
		ProgressionManager.record_collected(persistent_id, kind, amount)
	collected.emit(self, collector)
	_on_collected(collector)


## Override for feedback. Default: vanish.
func _on_collected(_by: CharacterController) -> void:
	queue_free()


func _collector_from(body: Node3D) -> CharacterController:
	if body is CharacterController and body.is_player_controlled:
		return body
	if body is VehicleController and body.driver is CharacterController:
		return body.driver
	return null
