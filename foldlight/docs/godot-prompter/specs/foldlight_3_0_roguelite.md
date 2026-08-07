# FOLDLIGHT 3.0 — 纸海迷宫

## Product decision

FOLDLIGHT 3.0 makes the room-based roguelite the primary mode. The existing twelve-mission campaign remains complete and save-compatible under **经典战役 / Classic Voyage**. It is not deleted and does not share mutable run state with the new mode.

The new-player route is:

`35-second basics -> 8–12 minute prologue -> three-region roguelite`

A full successful run targets 30–45 minutes. Ordinary rooms sustain 60–100 seconds of combat, elite rooms 90–150 seconds, and bosses 3–5 minutes.

## Design pillars

1. **Move before Fold.** Dash, terrain, unreflectable threats and a Fold cooldown make positioning the foundation of survival.
2. **Fold with intent.** Base capture capacity falls from 16 to 6. A released Fold enters a visible internal cooldown, while upgrades can specialize capacity, radius, return damage or cadence.
3. **Readable combinations, not raw volume.** Encounters are assembled from role quotas and a threat budget. Every mechanic enemy has a single obvious job and a distinct silhouette.
4. **The room is a weapon.** Walls, refraction pillars, ink pools and current lanes affect routes, projectiles and build choices.
5. **Power lives inside the run.** At least 85% of combat power comes from weapons, items and Fold choices earned during the current run. Meta progression primarily unlocks options.
6. **Bosses are exams.** Every boss combines reflectable opportunity, unreflectable movement checks and an arena rule across explicit phases.
7. **Feedback has a budget.** High projectile counts must not multiply hit-stop, camera shake, controller vibration or full-volume sounds. Ordinary hits aggregate; only player damage, elite breaks, boss staggers and room clears receive dominant feedback.

## Controls and player contract

| Action | Keyboard | Controller | Contract |
|---|---|---|---|
| Move | WASD / arrows | Left stick | Continuous, normalized movement |
| Fold | Space / E | A | Hold to capture, release to return |
| Dash | Shift | B | Directional burst, buffered, short invulnerability |
| Active item | Q | X | One equipped item, clear cooldown |
| Pause | Esc | Start | Stops simulation |

Initial tuning targets:

- Hit radius: `13 px` (formerly 18); visual silhouette approximately 82% of the 2.1 size.
- Dash: `0.18 s`, `1,050 px/s`, `1.05 s` cooldown, up to `0.16 s` invulnerability.
- Fold capacity: `6`; Fold release cooldown: `1.0 s`; full charge target: `1.35 s`.
- Dash cancels an empty Fold and cannot be used while a loaded Fold is held. The rule is shown in the prologue.
- Automatic starter weapon fires at the nearest valid target. It is steady baseline damage, never the strongest build by itself.
- Size changes alter the primitive collision radius directly; physics bodies and collision shapes are never scaled.

## Projectile language

- **Reflectable:** warm ivory/gold petal with a cyan capture reaction.
- **Unreflectable:** black-red diamond or blade with a hollow core, red leading telegraph and a lower warning tone.
- **Terrain/arena warning:** violet contour or hatched floor region; never visually confused with damage projectiles.
- A Fold touching an unreflectable projectile produces a brief edge spark but cannot capture, delete or slow it.

Feedback throttles are part of combat correctness:

- ordinary return-light hits never stop global simulation;
- repeated hits inside a short window merge into one impact sound and one restrained flash;
- camera shake uses a capped impulse accumulator with decay;
- controller vibration has a duty-cycle ceiling;
- hit-stop is reserved for player damage, elite armor breaks, boss staggers and finishing blows, with a hard maximum duration;
- stress tests assert the feedback event budget under maximum reflected-projectile load.

## Run structure

Each run owns a seeded route with three regions:

1. **纸礁浅海** — open lanes, simple walls, turret introduction.
2. **倒悬墨城** — tighter channels, ink pools, buffers and control enemies.
3. **无名日庭** — mixed terrain, moving safe-space rules and full encounter compositions.

Each region contains 6–8 visited rooms selected from a branching graph:

- combat
- elite
- cache/reward
- shop
- signed event
- forge/remix
- rest
- boss

The player sees room category and risk before choosing a door, but not exact enemies or rewards.

## Encounter rules

Every enemy definition declares `role`, `threat_cost`, `minimum_region`, tags and quota group. The encounter director first chooses a room theme, then spends a threat budget subject to these constraints:

- At most one hard controller alive.
- At most two buffers alive, and no two identical buffers in an ordinary room.
- Turret slots are authored per room so they cannot block every route.
- At least 45% of ordinary-room budget is spent on readable fodder that supplies Fold ammunition.
- A mechanic enemy is introduced alone before appearing in combinations.
- Reinforcement waves reserve safe spawn lanes and telegraph for at least 0.75 seconds.

New core roles:

- **Paper Turret / 纸钉炮台:** stationary, rotating lane fire, exposed after a volley.
- **Bell Binder / 系潮铃:** visible tether buffs nearby attack cadence; fragile priority target.
- **Ink Warden / 墨界吏:** paints temporary movement-denial zones; only one hard controller at once.
- Existing Ram, Rewinder, Bell and other readable identities are reclassified into the same role budget.

## Terrain contract

- **Paper reef wall:** `StaticBody2D`; blocks actors and projectiles.
- **Refraction pillar:** blocks actors; return light touching it splits once with reduced damage.
- **Ink pool:** `Area2D`; slows actors and is temporarily erased by a charged return burst.
- **Current lane:** `Area2D`; visibly accelerates actors and projectiles along one direction.

Each room uses at most two active terrain mechanics. Navigation lanes, spawn points and exits are validated before the room becomes eligible for generation.

## In-run and meta progression

Run power is divided into four families:

- automatic weapon
- Fold/return
- movement/dash
- survival/active item

Size effects are explicit build modifiers:

- **燕折:** smaller silhouette and hit radius, slightly faster movement.
- **重纸潮:** larger silhouette and hit radius as a negative event/debuff; any associated power bonus is stated before acceptance.

The 3.0 release target is at least six automatic weapon definitions, six active items and thirty-six run upgrades with tagged prerequisites and exclusions. Meta upgrades unlock definitions, starting choices, archive information and cosmetic variants. Existing 2.1 flat upgrades continue to affect Classic Voyage; roguelite base stats are normalized so old saves do not trivialize a run.

## Boss contract

Every roguelite boss has:

- explicit phase thresholds and telegraphed transitions;
- reflectable ammunition opportunities;
- unreflectable dodge patterns with traversable lanes;
- an arena manipulation rule;
- a stagger or per-window return-damage limiter that prevents a single Fold from skipping the fight without hard invulnerability spam;
- at least one punish for stationary play and one recovery window.

Primary bosses:

1. **礁冠炮城:** deploys stationary turrets and rotating wall lanes.
2. **倒悬书记:** paints and rotates rectangular ink partitions, forcing route changes.
3. **折纸裁判:** frames the player inside a moving and shrinking safe rectangle while combining reflectable petals with unreflectable cutting lines.

## Scene tree

```text
Foldlight (Node2D)                         # composition root / mode router
├── ClassicRuntime (Node)                  # delegates to preserved 2.1 campaign logic
├── RogueRunController (Node)              # authoritative roguelite state machine
│   ├── RouteGenerator (Node)
│   ├── EncounterDirector (Node)
│   ├── RewardDirector (Node)
│   └── RunState (Node)
├── RogueWorld (Node2D)
│   ├── RoomRuntime (Node2D)
│   │   ├── Backdrop (Node2D)
│   │   ├── Terrain (Node2D)
│   │   ├── Actors (Node2D)
│   │   │   ├── Player (CharacterBody2D)
│   │   │   └── Enemies (Node2D)
│   │   ├── Projectiles (Node2D)
│   │   ├── Pickups (Node2D)
│   │   └── Doors (Node2D)
│   └── CameraRig (Camera2D)
└── HUD (CanvasLayer)
    ├── CombatHUD (Control)
    ├── RouteMap (Control)
    ├── RewardDraft (Control)
    └── ModalFlow (Control)
```

Reusable player composition:

```text
Player (CharacterBody2D)
├── CollisionShape2D
├── StatusEffects (Node)
├── DashComponent (Node)
├── FoldComponent (Node)
├── WeaponMount (Node)
├── ActiveItemSlot (Node)
└── Visuals (Node2D)
```

## Node responsibilities

| Node | Owns | Does not own |
|---|---|---|
| `RogueRunController` | seed, region, route position, room transition state | projectile or enemy frame logic |
| `RouteGenerator` | deterministic room graph | current player build |
| `EncounterDirector` | threat budget, role quotas, wave schedule | permanent unlocks |
| `RoomRuntime` | current room geometry, actors, doors and completion | route generation |
| `RunState` | mutable run inventory, stats, currency and selected upgrades | shared Resource definitions |
| `WeaponMount` | equipped automatic weapon runtimes | input routing or room state |
| `ActiveItemSlot` | equipped active definition and cooldown | meta ownership |
| `HUD` | presentation and UI focus | authoritative gameplay state |

Definitions are immutable custom Resources. Runtime counters and mutable values remain on Nodes or duplicated runtime objects.

## Signal map

| Signal | Source | Consumer | Payload |
|---|---|---|---|
| `dash_started` | Player/DashComponent | RoomRuntime, HUD, audio/VFX | direction, duration |
| `fold_released` | Player/FoldComponent | RoomRuntime, HUD | count, charge, radius |
| `weapon_fired` | WeaponMount | RoomRuntime | definition, origin, target |
| `active_used` | ActiveItemSlot | RoomRuntime, HUD | item id |
| `room_started` | RogueRunController | RoomRuntime, HUD | room definition, seed |
| `wave_requested` | EncounterDirector | RoomRuntime | enemy entries, spawn slots |
| `room_cleared` | RoomRuntime | RogueRunController | room id, performance |
| `door_chosen` | RoomRuntime | RogueRunController | destination node id |
| `reward_requested` | RewardDirector | HUD | three immutable definitions |
| `reward_chosen` | HUD | RunState | definition id |
| `run_finished` | RogueRunController | ProfileManager, HUD | result snapshot |

Signals travel upward from reusable children; parents call child APIs downward. Cross-mode persistence is routed only through `ProfileManager`.

## Data flow

```text
Title selects Maze Voyage
→ RogueRunController creates seeded RunState and route graph
→ selected RoomDefinition configures RoomRuntime
→ EncounterDirector reads room tags + region budget + EnemyDefinitions
→ RoomRuntime spawns telegraphed waves and terrain
→ player components emit combat actions; RoomRuntime resolves shared combat
→ room clear freezes combat and RewardDirector offers three legal definitions
→ RunState applies the choice and RogueRunController opens authored exits
→ boss clear advances region; final boss or death produces an immutable result
→ ProfileManager records unlock progress and run history, never current-run power
```

## Save and compatibility

- Profile schema advances from version 5 to version 6.
- Version 5 campaign, tutorial, challenge and meta data migrates unchanged.
- New fields store roguelite unlocks, bests, discoveries, difficulty and prologue completion.
- Current roguelite runs save only at cleared-room boundaries using seed, route node, build IDs and deterministic counters.
- Classic checkpoints retain their existing schema and behavior.

## Release acceptance

- New primary mode is completable from title to final result without debug flags.
- The prologue teaches all four controls within 8–12 minutes.
- Keyboard-only left hand and controller complete every flow.
- At least three regions, three full bosses, six weapons, six active items, thirty-six upgrades and sufficient room templates ship.
- No role quota, enemy/projectile budget or terrain rule can deadlock a room.
- Classic Voyage 2.1 regression suite remains green.
- Parser, deterministic route, room graph, combat, migration, fixed-step soak, performance, visual capture, controller navigation, export and exported-startup gates pass.
