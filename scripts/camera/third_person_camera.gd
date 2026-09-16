class_name ThirdPersonCamera
extends Node3D
## Third-person orbit camera with collision avoidance (SpringArm3D).
##
## Fully independent from the character: it only needs a Node3D to follow, and
## the character only needs the camera's basis to know where "forward" is.
## Mouse look is handled here — the one place in the project that is allowed to
## care about a physical device, because that IS the camera's job.

@export var target: Node3D
## Vertical offset of the orbit pivot, roughly the character's head height.
@export var target_height := 1.15
@export_range(1.0, 20.0, 0.1) var distance := 5.5
## Higher = snappier follow. Frame-rate independent.
@export_range(1.0, 40.0, 0.5) var follow_speed := 14.0

@export_group("Look")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0024
## Radians per second for keyboard / right stick camera actions.
@export_range(0.5, 8.0, 0.1) var stick_sensitivity := 2.8
@export var invert_y := false
## Settings menu multiplier on every look input.
var sensitivity_scale := 1.0
@export var min_pitch_degrees := -65.0
@export var max_pitch_degrees := 30.0

@export_group("Auto align")
## When on, the camera swings back behind the target's heading after the
## player stops looking around. Used at the wheel, off on foot.
@export var auto_align := false
## Seconds without look input before auto align kicks in.
@export_range(0.0, 5.0, 0.1) var auto_align_delay := 0.8
## Higher = swings behind faster. Frame-rate independent.
@export_range(0.5, 20.0, 0.5) var auto_align_speed := 3.0

## Seconds of mouse motion ignored after the cursor gets captured: the OS warp
## to the window centre arrives as one huge motion event and would yank the view.
const CAPTURE_SETTLE_TIME := 0.15
## Largest per-event mouse delta accepted, in pixels. Bigger = a warp, not a hand.
const MAX_MOUSE_DELTA := 300.0

@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D
@onready var camera: Camera3D = $PitchPivot/SpringArm3D/Camera3D

var _yaw := 0.0
var _pitch := deg_to_rad(-12.0)
var _mouse_delta := Vector2.ZERO
var _mouse_blocked_until := 0.0
var _last_look_time := -1000.0


func _ready() -> void:
	# Run after the character has moved this tick, otherwise the camera lags.
	process_physics_priority = 100
	spring_arm.spring_length = distance
	_yaw = rotation.y
	if is_instance_valid(target):
		global_position = _desired_position()
	add_to_group(&"camera_rig")
	GameManager.mouse_capture_changed.connect(_on_mouse_capture_changed)
	_on_mouse_capture_changed(GameManager.is_mouse_captured())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and GameManager.is_mouse_captured():
		if _now() < _mouse_blocked_until or event.relative.length() > MAX_MOUSE_DELTA:
			return
		# Touch screens: only the right-half drag turns the camera
		# (TouchControls.add_look_delta), never a touch-emulated mouse.
		if TouchControls.active:
			return
		_mouse_delta += event.relative


## Touch drag (TouchControls): pixels of finger motion, same units as the mouse.
func add_look_delta(pixels: Vector2) -> void:
	_mouse_delta += pixels


func _on_mouse_capture_changed(captured: bool) -> void:
	_mouse_delta = Vector2.ZERO
	if captured:
		_mouse_blocked_until = _now() + CAPTURE_SETTLE_TIME


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	_update_rotation(delta)
	_update_position(delta)


func _update_rotation(delta: float) -> void:
	var look := Vector2.ZERO
	look += _mouse_delta * mouse_sensitivity
	_mouse_delta = Vector2.ZERO
	look += Input.get_vector(
		InputActions.CAMERA_LEFT, InputActions.CAMERA_RIGHT,
		InputActions.CAMERA_UP, InputActions.CAMERA_DOWN
	) * stick_sensitivity * delta
	look *= sensitivity_scale

	if look.length_squared() > 0.0:
		_last_look_time = _now()
	_yaw -= look.x
	_pitch -= look.y * (-1.0 if invert_y else 1.0)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

	if auto_align and is_instance_valid(target) and target.has_method(&"get_heading_yaw") 			and _now() - _last_look_time >= auto_align_delay:
		var heading: float = target.call(&"get_heading_yaw")
		_yaw = lerp_angle(_yaw, heading, 1.0 - exp(-auto_align_speed * delta))

	rotation.y = _yaw
	pitch_pivot.rotation.x = _pitch


func _update_position(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_desired_position(), weight)


func _desired_position() -> Vector3:
	return target.global_position + Vector3.UP * target_height


## Points the camera at a given heading. Useful to snap the view behind the
## character after a teleport / level load.
func set_yaw(radians: float) -> void:
	_yaw = radians
	rotation.y = _yaw


func get_yaw() -> float:
	return _yaw


func set_target(new_target: Node3D, snap: bool = true) -> void:
	target = new_target
	_last_look_time = _now()
	if snap and is_instance_valid(target):
		global_position = _desired_position()


## Orbit distance and pivot height, so vehicles can be framed wider than a
## character without a second camera.
func set_framing(new_distance: float, new_target_height: float) -> void:
	distance = new_distance
	target_height = new_target_height
	spring_arm.spring_length = distance
