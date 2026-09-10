class_name StepUp
extends RefCounted
## Lets a CharacterBody3D walk or drive over small ledges (kerbs, plinths,
## stairs) that its collision shape would otherwise bump into.
##
## Godot's move_and_slide only climbs what the shape's rounded bottom can slide
## over. This probes: is the way ahead blocked? is there room to go up by
## `max_height`? is it free ahead from up there? is there floor within
## `max_height` below that point? If so the body is lifted to that floor and
## the normal move continues. Called by the motors before move_and_slide.

const FORWARD_PROBE := 0.06
const WALKABLE_NORMAL_Y := 0.7


## Returns true when the body was lifted onto a step.
static func try_step(body: CharacterBody3D, horizontal_motion: Vector3, max_height: float) -> bool:
	if max_height <= 0.0 or not body.is_on_floor():
		return false
	if horizontal_motion.length_squared() < 0.000001:
		return false
	var transform := body.global_transform
	# Nothing in the way: no step needed.
	if not body.test_move(transform, horizontal_motion):
		return false
	var up := Vector3.UP * max_height
	# No headroom.
	if body.test_move(transform, up):
		return false
	transform.origin += up
	var probe := horizontal_motion + horizontal_motion.normalized() * FORWARD_PROBE
	# Still blocked from higher up: a real wall.
	if body.test_move(transform, probe):
		return false
	transform.origin += probe
	var collision := KinematicCollision3D.new()
	# No floor within reach below: a ledge to fall off, not a step to climb.
	if not body.test_move(transform, -up, collision):
		return false
	if collision.get_normal().y < WALKABLE_NORMAL_Y:
		return false
	var rise := max_height - collision.get_travel().length()
	if rise <= 0.001:
		return false
	# Land on the step, not on its edge: the forward probe was verified free,
	# so the body moves up and onto it in one go. Otherwise floor snapping can
	# pull a long body (the kart) back down before it has cleared the lip.
	body.global_position += Vector3.UP * (rise + 0.01) + probe
	return true
