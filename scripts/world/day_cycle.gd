class_name DayCycle
extends Node
## Day and night for a world: turns the sun (`sun_path`) around and dims it
## at night, tints the fog/sky. `time_of_day` 0 = midnight, 0.5 = noon.
## Sleeping in the Bed calls `set_morning()`. One full day lasts
## `day_length` seconds. Keeps the lighting recipe: one sun, no ambient.

const GROUP := &"day_cycle"

@export var sun_path: NodePath
@export var environment_path: NodePath
@export_range(60.0, 3600.0, 10.0) var day_length := 600.0
@export_range(0.0, 1.0, 0.01) var time_of_day := 0.35
@export var run := true

var _sun: DirectionalLight3D
var _env: Environment
var _base_yaw := 0.0
var _day_fog := Color.WHITE


func _ready() -> void:
	add_to_group(GROUP)
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	_env = world_env.environment if world_env else null
	if _sun:
		_base_yaw = _sun.rotation.y
	if _env:
		_day_fog = _env.fog_light_color
	_apply()


func _process(delta: float) -> void:
	if not run:
		return
	time_of_day = fmod(time_of_day + delta / day_length, 1.0)
	_apply()


func is_night() -> bool:
	return time_of_day < 0.22 or time_of_day > 0.8


func set_morning() -> void:
	time_of_day = 0.3
	_apply()


## Sun elevation: -1 at midnight, +1 at noon.
func sun_height() -> float:
	return -cos(time_of_day * TAU)


func _apply() -> void:
	var h := sun_height()
	if _sun:
		# Elevation from the time; keep the authored yaw. Never below the
		# horizon: a sun under the ground lights nothing and shadows vanish.
		var elevation := clampf(asin(clampf(h, -1.0, 1.0)), deg_to_rad(8.0), deg_to_rad(75.0))
		_sun.rotation = Vector3(-elevation, _base_yaw, 0.0)
		var daylight := clampf((h + 0.15) / 0.5, 0.0, 1.0)
		_sun.light_energy = lerpf(0.12, 0.72, daylight)
		_sun.light_color = Color(0.55, 0.62, 0.9).lerp(Color(1.0, 0.97, 0.9), daylight)
	if _env:
		var daylight := clampf((h + 0.15) / 0.5, 0.0, 1.0)
		_env.fog_light_color = Color(0.08, 0.1, 0.2).lerp(_day_fog, daylight)
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			var sky := _env.sky.sky_material as ProceduralSkyMaterial
			sky.sky_energy_multiplier = lerpf(0.12, 1.0, daylight)
			sky.ground_energy_multiplier = lerpf(0.12, 1.0, daylight)
