class_name SwingPose
extends Node
## Procedural weapon attack for a Mixamo rig: an overhead swing (club,
## sword) or a throw (boomerang), driven on the right arm over the
## attack window, on top of whatever clip plays. A late-process child
## of the Skeleton3D like SeatedPose. `start(duration, style)`.

var active := false
var _time := 0.0
var _duration := 0.35
var _style := &"swing"
var _bones: Dictionary = {}
var _touched: Dictionary = {}


func _ready() -> void:
	process_priority = 101


func start(duration: float, style: StringName) -> void:
	_duration = maxf(duration, 0.1)
	_style = style
	_time = 0.0
	active = true


func _process(delta: float) -> void:
	if not active:
		return
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		return
	if _bones.is_empty():
		for role in ["Spine", "RightShoulder", "RightArm", "RightForeArm"]:
			_bones[role] = _find(skeleton, role)
	_time += delta
	var t := clampf(_time / _duration, 0.0, 1.0)
	if _time >= _duration + 0.12:
		active = false
		return
	_touched.clear()
	# The rig faces +Z. Wind-up (arm back and up), then a fast swing down
	# and forward, then settle.
	var wind := smoothstep(0.0, 0.25, t)
	var strike := smoothstep(0.25, 0.6, t)
	var settle := smoothstep(0.8, 1.0, minf(_time / (_duration + 0.12), 1.0))
	if _style == &"throw":
		# Arm back, then whipped forward horizontally.
		var back := deg_to_rad(-110.0) * wind * (1.0 - strike)
		var fwd := deg_to_rad(80.0) * strike * (1.0 - settle)
		_rotate(skeleton, "RightArm", Vector3.UP, deg_to_rad(60.0) * (1.0 - settle))
		_rotate(skeleton, "RightArm", Vector3.RIGHT, back + fwd)
		_rotate(skeleton, "RightForeArm", Vector3.UP, deg_to_rad(25.0) * (1.0 - settle))
		_rotate(skeleton, "Spine", Vector3.UP, deg_to_rad(-25.0 * wind * (1.0 - strike) + 20.0 * strike * (1.0 - settle)), false)
	else:
		# Arm raised behind the head, then chopped down in front.
		var raise := deg_to_rad(-150.0) * wind * (1.0 - strike * 0.9)
		var chop := deg_to_rad(70.0) * strike * (1.0 - settle)
		_rotate(skeleton, "RightArm", Vector3.UP, deg_to_rad(75.0) * (1.0 - settle))
		_rotate(skeleton, "RightArm", Vector3.RIGHT, raise + chop)
		_rotate(skeleton, "RightForeArm", Vector3.RIGHT, deg_to_rad(-40.0) * wind * (1.0 - strike) + deg_to_rad(15.0) * strike * (1.0 - settle))
		_rotate(skeleton, "Spine", Vector3.RIGHT, deg_to_rad(-10.0 * wind * (1.0 - strike) + 18.0 * strike * (1.0 - settle)), false)


func _find(skeleton: Skeleton3D, suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(suffix):
			return i
	return -1


## Same maths as SeatedPose: rotate about a skeleton-space axis by editing
## the local pose (limbs from the rest pose, the spine from the clip).
func _rotate(skeleton: Skeleton3D, role: String, axis: Vector3, angle: float, from_rest := true) -> void:
	var index: int = _bones.get(role, -1)
	if index < 0 or is_zero_approx(angle):
		return
	var parent := skeleton.get_bone_parent(index)
	var p := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var base: Quaternion
	if _touched.has(role):
		base = skeleton.get_bone_pose_rotation(index)
	elif from_rest:
		base = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	else:
		base = skeleton.get_bone_pose_rotation(index)
	_touched[role] = true
	var new_local := p.inverse() * Basis(axis, angle) * p * Basis(base)
	skeleton.set_bone_pose_rotation(index, new_local.get_rotation_quaternion())
