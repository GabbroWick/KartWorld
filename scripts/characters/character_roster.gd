class_name CharacterRoster
extends RefCounted
## The playable cast: which characters exist, who the player is right now
## (ProgressionManager.character, saved) and who an NPC should be instead
## when its definition is the one the player picked.
##
## Rule: NPCs never duplicate the player's character; the leopard fills
## in for them (so the leopard is an NPC whenever it is not the hero).

const IDS: Array[StringName] = [&"leopard", &"fox", &"panda"]
const PATHS := {
	&"leopard": "res://resources/characters/leopard.tres",
	&"fox": "res://resources/characters/fox.tres",
	&"panda": "res://resources/characters/panda.tres",
}


static func definition(id: StringName) -> CharacterDefinition:
	if not PATHS.has(id):
		id = IDS[0]
	return load(PATHS[id]) as CharacterDefinition


static func player_definition() -> CharacterDefinition:
	return definition(ProgressionManager.character)


## The next character after `id` in the roster (menu cycling).
static func next(id: StringName) -> StringName:
	var index := IDS.find(id)
	return IDS[(index + 1) % IDS.size()]


## What an NPC with `wanted` should look like: unchanged unless it is the
## player's character, then the leopard (or the first other one).
static func for_npc(wanted: CharacterDefinition) -> CharacterDefinition:
	if wanted == null or wanted.id != ProgressionManager.character:
		return wanted
	for id in IDS:
		if id != wanted.id:
			return definition(id)
	return wanted
