extends Node
## Loads the main scene, lets it settle, saves a PNG and quits.
##
## Run:  godot --path <project> res://tools/capture_screenshot.tscn -- <out.png> [frames]
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

	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(scene)

	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(out_path)
	if error != OK:
		printerr("Screenshot failed (%d): %s" % [error, out_path])
		get_tree().quit(1)
		return
	print("Screenshot saved: %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
