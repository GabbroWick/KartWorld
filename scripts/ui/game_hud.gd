class_name GameHUD
extends CanvasLayer
## The player-facing HUD: health, stars, current objective, interaction prompt.
##
## Anchored controls, no fixed pixel positions, so it works at any window
## size. Reads state through signals from the character, the LevelManager and
## the current LevelController; polls only the cheap "what can I do" prompt.


@onready var hearts: HeartBar = $Root/TopLeft/TopLeftRows/Hearts
@onready var turbo_gauge: TurboGauge = $Root/TopLeft/TopLeftRows/Turbo
@onready var inventory_label: Label = $Root/TopLeft/TopLeftRows/Inventory
@onready var fade_rect: ColorRect = $Root/Fade
@onready var world_map: WorldMap = $WorldMap
@onready var minimap: MapView = $Root/Minimap
@onready var full_map: PanelContainer = $Root/FullMap
@onready var full_map_view: MapView = $Root/FullMap/Rows/View
@onready var full_map_title: Label = $Root/FullMap/Rows/Title
@onready var full_map_close: Button = $Root/FullMap/Rows/Close
@onready var shop_menu: ShopMenu = $Root/ShopMenu
@onready var inventory_menu: InventoryMenu = $Root/InventoryMenu
@onready var loading_label: Label = $Root/Fade/Loading
@onready var star_row: HBoxContainer = $Root/TopRight/StarRow
@onready var stars_label: Label = $Root/TopRight/StarRow/Stars
@onready var objective_label: Label = $Root/TopCenter/Objective
@onready var prompt_label: Label = $Root/Bottom/Prompt
@onready var notice_label: Label = $Root/Notice/Text
@onready var controls_label: Label = $Root/BottomRight/Controls
@onready var card: LevelCompleteCard = $Root/Card


const NOTICE_TIME := 3.0

var _notice_left := 0.0

var _player: CharacterController
var _manager: LevelManager
var _level: LevelController


func _ready() -> void:
	add_to_group(&"hud")
	minimap.world_map = world_map
	full_map_view.world_map = world_map
	full_map_title.text = tr(&"MAP_TITLE")
	full_map_close.text = tr(&"MAP_CLOSE")
	full_map_close.pressed.connect(func() -> void: set_full_map(false))
	full_map.process_mode = Node.PROCESS_MODE_ALWAYS
	ProgressionManager.changed.connect(_refresh_inventory)
	_refresh_inventory()


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
		var driving := _player.driver.is_driving
		var turbo: TurboAbility = _player.driver.vehicle.turbo if driving and _player.driver.vehicle else null
		turbo_gauge.visible = turbo != null
		if turbo:
			turbo_gauge.charge = turbo.charge
			turbo_gauge.boosting = turbo.is_active
		if TouchControls.active:
			controls_label.text = ""
		else:
			controls_label.text = tr(&"HUD_CONTROLS_KART") if _player.driver.is_driving else tr(&"HUD_CONTROLS_FOOT")
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			notice_label.text = ""


func _refresh_inventory() -> void:
	var parts := PackedStringArray()
	for item in [&"fruit", &"meat"]:
		var n := ProgressionManager.count_item(item)
		if n > 0:
			parts.append("%s %d" % [tr(&"ITEM_" + String(item).to_upper()), n])
	inventory_label.text = " · ".join(parts)


## Black screen with "Caricamento..." while a world is rebuilt (character
## change). Call with false when done.
func show_loading(on: bool) -> void:
	fade_rect.visible = on
	fade_rect.color.a = 1.0 if on else 0.0
	loading_label.visible = on
	loading_label.text = tr(&"HUD_LOADING")


## Fade to black and back (sleeping). Awaitable.
func fade(seconds: float) -> void:
	fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, seconds * 0.4)
	tween.tween_interval(seconds * 0.2)
	tween.tween_property(fade_rect, "color:a", 0.0, seconds * 0.4)
	await tween.finished
	fade_rect.visible = false


func toggle_inventory() -> void:
	inventory_menu.toggle()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.INVENTORY) and not inventory_menu.visible and not shop_menu.visible and not GameManager.is_paused:
		inventory_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.MAP) and minimap.visible:
		set_full_map(not full_map.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.PAUSE) and full_map.visible:
		set_full_map(false)
		get_viewport().set_input_as_handled()


func open_shop() -> void:
	shop_menu.open()


## The whole island on screen (M). Only where a map exists (the hub).
func set_full_map(show: bool) -> void:
	full_map.visible = show and minimap.visible
	if full_map.visible:
		Sfx.play(&"ui", -8.0)


func show_notice(text: String) -> void:
	notice_label.text = text
	_notice_left = NOTICE_TIME


func _on_ability_unlocked(id: StringName) -> void:
	Sfx.play(&"unlock")
	show_notice(tr(&"HUD_NEW_ABILITY") % AbilityComponent.display_name(id))


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
	var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	world_map.build_for(terrain)
	minimap.visible = terrain != null
	_level = null
	card.dismiss()
	objective_label.text = tr(&"HUD_HUB_HINT")
	_refresh_hub_stars()


func _on_level_loaded(_definition: LevelDefinition) -> void:
	minimap.visible = false
	full_map.visible = false
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController
	if _level == null:
		objective_label.text = ""
		_set_stars_text("")
		return
	_level.objectives_changed.connect(_refresh_objective)
	_level.stars_changed.connect(_on_stars_changed)
	_level.completed.connect(_on_level_completed.bind(_definition))
	_refresh_objective()
	_on_stars_changed(_level.stars_collected, _level.stars_total)


func _refresh_objective() -> void:
	if not is_instance_valid(_level):
		return
	if _level.is_complete:
		objective_label.text = tr(&"HUD_LEVEL_COMPLETE")
		return
	var objective := _level.get_current_objective()
	objective_label.text = objective.get_status_text() if objective else ""


func _on_level_completed(stars: int, definition: LevelDefinition) -> void:
	var first_time := definition != null and not ProgressionManager.is_level_completed(definition.id)
	var total := _level.stars_total if is_instance_valid(_level) else stars
	card.show_result(definition, stars, total, first_time)
	Sfx.play(&"fanfare")


func _on_stars_changed(collected: int, total: int) -> void:
	_set_stars_text("%d/%d" % [collected, total])


func _prompt_text() -> String:
	var text := _prompt_text_keys()
	if TouchControls.active and text.length() > 3 and text[1] == " " and text[2] == " ":
		# "E  parla con Volpe" -> "parla con Volpe": no keys on a phone.
		return text.substr(3)
	return text


func _prompt_text_keys() -> String:
	if not is_instance_valid(_player):
		return ""
	var driver := _player.driver
	if driver.is_driving:
		return "" if (driver.vehicle and (driver.vehicle.is_submarine or driver.vehicle.is_flying())) else tr(&"PROMPT_LEAVE_KART")
	var interaction := _player.interaction.get_prompt()
	if interaction != "":
		return interaction
	if driver.is_vehicle_in_reach():
		return tr(&"PROMPT_ENTER_KART")
	if driver.vehicle != null:
		return tr(&"PROMPT_SUMMON_KART")
	return ""
