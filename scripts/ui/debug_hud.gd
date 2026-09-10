extends CanvasLayer
## Minimal on-screen helper for the prototype: control list + live movement
## state. Not the real game UI (health / stars / objectives come in a later
## phase) — it exists so the prototype can be tested at a glance.

const CONTROLS := "WASD move   Shift run   Space jump (x2)   Mouse look   Esc free cursor   F3 hide"

@onready var controls_label: Label = $Root/Controls
@onready var state_label: Label = $Root/State

var _player: CharacterController


func _ready() -> void:
	controls_label.text = CONTROLS


func bind_player(player: CharacterController) -> void:
	_player = player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_TOGGLE_HUD):
		visible = not visible


func _process(_delta: float) -> void:
	if not is_instance_valid(_player) or not visible:
		return
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
	var state := "grounded" if _player.is_on_floor() else "airborne"
	state_label.text = "%s | speed %5.1f | air jumps %d/%d | fps %d" % [
		state,
		horizontal,
		_player.motor.air_jumps_used,
		_player.definition.max_air_jumps,
		Engine.get_frames_per_second(),
	]
