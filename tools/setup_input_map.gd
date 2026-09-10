extends SceneTree
## Generates the KartWorld Input Map into project.godot.
##
## Run:  godot --headless --script res://tools/setup_input_map.gd
##
## Bindings live here (and therefore in project.godot) instead of being written
## by hand in the editor, so they are reviewable in git and reproducible.
## Gameplay code only ever refers to the action names in
## scripts/core/input_actions.gd.

const DEADZONE := 0.2


func _initialize() -> void:
	var actions := {
		"move_forward": [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_backward": [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)],

		"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		"run": [_key(KEY_SHIFT), _button(JOY_BUTTON_B)],
		"interact": [_key(KEY_E), _button(JOY_BUTTON_X)],
		"attack": [_key(KEY_J), _mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		"emote": [_key(KEY_H), _mouse(MOUSE_BUTTON_RIGHT), _button(JOY_BUTTON_DPAD_UP)],

		# Kart. Same physical keys as walking where the meaning matches
		# (W = go, S = stop, Shift = faster); the vehicle reads its own actions.
		"accelerate": [_key(KEY_W), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"brake": [_key(KEY_S), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"turbo": [_key(KEY_SHIFT), _button(JOY_BUTTON_B)],
		"summon_kart": [_key(KEY_K), _button(JOY_BUTTON_Y)],

		"camera_left": [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1.0)],
		"camera_right": [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1.0)],
		"camera_up": [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"camera_down": [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1.0)],

		"toggle_mouse_capture": [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
		"debug_toggle_hud": [_key(KEY_F3)],
	}

	for action_name: String in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": actions[action_name],
		})

	var error := ProjectSettings.save()
	if error != OK:
		printerr("Failed to save project settings: %d" % error)
		quit(1)
		return
	print("Input map written: %d actions." % actions.size())
	quit(0)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	# Physical so WASD stays in the same place on AZERTY/QWERTZ keyboards.
	event.physical_keycode = keycode
	event.device = -1
	return event


func _mouse(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.device = -1
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.device = -1
	return event


func _axis(which: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = which
	event.axis_value = value
	event.device = -1
	return event
