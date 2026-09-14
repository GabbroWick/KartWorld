class_name NpcBehaviour
extends Node
## Makes a non-player character alive: wanders near its start point, stops
## and turns to face a nearby player, and can be talked to with `interact`.
##
## Drives the same CharacterController as the player through
## CharacterInput.world_direction, so NPCs walk, climb steps and respect
## collisions exactly like the leopard does. Dialogue lines are data on the
## node; a Label3D speech bubble shows them.

signal spoke(line: String)

@export_range(0.0, 30.0, 0.5) var wander_radius := 4.0
@export var idle_time := Vector2(1.0, 3.0)
## Stops wandering and looks at a player closer than this.
@export_range(0.0, 20.0, 0.5) var notice_radius := 3.5
## What the NPC says, one line per interaction, cycling.
@export var dialogue_lines: PackedStringArray = PackedStringArray()
@export var bubble_time := 3.5

var home := Vector3.ZERO
var _character: CharacterController
var _goal := Vector3.ZERO
var _walking := false
var _idle_left := 1.0
var _rng := RandomNumberGenerator.new()
var _line_index := 0
var _bubble: Label3D
var _bubble_left := 0.0
var _stuck_time := 0.0
var _terrain: IslandTerrain
var _parked := false


func _ready() -> void:
	_character = get_parent() as CharacterController
	if _character == null or _character.is_player_controlled:
		set_physics_process(false)
		return
	add_to_group(InteractionComponent.GROUP)
	_rng.seed = hash(_character.name)
	# Children get _ready before their parent: the character's components are
	# not wired yet, so finish the setup one frame later.
	set_physics_process(false)
	call_deferred(&"_late_setup")


func _late_setup() -> void:
	home = _character.global_position
	_character.input.uses_world_direction = true
	_terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_tick_bubble(delta)
	# Streaming terrain: no ground under us right now → stand still on the
	# analytic surface until the tile is back (else we would fall through).
	if _terrain and _terrain.streaming:
		var p := _character.global_position
		if not _terrain.is_built_at(p.x, p.z):
			_character.velocity = Vector3.ZERO
			_character.input.world_direction = Vector3.ZERO
			_character.global_position.y = maxf(p.y, _terrain.sample_height(p.x, p.z) + 0.05)
			_character.set_physics_process(false)
			_parked = true
			return
		elif _parked:
			_parked = false
			_character.global_position.y = _terrain.sample_height(p.x, p.z) + 0.3
			_character.set_physics_process(true)
	var player := _nearest_player()
	if player and player.global_position.distance_to(_character.global_position) < notice_radius:
		_walking = false
		_idle_left = maxf(_idle_left, 0.5)
		_character.input.world_direction = Vector3.ZERO
		_face(player.global_position, delta)
		return
	if _walking:
		var to_goal := _goal - _character.global_position
		to_goal.y = 0.0
		# Pressed against something = as good as arrived.
		_stuck_time = _stuck_time + delta if Vector2(_character.velocity.x, _character.velocity.z).length() < 0.2 else 0.0
		if to_goal.length() < 0.4 or _character.is_on_wall() or _stuck_time > 0.4:
			_walking = false
			_stuck_time = 0.0
			_idle_left = _rng.randf_range(idle_time.x, idle_time.y)
			_character.input.world_direction = Vector3.ZERO
		else:
			_character.input.world_direction = to_goal.normalized() * 0.55  # stroll, don't run
	else:
		_idle_left -= delta
		if _idle_left <= 0.0 and wander_radius > 0.0:
			if _pick_goal():
				_walking = true
			else:
				_idle_left = 0.5


## A wander goal with a clear straight line from here; false if none found.
func _pick_goal() -> bool:
	var space := _character.get_world_3d().direct_space_state
	var eye := _character.global_position + Vector3.UP * 0.6
	for attempt in 6:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(0.3, 1.0) * wander_radius
		var candidate := home + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var query := PhysicsRayQueryParameters3D.create(eye, Vector3(candidate.x, eye.y, candidate.z), 1)
		if space.intersect_ray(query).is_empty():
			_goal = candidate
			return true
	return false


## Interactable contract.
func can_interact(_player: CharacterController) -> bool:
	return not dialogue_lines.is_empty()


func get_prompt() -> String:
	return tr(&"PROMPT_TALK") % tr(_character.definition.display_name)


func get_interaction_position() -> Vector3:
	return _character.global_position


func interact(_player: CharacterController) -> void:
	if dialogue_lines.is_empty():
		return
	var line := dialogue_lines[_line_index % dialogue_lines.size()]
	_line_index += 1
	say(tr(line))


func say(line: String) -> void:
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.font_size = 48
		_bubble.outline_size = 12
		_bubble.pixel_size = 0.006
		_bubble.position = Vector3(0.0, _character.definition.capsule_height + 0.8, 0.0)
		_bubble.no_depth_test = true
		_character.add_child(_bubble)
	_bubble.text = line
	_bubble.visible = true
	_bubble_left = bubble_time
	spoke.emit(line)


func _tick_bubble(delta: float) -> void:
	if _bubble_left <= 0.0:
		return
	_bubble_left -= delta
	if _bubble_left <= 0.0 and _bubble:
		_bubble.visible = false


func _face(point: Vector3, delta: float) -> void:
	var dir := point - _character.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	_character.visual_root.rotation.y = lerp_angle(_character.visual_root.rotation.y, target_yaw, 8.0 * delta)


func _nearest_player() -> CharacterController:
	var best: CharacterController = null
	var best_distance := INF
	for node in GameManager.players:
		var player := node as CharacterController
		if player == null or player.driver.is_driving:
			continue
		var d := player.global_position.distance_to(_character.global_position)
		if d < best_distance:
			best_distance = d
			best = player
	return best
