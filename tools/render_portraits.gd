extends Node
## Renders a head-and-shoulders portrait PNG of every playable character
## (CharacterRoster) into assets/ui/portraits/<id>.png, for the character
## picker in the pause menu. Windowed run (needs a renderer):
##
##   godot --path . res://tools/render_portraits.tscn
##
## Same lighting recipe as the game (one sun, no ambient, self-lit fill).

const SIZE := 256


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/portraits"))
	for id in CharacterRoster.IDS:
		var definition := CharacterRoster.definition(id)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(SIZE, SIZE)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.0, 0.0, 0.0, 0.0)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.environment = e
		viewport.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35.0, 210.0, 0.0)
		sun.light_energy = 0.72
		viewport.add_child(sun)
		var visual := definition.visual_scene.instantiate() as Node3D
		visual.scale = Vector3.ONE * definition.visual_scale
		viewport.add_child(visual)
		var camera := Camera3D.new()
		var height := definition.capsule_height * definition.visual_scale
		camera.fov = 40.0
		viewport.add_child(camera)
		camera.look_at_from_position(Vector3(0.0, height * 0.72, -height * 1.25), Vector3(0.0, height * 0.66, 0.0), Vector3.UP)
		camera.make_current()
		for i in 6:
			await get_tree().process_frame
		var image := viewport.get_texture().get_image()
		var path := "res://assets/ui/portraits/%s.png" % id
		var err := image.save_png(path)
		print("PORTRAIT %s -> %s (%s)" % [id, path, error_string(err)])
		viewport.queue_free()
	get_tree().quit()
