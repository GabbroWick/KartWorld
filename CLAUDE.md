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
| 8 — polish | in progress | done: procedural animation, kart slopes + 4-ray visual suspension, controls hint, health refill, NPC wander/talk, hub stars, gated Cliff Steps level, Web export, Kenney models, Meshy+Mixamo rigged leopard (idle/walk/run/jump/fall/attack/hurt/emote), Italian localization, hit flash + star/enemy bursts, level-complete card, pause menu, synthesised placeholder SFX + engine hum + music slots. next: fox/panda/slime models, real SFX/music files (ASSET_GUIDE.md), touch controls |

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
$G --path . res://tools/capture_screenshot.tscn -- out.png 90 level=res://resources/levels/level_01_forest_trail.tres at=20,0.3,-40   # ...inside a level
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
  dev/test helpers in `tools/`. Real models live in `assets/models/kenney/`
  (CC0, curated .glb subsets; raw zips in untracked `art/`). Characters,
  enemies, house and portal are still primitives.
* Props from models: instance `scenes/world/props/kenney_{tree,rock,plant}.tscn`
  and set `model`; never hand-place raw .glb scenes (no collision, no palette).
  Scatter variety = `PropScatter.models`.
* Character models: `assets/models/meshy/<name>.glb` wrapped by
  `scripts/characters/meshy_character_visual.gd` (feet on ground, flip to -Z,
  flattened PBR, whole-body procedural `animate()`); the definition's
  `visual_scene` points at `scenes/characters/visuals/<name>_meshy.tscn`.
  Meshy exports: pivot at centre, faces +Z, metallic 1.0 — never use raw.
  A rigged model (Mixamo FBX) should subclass MeshyCharacterVisual and drive
  an AnimationTree from the same `animate()` call.
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
* **The game is Italian.** Every player-facing string is a key in
  `translations/text.csv` (columns en/it), shown through `tr()`; data files
  (`display_name`, objective `description`, `dialogue_lines`) hold keys.
  GameManager forces locale `it`. Tests compare with `tr(&"KEY")`. Adding
  text = add a CSV row; the `.translation` files regenerate on import.
* Character clips: `RiggedCharacterVisual` merges Mixamo "without skin" FBX
  clips into the rig at start-up; one-shots (`attack`, `hurt`) via
  `play_action()`; the controller routes `combat.attacked` / `hurt` to it and
  hides the swipe arc when the model has an attack clip.

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
* Kenney kits: units ~1/3 of ours; Car/Platformer/Mini Forest/Buildings .glb
  reference an external `Textures/colormap.png` (keep the folder next to the
  models); the Nature Kit is untextured and teal — `KenneyPalette` recolours
  it by material name. Kenney cars face +Z (`KenneyVehicleVisual` flips).
* `PropScatter` picks model variants from a second RNG: consuming the layout
  RNG for anything else silently moves every prop and breaks the island suite.
* Kart physics: the body is an upright CharacterBody3D with a **sphere**
  collider (r = 0.6) and the model is a 4-ray visual suspension. A box
  collider rested on its front edge 1.7 m above a 50° slope and stalled; a
  slope-aligned box (tried, reverted) drifted while parked, stuttered and
  broke steering. Do not re-project speed from the velocity every tick
  either — the motor owns `speed`, walls take it away.
* `StepUp.try_step` moves the body up AND forward onto the ledge; lifting
  only lets floor snapping pull a long body back off the lip (kart vs the
  portal plinth).
* `make web` / `make test` / `make serve` (GNU make from GnuWin32 is on PATH).
* `CPUParticles3D` starts `emitting = true`: a one-shot burst built in code
  fires at the origin on entering the tree unless created with
  `emitting = false` and `restart()`ed after placement (`Burst.spawn`).
* Running two Godot instances on the project at once (e.g. a Web export in
  the background plus a test) corrupts the class cache for the second one
  ("Identifier X not declared"). Run them one after the other.
* Esc is `pause` now; `toggle_mouse_capture` is F1. Tests feed actions
  through `Input.parse_input_event(InputEventAction)` to reach
  `_unhandled_input`.
* Lighting recipe (palette renders as authored on every renderer, shadows on):
  `tonemap_mode = 0`, `ambient_light_source = 1` (Disabled),
  `reflected_light_source = 1`, ONE sun `light_energy = 0.72`,
  `shadow_enabled = true`, `shadow_opacity = 0.7`. "Ambient" is a material
  term instead: every material emits `FlatMaterial.FILL` (0.28) × its albedo
  (`FlatMaterial.flat/with_fill/apply_fill`, the terrain shader
  `shaders/flat_vertex_fill.gdshader`, KenneyPalette, MeshyCharacterVisual).
  Reason: Compatibility doubles the base pass when a shadowed light coexists
  with ambient OR a second light (godot#90259) — a fill light is not an
  option. New materials/models must go through `FlatMaterial.apply_fill`
  (textured: emission_operator MULTIPLY, else the glow is 100%).
  `test_lighting_runner.tscn` (windowed) guards sunlit and shaded faces.
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
  Marker3D. LevelManager is found via group `level_manager`. A level ends by
  entering its finish portal (`completes_level = true`, the
  `ReachDestinationObjective.goal_zone`), never by standing on a pad. On
  completion `GameManager.set_frozen(true)` pauses the tree (no menu, mouse
  kept) until the hub loads; the card is PROCESS_MODE_ALWAYS.
* Audio: `Sfx` autoload (`scripts/audio/sfx.gd`) — `Sfx.play(&"name")`,
  `Sfx.play_music(&"hub"|&"level")`. File in `assets/audio/sfx/<name>.ogg`
  wins, else `SoundBank` synth. Kart hum: `EngineSound` in vehicle.tscn.
* VFX: `scripts/vfx/hit_flash.gd` (component, enemy scene), `burst.gd`
  (`Burst.spawn`). UI: `scenes/ui/pause_menu.tscn`, card inside game_hud.
* Steps/kerbs: `scripts/core/step_up.gd`, called by both motors. It ignores
  hits on walkable normals (slopes): treating them as steps made the kart hop
  up+forward every frame on uneven ground ("va a scatti anche in piano").
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

## Local AI 3D pipeline (in progress, 2026-09-11)

Human's decision: replace Meshy with a free local pipeline. Details, commands
and the running diary live in `tools/README_3D.md` — read it before touching
`tools/ai3d/` or `tools/blender/`. State:

* Backend: PyTorch 2.12 + ROCm 7.14.1 official Windows wheels, `gfx1200`
  (RX 9060 XT), venv `tools/ai3d/.venv` (uv). `check_gpu.py` passes.
* TripoSR smoke test passes (24 s, 3 GB VRAM) → `_generated/leopard_front_triposr`.
* `tools/blender/import_ai3d.py` verified (orient/scale/decimate/preview).
* Hunyuan3D 2.1 **shape only** via `generate_shape.py` (fork
  VladimirTalyzin/hunyuan3d-2.1-mac-rocm + upstream, pure-torch, no CUDA
  ext) WORKS on the RX 9060 XT: 300 s / 12.3 GB VRAM for 30 steps at
  octree 256. Leopard shape → Blender → `_final/leopard/leopard.glb` →
  `scenes/dev/character_preview.tscn` verified. Known defect: light belly
  patch became a through-hole. Paint/PBR NOT installed yet (next, after
  the human signs off on the shape); then rig, then automation.
* Rules from the human: no TDR registry change without explicit approval
  (key, current value, new value, risk, rollback explained first); announce
  size + disk before every large download; keep _source/_generated/
  _processed/_final separate; never overwrite finals without backup.
* Folders `tools/ai3d`, `tools/blender`, `assets/characters/_source|
  _generated|_processed` carry `.gdignore`; only `_final` is imported.

## Next step (Phase 8 — polish, continued)

Decided with the human (2026-09-10): real models from **Kenney** (done for
props/kart/pickups) and **Meshy** for characters (leopard, fox, panda, slime)
— rigged GLB with animations; the placeholder's `animate(delta, speed_ratio,
grounded)` contract is what a rigged model must implement (drive an
AnimationTree). Audio: ElevenLabs SFX / Suno music, synthetic placeholders
acceptable meanwhile. Web export works and is verified headless.

Done in this pass: hit flash, star/enemy bursts, level-complete card, kart
engine hum + turbo whoosh, pause menu, synthesised placeholder SFX. Waiting
on the human (instructions in `ASSET_GUIDE.md`): Meshy+Mixamo fox / panda /
slime, ElevenLabs SFX files, Suno music (`hub.ogg`, `level.ogg`).

Candidates next, cheapest first: footstep/skid particles, squash & stretch
on land, touch controls, Cliff Steps rebuilt with Platformer Kit
`block-grass-*` pieces, the house from Modular Buildings (needs a door and
the pad test kept). Keep every effect a component or a scene, never a
special case in a controller.
