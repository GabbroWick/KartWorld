class_name VehicleAbility
extends Node
## Base for vehicle abilities that own behaviour (turbo, later dash, flight,
## weapons). Each is an independent node under the vehicle's Abilities group;
## the controller asks `try_activate()` and never knows what the ability does.
##
## Gating (is it unlocked?) stays in AbilityComponent; this node only knows
## its own id and behaviour.

@export var id: StringName = &"ability"

var vehicle: VehicleController


func setup(owner_vehicle: VehicleController) -> void:
	vehicle = owner_vehicle


func is_unlocked() -> bool:
	return vehicle != null and vehicle.abilities.has(id)


## Override. Return true when the ability actually fired.
func try_activate() -> bool:
	return false


## Override for per-tick behaviour. Called by the controller while driving.
func tick(_delta: float) -> void:
	pass
