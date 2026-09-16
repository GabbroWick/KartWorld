class_name DefeatEnemiesObjective
extends Objective
## Complete when enough of the level's enemies are dead.

## How many to defeat. 0 = every enemy present in the level at start.
@export_range(0, 100, 1) var required := 0
## Only count enemies in group `boss` (BossSlime.BOSS_GROUP).
@export var boss_only := false

var defeated := 0
var target := 0


func _start() -> void:
	target = required
	var present := 0
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy is BossSlime and not boss_only:
			continue   # the boss has its own objective
		if enemy and level.owns(enemy) and (not boss_only or enemy.is_in_group(BossSlime.BOSS_GROUP)):
			present += 1
			enemy.died.connect(_on_enemy_died)
	if target == 0:
		target = present


func get_status_text() -> String:
	return "%s %d/%d" % [tr(description), defeated, target]


func _on_enemy_died(_enemy: Enemy) -> void:
	defeated += 1
	progress_changed.emit(self)
	if defeated >= target:
		complete()
