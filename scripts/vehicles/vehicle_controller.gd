class_name VehicleController
extends CharacterBody3D
## Generic drivable vehicle. The kart is one VehicleDefinition of it.
##
## A vehicle is its own entity in the world: it exists whether or not anyone
## is driving, and it is never a child of the character. A driver mounts it,
## input flows through VehicleInput, VehicleMotor moves the body, ability nodes
## under Abilities add behaviour (turbo today, more later).

signal driver_entered(driver: Node)
signal driver_exited(driver: Node)
signal fell_out_of_world

@export var definition: VehicleDefinition
## Below this height the vehicle is considered fallen out of the world.
@export var fall_limit := -25.0

@onready var input: VehicleInput = $InputSource
@onready var motor: VehicleMotor = $Motor
@onready var health: HealthComponent = $Health
@onready var abilities: AbilityComponent = $Abilities
@onready var ability_nodes: Node = $AbilityNodes
@onready var visual_root: Node3D = $VisualRoot
@onready var collision: CollisionShape3D = $Collision

var driver: Node = null
var turbo: TurboAbility
var _visual_instance: Node3D
var _camera_reversed := false


func _ready() -> void:
	if definition == null:
		push_error("VehicleController '%s' has no VehicleDefinition assigned." % name)
		set_physics_process(false)
		return
	_apply_definition()


func _physics_process(delta: float) -> void:
	input.poll()

	var speed_multiplier := 1.0
	var acceleration_multiplier := 1.0
	if turbo:
		if input.turbo_pressed:
			turbo.try_activate()
		speed_multiplier = turbo.get_speed_multiplier()
		acceleration_multiplier = turbo.get_acceleration_multiplier()
	for ability in ability_nodes.get_children():
		if ability is VehicleAbility:
			ability.tick(delta)

	motor.drive(delta, input.throttle, input.steer, input.jump_pressed,
		speed_multiplier, acceleration_multiplier)
	if _visual_instance and _visual_instance.has_method(&"update_visual"):
		_visual_instance.call(&"update_visual", motor.speed, delta)

	if global_position.y < fall_limit:
		fell_out_of_world.emit()


func is_driven() -> bool:
	return driver != null


## Puts `new_driver` at the wheel. The driver decides what happens to its own
## body (hide, disable physics); the vehicle only takes over input.
func mount(new_driver: Node, local_device: bool) -> void:
	if driver != null:
		return
	driver = new_driver
	input.clear()
	input.reads_local_device = local_device
	driver_entered.emit(driver)


func dismount() -> Node:
	if driver == null:
		return null
	var leaving := driver
	driver = null
	input.clear()
	input.reads_local_device = false
	motor.reset()
	driver_exited.emit(leaving)
	return leaving


## World position where a leaving driver should stand: beside the vehicle
## on the flat, whatever the slope the body is aligned to.
func get_exit_position() -> Vector3:
	var flat := Transform3D(Basis.from_euler(Vector3(0.0, motor.heading, 0.0)), global_position)
	return flat * definition.exit_offset + Vector3.UP * 0.3


## Teleports the vehicle to a new place, at rest.
func place(at: Transform3D) -> void:
	global_transform = at
	motor.reset()
	_camera_reversed = false
	if turbo:
		turbo.reset()


func get_speed() -> float:
	return motor.speed


## Yaw the camera should settle on: behind the kart when going forward, in
## front of it (looking at the tail) when reversing. Hysteresis so the view
## does not flip back and forth around a standstill.
func get_heading_yaw() -> float:
	# Front view only while actually reversing; at a standstill go back behind.
	if _camera_reversed and motor.speed > -0.3:
		_camera_reversed = false
	elif not _camera_reversed and motor.speed < -1.0:
		_camera_reversed = true
	return motor.heading + (PI if _camera_reversed else 0.0)


func _apply_definition() -> void:
	abilities.setup(definition.starting_abilities)
	health.setup(definition.max_health)
	motor.setup(self, definition, abilities)

	var shape := collision.shape as BoxShape3D
	if shape:
		shape = shape.duplicate()
		shape.size = definition.collision_size
		collision.shape = shape
		collision.position.y = definition.collision_size.y * 0.5 + 0.1

	for ability in ability_nodes.get_children():
		if ability is VehicleAbility:
			ability.setup(self)
			if ability is TurboAbility:
				turbo = ability

	_spawn_visual()


func _spawn_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	if definition.visual_scene == null:
		return
	_visual_instance = definition.visual_scene.instantiate() as Node3D
	visual_root.add_child(_visual_instance)
