class_name RaceLine
extends Area3D
## A start/finish arch on a road ring. Drive the kart through it to start
## a one-lap race against `opponents` NPC karts spawned just ahead; cross
## it again after a full lap to finish. Position along the ring comes
## from IslandTerrain.road_progress; the HUD shows time, place and lap.
## Places pay stars once each (1st 5, 2nd 3, 3rd 1), saved as collected
## ids `race_<name>_<place>`.
##
## Placed on the terrain's road ring `road_index` at the point nearest to
## this node (so it can be dropped roughly in the scene).

signal race_started
signal race_finished(place: int, seconds: float)

const GROUP := &"race_line"
const REWARDS := [5, 3, 1]

@export var road_index := 1
@export_range(1, 6, 1) var opponents := 3
@export var vehicle_scene: PackedScene
@export var vehicle_definition: VehicleDefinition
@export var opponent_definitions: Array[CharacterDefinition] = []
@export_range(0.5, 1.1, 0.05) var opponent_speed := 0.92
@export var race_name: StringName = &"island"

var is_racing := false
var elapsed := 0.0
var place := 1
var lap_progress := 0.0   # 0..1 for the player
var _terrain: IslandTerrain
var _length := 0.0
var _start_distance := 0.0
var _racers: Array[Dictionary] = []   # {kart, progress, finished}
var _player_kart: VehicleController
var _player_last := 0.0
var _player_mid := false
var _player_laps := 0
var _player_left_line := false
var _finished_count := 0

@onready var banner: Label3D = $Banner


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"map_race")
	collision_layer = 8
	collision_mask = 16   # vehicles
	body_entered.connect(_on_body_entered)
	banner.text = tr(&"RACE_BANNER")
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


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and banner:
		var to_camera := camera.global_position - banner.global_position
		to_camera.y = 0.0
		if to_camera.length_squared() > 0.001:
			banner.global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_racing or _player_kart == null or _terrain == null:
		return
	elapsed += delta
	var p := _relative_progress(_player_kart.global_position)
	# Lap counting: progress wraps from near the end to near the start,
	# and only after most of the ring was really driven (no U-turns).
	if _player_last > _length * 0.7 and p < _length * 0.3 and _player_mid:
		_player_laps += 1
		_player_mid = false
	_player_last = p
	if p > _length * 0.4 and p < _length * 0.7:
		_player_mid = true   # the far side of the ring was really reached
	lap_progress = clampf(p / _length, 0.0, 1.0)
	for racer in _racers:
		var kart: VehicleController = racer["kart"]
		if racer["finished"] or not is_instance_valid(kart):
			continue
		var rp := _relative_progress(kart.global_position)
		if racer["last"] > _length * 0.7 and rp < _length * 0.3 and racer["mid"]:
			racer["laps"] += 1
			racer["mid"] = false
		racer["last"] = rp
		if rp > _length * 0.4 and rp < _length * 0.7:
			racer["mid"] = true
		if racer["laps"] >= 1:
			racer["finished"] = true
			_finished_count += 1
	# Place: 1 + racers ahead (finished or further along this lap).
	var ahead := 0
	for racer in _racers:
		if racer["finished"] or (racer["laps"] == _player_laps and racer["last"] > p) or racer["laps"] > _player_laps:
			ahead += 1
	place = 1 + ahead
	if _player_laps >= 1:
		_finish()


## Metres along the ring measured from the start line.
func _relative_progress(at: Vector3) -> float:
	return fposmod(_terrain.road_progress(road_index, at) - _start_distance, _length)


func _on_body_entered(body: Node3D) -> void:
	var kart := body as VehicleController
	if kart == null or kart.driver == null or not (kart.driver is CharacterController):
		return
	if is_racing:
		return
	_start(kart)


func _start(kart: VehicleController) -> void:
	_player_kart = kart
	is_racing = true
	elapsed = 0.0
	place = 1
	_player_laps = 0
	_player_last = 0.0
	_player_mid = false
	_finished_count = 0
	_racers.clear()
	for i in opponents:
		var rival := vehicle_scene.instantiate() as VehicleController
		rival.name = "Racer%d" % i
		if vehicle_definition:
			rival.definition = vehicle_definition
		var driver := NpcDriver.new()
		driver.name = "NpcDriver"
		driver.road_index = road_index
		driver.distance = fposmod(_start_distance + 6.0 + 5.0 * i, _length)
		driver.speed_factor = opponent_speed - 0.04 * i
		driver.caution_radius = 0.0
		rival.add_child(driver)
		add_child(rival)
		if not opponent_definitions.is_empty():
			var definition := CharacterRoster.for_npc(opponent_definitions[i % opponent_definitions.size()])
			if definition and definition.visual_scene:
				var visual := definition.visual_scene.instantiate() as Node3D
				visual.scale = Vector3.ONE * definition.visual_scale
				rival.seat_visual(visual)
				if visual.has_method(&"set_seated"):
					visual.call(&"set_seated", true)
		_racers.append({"kart": rival, "last": 0.0, "mid": false, "laps": 0, "finished": false})
	Sfx.play(&"fanfare", -6.0)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"show_notice"):
		hud.call(&"show_notice", tr(&"RACE_GO"))
	race_started.emit()


func _finish() -> void:
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
	for racer in _racers:
		if is_instance_valid(racer["kart"]):
			(racer["kart"] as Node).queue_free()
	_racers.clear()
	race_finished.emit(final_place, elapsed)
