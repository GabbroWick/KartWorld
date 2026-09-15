extends Node
## Lighting regression test. Needs a window (it renders), so run it without
## --headless:
##
##   godot --path . res://tools/tests/test_lighting_runner.tscn
##   godot --path . --rendering-method forward_plus res://tools/tests/test_lighting_runner.tscn
##
## Guards the "palette renders as authored" rule: a sunlit flat surface must
## come out as the colour written in the scene file, on every renderer. This
## is what catches Godot's Compatibility bug where enabling directional
## shadows re-adds the ambient/base pass (godotengine/godot#90259), and any
## future change to the lighting recipe in ARCHITECTURE.md.

const MAIN_SCENE := "res://scenes/main.tscn"
## Per-channel tolerance in sRGB 0..1. Lambert on a flat face with the sun at
## 52 degrees gives 1.25 * 0.79 = 0.99x the albedo, so a few units of slack.
const TOLERANCE := 0.06

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	for i in 5:
		await get_tree().process_frame

	var world: Node = scene.get("world")
	var terrain := world.get_node("IslandTerrain") as IslandTerrain
	var sun := world.get_node("SunLight") as DirectionalLight3D
	var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment

	_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED,
		"ambient light is disabled (Compatibility shadow bug workaround)")
	_check(env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "tonemap is linear")
	_check(sun.shadow_enabled, "sun casts shadows")
	_check(sun.shadow_opacity < 1.0, "shadows are semi-transparent (that is the fill light)")

	# Look straight down at a flat, sunlit, unoccluded patch of the house pad
	# (the flat zone around the house; the streamed tile must exist there,
	# a far tile's coarse mesh would bury the probe quads).
	terrain.set_focus(Vector3(60.0, 4.0, 70.0))
	terrain.ensure_built_at(60.0, 70.0)
	var probe := Vector3(60.0, terrain.sample_height(60.0, 70.0), 70.0)
	var camera := Camera3D.new()
	camera.position = probe + Vector3.UP * 8.0
	camera.rotation_degrees = Vector3(-90, 0, 0)
	scene.add_child(camera)
	camera.make_current()

	# Reference quad with a known albedo, next to the grass probe.
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	var quad_color := Color(0.5, 0.5, 0.5)
	mesh.material = FlatMaterial.flat(quad_color)
	quad.mesh = mesh
	quad.rotation_degrees = Vector3(-90, 0, 0)
	quad.position = probe + Vector3(3.0, 0.05, 0.0)
	scene.add_child(quad)

	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()

	var grass := _pixel(image, camera, probe)
	_check_color(grass, terrain.grass_color, "sunlit grass renders as authored")
	var grey := _pixel(image, camera, quad.global_position)
	_check_color(grey, quad_color, "sunlit 50 percent grey quad renders as authored")

	# Faces turned away from the sun must stay readable: the material fill
	# term (FlatMaterial.FILL) stands in for ambient light. Two vertical quads
	# face opposite ways along the sun's azimuth; the darker one is the one
	# turned away, and it must be lit by the fill alone.
	var sun_dir: Vector3 = -sun.global_basis.z
	var along := Vector3(sun_dir.x, 0.0, sun_dir.z).normalized()
	var darkest := 1.0
	for sign in [1.0, -1.0]:
		var away := MeshInstance3D.new()
		var away_mesh := QuadMesh.new()
		away_mesh.size = Vector2(2, 2)
		away_mesh.material = FlatMaterial.flat(quad_color)
		away.mesh = away_mesh
		away.position = probe + Vector3(-3.0 * sign, 1.2, 0.0)
		away.look_at(away.position + along * sign, Vector3.UP)
		scene.add_child(away)
		var side_camera := Camera3D.new()
		side_camera.position = away.position - along * sign * 4.0
		scene.add_child(side_camera)
		side_camera.look_at(away.position, Vector3.UP)
		side_camera.make_current()
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shade := _pixel(get_tree().root.get_texture().get_image(), side_camera, away.position)
		darkest = minf(darkest, shade.r)
	_check(darkest > 0.2 and darkest < 0.45,
		"a face turned away from the sun is lit by the fill, not black (got %.2f, want 0.2-0.45)" % darkest)

	print("  renderer: %s" % RenderingServer.get_current_rendering_method())
	_finish()


func _pixel(image: Image, camera: Camera3D, world_point: Vector3) -> Color:
	var p := camera.unproject_position(world_point)
	return image.get_pixel(int(p.x), int(p.y))


func _check_color(got: Color, expected: Color, label: String) -> void:
	var ok := absf(got.r - expected.r) <= TOLERANCE \
		and absf(got.g - expected.g) <= TOLERANCE \
		and absf(got.b - expected.b) <= TOLERANCE
	_check(ok, "%s: got (%.2f %.2f %.2f) expected (%.2f %.2f %.2f)"
		% [label, got.r, got.g, got.b, expected.r, expected.g, expected.b])


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
