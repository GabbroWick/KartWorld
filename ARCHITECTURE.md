# KartWorld — Architecture

Status: Phase 0–1 only. This document describes what exists today and the
extension points that were deliberately left open. It is updated when the
architecture materially changes, not on every commit.

## Principles

1. **Nothing is built around the leopard.** The leopard is a `.tres` resource
   plus a placeholder model. Gameplay code only knows "a character".
2. **Components over monoliths.** A character is a thin controller plus small
   single-responsibility nodes. No `player.gd` that owns everything.
3. **Only what is needed now**, but no decision that blocks a later phase
   (kart, combat, portals, local co-op, touch input).
4. **Everything is testable headlessly.** Movement is verified by a script, not
   by a human pressing keys.

## Runtime graph

```text
/root
├── GameManager                    autoload: mouse capture, player registry
└── Main (scenes/main.tscn)        entry point, spawns the pieces
    ├── World (test_arena.tscn)    environment, light, spawn marker
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
gameplay code changes. `resources/characters/leopard.tres` is the first one.

### `CharacterController` (CharacterBody3D)

Thin orchestrator, ~120 lines. Every frame it:

1. polls `CharacterInput` for the intent snapshot,
2. converts the 2D move axis into a **camera-relative** world direction,
3. hands that to `CharacterMotor`,
4. turns the visual toward the movement direction.

It also applies the definition to the components at `_ready()` and owns
spawn/respawn.

### Components

| Node | Responsibility | Reused later by |
| --- | --- | --- |
| `CharacterInput` | device input → `move_axis`, `run_held`, `jump_pressed`… | AI characters, replays, touch, co-op |
| `CharacterMotor` | gravity, acceleration/friction, jump, coyote time, jump buffering, air jumps | any walking actor |
| `HealthComponent` | max/current health, damage, heal, death signal | enemies, bosses, vehicles |
| `AbilityComponent` | set of unlocked ability ids + signals | progression, power-ups |

The controller polls `CharacterInput` explicitly instead of relying on node
processing order, so the intent is always fresh for the current physics tick.

### Movement feel

Arcade, not realistic: high gravity (26 m/s²), extra gravity while falling,
coyote time, jump buffering, and a short hop when the jump button is released
early. All of it is data on the definition, not constants in the motor.

## Input

Gameplay never reads a key or a pad button. `scripts/core/input_actions.gd`
holds the semantic action names; the actual bindings live in the Godot Input Map
and are generated (and therefore reviewable and reproducible) by
`tools/setup_input_map.gd`.

Keys are bound as **physical** keycodes so WASD stays in place on AZERTY and
QWERTZ keyboards. Every action already has a gamepad binding.

Adding touch controls later means adding events to the Input Map (or feeding
`CharacterInput` directly) — no gameplay code changes.

## Camera

`ThirdPersonCamera` is a `Node3D` (yaw) → `PitchPivot` (pitch) → `SpringArm3D`
(collision-aware distance) → `Camera3D`. It follows a target with a
frame-rate-independent lerp and runs at a late physics priority so it moves
after the character has moved.

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

Forward+ on desktop; Godot's per-platform overrides will select the mobile and
compatibility renderers for Android/iOS and Web. No shaders or post-processing
yet, so this choice is still cheap to revisit — see "Open questions".

## Engine gotchas found so far

* **Keep a `DirectionalLight3D` at the origin.** Giving the sun a non-zero
  `position` in Godot 4.7 breaks the directional shadow frustum and drops the
  entire scene into shadow (it then looks flat and blue, lit only by ambient).
  Only its rotation matters.
* **`--script` main loops don't see autoloads.** Scripts run with
  `godot --script` are compiled before autoloads register, so the test suite
  runs as a *scene* (`tools/tests/test_runner.tscn`) instead.
* **Simulated input needs one physics tick** to reach a character that polls
  `Input`, which the tests account for.

## Open questions (for the human developer)

* **Renderer.** Forward+ looks best on Windows but Web export needs the
  compatibility renderer and mobile prefers the mobile one. Right now nothing
  depends on Forward+ features, so switching is a one-line change. Worth
  deciding before writing shaders or lighting-heavy art.
* **Character scale.** The leopard is 1.6 m of collision capsule with a ~1.9 m
  visual. Fine for a prototype, but level metrics (step height, jump distance,
  door sizes) should be pinned down before the island is built for real.
