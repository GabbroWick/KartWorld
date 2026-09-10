class_name Checkpoint
extends Area3D
## Touch it and it becomes the player's respawn point for this level.
##
## Reusable in every level: it only talks to the character's spawn transform,
## which is what respawn() already uses. The ring on the ground turns green
## once activated.

signal activated(checkpoint: Checkpoint, by: CharacterController)

const GROUP := &"checkpoint"

@export var active_color := Color(0.3, 0.9, 0.4)
@export var inactive_color := Color(0.9, 0.3, 0.3)

@onready var respawn_point: Marker3D = $RespawnPoint
@onready var flag: Node3D = $Flag
@onready var ring: MeshInstance3D = $Ring

var is_active := false
var ring_color := Color.WHITE


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	# Own copy of the ring material so checkpoints do not share state.
	var material := (ring.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	ring.material_override = material
	_set_ring_color(inactive_color)
	FlatMaterial.apply_fill(flag)


func _set_ring_color(color: Color) -> void:
	ring_color = color
	var material := ring.material_override as StandardMaterial3D
	material.albedo_color = color
	material.emission = color


func _on_body_entered(body: Node3D) -> void:
	var player := _player_from(body)
	if player == null or is_active:
		return
	activate(player)


func activate(player: CharacterController) -> void:
	# Only one checkpoint is "the" checkpoint at a time.
	for other in get_tree().get_nodes_in_group(GROUP):
		if other != self and other is Checkpoint:
			other.deactivate()
	is_active = true
	_set_ring_color(active_color)
	player.set_spawn_transform(respawn_point.global_transform, false)
	activated.emit(self, player)


func deactivate() -> void:
	is_active = false
	_set_ring_color(inactive_color)


func _player_from(body: Node3D) -> CharacterController:
	if body is CharacterController and body.is_player_controlled:
		return body
	if body is VehicleController and body.driver is CharacterController:
		return body.driver
	return null
