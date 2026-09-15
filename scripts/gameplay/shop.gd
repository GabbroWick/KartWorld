@tool
class_name Shop
extends StaticBody3D
## The island shop: a stall with an awning and a sign. Interact to open
## the ShopMenu (weapons for stars). The menu lives in the HUD layer.

const GROUP := &"interactable"

@onready var sign_label: Label3D = $Sign


func _ready() -> void:
	FlatMaterial.apply_fill(self)
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
		add_to_group(&"map_shop")
		sign_label.text = tr(&"SHOP_SIGN")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if camera and sign_label:
		var to_camera := camera.global_position - sign_label.global_position
		to_camera.y = 0.0
		if to_camera.length_squared() > 0.001:
			sign_label.global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP)


func can_interact(_player: CharacterController) -> bool:
	return true


func get_prompt() -> String:
	return tr(&"PROMPT_SHOP")


func get_interaction_position() -> Vector3:
	return global_position


func interact(_player: CharacterController) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"open_shop"):
		hud.call(&"open_shop")
