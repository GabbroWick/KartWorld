extends Node
## Headless test for the on-screen touch controls.
##
## Run:  godot --headless res://tools/tests/test_touch_runner.tscn
##
## Forces the layer visible (no touchscreen headless), then feeds
## InputEventScreenTouch/Drag like a phone would: the stick must move the
## character and steer the kart, the buttons must jump / summon the kart /
## enter it, and a drag on the right half must turn the camera.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _touch: TouchControls
var _camera: ThirdPersonCamera


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = "user://test_touch_save.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_touch = _scene.get_node("TouchControls")
	_camera = _scene.get_node("CameraRig")
	await _steps(20)
	_player = GameManager.get_player(0) as CharacterController
	_check(not _touch.root.visible, "touch layer hidden without a touchscreen")
	_touch.force_visible = true
	_touch._ready()
	_check(_touch.root.visible and TouchControls.active, "force_visible shows the touch layer")
	var mouse_bound := false
	for ev in InputMap.action_get_events(InputActions.ATTACK):
		if ev is InputEventMouseButton:
			mouse_bound = true
	_check(not mouse_bound, "mouse bindings are stripped while touch controls are active")
	var lowest := 0.0
	for b in _touch.buttons.get_children():
		if b is Control and b.name != "Pause":
			lowest = maxf(lowest, (b as Control).get_global_rect().end.y)
	_check(lowest <= _viewport_size().y - 80.0, "buttons keep a margin from the bottom edge (%.0f of %.0f)" % [lowest, _viewport_size().y])
	await _steps(2)
	var hud: CanvasLayer = _scene.get_node("GameHUD")
	_check(hud.controls_label.text == "", "keyboard hints hidden while touch controls are active")

	await _test_stick_walk()
	await _test_look_drag()
	await _test_buttons()
	await _test_kart()
	_finish()


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## parse_input_event takes WINDOW coordinates (what a real screen sends);
## headless the window is 0x0 and the viewport stretched, so convert.
func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _touch_press(index: int, at: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(at)
	ev.pressed = true
	Input.parse_input_event(ev)


func _touch_release(index: int, at: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(at)
	ev.pressed = false
	Input.parse_input_event(ev)


func _touch_drag(index: int, from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _to_window(to)
	ev.relative = _to_window(to) - _to_window(from)
	Input.parse_input_event(ev)


func _test_stick_walk() -> void:
	var size := _viewport_size()
	var origin := Vector2(size.x * 0.2, size.y * 0.7)
	_camera.set_yaw(0.0)
	var start := _player.global_position
	_touch_press(0, origin)
	await _steps(1)
	var yaw_before := _camera.rotation.y
	_touch_drag(0, origin, origin + Vector2(0, -60))   # push forward, 2/3 stick
	await _steps(1)
	_check(_touch.stick_knob.visible, "stick appears under the finger")
	_check(not Input.is_action_pressed(InputActions.ATTACK), "a touch on the left half does not attack")
	_touch_drag(0, origin + Vector2(0, -60), origin + Vector2(80, -60))
	await _steps(3)
	_check(absf(wrapf(_camera.rotation.y - yaw_before, -PI, PI)) < 0.01, "dragging on the left half does not turn the camera")
	_touch_drag(0, origin + Vector2(80, -60), origin + Vector2(0, -60))
	await _steps(1)
	_check(Input.get_action_strength(InputActions.MOVE_FORWARD) > 0.5, "stick feeds move_forward (%.2f)" % Input.get_action_strength(InputActions.MOVE_FORWARD))
	await _steps(45)
	var moved := start.distance_to(_player.global_position)
	_check(moved > 1.5, "character walks with the virtual stick (%.1f m)" % moved)
	_touch_drag(0, origin + Vector2(0, -60), origin + Vector2(0, -90))  # full push = run
	await _steps(30)
	_check(Input.is_action_pressed(InputActions.RUN), "pushing the stick to the edge runs")
	_touch_release(0, origin + Vector2(0, -90))
	await _steps(2)
	_check(Input.get_action_strength(InputActions.MOVE_FORWARD) == 0.0 and not _touch.stick_knob.visible,
		"releasing the finger stops and hides the stick")
	await _steps(20)


func _test_look_drag() -> void:
	var size := _viewport_size()
	var origin := Vector2(size.x * 0.75, size.y * 0.5)
	var yaw_before := _camera.rotation.y
	_touch_press(1, origin)
	await _steps(1)
	_touch_drag(1, origin, origin + Vector2(120, 0))
	await _steps(3)
	_touch_release(1, origin + Vector2(120, 0))
	await _steps(2)
	var turned := wrapf(_camera.rotation.y - yaw_before, -PI, PI)
	_check(absf(turned) > 0.1, "dragging the right half turns the camera (%.2f rad)" % turned)


func _test_buttons() -> void:
	var jump := _touch.buttons.get_node("Jump") as Button
	var y0 := _player.global_position.y
	jump.button_down.emit()
	await _steps(1)
	_check(Input.is_action_pressed(InputActions.JUMP), "Jump button presses the jump action")
	await _steps(8)
	jump.button_up.emit()
	await _steps(6)
	_check(_player.global_position.y > y0 + 0.5, "character jumps from the button (+%.2f m)" % (_player.global_position.y - y0))
	await _steps(60)
	var dance := _touch.buttons.get_node("Dance") as Button
	dance.button_down.emit()
	await _steps(1)
	_check(Input.is_action_pressed(InputActions.EMOTE), "Dance button presses the emote action")
	dance.button_up.emit()
	await _steps(2)


func _test_kart() -> void:
	var kart_btn := _touch.buttons.get_node("Kart") as Button
	kart_btn.button_down.emit()
	await _steps(2)
	kart_btn.button_up.emit()
	await _steps(15)
	var kart := _player.driver.vehicle
	_check(_player.driver.is_vehicle_in_reach(), "Kart button summons the kart next to the player")
	var use := _touch.buttons.get_node("Use") as Button
	use.button_down.emit()
	await _steps(2)
	use.button_up.emit()
	await _steps(3)
	_check(_player.driver.is_driving, "Use button enters the kart")
	_check((_touch.buttons.get_node("Action") as Button).text == tr(&"TOUCH_TURBO"), "Action button relabels to Turbo at the wheel")
	# Face the open meadow (+Z, away from the house) before driving.
	kart.place(Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), kart.global_position))
	var size := _viewport_size()
	var origin := Vector2(size.x * 0.2, size.y * 0.7)
	var start := kart.global_position
	_touch_press(0, origin)
	await _steps(1)
	_touch_drag(0, origin, origin + Vector2(30, -90))   # forward + right
	await _steps(3)
	_check(Input.get_action_strength(InputActions.ACCELERATE) > 0.8, "stick feeds accelerate (%.2f) and steer (%.2f)" % [Input.get_action_strength(InputActions.ACCELERATE), Input.get_action_strength(InputActions.MOVE_RIGHT)])
	await _steps(90)
	_touch_release(0, origin + Vector2(30, -90))
	await _steps(2)
	_check(kart.global_position.distance_to(start) > 4.0, "stick drives the kart (%.1f m, speed %.1f)" % [kart.global_position.distance_to(start), kart.get_speed()])
	_check(Input.get_action_strength(InputActions.ACCELERATE) == 0.0, "throttle released with the finger")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	ProgressionManager.reset()
	get_tree().quit(1 if _failures.size() > 0 else 0)
