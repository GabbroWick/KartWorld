@tool
class_name HeartBar
extends Control
## Draws the player's hearts as vector shapes: no font glyphs, so it looks
## the same on Windows, Web and phones (the default web font has no ♥).

@export_range(0, 20, 1) var current := 5:
	set(value):
		current = value
		queue_redraw()
@export_range(1, 20, 1) var maximum := 5:
	set(value):
		maximum = value
		queue_redraw()
@export var heart_size := 26.0:
	set(value):
		heart_size = value
		queue_redraw()
		update_minimum_size()
@export var spacing := 6.0
@export var full_color := Color(1.0, 0.3, 0.38)
@export var empty_color := Color(0.25, 0.1, 0.12, 0.75)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.85)


func set_hearts(now: float, max_value: float) -> void:
	maximum = maxi(int(round(max_value)), 1)
	current = clampi(int(round(now)), 0, maximum)


func _get_minimum_size() -> Vector2:
	return Vector2((heart_size + spacing) * maximum, heart_size * 1.1)


func _draw() -> void:
	for i in maximum:
		var origin := Vector2(i * (heart_size + spacing), 0.0)
		var points := _heart_points(origin, heart_size)
		draw_colored_polygon(points, full_color if i < current else empty_color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, outline_color, 2.0, true)


## Heart outline: two arcs on top, a point at the bottom.
func _heart_points(origin: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := size * 0.25
	var left := origin + Vector2(r, r * 1.1)
	var right := origin + Vector2(size - r, r * 1.1)
	var bottom := origin + Vector2(size * 0.5, size * 0.98)
	# Left lobe: from the middle top, over the left, down to the side.
	for step in 11:
		var angle := PI + PI * 0.9 * step / 10.0 + PI * 0.05
		points.append(left + Vector2(cos(angle), sin(angle)) * r)
	# Right lobe.
	for step in 11:
		var angle := PI * 1.05 + PI * 0.9 * step / 10.0
		points.append(right + Vector2(cos(angle), sin(angle)) * r)
	points.append(bottom)
	return points
