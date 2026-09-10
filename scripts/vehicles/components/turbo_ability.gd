class_name TurboAbility
extends VehicleAbility
## Short burst of extra top speed and acceleration, then a cooldown.
## Numbers come from the VehicleDefinition so different vehicles can differ.

signal activated
signal ended

var is_active := false
var time_left := 0.0
var cooldown_left := 0.0


func _init() -> void:
	id = &"turbo"


func try_activate() -> bool:
	if not is_unlocked() or is_active or cooldown_left > 0.0:
		return false
	is_active = true
	time_left = vehicle.definition.turbo_duration
	activated.emit()
	return true


func tick(delta: float) -> void:
	if is_active:
		time_left -= delta
		if time_left <= 0.0:
			is_active = false
			cooldown_left = vehicle.definition.turbo_cooldown
			ended.emit()
	elif cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)


func get_speed_multiplier() -> float:
	return vehicle.definition.turbo_speed_multiplier if is_active else 1.0


func get_acceleration_multiplier() -> float:
	return vehicle.definition.turbo_acceleration_multiplier if is_active else 1.0


func reset() -> void:
	is_active = false
	time_left = 0.0
	cooldown_left = 0.0
