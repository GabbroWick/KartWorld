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
	ProgressionManager.changed.connect(_refresh_character_label)
	_refresh_character_label()
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	GameManager.pause_changed.connect(_on_pause_changed)


func _on_pause_changed(paused: bool) -> void:
	root.visible = paused
	if paused:
		var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
		hub_button.visible = manager != null and not manager.is_in_hub()
		resume_button.grab_focus()


func _refresh_character_label() -> void:
	var definition := CharacterRoster.player_definition()
	character_button.text = tr(&"PAUSE_CHARACTER") % tr(definition.display_name)


## Cycle leopard -> fox -> panda and become it (the island reloads).
func _on_character_pressed() -> void:
	var main := get_tree().get_first_node_in_group(&"main")
	var next := CharacterRoster.next(ProgressionManager.character)
	if main and main.has_method(&"set_character"):
		main.call(&"set_character", next)
	else:
		ProgressionManager.set_character(next)
	_refresh_character_label()
	GameManager.set_paused(false)


func _on_hub_pressed() -> void:
	var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	GameManager.set_paused(false)
	if manager and not manager.is_in_hub():
		manager.return_to_hub()
