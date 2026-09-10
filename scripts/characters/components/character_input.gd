class_name CharacterInput
extends Node
## Turns device input into an intent snapshot for one character.
##
## Everything downstream (controller, motor) reads this struct-like node and
## never touches `Input` directly. That is what lets us add touch controls,
## split-screen devices, replays or AI-driven characters later without changing
## a single line of movement code.

## Set false for AI/remote characters: their intent gets written directly.
@export var reads_local_device := true
## Reserved for local co-op: -1 means "any device".
@export var device_id := -1

var move_axis := Vector2.ZERO  ## x = strafe, y = -1 forward / +1 backward
var run_held := false
var jump_pressed := false
var jump_released := false
var jump_held := false
var interact_pressed := false


func _ready() -> void:
	# The controller polls us explicitly so the snapshot is always fresh for the
	# current physics tick, independent of node processing order.
	set_process(false)
	set_physics_process(false)


func poll() -> void:
	if not reads_local_device:
		return
	move_axis = Input.get_vector(
		InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
		InputActions.MOVE_FORWARD, InputActions.MOVE_BACKWARD
	)
	run_held = Input.is_action_pressed(InputActions.RUN)
	jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	jump_released = Input.is_action_just_released(InputActions.JUMP)
	jump_held = Input.is_action_pressed(InputActions.JUMP)
	interact_pressed = Input.is_action_just_pressed(InputActions.INTERACT)


func clear() -> void:
	move_axis = Vector2.ZERO
	run_held = false
	jump_pressed = false
	jump_released = false
	jump_held = false
	interact_pressed = false
