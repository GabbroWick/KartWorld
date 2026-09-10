class_name CollectObjective
extends Objective
## Complete when enough collectibles of one kind have been picked up.

## Collectible kind to count (Collectible.kind), e.g. "star".
@export var kind: StringName = &"star"
## How many to collect. 0 = every one that exists in the level at start.
@export_range(0, 100, 1) var required := 0

var collected := 0
var target := 0


func _start() -> void:
	target = required
	var present := 0
	for node in get_tree().get_nodes_in_group(Collectible.GROUP):
		var item := node as Collectible
		if item and item.kind == kind and level.owns(item):
			present += item.amount
			item.collected.connect(_on_collected)
	if target == 0:
		target = present


func get_status_text() -> String:
	return "%s %d/%d" % [description, collected, target]


func _on_collected(item: Collectible, _by: CharacterController) -> void:
	if item.kind != kind:
		return
	collected += item.amount
	progress_changed.emit(self)
	if collected >= target:
		complete()
