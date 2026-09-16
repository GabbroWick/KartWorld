extends Node
## Headless test for combat (Phase 6).
##
## Run:  godot --headless res://tools/tests/test_combat_runner.tscn
##
## Loads the game into the Forest Trail and checks: enemies exist and chase,
## the melee swing damages and kills an enemy, the defeat objective counts,
## contact with an enemy hurts the player once (invulnerability, knockback),
## dying from damage respawns at the spawn with full health, and the kart is
## a safe place.

const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL := "res://resources/levels/level_01_forest_trail.tres"

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: CharacterController
var _manager: LevelManager
var _camera_rig: ThirdPersonCamera
var _hud: CanvasLayer
var _level: LevelController


func _ready() -> void:
	_run()


func _run() -> void:
	ProgressionManager.save_path = "user://test_scratch_save.json"
	ProgressionManager.reset()
	await get_tree().process_frame
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	_camera_rig = _scene.get_node("CameraRig")
	_hud = _scene.get_node("GameHUD")
	await _steps(20)
	_player = GameManager.get_player(0) as CharacterController
	_manager = get_tree().get_first_node_in_group(LevelManager.GROUP) as LevelManager
	_manager.load_level(load(LEVEL))
	await _steps(10)
	_level = get_tree().get_first_node_in_group(LevelController.GROUP) as LevelController

	_test_setup()
	await _test_attack_kills()
	await _test_shop_weapons()
	await _test_chase()
	await _test_contact_damage()
	await _test_death_by_damage()
	await _test_kart_is_safe()
	_finish()


func _test_setup() -> void:
	_check(InputMap.has_action(InputActions.ATTACK), "attack action exists")
	_check(_player.combat != null and not _player.combat.is_attacking, "character has a combat component")
	var enemies := get_tree().get_nodes_in_group(Enemy.GROUP)
	_check(enemies.size() == 2, "level has two enemies (%d)" % enemies.size())
	if enemies.size() > 0:
		var enemy: Enemy = enemies[0]
		_check(enemy.definition.display_name == "ENEMY_SLIME", "enemies use the slime definition")
		_check(enemy.health.current_health == 2.0, "slime has 2 health")
		_check(enemy.visual_root.get_child_count() == 1, "slime has its placeholder visual")
	var defeat: DefeatEnemiesObjective = null
	for objective in _level.objectives:
		if objective is DefeatEnemiesObjective:
			defeat = objective
	_check(defeat != null and defeat.target == 2, "defeat objective targets both slimes")
	_check(defeat != null and defeat.optional, "defeat objective is optional on this level")


func _test_attack_kills() -> void:
	# Stand the player 1 m in front of a slime, facing it, and swing twice.
	var enemy: Enemy = get_tree().get_nodes_in_group(Enemy.GROUP)[0]
	var defeat: DefeatEnemiesObjective = _level.objectives[2]
	enemy.global_position = Vector3(0.0, 0.2, -6.0)
	enemy.velocity = Vector3.ZERO
	enemy.definition = enemy.definition.duplicate()
	enemy.definition.chase_radius = 0.0  # hold still for the test
	_player.global_position = Vector3(0.0, 0.2, -4.6)
	_player.motor.reset()
	_player.visual_root.rotation.y = 0.0  # face -Z, toward the slime
	_camera_rig.set_yaw(0.0)
	await _steps(10)
	var swung := [false]
	var hits := [0]
	_player.combat.attacked.connect(func() -> void: swung[0] = true)
	_player.combat.hit.connect(func(_t: Node) -> void: hits[0] += 1)
	var died := [false]
	enemy.died.connect(func(_e: Enemy) -> void: died[0] = true)

	Sfx.clear_log()
	await _press(InputActions.ATTACK)
	await _steps(3)
	_check(swung[0], "attack input starts a swing")
	_check(hits[0] == 1, "the swing hits the slime once (%d)" % hits[0])
	_check(enemy.hit_flash.is_flashing, "a hit flashes the slime white")
	_check(Sfx.played.has(&"attack") and Sfx.played.has(&"hit"), "swing and hit play their sounds (%s)" % str(Sfx.played))
	_check(enemy.health.current_health == 1.0, "slime lost 1 health (%.0f left)" % enemy.health.current_health)
	await _press(InputActions.ATTACK)
	await _steps(3)
	_check(hits[0] == 1, "a second press during cooldown does not hit again")
	await _steps(30)
	await _press(InputActions.ATTACK)
	await _steps(3)
	_check(hits[0] == 2, "after the cooldown the next swing hits (%d)" % hits[0])
	_check(died[0], "second hit kills the slime")
	_check(Sfx.played.has(&"enemy_die"), "defeat plays the enemy sound")
	_check(get_tree().get_nodes_in_group(Burst.GROUP).size() >= 1, "defeat spawns a particle burst")
	_check(defeat.defeated == 1, "defeat objective counts 1/2")
	_check(defeat.get_status_text() == tr(&"OBJ_DEFEAT_SLIMES") + " 1/2", "objective text shows progress (%s)" % defeat.get_status_text())
	await _steps(30)
	_check(get_tree().get_nodes_in_group(Enemy.GROUP).size() == 1, "dead slime is removed from the scene")


func _test_chase() -> void:
	var enemy: Enemy = get_tree().get_nodes_in_group(Enemy.GROUP)[0]
	enemy.global_position = Vector3(20.0, 0.2, -44.0)
	enemy.velocity = Vector3.ZERO
	_player.global_position = Vector3(20.0, 0.2, -39.0)  # 5 m away, inside chase radius
	_player.motor.reset()
	await _steps(5)
	var before := enemy.global_position.distance_to(_player.global_position)
	await _steps(45)
	var after := enemy.global_position.distance_to(_player.global_position)
	_check(enemy.state == Enemy.State.CHASE, "slime switches to CHASE near the player")
	_check(after < before - 1.0, "slime closes in on the player (%.1f -> %.1f m)" % [before, after])


func _test_contact_damage() -> void:
	var enemy: Enemy = get_tree().get_nodes_in_group(Enemy.GROUP)[0]
	var hurt := [0]
	_player.hurt.connect(func(_a: float, _s: Node) -> void: hurt[0] += 1)
	var start_health := _player.health.current_health
	# The chase test left the slime closing in; give it time to make contact.
	await _steps(60)
	_check(hurt[0] >= 1, "touching a slime hurts the player")
	_check(_player.health.current_health == start_health - 1.0,
		"contact costs exactly 1 heart (%.0f -> %.0f)" % [start_health, _player.health.current_health])
	_check(_player.is_invulnerable(), "player is invulnerable right after the hit")
	_check(_hud.hearts.current == 4, "HUD shows the lost heart (%d)" % _hud.hearts.current)
	# The slime is still touching us; nothing may land until the i-frames end.
	var hurt_after_first: int = hurt[0]
	var frames_left := int(_player.invulnerable_left * 60.0) - 6
	await _steps(maxi(frames_left, 1))
	_check(hurt[0] == hurt_after_first, "no second hit inside the invulnerability window")
	# Move away so the slime cannot keep hurting us.
	enemy.global_position = Vector3(20.0, 0.2, -47.0)
	enemy.velocity = Vector3.ZERO
	enemy.definition = enemy.definition.duplicate()
	enemy.definition.chase_radius = 0.0
	_player.global_position = Vector3(20.0, 0.2, -39.0)
	_player.motor.reset()
	await _steps(70)
	_check(not _player.is_invulnerable(), "invulnerability wears off (%.2fs left)" % _player.invulnerable_left)
	_check(_player.visual_root.visible, "model is solid again after blinking")


func _test_death_by_damage() -> void:
	var died := [false]
	_player.died.connect(func() -> void: died[0] = true)
	var spawn := _player.spawn_transform.origin
	# Exactly as many hits as hearts left: the last one kills and respawn
	# refills, so a "while alive" loop would never end.
	for i in int(_player.health.current_health):
		_player.invulnerable_left = 0.0
		_player.take_damage(1.0, null)
		await _steps(1)
	await _steps(5)
	_check(died[0], "running out of hearts kills the character")
	_check(_player.health.current_health == _player.health.max_health, "respawn restores full health")
	_check(_player.global_position.distance_to(spawn) < 1.0, "character respawns at the spawn point")
	_check(_hud.hearts.current == 5, "HUD shows full hearts again")
	_check(not _manager.is_in_hub(), "dying keeps the party in the level")


func _test_kart_is_safe() -> void:
	# At the wheel the character cannot be hurt.
	await _press(InputActions.SUMMON_KART)
	await _steps(10)
	await _press(InputActions.INTERACT)
	await _steps(3)
	_check(_player.driver.is_driving, "player is in the kart")
	var before := _player.health.current_health
	_player.take_damage(1.0, null)
	_check(_player.health.current_health == before, "damage is ignored while driving")
	await _press(InputActions.INTERACT)
	await _steps(5)


func _test_shop_weapons() -> void:
	# Stars are the currency; buying equips; the club doubles the damage,
	# the boomerang flies, hits and comes back.
	var enemy: Enemy = get_tree().get_nodes_in_group(Enemy.GROUP)[0]
	var original_definition := enemy.definition
	enemy.definition = enemy.definition.duplicate()
	enemy.definition.chase_radius = 0.0
	enemy.health.restore_full()
	_check(ProgressionManager.get_available_stars() == 0, "no stars, no shopping")
	_check(not ProgressionManager.buy_weapon(&"club"), "cannot buy the club without stars")
	for i in 12:
		ProgressionManager.record_collected(StringName("test_star_%d" % i), &"star", 1)
	_check(ProgressionManager.get_available_stars() == 12, "wallet counts the stars (%d)" % ProgressionManager.get_available_stars())
	_check(ProgressionManager.buy_weapon(&"club") and ProgressionManager.equipped_weapon == &"club", "buying the club equips it")
	_check(ProgressionManager.get_available_stars() == 9, "the club cost 3 stars (%d left)" % ProgressionManager.get_available_stars())
	_check(not ProgressionManager.buy_weapon(&"club"), "a weapon is bought once")
	_check(_player.combat.weapon_damage == 2.0, "club doubles the melee damage (%.1f)" % _player.combat.weapon_damage)
	var hud: GameHUD = _hud
	hud.open_shop()
	await get_tree().process_frame
	_check(hud.shop_menu.visible and get_tree().paused, "the shop menu opens and freezes the world")
	_check(hud.shop_menu.balance_label.text == tr(&"SHOP_BALANCE") % 9, "shop shows the balance (%s)" % hud.shop_menu.balance_label.text)
	_check((hud.shop_menu._buttons[&"club"] as Button).text == tr(&"SHOP_IN_USE"), "club row says in use")
	_check(not (hud.shop_menu._buttons[&"boomerang"] as Button).disabled, "boomerang is affordable")
	(hud.shop_menu._buttons[&"boomerang"] as Button).pressed.emit()
	_check(ProgressionManager.owns_weapon(&"boomerang") and ProgressionManager.equipped_weapon == &"boomerang" and ProgressionManager.get_available_stars() == 3,
		"pressing Buy on the boomerang buys and equips it (%d stars left)" % ProgressionManager.get_available_stars())
	_check((hud.shop_menu._buttons[&"sword"] as Button).disabled, "the sword is too expensive now")
	hud.shop_menu.close()
	await get_tree().process_frame
	_check(not get_tree().paused, "closing the shop thaws the world")
	# Throw: the boomerang crosses 6 m, hits the slime once and returns.
	enemy.global_position = Vector3(0.0, 0.2, -10.0)
	enemy.velocity = Vector3.ZERO
	enemy.health.restore_full()
	_player.global_position = Vector3(0.0, 0.2, -4.0)
	_player.motor.reset()
	_player.visual_root.rotation.y = 0.0
	_camera_rig.set_yaw(0.0)
	await _steps(10)
	var hits := [0]
	_player.combat.hit.connect(func(_t: Node) -> void: hits[0] += 1)
	await _press(InputActions.ATTACK)
	await _steps(2)
	var thrown := get_tree().root.find_children("*", "Boomerang", true, false)
	_check(thrown.size() == 1, "attacking with the boomerang throws it")
	await _steps(120)
	_check(hits[0] >= 1 and enemy.health.current_health <= 1.0, "the boomerang hits the slime (%d hits, %.0f hp)" % [hits[0], enemy.health.current_health])
	_check(get_tree().root.find_children("*", "Boomerang", true, false).is_empty(), "the boomerang came back and vanished")
	# Backpack: I lists paws + owned weapons; Use swaps the weapon; the
	# swing is the weapon's move, not the kick clip.
	_press_action_once(InputActions.INVENTORY)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.inventory_menu.visible and get_tree().paused, "I opens the backpack")
	_check(hud.inventory_menu._buttons.size() == 3 and hud.inventory_menu._buttons.has(&"club") and hud.inventory_menu._buttons.has(&"boomerang"),
		"backpack lists paws, club and boomerang (%d rows)" % hud.inventory_menu._buttons.size())
	(hud.inventory_menu._buttons[&"club"] as Button).pressed.emit()
	_check(ProgressionManager.equipped_weapon == &"club", "Use in the backpack equips the club")
	hud.inventory_menu.close()
	await get_tree().process_frame
	_check(not get_tree().paused, "closing the backpack thaws the world")
	var rigged := _player.get_visual() as RiggedCharacterVisual
	if rigged:
		_check(rigged._weapon_mount != null and rigged._weapon_mount.get_child_count() == 1, "the club model hangs from the hand bone")
		var swung := rigged.play_action(&"attack", 1.4)
		_check(swung and rigged._swing_pose.active and rigged.player.current_animation != "attack", "with a weapon the attack is the procedural swing, not the kick clip")
		await _steps(30)
	# Back to paws (and a chasing slime) for the remaining tests.
	enemy.definition = original_definition
	enemy.health.restore_full()
	ProgressionManager.equip_weapon(&"")
	_check(_player.combat.weapon_damage == 1.0 and not _player.combat.weapon_ranged, "paws again")


func _press_action_once(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _finish() -> void:
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)
