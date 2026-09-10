extends CanvasLayer
## The player-facing HUD: health, stars, current objective, interaction prompt.
##
## Anchored controls, no fixed pixel positions, so it works at any window
## size. Reads state through signals from the character, the LevelManager and
## the current LevelController; polls only the cheap "what can I do" prompt.

const HUB_OBJECTIVE := "Explore the island. Find a portal!"

@onready var hearts: HeartBar = $Root/TopLeft/Hearts
@onready var star_row: HBoxContainer = $Root/TopRight/StarRow
@onready var stars_label: Label = $Root/TopRight/StarRow/Stars
@onready var objective_label: Label = $Root/TopCenter/Objective
@onready var prompt_label: Label = $Root/Bottom/Prompt
@onready var notice_label: Label = $Root/Notice/Text
@onready var controls_label: Label = $Root/BottomRight/Controls

const CONTROLS_FOOT := "WASD move · Shift run · Space jump · J attack · E use · K kart"
const CONTROLS_KART := "W/S gas/brake · A/D steer · Shift turbo · Space jump · E leave"

## Friendly names for ability ids, for the unlock notice.
const ABILITY_NAMES := {
	&"enhanced_jump": "Triple jump",
	&"double_jump": "Double jump",
	&"turbo": "Kart turbo",
	&"vehicle_jump": "Kart jump",
}
const NOTICE_TIME := 3.0

var _notice_left := 0.0

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
	ProgressionManager.ability_unlocked.connect(_on_ability_unlocked)
	ProgressionManager.changed.connect(_refresh_hub_stars)
	if _manager.is_in_hub():
		_on_hub_loaded()
	else:
		_on_level_loaded(_manager.current_level)


func _process(delta: float) -> void:
	prompt_label.text = _prompt_text()
	if is_instance_valid(_player):
		controls_label.text = CONTROLS_KART if _player.driver.is_driving else CONTROLS_FOOT
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			notice_label.text = ""


func show_notice(text: String) -> void:
	notice_label.text = text
	_notice_left = NOTICE_TIME


func _on_ability_unlocked(id: StringName) -> void:
	show_notice("New ability: %s!" % ABILITY_NAMES.get(id, String(id)))


func _refresh_hub_stars() -> void:
	if _manager == null or not _manager.is_in_hub():
		return
	var total := ProgressionManager.get_total_stars()
	_set_stars_text(str(total) if total > 0 else "")


func _on_health_changed(current: float, maximum: float) -> void:
	hearts.set_hearts(current, maximum)


## Star counter text; hides the whole row when empty.
func _set_stars_text(text: String) -> void:
	stars_label.text = text
	star_row.visible = text != ""


func _on_hub_loaded() -> void:
	_level = null
	objective_label.text = HUB_OBJECTIVE
	_refresh_hub_stars()


func _on_level_loaded(_definition: LevelDefinition) -> void:
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	if _level == null:
		objective_label.text = ""
		_set_stars_text("")
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
	_set_stars_text("%d/%d" % [collected, total])


func _prompt_text() -> String:
	if not is_instance_valid(_player):
		return ""
	var driver := _player.driver
	if driver.is_driving:
		return "E  leave kart"
	var interaction := _player.interaction.get_prompt()
	if interaction != "":
		return interaction
	if driver.is_vehicle_in_reach():
		return "E  enter kart"
	if driver.vehicle != null:
		return "K  summon kart"
	return ""
