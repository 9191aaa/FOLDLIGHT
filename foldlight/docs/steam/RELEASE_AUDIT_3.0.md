# FOLDLIGHT 3.0.0 — Three-Region Maze Release Audit

Audited: 2026-07-27

## Release artifacts

- Windows x86-64 executable: `build/FOLDLIGHT_3.0_Windows/FOLDLIGHT.exe`
- Executable size: 111,085,792 bytes (105.94 MiB)
- Executable SHA-256: `BB5998195883F3711D897B951685A0D4F7EA98CA3F484F250FA2D7ACD9C495FB`
- Portable archive: `build/FOLDLIGHT_3.0_Windows.zip`
- Archive size: 40,464,124 bytes (38.59 MiB)
- Archive SHA-256: `7B64863F82C016EB135EB00818CAABB96CEDC9C8F5637C0E3AD11BD450CBAC27`
- File/Product version: `3.0.0.0`
- Product metadata: `FOLDLIGHT · 折光`
- Exported executable hidden headless startup exit: `0`

The build is not code-signed. Windows SmartScreen may warn on an unsigned download; signing remains a publisher-owned distribution step.

## 3.0 product gates

- The first-run primary action enters a five-step interactive prologue that teaches movement, dash, Fold capture/release, active item use and one real mixed encounter.
- The main mode is a deterministic three-region branching voyage with 22 visited large rooms on a complete route and a 30–45 minute target duration.
- Every room uses tactical terrain: projectile-blocking paper walls, reflectable-shot bending pillars, slowing ink pools or directional current lanes.
- Encounters use threat budgets and role quotas. Stationary Paper Turrets, ally-buffing Bell Binders and space-denying Ink Wardens have isolated first-introduction cards.
- Six automatic weapons, six one-slot active items and thirty-six runtime-verified upgrades cover weapon, Fold, dash, size and survival families.
- Fold starts at six captures with a one-second internal cooldown. The player has a thirteen-pixel honest hit radius and a buffered, invulnerable directional dash.
- All three bosses have rising health, three phases, mixed reflectable/unreflectable projectile patterns, warning snapshots, capped return-light damage and unique arena restrictions.
- Reef-Crown uses damaging rotating lanes and bounded turret summons; Inverted Archivist uses ink partitions; Origami Judge shrinks and moves the legal frame.
- Room, reward and route-choice checkpoints restore exactly without replaying a cleared encounter. Profile v5 migrates to v6 while preserving Classic Voyage data.
- The original three-chapter, twelve-mission campaign remains accessible as Classic Voyage and retains its established timing, progression and controls.

## Input and accessibility

- One-hand keyboard: WASD, Space/E Fold, Shift dash, Q active item, Esc pause.
- Controller: left stick, A Fold/confirm, B dash, X active item, Start pause.
- Input contract tests dispatch the actions into the live player and pause controller, not only the Input Map.
- All new interactive controls have a minimum 52-pixel target and explicit keyboard/controller focus.
- High-contrast unreflectable bullets, master/music/SFX volume, screen shake, controller vibration and fullscreen settings are available from title and pause.
- `viewport` + `keep` preserves the exact Classic 16:9 composition and letterboxes other aspects rather than cropping combat or HUD.

## Verification

- Godot 4.6.3 parser/editor scan: PASS.
- Final non-performance integration matrix: 21 / 21 scripts PASS.
- Full 3.0 route simulation: 22 rooms, three regions, three bosses and a substantial legal in-run build: PASS.
- Classic fixed-step route: 424,800 physics frames / 7,080 authored seconds / twelve missions: PASS.
- Accelerated two-hour Classic campaign and system soak: PASS.
- Roguelite rendered stress: 19 enemies plus phase-three boss load and the 260-projectile ceiling: PASS.
  - Average frame: 15.43 ms; P95: 23.40 ms; 915 draw calls; 74.3 MiB static memory.
- Classic rendered stress: 18 enemies, 300 hostile petals and 420 persistent particles: PASS.
  - Average frame: 11.45 ms; P95: 19.14 ms; 370 draw calls; 73.9 MiB static memory.
- Visual capture review at the 1920×1080 design canvas: title, prologue, all three terrain regions, reward, shop, forge, route, pause, settings, all three bosses and result: PASS.
- Export filter excludes artifacts, captures, docs, tests, tools and source icon art from the shipped executable.
- Release export and exported-executable startup verification: PASS.

## Static code review

No unresolved critical issue was found against the Godot 4.3+ review checklist. New gameplay scenes have focused responsibilities and shallow composition; signals are connected during setup; scene resources are preloaded; dynamically created actors use `queue_free()`; no resource `load()` or parent-chain lookup occurs in a per-frame path; hot node references are cached or limited to event-driven spawn/cleanup paths; projectile, enemy and feedback populations are bounded.

## Publisher-owned external steps

Code signing, storefront credentials, capsule art, age rating and store upload are intentionally not embedded in this project.
