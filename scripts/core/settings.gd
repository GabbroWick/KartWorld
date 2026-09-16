extends Node
## Autoload `Settings`: the player's options, saved to user://settings.json
## and applied live: graphics quality, flight/camera Y inversion, camera
## sensitivity, sound and music volume. Anything that cares connects to
## `changed` or reads the fields; `apply()` pushes the quality preset onto
## the current world (sun shadows, streaming distance, 3D resolution).

signal changed

## Tests point this at a scratch file.
var path := "user://settings.json"
const QUALITY_NAMES: Array[StringName] = [&"low", &"medium", &"high"]

var quality: StringName = &"medium"
var invert_fly_y := false
var invert_look_y := false
## 0.5 .. 2.0 multiplier on mouse/touch/stick look speed.
var look_sensitivity := 1.0
## 0..1
var sfx_volume := 1.0
var music_volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	# A sensible default for phones: they have less GPU and a small screen.
	if quality == &"medium" and OS.has_feature("mobile") and not FileAccess.file_exists(path):
		quality = &"low"
	get_tree().node_added.connect(_on_node_added)
	apply()


func set_quality(value: StringName) -> void:
	if value in QUALITY_NAMES:
		quality = value
		apply()
		save_to_disk()


func set_invert_fly_y(on: bool) -> void:
	invert_fly_y = on
	save_to_disk()


func set_invert_look_y(on: bool) -> void:
	invert_look_y = on
	apply()
	save_to_disk()


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = clampf(value, 0.3, 2.5)
	apply()
	save_to_disk()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply()
	save_to_disk()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply()
	save_to_disk()


## Pushes everything onto the live scene (safe to call any time).
func apply() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Sound.
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(sfx_volume, 0.0001)))
	if has_node("/root/Sfx") and get_node("/root/Sfx").has_method(&"set_music_volume"):
		get_node("/root/Sfx").call(&"set_music_volume", music_volume)
	# 3D resolution.
	var root := tree.root
	root.scaling_3d_scale = {&"low": 0.7, &"medium": 0.85, &"high": 1.0}[quality]
	# World pieces (present or not).
	for sun in tree.get_nodes_in_group(&"sun"):
		_apply_sun(sun as DirectionalLight3D)
	for terrain in tree.get_nodes_in_group(&"terrain"):
		_apply_terrain(terrain)
	for camera in tree.get_nodes_in_group(&"camera_rig"):
		_apply_camera(camera)
	changed.emit()


func _apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.shadow_enabled = quality != &"low"
	sun.directional_shadow_max_distance = {&"low": 40.0, &"medium": 80.0, &"high": 120.0}[quality]


func _apply_terrain(terrain: Node) -> void:
	if terrain == null or not terrain.get(&"streaming"):
		return
	terrain.set(&"far_distance", {&"low": 400.0, &"medium": 560.0, &"high": 720.0}[quality])


func _apply_camera(camera: Node) -> void:
	if camera == null:
		return
	camera.set(&"invert_y", invert_look_y)
	camera.set(&"sensitivity_scale", look_sensitivity)


## New worlds bring new suns/terrains: apply as they arrive.
func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		node.add_to_group(&"sun")
		_apply_sun(node)
	elif node.has_method(&"ensure_built_at"):   # IslandTerrain (groups come later)
		call_deferred(&"_apply_terrain", node)
	elif node.has_method(&"add_look_delta"):   # ThirdPersonCamera
		_apply_camera(node)


func save_to_disk() -> void:
	var data := {
		"quality": String(quality),
		"invert_fly_y": invert_fly_y,
		"invert_look_y": invert_look_y,
		"look_sensitivity": look_sensitivity,
		"sfx_volume": sfx_volume,
		"music_volume": music_volume,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	changed.emit()


func load_from_disk() -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var q := StringName(String(data.get("quality", "medium")))
	quality = q if q in QUALITY_NAMES else &"medium"
	invert_fly_y = bool(data.get("invert_fly_y", false))
	invert_look_y = bool(data.get("invert_look_y", false))
	look_sensitivity = clampf(float(data.get("look_sensitivity", 1.0)), 0.3, 2.5)
	sfx_volume = clampf(float(data.get("sfx_volume", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.8)), 0.0, 1.0)
