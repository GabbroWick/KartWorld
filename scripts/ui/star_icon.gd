@tool
class_name StarIcon
extends Control
## A five-point star drawn as a polygon, for counters and badges. No glyphs.

@export var star_size := 26.0:
	set(value):
		star_size = value
		queue_redraw()
		update_minimum_size()
@export var fill_color := Color(1.0, 0.85, 0.25)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.85)


func _get_minimum_size() -> Vector2:
	return Vector2(star_size, star_size)


func _draw() -> void:
	var centre := Vector2(star_size, star_size) * 0.5
	var outer := star_size * 0.5
	var inner := outer * 0.45
	var points := PackedVector2Array()
	for i in 10:
		var radius := outer if i % 2 == 0 else inner
		var angle := -PI * 0.5 + TAU * i / 10.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, fill_color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, outline_color, 2.0, true)
