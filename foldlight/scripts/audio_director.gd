class_name FoldlightAudioDirector
extends Node

signal sfx_requested(sound_name: StringName, pitch: float, volume_db: float)

## Self-contained adaptive score and pooled one-shot synthesis.
## No imported placeholders: every sound is generated once at startup.

const MIX_RATE: float = 44100.0
const POOL_SIZE: int = 12
const IMPACT_TOKEN_LIMIT: float = 4.0
const IMPACT_TOKEN_REFILL: float = 18.0
const IMPACT_GAPS: Dictionary = {&"weapon": 0.065, &"return": 0.085, &"break": 0.10}

var _music_player: AudioStreamPlayer
var _music_playback: AudioStreamGeneratorPlayback
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx: Dictionary = {}
var _pool_cursor: int = 0
var _sample_clock: int = 0
var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _muted: bool = false
var _impact_tokens: float = IMPACT_TOKEN_LIMIT
var _impact_cooldowns: Dictionary = {}
var _hurt_focus_remaining: float = 0.0

const CHORDS: Array[Array] = [
	[45, 52, 57, 61], # A add9
	[41, 48, 52, 57], # F maj7
	[48, 55, 59, 64], # C maj7
	[43, 50, 57, 59], # G add9
]
const ARP_ORDER: Array[int] = [0, 2, 1, 3, 2, 1, 3, 1]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name().to_lower() == "headless":
		return
	_build_music_player()
	_build_sfx_pool()
	_build_sfx_library()


func _process(delta: float) -> void:
	_impact_tokens = minf(IMPACT_TOKEN_LIMIT, _impact_tokens + maxf(0.0, delta) * IMPACT_TOKEN_REFILL)
	_hurt_focus_remaining = maxf(0.0, _hurt_focus_remaining - delta)
	for kind in _impact_cooldowns:
		_impact_cooldowns[kind] = maxf(0.0, float(_impact_cooldowns[kind]) - delta)
	_intensity = move_toward(_intensity, _target_intensity, delta * 0.32)
	_fill_music_buffer()


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
	_music_playback = null
	if is_instance_valid(_music_player):
		_music_player.stream = null
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
		for voice in _sfx_players:
			if voice.playing and int(voice.get_meta(&"sfx_priority", 0)) < 3:
				voice.volume_db -= 6.0
	var priority := _sound_priority(sound_name)
	var resolved_volume := volume_db - (6.0 if _hurt_focus_remaining > 0.0 and priority < 3 else 0.0)
	var resolved_pitch := clampf(pitch, 0.55, 1.8)
	if not _sfx.has(sound_name):
		# Headless simulation still exposes accepted cues to integration tests.
		if DisplayServer.get_name().to_lower() == "headless":
			sfx_requested.emit(sound_name, resolved_pitch, resolved_volume)
		return
	var selected: AudioStreamPlayer
	var lowest_priority := 4
	for index in _sfx_players.size():
		var voice := _sfx_players[(_pool_cursor + index) % _sfx_players.size()]
		if not voice.playing:
			selected = voice
			break
		var voice_priority := int(voice.get_meta(&"sfx_priority", 0))
		if voice_priority <= priority and voice_priority < lowest_priority:
			selected = voice
			lowest_priority = voice_priority
	if selected == null:
		return
	_pool_cursor = (_pool_cursor + 1) % _sfx_players.size()
	selected.stop()
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
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "GeneratedMusic"
	_music_player.bus = &"Music"
	if OS.has_feature("web"):
		# Web's default Sample backend cannot consume AudioStreamGenerator.
		# Only the adaptive score needs Stream; pooled SFX keep Sample latency.
		_music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_music_player)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.32
	_music_player.stream = generator
	_music_player.play()
	_music_playback = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback


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


func _build_sfx_library() -> void:
	var names: Array[StringName] = [
		&"start", &"fold", &"capture", &"release", &"empty",
		&"hit", &"hurt", &"kill", &"act", &"boss", &"victory", &"ui",
		&"paper_hit", &"return_hit", &"paper_break",
	]
	for sound_name in names:
		_sfx[sound_name] = _synthesize_sfx(sound_name)


func _fill_music_buffer() -> void:
	if not is_instance_valid(_music_playback):
		return
	var frames := _music_playback.get_frames_available()
	for frame_index in frames:
		var time := float(_sample_clock + frame_index) / MIX_RATE
		var beat := time * 1.24
		var chord_index := int(floor(beat / 8.0)) % CHORDS.size()
		var chord: Array = CHORDS[chord_index]
		var bar_phase := fmod(beat, 8.0) / 8.0
		var breath := 0.72 + 0.28 * sin(bar_phase * TAU - PI * 0.5)

		var pad := 0.0
		for note_index in chord.size():
			var note: int = chord[note_index]
			var frequency := _midi_to_hz(note)
			var detune := 1.0 + (float(note_index) - 1.5) * 0.0017
			pad += sin(TAU * frequency * detune * time + float(note_index) * 0.7) * (0.12 / float(note_index + 1))
			pad += sin(TAU * frequency * 0.5 * time + float(note_index)) * 0.025

		var arp_step := int(floor(beat * 2.0))
		var arp_note: int = chord[ARP_ORDER[arp_step % ARP_ORDER.size()]] + 12
		var arp_phase := fmod(beat * 2.0, 1.0)
		var arp_env := pow(1.0 - arp_phase, 3.4)
		var arp_freq := _midi_to_hz(arp_note)
		var arp := sin(TAU * arp_freq * time) * arp_env * (0.045 + _intensity * 0.055)
		arp += sin(TAU * arp_freq * 2.01 * time) * arp_env * 0.012

		var pulse_phase := fmod(beat, 1.0)
		var pulse_env := exp(-pulse_phase * 12.0)
		var pulse := sin(TAU * (55.0 + 20.0 * (1.0 - pulse_phase)) * time) * pulse_env * _intensity * 0.075
		var shimmer := sin(TAU * (880.0 + sin(time * 0.17) * 26.0) * time) * 0.004 * breath

		var mono := (pad * breath + arp + pulse + shimmer) * 0.58
		var width := sin(time * 0.21) * 0.035 + sin(time * 0.071) * 0.018
		_music_playback.push_frame(Vector2(mono * (1.0 - width), mono * (1.0 + width)))
	_sample_clock += frames


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
	for i in frame_count:
		var t := float(i) / MIX_RATE
		var u := float(i) / float(maxi(1, frame_count - 1))
		var sample := _sfx_sample(sound_name, t, u)
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
			return sin(TAU * _midi_to_hz(note) * t) * pow(1.0 - local_u, 1.8) * 0.42
		&"fold":
			var frequency := lerpf(210.0, 540.0, u)
			return (sin(TAU * frequency * t) + sin(TAU * frequency * 2.03 * t) * 0.2) * env * 0.34
		&"capture":
			var frequency := lerpf(520.0, 1080.0, u)
			return sin(TAU * frequency * t) * env * 0.32 + sin(TAU * frequency * 1.5 * t) * env * 0.1
		&"release":
			var frequency := lerpf(260.0, 920.0, sqrt(u))
			return (sin(TAU * frequency * t) + sin(TAU * frequency * 1.498 * t) * 0.35) * env * 0.42
		&"empty":
			return sin(TAU * lerpf(240.0, 130.0, u) * t) * env * 0.22
		&"hit":
			var noise := _noise(float(_sample_clock) + t * 12000.0)
			return (sin(TAU * 170.0 * t) * 0.55 + noise * 0.45) * env * 0.38
		&"hurt":
			var noise := _noise(t * 18000.0)
			return (sin(TAU * lerpf(150.0, 62.0, u) * t) * 0.7 + noise * 0.3) * env * 0.48
		&"kill":
			var frequency := lerpf(180.0, 860.0, u)
			return (sin(TAU * frequency * t) * 0.55 + sin(TAU * frequency * 2.0 * t) * 0.16) * env * 0.42
		&"act":
			return (sin(TAU * 110.0 * t) * 0.35 + sin(TAU * 220.0 * t) * 0.18 + sin(TAU * 440.0 * t) * 0.08) * sin(PI * u) * 0.5
		&"boss":
			var rumble := sin(TAU * lerpf(54.0, 39.0, u) * t)
			return (rumble * 0.58 + sin(TAU * 81.0 * t) * 0.2) * sin(PI * u) * 0.65
		&"victory":
			var slot := mini(7, int(u * 8.0))
			var notes: Array[int] = [57, 61, 64, 69, 64, 68, 71, 76]
			var local_u := fmod(u * 8.0, 1.0)
			return (sin(TAU * _midi_to_hz(notes[slot]) * t) + sin(TAU * _midi_to_hz(notes[slot] - 12) * t) * 0.25) * pow(1.0 - local_u, 1.4) * 0.36
		&"ui":
			return sin(TAU * 720.0 * t) * env * 0.23
		_:
			return 0.0


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
