class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, back to the island (only inside a level), quit (not on
## the Web). Runs while the tree is paused; GameManager owns the pause state
## and the mouse, this is only the buttons.

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Panel/Margin/Rows/Title
@onready var resume_button: Button = $Root/Panel/Margin/Rows/Resume
@onready var hub_button: Button = $Root/Panel/Margin/Rows/Hub
@onready var character_button: Button = $Root/Panel/Margin/Rows/Character
@onready var settings_button: Button = $Root/Panel/Margin/Rows/Settings
@onready var settings_panel: SettingsMenu = $Root/SettingsPanel
@onready var panel: Control = $Root/Panel
@onready var picker: Control = $Root/Picker
@onready var picker_title: Label = $Root/Picker/Margin/Rows/Title
@onready var cards: HBoxContainer = $Root/Picker/Margin/Rows/Cards
@onready var back_button: Button = $Root/Picker/Margin/Rows/Back

const PORTRAIT_PATH := "res://assets/ui/portraits/%s.png"
@onready var quit_button: Button = $Root/Panel/Margin/Rows/Quit


func _ready() -> void:
	root.visible = false
	title_label.text = tr(&"PAUSE_TITLE")
	resume_button.text = tr(&"PAUSE_RESUME")
	hub_button.text = tr(&"PAUSE_HUB")
	quit_button.text = tr(&"PAUSE_QUIT")
	quit_button.visible = not OS.has_feature("web")
	resume_button.pressed.connect(func() -> void: GameManager.set_paused(false))
	hub_button.pressed.connect(_on_hub_pressed)
	character_button.pressed.connect(_on_character_pressed)
	settings_button.text = tr(&"SET_TITLE")
	settings_button.pressed.connect(func() -> void:
		panel.visible = false
		settings_panel.open())
	settings_panel.closed.connect(func() -> void:
		panel.visible = true
		settings_button.grab_focus())
	back_button.text = tr(&"PICK_BACK")
	back_button.pressed.connect(_show_picker.bind(false))
	picker_title.text = tr(&"PICK_TITLE")
	_build_cards()
	ProgressionManager.changed.connect(_refresh_character_label)
	_refresh_character_label()
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	GameManager.pause_changed.connect(_on_pause_changed)


func _on_pause_changed(paused: bool) -> void:
	root.visible = paused
	picker.visible = false
	settings_panel.visible = false
	panel.visible = true
	if paused:
		var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
		hub_button.visible = manager != null and not manager.is_in_hub()
		resume_button.grab_focus()


func _refresh_character_label() -> void:
	var definition := CharacterRoster.player_definition()
	character_button.text = tr(&"PAUSE_CHARACTER") % tr(definition.display_name)


## "Personaggio" opens the picker: one card per character, portrait + name.
func _on_character_pressed() -> void:
	_show_picker(true)


func _show_picker(show: bool) -> void:
	picker.visible = show
	panel.visible = not show
	if show:
		_refresh_cards()
		for card in cards.get_children():
			if card is Button and (card as Button).get_meta(&"id") == ProgressionManager.character:
				(card as Button).grab_focus()
	else:
		resume_button.grab_focus()


func _build_cards() -> void:
	for child in cards.get_children():
		child.queue_free()
	for id in CharacterRoster.IDS:
		var definition := CharacterRoster.definition(id)
		var card := Button.new()
		card.set_meta(&"id", id)
		card.custom_minimum_size = Vector2(180.0, 240.0)
		card.focus_mode = Control.FOCUS_ALL
		var rows := VBoxContainer.new()
		rows.alignment = BoxContainer.ALIGNMENT_CENTER
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var portrait := TextureRect.new()
		portrait.texture = load(PORTRAIT_PATH % id) if ResourceLoader.exists(PORTRAIT_PATH % id) else null
		portrait.custom_minimum_size = Vector2(160.0, 160.0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(portrait)
		var label := Label.new()
		label.text = tr(definition.display_name)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 22)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(label)
		card.add_child(rows)
		card.pressed.connect(_on_card_pressed.bind(id))
		cards.add_child(card)


func _refresh_cards() -> void:
	for card in cards.get_children():
		if card is Button:
			var chosen: bool = (card as Button).get_meta(&"id") == ProgressionManager.character
			(card as Button).modulate = Color(1, 1, 1, 1) if chosen else Color(0.75, 0.75, 0.8, 1)
			(card as Button).disabled = chosen


## Pick a card: become that character (the island reloads) and resume.
func _on_card_pressed(id: StringName) -> void:
	var main := get_tree().get_first_node_in_group(&"main")
	if main and main.has_method(&"set_character"):
		main.call(&"set_character", id)
	else:
		ProgressionManager.set_character(id)
	_refresh_character_label()
	_show_picker(false)
	GameManager.set_paused(false)


func _on_hub_pressed() -> void:
	var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	GameManager.set_paused(false)
	if manager and not manager.is_in_hub():
		manager.return_to_hub()
