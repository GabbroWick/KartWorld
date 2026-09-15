class_name Weapons
extends RefCounted
## The weapon catalogue sold in the shop (paid with stars) and read by
## CharacterCombat. Paws (`&""`) are the default: damage x1, no reach.
## Melee weapons multiply the definition's damage and reach; a ranged one
## throws a Boomerang instead of swinging.

const CATALOGUE := {
	&"club": {"price": 3, "damage": 2.0, "reach": 1.15, "ranged": false,
		"name": "WEAPON_CLUB", "desc": "WEAPON_CLUB_DESC", "color": Color(0.55, 0.35, 0.2)},
	&"boomerang": {"price": 6, "damage": 1.0, "reach": 1.0, "ranged": true,
		"name": "WEAPON_BOOMERANG", "desc": "WEAPON_BOOMERANG_DESC", "color": Color(0.9, 0.6, 0.2)},
	&"sword": {"price": 10, "damage": 3.0, "reach": 1.5, "ranged": false,
		"name": "WEAPON_SWORD", "desc": "WEAPON_SWORD_DESC", "color": Color(0.95, 0.8, 0.3)},
}
const ORDER: Array[StringName] = [&"club", &"boomerang", &"sword"]


static func exists(id: StringName) -> bool:
	return CATALOGUE.has(id)


static func stats(id: StringName) -> Dictionary:
	if CATALOGUE.has(id):
		return CATALOGUE[id]
	return {"price": 0, "damage": 1.0, "reach": 1.0, "ranged": false, "name": "WEAPON_PAWS", "desc": "WEAPON_PAWS_DESC", "color": Color.WHITE}


static func price(id: StringName) -> int:
	return int(stats(id)["price"])


## A little mesh to put in the hand (BoneAttachment3D): club, boomerang
## or sword, built from primitives so no asset is needed.
static func make_mesh(id: StringName) -> Mesh:
	var color: Color = stats(id)["color"]
	match id:
		&"club":
			var m := CapsuleMesh.new()
			m.radius = 0.06
			m.height = 0.42
			m.material = FlatMaterial.flat(color)
			return m
		&"boomerang":
			var m := BoxMesh.new()
			m.size = Vector3(0.36, 0.03, 0.09)
			m.material = FlatMaterial.flat(color)
			return m
		&"sword":
			var m := BoxMesh.new()
			m.size = Vector3(0.05, 0.55, 0.02)
			m.material = FlatMaterial.flat(color)
			return m
	return null
