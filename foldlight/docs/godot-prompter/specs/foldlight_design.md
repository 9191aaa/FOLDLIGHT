# FOLDLIGHT / 折光 — Game Design

## Visual thesis

Deep-night indigo paper sea, warm ivory origami, and restrained cyan-gold light; every combat action should feel like folding a luminous print by hand.

## Content plan

1. Title: logo, one-sentence premise, one action to start.
2. Learn by play: movement, hold-to-fold, release-to-return in three short prompts.
3. Six authored tides: each adds one readable threat or combination.
4. Finale: a bespoke Ink Moon boss, victory rank, story epilogue and permanent Glimmer reward.
5. Foldlight Court: spend Glimmer on four compact upgrades before the next voyage.

## Interaction thesis

- Movement pulls a layered ink-and-gold ribbon behind the paper moth.
- Holding Fold slows the player while an expanding paper crease catches hostile petals.
- Releasing snaps the whole field inward, then sends the stored petals back as a homing ribbon.

## Core loop

Move to dodge → hold one button to catch nearby hostile shots → release to convert everything caught into automatic counterfire → defeat six authored tides and the boss → carry Glimmer into the next voyage.

## Scene tree

```text
Foldlight (Node2D) — owns run state, encounters, collision and world drawing
├── Player (CharacterBody2D) — owns movement, focus, capture capacity and character drawing
│   └── CollisionShape2D — documents the readable player hit radius
└── HUD (CanvasLayer, layer 5) — screen-space information and overlays
    └── Interface (Control) — owns all responsive HUD/title/result drawing

/root/AudioDirector (Autoload)
├── Music (AudioStreamPlayer) — generated adaptive music stream
└── SFXPool (8 × AudioStreamPlayer) — reusable one-shot voice pool
```

## Responsibilities

| Node | Owns | Calls / emits |
|---|---|---|
| Foldlight | enemies, hostile/friendly shots, acts, score, win/loss | calls Player/HUD; drives AudioDirector intensity |
| Player | input-driven movement, focus, fold radius, health/i-frames | emits `fold_started`, `fold_released`, `focus_empty` |
| Interface | display-only UI state and transitions | receives `present(state)` from Foldlight |
| AudioDirector | generated music, SFX resources, pooled voices | receives `play_sfx()` and `set_intensity()` |

## Signal map

| Signal | Source | Consumer | Payload |
|---|---|---|---|
| `fold_started` | Player | Foldlight | none |
| `fold_released` | Player | Foldlight | captured count, charge ratio |
| `focus_empty` | Player | Foldlight | captured count, charge ratio |

Signals travel upward. Foldlight calls child presentation methods downward. No peer uses parent traversal.

## Data flow

`InputMap fold press` → `Player.begin_fold()` → expanding radius → `Foldlight` detects hostile petals inside radius → `Player.capture_one()` → release signal → `Foldlight.spawn_return_light()` × captured → homing hits enemy → score/particles/audio → `HUD.present(snapshot)`.

## Failure boundaries

- Missing child nodes are caught by typed `@onready` paths during startup.
- A fold release with zero petals creates feedback but no damage.
- Enemy and projectile arrays are capped; dead entries are removed every physics tick.
- Boss arrival clears disposable enemies and slows existing petals so the transition is readable.
