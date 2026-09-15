class_name Animal
extends Enemy
## A harmless animal (chicken, rabbit...): pecks around its home, runs
## away when the player comes close, never attacks. Hit it and it drops
## food into the inventory (`definition.drop_item` x `drop_amount`).
## Reuses the Enemy body/health/hit flash; only the brain differs.

@export_range(0.0, 20.0, 0.5) var flee_radius := 4.0


func _think(delta: float) -> void:
	target = _nearest_player()
	var distance := target.global_position.distance_to(global_position) if target else INF
	if target and distance < flee_radius:
		state = State.CHASE   # "chase" = run, the direction is flipped below
		return
	if state == State.CHASE:
		state = State.IDLE
		_idle_left = 0.6
	super._think(delta)


func _wish_direction() -> Vector3:
	if state == State.CHASE and target:
		var away := global_position - target.global_position
		away.y = 0.0
		# Stay near home: bend the escape back toward it when far out.
		var to_home := home - global_position
		to_home.y = 0.0
		if to_home.length() > definition.patrol_radius * 1.5:
			away = away.normalized() + to_home.normalized() * 0.8
		return away.normalized() if away.length_squared() > 0.01 else Vector3.ZERO
	return super._wish_direction()


func _on_contact(_body: Node3D) -> void:
	pass   # animals do not hurt


func _on_died() -> void:
	if definition.drop_item != &"":
		ProgressionManager.add_item(definition.drop_item, definition.drop_amount)
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"show_notice"):
			hud.call(&"show_notice", tr(&"NOTICE_GOT_MEAT") % definition.drop_amount)
	super._on_died()
