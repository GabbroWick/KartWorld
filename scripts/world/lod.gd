class_name Lod
extends RefCounted
## Distance culling for phones: props stop drawing beyond the quality's
## range (`Settings.prop_range()`), far NPCs stop animating their rigs.
## Props register themselves (`register`) so a quality change re-applies.

const GROUP := &"lod_prop"
## Beyond this an NPC's rig (AnimationPlayer, skeleton) is frozen.
const NPC_ANIMATE_RANGE := 60.0
## Beyond this an NPC kart's engine hum is silenced.
const ENGINE_SOUND_RANGE := 45.0


static func register(node: Node) -> void:
	node.add_to_group(GROUP)
	apply_range(node, Settings.prop_range())


## Register after the node built its meshes (visuals spawn in `_ready`).
static func register_deferred(node: Node) -> void:
	(func() -> void:
		if is_instance_valid(node) and node.is_inside_tree():
			register(node)).call_deferred()


## Sets `visibility_range_end` on every mesh under `node` (0 = always).
static func apply_range(node: Node, range_end: float) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.visibility_range_end = range_end
		geometry.visibility_range_end_margin = 8.0 if range_end > 0.0 else 0.0
	for child in node.get_children():
		apply_range(child, range_end)


## Distance from the active camera (or the player) to `at`.
static func camera_distance(tree: SceneTree, at: Vector3) -> float:
	var camera := tree.root.get_camera_3d() if tree and tree.root else null
	if camera:
		return camera.global_position.distance_to(at)
	return 0.0
