# FOLDLIGHT 3.1 — 爽感重铸

## Product decision

3.1 adopts **overlapping readable reinforcements** instead of either sparse tactical rooms or an undifferentiated enemy flood. Ordinary enemies are ammunition and combo fuel; mechanic enemies each present one priority or movement rule; Fold converts survived pressure into a visible homing-return payoff.

Rejected alternatives:

1. Raising health and damage alone lengthens fights without increasing expression.
2. Spawning every enemy at once produces noise and undermines one-hand readability.
3. Keeping kill-all wave gates preserves the dead air reported by players.

## Combat contract

- Ordinary rooms contain roughly 18–24 enemies; elite and late rooms reach 24–30.
- A wave presents 6–9 simultaneous enemies. When only 2–3 remain, the next wave telegraphs while combat continues.
- At least half of the bodies are low-cost reflectable-ammunition enemies.
- A normal composition includes one or two different mechanic jobs, never duplicate hard controllers.
- Every captured projectile releases as an independently targeted homing Return Missile. Missiles retarget after a kill and leave a readable cyan-gold trail.
- Base dash cooldown is long enough that two consecutive mistakes cannot be erased by repeated dashing. Run upgrades may recover the faster cadence.
- Every active item must immediately create at least one of: a kill swing, projectile conversion, strong control, meaningful recovery, or a safe reposition.

## New mechanic enemies

| Enemy | One rule | Response |
|---|---|---|
| 棱镜折卫 | A frontal prism greatly reduces automatic-weapon damage | A Return Missile breaks the prism and opens a punish window |
| 孵潮灯 | A stationary lamp periodically adds two fragile drifters | Kill the clearly pulsing lamp before the room fills |
| 裁线使 | A long cross telegraph resolves into four unreflectable blades | Leave the two marked axes; attack during recovery |

## Terrain contract

The room palette expands from four to six mechanical pieces:

- Paper wall: neutral cover.
- Refraction pillar: neutral/positive Return Missile routing object.
- Ink pool: negative slow.
- Current lane: mixed directional force.
- Sun patch: positive movement, Fold focus regeneration and friendly-projectile acceleration.
- Thorn paper: negative contact field that damages enemies as well as the player, turning risk into a lure tool.

Each region receives denser authored layouts with decorative facets, rim lighting and animated markings. Layout validation still reserves broad traversable lanes and safe spawn slots.

## Scene tree

```text
RogueWorld (Node2D)
├── RoomRuntime (Node2D)
│   ├── Backdrop (Node2D)
│   ├── Terrain (Node2D)
│   │   └── TerrainPiece (Node2D + generated StaticBody2D/Area2D)
│   ├── Actors/Enemies (Node2D)
│   │   ├── PrismBulwark (CharacterBody2D)
│   │   ├── BroodLantern (StaticBody2D)
│   │   └── ShearScribe (CharacterBody2D)
│   ├── Projectiles (Node2D)
│   │   └── RogueProjectile (Node2D; optional homing target)
│   └── EncounterRuntime (Node)
└── CombatRuntime (Node2D)
```

## Responsibilities

| Node | Owns | Communicates through |
|---|---|---|
| EncounterDirector | deterministic total composition, role quotas and wave assignments | immutable plan dictionary |
| EncounterRuntime | overlap thresholds, telegraph timing and outstanding room count | wave/spawn/clear signals |
| Mechanic enemy scene | one mechanic state machine and its telegraph drawing | attack/minion/defeat signals |
| CombatRuntime | target assignment, damage routing, active effects and terrain interactions | calls down to actors/projectiles; emits combat result signals |
| RogueProjectile | velocity, homing steering and trail rendering | public configure/retarget API |
| TerrainPiece | collision/effect geometry and local presentation | terrain enter/exit signals plus queried kind |

## Signal map

| Signal | Source | Consumer | Payload |
|---|---|---|---|
| reinforcement_requested | EncounterRuntime | RoomRuntime/CombatRuntime | next wave entries via existing telegraph/spawn signals |
| minions_requested | BroodLantern | CombatRuntime | enemy id, positions, cap |
| volley_requested | ShearScribe | CombatRuntime | unreflectable cross snapshot |
| prism_broken | PrismBulwark | CombatRuntime feedback | duration and position |
| active_item_resolved | CombatRuntime | session feedback/UI | item id and measurable result |

## Data flow

```text
Room starts
→ Director spends a larger budget with body-density targets
→ EncounterRuntime telegraphs wave one
→ remaining enemy threshold starts the next telegraph before silence
→ ordinary shots become Fold captures
→ release assigns captured shots across living enemies
→ Return Missiles home, retarget and break mechanic nodes
→ kills open space while another readable reinforcement arrives
→ strong active item creates a second intentional swing
→ all authored and summoned actors are resolved before room clear
```

## Acceptance

- Region-one plans produce at least 16 total enemies and at least 6 in the opening wave with valid slots.
- New roles appear through deterministic quotas and each has an isolated behavior test.
- Return light curves toward a live target, retargets after invalidation and remains bounded by projectile caps.
- Base dash cooldown is at least 1.65 seconds; upgrades still measurably reduce it.
- All six active items pass effect-specific assertions and have stronger presentation text.
- Every normal region layout contains at least seven terrain pieces and both positive and negative mechanics appear across the run.
- Parser, focused combat tests, complete roguelite suite, visual captures and Windows export pass.
