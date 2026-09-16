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
@onready var profile_button: Button = $Root/Panel/Margin/Rows/Profile
@onready var profiles: Control = $Root/Profiles
@onready var profiles_title: Label = $Root/Profiles/Margin/Rows/Title
@onready var profile_cards: HBoxContainer = $Root/Profiles/Margin/Rows/Cards
@onready var profiles_back: Button = $Root/Profiles/Margin/Rows/Back

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
	profile_button.pressed.connect(_show_profiles.bind(true))
	profiles_title.text = tr(&"PROFILE_TITLE")
	profiles_back.text = tr(&"PICK_BACK")
	profiles_back.pressed.connect(_show_profiles.bind(false))
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
	profile_button.text = tr(&"PAUSE_PROFILE") % ProgressionManager.profile


# --- save profiles ------------------------------------------------------------

func _show_profiles(show: bool) -> void:
	profiles.visible = show
	panel.visible = not show
	if show:
		_build_profile_cards()
	else:
		profile_button.grab_focus()


## One card per slot: hero portrait, "Profilo N", stars, a Use/Play
## button and a two-press Delete (first press asks "Sicuro?").
func _build_profile_cards() -> void:
	for child in profile_cards.get_children():
		child.queue_free()
	for slot in range(1, ProgressionManager.PROFILES + 1):
		var summary := ProgressionManager.profile_summary(slot)
		var active := slot == ProgressionManager.profile
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(190.0, 250.0)
		card.set_meta(&"slot", slot)
		var rows := VBoxContainer.new()
		rows.alignment = BoxContainer.ALIGNMENT_CENTER
		rows.add_theme_constant_override(&"separation", 6)
		card.add_child(rows)
		var title := Label.new()
		title.text = tr(&"PROFILE_NAME") % slot
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override(&"font_size", 22)
		if active:
			title.add_theme_color_override(&"font_color", Color(1, 0.92, 0.4))
		rows.add_child(title)
		var portrait := TextureRect.new()
		var id: StringName = summary["character"]
		portrait.texture = load(PORTRAIT_PATH % id) if summary["exists"] and ResourceLoader.exists(PORTRAIT_PATH % id) else null
		portrait.custom_minimum_size = Vector2(120.0, 120.0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.modulate = Color(1, 1, 1, 1) if summary["exists"] else Color(1, 1, 1, 0.2)
		rows.add_child(portrait)
		var info := Label.new()
		info.text = (tr(&"PROFILE_STARS") % int(summary["stars"])) if summary["exists"] else tr(&"PROFILE_EMPTY")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override(&"font_size", 18)
		rows.add_child(info)
		var use := Button.new()
		use.name = "Use"
		use.text = tr(&"PROFILE_IN_USE") if active else tr(&"PROFILE_USE")
		use.disabled = active
		use.add_theme_font_size_override(&"font_size", 18)
		use.pressed.connect(_on_profile_pressed.bind(slot))
		rows.add_child(use)
		var wipe := Button.new()
		wipe.name = "Delete"
		wipe.text = tr(&"PROFILE_DELETE")
		wipe.visible = summary["exists"]
		wipe.add_theme_font_size_override(&"font_size", 16)
		wipe.modulate = Color(1, 0.7, 0.7)
		wipe.pressed.connect(_on_profile_delete_pressed.bind(slot, wipe))
		rows.add_child(wipe)
		profile_cards.add_child(card)
		if active:
			use.grab_focus()


func _on_profile_pressed(slot: int) -> void:
	var main := get_tree().get_first_node_in_group(&"main")
	if main and main.has_method(&"set_profile"):
		main.call(&"set_profile", slot)
	else:
		ProgressionManager.switch_profile(slot)
	_refresh_character_label()
	_show_profiles(false)
	GameManager.set_paused(false)


func _on_profile_delete_pressed(slot: int, button: Button) -> void:
	if button.get_meta(&"armed", false):
		ProgressionManager.delete_profile(slot)
		if slot == ProgressionManager.profile:
			var main := get_tree().get_first_node_in_group(&"main")
			if main and main.has_method(&"set_profile"):
				# Reload the island as a fresh hero.
				var other := 1 if slot != 1 else 2
				ProgressionManager.switch_profile(other)
				main.call(&"set_profile", slot)
		_build_profile_cards()
	else:
		button.set_meta(&"armed", true)
		button.text = tr(&"PROFILE_SURE")


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
