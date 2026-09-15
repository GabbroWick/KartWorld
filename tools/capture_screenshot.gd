extends Node
## Loads the main scene, lets it settle, saves a PNG and quits.
##
## Run:  godot --path <project> res://tools/capture_screenshot.tscn -- <out.png> [frames] [drive] [turbo] [talk] [picker] [face=deg] [level=<.tres>] [at=x,y,z] [yaw=deg] [zoom=m]
##
## With the optional "drive" word the player summons the kart, gets in and
## holds the accelerator for the given frames, so the shot shows driving.
## `level=res://resources/levels/x.tres` loads that level first and
## `at=x,y,z` teleports the player there (camera behind, facing -Z).
##
## Used to visually verify a build without a human having to launch the game.
## Requires a real (non-headless) renderer.

const MAIN_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	_run()


func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	var out_path := user_args[0] if user_args.size() > 0 else "screenshot.png"
	var frames := int(user_args[1]) if user_args.size() > 1 else 60
	var drive := user_args.has("drive")
	var level_path := ""
	var at := ""
	var yaw := ""
	var zoom := ""
	for arg in user_args:
		if arg.begins_with("yaw="):
			yaw = arg.trim_prefix("yaw=")
		elif arg.begins_with("zoom="):
			zoom = arg.trim_prefix("zoom=")
		if arg.begins_with("level="):
			level_path = arg.trim_prefix("level=")
		elif arg.begins_with("at="):
			at = arg.trim_prefix("at=")

	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(5)

	if level_path != "":
		var manager := get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
		manager.load_level(load(level_path) as LevelDefinition)
		await _wait(5)
	if at != "":
		var parts := at.split(",")
		var player := GameManager.get_player(0) as CharacterController
		var target := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		# Streaming terrain: build the tiles there first or the player falls.
		var terrain := get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
		if terrain and terrain.streaming:
			terrain.set_focus(target)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					terrain.ensure_built_at(target.x + dx * terrain.chunk_size, target.z + dz * terrain.chunk_size)
		player.global_position = target
		player.motor.reset()
		player.visual_root.global_rotation.y = 0.0
		for cam in scene.find_children("*", "ThirdPersonCamera", true, false):
			(cam as ThirdPersonCamera).set_yaw(0.0)
			(cam as ThirdPersonCamera).set_target(player, true)
		await _wait(5)

	if user_args.has("picker"):
		GameManager.set_paused(true)
		await _wait(2)
		(scene.get_node("PauseMenu") as PauseMenu)._show_picker(true)   # never picks: the real save stays
		await _wait(2)
	if user_args.has("talk"):
		await _press(InputActions.INTERACT)
		await _wait(5)
	for arg in user_args:
		if arg.begins_with("face="):
			# Turn the player (and the summoned kart) before driving.
			var player := GameManager.get_player(0) as CharacterController
			player.visual_root.global_rotation.y = deg_to_rad(float(arg.trim_prefix("face=")))
			for cam in scene.find_children("*", "ThirdPersonCamera", true, false):
				(cam as ThirdPersonCamera).set_yaw(deg_to_rad(float(arg.trim_prefix("face="))))
	if drive:
		await _press(InputActions.SUMMON_KART)
		await _wait(15)
		await _press(InputActions.INTERACT)
		await _wait(5)
		Input.action_press(InputActions.ACCELERATE)
		if user_args.has("turbo"):
			Input.action_press(InputActions.TURBO)
	for i in frames:
		await get_tree().process_frame
	Input.action_release(InputActions.ACCELERATE)
	Input.action_release(InputActions.TURBO)
	if zoom != "":
		# Camera distance in metres (close-ups of the kart / character).
		for cam in scene.find_children("*", "ThirdPersonCamera", true, false):
			(cam as ThirdPersonCamera).set_framing(float(zoom), (cam as ThirdPersonCamera).target_height)
	if yaw != "":
		# Camera heading in degrees (e.g. yaw=90 looks at the kart's side).
		for cam in scene.find_children("*", "ThirdPersonCamera", true, false):
			(cam as ThirdPersonCamera).set_yaw(deg_to_rad(float(yaw)))
		await _wait(3)
	await RenderingServer.frame_post_draw

	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(out_path)
	if error != OK:
		printerr("Screenshot failed (%d): %s" % [error, out_path])
		get_tree().quit(1)
		return
	print("Screenshot saved: %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _wait(2)
	Input.action_release(action)
	await _wait(1)
