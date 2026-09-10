@tool
class_name IslandTerrain
extends StaticBody3D
## Procedural low-poly island: flat-shaded height-field mesh + trimesh collision.
##
## The island shape is a radial profile (plateau -> beach -> steep drop into the
## sea) plus one rounded mountain and gentle noise. Everything is a parameter,
## so the hub can be reshaped from the inspector and regenerated instantly.
## Other nodes (prop scatter, spawn points) query `sample_height()` instead of
## raycasting, which also works inside the editor.
##
## Beyond `shore_radius` the ground plunges to `sea_floor_height`: the slope is
## steeper than the character's floor angle, so walking into the sea means
## sliding down until the fall limit triggers a respawn. No extra kill system.

const GROUP := &"terrain"

@export_group("Island")
@export_range(10.0, 200.0, 1.0) var plateau_radius := 40.0:
	set(value):
		plateau_radius = value
		_request_rebuild()
@export_range(10.0, 220.0, 1.0) var shore_radius := 54.0:
	set(value):
		shore_radius = value
		_request_rebuild()
@export_range(0.0, 20.0, 0.1) var beach_height := 0.5:
	set(value):
		beach_height = value
		_request_rebuild()
@export_range(0.0, 30.0, 0.1) var plateau_height := 3.5:
	set(value):
		plateau_height = value
		_request_rebuild()
@export_range(-100.0, 0.0, 1.0) var sea_floor_height := -45.0:
	set(value):
		sea_floor_height = value
		_request_rebuild()
@export_range(1.0, 30.0, 0.5) var drop_width := 6.0:
	set(value):
		drop_width = value
		_request_rebuild()

## Areas forced flat for buildings and spawn points: (x, z, radius, height).
@export var flat_zones: Array[Vector4] = []:
	set(value):
		flat_zones = value
		_request_rebuild()

@export_group("Mountain")
@export var mountain_center := Vector2(-22.0, -20.0):
	set(value):
		mountain_center = value
		_request_rebuild()
@export_range(0.0, 100.0, 0.5) var mountain_radius := 22.0:
	set(value):
		mountain_radius = value
		_request_rebuild()
@export_range(0.0, 60.0, 0.5) var mountain_height := 13.0:
	set(value):
		mountain_height = value
		_request_rebuild()

@export_group("Detail")
@export var noise_seed := 7:
	set(value):
		noise_seed = value
		_request_rebuild()
@export_range(0.0, 10.0, 0.1) var noise_amplitude := 1.4:
	set(value):
		noise_amplitude = value
		_request_rebuild()
@export_range(0.001, 0.2, 0.001) var noise_frequency := 0.035:
	set(value):
		noise_frequency = value
		_request_rebuild()
## Metres per grid cell. Lower = smoother and heavier.
@export_range(0.5, 8.0, 0.25) var cell_size := 1.5:
	set(value):
		cell_size = value
		_request_rebuild()

@export_group("Colours")
@export var sand_color := Color(0.9, 0.82, 0.58)
@export var grass_color := Color(0.42, 0.68, 0.32)
@export var rock_color := Color(0.5, 0.48, 0.46)
@export var snow_color := Color(0.95, 0.95, 0.97)

var _noise := FastNoiseLite.new()
var _rebuild_queued := false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


## Height of the terrain surface at world (x, z).
func sample_height(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()

	# Radial island profile: plateau, then a beach easing down to the shore.
	var inland := 1.0 - smoothstep(plateau_radius, shore_radius, distance)
	var height := beach_height + (plateau_height - beach_height) * pow(inland, 0.8)

	# One rounded mountain.
	var mountain_distance := Vector2(x, z).distance_to(mountain_center)
	var m := 1.0 - smoothstep(0.0, mountain_radius, mountain_distance)
	height += mountain_height * m * m * (3.0 - 2.0 * m)

	# Rolling detail, fading out toward the beach.
	height += _noise.get_noise_2d(x, z) * noise_amplitude * inland

	# Past the shore, plunge to the sea floor.
	if distance > shore_radius:
		var t := clampf((distance - shore_radius) / drop_width, 0.0, 1.0)
		height = lerpf(beach_height, sea_floor_height, t * t)

	# Flatten pads for buildings; blended edge so there is no visible seam.
	for zone in flat_zones:
		var zone_distance := Vector2(x, z).distance_to(Vector2(zone.x, zone.y))
		var weight := 1.0 - smoothstep(zone.z * 0.55, zone.z, zone_distance)
		height = lerpf(height, zone.w, weight)
	return height


## Approximate surface normal at world (x, z).
func sample_normal(x: float, z: float) -> Vector3:
	var step := 0.5
	var dx := sample_height(x + step, z) - sample_height(x - step, z)
	var dz := sample_height(x, z + step) - sample_height(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Slope in degrees at world (x, z).
func sample_slope_degrees(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(sample_normal(x, z).y, -1.0, 1.0)))


## True when (x, z) is on the walkable island (not on the drop into the sea).
func is_on_land(x: float, z: float) -> bool:
	return Vector2(x, z).length() <= shore_radius


func rebuild() -> void:
	if not is_node_ready():
		return
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var extent := shore_radius + drop_width
	var cells := int(ceil(extent * 2.0 / cell_size))
	var origin := -extent

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in cells:
		for ix in cells:
			var x0 := origin + ix * cell_size
			var z0 := origin + iz * cell_size
			var x1 := x0 + cell_size
			var z1 := z0 + cell_size
			var a := Vector3(x0, sample_height(x0, z0), z0)
			var b := Vector3(x1, sample_height(x1, z0), z0)
			var c := Vector3(x1, sample_height(x1, z1), z1)
			var d := Vector3(x0, sample_height(x0, z1), z1)
			# Alternate the diagonal so slopes do not show a directional grain.
			# Godot front faces wind clockwise: these orders give up-facing normals.
			if (ix + iz) % 2 == 0:
				_add_triangle(surface, a, b, c)
				_add_triangle(surface, a, c, d)
			else:
				_add_triangle(surface, a, b, d)
				_add_triangle(surface, b, c, d)

	var array_mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Palette colours are authored in sRGB; without this they render washed out.
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	array_mesh.surface_set_material(0, material)
	mesh_instance.mesh = array_mesh
	collision.shape = array_mesh.create_trimesh_shape()


## Flat-shaded triangle: one normal and one colour for the whole face.
## The normal comes from Plane() so it always matches Godot's winding rule.
func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := Plane(a, b, c).normal
	var centre := (a + b + c) / 3.0
	surface.set_normal(normal)
	surface.set_color(_color_for(centre.y, normal))
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _color_for(height: float, normal: Vector3) -> Color:
	var slope := 1.0 - normal.y  # 0 flat, 1 vertical
	var color := sand_color.lerp(grass_color, smoothstep(beach_height + 0.3, beach_height + 1.6, height))
	var snow_line := plateau_height + mountain_height * 0.72
	color = color.lerp(snow_color, smoothstep(snow_line, snow_line + 2.5, height))
	color = color.lerp(rock_color, smoothstep(0.35, 0.6, slope))
	return color


func _request_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()
