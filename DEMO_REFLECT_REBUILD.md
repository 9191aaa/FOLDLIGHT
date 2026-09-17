# FOLDLIGHT Reflect Rebuild Demo

This branch is an isolated playable boss demo for the cleaner reflect-bullet combat direction.

## Run

From Windows PowerShell:

```powershell
cd foldlight
.\run_reflect_demo.ps1
```

Or open `foldlight/project.godot` in Godot 4.6+ and run `res://rebuild/scenes/boss_lab.tscn` with F6.

## Controls

- WASD / arrows: move
- Space / E: hold Fold to capture purple petals; release to return them
- Shift: dash. If a dash is ready while carrying captured bullets, the demo releases them before dashing.
- Esc: pause/resume

## Boss design

Normal is the intended baseline: 320 HP, 5 player HP, two phases, roughly one-second warnings, no summons, no shrinking arena, and no hidden reflected-damage suppression. Purple attacks feed the reflect loop. Black/gold lanes cannot be captured and must be dodged. A strong sequence of return hits opens a short break window where return damage is amplified.

Relaxed keeps the same rules with slower attacks and more health allowance. Challenge speeds the cadence without adding unrelated mechanics.

## Scope

This is deliberately a boss lab rather than the full rebuilt campaign. It reuses the existing player, projectile, enemy-art, return-light and Godot runtime, while replacing the boss scheduler and tuning. The next step after validating feel is to put 3-4 curated encounters before this boss.

## Validation status

The branch was assembled through GitHub source writes. It has not been executed in a Godot runtime from this environment, so treat it as a playable-source candidate until it is imported/run on a machine with Godot 4.6+.
