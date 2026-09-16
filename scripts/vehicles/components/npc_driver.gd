class_name NpcDriver
extends Node
## An AI at the wheel: child of a VehicleController instance, it follows the
## island's road network by steering toward a point ahead on the nearest
## road, slows for tight bends and for the player, and puts itself back on
## the road if it ever falls off. The vehicle's physics are untouched: the
## driver only writes `VehicleInput.throttle / steer` like a hand would.
##
## `distance` chooses where on the road the kart starts; drivers spaced by
## distance on the same road never bunch up (same speed cap).

## Road to follow: -1 = the terrain's main loop, 0.. = `extra_roads` index.
@export var road_index := -1
## Start this many metres along the road.
@export_range(0.0, 20000.0, 1.0) var distance := 0.0
## Drive the loop the other way.
@export var reverse := false
## Cruise speed as a fraction of the vehicle's max speed.
@export_range(0.2, 1.0, 0.05) var speed_factor := 0.7
## Look-ahead for steering, metres.
@export_range(4.0, 40.0, 1.0) var look_ahead := 12.0
## Brake when the player (on foot or in a kart) is closer than this ahead.
@export_range(0.0, 30.0, 0.5) var caution_radius := 9.0
## Metres to the right of the road centre to drive on (racers share the road).
@export_range(-4.0, 4.0, 0.1) var lane_offset := 0.0
## Speed kept in the tightest bends (racers brake less).
@export_range(0.2, 1.0, 0.05) var bend_speed := 0.45
## Fire the turbo on straights (racers).
@export var use_turbo := false
## Racer: floor the throttle whenever below the wanted speed (a cruiser
## eases off near it and never reaches the player's top speed).
@export var racing := false

var vehicle: VehicleController
var terrain: IslandTerrain
var _samples: PackedVector3Array = PackedVector3Array()   # (x, h, z) along the road
var _closed := true
var _cursor := 0
var _last_progress_time := 0.0
var _last_position := Vector3.ZERO
var _gliding := false
var _glide_offset := 0.0
var _lod_ticks := 0


func _ready() -> void:
	vehicle = get_parent() as VehicleController
	if vehicle == null:
		push_error("NpcDriver must be a child of a VehicleController.")
		set_physics_process(false)
		return
	set_physics_process(false)
	call_deferred(&"_late_setup")


func _late_setup() -> void:
	terrain = get_tree().get_first_node_in_group(IslandTerrain.GROUP) as IslandTerrain
	if terrain == null:
		push_warning("NpcDriver '%s': no terrain, staying parked." % name)
		return
	if not terrain.is_node_ready():
		await terrain.ready
	_build_samples()
	if _samples.is_empty():
		push_warning("NpcDriver '%s': road %d has no samples." % [name, road_index])
		return
	vehicle.mount(self, false)
	vehicle.add_to_group(&"npc_kart")
	_teleport_to(_index_at_distance(distance))
	set_physics_process(true)


## Dense (x, h, z) samples of the chosen road, every 2 m, in driving order.
func _build_samples() -> void:
	var points: PackedVector2Array
	if road_index < 0:
		points = terrain.road_points
		_closed = true
	elif road_index < terrain.extra_roads.size():
		points = terrain.extra_roads[road_index]
		_closed = terrain.extra_roads_closed[road_index] if road_index < terrain.extra_roads_closed.size() else true
	else:
		return
	if points.size() < 2:
		return
	var n := points.size()
	var segments := n if _closed else n - 1
	var dense := PackedVector2Array()
	for i in segments:
		var a := points[i]
		var b := points[(i + 1) % n]
		var steps := maxi(1, int(a.distance_to(b) / 2.0))
		for k in steps:
			dense.append(a.lerp(b, float(k) / steps))
	if reverse:
		dense.reverse()
	for q in dense:
		_samples.append(Vector3(q.x, terrain.sample_height(q.x, q.y), q.y))


func _index_at_distance(metres: float) -> int:
	var walked := 0.0
	for i in _samples.size():
		var a := _samples[i]
		var b := _samples[(i + 1) % _samples.size()]
		walked += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		if walked >= metres:
			return i
	return 0


func _teleport_to(index: int) -> void:
	_cursor = index
	var here := _samples[index]
	var next := _samples[(index + 3) % _samples.size()]
	var heading := Vector3(next.x - here.x, 0.0, next.z - here.z)
	if heading.length_squared() < 0.001:
		heading = Vector3.FORWARD
	var pose := Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), Vector3(here.x, here.y + 0.3, here.z))
	# No collidable ground here (the streamer keeps this tile far): glide
	# kinematically from the road instead of forcing a near tile build —
	# that build cost ~40 ms and the streamer freed it again next frame
	# (a stuck kart just outside `near_distance` hitched the game forever).
	if terrain.streaming and not terrain.is_built_at(here.x, here.z):
		vehicle.set_physics_process(false)
		vehicle.velocity = Vector3.ZERO
		vehicle.global_transform = pose
		_gliding = true
		_glide_offset = 0.0
	else:
		if _gliding:
			_gliding = false
			vehicle.set_physics_process(true)
		vehicle.place(pose)
	_last_position = vehicle.global_position
	_last_progress_time = _now()


func _physics_process(delta: float) -> void:
	var pos := vehicle.global_position
	_lod_ticks += 1
	if _lod_ticks % 15 == 0:
		vehicle.set_lod_far(Lod.camera_distance(get_tree(), pos) > Lod.NPC_ANIMATE_RANGE)
	# Far from the player the terrain tile is not built: glide along the
	# road samples kinematically instead of falling through the world.
	if terrain.streaming and not terrain.is_built_at(pos.x, pos.z):
		_glide(delta)
		return
	elif _gliding:
		_gliding = false
		vehicle.set_physics_process(true)
		_teleport_to(_cursor)
		return
	# Advance the cursor to the closest sample within a window ahead.
	var n := _samples.size()
	var best := _cursor
	var best_d := INF
	for k in 24:
		var i := (_cursor + k) % n
		var s := _samples[i]
		var d := Vector2(pos.x - s.x, pos.z - s.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	_cursor = best
	# Target: a point look_ahead metres further along the road.
	var target_index := _cursor
	var walked := 0.0
	while walked < look_ahead:
		var a := _samples[target_index]
		var ni := (target_index + 1) % n
		if not _closed and ni <= target_index:
			break
		var b := _samples[ni]
		walked += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		target_index = ni
	var target := _samples[target_index]
	if lane_offset != 0.0:
		var after := _samples[(target_index + 1) % n]
		var dir := Vector2(after.x - target.x, after.z - target.z).normalized()
		target += Vector3(-dir.y, 0.0, dir.x) * lane_offset   # right-hand side of the road
	var to_target := Vector2(target.x - pos.x, target.z - pos.z)
	var forward := -vehicle.global_basis.z
	var fwd2 := Vector2(forward.x, forward.z).normalized()
	var angle := fwd2.angle_to(to_target.normalized())
	var steer := clampf(angle / deg_to_rad(35.0), -1.0, 1.0)

	# Speed: cruise, less in bends, brake for a nearby player ahead.
	var wanted := speed_factor * vehicle.definition.max_speed
	wanted *= lerpf(1.0, bend_speed, clampf(absf(angle) / deg_to_rad(60.0), 0.0, 1.0))
	var player := GameManager.get_player(0) as Node3D
	if player and caution_radius > 0.0:
		var focus := player
		var driver := (player as CharacterController).driver if player is CharacterController else null
		if driver and driver.is_driving and driver.vehicle:
			focus = driver.vehicle
		var rel := focus.global_position - pos
		if rel.length() < caution_radius and forward.dot(rel.normalized()) > 0.3:
			wanted = 0.0
	var speed := vehicle.get_speed()
	var throttle := clampf((wanted - speed) / (0.5 if racing else 4.0), -1.0, 1.0)
	if wanted <= 0.01 and speed < 0.5:
		throttle = 0.0
	vehicle.input.throttle = throttle
	vehicle.input.steer = steer
	if use_turbo and vehicle.turbo and absf(angle) < deg_to_rad(16.0) 			and speed > 0.5 * vehicle.definition.max_speed and wanted > speed - 1.0:
		vehicle.turbo.try_activate()

	# Fell off / stuck for a while: back on the road.
	if pos.distance_to(_last_position) > 0.5:
		_last_position = pos
		_last_progress_time = _now()
	elif wanted > 0.1 and _now() - _last_progress_time > 4.0:
		_teleport_to(_cursor)
	if pos.y < vehicle.fall_limit + 5.0 or (terrain and terrain.road_distance(pos.x, pos.z) > 25.0):
		_teleport_to(_cursor)


## Kinematic travel along the road (no physics, no terrain needed).
func _glide(delta: float) -> void:
	if not _gliding:
		_gliding = true
		vehicle.set_physics_process(false)
		vehicle.velocity = Vector3.ZERO
		_glide_offset = 0.0
	var n := _samples.size()
	_glide_offset += speed_factor * vehicle.definition.max_speed * 0.8 * delta
	while true:
		var a := _samples[_cursor]
		var b := _samples[(_cursor + 1) % n]
		var seg := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		if _glide_offset < seg or seg <= 0.0:
			var t := clampf(_glide_offset / maxf(seg, 0.001), 0.0, 1.0)
			var here := a.lerp(b, t)
			var heading := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if heading.length_squared() > 0.0001:
				vehicle.global_transform = Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP),
					Vector3(here.x, here.y + 0.3, here.z))
			break
		_glide_offset -= seg
		_cursor = (_cursor + 1) % n
	_last_position = vehicle.global_position
	_last_progress_time = _now()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
