# FOLDLIGHT 2.1.0 — Endless Challenge Release Audit

Audited: 2026-07-27

## Release artifact

- Windows x86_64: `build/windows/FOLDLIGHT.exe`
- Size: 105,941,560 bytes (101.03 MiB)
- SHA-256: `77B56AC05A3AF2512FDD4EDA3C5C6A0CC54215FC5C6AD1B504AFA909DEF4E142`
- File/Product version: `2.1.0.0`
- Product metadata: `FOLDLIGHT · 折光` / `一只手或手柄即可游玩的弹幕折返战役与无尽挑战`
- Exported-build hidden headless startup exit: `0`

## Campaign and gameplay gates

- Endless challenge starts in a compact arena that expands continuously to the full authored map over ten minutes.
- Difficulty rises every 45 seconds; one of six positive or six negative signed events occurs on a 24–36 second seeded cadence after the first event at 20 seconds. Recent events cannot immediately repeat and negative streaks are capped at two.
- Every 75 seconds pauses on three unique roguelite Fold choices; selected doctrines stack for the current run. Challenge records, rewards and restarts are isolated from campaign checkpoints.
- A replayable 35-second onboarding teaches movement, capture, release and free practice with an enforced 30-second completion floor.
- The purchasable `Crease Rebuke / 折界棘` passive damages and interrupts charging Rams and rewinding Echo Moths when their swept path crosses the released Fold boundary; ordinary enemies remain immune.
- Three chapters, twelve missions, 72 authored tides and twelve distinct finale identities.
- Exact configured active route: 7,080 seconds (118 minutes), split into 7–14 minute missions.
- Every mission contains six fixed technique gates, a three-phase finale, opening/ending story records and a safe tide-boundary checkpoint.
- Eight objective families: survive, return quota, beacon charge, cleanse, escort, Ram relay, courier pursuit and mastery.
- Twelve regular enemy behaviors plus Herald and bosses. Late-game additions are Carver, Tide Bell, Name Thief and Echo Moth.
- Six elite affixes, at most two live elites, and an authoritative 18-enemy global budget. A forced authored threat at capacity replaces the oldest ordinary enemy.
- Six cross-doctrine synergies: Sea Mirror, Ocean Memory, Needle Light, Sun Chain, Walking Lantern and Mercy Fire.
- Profile version 5 with verified temporary write, primary/backup recovery, future-version read-only protection, stable mission IDs, challenge records, tutorial completion, idempotent rewards and v3/v4 migration.
- Explicit Wide Fold assistance becomes available after two failures; it adds survivability and slows hostile shots while capping rank at B.
- Full keyboard and controller navigation through title, route map, briefings, gameplay, seals, pause, settings, Foldlight Court, results, checkpoints and replay.

## Verification

- Godot 4.6.3 editor import and parser scan: PASS.
- All seven integration entry points: PASS.
- Endless challenge, twelve signed events, expanding arena, three-choice drafts, short tutorial, persistent passive and v4→v5 migration suite: PASS.
- Complete-run campaign smoke after 2.1 integration: PASS.
- Complete-run state graph: PASS.
- Product/system integration suite: PASS.
- Campaign catalog, unlock graph, checkpoint and migration suite: PASS.
- Accelerated 12-mission systems soak: PASS.
  - 7,080 authored seconds accounted for.
  - All 72 tides and 36 boss-phase checks executed.
- Full-duration production-rate fixed-step route: PASS.
  - 424,800 physics frames at 60 Hz.
  - 7,080 virtual seconds; all twelve mission records and final ending reached.
  - Wall time: 138.79 seconds.
  - Peak live load: 18 enemies, 300 hostile petals, 70 effect particles.
- Automated maximum-load performance budget: PASS.
  - Average frame: 6.90 ms.
  - P95 frame: 6.95 ms.
  - Static memory: 54.6 MB.
  - Load: 18 enemies, 300 hostile petals, 420 persistent particles.
- Visual review: title entry points, expanding challenge field, signed event card, three-choice Fold draft, contextual tutorial, five-card Foldlight Court and dedicated challenge result at the fixed 1920×1080 design canvas.
- Aspect safety: `viewport` stretch mode with `keep` aspect ratio; 4:3 and ultrawide displays letterbox rather than crop combat or HUD.
- Godot code review: no unresolved critical issue; autoload lookups are cached, no runtime resource loads occur in frame loops, hostile/effect arrays are bounded, and event spawns cannot bypass the enemy budget.
- Export filter excludes captures, docs, tests and source icon art from the shipped executable.

## Publisher-owned launch steps

Code signing, production storefront credentials, capsule art, age rating and upload remain publisher-owned external steps and are intentionally not embedded in this project.
