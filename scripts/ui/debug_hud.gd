extends CanvasLayer
## Developer overlay (F3): control list + live movement state. Hidden by
## default; the player-facing HUD is scenes/ui/game_hud.tscn.

const CONTROLS_FOOT := "WASD move   Shift run   Space jump (x2)   J/click attack   K summon kart   E enter kart   Mouse look   Esc cursor   F3 hide"
const CONTROLS_KART := "W/S gas/brake   A/D steer   Shift turbo   Space jump   E leave kart   Mouse look   Esc cursor   F3 hide"

@onready var controls_label: Label = $Root/Controls
@onready var state_label: Label = $Root/State

var _player: CharacterController


func _ready() -> void:
	controls_label.text = CONTROLS_FOOT


func bind_player(player: CharacterController) -> void:
	_player = player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_TOGGLE_HUD):
		visible = not visible


func _process(_delta: float) -> void:
	if not is_instance_valid(_player) or not visible:
		return
	if _player.driver.is_driving:
		var kart := _player.driver.vehicle
		controls_label.text = CONTROLS_KART
		var turbo_state := "ready"
		if kart.turbo:
			if kart.turbo.is_active:
				turbo_state = "ON %.1fs" % kart.turbo.time_left
			elif kart.turbo.cooldown_left > 0.0:
				turbo_state = "cooldown %.1fs" % kart.turbo.cooldown_left
		state_label.text = "KART %s | speed %5.1f | turbo %s | fps %d" % [
			"grounded" if kart.is_on_floor() else "airborne",
			kart.get_speed(),
			turbo_state,
			Engine.get_frames_per_second(),
		]
		return
	controls_label.text = CONTROLS_FOOT
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
	var state := "grounded" if _player.is_on_floor() else "airborne"
	state_label.text = "%s | speed %5.1f | air jumps %d/%d | fps %d" % [
		state,
		horizontal,
		_player.motor.air_jumps_used,
		_player.motor.get_max_air_jumps(),
		Engine.get_frames_per_second(),
	]
