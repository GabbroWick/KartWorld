extends Node
## Headless test for the kart (Phase 3).
##
## Run:  godot --headless res://tools/tests/test_kart_runner.tscn
##
## Drives the movement gym with simulated input and checks: the kart exists as
## a separate entity, summoning brings it in front of the player, interact
## enters and leaves it, the camera re-targets, driving/steering/braking/
## reversing, turbo, jump, wall collision, and losing the kart off the world.

const SCENE := "res://scenes/dev/movement_gym.tscn"

var _failures: Array[String] = []
var _checks := 0
var _player: CharacterController
var _kart: VehicleController
var _camera_rig: ThirdPersonCamera


func _ready() -> void:
	_run()


func _run() -> void:
	# Never let the player's real progress (triple jump!) leak into a suite.
	ProgressionManager.save_path = "user://test_scratch_save.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	var scene := (load(SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	_camera_rig = scene.get_node("CameraRig")
	await _steps(30)

	_player = GameManager.get_player(0) as CharacterController
	_kart = scene.get("vehicle") as VehicleController
	if _player == null or _kart == null:
		_fail("scene did not spawn a player and a vehicle")
		_finish()
		return

	_test_setup()
	await _test_summon()
	await _test_enter()
	await _test_drive()
	await _test_wheels()
	await _test_steer()
	await _test_brake_and_reverse()
	await _test_camera_align()
	await _test_turbo()
	await _test_bump()
	await _test_jump()
	await _test_wall()
	await _test_kerb()
	await _test_exit()
	await _test_fall_out()
	_finish()


func _test_setup() -> void:
	_check(_kart.get_parent() != _player, "kart is not a child of the character")
	_check(_kart.definition.display_name == "VEHICLE_KART", "kart uses the basic_kart definition")
	_check(_kart.visual_root.get_children().filter(func(c: Node) -> bool: return c.name != "Seat" and c.name != "TurboFlames").size() == 1, "kart visual instantiated")
	_check(_kart.abilities.has(&"turbo") and _kart.abilities.has(&"vehicle_jump"),
		"kart starts with turbo and jump abilities")
	_check(_kart.turbo != null, "turbo ability node is registered")
	_check(_kart.health.current_health == _kart.definition.max_health, "kart health initialised")
	_check(not _kart.is_driven(), "nobody is driving at start")
	_check(_player.driver.vehicle == _kart, "player's DriverComponent knows its kart")
	_check(_player.global_position.distance_to(_kart.global_position) > 3.0,
		"kart starts parked away from the player (%.1fm)"
		% _player.global_position.distance_to(_kart.global_position))


func _test_summon() -> void:
	# Face the character down -Z, then summon: kart must appear ahead, grounded.
	_camera_rig.set_yaw(0.0)
	await _hold(&"move_forward", 10)
	await _steps(20)
	var before := _kart.global_position
	await _press(InputActions.SUMMON_KART)
	await _steps(30)
	var offset := _kart.global_position - _player.global_position
	_check(_kart.global_position.distance_to(before) > 1.0, "summon moved the kart")
	_check(offset.z < -2.0 and absf(offset.x) < 1.5,
		"kart appears in front of the character (offset %s)" % offset)
	_check(_kart.is_on_floor(), "summoned kart rests on the ground")
	_check(_player.driver.is_vehicle_in_reach(), "summoned kart is within enter range")


func _test_enter() -> void:
	await _press(InputActions.INTERACT)
	await _steps(2)
	_check(_player.driver.is_driving, "interact near the kart enters it")
	_check(_kart.driver == _player, "kart knows its driver")
	_check(not _player.visible, "character is hidden while driving")
	_check(_camera_rig.target == _kart, "camera follows the kart")
	_check(_kart.input.reads_local_device, "kart reads the local device while driven")


func _test_drive() -> void:
	var start := _kart.global_position
	await _hold(InputActions.ACCELERATE, 120)
	var travelled := start.distance_to(_kart.global_position)
	_check(_kart.get_speed() > _kart.definition.max_speed * 0.8,
		"kart reaches near max speed (%.1f of %.1f m/s)" % [_kart.get_speed(), _kart.definition.max_speed])
	_check(travelled > 15.0, "kart moved forward (%.1fm in 2s)" % travelled)
	_check(_player.global_position.distance_to(_kart.global_position) < 0.5,
		"character rides along with the kart")
	_check(_kart.is_on_floor(), "kart stays grounded on flat ground")


func _test_wheels() -> void:
	var visual := _kart.visual_root.get_children().filter(func(c: Node) -> bool: return c is AiVehicleVisual)
	_check(visual.size() == 1, "kart uses the AI visual with procedural wheels")
	if visual.is_empty():
		return
	var ai := visual[0] as AiVehicleVisual
	_check(ai._spinners.size() == 4 and ai._steerers.size() == 2, "four rolling wheels, two steering (%d/%d)" % [ai._spinners.size(), ai._steerers.size()])
	# Roll direction: a short forward push must rotate the tyres so the top
	# moves forward (+X rotation inside the flipped model: y axis tips to +Z).
	var spin := ai._spinners[0]
	spin.basis = Basis.IDENTITY
	await _hold(InputActions.ACCELERATE, 3)
	_check(spin.basis.y.z > 0.0 and spin.basis.y.z < 0.99, "tyres roll forward when driving forward (y.z %.2f)" % spin.basis.y.z)
	await _hold(InputActions.BRAKE, 40)
	await _steps(10)
	# Driver: seated pose reaches for the wheel (hands well ahead of hips).
	var driver_visual := _kart.seat.get_children().filter(func(c: Node) -> bool: return c is RiggedCharacterVisual)
	if driver_visual.size() == 1:
		var skeleton: Skeleton3D = (driver_visual[0] as Node).find_children("*", "Skeleton3D", true, false)[0]
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_LeftHand")).origin
		var hips := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips")).origin
		_check(hand.z - hips.z > 0.2 and hand.y > hips.y + 0.15, "driver's hands reach forward to the wheel (dz %.2f, dy %.2f)" % [hand.z - hips.z, hand.y - hips.y])


func _test_steer() -> void:
	var yaw_before := _kart.global_rotation.y
	Input.action_press(InputActions.ACCELERATE)
	await _hold(&"move_right", 30)
	var ai := _kart.visual_root.get_children().filter(func(c: Node) -> bool: return c is AiVehicleVisual)
	if ai.size() == 1:
		_check((ai[0] as AiVehicleVisual)._steerers[0].rotation.y < -0.2, "front wheels yaw with the steering (%.2f rad)" % (ai[0] as AiVehicleVisual)._steerers[0].rotation.y)
	Input.action_release(InputActions.ACCELERATE)
	var turned := wrapf(_kart.global_rotation.y - yaw_before, -PI, PI)
	_check(turned < -0.3, "steering right turns the kart clockwise (%.2f rad)" % turned)
	await _steps(10)


func _test_camera_align() -> void:
	# Kart is stopped here. Knock the camera off the heading, give no look
	# input: it must swing back behind the kart on its own.
	_check(_camera_rig.auto_align, "auto align is on at the wheel")
	var kart_yaw := _kart.global_rotation.y
	_camera_rig.set_yaw(kart_yaw + 1.2)
	await _steps(120)
	var gap_after := absf(wrapf(_camera_rig.get_yaw() - kart_yaw, -PI, PI))
	_check(gap_after < 0.15, "camera settles behind the kart (1.20 -> %.2f rad off heading)" % gap_after)
	# Looking around overrides it while the stick is held.
	await _hold(InputActions.CAMERA_RIGHT, 20)
	var gap_look := absf(wrapf(_camera_rig.get_yaw() - kart_yaw, -PI, PI))
	_check(gap_look > 0.4, "manual look still moves the camera off the heading (%.2f rad)" % gap_look)

	# Reversing: the camera must swing round to the front and look at the tail.
	_kart.place(Transform3D(Basis.IDENTITY, Vector3(-20.0, 0.3, 8.0)))
	_camera_rig.set_yaw(0.0)
	await _steps(5)
	Input.action_press(InputActions.BRAKE)
	await _steps(110)
	var reverse_gap := absf(wrapf(_camera_rig.get_yaw() - (_kart.global_rotation.y + PI), -PI, PI))
	_check(_kart.get_speed() < -1.0, "kart is reversing (%.1f m/s)" % _kart.get_speed())
	_check(reverse_gap < 0.2, "camera settles in front while reversing (%.2f rad off)" % reverse_gap)
	Input.action_release(InputActions.BRAKE)
	await _hold(InputActions.ACCELERATE, 40)
	await _steps(80)
	var forward_gap := absf(wrapf(_camera_rig.get_yaw() - _kart.global_rotation.y, -PI, PI))
	_check(forward_gap < 0.2, "camera swings back behind once driving forward (%.2f rad off)" % forward_gap)


func _test_brake_and_reverse() -> void:
	_check(_kart.get_speed() > 2.0, "kart is still rolling before braking (%.1f)" % _kart.get_speed())
	await _hold(InputActions.BRAKE, 40)
	_check(_kart.get_speed() < 0.0, "holding brake stops then reverses (%.1f m/s)" % _kart.get_speed())
	_check(_kart.get_speed() > -_kart.definition.reverse_speed - 0.5,
		"reverse is capped at reverse_speed")
	await _steps(60)
	_check(absf(_kart.get_speed()) < 0.3, "kart coasts to a stop (%.2f)" % _kart.get_speed())


func _test_turbo() -> void:
	# Longest clear straight in the arena: along x=24 from z=28 to z=-28.
	# Get up to normal top speed first, then hold the turbo.
	_kart.place(Transform3D(Basis.IDENTITY, Vector3(24.0, 0.3, 28.0)))
	await _steps(10)
	var hud: CanvasLayer = get_tree().root.find_child("GameHUD", true, false)
	if hud:
		_check(hud.turbo_gauge.visible, "turbo gauge shown at the wheel")
	_check(is_equal_approx(_kart.turbo.charge, 1.0), "turbo gauge starts full")
	Input.action_press(InputActions.ACCELERATE)
	await _steps(80)
	var normal_top := _kart.get_speed()
	Input.action_press(InputActions.TURBO)
	await _steps(3)
	_check(_kart.turbo.is_active, "holding turbo boosts")
	_check(_kart.turbo_flames.emitting, "flames come out of the back while boosting")
	await _steps(20)
	var boosted := _kart.get_speed()
	_check(boosted > normal_top * 1.25,
		"turbo raises speed clearly (%.1f -> %.1f m/s)" % [normal_top, boosted])
	_check(_kart.turbo.charge < 0.95, "gauge drains while boosting (%.2f)" % _kart.turbo.charge)
	if hud:
		_check(hud.turbo_gauge.charge < 0.95 and hud.turbo_gauge.boosting, "HUD gauge follows the turbo")
	Input.action_release(InputActions.TURBO)
	Input.action_release(InputActions.ACCELERATE)
	Input.action_press(InputActions.BRAKE)
	await _steps(3)
	_check(not _kart.turbo.is_active, "releasing turbo stops the boost")
	_check(not _kart.turbo_flames.emitting, "flames stop with the boost")
	var partial := _kart.turbo.charge
	await _steps(40)
	Input.action_release(InputActions.BRAKE)
	_check(_kart.turbo.charge > partial, "gauge refills when released (%.2f -> %.2f)" % [partial, _kart.turbo.charge])
	# Drain it completely (standing still, the gym is small): it must cut
	# out and refuse to relight while the button stays held.
	Input.action_press(InputActions.TURBO)
	await _steps(int(_kart.definition.turbo_duration * 60.0) + 10)
	_check(not _kart.turbo.is_active and _kart.turbo.charge < 0.1, "an emptied gauge ends the boost (%.2f)" % _kart.turbo.charge)
	await _steps(int(_kart.definition.turbo_cooldown * 30.0))
	_check(not _kart.turbo.is_active, "holding turbo on an empty gauge does not relight it")
	Input.action_release(InputActions.TURBO)
	await _steps(int(_kart.definition.turbo_cooldown * 60.0) + 10)
	_check(_kart.turbo.charge > 0.95, "gauge refills to full (%.2f)" % _kart.turbo.charge)
	await _steps(30)


func _test_bump() -> void:
	# A parked kart in the way is solid and gets shoved along, not crossed.
	var other := (load("res://scenes/vehicles/vehicle.tscn") as PackedScene).instantiate() as VehicleController
	other.definition = _kart.definition
	_kart.get_parent().add_child(other)
	_kart.place(Transform3D(Basis.IDENTITY, Vector3(24.0, 0.3, 20.0)))
	other.place(Transform3D(Basis.IDENTITY, Vector3(24.0, 0.3, 8.0)))
	await _steps(10)
	var other_start := other.global_position
	Sfx.clear_log()
	Input.action_press(InputActions.ACCELERATE)
	await _steps(75)
	Input.action_release(InputActions.ACCELERATE)
	await _steps(30)
	var pushed := other.global_position.distance_to(other_start)
	_check(pushed > 1.0, "ramming a parked kart shoves it along (%.1f m)" % pushed)
	_check(_kart.global_position.distance_to(other.global_position) > 1.0, "karts do not overlap after the hit (%.1f m apart)" % _kart.global_position.distance_to(other.global_position))
	_check(Sfx.played.has(&"hit"), "a kart bump makes a sound")
	other.queue_free()
	await _steps(5)


func _test_jump() -> void:
	# Park facing +X on open ground so the jump has room.
	_kart.place(Transform3D(Basis.from_euler(Vector3(0, -PI / 2, 0)), Vector3(-20.0, 0.3, 12.0)))
	await _steps(20)
	var ground_y := _kart.global_position.y
	await _press(InputActions.JUMP)
	var peak := ground_y
	for i in 120:
		await _steps(1)
		peak = maxf(peak, _kart.global_position.y)
		if _kart.is_on_floor() and i > 5:
			break
	_check(peak - ground_y > _kart.definition.jump_height * 0.7,
		"kart jump reaches %.2fm (definition %.1f)" % [peak - ground_y, _kart.definition.jump_height])
	_check(_kart.is_on_floor(), "kart lands again")


func _test_wall() -> void:
	# The arena wall is 10m wide at z=-8 (x -11..-1). Drive into it along -Z.
	_kart.place(Transform3D(Basis.IDENTITY, Vector3(-6.0, 0.3, -2.0)))
	await _steps(10)
	await _hold(InputActions.ACCELERATE, 90)
	_check(_kart.global_position.z > -7.8,
		"wall stops the kart (z %.2f, wall face at -7.7)" % _kart.global_position.z)
	_check(_kart.get_speed() < 1.0, "speed is killed by the impact (%.1f)" % _kart.get_speed())
	await _steps(10)


func _test_kerb() -> void:
	# Kerb at z=22, top y=0.4. Drive onto it from z=28 heading -Z.
	_kart.place(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 28.0)))
	await _steps(10)
	await _hold(InputActions.ACCELERATE, 60)
	_check(_kart.global_position.z < 22.0 and _kart.global_position.y > 0.25,
		"kart rolls over a 0.4 m kerb (z %.1f, y %.2f)" % [_kart.global_position.z, _kart.global_position.y])
	await _steps(30)


func _test_exit() -> void:
	await _press(InputActions.INTERACT)
	await _steps(5)
	_check(not _player.driver.is_driving, "interact while driving leaves the kart")
	_check(_kart.driver == null, "kart has no driver after exit")
	_check(_player.visible, "character is visible again")
	_check(_camera_rig.target == _player, "camera follows the character again")
	_check(not _camera_rig.auto_align, "auto align is off on foot")
	_camera_rig.set_yaw(1.0)
	await _steps(90)
	_check(absf(_camera_rig.get_yaw() - 1.0) < 0.01, "on foot the camera stays where the player put it")
	var gap := _player.global_position.distance_to(_kart.global_position)
	_check(gap > 1.0 and gap < 4.0, "character stands beside the kart (%.1fm)" % gap)
	await _steps(30)
	_check(_player.is_on_floor(), "character is on the ground after leaving")
	await _hold(&"move_forward", 20)
	_check(_player.velocity.length() > 0.5 or _player.global_position.z < _kart.global_position.z + 3.0,
		"character can walk again after leaving")
	await _steps(20)


func _test_fall_out() -> void:
	# Drop the kart into the void: player must not be stranded.
	await _press(InputActions.SUMMON_KART)
	await _steps(10)
	await _press(InputActions.INTERACT)
	await _steps(2)
	_check(_player.driver.is_driving, "back in the kart for the fall test")
	_kart.global_position = Vector3(0.0, -40.0, 0.0)
	await _steps(5)
	_check(not _player.driver.is_driving, "falling off the world ejects the driver")
	_check(_player.global_position.distance_to(_player.spawn_transform.origin) < 1.5,
		"character respawns at the spawn point")
	_check(_kart.global_position.y > -5.0 and
		_kart.global_position.distance_to(_player.spawn_transform.origin) < 6.0,
		"kart is parked back near the spawn")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _steps(frames)
	Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _fail(description: String) -> void:
	_check(false, description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
