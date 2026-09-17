# FOLDLIGHT Demo 0.2.1 — impact feedback adjustment

Player feedback on 0.2.0: screen shake was too weak.

This is a feedback-only hotfix. The three encounters, two reward choices, boss tuning, controls, collision and upgrade definitions are unchanged.

At the existing subtle setting (0.55), an eight-light release now requests a 7.04 logical-pixel peak, previously 2.86. This is about 2.46 times the configured amplitude, not a claim about subjective strength. The event-local waveform starts at its peak, holds the amplitude envelope for 25 ms, and settles within 240 ms for a full release. Ordinary kills, hurt and boss transitions receive separate stronger pulses. Single-bullet releases remain smaller, captures still use sound/sparks without camera shake, and weak auto-fire still does not shake the view.

Lower-amplitude requests cannot overwrite a stronger active impulse's timing. Total translation is capped at 16 logical pixels and each accepted impulse at 300 ms. No camera rotation, zoom or added gameplay hit-stop. Off stays off, saved preferences are retained, and pause clears the camera offset.

The build stamps the packaged UI and metadata as 0.2.1 and runs the retained boss/voyage tests plus a feedback-specific suite. Checks cover frame sampling at 30/60/144 FPS, event ordering, true player release signals, unchanged actor/HUD transforms, disabled feedback and pause/reset. Test pass counts and final executable provenance are reported by CI, not assumed in this note.
