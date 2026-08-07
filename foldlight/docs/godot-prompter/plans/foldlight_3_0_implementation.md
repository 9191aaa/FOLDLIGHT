# FOLDLIGHT 3.0 Implementation Plan

Every task is completed with parser and relevant focused tests before the next dependency layer begins. The existing Windows 2.1 executable remains usable until the 3.0 release artifact replaces it.

## 1. Baseline and boundaries

- [x] Record the current seven-test 2.1 baseline: all pass; fixed-step route 424,800 frames / 7,080 seconds / 122.60 seconds wall time.
- [x] Add the 3.0 specification and define ownership boundaries around the 4,650-line legacy controller.
- [x] Add command-line hooks for deterministic prologue, room, boss and result captures.

Skills: `godot-prompter:godot-testing`, `godot-prompter:scene-organization`, `godot-prompter:godot-code-review`

## 2. Data contracts and profile v6

- [x] Create typed immutable Resources for region, room, terrain, encounter, enemy, weapon, active item, upgrade and boss definitions.
- [x] Create content catalogs with uniqueness and reference validation.
- [x] Add `RunState` and deterministic route snapshot serialization.
- [x] Migrate profile v5 to v6 while retaining campaign/checkpoint/challenge/meta fields byte-for-byte where possible.

Skills: `godot-prompter:resource-pattern`, `godot-prompter:save-load`, `godot-prompter:godot-testing`

## 3. Player combat loop

- [x] Reduce the default visual and collision radius without scaling physics shapes.
- [x] Add buffered directional dash with cooldown, invulnerability and controller feedback.
- [x] Add Fold cooldown, base capacity six, clear readiness feedback and compatibility configuration for Classic Voyage.
- [x] Add reflectable/unreflectable projectile contract.
- [x] Add composable automatic weapon mount and single active-item slot.
- [x] Add explicit size modifier API and tiny/large status effects.
- [x] Add a feedback budget that aggregates ordinary impacts and caps shake, vibration, sounds and hit-stop under reflection-heavy load.

Skills: `godot-prompter:player-controller`, `godot-prompter:input-handling`, `godot-prompter:physics-system`, `godot-prompter:component-system`, `godot-prompter:state-machine`, `godot-prompter:audio-system`

## 4. Room world and camera

- [x] Add `RogueWorld`, `RoomRuntime`, containers and collision layers.
- [x] Add a smooth bounded Camera2D for rooms larger than the design viewport.
- [x] Implement walls, refraction pillars, ink pools and current lanes with primitive physics shapes.
- [x] Implement safe room load/unload, door locks, spawn telegraphs and room completion.

Skills: `godot-prompter:2d-essentials`, `godot-prompter:camera-system`, `godot-prompter:physics-system`, `godot-prompter:scene-organization`, `godot-prompter:godot-optimization`

## 5. Route and encounter generation

- [x] Generate a deterministic three-region branching route with required room categories and reachable bosses.
- [x] Implement threat-budget wave composition, role quotas and safe-spawn validation.
- [x] Add room themes and 60–150 second pacing profiles.
- [x] Persist cleared-room boundaries and restore an interrupted run deterministically.

Skills: `godot-prompter:procedural-generation`, `godot-prompter:ai-navigation`, `godot-prompter:resource-pattern`, `godot-prompter:save-load`, `godot-prompter:godot-testing`

## 6. Mechanic enemies

- [x] Implement Paper Turret stationary lane fire and exposure cycle.
- [x] Implement Bell Binder visible buff tether and protected-priority behavior.
- [x] Implement Ink Warden temporary denial zones.
- [x] Reclassify existing enemies by role/cost and enforce room quotas.
- [x] Give every mechanic an isolated introduction encounter and concise archive/tutorial card.

Skills: `godot-prompter:ai-navigation`, `godot-prompter:state-machine`, `godot-prompter:component-system`, `godot-prompter:particles-vfx`, `godot-prompter:audio-system`

## 7. Run build system

- [x] Ship at least six automatic weapons with different targeting and return-light interactions.
- [x] Ship at least six active items with explicit cooldowns and one-slot replacement flow.
- [x] Ship at least thirty-six tagged upgrades across weapon, Fold, dash and survival families.
- [x] Add prerequisites, exclusions, rarity, duplicate stacking and deterministic three-choice rewards.
- [x] Add tiny positive and large negative size modifiers with honest preview text.

Skills: `godot-prompter:resource-pattern`, `godot-prompter:component-system`, `godot-prompter:inventory-system`, `godot-prompter:godot-ui`, `godot-prompter:godot-testing`

## 8. Boss rebuild

- [x] Add a reusable phase controller, stagger/return-damage window and arena-rule interface.
- [x] Implement Reef-Crown Battery with turret deployment and rotating lanes.
- [x] Implement Inverted Archivist with ink partitions and route control.
- [x] Implement Origami Judge with moving/shrinking safe rectangles and unreflectable cuts.
- [x] Tune 3–5 minute fights, recovery windows, stationary-play punish and readable multi-projectile load.

Skills: `godot-prompter:state-machine`, `godot-prompter:physics-system`, `godot-prompter:shader-basics`, `godot-prompter:particles-vfx`, `godot-prompter:camera-system`, `godot-prompter:audio-system`

## 9. Prologue, UI and classic compatibility

- [x] Replace the primary title action with Maze Voyage and move the preserved campaign to Classic Voyage.
- [x] Build the 8–12 minute five-step real-room prologue and retain the 35-second Classic basics tutorial.
- [x] Add route map, room preview, combat resources, dash/Fold/active cooldowns, reward drafts and run result UI.
- [x] Normalize roguelite base power while keeping existing meta effects in Classic Voyage.
- [x] Add settings/accessibility help for unreflectable colors, screen shake and input prompts.

Skills: `godot-prompter:godot-ui`, `godot-prompter:hud-system`, `godot-prompter:responsive-ui`, `godot-prompter:localization`, `godot-prompter:save-load`

## 10. Content, balance and release

- [x] Author enough room templates and encounter themes for all three regions without immediate repetition.
- [x] Run deterministic simulations for room duration, build legality, threat quotas, boss duration and full route completion.
- [x] Stress maximum return-light density and assert that feedback throttles preserve continuous control and readable audio/visual output.
- [x] Run controller-only navigation and a one-hand keyboard playthrough.
- [x] Capture and inspect title, prologue, every region, every terrain, reward, shop, all bosses and results at 1920×1080 plus aspect-safety checks.
- [x] Run the preserved 2.1 suite, new 3.0 integration suite, long soak and performance budgets.
- [x] Version as 3.0.0, update documentation/audit, export Windows release and verify the exported executable starts and exits cleanly.

Skills: `godot-prompter:godot-testing`, `godot-prompter:godot-optimization`, `godot-prompter:godot-code-review`, `godot-prompter:export-pipeline`, `godot-prompter:assets-pipeline`
