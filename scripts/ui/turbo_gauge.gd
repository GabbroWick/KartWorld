class_name TurboGauge
extends Control
## The kart's turbo gauge: a rounded bar that drains while boosting and
## refills afterwards. Shown only at the wheel. Drawn, not textured, like
## the hearts and the star (the Web font has no icons anyway).

@export_range(0.0, 1.0, 0.01) var charge := 1.0:
	set(value):
		charge = value
		queue_redraw()
@export var boosting := false:
	set(value):
		boosting = value
		queue_redraw()
@export var bar_size := Vector2(150.0, 14.0)
@export var fill_color := Color(1.0, 0.6, 0.15)
@export var boost_color := Color(1.0, 0.9, 0.4)
@export var empty_color := Color(0.15, 0.15, 0.2, 0.7)

var _time := 0.0


func _ready() -> void:
	custom_minimum_size = bar_size + Vector2(0.0, 6.0)


func _process(delta: float) -> void:
	_time += delta
	if boosting:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, bar_size)
	var style := StyleBoxFlat.new()
	style.bg_color = empty_color
	style.set_corner_radius_all(int(bar_size.y * 0.5))
	style.border_color = Color(1, 1, 1, 0.8)
	style.set_border_width_all(2)
	draw_style_box(style, rect)
	if charge <= 0.01:
		return
	var fill := StyleBoxFlat.new()
	var color := fill_color
	if boosting:
		color = fill_color.lerp(boost_color, 0.5 + 0.5 * sin(_time * 18.0))
	elif charge >= 0.999:
		color = fill_color.lerp(boost_color, 0.3 + 0.3 * sin(_time * 3.0))
	fill.bg_color = color
	fill.set_corner_radius_all(int(bar_size.y * 0.5))
	var inner := Rect2(Vector2(3.0, 3.0), Vector2((bar_size.x - 6.0) * charge, bar_size.y - 6.0))
	draw_style_box(fill, inner)
