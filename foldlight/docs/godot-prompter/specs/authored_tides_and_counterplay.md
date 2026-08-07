# FOLDLIGHT — Authored Tides and Counterplay

## Product decision

FOLDLIGHT is a fixed, authored narrative voyage rather than a run-randomized Roguelike. Chapter I always contains six combat tides, six Herald gates, one deterministic technique path, and the Ink Moon finale. Randomness may vary formations, never the chapter structure or awarded technique.

## Flow and difficulty

1. **Still Water** teaches movement, capture, and release with Drifters only.
2. **Paper Kite** adds Fans, crosswind, then a single Weaver that teaches `Veiled Fold`, its full-charge cleanse, and the first telegraphed black-gold Seal projectile.
3. **Echo** adds Bloomers and introduces the Mirror Folder. Its visible cyan fold field captures player return lights and releases them back as capturable hostile petals.
4. **Storm Eye** combines Leeches, Weavers, and Mirror Folders. `Wet Ink` and other accumulated effects teach deliberate cleansing.
5. **Red Wheel** introduces the rebuilt Ram: a harmless gold-line telegraph, locked high-speed charge, wall shockwave, and punishable recovery.
6. **Reversal** introduces the Rewinder, which shows and retraces its exact recent four-second path, then mixes it with Rams and Mirror Folders.
7. **Ink Moon** remixes the learned rules in three readable phases.

Pressure is monotonic and visible in the HUD. Each tide has an opening section, first ritual, second ritual, and Herald gate.

## Deterministic technique paths

The first Herald offers three fixed paths. Later Heralds award the next fixed technique in the selected path; there is no random draft.

| Path | Tide I | Tide II | Tide III | Tide IV | Tide V | Tide VI |
|---|---|---|---|---|---|---|
| Fold Field | Wide Crease | Deep Breath | Still Water | Lantern Pocket | Quiet Horizon | Ocean Fold |
| Return Light | Swift Return | Bright Edge | Chain Bloom | Full Moon | Sunward | Starfall |
| Lantern Body | Slipstream | Paper Heart | Mercy Blank | Golden Seam | Afterglow | Dawn Vow |

## Status counterplay

| Status | Stat effect | Player counter |
|---|---|---|
| Wet Ink | Focus regeneration -45% | Release at least 6 lights |
| Bound Crease | Movement speed -30% | Release at least 3 lights |
| Veiled Fold | Fold radius -28% | Release at full charge |

Statuses never reverse controls or disable the fold button. Every counter uses the existing hold/release language and remains possible while affected.

## Projectile contract

- Ordinary petals and Mirror Folder reflections have `reflectable = true` and use the normal fold/capture/return loop.
- Black-gold Seal skill petals have `reflectable = false`. The fold field still slows them, but never removes them or adds ammunition.
- Seal petals use a larger orange diamond, dark core, crossbar, and red tail. Their source contracts an orange warning ring for roughly one second before firing.
- Weavers introduce a three-petal aimed seal fan. Later Heralds use a six-petal seal ring whose player-facing direction is deliberately left as a gap.
- The first charge displays an explicit rule message; later casts rely on the stable visual and audio telegraph.

## Ownership and communication

```text
FoldlightGame (world authority)
├── enemy dictionaries: attack/status payloads, Mirror state
├── hostile/return-light arrays: collision and interception
├── Player (movement/combat authority)
│   └── StatusEffects (timers, multipliers, cleanse rules)
└── HUD CanvasLayer (read-only snapshots)
```

- `FoldlightGame` applies a named status only after a real, non-invulnerable hit.
- `StatusEffects` owns status duration and exposes multipliers to `Player`.
- `Player` emits `statuses_cleansed` after a qualifying release.
- `FoldlightGame` turns that signal into audiovisual confirmation.
- HUD never mutates gameplay state.

## Mirror Folder state machine

`SEEK → FOLD → RELEASE → SEEK`

- **Seek:** orbits at range and fires ordinary, capturable petals.
- **Fold:** slows down and shows a large cyan interception ring. Return lights entering it are stored.
- **Release:** fires the stored count back toward the player as ordinary, capturable petals that inflict Veiled Fold on hit.

The state machine has explicit timers and no implicit transitions. The Fold state is the only interception state.
