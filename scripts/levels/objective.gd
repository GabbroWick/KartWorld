class_name Objective
extends Node
## One goal inside a level: reach a place, collect things, defeat enemies...
##
## Objectives are nodes under the level's LevelController so a level's goals
## are configured in the scene, not coded. Subclasses implement `_start()` and
## call `complete()`; the controller listens and decides when the level is done.

signal completed(objective: Objective)
signal progress_changed(objective: Objective)

## Shown on the HUD.
@export var description := "Do the thing"
## Optional objectives never block level completion (secrets, bonus stars).
@export var optional := false

var is_complete := false
var level: LevelController


func setup(level_controller: LevelController) -> void:
	level = level_controller
	_start()


## Override: connect to whatever the objective watches.
func _start() -> void:
	pass


## Text for the HUD, e.g. "Collect stars 1/3". Override for progress.
func get_status_text() -> String:
	return description


func complete() -> void:
	if is_complete:
		return
	is_complete = true
	completed.emit(self)
