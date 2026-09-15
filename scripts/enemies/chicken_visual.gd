extends Node3D
## Procedural chicken: white body, red comb and wattle, yellow beak and
## legs. `animate(delta, speed_ratio, grounded)` bobs the head while it
## walks and pecks when idle. Faces -Z like every character visual.

@onready var body: MeshInstance3D = $Body
@onready var head: Node3D = $Head
@onready var legs: Node3D = $Legs

var _time := 0.0


func _ready() -> void:
	FlatMaterial.apply_fill(self)


func animate(delta: float, speed_ratio: float, _grounded: bool) -> void:
	_time += delta
	if speed_ratio > 0.05:
		head.position.z = -0.32 + sin(_time * 14.0) * 0.06
		head.position.y = 0.55 + absf(sin(_time * 14.0)) * 0.04
		legs.rotation.x = sin(_time * 14.0) * 0.5
		body.rotation.z = sin(_time * 7.0) * 0.08
	else:
		var peck := maxf(sin(_time * 2.2), 0.0)
		head.position.z = -0.32 - peck * 0.12
		head.position.y = 0.55 - peck * 0.22
		head.rotation.x = -peck * 0.9
		legs.rotation.x = 0.0
		body.rotation.z = 0.0
