class_name Burst
extends CPUParticles3D
## One-shot puff of coloured squares: star pickups, defeated enemies, landings.
## CPU particles so it renders the same on Compatibility and on the Web.
## Frees itself when done. Use `Burst.spawn(...)`, never keep a reference.

const GROUP := &"burst"


## Spawns a burst at `position` in world space, parented to `world` (any
## node inside the current world; a Node3D so it dies with the level).
static func spawn(world: Node, position: Vector3, color: Color, count := 16,
		speed := 5.0, size := 0.18) -> Burst:
	var burst := Burst.new()
	# Particles default to emitting: with one_shot + explosiveness 1 the whole
	# burst would fire at the origin on entering the tree, before it is placed.
	burst.emitting = false
	burst.amount = count
	burst.lifetime = 0.6
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = false
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = speed * 0.6
	burst.initial_velocity_max = speed
	burst.gravity = Vector3(0.0, -12.0, 0.0)
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 0.7
	burst.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	burst.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	burst.mesh = quad
	burst.add_to_group(GROUP)
	world.add_child(burst)
	burst.global_position = position
	burst.restart()
	burst.finished.connect(burst.queue_free)
	return burst
