class_name SettingsMenu
extends PanelContainer
## Options page inside the pause menu: quality, flight/camera Y inversion,
## look sensitivity, volumes, and a "Comandi" page listing the controls.
## Everything writes straight into the Settings autoload.

signal closed

@onready var title_label: Label = $Margin/Rows/Title
@onready var rows: VBoxContainer = $Margin/Rows/Options
@onready var controls_label: Label = $Margin/Rows/Controls
@onready var controls_button: Button = $Margin/Rows/Buttons/ControlsButton
@onready var back_button: Button = $Margin/Rows/Buttons/Back

var quality_buttons: Dictionary = {}
var fly_check: CheckButton
var look_check: CheckButton
var sensitivity_slider: HSlider
var sfx_slider: HSlider
var music_slider: HSlider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	title_label.text = tr(&"SET_TITLE")
	back_button.text = tr(&"PICK_BACK")
	controls_button.text = tr(&"SET_CONTROLS")
	back_button.pressed.connect(func() -> void: close())
	controls_button.pressed.connect(_toggle_controls)
	controls_label.visible = false
	_build()
	Settings.changed.connect(_refresh)


func open() -> void:
	_refresh()
	controls_label.visible = false
	rows.visible = true
	visible = true
	back_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	# Quality: three buttons in a row.
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override(&"separation", 10)
	q_row.add_child(_label(tr(&"SET_QUALITY")))
	for id in Settings.QUALITY_NAMES:
		var b := Button.new()
		b.text = tr(StringName("SET_QUALITY_" + String(id).to_upper()))
		b.custom_minimum_size = Vector2(90.0, 36.0)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: Settings.set_quality(id))
		q_row.add_child(b)
		quality_buttons[id] = b
	rows.add_child(q_row)
	# Toggles.
	fly_check = CheckButton.new()
	fly_check.text = tr(&"SET_INVERT_FLY")
	fly_check.add_theme_font_size_override(&"font_size", 20)
	fly_check.toggled.connect(func(on: bool) -> void: Settings.set_invert_fly_y(on))
	rows.add_child(fly_check)
	look_check = CheckButton.new()
	look_check.text = tr(&"SET_INVERT_LOOK")
	look_check.add_theme_font_size_override(&"font_size", 20)
	look_check.toggled.connect(func(on: bool) -> void: Settings.set_invert_look_y(on))
	rows.add_child(look_check)
	# Sliders.
	sensitivity_slider = _slider(tr(&"SET_SENSITIVITY"), 0.3, 2.5, 0.05, func(v: float) -> void: Settings.set_look_sensitivity(v))
	sfx_slider = _slider(tr(&"SET_SFX"), 0.0, 1.0, 0.05, func(v: float) -> void: Settings.set_sfx_volume(v))
	music_slider = _slider(tr(&"SET_MUSIC"), 0.0, 1.0, 0.05, func(v: float) -> void: Settings.set_music_volume(v))
	controls_label.text = tr(&"SET_CONTROLS_TEXT")


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 20)
	l.custom_minimum_size = Vector2(170.0, 0.0)
	return l


func _slider(text: String, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.add_child(_label(text))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240.0, 30.0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	rows.add_child(row)
	return s


func _refresh() -> void:
	for id in quality_buttons:
		(quality_buttons[id] as Button).button_pressed = Settings.quality == id
	fly_check.set_pressed_no_signal(Settings.invert_fly_y)
	look_check.set_pressed_no_signal(Settings.invert_look_y)
	sensitivity_slider.set_value_no_signal(Settings.look_sensitivity)
	sfx_slider.set_value_no_signal(Settings.sfx_volume)
	music_slider.set_value_no_signal(Settings.music_volume)


func _toggle_controls() -> void:
	controls_label.visible = not controls_label.visible
	rows.visible = not controls_label.visible
	if controls_label.visible:
		controls_label.text = tr(&"SET_CONTROLS_TOUCH") if TouchControls.active else tr(&"SET_CONTROLS_TEXT")
