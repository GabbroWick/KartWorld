class_name AbilityComponent
extends Node
## Tracks which abilities an actor currently has.
##
## Deliberately tiny: gameplay code asks `abilities.has(&"double_jump")` instead
## of hard-coding what a character can do. When abilities need behaviour of their
## own (turbo, flight, ranged attack...), they become their own nodes/resources
## registered here — no `if power_up == "fire"` chains.

signal ability_unlocked(id: StringName)
signal ability_locked(id: StringName)

const DOUBLE_JUMP := &"double_jump"
const RUN := &"run"
## One more air jump on top of the definition's max_air_jumps.
const ENHANCED_JUMP := &"enhanced_jump"

var _unlocked: Dictionary[StringName, bool] = {}


func setup(ability_ids: PackedStringArray) -> void:
	_unlocked.clear()
	for id in ability_ids:
		_unlocked[StringName(id)] = true


func has(id: StringName) -> bool:
	return _unlocked.get(id, false)


func unlock(id: StringName) -> void:
	if not has(id):
		_unlocked[id] = true
		ability_unlocked.emit(id)


func lock(id: StringName) -> void:
	if has(id):
		_unlocked.erase(id)
		ability_locked.emit(id)


func get_unlocked() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_unlocked.keys())
	return result
