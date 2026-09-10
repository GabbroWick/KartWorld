class_name LevelDefinition
extends Resource
## Metadata for one adventure level. Levels are data: 30-40 of these must be
## possible without a line of level-specific gameplay code.

@export var id: StringName = &"level"
@export var display_name: String = "Level"
## Theme/world the level belongs to (forest, desert, volcano...).
@export var world: StringName = &"forest"
@export_multiline var description := ""
## The playable scene. Must contain a Marker3D in group "player_spawn".
@export var scene: PackedScene
## Ability ids the player must have to enter (empty = always open).
@export var required_abilities: PackedStringArray = PackedStringArray()
## How many stars this level can award in total.
@export_range(0, 20, 1) var star_count := 1
@export var has_boss := false
## Levels unlocked from the start; others get unlocked by progression.
@export var unlocked_by_default := true
