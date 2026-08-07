# Code Review — FOLDLIGHT Chapter I Campaign

## Critical

None remaining. Godot 4.6 editor import, live-scene startup, modal transitions, new enemy state machines, render callbacks and the six-tide complete-run integration smoke test are clean.

## Improvements resolved during review

- Boss spawn frame produced degenerate zero-area paper polygons. The visual spawn scale now has a non-zero floor.
- Direct autoload identifier access made standalone scene tests compile differently from a normal project launch. The game now caches the typed `/root/AudioDirector` node once with `@onready`.
- Gameplay Input Map names in hot paths now use `StringName` literals.
- Generated audio voices and playback references are stopped and released in `_exit_tree()`.
- Entity collections have explicit caps: 18 enemies, 300 hostile petals and 420 particles.
- Enemy and effect teaching tips are owned by a direct-child queue component; two lanes coexist, same-lane cards queue, and `channel:id` entries deduplicate per run.
- Fixed-layout combat now uses `viewport + keep`, preserving the complete 1920×1080 arena and HUD rather than cropping side information at 4:3.
- Tip snapshots reuse their active dictionaries instead of duplicating them every presentation frame.
- Paused teaching uses an explicit `BRIEFING` mode instead of pausing the SceneTree, so audio/HUD/background remain alive while physics simulation is guaranteed to stop.
- Rewinder history uses a fixed 54-point ring buffer and allocates a path snapshot only when its attack locks.
- Ram and Rewinder contact is gated to explicit danger states and uses swept segment collision to prevent high-speed tunnelling.
- Profile version 3 separates discovery, acknowledged introductions and story flags; test mode disables real user-data reads and writes.
- The retired archive-doctrine snapshot was removed from the per-frame Foldlight Court presentation path.

## Positive

- Player, world simulation, HUD and audio each have one named responsibility.
- Child signals travel upward; the game calls child presentation methods downward.
- Continuous movement uses `Input.get_vector()` in `_physics_process()`; fold, pause and restart are discrete `_unhandled_input()` actions.
- Keyboard and gamepad share the same Input Map contract.
- No resource loads, node lookups or node creation occur in hot gameplay loops.
- New enemy transitions use explicit enum state machines with authored timers and visible recovery windows.
- HUD lives on a dedicated `CanvasLayer`, ignores pointer input and receives pushed snapshots.
- Tide scenery remains in the world draw pass at low contrast; enemy/effect instruction cards remain in the HUD pass.
- SFX uses a fixed voice pool, and visual arrays remove expired entries in place.
- The integration smoke test drives real InputEvents and covers six Herald gates, all six deterministic doctrine steps, paused story beats, victory, defeat and restart paths.

Reviewed against Godot 4.3+ best practices on Godot 4.6.3.
