extends Node
## Performance probe (windowed): starts the game, drives the kart around
## the village for `seconds`, and prints frame times, draw calls, visible
## primitives and node counts. Phone proxy: draw calls and primitive
## counts matter there more than the PC's frame time.
##
## Run:  godot --path <project> res://tools/perf_probe.tscn -- [seconds] [quality]

const MAIN_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 12.0
	if args.size() > 1:
		Settings.quality = StringName(args[1])
	if FileAccess.file_exists(ProgressionManager.save_path):
		DirAccess.copy_absolute(ProgressionManager.save_path, "user://perf_save.json")
	ProgressionManager.save_path = "user://perf_save.json"
	ProgressionManager.load_from_disk()
	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	for i in 120:
		await get_tree().process_frame
	var player := GameManager.get_player(0) as CharacterController
	player.driver.summon()
	for i in 20:
		await get_tree().process_frame
	player.driver.enter_vehicle()
	# On the road ring near the village, so the drive crosses the busy area.
	var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	var line := get_tree().get_first_node_in_group(&"race_line") as Node3D
	if terrain and line:
		var pose := terrain.road_pose(1, terrain.road_progress(1, line.global_position) - 120.0)
		pose.origin.y += 0.4
		player.driver.vehicle.place(pose)
		terrain.set_focus(pose.origin)
	for i in 20:
		await get_tree().process_frame
	print("PERF driving: %s" % player.driver.is_driving)
	var frames: Array[float] = []
	var spikes: Array[int] = []
	var draw_calls: Array[int] = []
	var primitives: Array[int] = []
	var objects: Array[int] = []
	var t := 0.0
	var last := Time.get_ticks_usec()
	Input.action_press(InputActions.ACCELERATE)
	while t < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		t += dt / 1000.0
		frames.append(dt)
		if dt > 35.0:
			spikes.append(frames.size())
			if spikes.size() <= 4:
				var kart := player.driver.vehicle
				print("PERF spike %d: process %.1f physics %.1f ms, kart %s speed %.1f, nodes %d" % [frames.size(),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					kart.global_position.round(), kart.get_speed(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	Input.action_release(InputActions.ACCELERATE)
	print("PERF spikes at frames: %s" % [spikes])
	frames.sort()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= maxf(frames.size(), 1.0)
	print("PERF frames %d  avg %.1f ms  p95 %.1f ms  max %.1f ms" % [frames.size(), avg, frames[int(frames.size() * 0.95)], frames[-1]])
	print("PERF draw calls avg %d max %d  primitives avg %dk max %dk  objects avg %d max %d" % [
		_avg(draw_calls), draw_calls.max(), _avg(primitives) / 1000, primitives.max() / 1000, _avg(objects), objects.max()])
	var counts := {}
	_count(get_tree().root, counts)
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var parts := PackedStringArray()
	for k in keys.slice(0, 14):
		parts.append("%s %d" % [k, counts[k]])
	print("PERF nodes: " + ", ".join(parts))
	var ranged := 0
	var geometry := 0
	for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		geometry += 1
		if (node as GeometryInstance3D).visibility_range_end > 0.0:
			ranged += 1
	# Who owns the visible meshes: walk up to the first scripted ancestor.
	var camera := get_tree().root.get_camera_3d()
	var owners := {}
	for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var d := camera.global_position.distance_to(g.global_position) if camera else 0.0
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end:
			continue
		var owner_node: Node = g
		while owner_node and owner_node.get_script() == null:
			owner_node = owner_node.get_parent()
		var key: String = (owner_node.get_script() as Script).resource_path.get_file() if owner_node else "-"
		owners[key] = owners.get(key, 0) + 1
	var okeys := owners.keys()
	okeys.sort_custom(func(a: String, b: String) -> bool: return owners[a] > owners[b])
	var oparts := PackedStringArray()
	for k in okeys.slice(0, 12):
		oparts.append("%s %d" % [k, owners[k]])
	print("PERF visible meshes by owner: " + ", ".join(oparts))
	print("PERF lod props %d, geometry with a range %d / %d, quality %s (range %.0f)" % [get_tree().get_nodes_in_group(Lod.GROUP).size(), ranged, geometry, Settings.quality, Settings.prop_range()])
	get_tree().quit()


func _avg(values: Array[int]) -> int:
	var total := 0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)


func _count(node: Node, counts: Dictionary) -> void:
	var cls := node.get_class()
	counts[cls] = counts.get(cls, 0) + 1
	for child in node.get_children():
		_count(child, counts)
