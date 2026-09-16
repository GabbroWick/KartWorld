class_name Star
extends Collectible
## The main reward collectible. Spins and bobs so it reads as "pick me up".

@export var spin_speed := 2.0
@export var bob_height := 0.15
@export var bob_speed := 2.5

@onready var visual: Node3D = $Visual

var _base_y := 0.0
var _time := 0.0


func _ready() -> void:
	super()
	kind = &"star"
	add_to_group(&"star")
	_base_y = visual.position.y
	FlatMaterial.apply_fill(visual)
	Lod.register_deferred(self)


func _on_collected(_by: CharacterController) -> void:
	Burst.spawn(get_parent(), visual.global_position, Color(1.0, 0.85, 0.25), 18, 6.0, 0.22)
	Sfx.play(&"star")
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	visual.rotate_y(spin_speed * delta)
	visual.position.y = _base_y + sin(_time * bob_speed) * bob_height
