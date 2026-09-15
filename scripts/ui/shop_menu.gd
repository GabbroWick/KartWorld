class_name ShopMenu
extends PanelContainer
## Weapons for stars. One row per catalogue item: name, description,
## price, a Buy / Use / In use button. The world freezes while it is open
## (GameManager.set_frozen), like the level-complete card.

signal closed

@onready var title_label: Label = $Margin/Rows/Title
@onready var balance_label: Label = $Margin/Rows/Balance
@onready var rows: VBoxContainer = $Margin/Rows/Items
@onready var close_button: Button = $Margin/Rows/Close

var _buttons: Dictionary = {}   # id -> Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	title_label.text = tr(&"SHOP_TITLE")
	close_button.text = tr(&"SHOP_CLOSE")
	close_button.pressed.connect(close)
	_build_rows()
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
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(InputActions.INTERACT)):
		close()
		get_viewport().set_input_as_handled()


func _build_rows() -> void:
	for child in rows.get_children():
		child.queue_free()
	_buttons.clear()
	for id in Weapons.ORDER:
		_add_row(id, Weapons.stats(id), false)
	for id in Weapons.UPGRADE_ORDER:
		_add_row(id, Weapons.UPGRADES[id], true)


func _add_row(id: StringName, stats: Dictionary, upgrade: bool) -> void:
	if true:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 14)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(28.0, 28.0)
		icon.draw.connect(func() -> void:
			icon.draw_rect(Rect2(Vector2(4, 4), Vector2(20, 20)), stats["color"]))
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = "%s  ★ %d" % [tr(stats["name"]), int(stats["price"])]
		name_label.add_theme_font_size_override(&"font_size", 22)
		text.add_child(name_label)
		var desc := Label.new()
		desc.text = tr(stats["desc"])
		desc.add_theme_font_size_override(&"font_size", 16)
		desc.modulate = Color(0.85, 0.85, 0.9)
		text.add_child(desc)
		row.add_child(text)
		var button := Button.new()
		button.custom_minimum_size = Vector2(130.0, 44.0)
		button.add_theme_font_size_override(&"font_size", 18)
		button.pressed.connect(_on_upgrade_pressed.bind(id) if upgrade else _on_item_pressed.bind(id))
		button.set_meta(&"upgrade", upgrade)
		row.add_child(button)
		_buttons[id] = button
		rows.add_child(row)


func _refresh() -> void:
	balance_label.text = tr(&"SHOP_BALANCE") % ProgressionManager.get_available_stars()
	for id in _buttons:
		var button: Button = _buttons[id]
		if button.get_meta(&"upgrade", false):
			if ProgressionManager.owns_upgrade(id):
				button.text = tr(&"SHOP_OWNED")
				button.disabled = true
			else:
				button.text = tr(&"SHOP_BUY")
				button.disabled = ProgressionManager.get_available_stars() < int(Weapons.UPGRADES[id]["price"])
		elif ProgressionManager.equipped_weapon == id:
			button.text = tr(&"SHOP_IN_USE")
			button.disabled = true
		elif ProgressionManager.owns_weapon(id):
			button.text = tr(&"SHOP_USE")
			button.disabled = false
		else:
			button.text = tr(&"SHOP_BUY")
			button.disabled = ProgressionManager.get_available_stars() < Weapons.price(id)


func _on_upgrade_pressed(id: StringName) -> void:
	if ProgressionManager.buy_upgrade(id):
		Sfx.play(&"unlock")
	else:
		Sfx.play(&"hurt", -10.0)
	_refresh()


func _on_item_pressed(id: StringName) -> void:
	if ProgressionManager.owns_weapon(id):
		ProgressionManager.equip_weapon(id)
		Sfx.play(&"ui", -4.0)
	elif ProgressionManager.buy_weapon(id):
		Sfx.play(&"unlock")
	else:
		Sfx.play(&"hurt", -10.0)
	_refresh()
