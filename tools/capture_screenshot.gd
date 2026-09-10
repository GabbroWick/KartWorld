extends Node
## Loads the main scene, lets it settle, saves a PNG and quits.
##
## Run:  godot --path <project> res://tools/capture_screenshot.tscn -- <out.png> [frames] [drive]
##
## With the optional "drive" word the player summons the kart, gets in and
## holds the accelerator for the given frames, so the shot shows driving.
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
	var drive := user_args.size() > 2 and user_args[2] == "drive"

	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)

	if drive:
		await _press(InputActions.SUMMON_KART)
		await _wait(15)
		await _press(InputActions.INTERACT)
		await _wait(5)
		Input.action_press(InputActions.ACCELERATE)
	for i in frames:
		await get_tree().process_frame
	Input.action_release(InputActions.ACCELERATE)
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
