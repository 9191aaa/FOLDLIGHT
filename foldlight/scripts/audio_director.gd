class_name FoldlightAudioDirector
extends Node

signal sfx_requested(sound_name: StringName, pitch: float, volume_db: float)

## Original, pre-rendered adaptive score and pooled one-shot synthesis.
## Music runs on the browser's audio clock, independent of busy combat frames.

const MIX_RATE: float = 44100.0
const POOL_SIZE: int = 12
const IMPACT_TOKEN_LIMIT: float = 4.0
const IMPACT_TOKEN_REFILL: float = 18.0
const IMPACT_GAPS: Dictionary = {&"weapon": 0.065, &"return": 0.085, &"break": 0.10}
const MUSIC_THEMES: Dictionary = {
	&"harbor": "paper_harbor", &"reef": "paper_sea", &"archive": "paper_archive",
	&"eclipse": "paper_eclipse", &"boss": "paper_boss",
}
const MUSIC_CROSSFADE_SECONDS: float = 2.4
const PAPER_CUTOFF_HZ: float = 4200.0

var _music_player: AudioStreamPlayer
var _music_energy_player: AudioStreamPlayer
var _hurt_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx: Dictionary = {}
var _pool_cursor: int = 0
var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _music_gain: float = 0.0
var _music_pressure: float = 0.0
var _music_context: StringName = &"title"
var _music_region: StringName = &"paper_reef"
var _music_theme: StringName = &"harbor"
var _music_scene_gain: float = 1.0
var _music_scene_target: float = 1.0
var _music_banks: Array[Dictionary] = []
var _music_positions: Dictionary = {}
var _music_active_bank: int = 0
var _music_incoming_bank: int = -1
var _music_fade_elapsed: float = 0.0
var _music_enabled: bool = true
var _web_music_cache: JavaScriptObject
var _music_pending_release: Array[AudioStream] = []
var _muted: bool = false
var _impact_tokens: float = IMPACT_TOKEN_LIMIT
var _impact_cooldowns: Dictionary = {}
var _hurt_focus_remaining: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name().to_lower() == "headless":
		return
	_build_sfx_pool()
	_build_sfx_library()
	_build_music_player()


func _process(delta: float) -> void:
	_impact_tokens = minf(IMPACT_TOKEN_LIMIT, _impact_tokens + maxf(0.0, delta) * IMPACT_TOKEN_REFILL)
	_hurt_focus_remaining = maxf(0.0, _hurt_focus_remaining - delta)
	for kind in _impact_cooldowns:
		_impact_cooldowns[kind] = maxf(0.0, float(_impact_cooldowns[kind]) - delta)
	var quiet := _music_context in [&"paused", &"reward", &"victory", &"defeat"]
	_intensity = move_toward(_intensity, _target_intensity, delta * (0.85 if quiet else 0.32))
	_music_gain = move_toward(_music_gain, 1.0, delta * 0.75)
	_music_scene_gain = move_toward(_music_scene_gain, _music_scene_target, delta * 0.65)
	_update_music_banks(delta)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	_music_enabled = false
	_music_incoming_bank = -1
	for bank in _music_banks:
		_clear_music_bank(bank)
	if is_instance_valid(_hurt_player):
		_hurt_player.stop()
		_hurt_player.stream = null
	for voice in _sfx_players:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_sfx_players.clear()
	_sfx.clear()


func set_intensity(value: float) -> void:
	_music_pressure = clampf(value, 0.0, 1.0)
	_update_music_mood()


## Presentation only: neither scene transitions nor musical variation use the
## gameplay RNG or affect combat time. Quiet overlays retain the current score.
func set_music_context(context: StringName, region: StringName = &"", intensity: float = -1.0) -> void:
	if context not in [&"title", &"route", &"rest", &"combat", &"boss", &"endless", &"reward", &"paused", &"victory", &"defeat"]:
		return
	_music_context = context
	if region != &"": _music_region = region
	if intensity >= 0.0: _music_pressure = clampf(intensity, 0.0, 1.0)
	match context:
		&"title", &"route", &"rest": _music_theme = &"harbor"
		&"boss": _music_theme = &"boss"
		&"combat", &"endless":
			match _music_region:
				&"inverted_ink_city": _music_theme = &"archive"
				&"nameless_sun_court": _music_theme = &"eclipse"
				_: _music_theme = &"reef"
	_update_music_mood()
	if _music_enabled and not _music_banks.is_empty() and _music_incoming_bank < 0:
		_begin_music_transition()


func _update_music_mood() -> void:
	var energy_scale := 1.0
	_music_scene_target = 1.0
	match _music_context:
		&"title", &"route", &"rest": energy_scale = 0.45
		&"paused", &"reward":
			energy_scale = 0.08
			_music_scene_target = 0.65
		&"victory":
			energy_scale = 0.03
			_music_scene_target = 0.75
		&"defeat":
			energy_scale = 0.0
			_music_scene_target = 0.55
	_target_intensity = _music_pressure * energy_scale


func get_music_state() -> Dictionary:
	var themes: Array[StringName] = []
	var playing := 0
	for bank in _music_banks:
		if bank.theme != &"": themes.append(bank.theme)
		for voice: AudioStreamPlayer in [bank.base, bank.energy]:
			if voice.playing: playing += 1
	return {"context": _music_context, "theme": _music_theme, "region": _music_region,
		"intensity": _intensity, "target_intensity": _target_intensity,
		"loaded_themes": themes, "playing_layers": playing,
		"transitioning": _music_incoming_bank >= 0, "enabled": _music_enabled}


func play_sfx(sound_name: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if sound_name == &"hurt":
		_hurt_focus_remaining = 0.16
	var priority := _sound_priority(sound_name)
	var resolved_volume := volume_db - (6.0 if _hurt_focus_remaining > 0.0 and priority < 3 else 0.0)
	var resolved_pitch := clampf(pitch, 0.55, 1.8)
	if not _sfx.has(sound_name):
		# Headless simulation still exposes accepted cues to integration tests.
		if DisplayServer.get_name().to_lower() == "headless":
			sfx_requested.emit(sound_name, resolved_pitch, resolved_volume)
		return
	var selected: AudioStreamPlayer
	# Reserve one bounded voice for damage. Never cut a waveform halfway through
	# to make room for a new hit: Sample playback cannot fade stops for us.
	if sound_name == &"hurt" and is_instance_valid(_hurt_player) and not _hurt_player.playing:
		selected = _hurt_player
	else:
		for index in _sfx_players.size():
			var voice := _sfx_players[(_pool_cursor + index) % _sfx_players.size()]
			if not voice.playing:
				selected = voice
				break
	if selected == null:
		return
	_pool_cursor = (_pool_cursor + 1) % _sfx_players.size()
	selected.stream = _sfx[sound_name]
	selected.pitch_scale = resolved_pitch
	selected.volume_db = resolved_volume
	selected.set_meta(&"sfx_priority", priority)
	sfx_requested.emit(sound_name, resolved_pitch, resolved_volume)
	selected.play()


## Only confirmed damage/defeat events enter this shared audio budget.
## Timers are presentation-only; no physics delta, global time scale or RNG changes.
func play_combat_impact(kind: StringName, weight: float = 1.0) -> bool:
	if not IMPACT_GAPS.has(kind) or _hurt_focus_remaining > 0.0:
		return false
	if float(_impact_cooldowns.get(kind, 0.0)) > 0.0:
		return false
	# Reserve one token for a kill so a burst of weak hits cannot swallow it.
	if _impact_tokens < (1.0 if kind == &"break" else 2.0):
		return false
	_impact_tokens -= 1.0
	_impact_cooldowns[kind] = float(IMPACT_GAPS[kind])
	var strength := clampf(weight, 0.0, 1.0)
	match kind:
		&"weapon": play_sfx(&"paper_hit", 1.03 + strength * 0.12, -13.0 + strength * 2.0)
		&"return": play_sfx(&"return_hit", 0.92 + strength * 0.10, -8.5 + strength * 1.5)
		&"break": play_sfx(&"paper_break", 0.96 + strength * 0.12, -10.0 + strength * 2.0)
	return true


func reset_combat_feedback() -> void:
	_impact_cooldowns.clear()
	_impact_tokens = IMPACT_TOKEN_LIMIT
	_hurt_focus_remaining = 0.0


func _sound_priority(sound_name: StringName) -> int:
	if sound_name == &"hurt":
		return 3
	if sound_name in [&"release", &"return_hit", &"paper_break", &"kill", &"act", &"boss", &"victory"]:
		return 2
	return 1


func toggle_mute() -> bool:
	_muted = not _muted
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, _muted)
	return _muted


func is_muted() -> bool:
	return _muted


func _build_music_player() -> void:
	if not _music_banks.is_empty(): return
	_music_gain = 0.0
	if OS.has_feature("web"):
		_web_music_cache = JavaScriptBridge.get_interface("FoldlightMusicCache")
	for index in 2:
		var bank := {"theme": &"", "offset": 0.0, "started_at": 0}
		for layer in ["base", "energy"]:
			var voice := AudioStreamPlayer.new()
			voice.name = "Music%d%s" % [index, layer.capitalize()]
			voice.bus = &"Music"
			voice.volume_linear = 0.0
			if OS.has_feature("web"):
				voice.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
			add_child(voice)
			bank[layer] = voice
		_music_banks.append(bank)
	_load_music_bank(_music_banks[0], _music_theme)
	_set_active_music_bank(0)


func _load_music_bank(bank: Dictionary, theme: StringName) -> void:
	var prefix: String = MUSIC_THEMES[theme]
	for layer in ["base", "energy"]:
		var voice: AudioStreamPlayer = bank[layer]
		voice.stream = ResourceLoader.load("res://assets/audio/%s_%s.ogg" % [prefix, layer], "AudioStreamOggVorbis", ResourceLoader.CACHE_MODE_IGNORE)
		voice.volume_linear = 0.0
		if OS.has_feature("web"):
			# Decode BOTH layers before starting either clock. Web uses native
			# AudioBuffer loops so busy gameplay frames cannot interrupt music.
			AudioServer.register_stream_as_sample(voice.stream)
			if _web_music_cache != null:
				_web_music_cache.prepare(str(voice.stream.get_instance_id()))
	bank.theme = theme
	bank.offset = fmod(float(_music_positions.get(theme, 0.0)), bank.base.stream.get_length())
	bank.started_at = Time.get_ticks_msec()
	bank.base.play(bank.offset)
	bank.energy.play(bank.offset)


func _clear_music_bank(bank: Dictionary) -> void:
	if bank.theme != &"":
		_music_positions[bank.theme] = float(bank.offset) + float(Time.get_ticks_msec() - int(bank.started_at)) / 1000.0
	# Stop both sources before retiring their browser-side PCM. Releasing the
	# Godot resource alone leaves an entry in the Web driver's sample registry.
	bank.base.stop()
	bank.energy.stop()
	for voice: AudioStreamPlayer in [bank.base, bank.energy]:
		if voice.stream != null and _web_music_cache != null:
			if not _web_music_cache.release(str(voice.stream.get_instance_id())):
				_music_pending_release.append(voice.stream)
		voice.stream = null
	bank.theme = &""


func _set_active_music_bank(index: int) -> void:
	_music_active_bank = index
	_music_player = _music_banks[index].base
	_music_energy_player = _music_banks[index].energy


func _begin_music_transition() -> void:
	if _music_banks[_music_active_bank].theme == _music_theme: return
	# Packaged Web builds always supply the bounded cache adapter. A raw engine
	# export keeps its initial cue rather than accumulating unreleasable samples.
	if OS.has_feature("web") and _web_music_cache == null: return
	_music_incoming_bank = 1 - _music_active_bank
	_music_fade_elapsed = 0.0
	if not OS.has_feature("web"):
		_load_music_bank(_music_banks[_music_incoming_bank], _music_theme)


func _apply_music_gain(bank: Dictionary, weight: float) -> void:
	var gain := _music_gain * _music_scene_gain * weight
	bank.base.volume_linear = gain
	bank.energy.volume_linear = gain * _intensity


func _update_music_banks(delta: float) -> void:
	if not _music_enabled or _music_banks.is_empty(): return
	for index in range(_music_pending_release.size() - 1, -1, -1):
		if _web_music_cache.release(str(_music_pending_release[index].get_instance_id())):
			_music_pending_release.remove_at(index)
	if _music_incoming_bank < 0:
		_apply_music_gain(_music_banks[_music_active_bank], 1.0)
		_begin_music_transition()
		return
	var outgoing := _music_banks[_music_active_bank]
	var incoming := _music_banks[_music_incoming_bank]
	var half := MUSIC_CROSSFADE_SECONDS * 0.5
	if OS.has_feature("web"):
		# Fade through on mobile browsers: release the old pair BEFORE decoding
		# the new one. At most two music buffers live, independent of room count.
		if outgoing.theme != &"":
			_music_fade_elapsed += delta
			_apply_music_gain(outgoing, 1.0 - clampf(_music_fade_elapsed / half, 0.0, 1.0))
			if _music_fade_elapsed >= half:
				_clear_music_bank(outgoing)
				_music_fade_elapsed = half
			return
		if incoming.theme == &"":
			if _music_pending_release.is_empty():
				_load_music_bank(incoming, _music_theme)
			return
		_music_fade_elapsed += delta
		_apply_music_gain(incoming, clampf((_music_fade_elapsed - half) / half, 0.0, 1.0))
	else:
		_music_fade_elapsed += delta
		var blend := clampf(_music_fade_elapsed / MUSIC_CROSSFADE_SECONDS, 0.0, 1.0)
		_apply_music_gain(outgoing, 1.0 - blend)
		_apply_music_gain(incoming, blend)
	if _music_fade_elapsed >= MUSIC_CROSSFADE_SECONDS:
		_clear_music_bank(outgoing)
		_set_active_music_bank(_music_incoming_bank)
		_music_incoming_bank = -1


func _build_sfx_pool() -> void:
	var pool := Node.new()
	pool.name = "SFXPool"
	add_child(pool)
	for index in POOL_SIZE:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%02d" % index
		voice.bus = &"SFX"
		voice.max_polyphony = 1
		pool.add_child(voice)
		_sfx_players.append(voice)
	_hurt_player = AudioStreamPlayer.new()
	_hurt_player.name = "HurtVoice"
	_hurt_player.bus = &"SFX"
	pool.add_child(_hurt_player)


func _build_sfx_library() -> void:
	var names: Array[StringName] = [
		&"start", &"fold", &"capture", &"release", &"empty",
		&"hit", &"hurt", &"kill", &"act", &"boss", &"victory", &"ui",
		&"paper_hit", &"return_hit", &"paper_break",
	]
	for sound_name in names:
		_sfx[sound_name] = _synthesize_sfx(sound_name)


func _synthesize_sfx(sound_name: StringName) -> AudioStreamWAV:
	var duration := 0.22
	match sound_name:
		&"paper_hit": duration = 0.075
		&"return_hit": duration = 0.16
		&"paper_break": duration = 0.19
		&"start": duration = 0.75
		&"release": duration = 0.62
		&"hurt": duration = 0.38
		&"kill": duration = 0.42
		&"act": duration = 0.85
		&"boss": duration = 1.35
		&"victory": duration = 2.1
		_: pass
	var frame_count := int(MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 4)
	var write_index := 0
	var filter_paper := sound_name in [&"paper_hit", &"return_hit", &"paper_break", &"hit", &"hurt"]
	var filter_alpha := 1.0 - exp(-TAU * PAPER_CUTOFF_HZ / MIX_RATE)
	var filtered := 0.0
	var filtered_twice := 0.0
	for i in frame_count:
		var t := float(i) / MIX_RATE
		var u := float(i) / float(maxi(1, frame_count - 1))
		var sample := _sfx_sample(sound_name, t, u)
		if filter_paper:
			filtered += filter_alpha * (sample - filtered)
			filtered_twice += filter_alpha * (filtered - filtered_twice)
			sample = filtered_twice
		# Also taper the filter's tail and the very last sample to digital silence.
		sample *= smoothstep(0.0, 0.003, minf(t, float(frame_count - 1 - i) / MIX_RATE))
		var left := clampf(sample * (0.96 + 0.04 * sin(t * 19.0)), -1.0, 1.0)
		var right := clampf(sample * (0.96 + 0.04 * cos(t * 17.0)), -1.0, 1.0)
		write_index = _write_pcm16(bytes, write_index, left)
		write_index = _write_pcm16(bytes, write_index, right)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(MIX_RATE)
	stream.stereo = true
	stream.data = bytes
	return stream


func _sfx_sample(sound_name: StringName, t: float, u: float) -> float:
	var attack := minf(1.0, u * 38.0)
	var decay := pow(1.0 - u, 2.2)
	var env := attack * decay
	match sound_name:
		&"paper_hit":
			var transient := exp(-t * 48.0) * minf(1.0, t * 1200.0)
			var paper := _noise(t * 23000.0) - _noise(t * 23000.0 + 0.9) * 0.55
			return (paper * 0.33 + sin(TAU * 680.0 * t) * 0.10) * transient * (1.0 - u)
		&"return_hit":
			var transient := minf(1.0, t * 900.0) * exp(-t * 24.0) * (1.0 - u)
			var body := sin(TAU * (210.0 * t - 380.0 * t * t)) * 0.40
			return (body + _noise(t * 18000.0) * exp(-t * 35.0) * 0.22 + sin(TAU * 960.0 * t) * 0.12) * transient
		&"paper_break":
			var tear := _noise(t * 25000.0) * (0.35 + 0.15 * sin(t * 190.0))
			return (tear + sin(TAU * (420.0 * t + 1000.0 * t * t)) * 0.18) * minf(1.0, t * 1100.0) * exp(-t * 19.0) * (1.0 - u)
		&"start":
			var step := mini(2, int(u * 3.0))
			var note: int = [57, 64, 69][step]
			var local_u := fmod(u * 3.0, 1.0)
			var local_time := local_u * (0.75 / 3.0)
			return sin(TAU * _midi_to_hz(note) * local_time) * smoothstep(0.0, 0.006, local_time) * pow(1.0 - local_u, 1.8) * 0.42
		&"fold":
			var phase := _sweep_phase(210.0, 540.0, t, u)
			return (sin(phase) + sin(phase * 2.03) * 0.2) * env * 0.34
		&"capture":
			var phase := _sweep_phase(520.0, 1080.0, t, u)
			return sin(phase) * env * 0.32 + sin(phase * 1.5) * env * 0.1
		&"release":
			var phase := TAU * t * (260.0 + (2.0 / 3.0) * 660.0 * sqrt(u))
			return (sin(phase) + sin(phase * 1.498) * 0.35) * env * 0.42
		&"empty":
			return sin(_sweep_phase(240.0, 130.0, t, u)) * env * 0.22
		&"hit":
			var noise := _noise(t * 12000.0)
			return (sin(TAU * 170.0 * t) * 0.55 + noise * 0.45) * env * 0.38
		&"hurt":
			var noise := _noise(t * 18000.0)
			return (sin(_sweep_phase(150.0, 62.0, t, u)) * 0.7 + noise * 0.3) * env * 0.48
		&"kill":
			var phase := _sweep_phase(180.0, 860.0, t, u)
			return (sin(phase) * 0.55 + sin(phase * 2.0) * 0.16) * env * 0.42
		&"act":
			return (sin(TAU * 110.0 * t) * 0.35 + sin(TAU * 220.0 * t) * 0.18 + sin(TAU * 440.0 * t) * 0.08) * sin(PI * u) * 0.5
		&"boss":
			var rumble := sin(_sweep_phase(54.0, 39.0, t, u))
			return (rumble * 0.58 + sin(TAU * 81.0 * t) * 0.2) * sin(PI * u) * 0.65
		&"victory":
			var slot := mini(7, int(u * 8.0))
			var notes: Array[int] = [57, 61, 64, 69, 64, 68, 71, 76]
			var local_u := fmod(u * 8.0, 1.0)
			var local_time := local_u * (2.1 / 8.0)
			return (sin(TAU * _midi_to_hz(notes[slot]) * local_time) + sin(TAU * _midi_to_hz(notes[slot] - 12) * local_time) * 0.25) * smoothstep(0.0, 0.006, local_time) * pow(1.0 - local_u, 1.4) * 0.36
		&"ui":
			return sin(TAU * 720.0 * t) * env * 0.23
		_:
			return 0.0


func _sweep_phase(start_hz: float, end_hz: float, time: float, progress: float) -> float:
	# Integrate the frequency ramp; frequency(t) * t doubles its slope.
	return TAU * time * (start_hz + 0.5 * (end_hz - start_hz) * progress)


func _write_pcm16(bytes: PackedByteArray, index: int, sample: float) -> int:
	var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
	if value < 0:
		value += 65536
	bytes[index] = value & 0xFF
	bytes[index + 1] = (value >> 8) & 0xFF
	return index + 2


func _midi_to_hz(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


func _noise(seed_value: float) -> float:
	var value := sin(seed_value * 12.9898 + 78.233) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
