class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets (Web build included).
##
## Shown only when a touchscreen exists (or `force_visible`). It never talks
## to the character or the kart: it feeds the same Input actions the
## keyboard does (`Input.action_press` / `parse_input_event` with strength
## for the stick), so every controller keeps polling `InputActions` as
## before. Camera drag goes straight to `ThirdPersonCamera.add_look_delta`.
##
## Layout (landscape): left half = virtual stick (walk / steer+throttle),
## right half = drag to look; buttons bottom-right: Jump, Attack|Turbo,
## Use, Kart, Dance; top-right: Pause.

@export var force_visible := false
@export_range(40.0, 200.0, 1.0) var stick_radius := 90.0
@export_range(0.5, 4.0, 0.1) var look_sensitivity := 1.6

@onready var root: Control = $Root
@onready var stick_base: Control = $Root/Stick/Base
@onready var stick_knob: Control = $Root/Stick/Knob
@onready var buttons: Control = $Root/Buttons

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _look_finger := -1
var _held: Dictionary = {}   # button name -> true while pressed
var _camera: ThirdPersonCamera
var _driving := false


## True when the on-screen controls are in use (HUD hides the key hints).
static var active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var touch := DisplayServer.is_touchscreen_available() or force_visible
	active = touch
	root.visible = touch
	set_process(touch)
	set_process_input(touch)
	if not touch:
		return
	stick_base.visible = false
	stick_knob.visible = false
	for button in buttons.get_children():
		if button is BaseButton:
			var b := button as BaseButton
			b.focus_mode = Control.FOCUS_NONE
			b.button_down.connect(_on_button_down.bind(b.name))
			b.button_up.connect(_on_button_up.bind(b.name))
	_relabel()


func _process(_delta: float) -> void:
	# The Attack button becomes Turbo at the wheel; labels follow.
	var player := GameManager.get_player(0) as CharacterController
	var driving: bool = player != null and player.driver != null and player.driver.is_driving
	if driving != _driving:
		_driving = driving
		_relabel()
	if _camera == null:
		_camera = get_tree().get_first_node_in_group(&"camera_rig") as ThirdPersonCamera
	# Only the pause button stays usable while paused.
	var paused := GameManager.is_paused
	for button in buttons.get_children():
		if button is Control and button.name != "Pause":
			(button as Control).visible = not paused
	if paused and (_stick_finger >= 0 or _look_finger >= 0):
		_touch_ended(_stick_finger)
		_touch_ended(_look_finger)


func _relabel() -> void:
	_set_label("Jump", tr(&"TOUCH_JUMP"))
	_set_label("Action", tr(&"TOUCH_TURBO") if _driving else tr(&"TOUCH_ATTACK"))
	_set_label("Use", tr(&"TOUCH_USE"))
	_set_label("Kart", tr(&"TOUCH_KART"))
	_set_label("Dance", tr(&"TOUCH_DANCE"))
	_set_label("Pause", "II")


func _set_label(button_name: String, text: String) -> void:
	var b := buttons.get_node_or_null(button_name) as Button
	if b:
		b.text = text


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_began(touch.index, touch.position)
		else:
			_touch_ended(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_finger:
			_stick_moved(drag.position)
		elif drag.index == _look_finger and _camera:
			_camera.add_look_delta(drag.relative * look_sensitivity)


func _touch_began(index: int, position: Vector2) -> void:
	# Fingers over a button are the button's business.
	for button in buttons.get_children():
		if button is Control and (button as Control).visible and (button as Control).get_global_rect().has_point(position):
			return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if position.x < half and _stick_finger < 0:
		_stick_finger = index
		_stick_origin = position
		stick_base.position = position - stick_base.size * 0.5
		stick_knob.position = position - stick_knob.size * 0.5
		stick_base.visible = true
		stick_knob.visible = true
		_stick_moved(position)
	elif position.x >= half and _look_finger < 0:
		_look_finger = index


func _touch_ended(index: int) -> void:
	if index == _stick_finger:
		_stick_finger = -1
		_stick_vector = Vector2.ZERO
		stick_base.visible = false
		stick_knob.visible = false
		_apply_stick()
	elif index == _look_finger:
		_look_finger = -1


func _stick_moved(position: Vector2) -> void:
	var offset := position - _stick_origin
	var vector := offset.limit_length(stick_radius) / stick_radius
	stick_knob.position = _stick_origin + vector * stick_radius - stick_knob.size * 0.5
	_stick_vector = vector
	_apply_stick()


## Stick -> move_forward/backward/left/right with analog strength. Walking
## and driving read the same four actions (steer = left/right, throttle =
## accelerate/brake), so the stick drives both.
func _apply_stick() -> void:
	var v := _stick_vector
	_strength(InputActions.MOVE_RIGHT, maxf(v.x, 0.0))
	_strength(InputActions.MOVE_LEFT, maxf(-v.x, 0.0))
	_strength(InputActions.MOVE_BACKWARD, maxf(v.y, 0.0))
	_strength(InputActions.MOVE_FORWARD, maxf(-v.y, 0.0))
	_strength(InputActions.ACCELERATE, maxf(-v.y, 0.0))
	_strength(InputActions.BRAKE, maxf(v.y, 0.0))
	# Push the stick past 80% to run.
	_strength(InputActions.RUN, 1.0 if v.length() > 0.8 else 0.0)


func _strength(action: StringName, value: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = value > 0.02
	ev.strength = clampf(value, 0.0, 1.0)
	Input.parse_input_event(ev)


func _on_button_down(button_name: String) -> void:
	_held[button_name] = true
	match button_name:
		"Jump": Input.action_press(InputActions.JUMP)
		"Action": Input.action_press(InputActions.TURBO if _driving else InputActions.ATTACK)
		"Use": Input.action_press(InputActions.INTERACT)
		"Kart": Input.action_press(InputActions.SUMMON_KART)
		"Dance": Input.action_press(InputActions.EMOTE)
		"Pause": GameManager.set_paused(not GameManager.is_paused)


func _on_button_up(button_name: String) -> void:
	_held.erase(button_name)
	match button_name:
		"Jump": Input.action_release(InputActions.JUMP)
		"Action":
			Input.action_release(InputActions.TURBO)
			Input.action_release(InputActions.ATTACK)
		"Use": Input.action_release(InputActions.INTERACT)
		"Kart": Input.action_release(InputActions.SUMMON_KART)
		"Dance": Input.action_release(InputActions.EMOTE)
