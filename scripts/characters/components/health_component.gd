class_name HealthComponent
extends Node
## Reusable health/damage container.
##
## Same component for player, enemies, bosses and (later) vehicles: it only
## knows numbers and signals, never who owns it. Nothing in here references the
## player or the leopard.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health := 5.0
@export var invulnerable := false

var current_health: float
var is_dead := false


func _ready() -> void:
	if current_health <= 0.0:
		current_health = max_health


func setup(maximum: float) -> void:
	max_health = maximum
	current_health = maximum
	is_dead = false
	health_changed.emit(current_health, max_health)


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or invulnerable or amount <= 0.0:
		return
	current_health = maxf(current_health - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)
	if is_zero_approx(current_health):
		_die()


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


func kill() -> void:
	if is_dead:
		return
	current_health = 0.0
	health_changed.emit(current_health, max_health)
	_die()


func restore_full() -> void:
	is_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)


func get_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


func _die() -> void:
	is_dead = true
	died.emit()
