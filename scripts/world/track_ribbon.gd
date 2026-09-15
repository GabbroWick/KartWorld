@tool
class_name TrackRibbon
extends StaticBody3D
## A kart track built from a few control points: a smooth ribbon (Catmull-
## Rom through `points`), `width` metres wide, with optional kerb walls on
## both edges so the kart stays on it, and trimesh collision that can never
## drift from the mesh. Ramps (`ramp_scene`) are dropped at the given
## fractions along the track, facing the driving direction.
##
## Data, not hand-placed geometry: a whole mountain road is a dozen points.

@export var points: PackedVector3Array = PackedVector3Array():
	set(value):
		points = value
		_request_rebuild()
@export_range(3.0, 30.0, 0.5) var width := 10.0:
	set(value):
		width = value
		_request_rebuild()
## Subdivisions per control segment (smoothness).
@export_range(1, 24, 1) var subdivisions := 8:
	set(value):
		subdivisions = value
		_request_rebuild()
@export_range(0.0, 3.0, 0.1) var kerb_height := 0.8:
	set(value):
		kerb_height = value
		_request_rebuild()
@export_range(0.0, 3.0, 0.1) var kerb_width := 0.6:
	set(value):
		kerb_width = value
		_request_rebuild()
@export var color := Color(0.36, 0.34, 0.36):
	set(value):
		color = value
		_request_rebuild()
@export var kerb_color := Color(0.9, 0.25, 0.2):
	set(value):
		kerb_color = value
		_request_rebuild()
@export var ramp_scene: PackedScene
## Fractions (0..1) along the track where a ramp is placed.
@export var ramp_at: PackedFloat32Array = PackedFloat32Array():
	set(value):
		ramp_at = value
		_request_rebuild()
@export var closed := false:
	set(value):
		closed = value
		_request_rebuild()

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var _curve: PackedVector3Array = PackedVector3Array()
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


## Dense centre-line samples (local space) after smoothing.
func get_curve() -> PackedVector3Array:
	return _curve


func length() -> float:
	var total := 0.0
	for i in _curve.size() - 1:
		total += _curve[i].distance_to(_curve[i + 1])
	return total


## Local pose at `fraction` (0..1) of the track: -Z along the driving direction.
func pose_at(fraction: float) -> Transform3D:
	var target := clampf(fraction, 0.0, 1.0) * length()
	var walked := 0.0
	for i in _curve.size() - 1:
		var a := _curve[i]
		var b := _curve[i + 1]
		var seg := a.distance_to(b)
		if walked + seg >= target or i == _curve.size() - 2:
			var t := clampf((target - walked) / maxf(seg, 0.001), 0.0, 1.0)
			var forward := (b - a)
			forward.y = 0.0
			if forward.length_squared() < 0.0001:
				forward = Vector3.FORWARD
			return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), a.lerp(b, t))
		walked += seg
	return Transform3D.IDENTITY


func rebuild() -> void:
	if not is_node_ready():
		return
	for child in get_children():
		if child.has_meta(&"track_ramp"):
			remove_child(child)
			child.queue_free()
	_curve = _smooth(points)
	if _curve.size() < 2:
		mesh_instance.mesh = null
		collision.shape = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var hw := width * 0.5
	var n := _curve.size()
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in n:
		var prev := _curve[maxi(i - 1, 0)]
		var next := _curve[mini(i + 1, n - 1)]
		var dir := next - prev
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(Vector3.UP).normalized()   # right of travel
		lefts.append(_curve[i] - side * hw)
		rights.append(_curve[i] + side * hw)
	for i in n - 1:
		# Road surface, seen from above: clockwise.
		_quad(st, faces, lefts[i], rights[i], rights[i + 1], lefts[i + 1], color)
		if kerb_height > 0.0:
			var up := Vector3.UP * kerb_height
			var lo := (lefts[i] - _curve[i]).normalized() * kerb_width
			var lo2 := (lefts[i + 1] - _curve[i + 1]).normalized() * kerb_width
			var ro := (rights[i] - _curve[i]).normalized() * kerb_width
			var ro2 := (rights[i + 1] - _curve[i + 1]).normalized() * kerb_width
			# Left kerb: inner face, top, outer face.
			_quad(st, faces, lefts[i], lefts[i + 1], lefts[i + 1] + up, lefts[i] + up, kerb_color)
			_quad(st, faces, lefts[i] + up, lefts[i + 1] + up, lefts[i + 1] + lo2 + up, lefts[i] + lo + up, kerb_color)
			_quad(st, faces, lefts[i] + lo + up, lefts[i + 1] + lo2 + up, lefts[i + 1] + lo2, lefts[i] + lo, kerb_color)
			# Right kerb.
			_quad(st, faces, rights[i + 1], rights[i], rights[i] + up, rights[i + 1] + up, kerb_color)
			_quad(st, faces, rights[i + 1] + up, rights[i] + up, rights[i] + ro + up, rights[i + 1] + ro2 + up, kerb_color)
			_quad(st, faces, rights[i + 1] + ro2 + up, rights[i] + ro + up, rights[i] + ro, rights[i + 1] + ro2, kerb_color)
		# Underside so the ribbon is not see-through from below.
		_quad(st, faces, lefts[i + 1] - Vector3.UP * 0.5, rights[i + 1] - Vector3.UP * 0.5, rights[i] - Vector3.UP * 0.5, lefts[i] - Vector3.UP * 0.5, color.darkened(0.3))
	st.generate_normals()
	var mesh := st.commit()
	var material := FlatMaterial.flat(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	if ramp_scene and not Engine.is_editor_hint():
		for f in ramp_at:
			var ramp := ramp_scene.instantiate() as Node3D
			ramp.set_meta(&"track_ramp", true)
			add_child(ramp)
			ramp.transform = pose_at(f)


func _smooth(control: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := control.size()
	if n < 2:
		return control
	if n == 2 or subdivisions <= 1:
		return control
	var segments := n if closed else n - 1
	for i in segments:
		var p0 := control[(i - 1 + n) % n] if closed else control[maxi(i - 1, 0)]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[(i + 2) % n] if closed else control[mini(i + 2, n - 1)]
		for k in subdivisions:
			var t := float(k) / subdivisions
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(control[0] if closed else control[n - 1])
	return out


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_tri(st, faces, a, b, c, tint)
	_tri(st, faces, a, c, d, tint)


func _tri(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	# Godot front faces: Plane(a, b, c).normal must point outward, which is
	# (c - a) x (b - a) -- the reverse of the textbook cross product.
	st.set_color(tint)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	faces.append(a)
	faces.append(c)
	faces.append(b)


func _request_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()
