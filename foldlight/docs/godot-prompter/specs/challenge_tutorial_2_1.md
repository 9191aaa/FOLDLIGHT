# FOLDLIGHT 2.1 — Challenge, Tutorial, and Fold-Boundary Passive

## Scope

This increment adds three finished systems without changing the authored two-hour campaign:

1. A separate endless Challenge mode.
2. A short, independent onboarding tutorial.
3. A purchasable archive passive, `crease_rebuke` (折界棘).

Campaign checkpoints, mission pacing, authored chapter rules, and campaign victory remain isolated from special runs.

## Challenge mode

- Launches from the title screen and owns its own result flow and profile records.
- Starts in a compact arena and eases to the full arena over ten minutes.
- Difficulty tiers advance every 45 seconds. Spawn pressure, enemy roster, elite chance, speed, and health scale indefinitely.
- A signed world event begins every 24–36 seconds. Positive and negative events draw from separate pools; the last two events cannot repeat and negative streaks are capped at two.
- A roguelite three-choice draft appears every 75 seconds. Choices reuse the campaign doctrine system and stack for the current run only.
- The run ends on player defeat. Results record duration, score, tier, event count, bests, and Glimmer reward.

Event modifiers are owned by `FoldlightChallengeDirector`; `game.gd` translates event snapshots into world effects. Arena bounds are a runtime rectangle shared by player clamping, enemy spawning, projectile cleanup, and presentation.

## Tutorial

The tutorial is an independent finite-state sequence:

`intro -> move -> fold/capture -> release -> free practice -> complete`

- Expected completion is 35–45 seconds; completion cannot occur before 32 seconds.
- It uses safe training spawns and player invulnerability.
- Prompts are contextual and rendered in the normal HUD language.
- Completion is saved once and returns to the title screen. The tutorial can be replayed.

## Fold-boundary passive

`crease_rebuke` is a one-level archive purchase. When the player releases Fold, a Ram in `CHARGE` or Rewinder in `REWIND` that crosses the charged circle boundary takes damage and is forced into recovery. Other enemies and non-charging states are unaffected.

The collision test uses the enemy's current-to-predicted motion segment against the release circle, so fast enemies cannot tunnel through the boundary between fixed-physics frames.

## Persistence and validation

- Profile schema version: 5.
- New fields: `tutorial_complete`, challenge totals/bests, and `meta_upgrades.crease_rebuke`.
- Migration from version 4 supplies safe defaults.
- Automated coverage must include director timing/bounds, tutorial progression, profile migration, draft flow, and passive collision/state filtering.
- Final validation includes headless tests, a visual review at multiple states, release export, and startup of the exported build.
