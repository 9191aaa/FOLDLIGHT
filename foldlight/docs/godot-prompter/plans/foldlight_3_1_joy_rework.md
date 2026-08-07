# FOLDLIGHT 3.1 Joy Rework Plan

## 1. Baseline and behavioral tests

- [ ] Preserve the current focused test baseline.
- [ ] Add failing contracts for encounter body counts, overlapping reinforcements, homing return light, dash cadence, active-item impact, new roles and terrain polarity.

Skills: `godot-prompter:godot-testing`

## 2. Dense readable encounters

- [ ] Separate body-density requirements from threat spending.
- [ ] Raise regional budgets and author 18–30 enemy room totals.
- [ ] Trigger telegraphed reinforcement waves before the current wave reaches zero.
- [ ] Keep controller, buffer and stationary pressure quotas deterministic.

Skills: `godot-prompter:procedural-generation`, `godot-prompter:resource-pattern`, `godot-prompter:godot-testing`

## 3. Mechanic roster

- [ ] Add Prism Bulwark, Brood Lantern and Shear Scribe definitions and self-contained scenes.
- [ ] Connect their signals to the shared combat runtime and mechanic introduction cards.
- [ ] Verify one-rule silhouettes, telegraphs and priority-target counterplay.

Skills: `godot-prompter:ai-navigation`, `godot-prompter:scene-organization`, `godot-prompter:component-system`, `godot-prompter:2d-essentials`

## 4. Fold, dash and active payoff

- [ ] Restore every captured shot as a homing, retargeting Return Missile with a trail.
- [ ] Increase base dash cooldown and retain build-controlled recovery.
- [ ] Strengthen all six active items and add shared pulse/impact presentation.

Skills: `godot-prompter:component-system`, `godot-prompter:player-controller`, `godot-prompter:2d-essentials`

## 5. Terrain and room art

- [ ] Add positive Sun Patch and double-edged Thorn Paper mechanics.
- [ ] Expand all region and boss layouts with safe, varied terrain clusters.
- [ ] Improve backdrop and terrain custom drawing without obscuring projectile language.

Skills: `godot-prompter:2d-essentials`, `godot-prompter:physics-system`, `godot-prompter:camera-system`

## 6. Balance and release

- [ ] Run parser, focused tests, full 3.0/Classic regressions and performance checks.
- [ ] Capture representative rooms and inspect them at 1920×1080.
- [ ] Export and smoke-test the Windows build.

Skills: `godot-prompter:godot-testing`, `godot-prompter:godot-code-review`, `godot-prompter:godot-optimization`, `godot-prompter:export-pipeline`
