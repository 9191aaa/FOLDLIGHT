# 烬火纸雷 / Cinder Mine

The later-game bomber shares the existing enemy factory, hit feedback, encounter accounting, and player damage rules. No timers or physics callbacks run independently from the combat runtime.

- Appears in expedition regions 2–3 from depth 2 onward, in combat / elite / event rooms. Threat cost 3, 5 base health, 135 movement speed, at most two in an encounter.
- Endless adds one every third wave after 150 survival seconds, spending 3 points from the wave budget. At most two bombers may be alive. Spawn sites use the existing seed/wave schedule; bombers are never task captains.
- Has 0.6 seconds of spawn grace. Within 185 pixels of its target, it stops and starts a full 1.5-second fuse. The fixed 160-pixel red circle, shrinking fuse marks, and numeric countdown show the danger even with motion disabled.
- A completed fuse emits exactly one radial hit check and retires the actor. The shared hit route limits damage to one heart and honors dash immunity, shields, damage grace, and fatal guards. Touching the actor causes no separate hit.
- Killing it before the fuse expires disarms it. It creates no explosive projectiles, child enemies, or chain explosions. A spent actor emits defeat only once, preserving room-clear and endless-task accounting.
- Pause and rewards freeze the fuse. A large delta advances at most 0.1 seconds per simulation tick, preserving a readable warning after a frame stall.

Tests: `test_cinder_mine.gd` exercises real factory, projectile collision, damage, pause, disarming, dash and shield interactions. `test_cinder_mine_placement.gd` exercises expedition gating and budgets, seeded endless placement, concurrency limits and restart cleanup.
