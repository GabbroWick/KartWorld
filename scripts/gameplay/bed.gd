@tool
class_name Bed
extends StaticBody3D
## The bed: interact to sleep. The screen fades, hearts refill and the
## DayCycle (if the world has one) jumps to the next morning.

signal slept

const GROUP := &"interactable"


func _ready() -> void:
	FlatMaterial.apply_fill(self)
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func can_interact(_player: CharacterController) -> bool:
	return true


func get_prompt() -> String:
	return tr(&"PROMPT_SLEEP")


func get_interaction_position() -> Vector3:
	return global_position


func interact(player: CharacterController) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"fade"):
		await hud.call(&"fade", 0.6)
	player.health.restore_full()
	var cycle := get_tree().get_first_node_in_group(DayCycle.GROUP) as DayCycle
	if cycle:
		cycle.set_morning()
	Sfx.play(&"checkpoint", -4.0)
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"NOTICE_SLEPT"))
	slept.emit()
