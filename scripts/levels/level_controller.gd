class_name LevelController
extends Node
## Runs one level: owns its objectives, counts stars, reports completion.
##
## Lives inside the level scene (group "level_controller"). Objectives are its
## child nodes. When every non-optional objective is complete it tells the
## LevelManager, which records the result and brings the party home. Nothing
## here is specific to any level.

signal objectives_changed
signal stars_changed(collected: int, total: int)
signal completed(stars: int)

const GROUP := &"level_controller"

## Seconds between the last objective completing and the return to the hub,
## so the player sees it happen.
@export_range(0.0, 10.0, 0.1) var completion_delay := 3.5
## Return home automatically when done. Off for levels with a goal portal.
@export var auto_return := true

var objectives: Array[Objective] = []
var stars_collected := 0
var stars_total := 0
var is_complete := false


func _ready() -> void:
	add_to_group(GROUP)
	# Collectibles and objectives register on their own _ready; wait a frame.
	call_deferred(&"_start")


func _exit_tree() -> void:
	# Whatever way the level ends (completion, pause menu, death), thaw.
	GameManager.set_frozen(false)


## The level scene's root: collectibles, checkpoints and zones live under it,
## next to this controller, not inside it.
func get_level_root() -> Node:
	return get_parent()


## True when `node` belongs to this level's scene.
func owns(node: Node) -> bool:
	return get_level_root().is_ancestor_of(node)


func _start() -> void:
	for node in get_tree().get_nodes_in_group(Collectible.GROUP):
		var item := node as Collectible
		if item and item.kind == &"star" and owns(item):
			stars_total += item.amount
			item.collected.connect(_on_star_collected)
	for child in get_children():
		if child is Objective:
			objectives.append(child)
			child.completed.connect(_on_objective_completed)
			child.progress_changed.connect(func(_o: Objective) -> void: objectives_changed.emit())
			child.setup(self)
	objectives_changed.emit()
	stars_changed.emit(stars_collected, stars_total)


## The objective the HUD should show: first incomplete required one, else
## first incomplete optional, else null.
func get_current_objective() -> Objective:
	for objective in objectives:
		if not objective.is_complete and not objective.optional:
			return objective
	for objective in objectives:
		if not objective.is_complete:
			return objective
	return null


func _on_star_collected(item: Collectible, _by: CharacterController) -> void:
	stars_collected += item.amount
	stars_changed.emit(stars_collected, stars_total)


func _on_objective_completed(_objective: Objective) -> void:
	# Decide completion first, then notify, so the HUD sees the final state.
	if not is_complete:
		var all_required_done := true
		for objective in objectives:
			if not objective.optional and not objective.is_complete:
				all_required_done = false
				break
		if all_required_done:
			is_complete = true
			# Freeze the world: nothing may hurt the player while the card shows.
			GameManager.set_frozen(true)
			objectives_changed.emit()
			completed.emit(stars_collected)
			if auto_return:
				_return_home()
			return
	objectives_changed.emit()


func _return_home() -> void:
	if completion_delay > 0.0:
		# process_always: the timer must run while the world is frozen.
		await get_tree().create_timer(completion_delay, true).timeout
	GameManager.set_frozen(false)
	var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	if manager:
		manager.complete_level(stars_collected)
