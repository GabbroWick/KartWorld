extends Node3D
## Character preview: one model on a neutral floor, the game's lighting recipe,
## a slow turntable. Checks scale, orientation, materials and fill light
## before a model goes into a CharacterDefinition.
##
## Run:  godot --path . res://scenes/dev/character_preview.tscn
##       godot --path . res://scenes/dev/character_preview.tscn -- <res_path.glb|.tscn> [height]
## Or set `model` in the inspector. `-- ... shot.png` also saves a screenshot.

## GLB or a visual scene (anything Node3D). GLB gets flip_forward + flatten
## through MeshyCharacterVisual so it matches the in-game wrapper.
@export var model: PackedScene
@export var flip_forward := true
@export var flatten_materials := true
@export var auto_ground := true
@export var turntable_speed := 0.6
## Reference height marker (m): a thin ring at this height, 0 = none.
@export var reference_height := 1.35

@onready var pivot: Node3D = $Pivot
@onready var height_marker: MeshInstance3D = $HeightMarker
@onready var info: Label = $UI/Info

var _instance: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := ""
	for a in args:
		if a.ends_with(".png"):
			shot = a
		elif a.ends_with(".glb") or a.ends_with(".tscn") or a.ends_with(".gltf"):
			model = load(a)
		elif a.is_valid_float():
			reference_height = float(a)
	_spawn()
	height_marker.visible = reference_height > 0.0
	height_marker.position.y = reference_height
	if shot != "":
		_screenshot(shot)


func _spawn() -> void:
	if is_instance_valid(_instance):
		_instance.queue_free()
	if model == null:
		info.text = "Nessun modello: passa un .glb/.tscn come argomento o imposta `model`."
		return
	var raw := model.instantiate() as Node3D
	if raw.has_method(&"animate"):
		_instance = raw
	else:
		# Wrap a bare GLB the same way the game does.
		var wrapper := MeshyCharacterVisual.new()
		wrapper.model = model
		wrapper.flip_forward = flip_forward
		wrapper.flatten_materials = flatten_materials
		wrapper.auto_ground = auto_ground
		wrapper.motion = 0.0
		raw.free()
		_instance = wrapper
	pivot.add_child(_instance)
	await get_tree().process_frame
	var aabb := _measure(_instance)
	info.text = "%s\naltezza %.2f m  larghezza %.2f m  profondità %.2f m\nmin y %.2f (piedi a 0?)  la camera guarda il fronte (-Z dopo flip_forward)" % [
		model.resource_path, aabb.size.y, aabb.size.x, aabb.size.z, aabb.position.y]


func _process(delta: float) -> void:
	pivot.rotate_y(turntable_speed * delta)
	if _instance and _instance.has_method(&"animate"):
		_instance.call(&"animate", delta, 0.0, true)


func _measure(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		var box := m.global_transform * m.get_aabb()
		box = AABB(box.position - pivot.global_position, box.size)
		result = box if first else result.merge(box)
		first = false
	return result


func _screenshot(path: String) -> void:
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(path)
	print("Screenshot saved: ", path)
	get_tree().quit(0)
