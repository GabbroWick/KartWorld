@tool
class_name Ramp
extends StaticBody3D
## A hump to jump from: an up-slope, a flat top and a (steeper) drop, in one
## mesh with a matching convex collider so the two can never drift apart.
## Vehicles drive toward -Z: the up-slope faces +Z (behind), the drop is in
## front. With `down_length` = 0 it is a plain wedge with a vertical back.
##
## Data, not art: length/height/width per instance. Wood look by default.

@export_range(1.0, 30.0, 0.5) var up_length := 5.0:
	set(value):
		up_length = value
		_apply()
@export_range(0.0, 10.0, 0.5) var top_length := 1.0:
	set(value):
		top_length = value
		_apply()
@export_range(0.0, 30.0, 0.5) var down_length := 2.5:
	set(value):
		down_length = value
		_apply()
@export_range(0.2, 6.0, 0.1) var height := 1.5:
	set(value):
		height = value
		_apply()
@export_range(1.0, 20.0, 0.5) var width := 6.0:
	set(value):
		width = value
		_apply()
## Sunk into the ground so uneven terrain never shows a gap under the base.
@export_range(0.0, 1.0, 0.05) var sink := 0.15:
	set(value):
		sink = value
		_apply()
@export var color := Color(0.72, 0.5, 0.3):
	set(value):
		color = value
		_apply()
@export var stripe_color := Color(0.95, 0.85, 0.35):
	set(value):
		stripe_color = value
		_apply()

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply()


func total_length() -> float:
	return up_length + top_length + down_length


func _apply() -> void:
	if not is_node_ready():
		return
	var hw := width * 0.5
	var z_back := total_length() * 0.5     # +Z = behind (the approach side)
	var z_top_back := z_back - up_length
	var z_top_front := z_top_back - top_length
	var z_front := -z_back
	var y0 := -sink
	var h := height
	# Profile (z, y) from back to front, extruded along X.
	var profile: Array[Vector2] = [Vector2(z_back, y0), Vector2(z_top_back, h), Vector2(z_top_front, h)]
	profile.append(Vector2(z_front, y0) if down_length > 0.0 else Vector2(z_top_front, y0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var c := stripe_color if (i == 1 and top_length > 0.0) else color
		_quad(st, Vector3(-hw, a.y, a.x), Vector3(hw, a.y, a.x), Vector3(hw, b.y, b.x), Vector3(-hw, b.y, b.x), c)
	# Sides: a fan from the first profile point, mirrored so both face out.
	var side := color.darkened(0.15)
	for i in range(1, profile.size() - 1):
		var a := profile[0]
		var b := profile[i]
		var c := profile[i + 1]
		_tri(st, Vector3(hw, a.y, a.x), Vector3(hw, c.y, c.x), Vector3(hw, b.y, b.x), side)
		_tri(st, Vector3(-hw, a.y, a.x), Vector3(-hw, b.y, b.x), Vector3(-hw, c.y, c.x), side)
	var last := profile[profile.size() - 1]
	if down_length <= 0.0:
		_quad(st, Vector3(-hw, last.y, last.x), Vector3(-hw, h, last.x), Vector3(hw, h, last.x), Vector3(hw, last.y, last.x), side)
	_quad(st, Vector3(-hw, y0, profile[0].x), Vector3(-hw, y0, last.x), Vector3(hw, y0, last.x), Vector3(hw, y0, profile[0].x), side)
	st.generate_normals()
	var mesh := st.commit()
	var material := FlatMaterial.flat(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for p in profile:
		points.append(Vector3(-hw, p.y, p.x))
		points.append(Vector3(hw, p.y, p.x))
	if down_length <= 0.0:
		points.append(Vector3(-hw, h, last.x))
		points.append(Vector3(hw, h, last.x))
	shape.points = points
	collision.shape = shape


## Quad wound clockwise seen from outside (Godot front faces are clockwise).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_tri(st, a, b, c, tint)
	_tri(st, a, c, d, tint)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	# Godot front faces: Plane(a, b, c).normal must point outward, which is
	# (c - a) x (b - a) -- the reverse of the textbook cross product.
	st.set_color(tint)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
