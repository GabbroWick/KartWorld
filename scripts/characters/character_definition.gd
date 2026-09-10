class_name CharacterDefinition
extends Resource
## Data that makes one character different from another.
##
## The gameplay systems are generic: the leopard is just a .tres of this type
## (res://resources/characters/leopard.tres). A tiger, fox, panda or robot is a
## new resource + a new placeholder visual, not new gameplay code.

@export var id: StringName = &"character"
@export var display_name: String = "Character"

@export_group("Visuals")
## Placeholder or final model, instantiated under the character's VisualRoot.
@export var visual_scene: PackedScene
## Uniform scale applied to the model, so one placeholder body serves
## characters of different sizes.
@export_range(0.2, 3.0, 0.01) var visual_scale := 1.0

@export_group("Body")
## Collision capsule, so characters can have different sizes.
@export_range(0.5, 4.0, 0.05) var capsule_height := 1.35
@export_range(0.1, 1.5, 0.01) var capsule_radius := 0.3

@export_group("Movement")
@export_range(0.5, 20.0, 0.1) var walk_speed := 5.0
@export_range(0.5, 30.0, 0.1) var run_speed := 10.0
@export_range(1.0, 200.0, 1.0) var ground_acceleration := 60.0
@export_range(1.0, 200.0, 1.0) var ground_friction := 70.0
@export_range(1.0, 200.0, 1.0) var air_acceleration := 25.0
@export_range(0.0, 200.0, 1.0) var air_friction := 6.0
## How fast the model turns to face the movement direction (rad/s-ish).
@export_range(1.0, 40.0, 0.5) var turn_speed := 14.0
## Tallest ledge walked over without jumping (kerbs, plinths, stairs).
@export_range(0.0, 1.5, 0.05) var max_step_height := 0.45

@export_group("Jump")
## Peak height in metres of a full ground jump.
@export_range(0.2, 10.0, 0.1) var jump_height := 2.7
## Extra air jumps once the `double_jump` ability is unlocked.
@export_range(0, 4, 1) var max_air_jumps := 1
## Air jump strength relative to the ground jump.
@export_range(0.2, 1.5, 0.05) var air_jump_scale := 0.9
## Multiplies project gravity for this character (arcade feel, not realism).
@export_range(0.1, 5.0, 0.05) var gravity_scale := 1.0
## Extra gravity while falling, makes jumps feel snappy instead of floaty.
@export_range(1.0, 4.0, 0.05) var fall_gravity_multiplier := 1.5
## Cutting the jump short by releasing the button.
@export_range(0.0, 1.0, 0.05) var short_hop_damping := 0.6
@export_range(1.0, 100.0, 1.0) var terminal_velocity := 40.0
## Grace period to still jump just after walking off a ledge.
@export_range(0.0, 0.5, 0.01) var coyote_time := 0.12
## Grace period for a jump pressed just before landing.
@export_range(0.0, 0.5, 0.01) var jump_buffer_time := 0.12

@export_group("Vitals")
@export_range(1.0, 100.0, 1.0) var max_health := 5.0

@export_group("Abilities")
## Abilities the character starts with. Others get unlocked by progression.
## Known ids so far: "run", "double_jump".
@export var starting_abilities: PackedStringArray = PackedStringArray(["run", "double_jump"])
