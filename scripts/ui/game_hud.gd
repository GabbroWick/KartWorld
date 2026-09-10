extends CanvasLayer
## The player-facing HUD: health, stars, current objective, interaction prompt.
##
## Anchored controls, no fixed pixel positions, so it works at any window
## size. Reads state through signals from the character, the LevelManager and
## the current LevelController; polls only the cheap "what can I do" prompt.

const HUB_OBJECTIVE := "Explore the island. Find a portal!"

@onready var health_label: Label = $Root/TopLeft/Health
@onready var stars_label: Label = $Root/TopRight/Stars
@onready var objective_label: Label = $Root/TopCenter/Objective
@onready var prompt_label: Label = $Root/Bottom/Prompt

var _player: CharacterController
var _manager: LevelManager
var _level: LevelController


func bind_player(player: CharacterController) -> void:
	_player = player
	_player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(_player.health.current_health, _player.health.max_health)


func bind_level_manager(manager: LevelManager) -> void:
	_manager = manager
	_manager.level_loaded.connect(_on_level_loaded)
	_manager.hub_loaded.connect(_on_hub_loaded)
	if _manager.is_in_hub():
		_on_hub_loaded()
	else:
		_on_level_loaded(_manager.current_level)


func _process(_delta: float) -> void:
	prompt_label.text = _prompt_text()


func _on_health_changed(current: float, maximum: float) -> void:
	var full := int(round(current))
	var empty := int(round(maximum)) - full
	health_label.text = "♥".repeat(maxi(full, 0)) + "♡".repeat(maxi(empty, 0))


func _on_hub_loaded() -> void:
	_level = null
	objective_label.text = HUB_OBJECTIVE
	stars_label.text = ""


func _on_level_loaded(_definition: LevelDefinition) -> void:
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	if _level == null:
		objective_label.text = ""
		stars_label.text = ""
		return
	_level.objectives_changed.connect(_refresh_objective)
	_level.stars_changed.connect(_on_stars_changed)
	_refresh_objective()
	_on_stars_changed(_level.stars_collected, _level.stars_total)


func _refresh_objective() -> void:
	if not is_instance_valid(_level):
		return
	if _level.is_complete:
		objective_label.text = "Level complete!"
		return
	var objective := _level.get_current_objective()
	objective_label.text = objective.get_status_text() if objective else ""


func _on_stars_changed(collected: int, total: int) -> void:
	stars_label.text = "★ %d/%d" % [collected, total]


func _prompt_text() -> String:
	if not is_instance_valid(_player):
		return ""
	var driver := _player.driver
	if driver.is_driving:
		return "E  leave kart"
	if driver.is_vehicle_in_reach():
		return "E  enter kart"
	if driver.vehicle != null:
		return "K  summon kart"
	return ""
