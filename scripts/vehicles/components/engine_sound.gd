class_name EngineSound
extends AudioStreamPlayer3D
## Looping engine hum under the kart; pitch follows the speed, the turbo
## whooshes. Child of the vehicle scene, finds its VehicleController parent.

@export var idle_pitch := 0.8
@export var top_pitch := 2.2
@export var idle_db := -20.0
@export var driving_db := -8.0

var _vehicle: VehicleController


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	stream = Sfx.get_stream(&"engine")
	if stream:
		Sfx.make_looping(stream)
	unit_size = 6.0
	max_db = 0.0
	volume_db = idle_db
	# The controller applies its definition (and finds the turbo) in its own
	# _ready, which runs after this one.
	call_deferred(&"_connect_turbo")
	if stream and Sfx.enabled:
		play()


func _connect_turbo() -> void:
	if _vehicle and _vehicle.turbo:
		_vehicle.turbo.activated.connect(func() -> void: Sfx.play(&"turbo", -4.0))


func _process(delta: float) -> void:
	if _vehicle == null or _vehicle.definition == null:
		return
	var ratio := clampf(absf(_vehicle.get_speed()) / maxf(_vehicle.definition.max_speed, 1.0), 0.0, 1.0)
	pitch_scale = lerpf(pitch_scale, lerpf(idle_pitch, top_pitch, ratio), 6.0 * delta)
	var target_db := lerpf(idle_db, driving_db, ratio) if _vehicle.is_driven() else idle_db
	volume_db = lerpf(volume_db, target_db, 6.0 * delta)
