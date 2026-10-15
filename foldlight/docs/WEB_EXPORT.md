# Web export

Use Godot 4.6.3 and its matching `web_nothreads_release.zip` export template. Export preset **Web** writes `build/FOLDLIGHT_Web/index.html` with the Compatibility renderer, no threads, and no GDExtension support. It runs without COOP/COEP headers or `SharedArrayBuffer`.

```powershell
# Use isolated directories for validation; do not reuse a player's native profile.
$env:APPDATA = "$PWD/build/test-runtime/web-export/Roaming"
$env:LOCALAPPDATA = "$PWD/build/test-runtime/web-export/Local"
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA, "$PWD/build/FOLDLIGHT_Web"
godot --headless --path . --editor --import --quit
godot --headless --path . --export-release Web build/FOLDLIGHT_Web/index.html
```

Place the matching export templates under `$env:APPDATA/Godot/export_templates/4.6.3.stable` before exporting. Serve the result over HTTPS (localhost HTTP also works), with `.wasm` served as `application/wasm`. Opening `index.html` directly from disk is not supported. Keep the generated JS, WASM, PCK and audio worklet files together.

## Platform behavior

- Chinese UI and world labels use the bundled, OFL-licensed Foldlight Sans SC font. The full Chinese glyph collection is retained. Native builds keep their original system typography. Font provenance and license are in `assets/fonts/` and are included by each export preset.
- Music uses two pre-rendered, equal-length Ogg loops on the Web Sample backend: an ambient layer and a combat layer whose gain follows intensity. This removes frame-by-frame GDScript synthesis and Stream buffer starvation during dense combat. Rebuild the original score with `python tools/bake_music.py` (NumPy and FFmpeg; see the script for details).
- The Sites game's packager applies a version-checked Godot 4.6.3 compatibility patch for whole-buffer forward loops. Those loops use the browser's audio clock directly instead of scheduling a new source from `ended` on the game thread; this prevents inter-loop gaps and drift between the two music layers. Other loop ranges and one-shot effects retain their engine behavior. Its contract tests reject an unknown engine template rather than silently applying an incompatible patch.
- Synthesized WAV effects also use Sample playback. Paper transients are band-limited and tapered; note sequences have local attack envelopes. A bounded 12-voice pool drops excess cues rather than abruptly stealing an active sound, with one extra voice reserved for player damage. Browsers may require a click or key press before sound starts; the website launch action provides that gesture.
- Web startup never restores fullscreen automatically. Fullscreen requests happen synchronously from a setting action; an embedding website can also provide its own fullscreen button. The browser edition hides the native Quit button.
- Ordinary solo save files use the browser's IndexedDB. Private browsing, storage clearing, or blocking storage can remove persistence. Web race sessions deliberately skip the ordinary profile and settings persistence to keep competitions isolated.
- Keyboard and gamepad controls are supported. This build does not add touch controls. A WebGL 2 capable browser is required.

## Hosting size

The Godot 4.6.3 single-thread release engine is 37,700,666 bytes (35.95 MiB), larger than a 25 MiB static-asset limit. The companion site packages it into bounded chunks and reconstructs a streamed response before Godot loads it. Do not rename or manually edit generated engine files. The first game pack is approximately 10.45 MiB; remeasure it after content changes.

## Verification

The first export was launched in Edge with a fresh browser context and a plain local HTTP server without isolation headers. The title and story selector rendered their Chinese text, the audio context ran, and the console had no script/runtime errors. `crossOriginIsolated` was false and `SharedArrayBuffer` was undefined. This checks Chromium compatibility; it is not a Safari, Firefox, mobile, or frame-rate certification.

References: [Godot Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [SystemFont platform support](https://docs.godotengine.org/en/stable/classes/class_systemfont.html), [Web preset properties](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformweb.html).
