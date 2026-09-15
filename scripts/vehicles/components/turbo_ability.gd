class_name TurboAbility
extends VehicleAbility
## Boost with a gauge: hold the turbo action and the kart gets extra top
## speed and acceleration while `charge` drains (full gauge lasts
## `turbo_duration` seconds); release and it refills (empty to full in
## `turbo_cooldown` seconds). An emptied gauge must refill a little before
## it can boost again, so mashing the button never stutters.
## Numbers come from the VehicleDefinition so different vehicles can differ.

signal activated
signal ended

## Fraction of the gauge an empty turbo must regain (with the button
## released) before it works again.
const RELIGHT_CHARGE := 0.25

var is_active := false
var charge := 1.0
var time_left := 0.0      # for one-shot bursts (try_activate)
var cooldown_left := 0.0  # seconds until an emptied gauge can relight

var _held := false
var _needs_relight := false


func _init() -> void:
	id = &"turbo"


## Player input: boosting while held (and the gauge allows it).
func set_boosting(held: bool) -> void:
	_held = held


## One-shot burst (NPCs, tests): boosts for `turbo_duration` from now, as
## far as the gauge allows. False when it cannot start.
func try_activate() -> bool:
	if not is_unlocked() or is_active or not _can_start():
		return false
	time_left = vehicle.definition.turbo_duration
	_start()
	return true


func _can_start() -> bool:
	return charge > 0.0 and not _needs_relight


func _start() -> void:
	is_active = true
	activated.emit()


func _stop() -> void:
	is_active = false
	time_left = 0.0
	ended.emit()


func tick(delta: float) -> void:
	var want := _held or time_left > 0.0
	if want and not is_active and is_unlocked() and _can_start():
		_start()
	if is_active:
		time_left = maxf(time_left - delta, 0.0)
		charge -= delta / maxf(vehicle.definition.turbo_duration, 0.01)
		if charge <= 0.0:
			charge = 0.0
			_needs_relight = true
			cooldown_left = vehicle.definition.turbo_cooldown * RELIGHT_CHARGE
			_stop()
		elif not want:
			_stop()
	else:
		charge = minf(charge + delta / maxf(vehicle.definition.turbo_cooldown, 0.01), 1.0)
		if _needs_relight:
			cooldown_left = maxf(cooldown_left - delta, 0.0)
			# Relight only once the button has been let go: holding it on an
			# empty gauge must not pulse the boost on and off.
			if charge >= RELIGHT_CHARGE and not _held and time_left <= 0.0:
				_needs_relight = false
				cooldown_left = 0.0


func get_speed_multiplier() -> float:
	return vehicle.definition.turbo_speed_multiplier if is_active else 1.0


func get_acceleration_multiplier() -> float:
	return vehicle.definition.turbo_acceleration_multiplier if is_active else 1.0


func reset() -> void:
	is_active = false
	charge = 1.0
	time_left = 0.0
	cooldown_left = 0.0
	_held = false
	_needs_relight = false
