extends Node
## Autoload: what the player has achieved and unlocked, persisted to disk.
##
## Records level completions (best stars per level), grants ability rewards
## on a level's first completion, and pushes unlocked abilities onto any
## AbilityComponent that asks. Saves to `save_path` after every change and
## loads at start. Nothing here knows a level or an ability by name: levels
## declare their rewards, abilities are ids.

signal changed
signal ability_unlocked(id: StringName)
signal level_recorded(level_id: StringName, stars: int, first_time: bool)

const SAVE_VERSION := 1

## Where progress is stored. Tests point this at a scratch file.
var save_path := "user://save.json"

## level id -> best stars collected in a single run.
var best_stars: Dictionary = {}
## Ability ids granted by progression (on top of the definitions' starters).
var unlocked_abilities: Array[StringName] = []
## The hero's character id (see CharacterRoster). Saved.
var character: StringName = &"leopard"
## Food and things carried: item id -> count (fruit, meat, meal). Saved.
var inventory: Dictionary = {}
## Stars spent in the shop (the total stars never go down; the wallet is
## total - spent). Saved.
var stars_spent := 0
## Weapons bought (Weapons catalogue ids) and the one in the hand. Saved.
var owned_weapons: Array[StringName] = []
var equipped_weapon: StringName = &""
## Persistent collectibles picked up, id -> {"kind": String, "amount": int}.
var collected: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()


## Best stars over all levels plus every persistent star found in the world.
func get_total_stars() -> int:
	var total := 0
	for stars in best_stars.values():
		total += int(stars)
	for entry in collected.values():
		if entry.get("kind", "") == "star":
			total += int(entry.get("amount", 1))
	return total


func is_collected(id: StringName) -> bool:
	return collected.has(String(id))


func record_collected(id: StringName, kind: StringName, amount: int) -> void:
	if is_collected(id):
		return
	collected[String(id)] = {"kind": String(kind), "amount": amount}
	changed.emit()
	save_to_disk()


func is_level_completed(level_id: StringName) -> bool:
	return best_stars.has(String(level_id))


func get_best_stars(level_id: StringName) -> int:
	return int(best_stars.get(String(level_id), 0))


func has_ability(id: StringName) -> bool:
	return id in unlocked_abilities


## Called when a level ends. Keeps the best star count and, the first time,
## grants the level's reward abilities.
func record_level_completion(definition: LevelDefinition, stars: int) -> void:
	if definition == null:
		return
	var key := String(definition.id)
	var first_time := not best_stars.has(key)
	best_stars[key] = maxi(get_best_stars(definition.id), stars)
	level_recorded.emit(definition.id, stars, first_time)
	if first_time:
		for ability in definition.reward_abilities:
			unlock_ability(StringName(ability))
	changed.emit()
	save_to_disk()


func unlock_ability(id: StringName) -> void:
	if has_ability(id):
		return
	unlocked_abilities.append(id)
	ability_unlocked.emit(id)
	changed.emit()
	save_to_disk()


## Grants every progression ability to a component (character or vehicle).
## Call once when the actor spawns; live unlocks arrive via `ability_unlocked`.
func apply_to(abilities: AbilityComponent) -> void:
	for id in unlocked_abilities:
		abilities.unlock(id)


## Stars still in the wallet: everything earned minus what the shop took.
func get_available_stars() -> int:
	return maxi(get_total_stars() - stars_spent, 0)


func owns_weapon(id: StringName) -> bool:
	return id in owned_weapons


## Buys and equips a weapon if the wallet allows; false otherwise.
func buy_weapon(id: StringName) -> bool:
	if not Weapons.exists(id) or owns_weapon(id):
		return false
	var cost := Weapons.price(id)
	if get_available_stars() < cost:
		return false
	stars_spent += cost
	owned_weapons.append(id)
	equipped_weapon = id
	save_to_disk()
	changed.emit()
	return true


## Puts an owned weapon (or paws, `&""`) in the hand.
func equip_weapon(id: StringName) -> void:
	if id != &"" and not owns_weapon(id):
		return
	equipped_weapon = id
	save_to_disk()
	changed.emit()


func add_item(item: StringName, amount: int = 1) -> void:
	inventory[String(item)] = count_item(item) + amount
	save_to_disk()
	changed.emit()


## Takes `amount` of `item` if there is enough; false otherwise.
func take_item(item: StringName, amount: int = 1) -> bool:
	if count_item(item) < amount:
		return false
	inventory[String(item)] = count_item(item) - amount
	if inventory[String(item)] <= 0:
		inventory.erase(String(item))
	save_to_disk()
	changed.emit()
	return true


func count_item(item: StringName) -> int:
	return int(inventory.get(String(item), 0))


func set_character(id: StringName) -> void:
	if id == character:
		return
	character = id
	save_to_disk()
	changed.emit()


func reset() -> void:
	best_stars.clear()
	unlocked_abilities.clear()
	collected.clear()
	character = &"leopard"
	inventory.clear()
	stars_spent = 0
	owned_weapons.clear()
	equipped_weapon = &""
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	changed.emit()


func save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"best_stars": best_stars,
		"unlocked_abilities": Array(unlocked_abilities).map(func(id: StringName) -> String: return String(id)),
		"collected": collected,
		"character": String(character),
		"inventory": inventory,
		"stars_spent": stars_spent,
		"owned_weapons": Array(owned_weapons).map(func(id: StringName) -> String: return String(id)),
		"equipped_weapon": String(equipped_weapon),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("ProgressionManager: cannot write %s (%s)" % [save_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func load_from_disk() -> void:
	best_stars.clear()
	unlocked_abilities.clear()
	collected.clear()
	inventory.clear()
	stars_spent = 0
	owned_weapons.clear()
	equipped_weapon = &""
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("ProgressionManager: cannot read %s" % save_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("ProgressionManager: save file is not valid, starting fresh.")
		return
	var data: Dictionary = parsed
	for key in data.get("best_stars", {}):
		best_stars[String(key)] = int(data["best_stars"][key])
	for id in data.get("unlocked_abilities", []):
		unlocked_abilities.append(StringName(String(id)))
	character = StringName(String(data.get("character", "leopard")))
	inventory.clear()
	for key in data.get("inventory", {}):
		inventory[String(key)] = int(data["inventory"][key])
	stars_spent = int(data.get("stars_spent", 0))
	owned_weapons.clear()
	for id in data.get("owned_weapons", []):
		owned_weapons.append(StringName(String(id)))
	equipped_weapon = StringName(String(data.get("equipped_weapon", "")))
	for id in data.get("collected", {}):
		var entry: Dictionary = data["collected"][id]
		collected[String(id)] = {"kind": String(entry.get("kind", "item")), "amount": int(entry.get("amount", 1))}
	changed.emit()
