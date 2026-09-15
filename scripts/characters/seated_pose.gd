class_name SeatedPose
extends Node
## Procedural "sitting at the wheel" pose for a Mixamo rig, applied on top
## of whatever clip is playing (idle): thighs forward, knees bent, arms
## reaching forward to the wheel, a little forward lean. A child of the
## Skeleton3D with a late process priority, so it rewrites the bone poses
## after the AnimationPlayer every frame (a SkeletonModifier3D ran before
## the imported FBX's AnimationPlayer and was overwritten).
##
## Rotations are applied in skeleton space around each bone's global pose,
## so the rig's own bone axes never matter (Mixamo bone axes are odd).
## Fallback for rigs without a real `drive` clip; a clip always wins.

@export_range(0.0, 120.0, 1.0) var thigh_degrees := 85.0
@export_range(0.0, 140.0, 1.0) var knee_degrees := 80.0
## Arms swing forward from the T-pose by this much (about the vertical).
@export_range(0.0, 120.0, 1.0) var arm_forward_degrees := 85.0
## ...and drop toward the wheel from horizontal.
@export_range(-60.0, 60.0, 1.0) var arm_down_degrees := 0.0
@export_range(0.0, 90.0, 1.0) var elbow_degrees := 15.0
@export_range(0.0, 45.0, 1.0) var lean_degrees := 8.0

var _bones: Dictionary = {}
var _touched: Dictionary = {}   # role -> bone index


func _find(skeleton: Skeleton3D, suffix: String) -> int:
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n.ends_with(suffix):
			return i
	return -1


var active := false


func _ready() -> void:
	process_priority = 100


func _process(_delta: float) -> void:
	if not active:
		return
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		return
	if _bones.is_empty():
		for role in ["Spine", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]:
			_bones[role] = _find(skeleton, role)
	# The rig faces +Z in skeleton space (toes point +Z).
	var f := 1.0
	_touched.clear()
	_rotate(skeleton, "Spine", Vector3.RIGHT, f * deg_to_rad(lean_degrees), false)
	# Legs: thighs up to horizontal (forward), knees back down.
	for side in ["Left", "Right"]:
		_rotate(skeleton, side + "UpLeg", Vector3.RIGHT, -f * deg_to_rad(thigh_degrees))
		_rotate(skeleton, side + "Leg", Vector3.RIGHT, f * deg_to_rad(knee_degrees))
	# Arms: from sideways (+/-X) toward forward, then a little down.
	_rotate(skeleton, "LeftArm", Vector3.UP, -f * deg_to_rad(arm_forward_degrees))
	_rotate(skeleton, "RightArm", Vector3.UP, f * deg_to_rad(arm_forward_degrees))
	_rotate(skeleton, "LeftArm", Vector3.RIGHT, f * deg_to_rad(arm_down_degrees))
	_rotate(skeleton, "RightArm", Vector3.RIGHT, f * deg_to_rad(arm_down_degrees))
	_rotate(skeleton, "LeftForeArm", Vector3.UP, f * deg_to_rad(elbow_degrees))
	_rotate(skeleton, "RightForeArm", Vector3.UP, -f * deg_to_rad(elbow_degrees))


## Rotates a bone about `axis` (skeleton space) through its own origin, by
## rewriting its local pose: L' = P^-1 R P L (P = parent global pose).
## Children follow because only the local pose is stored.
func _rotate(skeleton: Skeleton3D, role: String, axis: Vector3, angle: float, from_rest := true) -> void:
	var index: int = _bones.get(role, -1)
	if index < 0 or is_zero_approx(angle):
		return
	var parent := skeleton.get_bone_parent(index)
	var p := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var r := Basis(axis, angle)
	# Limbs start from the rest (T-)pose, so the angles mean the same thing
	# whatever the idle clip does with the arms; the spine keeps breathing.
	# Chained rotations on one bone build on the previous write this frame.
	var key := role
	var base: Quaternion
	if _touched.has(key):
		base = skeleton.get_bone_pose_rotation(index)
	elif from_rest:
		base = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	else:
		base = skeleton.get_bone_pose_rotation(index)
	_touched[key] = true
	var new_local := p.inverse() * r * p * Basis(base)
	skeleton.set_bone_pose_rotation(index, new_local.get_rotation_quaternion())
