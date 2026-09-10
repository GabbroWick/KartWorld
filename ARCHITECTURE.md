# KartWorld — Architecture

Status: Phase 0–7. This document describes what exists today and the
extension points that were deliberately left open. It is updated when the
architecture materially changes, not on every commit.

## Principles

1. **Nothing is built around the leopard.** The leopard is a `.tres` resource
   plus a placeholder model. Gameplay code only knows "a character".
2. **Components over monoliths.** A character is a thin controller plus small
   single-responsibility nodes. No `player.gd` that owns everything.
3. **Only what is needed now**, but no decision that blocks a later phase
   (kart, combat, portals, local co-op, touch input).
4. **Everything is testable headlessly.** Movement and the island are verified
   by scripts, not by a human pressing keys.

## Runtime graph

```text
/root
├── GameManager                    autoload: mouse capture, player registry
├── ProgressionManager             autoload: level results, unlocks, save file
└── Main (scenes/main.tscn)        entry point, spawns the pieces
    ├── World (island_hub.tscn)    terrain, light, props, NPCs, spawn marker
    ├── Character (character.tscn) spawned at the world's PlayerSpawn marker
    │   ├── Collision              CapsuleShape3D, sized from the definition
    │   ├── VisualRoot             holds the instantiated character model
    │   ├── InputSource            device input -> intent snapshot
    │   ├── Motor                  gravity, acceleration, jump, air jumps
    │   ├── Health                 hit points, damage, death signal
    │   └── Abilities              which abilities are unlocked
    ├── CameraRig                  third-person orbit camera (SpringArm3D)
    └── HUD                        debug overlay (temporary)
```

`Main` wires the three top-level pieces together; the world scene contains no
player and the character scene contains no camera, so both stay reusable.

## Character system

### `CharacterDefinition` (Resource)

All per-character data: body size, walk/run speed, acceleration, jump height,
air jumps, gravity scale, health, starting abilities and the visual scene.
A new character (tiger, fox, panda, robot…) is a new `.tres` plus a model — no
gameplay code changes. `resources/characters/` holds the leopard (player) and
the fox and panda used as island NPCs.

### `CharacterController` (CharacterBody3D)

Thin orchestrator, ~120 lines. Every frame it:

1. polls `CharacterInput` for the intent snapshot,
2. converts the 2D move axis into a **camera-relative** world direction,
3. hands that to `CharacterMotor`,
4. turns the visual toward the movement direction.

It also applies the definition to the components at `_ready()` and owns
spawn/respawn. `is_player_controlled = false` turns the same scene into an NPC:
no device input, no registration as a player.

### Components

| Node | Responsibility | Reused later by |
| --- | --- | --- |
| `CharacterInput` | device input → `move_axis`, `run_held`, `jump_pressed`… | AI characters, replays, touch, co-op |
| `CharacterMotor` | gravity, acceleration/friction, jump, coyote time, jump buffering, air jumps | any walking actor |
| `HealthComponent` | max/current health, damage, heal, death signal | enemies, bosses, vehicles |
| `AbilityComponent` | set of unlocked ability ids + signals | progression, power-ups |

The controller polls `CharacterInput` explicitly instead of relying on node
processing order, so the intent is always fresh for the current physics tick.

### Steps and kerbs

`move_and_slide` only climbs what a shape's rounded bottom slides over, so a
capsule of radius 0.3 stops dead at a 0.4 m plinth. `StepUp.try_step()`
(`scripts/core/step_up.gd`) probes ahead / up / ahead / down with `test_move`
and lifts the body onto ledges up to the definition's `max_step_height`
(character 0.45 m, kart 0.5 m). Both motors call it before `move_and_slide`
whenever the body is on the floor and not rising.

### Movement feel

Arcade, not realistic: high gravity (26 m/s²), extra gravity while falling,
coyote time, jump buffering, and a short hop when the jump button is released
early. All of it is data on the definition, not constants in the motor.
Locked after playtesting: leopard capsule 1.35 m (model at `visual_scale`
0.8), walk 5 m/s, run 10 m/s, single jump 2.7 m, double jump ~4.7 m. Levels
are laid out against these numbers: a 2.2 m door is ~1.6 leopards tall, a
single jump clears ~2 leopards, a double jump ~3.5.

### Placeholder visuals

`scenes/characters/visuals/creature_placeholder.tscn` is one primitive creature
body whose mesh nodes carry role groups (`creature_fur`, `creature_belly`,
`creature_accent`, `creature_eye`, `creature_spot`). `CreaturePlaceholder`
paints them from exported colours. Leopard, fox and panda are that scene with
different colour overrides — geometry is shared, identity is data.

It also animates procedurally: the controller calls `animate(delta,
speed_ratio, grounded)` every tick and the placeholder swings legs and arms,
bobs, wags the tail and tucks up in the air. A real rigged model replaces this
by implementing the same `animate()` (driving an AnimationTree instead), so
the controller never changes.

The leopard now uses that contract with a real model: `MeshyCharacterVisual`
wraps `assets/models/meshy/leopard.glb` (an unrigged Meshy export), grounds
and flips it, flattens its PBR material to match the flat props, and gives
the whole body a walk bob, a forward lean with speed, a stretch in the air and
a squash on landing. Limbs stay in the A-pose until the mesh is rigged. Fox,
panda and the slime still use the primitive placeholder.

### NPCs and interaction

`NpcBehaviour` is a child node of an NPC `character.tscn` instance: wander
near home (goals checked with a raycast so nobody walks into walls), stop and
face a player within `notice_radius`, and speak `dialogue_lines` in a Label3D
bubble. It drives the character through `CharacterInput.world_direction`, so
NPCs obey exactly the same physics as the player.

`InteractionComponent` on the character resolves `interact` against anything
in group `interactable` implementing `can_interact / interact / get_prompt`;
it runs before `DriverComponent` and consumes the press, so an NPC standing
by the kart wins over "enter kart". The HUD prompt asks it first.

## Vehicle system

The kart is **its own entity in the world**, never a child of the character.
It is spawned by `Main` next to the player's spawn point and exists whether or
not anyone is driving it; local co-op later means one vehicle per player.

```text
Vehicle (vehicle.tscn, CharacterBody3D, layer 5 "vehicle")
├── Collision          BoxShape3D sized from the definition
├── VisualRoot         instantiated placeholder model
├── InputSource        VehicleInput: throttle / steer / turbo / jump / interact
├── Motor              VehicleMotor: arcade driving physics
├── Health             HealthComponent (same class as the character's)
├── Abilities          AbilityComponent (same class as the character's)
└── AbilityNodes
    └── Turbo          TurboAbility (VehicleAbility)
```

* **`VehicleDefinition`** (Resource) holds every number: speeds, acceleration,
  brake, steering, jump, turbo, health, starting abilities, visual scene.
  `resources/vehicles/basic_kart.tres` is the first; a hover-bike is a new
  `.tres` plus a model.
* **`VehicleController`** is the thin orchestrator: polls input, asks abilities
  to tick, hands throttle/steer/jump to the motor, and exposes
  `mount()` / `dismount()` / `place()`.
* **`VehicleMotor`** is deliberately not a wheel simulation: a signed forward
  speed, an explicit `heading` yaw that steering changes, gravity and a jump.
  The body itself is aligned to the smoothed floor normal every tick
  (`ground_up`, also set as `up_direction`) and driven along the slope plane,
  pressed onto it, so the collision box lies flat on hills instead of resting
  on an edge; in the air it eases back upright. After `move_and_slide()` the
  speed is re-projected on the 3D forward axis, so a wall simply kills the
  speed it blocked. `floor_max_angle` comes from the definition
  (`max_slope_degrees`, 60° for the kart) and `floor_constant_speed` keeps the
  same pace up and down hills. The model needs no extra tilt.
* **`VehicleAbility`** is the base for abilities that own behaviour. They are
  independent nodes under `AbilityNodes`; the controller only calls
  `try_activate()` and `tick()`. Whether an ability is *unlocked* stays in
  `AbilityComponent`, so progression works the same for characters and
  vehicles. Turbo is the first; dash, flight, weapons and defensive systems
  follow the same shape. The kart jump is gated by the `vehicle_jump` ability
  id but implemented in the motor, like the character's double jump.
* **`DriverComponent`** lives on the *character* and owns summon / enter /
  exit. Summon teleports the vehicle 3.5 m ahead on the ground (raycast).
  While driving, the character is hidden, its physics paused and its position
  pinned to the vehicle so "where is the player" keeps working. Leaving places
  the character at the definition's `exit_offset`. If the vehicle falls out of
  the world, the driver is ejected, respawned, and the kart parked beside the
  spawn — the player is never stranded.
* The camera is re-targeted by `Main` through the driver's signals and gets a
  wider framing (`set_framing`) at the wheel. No second camera.

## Real models (Kenney)

`assets/models/kenney/<kit>/*.glb` are imported by Godot as scenes. Three
pieces turn them into game props without per-model code:

* **`ModelProp`** (StaticBody3D, `scripts/world/model_prop.gd`): instantiates
  `model` at `model_scale`, measures its bounds and builds collision —
  `BOX` for rocks, `TRUNK` (narrow cylinder, lower part only) for trees so
  the player brushes past the canopy, `NONE` for flowers. Template scenes
  `kenney_tree.tscn`, `kenney_rock.tscn`, `kenney_plant.tscn` fix scale and
  collision per category.
* **`PropScatter.models`**: a list of model variants; each placed prop gets
  one from a *separate* seeded RNG, so adding or reordering models never
  moves the props (the island suite depends on that layout).
* **`KenneyPalette`**: the Nature Kit ships teal leaves and pink bark. The
  palette remaps materials **by name** (`leafsGreen`, `woodBark`, `stone`…)
  onto the island's greens and browns, applied as per-surface overrides with
  one cached copy per material — the imported resources are never edited.
  Kits that use a texture (Car, Platformer, Mini Forest, Buildings) are left
  alone; their `.glb` files reference an external `Textures/colormap.png`
  that must stay next to them.
* **`KenneyVehicleVisual`**: wraps a Car Kit model as a vehicle visual and
  spins every `wheel*` node from the speed the controller feeds through
  `update_visual(speed, delta)`. Kenney cars face +Z, so it flips them.

Kenney units are ~1/3 of ours (a tree is 1.6 units tall): trees use 2.8×,
rocks 3×, plants 2.2×, the star 2.5×, the flag 3×. The Car Kit is already
life-size (race-future is 2.66 m long, matching the kart's collision box).

## Level system

```text
Main
├── LevelManager        swaps the world; knows hub scene + current LevelDefinition
├── <World>             hub (island_hub.tscn) or a level scene, always first child
├── Character
├── Vehicle
└── CameraRig
```

* **`LevelDefinition`** (Resource): id, name, world theme, description, the
  scene, required abilities, star count, boss flag, unlocked-by-default.
  Thirty or forty of these must be possible without level-specific code, so
  nothing in the manager or the portal knows a level by name.
* **`LevelManager`** (node in Main): `load_level(def)`, `return_to_hub()`,
  `complete_level(stars)`. Swapping frees the current world node, instantiates
  the new scene as Main's first child (camera still updates last), then
  relocates the party: driver ejected if at the wheel, character teleported to
  the scene's `player_spawn` marker facing its way, kart parked 4 m beside it,
  camera snapped behind. Emits `level_loaded`, `hub_loaded` and
  `level_completed(def, stars)` for the progression system to record later.
* **`Portal`** (Area3D on layer 4, mask player|vehicle): walking or driving in
  travels — outbound portals carry a `LevelDefinition`, return portals set
  `returns_to_hub`. Required abilities are checked on the traveller (and on
  progression); a locked portal shows "Needs: Triple jump" in red and refuses,
  and relabels itself the moment the ability is earned. Portals
  are inert for a grace period after any load, so arriving beside one never
  bounces the player back. The manager call is deferred because the world is
  freed from inside a physics callback.
* Every scene that can host the party — hub or level — needs a `Marker3D` in
  group `player_spawn`; that is the whole contract.

### Inside a level

```text
<Level scene root>
├── LevelController          objectives, star count, completion
│   ├── ReachClearing        ReachDestinationObjective (goal_zone = ../../GoalZone)
│   └── CollectStars         CollectObjective (optional)
├── GoalZone                 Area3D
├── Checkpoint, Star, Star   gameplay props
└── geometry, portal, trees
```

* **`Objective`** (Node) is the base: `description`, `optional`,
  `completed` / `progress_changed`, `get_status_text()`. Subclasses:
  `ReachDestinationObjective` (an Area3D goal zone) and `CollectObjective`
  (N collectibles of a kind, 0 = all present). Defeat-enemies comes with
  combat. New objective types are new subclasses; levels pick and configure
  them in the scene, never in code.
* **`LevelController`** (group `level_controller`, a child of the level
  root) collects its `Objective` children and the level's stars, exposes
  `get_current_objective()` for the HUD, and when every non-optional
  objective is complete emits `completed(stars)` and — after
  `completion_delay` — calls `LevelManager.complete_level()`. Levels with a
  goal portal instead set `auto_return = false`.
* **`Collectible`** (Area3D base, group `collectible`): `kind`, `amount`,
  `collected(item, by)`; touching it on foot or in the kart collects.
  `Star` adds spin/bob and the `star` group. Coins, keys and power-ups are
  subclasses or just different `kind` values.
* **`Checkpoint`** (Area3D, group `checkpoint`): touching it calls
  `player.set_spawn_transform(respawn_point, false)`; only one is active at
  a time; the emissive ring on the ground turns from red to green (the Kenney
  flag itself is textured, so state lives on the ring, not the flag). Respawn after a fall or death already uses
  the spawn transform, so nothing else changes.

## Progression and saving

`ProgressionManager` (autoload) is the only thing that persists:

* `best_stars`: level id → best stars in one run (total = sum of bests, so
  replaying never inflates the count).
* `unlocked_abilities`: ability ids granted by progression, on top of what
  each definition starts with.
* `record_level_completion(def, stars)` — connected to
  `LevelManager.level_completed` by `Main`; the first completion grants the
  level's `reward_abilities` (data on `LevelDefinition`).
* `apply_to(AbilityComponent)` pushes unlocked abilities onto a freshly
  spawned character or vehicle; `ability_unlocked` reaches live ones. The
  manager never knows what an ability does — `CharacterMotor` reads
  `enhanced_jump` as one more air jump, a future `ranged_attack` component
  will read its own id.
* `collected`: persistent collectibles (`Collectible.persistent_id`), e.g.
  the island's hub stars — they never respawn and count toward total stars.
  Level collectibles leave the id empty and reset every run.
* Saved as JSON to `save_path` (`user://save.json`) after every change,
  loaded in `_ready()`. Tests point `save_path` at a scratch file and call
  `reset()`. The file carries a `version` for future migrations.

Kept out on purpose: settings, character/kart selection and customisation
(separate concerns, later phases), and any per-level checkpoint state (a
level always restarts from its spawn).

## Combat

* **`CharacterCombat`** (component on the character): the `attack` action
  fires a swing — a hitbox `Area3D` under `VisualRoot` (so it sits in front of
  wherever the model faces) is live for `melee_active_time`, then a
  `melee_cooldown`. Anything it overlaps that has `take_damage(amount,
  source)` gets hit once per swing. Damage, reach, width, timing all come from
  the `CharacterDefinition`. Ranged attacks will be a sibling component that
  spawns projectiles calling the same `take_damage`.
* **Taking damage** is a duck-typed contract: `CharacterController.take_damage`
  and `Enemy.take_damage` both exist, so hazards, projectiles and kart weapons
  never need to know what they hit. The character ignores damage while
  invulnerable or driving, gets shoved away from the source
  (`hurt_knockback`), blinks for `hurt_invulnerability` seconds, and dies
  through the same `HealthComponent.died` → `respawn()` path as falling.
* **`Enemy`** (CharacterBody3D, layer 3, group `enemy`) + **`EnemyDefinition`**
  (health, speed, patrol/chase/lose radii, contact damage, visual). Brain is
  idle → patrol → chase, picking the nearest registered player; a contact
  `Area3D` hurts the player it overlaps. Death = `HealthComponent.died` →
  squash tween → free. Smarter enemies and bosses override `_think()`.
* **`DefeatEnemiesObjective`** counts `died` on the level's enemies.
* Layers: enemy 3 (bit 4). Player hitbox mask = enemy; enemy contact mask =
  player; enemy body mask = world|player.

### HUD

`scenes/ui/game_hud.tscn` (`GameHUD`, CanvasLayer 2): hearts, star counter,
current objective, interaction prompt. Anchored containers, no fixed pixel
positions. It binds to the character's `HealthComponent` signals and to the
`LevelManager`'s `level_loaded` / `hub_loaded`, then to the current
`LevelController`. The F3 developer overlay (`debug_hud.tscn`) stays, hidden
by default.

## World

### `IslandTerrain`

Procedural, flat-shaded height field with trimesh collision, regenerated from
inspector values: plateau/shore radii, beach and plateau heights, one rounded
mountain, simplex noise, and flat pads for buildings. Other nodes query
`sample_height()` / `sample_slope_degrees()` instead of raycasting, which also
works inside the editor. Past the shore the ground drops steeply into the sea,
so walking off the island ends in the normal fall respawn — no separate kill
volume. Face colours (sand → grass → rock → snow) come from height and slope.

### `PropScatter`

Forests, rocks and future bushes are placement rules, not hand-placed nodes:
seed, disc region, exclusion zones, height and slope filters, spacing, scale
range. Deterministic for a given seed; generated children are not saved into
the scene. Resolves its terrain by `NodePath`, falling back to the `terrain`
group.

### Placeholder props

`PlaceholderBlock`, `PlaceholderCone` (roofs, rocks) and `PlaceholderTree` are
`@tool` StaticBody3D scripts driven by size/colour, so the house and the test
arena are a handful of instances with overrides. Level design later follows
the same recipe: reusable mechanic + configuration + layout.

The hub also carries a `PortalSite` node (plinth + `portal_site` marker) so
Phase 4 has a home without touching the terrain.

## Input

Gameplay never reads a key or a pad button. `scripts/core/input_actions.gd`
holds the semantic action names; the actual bindings live in the Godot Input Map
and are generated (and therefore reviewable and reproducible) by
`tools/setup_input_map.gd`.

Keys are bound as **physical** keycodes so WASD stays in place on AZERTY and
QWERTZ keyboards. Every action already has a gamepad binding. Walking and
driving are separate action sets (`move_*`/`run` vs `accelerate`/`brake`/
`turbo`) that happen to share keys; whichever entity is being controlled polls
its own actions, so remapping one never breaks the other.

Adding touch controls later means adding events to the Input Map (or feeding
`CharacterInput` directly) — no gameplay code changes.

## Camera

`ThirdPersonCamera` is a `Node3D` (yaw) → `PitchPivot` (pitch) → `SpringArm3D`
(collision-aware distance) → `Camera3D`. It follows a target with a
frame-rate-independent lerp and runs at a late physics priority so it moves
after the character has moved. `set_target()` / `set_yaw()` / `set_framing()`
exist so the kart and level transitions can re-point it.

**Auto align** (`auto_align`, on at the wheel, off on foot): after
`auto_align_delay` seconds without look input the yaw eases toward the
target's `get_heading_yaw()`, so the camera swings back behind the kart on its
own while the player can still look around at any time. Any target that
implements `get_heading_yaw()` gets the behaviour; the character does not, on
purpose — free camera on foot is the platformer convention.

The camera is the only place allowed to read a physical device directly (mouse
motion), because that is its job. The character asks the camera rig for a basis;
the camera never touches the character's movement.

## Multiplayer readiness

Nothing about the current design assumes a single player:

* player state lives on the character, not in a global singleton;
* `GameManager` keeps a *list* of players and emits signals;
* input is attached to a character instance (`CharacterInput` has a
  `device_id` and a `reads_local_device` switch for remote/AI actors).

Networking itself is not implemented and should not be until the single-player
core is stable.

## Rendering

**Compatibility (OpenGL 3 / WebGL 2) on every platform** — decided in
Phase 2. It is the only renderer that runs on Web, which the design targets,
and the cartoon style needs none of the Forward+-only effects. One renderer
means one look and one thing to test; moving up to Forward+ later would be
painless (superset), the reverse would not.

### Lighting recipe

Lighting is authored so the palette renders exactly as written in the scene
files, on any renderer, with shadows on:

* `Environment`: `tonemap_mode = Linear`, `ambient_light_source = Disabled`,
  `reflected_light_source = Disabled`, sky used only as background.
* One `DirectionalLight3D` at the origin: `light_energy = 0.72`,
  `shadow_enabled`, `shadow_opacity = 0.7`. There is no ambient light and no
  second light.
* The ambient term lives in the materials: everything emits
  `FlatMaterial.FILL` (0.28) × its own albedo — `FlatMaterial.flat()` for
  colours, `flat_vertex_colored()` (a 10-line shader) for the terrain,
  `with_fill()` / `apply_fill()` for imported materials (Kenney, Meshy,
  textured: emission texture with MULTIPLY). Sunlit faces therefore get
  sun + fill = the authored colour; faces turned away get the fill alone
  (≈ 0.44 sRGB on a 0.5 grey), never black.

Why no ambient: Godot's Compatibility renderer re-adds the whole base pass
(ambient and sun) once more whenever a shadowed light is present
([godotengine/godot#90259](https://github.com/godotengine/godot/issues/90259)),
which made the island ~1.3× brighter in sRGB and clipped the greens. Only
"one shadowed sun, zero ambient" renders correctly, and that configuration is
pixel-identical between Compatibility and Forward+ (measured: grass authored
0.42/0.68/0.32 → rendered 0.43/0.69/0.33 on both).

`tools/tests/test_lighting_runner.tscn` measures a sunlit grass patch and a
50 % grey reference quad every run and fails if either drifts from its
authored colour, so an engine upgrade that fixes (or changes) the bug is
caught immediately.

## Engine gotchas found so far

* **Keep a `DirectionalLight3D` at the origin.** Giving the sun a non-zero
  `position` in Godot 4.7 breaks the directional shadow frustum and drops the
  entire scene into shadow (it then looks flat and blue, lit only by ambient).
  Only its rotation matters.
* **Godot front faces wind clockwise.** A CCW triangle is culled from the
  visible side and its trimesh collision only works from below. Build normals
  with `Plane(a, b, c)` so they follow the same rule as the renderer.
* **Node exports in hand-written scenes.** `@export var t: SomeNodeType` set as
  `NodePath(...)` in a `.tscn` written by hand stays null at runtime. Export a
  `NodePath` and resolve it in code instead.
* **A Node3D under a plain Node is a top-level 3D node.** Its transform is
  world space, so an `Area3D` hitbox parented to a component `Node` sits at
  the origin forever. Put 3D helpers under a Node3D and point the component at
  them with a `NodePath`.
* **Vertex colours are linear by default.** Set `vertex_color_is_srgb = true`
  on the material when the palette is authored as normal sRGB colours.
* **`--script` main loops don't see autoloads.** Scripts run with
  `godot --script` are compiled before autoloads register, so the test suites
  run as *scenes* (`tools/tests/*_runner.tscn`) instead.
* **Simulated input needs one physics tick** to reach a character that polls
  `Input`, which the tests account for.
* **Compatibility + shadows + ambient = overexposure.** See the lighting
  recipe above; keep ambient disabled and use `shadow_opacity` for fill.
* **`StandardMaterial3D` has no `specular` property in Godot 4** — it is
  `metallic_specular`. Setting `specular` only logs a "SpatialMaterial
  remapped parameter" warning and does nothing.
* **`PlaceholderMaterial` is a built-in Godot class** (placeholder for missing
  resources). A `class_name` clashing with it fails with "Static function not
  found in base GDScriptNativeClass". Ours is `FlatMaterial`.
* **Capturing the mouse warps it.** The first `InputEventMouseMotion` after
  `MOUSE_MODE_CAPTURED` carries the jump to the window centre. The camera
  ignores motion for 0.15 s after capture and drops any single delta over
  300 px, otherwise the view starts in a random direction on every launch.

## Open questions (for the human developer)

* **House interior.** The base is solid for now; when customisation/trophies
  arrive it needs an interior or a separate interior scene.
