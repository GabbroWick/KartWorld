class_name RaceLine
extends Area3D
## A start arch ("GARA") on a road ring. Stop the kart under it and press
## `interact` to race: a 3-2-1 countdown, `opponents` NPC karts on the
## grid ahead, one lap of the ring through `gate_count` checkpoints in
## order, then the separate finish arch ("TRAGUARDO") `finish_offset`
## metres from the start (negative = before it: the race ends before the
## village comes back). While racing: wings are locked, the other NPC
## karts leave the island, leaving the road for more than `offroad_time`
## seconds puts the kart back at the last checkpoint, getting out of the
## kart gives up. Rivals drive at full speed and use their turbo on
## straights. Places pay stars once each (1st 5, 2nd 3, 3rd 1), saved as
## collected ids `race_<name>_<place>`. Position along the ring comes from
## IslandTerrain.road_progress.
##
## Placed on the terrain's road ring `road_index` at the point nearest to
## this node (so it can be dropped roughly in the scene).

signal race_started
signal race_finished(place: int, seconds: float)

const GROUP := &"race_line"
const REWARDS := [5, 3, 1]
const COUNTDOWN := 3.0
const OFFROAD_DISTANCE := 18.0
const ON_ROAD_DISTANCE := 10.0

@export var road_index := 1
@export_range(1, 6, 1) var opponents := 3
@export var vehicle_scene: PackedScene
@export var vehicle_definition: VehicleDefinition
@export var opponent_definitions: Array[CharacterDefinition] = []
## Rival cruise speed as a fraction of the kart's top speed (turbo on top).
@export_range(0.5, 1.1, 0.05) var opponent_speed := 1.0
@export var race_name: StringName = &"island"
@export_range(2, 12, 1) var gate_count := 6
## Metres from the start arch to the finish arch along the ring; negative
## = before the start (the race ends before reaching the village again).
@export_range(-600.0, 600.0, 5.0) var finish_offset := -110.0
@export_range(1.0, 10.0, 0.5) var offroad_time := 3.0

var is_racing := false
var is_counting := false
var elapsed := 0.0
var countdown_left := 0.0
var place := 1
var lap_progress := 0.0   # 0..1 for the player
var next_gate := 0        # player's next checkpoint (gate_count = all passed)
var _terrain: IslandTerrain
var _length := 0.0
var _start_distance := 0.0
var _gate_distances: PackedFloat32Array = PackedFloat32Array()   # relative to the start
var _finish_progress := 0.0   # finish arch, metres from the start along the ring
var _racers: Array[Dictionary] = []   # {kart, last, gate, laps, finished, handicap}
var _player_kart: VehicleController
var _player_last := 0.0
var _player_laps := 0
var _offroad_left := 0.0
var _off_kart_left := 0.0
var _hidden_karts: Array[Node] = []
var _gates: Array[Node3D] = []
var _finish: Node3D
var _mat_pole: Material
var _mat_banner: Material

@onready var banner: Label3D = $Banner


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"map_race")
	add_to_group(&"interactable")
	collision_layer = 8
	collision_mask = 16   # vehicles
	process_mode = Node.PROCESS_MODE_ALWAYS   # the countdown runs while the world is frozen
	banner.text = tr(&"RACE_BANNER")
	_mat_pole = ($PoleL as MeshInstance3D).mesh.surface_get_material(0)
	_mat_banner = ($Top as MeshInstance3D).mesh.surface_get_material(0)
	call_deferred(&"_snap_to_road")


func _snap_to_road() -> void:
	_terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if _terrain == null:
		return
	if not _terrain.is_node_ready():
		await _terrain.ready
	_length = _terrain.road_length_of(road_index)
	_start_distance = _terrain.road_progress(road_index, global_position)
	global_transform = _terrain.road_pose(road_index, _start_distance)
	global_position.y += 0.05
	_build_course()


## Finish arch and checkpoint gates along the ring (in the parent, so
## they never move with this node).
func _build_course() -> void:
	var parent := get_parent()
	_finish = Node3D.new()
	_finish.name = "RaceFinish"
	parent.add_child(_finish)
	_finish_progress = fposmod(finish_offset, _length)
	_finish.global_transform = _terrain.road_pose(road_index, _start_distance + _finish_progress)
	_finish.global_position.y += 0.05
	_add_arch(_finish, tr(&"RACE_FINISH"), true)
	_finish.set_meta(&"map_label", &"RACE_FINISH")
	_finish.add_to_group(&"map_race")
	_gate_distances.clear()
	for k in gate_count:
		var d := (k + 1) * _length / (gate_count + 1)
		_gate_distances.append(d)
		var gate := Node3D.new()
		gate.name = "RaceGate%d" % k
		parent.add_child(gate)
		gate.global_transform = _terrain.road_pose(road_index, _start_distance + d)
		for side in [-1.0, 1.0]:
			var pole := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.1
			mesh.bottom_radius = 0.1
			mesh.height = 3.0
			mesh.material = _mat_pole
			pole.mesh = mesh
			pole.position = Vector3(side * 4.8, 1.5, 0.0)
			gate.add_child(pole)
			var flag := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.2, 0.7, 0.08)
			box.material = FlatMaterial.flat(Color(0.3, 0.7, 1.0))
			flag.mesh = box
			flag.position = Vector3(side * 4.2, 2.6, 0.0)
			gate.add_child(flag)
		gate.visible = false
		_gates.append(gate)


func _add_arch(root: Node3D, text: String, checkered: bool) -> void:
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.12
		mesh.bottom_radius = 0.12
		mesh.height = 4.5
		mesh.material = _mat_pole
		pole.mesh = mesh
		pole.position = Vector3(side * 5.2, 2.25, 0.0)
		root.add_child(pole)
	if checkered:
		# Black and white squares along the top bar.
		for i in 12:
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.87, 0.9, 0.2)
			box.material = FlatMaterial.flat(Color.WHITE if i % 2 == 0 else Color(0.1, 0.1, 0.1))
			tile.mesh = box
			tile.position = Vector3(-4.8 + i * 0.87, 4.4, 0.0)
			root.add_child(tile)
	else:
		var top := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(10.4, 0.9, 0.2)
		box.material = _mat_banner
		top.mesh = box
		top.position = Vector3(0.0, 4.4, 0.0)
		root.add_child(top)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.outline_size = 16
	label.position = Vector3(0.0, 5.3, 0.0)
	label.name = "Banner"
	root.add_child(label)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		_face(banner, camera)
		if _finish:
			_face(_finish.get_node_or_null("Banner") as Label3D, camera)
	if is_counting:
		countdown_left -= delta
		var hud := get_tree().get_first_node_in_group(&"hud")
		if countdown_left <= 0.0:
			_go()
		elif hud and hud.has_method(&"show_notice"):
			hud.call(&"show_notice", str(ceili(countdown_left)))


func _face(label: Label3D, camera: Camera3D) -> void:
	if label == null:
		return
	var to_camera := camera.global_position - label.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() > 0.001:
		label.global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_racing or _player_kart == null or _terrain == null:
		return
	elapsed += delta
	# Giving up: out of the kart for a while.
	if not _player_kart.is_driven():
		_off_kart_left -= delta
		if _off_kart_left <= 0.0:
			_abort()
			return
	else:
		_off_kart_left = 3.0
	# Off the road too long: back to the last checkpoint.
	var pos := _player_kart.global_position
	if _terrain.road_distance(pos.x, pos.z) > OFFROAD_DISTANCE:
		_offroad_left -= delta
		if _offroad_left <= 0.0:
			_respawn_player()
			return
	else:
		_offroad_left = offroad_time
	var p := _relative_progress(pos)
	# Off the road the progress is meaningless (a shortcut across the
	# island would "pass" gates): count nothing there.
	var on_road := _terrain.road_distance(pos.x, pos.z) < ON_ROAD_DISTANCE
	if on_road:
		if _lap_wrapped(_player_last, p, next_gate):
			_player_laps += 1
			next_gate = 0
		_player_last = p
		if next_gate < gate_count and p > _gate_distances[next_gate] and p < _gate_distances[next_gate] + _length * 0.25:
			next_gate += 1
			Sfx.play(&"checkpoint", -6.0)
			_refresh_gates()
	lap_progress = clampf(p / _length, 0.0, 1.0)
	for racer in _racers:
		var kart: VehicleController = racer["kart"]
		if racer["finished"] or not is_instance_valid(kart):
			continue
		var rp := _relative_progress(kart.global_position)
		if _lap_wrapped(racer["last"], rp, racer["gate"]):
			racer["laps"] += 1
			racer["gate"] = 0
		racer["last"] = rp
		if racer["gate"] < gate_count and rp > _gate_distances[racer["gate"]]:
			racer["gate"] += 1
		if _at_finish(racer["laps"], racer["gate"], rp):
			racer["finished"] = true
		_drive_rival(racer, rp)
	# Place: 1 + racers ahead (finished, or further along the course).
	var mine := _course_position(_player_laps, next_gate, p)
	var ahead := 0
	for racer in _racers:
		if racer["finished"] or _course_position(racer["laps"], racer["gate"], racer["last"]) > mine:
			ahead += 1
	place = 1 + ahead
	if on_road and _at_finish(_player_laps, next_gate, p):
		_finish_race()


## Past the finish arch with the course done: after the start arch it
## takes a counted lap, before it every gate.
func _at_finish(laps: int, gate: int, progress: float) -> bool:
	if finish_offset >= 0.0:
		return laps >= 1 and progress >= _finish_progress
	return (laps >= 1 or gate >= gate_count) and progress >= _finish_progress


## A lap ends when the progress wraps from the last stretch to the first,
## and only with every checkpoint taken (no shortcuts, no U-turns).
func _lap_wrapped(last: float, now: float, gate: int) -> bool:
	return last > _length * 0.75 and now < _length * 0.25 and gate >= gate_count


## Comparable course position: laps, then checkpoints, then metres.
func _course_position(laps: int, gate: int, progress: float) -> float:
	return laps * (_length * 2.0) + gate * _length + progress


## Rivals: rubber band around the player, turbo unless far ahead.
func _drive_rival(racer: Dictionary, rp: float) -> void:
	var kart: VehicleController = racer["kart"]
	var driver := kart.get_node_or_null("NpcDriver") as NpcDriver
	if driver == null:
		return
	var gap := _course_position(racer["laps"], racer["gate"], rp) - _course_position(_player_laps, next_gate, _player_last)
	driver.speed_factor = clampf(opponent_speed - float(racer["handicap"]) + clampf(-gap / 400.0, -0.05, 0.05), 0.8, 1.1)
	driver.use_turbo = gap < 60.0


## Metres along the ring measured from the start line.
func _relative_progress(at: Vector3) -> float:
	return fposmod(_terrain.road_progress(road_index, at) - _start_distance, _length)


# --- interactable (from the kart) ------------------------------------------

func can_use_from_kart() -> bool:
	return true


func can_interact(player: CharacterController) -> bool:
	return not is_racing and not is_counting and _player_kart_inside(player) != null


func get_prompt() -> String:
	return tr(&"PROMPT_RACE")


func get_interaction_position() -> Vector3:
	var player := GameManager.get_player(0) as CharacterController
	var kart := _player_kart_inside(player) if player else null
	return kart.global_position if kart else global_position + Vector3.DOWN * 1000.0


func interact(player: CharacterController) -> void:
	var kart := _player_kart_inside(player)
	if kart and not is_racing and not is_counting:
		_start(kart)


func _player_kart_inside(player: CharacterController) -> VehicleController:
	if player == null or not player.driver.is_driving or player.driver.vehicle == null:
		return null
	var kart := player.driver.vehicle
	return kart if get_overlapping_bodies().has(kart) else null


# --- race flow --------------------------------------------------------------

func _start(kart: VehicleController) -> void:
	_player_kart = kart
	is_counting = true
	countdown_left = COUNTDOWN
	elapsed = 0.0
	place = 1
	next_gate = 0
	_player_laps = 0
	_player_last = 0.0
	_offroad_left = offroad_time
	_off_kart_left = 3.0
	_racers.clear()
	# The other NPC karts leave the road for the race.
	_hidden_karts.clear()
	for node in get_tree().get_nodes_in_group(&"npc_kart"):
		node.visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
		_hidden_karts.append(node)
	# Grid: two columns ahead of the start line.
	for i in opponents:
		var rival := vehicle_scene.instantiate() as VehicleController
		rival.name = "Racer%d" % i
		if vehicle_definition:
			rival.definition = vehicle_definition
		var driver := NpcDriver.new()
		driver.name = "NpcDriver"
		driver.road_index = road_index
		@warning_ignore("integer_division")
		driver.distance = fposmod(_start_distance + 7.0 + 6.0 * (i / 2), _length)
		driver.speed_factor = 0.0
		driver.caution_radius = 0.0
		driver.lane_offset = 2.6 * (1.0 if i % 2 == 0 else -1.0)
		driver.racing = true
		driver.bend_speed = 0.8
		driver.look_ahead = 14.0
		rival.add_child(driver)
		add_child(rival)
		rival.wings_locked = true
		if not opponent_definitions.is_empty():
			var definition := CharacterRoster.for_npc(opponent_definitions[i % opponent_definitions.size()])
			if definition and definition.visual_scene:
				var visual := definition.visual_scene.instantiate() as Node3D
				visual.scale = Vector3.ONE * definition.visual_scale
				rival.seat_visual(visual)
				if visual.has_method(&"set_seated"):
					visual.call(&"set_seated", true)
		_racers.append({"kart": rival, "last": 0.0, "gate": 0, "laps": 0, "finished": false, "handicap": 0.01 * i})
	kart.wings_locked = true
	kart.motor.is_flying = false
	GameManager.set_frozen(true)
	Sfx.play(&"checkpoint", -4.0)
	_refresh_gates()
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"RACE_READY"))


func _go() -> void:
	is_counting = false
	is_racing = true
	elapsed = 0.0
	GameManager.set_frozen(false)
	for racer in _racers:
		var driver := (racer["kart"] as Node).get_node_or_null("NpcDriver") as NpcDriver
		if driver:
			driver.speed_factor = opponent_speed - float(racer["handicap"])
			driver.use_turbo = true
	Sfx.play(&"fanfare", -6.0)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"RACE_GO"))
	race_started.emit()


## Gates show only during a race: next one yellow, passed ones grey.
func _refresh_gates() -> void:
	for k in _gates.size():
		var gate := _gates[k]
		gate.visible = is_racing or is_counting
		var color := Color(0.3, 0.7, 1.0)
		if k < next_gate:
			color = Color(0.6, 0.6, 0.6)
		elif k == next_gate:
			color = Color(1.0, 0.85, 0.2)
		for child in gate.get_children():
			var mesh := child as MeshInstance3D
			if mesh and mesh.mesh is BoxMesh:
				(mesh.mesh as BoxMesh).material = FlatMaterial.flat(color)


func _respawn_player() -> void:
	var d := _start_distance + (_gate_distances[next_gate - 1] if next_gate > 0 else 0.0) + 4.0
	var pose := _terrain.road_pose(road_index, d)
	pose.origin.y += 0.4
	_player_kart.place(pose)
	_player_kart.velocity = Vector3.ZERO
	_offroad_left = offroad_time
	_player_last = _relative_progress(_player_kart.global_position)
	Sfx.play(&"hurt", -6.0)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"RACE_OFFROAD"))


func _abort() -> void:
	is_racing = false
	_cleanup()
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"RACE_GAVE_UP"))
	race_finished.emit(0, elapsed)


func _finish_race() -> void:
	is_racing = false
	var final_place := place
	var reward := 0
	if final_place <= REWARDS.size():
		var id := StringName("race_%s_%d" % [race_name, final_place])
		if not ProgressionManager.is_collected(id):
			reward = REWARDS[final_place - 1]
			ProgressionManager.record_collected(id, &"star", reward)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		var text := tr(&"RACE_RESULT") % [final_place, elapsed]
		if reward > 0:
			text += "  " + tr(&"RACE_REWARD") % reward
		hud.call(&"show_notice", text)
	Sfx.play(&"fanfare" if final_place == 1 else &"checkpoint")
	_cleanup()
	race_finished.emit(final_place, elapsed)


func _cleanup() -> void:
	is_counting = false
	GameManager.set_frozen(false)
	for racer in _racers:
		if is_instance_valid(racer["kart"]):
			(racer["kart"] as Node).queue_free()
	_racers.clear()
	for node in _hidden_karts:
		if is_instance_valid(node):
			node.visible = true
			node.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden_karts.clear()
	if is_instance_valid(_player_kart):
		_player_kart.wings_locked = false
	next_gate = 0
	_refresh_gates()
