class_name CharacterCombat
extends Node
## Melee attack for a character: a hitbox in front of the model that is live
## for a few frames, with damage and cooldown from the CharacterDefinition.
##
## Anything the hitbox overlaps that has a `take_damage(amount, source)`
## method gets hit once per swing. Ranged attacks will be a sibling component
## that spawns projectiles; this one never needs to know about them.

signal attacked
signal hit(target: Node)

var character: CharacterController
var definition: CharacterDefinition

## Placeholder claw arc; off when the model animates the attack itself.
var show_swipe := true
var is_attacking := false
var cooldown_left := 0.0
var _active_left := 0.0
var _hit_this_swing: Array[Node] = []

## The hitbox lives under the character's VisualRoot so it sits in front of
## wherever the model faces (an Area3D under a plain Node would be stuck at
## the world origin).
@export var hitbox_path: NodePath = ^"../VisualRoot/Hitbox"

var weapon_damage := 1.0
var weapon_ranged := false

@onready var hitbox: Area3D = get_node(hitbox_path)
@onready var swipe: MeshInstance3D = hitbox.get_node("Swipe")


func _ready() -> void:
	set_physics_process(false)
	hitbox.monitoring = false
	swipe.visible = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	swipe.mesh = _build_swipe_mesh()
	swipe.position = Vector3.ZERO


## A translucent claw arc in front of the character: a fan of quads between
## an inner and an outer radius, flat, built once.
func _build_swipe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 10
	var span := deg_to_rad(120.0)
	var inner := 0.35
	var outer := 0.85
	for i in segments:
		var a0 := -span * 0.5 + span * i / segments
		var a1 := -span * 0.5 + span * (i + 1) / segments
		var p0 := Vector3(sin(a0) * inner, 0.0, cos(a0) * inner)
		var p1 := Vector3(sin(a0) * outer, 0.0, cos(a0) * outer)
		var p2 := Vector3(sin(a1) * outer, 0.0, cos(a1) * outer)
		var p3 := Vector3(sin(a1) * inner, 0.0, cos(a1) * inner)
		for v in [p0, p1, p2, p0, p2, p3, p0, p2, p1, p0, p3, p2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.95, 0.6, 0.7)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func setup(owner_character: CharacterController, character_definition: CharacterDefinition) -> void:
	character = owner_character
	definition = character_definition
	if character.is_player_controlled and not ProgressionManager.changed.is_connected(_apply_weapon):
		ProgressionManager.changed.connect(_apply_weapon)
	_apply_weapon()


## The shop weapon in the hand (players only): scales damage and reach,
## or turns the swing into a boomerang throw.
func _apply_weapon() -> void:
	var stats := Weapons.stats(ProgressionManager.equipped_weapon if character.is_player_controlled else &"")
	weapon_damage = definition.melee_damage * float(stats["damage"])
	weapon_ranged = bool(stats["ranged"])
	var reach := definition.melee_range * float(stats["reach"])
	var shape := hitbox.get_node("Shape") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	if box:
		box = box.duplicate()
		box.size = Vector3(definition.melee_width, 1.2, reach)
		shape.shape = box
	hitbox.position = Vector3(0.0, definition.capsule_height * 0.55, -reach * 0.5 - 0.2)
	var visual := character.get_visual()
	if visual and visual.has_method(&"set_weapon_visual"):
		visual.call(&"set_weapon_visual", ProgressionManager.equipped_weapon if character.is_player_controlled else &"")


## Called by the character every physics tick.
func tick(delta: float, attack_requested: bool) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if is_attacking:
		_active_left -= delta
		_sweep_overlaps()
		# Arc sweeps out and fades over the active window.
		var progress := 1.0 - clampf(_active_left / definition.melee_active_time, 0.0, 1.0)
		swipe.scale = Vector3.ONE * lerpf(0.5, 1.6, progress)
		swipe.rotation.y = lerpf(0.8, -0.8, progress)
		if _active_left <= 0.0:
			_end_swing()
	elif attack_requested:
		try_attack()


func try_attack() -> bool:
	if is_attacking or cooldown_left > 0.0 or definition == null:
		return false
	if weapon_ranged:
		cooldown_left = definition.melee_cooldown * 1.5
		var boomerang := Boomerang.new()
		boomerang.damage = weapon_damage
		character.get_parent().add_child(boomerang)
		boomerang.launch(character, -character.visual_root.global_basis.z)
		boomerang.hit.connect(func(body: Node) -> void: hit.emit(body))
		attacked.emit()
		return true
	is_attacking = true
	_active_left = definition.melee_active_time
	cooldown_left = definition.melee_cooldown
	_hit_this_swing.clear()
	hitbox.monitoring = true
	swipe.visible = show_swipe
	attacked.emit()
	return true


func _end_swing() -> void:
	is_attacking = false
	hitbox.monitoring = false
	swipe.visible = false


## Bodies already inside the box when it switches on do not fire body_entered.
func _sweep_overlaps() -> void:
	for body in hitbox.get_overlapping_bodies():
		_try_hit(body)


func _on_hitbox_body_entered(body: Node3D) -> void:
	_try_hit(body)


func _try_hit(body: Node) -> void:
	if body == character or body in _hit_this_swing:
		return
	if not body.has_method(&"take_damage"):
		return
	_hit_this_swing.append(body)
	body.call(&"take_damage", weapon_damage, character)
	hit.emit(body)
