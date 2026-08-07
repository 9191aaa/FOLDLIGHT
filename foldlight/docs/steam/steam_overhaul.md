# FOLDLIGHT — Steam-Ready Overhaul

## Reference audit: LUMENLOOM

The referenced build succeeds through feel and pacing rather than content volume:

- A constrained one-hand input contract: steer, hold, release.
- 180 ms action buffering so presses made during cooldown are remembered.
- 50–75 ms impact pause, screen trauma and controller vibration on the core action.
- Mid-run choices use the same left/right/action vocabulary as gameplay.
- The arena is made safe for 0.85 seconds after a choice, so a menu never creates a cheap hit.
- A three-minute authored arc ends in a boss, not an endless difficulty ramp.

FOLDLIGHT has an immediately readable verb — catch hostile petals and return them. The finished structure gives that verb new opponents and authored counterplay in every tide instead of depending on randomized build churn.

## Approaches considered

1. **Random survivor structure** — rejected because upgrade randomness would become the content and weaken the authored paper-sea identity.
2. **Fully scripted one-build campaign** — clear, but gives the player no long-term expression inside a run.
3. **Authored Chapter I voyage (chosen)** — six fixed tides, story and counterplay lessons, with one of three deterministic technique paths chosen after the first Herald and permanent growth between attempts.

## Target run

```text
Title / Foldlight Court / Settings
  ↓
Tide I: tutorial + Lantern Rain ritual
  ↓ Herald
Choose one of 3 fixed technique paths
  ↓
Tide II: fan formations + Crosswind ritual
  ↓ Herald
Next fixed path technique
  ↓
Tide III: bloom turrets + Echo Garden ritual
  ↓ Herald
Next fixed path technique
  ↓
Tide IV: leeches, elites + Eye of the Storm ritual
  ↓ Herald
Next fixed path technique
  ↓
Tide V: locked-line Rams + Red Wheel ritual
  ↓ Herald
Next fixed path technique
  ↓
Tide VI: four-second Rewinders + Reversal ritual
  ↓ Herald
Final fixed path technique
  ↓
Ink Moon: three phases, add waves, phase cleanses
  ↓
Story epilogue, rank, Glimmer reward, Foldlight Court or replay
```

Expected first clear: 10–14 minutes. The game remains playable with movement plus one action.

## Systems and ownership

| Owner | State | Responsibility |
|---|---|---|
| `FoldlightGame` | run state, encounter clock, enemies, shots, path modifiers | authored pacing and combat simulation |
| `FoldlightPlayer` | movement, focus, capacity, fold geometry, health | responsive controller and player-local technique modifiers |
| `StatusEffects` | negative status timers, stat multipliers, cleanse rules | one authoritative home for debuffs and counters |
| `FoldlightHUD` | display snapshots, technique seals, status counters, settings/archive overlays | all screen-space presentation |
| `ProfileManager` autoload | records, achievements, settings, save migration | user data in `user://` only |
| `FoldDoctrine` resources | read-only doctrine names, descriptions, family and limits | designer-editable build data |
| `AudioDirector` autoload | adaptive score and pooled feedback | audio presentation |

## Run state machine

The run remains enum-based because states are mutually exclusive and transition logic is centralized:

```text
TITLE / ARCHIVE → BRIEFING → PLAYING ↔ PAUSED
                               ↓
                            UPGRADE
                               ↓
               BRIEFING → GAME_OVER / VICTORY
```

Explicit transition methods own player enable/disable, music intensity, safety clears and UI state.

## Doctrine families

- **折域 / Crease** — radius, capacity, focus economy, stronger slow.
- **返光 / Return** — damage, homing, splitting and full-release bonuses.
- **纸身 / Vessel** — health, speed, hit protection and recovery.

Eighteen techniques form three fixed six-step routes. Definitions are shared read-only Resources; the selected route and earned steps live only in the current attempt.

## Persistence

- `settings.cfg`: audio, fullscreen, vibration, screen shake, high contrast.
- `profile.json`: versioned records, lifetime totals, codex discoveries, achievements, Glimmer, permanent upgrades, story flags and acknowledged introductions.
- All writes use `user://`; old profile versions migrate forward.

## Steam completion gates

- Six ritual acts, six Herald transitions, ten combat silhouettes and a three-phase boss.
- Three deterministic six-technique routes with no randomized rewards.
- Three readable stat debuffs, each cleansed through the existing hold/release verb.
- Telegraph-heavy black-gold Seal skills that cannot be captured, while remaining slowed by the fold field.
- Seven distinct low-contrast scene identities across the six tides and Ink Moon finale.
- Confirmation-based first-encounter and story briefings freeze combat simulation while preserving a slowly animated background; compact teaching lanes continue after confirmation.
- Action-oriented HUD rail for focus, fold charge and captured ammunition, plus persistent consequence/counter status chips.
- Controller-only completion, including title, technique seal, pause, settings and replay.
- Version-3 persistent profile, settings, Foldlight Court purchases and legacy migration.
- Independent Windows export with icon, metadata and no editor dependency.
- Full-run automated state test, save migration test, input test, boss-phase test and exported-build smoke test.
- GPU stress scene stays above 60 FPS on the current reference machine at 1080p.
