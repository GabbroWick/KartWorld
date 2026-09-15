@tool
class_name Kitchen
extends StaticBody3D
## The house kitchen: a counter with a stove. Interact to cook what you
## carry: fruit + meat = stew (full heal + "sazio" boost), fruit alone =
## fruit salad (2 hearts). Cooking eats the ingredients on the spot.

const GROUP := &"interactable"

@export var counter_color := Color(0.8, 0.72, 0.6)

@onready var counter: MeshInstance3D = $Counter
@onready var stove: MeshInstance3D = $Stove
@onready var smoke: CPUParticles3D = $Smoke


func _ready() -> void:
	FlatMaterial.apply_fill(self)
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
		smoke.emitting = false


func can_interact(_player: CharacterController) -> bool:
	return true


func get_prompt() -> String:
	var fruit := ProgressionManager.count_item(&"fruit")
	var meat := ProgressionManager.count_item(&"meat")
	if fruit > 0 and meat > 0:
		return tr(&"PROMPT_COOK_STEW")
	if fruit > 0:
		return tr(&"PROMPT_COOK_SALAD")
	return tr(&"PROMPT_KITCHEN_EMPTY")


func get_interaction_position() -> Vector3:
	return global_position


func interact(player: CharacterController) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if ProgressionManager.take_item(&"meat", 1) and ProgressionManager.take_item(&"fruit", 1):
		player.health.restore_full()
		player.motor.set_well_fed(60.0)
		Sfx.play(&"checkpoint")
		smoke.restart()
		smoke.emitting = true
		if hud:
			hud.call(&"show_notice", tr(&"NOTICE_ATE_STEW"))
	elif ProgressionManager.take_item(&"fruit", 1):
		player.health.heal(2.0)
		Sfx.play(&"star", -4.0)
		if hud:
			hud.call(&"show_notice", tr(&"NOTICE_ATE_SALAD"))
	else:
		Sfx.play(&"ui", -6.0)
		if hud:
			hud.call(&"show_notice", tr(&"NOTICE_KITCHEN_EMPTY"))
