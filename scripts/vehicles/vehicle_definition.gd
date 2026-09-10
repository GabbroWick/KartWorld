class_name VehicleDefinition
extends Resource
## Data that makes one vehicle different from another.
##
## Mirrors CharacterDefinition: the basic kart is a .tres of this type, a
## future hover-bike or heavy truck is another .tres plus a visual scene.

@export var id: StringName = &"vehicle"
@export var display_name: String = "Vehicle"

@export_group("Visuals")
@export var visual_scene: PackedScene

@export_group("Body")
@export var collision_size := Vector3(1.6, 0.8, 2.6)
## Where the driver reappears when leaving, relative to the vehicle.
@export var exit_offset := Vector3(2.0, 0.5, 0.0)

@export_group("Driving")
@export_range(1.0, 60.0, 0.5) var max_speed := 16.0
@export_range(1.0, 30.0, 0.5) var reverse_speed := 5.0
@export_range(1.0, 100.0, 0.5) var acceleration := 14.0
@export_range(1.0, 100.0, 0.5) var brake_deceleration := 28.0
## Deceleration when neither accelerating nor braking.
@export_range(0.0, 50.0, 0.5) var coast_deceleration := 6.0
## Yaw speed at full steering, radians per second.
@export_range(0.1, 10.0, 0.05) var steer_rate := 2.2
## Speed at which steering reaches full authority (slower = tighter turns).
@export_range(0.5, 30.0, 0.5) var steer_full_speed := 6.0
## Steering authority while airborne, 0..1.
@export_range(0.0, 1.0, 0.05) var air_steer_factor := 0.35

@export_group("Jump")
@export_range(0.2, 10.0, 0.1) var jump_height := 1.6
@export_range(0.1, 5.0, 0.05) var gravity_scale := 1.0
@export_range(1.0, 100.0, 1.0) var terminal_velocity := 40.0

@export_group("Turbo")
@export_range(1.0, 4.0, 0.05) var turbo_speed_multiplier := 1.6
@export_range(1.0, 4.0, 0.05) var turbo_acceleration_multiplier := 2.5
@export_range(0.1, 10.0, 0.1) var turbo_duration := 1.5
@export_range(0.0, 20.0, 0.1) var turbo_cooldown := 3.0

@export_group("Vitals")
@export_range(1.0, 100.0, 1.0) var max_health := 6.0

@export_group("Abilities")
## Known ids so far: "turbo", "vehicle_jump".
@export var starting_abilities: PackedStringArray = PackedStringArray(["turbo", "vehicle_jump"])
