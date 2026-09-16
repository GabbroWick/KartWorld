@tool
class_name Vine
extends Spring
## A jungle liana: grab it (walk into it) and it swings you up and
## forward (`forward_boost` m/s along the vine's -Z) over the gap.
## Looks like a rope hanging from above with a leafy end.

@export_range(0.0, 30.0, 0.5) var forward_boost := 12.0


func _apply() -> void:
	if not is_node_ready():
		return
	var rope := CylinderMesh.new()
	rope.top_radius = 0.05
	rope.bottom_radius = 0.05
	rope.height = 7.0
	rope.material = FlatMaterial.flat(Color(0.35, 0.28, 0.15))
	pad.mesh = rope
	pad.position.y = 4.2
	var leaf := SphereMesh.new()
	leaf.radius = 0.45
	leaf.height = 0.6
	leaf.material = FlatMaterial.flat(Color(0.3, 0.65, 0.3))
	base.mesh = leaf
	base.position.y = 1.0
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.4
	shape.shape = cyl
	shape.position.y = 1.2


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_squash = maxf(_squash - delta * 3.0, 0.0)
	# The rope sways after a grab.
	pad.rotation.x = sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 0.25 * _squash
	base.rotation.x = pad.rotation.x


func _on_body_entered(body: Node3D) -> void:
	var motor: Node = body.get(&"motor") if body else null
	if motor == null or not motor.has_method(&"launch"):
		return
	var gravity: float = motor.call(&"get_gravity_strength")
	motor.call(&"launch", sqrt(2.0 * gravity * height), -global_basis.z * forward_boost)
	_squash = 1.0
	Sfx.play(&"jump", 2.0)
