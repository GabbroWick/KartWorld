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
| 4 — portal | **next** | portal on the PortalSite, level scene load, return to hub |
| 5 — first level | todo | objective, star, checkpoint |
| 6 — combat | todo | enemy, damage, death, respawn |
| 7 — progression | todo | |
| 8 — polish | todo | |

Decided: **Compatibility renderer on all platforms** (Web needs it, cartoon
style does not need Forward+). Still open for the human: final character scale
(cheap to change; see ARCHITECTURE.md).

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
$G --path . res://tools/tests/test_lighting_runner.tscn            # lighting suite (needs a window)
$G --path . res://tools/capture_screenshot.tscn -- out.png 120     # render a frame to PNG
$G --path . res://tools/capture_screenshot.tscn -- out.png 120 drive   # ...while driving the kart
$G --path . --quit-after 400                                       # run the game 400 frames
$G --headless --path . --editor --quit                             # reimport / refresh class cache
$G --headless --path . --script res://tools/setup_input_map.gd     # regenerate input map
```

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
* Groups: `terrain`, `player_spawn`, `portal_site`.
* Physics layers: 1 world, 2 player, 3 enemy, 4 interactable, 5 vehicle.
  Player mask = world|vehicle (17); vehicle mask = world (1).

## Next step (Phase 4 — portal)

A `Portal` scene placed on the hub's `PortalSite` marker: `interact` (or
walking in) loads a level scene by metadata (`LevelDefinition` resource: id,
name, scene, objectives placeholder), a `LevelManager` in `Main` swaps the
world, moves player + kart to the level's spawn, and a return portal / exit
brings them back to the hub. Keep the kart summonable inside levels. Add
`tools/tests/test_portal*` before calling it done.
