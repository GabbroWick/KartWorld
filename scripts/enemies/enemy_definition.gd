class_name EnemyDefinition
extends Resource
## Data for one enemy type. Enemies are generic: a slime, a beetle and a robot
## are different .tres files and visuals, not different scripts.

@export var id: StringName = &"enemy"
@export var display_name: String = "Enemy"

@export_group("Visuals")
@export var visual_scene: PackedScene
@export_range(0.2, 3.0, 0.01) var visual_scale := 1.0

@export_group("Body")
@export_range(0.2, 3.0, 0.05) var body_radius := 0.5
@export_range(0.2, 4.0, 0.05) var body_height := 1.0

@export_group("Vitals")
@export_range(1.0, 100.0, 1.0) var max_health := 2.0

@export_group("Behaviour")
@export_range(0.0, 20.0, 0.1) var move_speed := 2.5
## Wanders this far from its start point when nobody is around.
@export_range(0.0, 30.0, 0.5) var patrol_radius := 3.0
## Starts chasing a player closer than this.
@export_range(0.0, 50.0, 0.5) var chase_radius := 7.0
## Gives up beyond this.
@export_range(0.0, 60.0, 0.5) var lose_radius := 11.0

@export_group("Attack")
@export_range(0.0, 20.0, 0.5) var contact_damage := 1.0
@export_range(0.0, 30.0, 0.5) var knockback := 7.0
