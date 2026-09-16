@tool
class_name FruitTree
extends StaticBody3D
## A tree with fruit on it: interact (E) to pick `fruit_count` fruit into
## the inventory; the fruit grows back after `regrow_time` seconds.
## Built from primitives (trunk, round crown, coloured fruit) so it reads
## as "fruit tree" next to the Kenney trees; scattered like any prop.

const GROUP := &"interactable"

@export_range(1, 6, 1) var fruit_count := 3
@export_range(5.0, 600.0, 1.0) var regrow_time := 90.0
@export var fruit_color := Color(0.95, 0.25, 0.2):
	set(value):
		fruit_color = value
		_apply()
@export var crown_color := Color(0.3, 0.62, 0.28):
	set(value):
		crown_color = value
		_apply()
@export_range(1.0, 6.0, 0.1) var height := 3.4:
	set(value):
		height = value
		_apply()

@onready var trunk: MeshInstance3D = $Trunk
@onready var crown: MeshInstance3D = $Crown
@onready var fruit: Node3D = $Fruit
@onready var collision: CollisionShape3D = $CollisionShape3D

var has_fruit := true
var _regrow_left := 0.0


func _ready() -> void:
	set_meta(&"scattered", true)
	_apply()
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
		Lod.register_deferred(self)


func _apply() -> void:
	if not is_node_ready():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = height * 0.5
	trunk_mesh.material = FlatMaterial.flat(Color(0.45, 0.3, 0.18))
	trunk.mesh = trunk_mesh
	trunk.position.y = height * 0.25
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = height * 0.42
	crown_mesh.height = height * 0.84
	crown_mesh.radial_segments = 12
	crown_mesh.rings = 6
	crown_mesh.material = FlatMaterial.flat(crown_color)
	crown.mesh = crown_mesh
	crown.position.y = height * 0.72
	for child in fruit.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 31.0 + position.z * 17.0)
	for i in fruit_count:
		var ball := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.32
		mesh.radial_segments = 8
		mesh.rings = 4
		mesh.material = FlatMaterial.flat(fruit_color)
		ball.mesh = mesh
		var a := rng.randf_range(0.0, TAU)
		var r := height * 0.38
		ball.position = Vector3(cos(a) * r, height * 0.72 + rng.randf_range(-0.2, 0.25) * height * 0.5, sin(a) * r)
		fruit.add_child(ball)
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = height * 0.5
	collision.shape = shape
	collision.position.y = height * 0.25


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or has_fruit:
		return
	_regrow_left -= delta
	if _regrow_left <= 0.0:
		has_fruit = true
		fruit.visible = true


func can_interact(_player: CharacterController) -> bool:
	return has_fruit


func get_prompt() -> String:
	return tr(&"PROMPT_PICK_FRUIT")


func get_interaction_position() -> Vector3:
	return global_position


func interact(_player: CharacterController) -> void:
	if not has_fruit:
		return
	has_fruit = false
	fruit.visible = false
	_regrow_left = regrow_time
	ProgressionManager.add_item(&"fruit", fruit_count)
	Sfx.play(&"star", -6.0)
	Burst.spawn(get_parent(), crown.global_position, fruit_color, 12, 3.0, 0.15)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"NOTICE_GOT_FRUIT") % fruit_count)
