# KartWorld — working notes for Claude Code

Read this first. Then `KARTWORLD_GAME_DESIGN.md` (what the game is) and
`CLAUDE_CODE_MASTER_PROMPT.md` (how we work) only when a task touches design or
process. `ARCHITECTURE.md` explains the code; `README.md` is for humans.

## Status

| Phase | State | Notes |
| --- | --- | --- |
| 0 — project setup | done | Godot 4.7.2, git, input map, structure |
| 1 — character | done | walk/run/jump/double jump, camera, 62 headless checks |
| 2 — island hub | done | procedural island, forest, mountain, house, NPCs |
| 3 — kart | done | separate entity, summon, enter/exit, drive, turbo, jump, camera auto-align at the wheel |
| 4 — portal | done | LevelDefinition + LevelManager + Portal, first level scene, 33 checks |
| 5 — first level | done | objectives, stars, checkpoint, game HUD, 35 checks |
| 6 — combat | done | melee, slime enemy, contact damage, i-frames, death, defeat objective, 33 checks |
| 7 — progression | done | ProgressionManager autoload, reward abilities, triple jump unlock, JSON save, 29 checks |
| 8 — polish | in progress | done: procedural animation, swipe arc, kart slopes+tilt, controls hint, health refill, NPC wander/talk, hub stars, gated Cliff Steps level. next: real models, VFX, audio |

Decided: **Compatibility renderer on all platforms** (Web needs it, cartoon
style does not need Forward+). **Character scale locked** after playtesting
(2026-09-10): leopard capsule 1.35 m, visual_scale 0.8, walk 5 / run 10 m/s,
jump 2.7 m (double ~4.7 m). Level metrics from here on are built against
these numbers; door 2.2 m ≈ 1.6 leopards, like a Mario-style world.

## Loop

PLAN → IMPLEMENT → RUN → TEST → FIX → DOCUMENT → COMMIT. One phase per session,
verify before moving on, stop and report at the end of a phase.

## Commands

Godot binary (this machine): `C:\Godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe`
(`_console` prints to the terminal; the non-console exe is the same engine).

```bash
G="/c/Godot/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe"
$G --headless --path . res://tools/tests/test_runner.tscn          # movement suite
$G --headless --path . res://tools/tests/test_kart_runner.tscn     # kart suite
$G --headless --path . res://tools/tests/test_island_runner.tscn   # island suite
$G --headless --path . res://tools/tests/test_portal_runner.tscn   # portal / level-swap suite
$G --headless --path . res://tools/tests/test_level_runner.tscn    # objectives / stars / checkpoint / HUD suite
$G --headless --path . res://tools/tests/test_combat_runner.tscn   # melee / enemies / damage / death suite
$G --headless --path . res://tools/tests/test_progression_runner.tscn  # unlocks / best stars / save suite
$G --headless --path . res://tools/tests/test_hub_runner.tscn      # hub stars / gated portal / Cliff Steps suite
$G --path . res://tools/tests/test_lighting_runner.tscn            # lighting suite (needs a window)
$G --path . res://tools/capture_screenshot.tscn -- out.png 120     # render a frame to PNG
$G --path . res://tools/capture_screenshot.tscn -- out.png 120 drive   # ...while driving the kart
$G --path . --quit-after 400                                       # run the game 400 frames
$G --headless --path . --editor --quit                             # reimport / refresh class cache
$G --headless --path . --script res://tools/setup_input_map.gd     # regenerate input map
$G --headless --path . --export-release "Web" builds/web/index.html   # web export (templates installed)
python tools/serve_web.py                                          # serve builds/web on :8060
"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --virtual-time-budget=90000 --enable-logging=stderr --screenshot=out.png http://localhost:8060/index.html   # headless browser check
```

Web export templates 4.7.2 are installed in
`%APPDATA%/Godot/export_templates/4.7.2.stable/` (web_* zips only). Web
gotchas: no pointer lock without a click; the default font has no ♥/★ glyphs
(HUD draws them as polygons: `scripts/ui/heart_bar.gd`, `star_icon.gd`).

Run the two suites and a screenshot after every change; read the PNG. Both
suites exit non-zero on failure.

## Conventions

* Scenes in `scenes/`, scripts mirror them in `scripts/`, data in `resources/`,
  dev/test helpers in `tools/`. Placeholder art is primitives only.
* Gameplay reads actions from `InputActions`, never keys. Bindings come from
  `tools/setup_input_map.gd`.
* A character = `scenes/characters/character.tscn` + a `CharacterDefinition`
  `.tres` + a visual scene. Never special-case the leopard.
* Components, not monoliths: controller / input / motor / health / abilities.
* World props are `@tool` scripts driven by exported size/colour; forests and
  rocks are `PropScatter` rules, not hand-placed nodes.
* Tests are scenes under `tools/tests/` (autoloads are unavailable to
  `--script` main loops).
* Commit per feature with a conventional message; never rewrite history.

## Engine gotchas (cost real time already)

* `DirectionalLight3D` must stay at position (0,0,0) — a positioned one drops
  the whole scene into shadow (looks blue and flat).
* Godot front faces wind **clockwise**. Build normals with `Plane(a, b, c)`;
  CCW triangles are invisible from above and collide from below.
* In hand-written `.tscn`, export Node references as `NodePath` and resolve in
  code; a typed `@export var x: SomeNode` set as `NodePath(...)` stays null.
* Vertex-colour materials need `vertex_color_is_srgb = true` or colours wash out.
* `Input.action_press()` reaches a polling character one physics tick later.
* Hand-written `Transform3D(...)` in `.tscn` lists basis columns X, Y, Z then
  origin; prefer `rotation_degrees` for readability.
* A Node3D under a plain `Node` is top-level (world origin): put 3D helpers
  (hitboxes) under a Node3D and reach them by NodePath.
* Children `_ready` before parents: a component that touches the character's
  `@onready` fields must defer its setup one frame.
* Lighting recipe (palette renders as authored on every renderer, shadows on):
  `tonemap_mode = 0`, `ambient_light_source = 1` (Disabled),
  `reflected_light_source = 1`, one sun `light_energy = 1.25`,
  `shadow_enabled = true`, `shadow_opacity = 0.7` (= the fill light).
  Reason: Compatibility re-adds the base pass when a shadowed light and any
  ambient coexist (godot#90259). Any ambient or second light → ~1.3× brighter.
  `test_lighting_runner.tscn` (windowed) guards this.
* Materials: use `FlatMaterial.flat(color)`; `StandardMaterial3D.specular`
  does not exist (`metallic_specular`). `PlaceholderMaterial` is a Godot
  built-in name — do not reuse it.
* First mouse-motion event after capturing the cursor is the OS warp to the
  window centre; the camera ignores it (`CAPTURE_SETTLE_TIME`). Symptom was a
  random camera heading on every launch and in screenshots.
* The screenshot tool runs windowed, so it *does* capture the mouse; keep the
  physical cursor still or rely on the settle window.

## Where things are

* Entry: `scenes/main.tscn` → `scripts/core/main.gd` spawns world + player + camera.
* Hub: `scenes/world/island_hub.tscn` (terrain, house, portal site marker,
  scatters, NPCs). Test arena: `scenes/world/test_arena.tscn`, used by
  `scenes/dev/movement_gym.tscn`.
* Characters: `scripts/characters/`, definitions in `resources/characters/`
  (leopard = player; fox, panda = NPCs), visuals in `scenes/characters/visuals/`.
* Vehicles: `scripts/vehicles/` (controller, definition, components/), scene
  `scenes/vehicles/vehicle.tscn`, data `resources/vehicles/basic_kart.tres`.
  Character side: `scripts/characters/components/driver_component.gd`.
* Levels: `scripts/levels/` (LevelDefinition, LevelManager, Portal), level
  scenes in `scenes/levels/`, metadata in `resources/levels/`, portal prop
  `scenes/world/props/portal.tscn`. Every hostable scene has a `player_spawn`
  Marker3D. LevelManager is found via group `level_manager`.
* Steps/kerbs: `scripts/core/step_up.gd`, called by both motors.
* In-level gameplay: `scripts/levels/level_controller.gd` + `objective.gd`
  subclasses (reach, collect); `scripts/gameplay/` collectible, star,
  checkpoint; scenes in `scenes/gameplay/`. HUD: `scripts/ui/game_hud.gd`.
* Combat: `scripts/characters/components/character_combat.gd` (hitbox under
  `VisualRoot/Hitbox`), `scripts/enemies/` (Enemy + EnemyDefinition), scene
  `scenes/enemies/enemy.tscn`, data `resources/enemies/slime.tres`. Damage is
  duck-typed: anything with `take_damage(amount, source)`.
* Progression: `scripts/core/progression_manager.gd` (autoload). Rewards are
  `LevelDefinition.reward_abilities`; abilities are ids read by whoever
  implements them (`enhanced_jump` → `CharacterMotor.get_max_air_jumps`).
  Tests that complete levels set `ProgressionManager.save_path` to a scratch
  file and call `reset()` — never let a test write the real `user://save.json`.
* NPCs: `scripts/characters/components/npc_behaviour.gd` (child of a
  character instance; wander + talk). Player-side `interaction_component.gd`
  resolves `E` against group `interactable` before the kart.
* Every test suite starts with `ProgressionManager.save_path = scratch` +
  `reset()`; the user's real save (`%APPDATA%/Godot/app_userdata/KartWorld/
  save.json`) already has enhanced_jump and would change jump behaviour.
* Groups: `terrain`, `player_spawn`, `portal_site`, `portal`, `level_manager`,
  `level_controller`, `collectible`, `star`, `checkpoint`, `enemy`,
  `interactable`.
* Physics layers: 1 world, 2 player, 3 enemy, 4 interactable, 5 vehicle.
  Player mask = world|vehicle (17); vehicle mask = world (1); portal area on
  layer 4 with mask player|vehicle (18).

## Next step (Phase 8 — polish)

The vertical slice is functionally complete (design doc §25 / master prompt
§4). Polish is where the human and the 8-year-old designer should steer:
which feels bad, what looks confusing. Candidates, cheapest first: squash &
stretch on jump/land, attack swipe arc, hit flash on enemies, star pickup
burst + sound, level-complete fanfare, kart engine hum and turbo whoosh,
footstep/skid particles, a "level complete" card with stars, an ability-gated
second portal (`required_abilities = ["enhanced_jump"]`) to prove the gate,
touch controls for Android/iOS, a pause menu. Keep every effect a component
or a scene, never a special case in a controller.
