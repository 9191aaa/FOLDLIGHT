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
const MUSIC_BASE: AudioStream = preload("res://assets/audio/paper_sea_base.ogg")
const MUSIC_ENERGY: AudioStream = preload("res://assets/audio/paper_sea_energy.ogg")
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
	_intensity = move_toward(_intensity, _target_intensity, delta * 0.32)
	_music_gain = move_toward(_music_gain, 1.0, delta * 8.0)
	if is_instance_valid(_music_player):
		_music_player.volume_linear = _music_gain
	if is_instance_valid(_music_energy_player):
		_music_energy_player.volume_linear = _intensity * _music_gain


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	for music in [_music_player, _music_energy_player]:
		if is_instance_valid(music):
			music.stop()
			music.stream = null
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
	_target_intensity = clampf(value, 0.0, 1.0)


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
	_music_gain = 0.0
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "GeneratedMusic"
	_music_player.bus = &"Music"
	_music_player.stream = MUSIC_BASE
	_music_player.volume_linear = 0.0
	_music_energy_player = AudioStreamPlayer.new()
	_music_energy_player.name = "MusicEnergy"
	_music_energy_player.bus = &"Music"
	_music_energy_player.stream = MUSIC_ENERGY
	_music_energy_player.volume_linear = 0.0
	if OS.has_feature("web"):
		_music_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		_music_energy_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	add_child(_music_player)
	add_child(_music_energy_player)
	_music_player.play()
	_music_energy_player.play()


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
