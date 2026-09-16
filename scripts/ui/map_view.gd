class_name MapView
extends Control
## Draws a WorldMap: either a minimap (a window `view_radius` metres around
## the player, north up) or the full map (`full = true`, whole texture
## fitted in the control). Markers are drawn as simple shapes, the player
## as a triangle pointing where the camera looks. Everything is `_draw`,
## no textures needed beyond the map itself (Web font has no icons).

@export var full := false
@export_range(30.0, 600.0, 5.0) var view_radius := 160.0
@export var frame_color := Color(1, 1, 1, 0.85)
@export var show_labels := false

var world_map: WorldMap
var _player: Node3D
var _camera: ThirdPersonCamera


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if world_map == null or not world_map.is_ready:
		_draw_frame()
		return
	_player = GameManager.get_player(0) as Node3D
	if _camera == null:
		_camera = get_tree().get_first_node_in_group(&"camera_rig") as ThirdPersonCamera
	var focus := _focus_position()
	var rect := Rect2(Vector2.ZERO, size)
	if full:
		_draw_full(rect, focus)
	else:
		_draw_window(rect, focus)
	_draw_frame()


## The player, or the kart while driving.
func _focus_position() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var c := _player as CharacterController
	if c and c.driver and c.driver.is_driving and c.driver.vehicle:
		return c.driver.vehicle.global_position
	return _player.global_position


func _heading() -> float:
	if _player == null:
		return 0.0
	var c := _player as CharacterController
	var forward: Vector3
	if c and c.driver and c.driver.is_driving and c.driver.vehicle:
		forward = -c.driver.vehicle.global_basis.z
	elif c:
		forward = -c.visual_root.global_basis.z
	else:
		forward = Vector3.FORWARD
	return atan2(forward.x, -forward.z)   # 0 = north (-Z), clockwise


func _draw_window(rect: Rect2, focus: Vector3) -> void:
	# Texture region around the focus, metres -> pixels of the map image.
	var mpp := WorldMap.METRES_PER_PIXEL
	var tex := world_map.texture
	var centre_px := Vector2((focus.x - world_map.bounds.position.x) / mpp, (focus.z - world_map.bounds.position.y) / mpp)
	var radius_px := view_radius / mpp
	var src := Rect2(centre_px - Vector2.ONE * radius_px, Vector2.ONE * radius_px * 2.0)
	draw_rect(rect, Color(0.16, 0.42, 0.7))
	draw_texture_rect_region(tex, rect, src, Color.WHITE, false, true)
	var scale := rect.size.x / (view_radius * 2.0)
	for marker in world_map.markers():
		var p: Vector3 = marker["position"]
		var d := Vector2(p.x - focus.x, p.z - focus.z)
		if d.length() > view_radius * 1.02:
			continue
		_draw_marker(rect.get_center() + d * scale, marker, 1.0)
	_draw_player(rect.get_center(), 9.0)


func _draw_full(rect: Rect2, focus: Vector3) -> void:
	var tex := world_map.texture
	var tex_size := Vector2(tex.get_size())
	var fit := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * fit
	var origin := rect.position + (rect.size - draw_size) * 0.5
	draw_rect(rect, Color(0.12, 0.3, 0.55))
	draw_texture_rect(tex, Rect2(origin, draw_size), false)
	var to_screen := func(p: Vector3) -> Vector2:
		var uv := world_map.to_uv(p)
		return origin + uv * draw_size
	for marker in world_map.markers():
		_draw_marker(to_screen.call(marker["position"]), marker, 1.4)
	_draw_player(to_screen.call(focus), 12.0)


func _draw_player(at: Vector2, s: float) -> void:
	var a := _heading()
	var tip := at + Vector2(sin(a), -cos(a)) * s
	var left := at + Vector2(sin(a + 2.5), -cos(a + 2.5)) * s
	var right := at + Vector2(sin(a - 2.5), -cos(a - 2.5)) * s
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1.0, 0.95, 0.3))
	draw_polyline(PackedVector2Array([tip, left, right, tip]), Color(0.1, 0.1, 0.1), 2.0)


func _draw_marker(at: Vector2, marker: Dictionary, scale: float) -> void:
	var kind: String = marker["kind"]
	var s := 6.0 * scale
	match kind:
		"door":
			var color := Color(0.6, 0.3, 1.0) if not marker.get("locked", false) else Color(0.55, 0.55, 0.6)
			draw_rect(Rect2(at - Vector2(s * 0.7, s), Vector2(s * 1.4, s * 2.0)), color)
			draw_rect(Rect2(at - Vector2(s * 0.7, s), Vector2(s * 1.4, s * 2.0)), Color.WHITE, false, 1.5)
		"home":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.3), at + Vector2(s, 0), at + Vector2(-s, 0)]), Color(0.95, 0.35, 0.3))
			draw_rect(Rect2(at - Vector2(s * 0.7, 0), Vector2(s * 1.4, s)), Color(0.95, 0.9, 0.75))
		"village":
			draw_rect(Rect2(at - Vector2(s, s * 0.6), Vector2(s * 0.8, s * 1.2)), Color(0.9, 0.75, 0.5))
			draw_rect(Rect2(at + Vector2(s * 0.1, -s * 0.9), Vector2(s * 0.9, s * 1.5)), Color(0.85, 0.65, 0.45))
		"kart":
			draw_circle(at, s * 0.9, Color(0.25, 0.55, 0.95))
			draw_arc(at, s * 0.9, 0.0, TAU, 12, Color.WHITE, 1.5)
		"shop":
			draw_rect(Rect2(at - Vector2(s, s * 0.8), Vector2(s * 2.0, s * 1.6)), Color(0.95, 0.3, 0.3))
			draw_rect(Rect2(at - Vector2(s, s * 0.8), Vector2(s * 2.0, s * 1.6)), Color.WHITE, false, 1.5)
		"race":
			draw_rect(Rect2(at - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), Color.WHITE)
			for cy in 2:
				for cx in 2:
					if (cx + cy) % 2 == 0:
						draw_rect(Rect2(at - Vector2(s, s) + Vector2(cx * s, cy * s), Vector2(s, s)), Color.BLACK)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := s if i % 2 == 0 else s * 0.45
				var ang := -PI * 0.5 + i * PI / 5.0
				pts.append(at + Vector2(cos(ang), sin(ang)) * r)
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.25))
	if show_labels and marker.get("label", "") != "":
		var font := ThemeDB.fallback_font
		var text: String = marker["label"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, at + Vector2(-w * 0.5, s * 2.4 + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at + Vector2(-w * 0.5, s * 2.4 + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_frame() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), frame_color, false, 3.0)
