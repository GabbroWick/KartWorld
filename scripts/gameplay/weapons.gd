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
## Kart upgrades, also for stars (owned once, never equipped).
const UPGRADES := {
	&"wings": {"price": 5, "name": "UPGRADE_WINGS", "desc": "UPGRADE_WINGS_DESC", "color": Color(0.85, 0.9, 1.0)},
}
const UPGRADE_ORDER: Array[StringName] = [&"wings"]


static func exists(id: StringName) -> bool:
	return CATALOGUE.has(id)


static func stats(id: StringName) -> Dictionary:
	if CATALOGUE.has(id):
		return CATALOGUE[id]
	return {"price": 0, "damage": 1.0, "reach": 1.0, "ranged": false, "name": "WEAPON_PAWS", "desc": "WEAPON_PAWS_DESC", "color": Color.WHITE}


static func price(id: StringName) -> int:
	return int(stats(id)["price"])


## A little model to put in the hand (or throw): parts assembled from
## primitives, +Y along the weapon from the grip, so no asset is needed.
static func make_visual(id: StringName) -> Node3D:
	var root := Node3D.new()
	match id:
		&"club":
			_part(root, _cyl(0.035, 0.05, 0.3, Color(0.5, 0.33, 0.18)), Vector3(0.0, 0.15, 0.0))
			_part(root, _cyl(0.07, 0.11, 0.26, Color(0.6, 0.4, 0.22)), Vector3(0.0, 0.42, 0.0))
			_part(root, _sphere(0.11, Color(0.6, 0.4, 0.22)), Vector3(0.0, 0.55, 0.0))
			for i in 6:
				var a := i * TAU / 6.0
				_part(root, _sphere(0.03, Color(0.35, 0.35, 0.38)), Vector3(cos(a) * 0.1, 0.5, sin(a) * 0.1))
			_part(root, _cyl(0.045, 0.045, 0.03, Color(0.3, 0.2, 0.1)), Vector3(0.0, 0.0, 0.0))
		&"boomerang":
			var wood := Color(0.9, 0.62, 0.22)
			var stripe := Color(0.85, 0.25, 0.2)
			for side in [-1.0, 1.0]:
				var arm := _box(Vector3(0.07, 0.24, 0.025), wood)
				arm.rotation.z = side * deg_to_rad(38.0)
				arm.position = Vector3(side * 0.085, 0.1, 0.0)
				root.add_child(arm)
				var band := _box(Vector3(0.075, 0.05, 0.03), stripe)
				band.rotation.z = side * deg_to_rad(38.0)
				band.position = Vector3(side * 0.15, 0.185, 0.0)
				root.add_child(band)
				_part(root, _sphere(0.04, wood), Vector3(side * 0.2, 0.245, 0.0))
			_part(root, _sphere(0.045, wood), Vector3(0.0, 0.0, 0.0))
		&"sword":
			var gold := Color(0.95, 0.8, 0.3)
			var steel := Color(0.9, 0.93, 1.0)
			_part(root, _cyl(0.03, 0.03, 0.16, Color(0.35, 0.2, 0.12)), Vector3(0.0, 0.08, 0.0))
			_part(root, _sphere(0.045, gold), Vector3(0.0, -0.01, 0.0))
			var guard := _box(Vector3(0.22, 0.04, 0.05), gold)
			guard.position = Vector3(0.0, 0.18, 0.0)
			root.add_child(guard)
			var blade := _box(Vector3(0.07, 0.5, 0.018), steel)
			blade.position = Vector3(0.0, 0.45, 0.0)
			root.add_child(blade)
			var tip := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.07, 0.12, 0.018)
			prism.material = FlatMaterial.flat(steel)
			tip.mesh = prism
			tip.position = Vector3(0.0, 0.76, 0.0)
			root.add_child(tip)
			var fuller := _box(Vector3(0.012, 0.42, 0.02), Color(0.7, 0.75, 0.85))
			fuller.position = Vector3(0.0, 0.42, 0.0)
			root.add_child(fuller)
		_:
			return null
	return root


static func _part(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	parent.add_child(m)
	return m


static func _cyl(top: float, bottom: float, height: float, color: Color) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 10
	m.material = FlatMaterial.flat(color)
	return m


static func _sphere(radius: float, color: Color) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 5
	m.material = FlatMaterial.flat(color)
	return m


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = FlatMaterial.flat(color)
	m.mesh = box
	return m


## Kept for callers that want a single mesh (the shop icon): the boomerang.
static func make_mesh(id: StringName) -> Mesh:
	var color: Color = stats(id)["color"]
	var m := BoxMesh.new()
	m.size = Vector3(0.36, 0.03, 0.09) if id == &"boomerang" else Vector3(0.05, 0.5, 0.05)
	m.material = FlatMaterial.flat(color)
	return m
