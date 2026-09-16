class_name InventoryMenu
extends PanelContainer
## The backpack (I / touch "Zaino"): weapons you own (paws first) with a
## Use button, and the food you carry. Same freeze-the-world behaviour as
## the shop.

@onready var title_label: Label = $Margin/Rows/Title
@onready var rows: VBoxContainer = $Margin/Rows/Items
@onready var food_label: Label = $Margin/Rows/Food
@onready var close_button: Button = $Margin/Rows/Close

var _buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	title_label.text = tr(&"INV_TITLE")
	close_button.text = tr(&"SHOP_CLOSE")
	close_button.pressed.connect(close)
	ProgressionManager.changed.connect(_refresh)


func open() -> void:
	_refresh()
	visible = true
	GameManager.set_frozen(true)
	Sfx.play(&"ui", -6.0)
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	GameManager.set_frozen(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(InputActions.INVENTORY)):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in rows.get_children():
		child.queue_free()
	_buttons.clear()
	var ids: Array[StringName] = [&""]
	for id in Weapons.ORDER:
		if ProgressionManager.owns_weapon(id):
			ids.append(id)
	for id in ids:
		var stats := Weapons.stats(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 14)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(28.0, 28.0)
		var color: Color = stats["color"]
		icon.draw.connect(func() -> void: icon.draw_rect(Rect2(Vector2(4, 4), Vector2(20, 20)), color))
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s — %s" % [tr(stats["name"]), tr(stats["desc"])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override(&"font_size", 20)
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(120.0, 40.0)
		var equipped := ProgressionManager.equipped_weapon == id
		button.text = tr(&"SHOP_IN_USE") if equipped else tr(&"SHOP_USE")
		button.disabled = equipped
		button.pressed.connect(func() -> void:
			ProgressionManager.equip_weapon(id)
			Sfx.play(&"ui", -4.0))
		row.add_child(button)
		_buttons[id] = button
		rows.add_child(row)
	var parts := PackedStringArray()
	for item in [&"fruit", &"meat"]:
		var n := ProgressionManager.count_item(item)
		if n > 0:
			parts.append("%s %d" % [tr(&"ITEM_" + String(item).to_upper()), n])
	food_label.text = tr(&"INV_FOOD") % (" · ".join(parts) if parts.size() > 0 else tr(&"INV_NOTHING"))
