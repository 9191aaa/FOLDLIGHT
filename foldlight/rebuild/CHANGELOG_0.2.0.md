# FOLDLIGHT Reflect Demo 0.2.0

User feedback: the first executable was playable but too bare, and needed a little screen shake.

## Delivered scope

- A finite voyage: three authored two-wave encounters, two three-choice upgrade breaks, then the existing balanced two-phase Reef Crown boss. Keep the direct boss practice entrance.
- Six run-local upgrades using the shared combat stat schema. Recovery between rooms and full-health checkpoint retry; upgrades persist only for the current voyage and are not duplicated on retry.
- Bounded, decaying, render-only shake, subtle by default; off/subtle/standard options on title and pause, saved in the demo user directory. HUD remains in an independent CanvasLayer. No physics position changes and no gameplay RNG use.
- Capture spark, return ripple, hit sparks, kill shards, boss-transition pulse, hurt edge tint, and throttled original synthesized sound cues. Pause removes camera displacement; result lets visual tails finish before its menu.
- Reworked Chinese title, status panels, smooth health bars, boss core meter, reward cards and retry screens. F11 fullscreen and M mute.

## Verification

CI imports the project, runs the retained Boss Lab assertions plus voyage/feedback/upgrade regression tests, exports Windows x86-64 and starts the packaged EXE headlessly. A separate Linux Mesa/Xvfb job captures actual title, voyage, reward and boss frames. Consult the run attached to the exact commit for actual results; the presence of a test is not a test pass.

These tests include forced-damage route traversal for state coverage. They do not prove human difficulty, run duration or frame rate on the player's PC. The standard boss profile is unchanged; upgrades intentionally improve the player's chances in the voyage.

The tracked classic project and main branch are preserved. New files are isolated to rebuild/ and build tooling. The Windows export uses a separate demo user directory. Fonts are resolved from the operating system; no font files are distributed by this change.
