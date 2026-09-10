# KartWorld

## Game Design Specification — v0.1

**Project name:** KartWorld
**Genre:** 3D Adventure / Exploration / Action
**Target platforms:** Windows, Web, Android, iOS
**Engine target:** Godot
**Development approach:** AI-first, primarily Claude Code
**Initial protagonist:** Leopard
**Visual style:** 3D cartoon

---

# 1. Vision

KartWorld is a colorful 3D adventure game combining:

* kart driving
* free exploration
* platforming
* combat
* puzzles
* collectibles
* power-ups
* character abilities
* level progression
* secrets
* boss encounters

The game takes inspiration from the general gameplay feel of:

* Mario Kart
* Crash Bandicoot
* Super Mario 3D World

These are references for gameplay style and accessibility only. KartWorld must have its own characters, environments, mechanics, visual identity, sounds and assets.

The game should feel:

* fun
* colorful
* accessible
* immediately playable
* suitable for children and families
* progressively deeper as the player unlocks abilities

---

# 2. Core Gameplay Loop

The main gameplay loop is:

1. Explore the main island.
2. Discover NPCs, secrets, collectibles and portals.
3. Enter a portal.
4. Complete an adventure level.
5. Collect stars and other rewards.
6. Unlock abilities or progression.
7. Return to the island.
8. Use new abilities to access previously unreachable areas.
9. Discover additional portals and levels.
10. Repeat.

The player should frequently have a reason to explore previously visited areas.

---

# 3. Main Character

## Initial Character

The first playable character is a cartoon leopard.

The leopard should be:

* expressive
* friendly
* agile
* recognizable
* suitable for a family-friendly game

The character is intentionally not hard-coded as "the leopard".

The game must use a generic character system so that additional playable characters can be added later.

Examples of future characters:

* tiger
* fox
* panda
* robot
* alien
* other original characters

Changing the character should primarily involve configuration and assets rather than rewriting gameplay systems.

---

# 4. Character Movement

The character uses third-person movement.

The camera follows from behind the character.

Basic movement:

* walk
* run
* jump
* double jump
* fall
* interact

The movement should feel arcade-like rather than realistic.

The player should be able to move comfortably using keyboard/controller and eventually touch controls.

---

# 5. Character Combat

The character supports both:

### Melee combat

Examples:

* claw attack
* combo
* charged attack
* special melee ability

### Ranged combat

Examples:

* energy projectile
* throwable object
* special ranged ability

The exact weapons and attacks can evolve during development.

Combat should be simple enough for a child to understand but expandable enough to support more advanced enemies and bosses.

---

# 6. Kart

The kart is a futuristic personal vehicle.

The player can summon the kart when appropriate.

The player can:

* enter the kart
* leave the kart
* drive
* accelerate
* brake
* steer
* jump
* use turbo
* use special abilities
* eventually use weapons

The kart should not simply be a cosmetic vehicle.

It is an important gameplay system.

---

# 7. Kart Abilities

Potential kart abilities include:

* turbo
* jump
* boosted jump
* flight
* aerial movement
* dash
* weapon systems
* special movement abilities

Abilities can be unlocked through progression.

The system must be modular so additional abilities can be added without rewriting the kart controller.

---

# 8. Kart Combat

The kart can fight.

Possible systems:

* projectile weapons
* missiles
* energy weapons
* area attacks
* defensive abilities
* special attacks

Weapons should eventually support different types of enemies and bosses.

The combat system should be designed so additional weapons can be added through configuration/components rather than rewriting the core kart controller.

---

# 9. Main Island

The game begins with a small explorable island.

The island is the central hub of the game.

Initial areas:

### Forest

A small but fully explorable cartoon forest.

Possible features:

* paths
* trees
* rocks
* collectibles
* hidden areas
* enemies
* environmental puzzles

### Mountain

A small mountain area.

It can contain:

* climbing routes
* caves
* elevated areas
* hidden paths
* future ability-gated areas

### Base / House

The player has a home/base.

The base can eventually contain:

* character customization
* kart customization
* progression information
* collectibles
* trophies
* unlocked abilities
* level selection
* NPCs

The base should be designed so it can grow throughout development.

### NPCs

The island contains several NPCs.

NPCs may:

* give information
* provide quests
* unlock activities
* explain mechanics
* reward the player
* contribute to the story

---

# 10. Portals

Portals are the main way to access adventure levels.

The island contains multiple portals.

Target:

**30–40 levels**

The initial development should NOT create all 30–40 levels.

Instead, the game should first implement the portal/level system with one working level.

Additional portals and levels can then be generated progressively.

Portals may eventually represent different worlds or themes.

Examples:

* Forest
* Desert
* Volcano
* Ice
* Ocean
* Space
* Ancient ruins
* Factory
* Sky world
* Underground world

These are examples, not final requirements.

---

# 11. Level Structure

KartWorld uses a mixture of level types.

Some levels can be:

* relatively linear
* platform-focused
* driving-focused
* combat-focused

Other levels can be:

* large
* exploratory
* semi-open
* full of secrets
* structured around multiple objectives

This mixture prevents the game from becoming repetitive.

---

# 12. Level Objectives

Levels do not all have the same objective.

Possible objectives:

* reach the destination
* find an object
* collect a number of items
* defeat enemies
* defeat a boss
* rescue an NPC
* activate mechanisms
* solve a puzzle
* reach a hidden area
* complete a driving challenge
* survive an encounter
* combine multiple objectives

Each level should communicate its main objective clearly to the player.

---

# 13. Stars

Stars are the primary collectible/reward system.

Stars can be obtained by:

* completing objectives
* exploring
* finding secrets
* completing challenges
* defeating bosses
* discovering hidden locations

Stars contribute to progression and completion.

The exact number of stars per level can vary.

---

# 14. Power-Ups

KartWorld contains different power-ups.

Examples:

* speed
* turbo
* fire
* stronger attack
* ranged attack
* defense
* flight
* special abilities

Power-ups are not necessarily temporary.

Once acquired, an ability remains active until:

* the player loses it
* the player changes it
* another power-up replaces it

The system should support multiple power-ups without hard-coding individual abilities into the player controller.

---

# 15. Ability Progression

The player progressively unlocks abilities.

Example progression:

### Beginning

* basic movement
* jump
* double jump
* basic melee attack
* basic kart
* basic turbo

### Early progression

* ranged attack
* improved turbo
* enhanced jump
* additional kart abilities

### Mid progression

* flight
* stronger combat abilities
* new kart weapons
* access to previously inaccessible areas

### Later progression

* advanced movement
* advanced combat
* combined abilities
* special abilities

The exact unlock order will be determined during development and playtesting.

---

# 16. Exploration

Exploration is a major part of KartWorld.

The world should contain:

* hidden paths
* secret areas
* collectibles
* optional challenges
* environmental interactions
* areas accessible only after unlocking abilities

New abilities should sometimes allow the player to revisit old areas and discover something new.

---

# 17. Health and Damage

The player has a health system.

Damage can come from:

* enemies
* environmental hazards
* falling
* enemy projectiles
* traps
* bosses

When health reaches zero:

**Player dies.**

The player respawns at the most recent checkpoint.

---

# 18. Checkpoints

Levels contain checkpoints.

When activated, a checkpoint becomes the player's latest respawn location.

After death:

1. Player respawns at the latest checkpoint.
2. Relevant temporary level state is restored/reset.
3. Player can continue playing.

The checkpoint system should be reusable across all levels.

---

# 19. Bosses

Bosses exist but are not present in every level.

Some levels may contain:

* mini-bosses
* bosses
* special encounters

Boss fights should use existing gameplay systems rather than becoming completely separate gameplay.

Bosses can use:

* melee attacks
* ranged attacks
* environmental attacks
* movement challenges
* kart combat
* multiple phases

---

# 20. Multiplayer

The final vision supports three modes:

### Single player

Primary development mode.

### Local co-op

Multiple players sharing the same local game session.

### Online multiplayer

Players can connect through the internet.

Multiplayer does NOT need to be implemented in the first prototype.

However, the architecture should avoid decisions that make multiplayer impossible later.

Single-player gameplay remains the first priority.

---

# 21. Controls

The game should eventually support:

### PC

* keyboard
* mouse where appropriate
* game controller

### Web

* keyboard
* controller where supported

### Android

* touchscreen controls
* optional controller

### iOS

* touchscreen controls
* optional controller where supported

Input must use an abstraction layer so gameplay code does not depend directly on a specific device.

---

# 22. Visual Direction

The visual style is:

**3D cartoon**

Characteristics:

* colorful
* readable shapes
* stylized environments
* expressive characters
* exaggerated animations
* friendly appearance
* clear gameplay objects
* strong visual distinction between interactive and decorative elements

The game should prioritize a coherent art direction over photorealism.

AI-generated assets can be used during development.

All assets should follow a consistent visual style.

---

# 23. AI-First Development

KartWorld is designed to be developed primarily using AI.

Claude Code is the main programming assistant.

AI may assist with:

* GDScript
* Godot scenes
* game systems
* level generation
* shaders
* UI
* debugging
* documentation
* testing
* game design iteration
* placeholder assets
* textures
* concept art
* sound effects
* music
* 3D assets

The development process should favor automation.

Whenever a repetitive task can be automated, it should be considered for automation.

---

# 24. Development Philosophy

The game must be built incrementally.

Never attempt to build the complete game in one step.

Development sequence:

```text
Design
↓
Implement small feature
↓
Run game
↓
Test feature
↓
Fix problems
↓
Commit
↓
Next feature
```

Every major system should be independently testable.

---

# 25. First Playable Prototype

The first playable version should contain only:

### World

* small island
* small forest
* house/base
* basic terrain
* one portal

### Character

* leopard
* third-person camera
* movement
* jump
* double jump
* basic attack

### Kart

* futuristic kart
* summon
* enter
* exit
* drive
* turbo
* jump

### Level

* one playable level
* portal entry
* exploration
* at least one enemy
* basic combat
* one collectible/star
* one checkpoint
* death
* respawn

### UI

* health
* basic objective
* stars
* simple interaction prompts

This is the first definition of "fun and playable".

---

# 26. Future Expansion

After the first prototype works, the game can progressively add:

1. More enemies
2. More power-ups
3. More kart abilities
4. More character abilities
5. More NPCs
6. More island areas
7. More portals
8. More level types
9. Bosses
10. Character customization
11. Kart customization
12. Save system
13. Progression system
14. Local multiplayer
15. Online multiplayer
16. Android optimization
17. iOS support
18. 30–40 complete levels

---

# 27. Player Customization

The initial game uses the leopard.

The architecture must support future customization.

Possible future customization:

* character selection
* character appearance
* colors
* accessories
* outfits
* animations
* kart appearance
* kart upgrades

Customization should be separated from core gameplay logic.

---

# 28. Design Rule: Fun First

KartWorld should prioritize:

1. Fun
2. Responsiveness
3. Clear gameplay
4. Exploration
5. Variety
6. Visual appeal
7. Technical scalability

Complexity should only be added when it improves the player experience.

---

# 29. Design Rule: Child-Friendly but Not Childish

The game should be accessible to children but enjoyable for adults.

Avoid unnecessary complexity in the controls.

Difficulty should come from:

* exploration
* timing
* puzzles
* combat
* discovery
* increasingly interesting mechanics

rather than confusing interfaces.

---

# 30. Project Name

The official working project name is:

# KARTWORLD

The name can be changed later without affecting the architecture.

---

# 31. Current Development Priority

The immediate objective is NOT:

"Build KartWorld."

The immediate objective is:

> Build a small, polished playable slice that proves the core gameplay is fun.

The first milestone is:

**Leopard + Island + Kart + Portal + Level + Combat + Star + Checkpoint.**

Everything else comes later.
