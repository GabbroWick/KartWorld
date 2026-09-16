class_name BossSlime
extends Enemy
## The Slime King: a giant slime that chases the player and, every
## `slam_period` seconds, leaps at them. Landing sends a shockwave (one
## heart to players within `slam_radius`, knocked back) and spawns baby
## slimes (`minion_definition`, up to `max_minions` alive). Below half
## health it gets angry: faster and slams more often. Group `boss`; the
## HUD shows its health bar while a player is near.

signal slammed(at: Vector3)

const BOSS_GROUP := &"boss"

@export_range(1.0, 10.0, 0.1) var slam_period := 3.5
@export_range(1.0, 10.0, 0.1) var enraged_slam_period := 2.2
## Slams only when the player is closer than this.
@export_range(2.0, 40.0, 0.5) var slam_range := 16.0
@export_range(1.0, 12.0, 0.1) var slam_radius := 4.5
@export_range(2.0, 20.0, 0.5) var jump_speed := 11.0
@export var minion_scene: PackedScene
@export var minion_definition: EnemyDefinition
@export_range(0, 6, 1) var minions_per_slam := 2
@export_range(0, 12, 1) var max_minions := 4

var slams := 0
var enraged := false
var _slam_left := 2.0
var _in_air := false
var _leap_planar := Vector3.ZERO
var _minions: Array[Node] = []


func _ready() -> void:
	super()
	add_to_group(BOSS_GROUP)
	health.health_changed.connect(_on_health_changed)
	_add_crown()


## A golden crown on top: kings wear crowns.
func _add_crown() -> void:
	var crown := Node3D.new()
	crown.name = "Crown"
	var gold := FlatMaterial.flat(Color(1.0, 0.82, 0.2))
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.55
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.3
	ring_mesh.material = gold
	ring.mesh = ring_mesh
	crown.add_child(ring)
	for i in 5:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.12
		cone.height = 0.35
		cone.material = gold
		spike.mesh = cone
		var angle := TAU * i / 5.0
		spike.position = Vector3(cos(angle) * 0.45, 0.3, sin(angle) * 0.45)
		crown.add_child(spike)
	crown.position = Vector3(0.0, definition.body_height * 0.95, 0.0)
	visual_root.add_child(crown)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	super(delta)
	if _in_air:
		if is_on_floor():
			_in_air = false
			_slam()
		else:
			# Keep the leap's planar speed (the base motor would brake it).
			velocity.x = _leap_planar.x
			velocity.z = _leap_planar.z


func _think(delta: float) -> void:
	super(delta)
	if _in_air:
		return
	_slam_left -= delta
	if _slam_left <= 0.0 and target and is_on_floor() 			and global_position.distance_to(target.global_position) < slam_range:
		_slam_left = enraged_slam_period if enraged else slam_period
		_leap()


## Jumps toward the player: the flight time is 2 * jump_speed / g, the
## planar speed is chosen to land on them.
func _leap() -> void:
	_in_air = true
	var dir := target.global_position - global_position
	dir.y = 0.0
	var distance := dir.length()
	dir = dir.normalized() if distance > 0.01 else Vector3.ZERO
	var flight := 2.0 * jump_speed / _gravity
	var planar := clampf(distance / flight, 2.0, definition.move_speed * 4.0)
	_leap_planar = dir * planar
	velocity = _leap_planar + Vector3.UP * jump_speed
	var tween := create_tween()
	tween.tween_property(visual_root, "scale", Vector3(0.8, 1.35, 0.8), 0.15)
	tween.tween_property(visual_root, "scale", Vector3.ONE, 0.3)
	Sfx.play(&"jump", -4.0, 0.6)


func _slam() -> void:
	slams += 1
	var at := global_position
	var tween := create_tween()
	tween.tween_property(visual_root, "scale", Vector3(1.4, 0.6, 1.4), 0.1)
	tween.tween_property(visual_root, "scale", Vector3.ONE, 0.35)
	Burst.spawn(get_parent(), at + Vector3.UP * 0.3, Color(0.55, 0.9, 0.45), 30, 9.0, 0.35)
	Sfx.play(&"land", 0.0, 0.5)
	Sfx.play(&"hit", -2.0, 0.6)
	for player in GameManager.players:
		var character := player as CharacterController
		if character == null:
			continue
		var d := character.global_position.distance_to(at)
		if d < slam_radius and character.global_position.y < at.y + 2.5:
			character.take_damage(definition.contact_damage, self)
	_spawn_minions()
	slammed.emit(at)


func _spawn_minions() -> void:
	_minions = _minions.filter(func(m: Node) -> bool: return is_instance_valid(m))
	if minion_scene == null or minion_definition == null:
		return
	for i in minions_per_slam:
		if _minions.size() >= max_minions:
			return
		var minion := minion_scene.instantiate() as Enemy
		minion.name = "Baby%d_%d" % [slams, i]
		minion.definition = minion_definition
		var angle := _rng.randf_range(0.0, TAU)
		var at := global_position + Vector3(cos(angle), 0.2, sin(angle)) * (definition.body_radius + 1.0)
		minion.position = get_parent().to_local(at) if get_parent() is Node3D else at
		get_parent().add_child(minion)
		minion.velocity = Vector3(cos(angle), 0.0, sin(angle)) * 4.0 + Vector3.UP * 5.0
		_minions.append(minion)


func _on_health_changed(current: float, maximum: float) -> void:
	if not enraged and current > 0.0 and current <= maximum * 0.5:
		enraged = true
		definition = definition.duplicate()
		definition.move_speed *= 1.4
		_slam_left = minf(_slam_left, 0.8)
		Sfx.play(&"hurt", 0.0, 0.5)


func _on_died() -> void:
	for minion in _minions:
		if is_instance_valid(minion) and not (minion as Enemy)._dying:
			(minion as Enemy).take_damage(100.0, self)
	_minions.clear()
	Burst.spawn(get_parent(), global_position + Vector3.UP * definition.body_height * 0.5, Color(1.0, 0.9, 0.3), 60, 12.0, 0.5)
	Sfx.play(&"fanfare")
	super()
