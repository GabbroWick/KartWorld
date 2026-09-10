class_name RiggedCharacterVisual
extends MeshyCharacterVisual
## A rigged character (Mixamo auto-rig + clips) behind the same
## `animate(delta, speed_ratio, grounded)` contract.
##
## `model` is the "with skin" FBX: skeleton, mesh and the idle clip. The other
## clips are Mixamo "without skin" FBX files that share the skeleton; their
## single animation is copied into the model's AnimationPlayer at start-up,
## root motion stripped and looping set, so the scene never depends on the
## editor having merged anything. The base class still grounds, flips and
## flattens the model and adds a light lean/squash on top of the clips.

const MIXAMO_CLIP := &"mixamo_com"

@export var walk_clip: PackedScene
@export var run_clip: PackedScene
@export var jump_clip: PackedScene
@export var fall_clip: PackedScene
@export var attack_clip: PackedScene
@export var hurt_clip: PackedScene
## The character's run speed (m/s) that `speed_ratio` = 1 stands for.
@export_range(1.0, 30.0, 0.5) var reference_speed := 10.0
## Ground speed baked into the walk / run clips before root motion was
## stripped (m/s), so the feet stop sliding.
@export_range(0.1, 10.0, 0.05) var walk_clip_speed := 1.0
@export_range(0.1, 15.0, 0.05) var run_clip_speed := 3.3
## Below this ratio the walk clip plays, above it the run clip.
@export_range(0.05, 0.95, 0.05) var run_threshold := 0.45
@export_range(0.5, 4.0, 0.05) var max_speed_scale := 2.2
@export_range(0.0, 1.0, 0.01) var blend_time := 0.15

var player: AnimationPlayer
var _current := &""
var _was_airborne := false
var _action := &""


func _ready() -> void:
	super()
	if _instance == null:
		return
	player = _instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_error("RiggedCharacterVisual: model has no AnimationPlayer.")
		return
	var library := player.get_animation_library(&"")
	_register(library, &"idle", library.get_animation(MIXAMO_CLIP), true)
	library.remove_animation(MIXAMO_CLIP)
	for entry in [[&"walk", walk_clip, true], [&"run", run_clip, true], [&"jump", jump_clip, false], [&"fall", fall_clip, true], [&"attack", attack_clip, false], [&"hurt", hurt_clip, false]]:
		var scene: PackedScene = entry[1]
		if scene == null:
			continue
		var clip := _extract_clip(scene)
		if clip:
			_register(library, entry[0], clip, entry[2])
	_play(&"idle", 1.0)


## One-shot clips (attack, hurt) take over until they finish.
func play_action(action: StringName, speed_scale: float = 1.0) -> bool:
	if player == null or not player.has_animation(action):
		return false
	_action = action
	player.speed_scale = speed_scale
	player.play(action, blend_time * 0.5)
	_current = action
	return true


func has_action(action: StringName) -> bool:
	return player != null and player.has_animation(action)


func animate(delta: float, speed_ratio: float, grounded: bool) -> void:
	# Real clips do the walking; keep only a touch of lean and the land squash.
	super.animate(delta, speed_ratio, grounded)
	if player == null:
		return
	if _action != &"":
		if player.is_playing() and player.current_animation == _action:
			return
		_action = &""
	var speed := speed_ratio * reference_speed
	if not grounded:
		var clip := &"jump" if (not _was_airborne and player.has_animation(&"jump")) else &"fall"
		if _current == &"jump" and player.is_playing():
			clip = &"jump"
		_play(clip, 1.0)
	elif speed_ratio < 0.05:
		_play(&"idle", 1.0)
	elif speed_ratio < run_threshold and player.has_animation(&"walk"):
		_play(&"walk", clampf(speed / walk_clip_speed, 0.6, max_speed_scale))
	else:
		_play(&"run", clampf(speed / run_clip_speed, 0.6, max_speed_scale))
	_was_airborne = not grounded


func _play(clip: StringName, speed_scale: float) -> void:
	if not player.has_animation(clip):
		return
	player.speed_scale = speed_scale
	if _current == clip and player.is_playing():
		return
	player.play(clip, blend_time)
	_current = clip


func _register(library: AnimationLibrary, clip_name: StringName, animation: Animation, loop: bool) -> void:
	var copy := animation.duplicate() as Animation
	copy.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_strip_root_motion(copy)
	library.add_animation(clip_name, copy)


## The clip's own AnimationPlayer holds exactly one animation.
func _extract_clip(scene: PackedScene) -> Animation:
	var instance := scene.instantiate()
	var clip_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var result: Animation = null
	if clip_player:
		for library_name in clip_player.get_animation_library_list():
			var library := clip_player.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				result = library.get_animation(animation_name)
				break
			if result:
				break
	instance.free()
	return result


## Mixamo clips move the hips forward; the character controller already moves
## the body, so keep the hips' first horizontal position on every key.
func _strip_root_motion(animation: Animation) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track)).ends_with("Hips"):
			continue
		if animation.track_get_key_count(track) == 0:
			continue
		var first: Vector3 = animation.track_get_key_value(track, 0)
		for key in animation.track_get_key_count(track):
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, Vector3(first.x, value.y, first.z))
