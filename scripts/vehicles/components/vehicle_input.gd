class_name VehicleInput
extends Node
## Device input -> driving intent for one vehicle. Same role as CharacterInput.
##
## Only polls the device while a local player is at the wheel; an AI or remote
## driver writes the fields directly.

var reads_local_device := false

var throttle := 0.0  ## -1 brake/reverse .. +1 accelerate
var steer := 0.0     ## -1 left .. +1 right
var turbo_pressed := false
var jump_pressed := false
var interact_pressed := false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func poll() -> void:
	if not reads_local_device:
		return
	throttle = Input.get_action_strength(InputActions.ACCELERATE) \
		- Input.get_action_strength(InputActions.BRAKE)
	steer = Input.get_axis(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT)
	turbo_pressed = Input.is_action_just_pressed(InputActions.TURBO)
	jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	interact_pressed = Input.is_action_just_pressed(InputActions.INTERACT)


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	turbo_pressed = false
	jump_pressed = false
	interact_pressed = false
