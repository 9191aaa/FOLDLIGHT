extends SceneTree

var failures: Array[String] = []
var cues: Array[StringName] = []
var pcm: Dictionary = {}
var music_mix := PackedVector2Array()
var burst_events: Array[Dictionary] = []
var burst_time: float = 0.0
var output_rate: float = 44100.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio := root.get_node("AudioDirector") as FoldlightAudioDirector
	audio.set_process(false)
	output_rate = AudioServer.get_mix_rate()
	if audio._sfx_players.is_empty():
		audio._build_sfx_pool()
	if audio._sfx.is_empty():
		audio._build_sfx_library()
	if not is_instance_valid(audio._music_player):
		audio._build_music_player()
	audio.sfx_requested.connect(_record_cue)
	_test_pcm(audio)
	_test_music(audio)
	_test_dense_mix(audio)
	_test_voice_pool(audio)
	_test_shutdown(audio)
	audio.sfx_requested.disconnect(_record_cue)
	# Let stopped playback handles leave the audio server before exiting.
	await process_frame
	await process_frame
	await create_timer(0.20).timeout
	print("FOLDLIGHT_AUDIO_QUALITY: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_pcm(audio: FoldlightAudioDirector) -> void:
	check(audio._sfx.size() == 15, "all gameplay cues retain their generated audio")
	for sound_name: StringName in audio._sfx:
		var stream: AudioStreamWAV = audio._sfx[sound_name]
		var bytes := stream.data
		var samples := PackedVector2Array()
		var peak := 0.0
		var step_peak := 0.0
		var previous := Vector2.ZERO
		for offset in range(0, bytes.size(), 4):
			var frame := Vector2(float(bytes.decode_s16(offset)), float(bytes.decode_s16(offset + 2))) / 32767.0
			samples.append(frame)
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			step_peak = maxf(step_peak, maxf(absf(frame.x - previous.x), absf(frame.y - previous.y)))
			previous = frame
		pcm[sound_name] = samples
		check(samples[0] == Vector2.ZERO and samples[-1] == Vector2.ZERO, "%s starts and ends at digital silence" % sound_name)
		check(peak > 0.015 and peak < 0.80, "%s retains an audible signal with sample headroom" % sound_name)
		if sound_name in [&"paper_hit", &"return_hit", &"paper_break", &"hit", &"hurt"]:
			check(step_peak < 0.18, "%s filters sharp paper-noise sample jumps" % sound_name)
		if sound_name in [&"start", &"victory"]:
			var divisions := 3 if sound_name == &"start" else 8
			var boundary_peak := 0.0
			for boundary in range(1, divisions):
				var point := int(round(float(samples.size() - 1) * float(boundary) / float(divisions)))
				for nearby in range(point - 2, point + 3):
					var frame: Vector2 = samples[nearby]
					boundary_peak = maxf(boundary_peak, maxf(absf(frame.x), absf(frame.y)))
			check(boundary_peak < 0.004, "%s note changes start softly instead of resetting to a loud arbitrary phase" % sound_name)
		print("PCM %s peak=%.5f max_adjacent_step=%.5f" % [sound_name, peak, step_peak])


func _test_music(audio: FoldlightAudioDirector) -> void:
	var base := audio._music_player.stream as AudioStreamOggVorbis
	var energy := audio._music_energy_player.stream as AudioStreamOggVorbis
	check(base != null and energy != null, "both music layers use pre-rendered browser-compatible audio")
	if base == null or energy == null:
		return
	check(base.loop and energy.loop and is_zero_approx(base.loop_offset) and is_zero_approx(energy.loop_offset), "both music layers loop from the same origin")
	check(base.get_length() > 20.0 and absf(base.get_length() - energy.get_length()) < 1.0 / output_rate, "the adaptive layers share a complete equal-length musical cycle")
	check(audio._music_player.playing and audio._music_energy_player.playing, "both music layers keep their playback clocks running even at zero energy")
	audio.set_intensity(1.0)
	audio._process(0.5)
	check(audio._music_energy_player.volume_linear > 0.0 and audio._music_energy_player.volume_linear < 1.0 and audio._music_player.playing, "combat intensity fades the added layer without restarting the base")
	audio.set_intensity(0.0)
	audio._process(1.0)
	check(is_zero_approx(audio._music_energy_player.volume_linear) and audio._music_energy_player.playing, "quiet intensity mutes the added layer while preserving its loop position")
	var frame_count := int(ceil(base.get_length() * output_rate)) + 32
	var base_pcm := _decode_stream(base, frame_count)
	var energy_pcm := _decode_stream(energy, frame_count)
	check(base_pcm.size() == frame_count and energy_pcm.size() == frame_count, "native decoding crosses the actual Ogg loop without ending either layer")
	if base_pcm.size() != frame_count or energy_pcm.size() != frame_count:
		return
	# Web Sample caches one complete decoded cycle, then AudioBufferSourceNode
	# loops those samples. Check that exact cache join, not only native Ogg wrap.
	var cache_frames := int(base.get_length() * output_rate)
	var base_edge_peak := maxf(maxf(absf(base_pcm[0].x), absf(base_pcm[0].y)), maxf(absf(base_pcm[cache_frames - 1].x), absf(base_pcm[cache_frames - 1].y)))
	var energy_edge_peak := maxf(maxf(absf(energy_pcm[0].x), absf(energy_pcm[0].y)), maxf(absf(energy_pcm[cache_frames - 1].x), absf(energy_pcm[cache_frames - 1].y)))
	check(base_edge_peak < 0.001, "the base Sample cache has quiet endpoints for browser-native looping")
	check(energy_edge_peak < 0.001, "the energy Sample cache has quiet endpoints for browser-native looping")
	print("SAMPLE_CACHE base_edge_peak=%.8f energy_edge_peak=%.8f" % [base_edge_peak, energy_edge_peak])
	var peak := 0.0
	var step_peak := 0.0
	var previous := Vector2.ZERO
	music_mix.resize(frame_count)
	for index in frame_count:
		var mixed := base_pcm[index] + energy_pcm[index]
		music_mix[index] = mixed
		peak = maxf(peak, maxf(absf(mixed.x), absf(mixed.y)))
		step_peak = maxf(step_peak, maxf(absf(mixed.x - previous.x), absf(mixed.y - previous.y)))
		previous = mixed
	check(peak > 0.02 and peak < 0.50, "decoded music layers leave room for combat SFX when fully combined")
	check(step_peak < 0.10, "decoded music has no large sample jumps, including its loop seam")
	print("MUSIC length=%.6f combined_peak=%.5f max_adjacent_step=%.5f" % [base.get_length(), peak, step_peak])


func _test_dense_mix(audio: FoldlightAudioDirector) -> void:
	# Exercise the real cue limiter, then mix its actual PCM at the emitted gains
	# and pitches. This intentionally leaves every user volume at its maximum.
	var emitter := FoldlightAudioDirector.new()
	root.add_child(emitter)
	emitter.set_process(false)
	emitter.sfx_requested.connect(_record_burst)
	for tick in 360:
		burst_time = float(tick) / 60.0
		emitter._process(1.0 / 60.0)
		emitter.play_combat_impact(&"weapon", 1.0)
		if tick % 7 == 0:
			emitter.play_combat_impact(&"return", 1.0)
		if tick % 10 == 0:
			emitter.play_combat_impact(&"break", 1.0)
		if tick % 4 == 0:
			emitter.play_sfx(&"capture", 1.25, -4.0)
		if tick % 90 == 0:
			emitter.play_sfx(&"fold", 1.0, -7.0)
		if tick % 90 == 45:
			emitter.play_sfx(&"release", 1.25, -5.0)
		if tick in [125, 245]:
			emitter.play_sfx(&"hurt", 0.96, -4.0)
	emitter.queue_free()
	var sample_count := int(7.0 * output_rate)
	var mixed := PackedVector2Array()
	mixed.resize(sample_count)
	for index in mini(sample_count, music_mix.size()):
		mixed[index] = music_mix[index]
	for event in burst_events:
		var stream: AudioStreamWAV = audio._sfx[event["sound"]]
		var pitch: float = event["pitch"]
		var gain := db_to_linear(float(event["volume_db"]))
		var playback := stream.instantiate_playback()
		playback.start()
		var decoded := playback.mix_audio(pitch, int(ceil(stream.get_length() / pitch * output_rate)))
		playback.stop()
		var offset := int(float(event["time"]) * output_rate)
		for index in mini(decoded.size(), sample_count - offset):
			mixed[offset + index] += decoded[index] * gain
	var peak := 0.0
	var clipped := 0
	for frame in mixed:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if absf(frame.x) >= 1.0 or absf(frame.y) >= 1.0:
			clipped += 1
	check(burst_events.size() > 150, "the mix probe contains sustained dense capture and confirmed-hit traffic")
	check(clipped == 0 and peak < 0.98, "dense real cue PCM plus full-energy music does not clip at maximum user volume")
	print("DENSE_MIX events=%d peak=%.5f clipped_frames=%d" % [burst_events.size(), peak, clipped])


func _test_voice_pool(audio: FoldlightAudioDirector) -> void:
	audio.reset_combat_feedback()
	cues.clear()
	for index in audio.POOL_SIZE:
		audio.play_sfx(&"victory", 0.55, -8.0)
	var streams: Array[AudioStream] = []
	var gains: Array[float] = []
	for voice in audio._sfx_players:
		streams.append(voice.stream)
		gains.append(voice.volume_db)
	check(cues.size() == audio.POOL_SIZE, "the ordinary voice pool has a fixed simultaneous limit")
	for index in 50:
		audio.play_sfx(&"paper_break", 1.0, -8.0)
		audio.play_sfx(&"capture", 1.0, -4.0)
	check(cues.size() == audio.POOL_SIZE, "a saturated pool drops extra cues instead of hard-restarting equal or weaker voices")
	audio.play_sfx(&"hurt", 0.96, -4.0)
	check(cues.size() == audio.POOL_SIZE + 1 and cues.back() == &"hurt" and audio._hurt_player.playing, "damage still sounds immediately through its reserved voice under full load")
	var unchanged := true
	for index in audio._sfx_players.size():
		var voice := audio._sfx_players[index]
		unchanged = unchanged and voice.playing and voice.stream == streams[index] and is_equal_approx(voice.volume_db, gains[index])
	check(unchanged, "hurt does not truncate or abruptly duck already playing waveforms")
	for index in 50:
		audio.play_sfx(&"hurt", 1.0, -4.0)
	check(cues.size() == audio.POOL_SIZE + 1, "repeated damage requests cannot create unlimited voices or interrupt the active hurt cue")
	check(not audio.play_combat_impact(&"weapon", 1.0), "weak impacts remain suppressed during the hurt emphasis window")
	for voice in audio._sfx_players:
		voice.stop()
	audio._hurt_player.stop()
	audio._process(0.17)
	check(audio.play_combat_impact(&"weapon", 1.0), "ordinary hit feedback resumes after hurt emphasis")


func _test_shutdown(audio: FoldlightAudioDirector) -> void:
	var players: Array[AudioStreamPlayer] = audio._sfx_players.duplicate()
	players.append(audio._hurt_player)
	players.append(audio._music_player)
	players.append(audio._music_energy_player)
	audio.shutdown()
	var silent := true
	for player in players:
		silent = silent and not player.playing and player.stream == null
	check(silent and audio._sfx.is_empty() and audio._sfx_players.is_empty(), "shutdown stops both music layers, hurt and all ordinary voices and releases their streams")
	audio.shutdown()
	check(not audio._music_player.playing and not audio._music_energy_player.playing, "repeated shutdown leaves no revived music")


func _decode_stream(stream: AudioStream, count: int) -> PackedVector2Array:
	var playback := stream.instantiate_playback()
	playback.start()
	var result := playback.mix_audio(1.0, count)
	playback.stop()
	return result


func _record_cue(sound_name: StringName, _pitch: float, _volume: float) -> void:
	cues.append(sound_name)


func _record_burst(sound_name: StringName, pitch: float, volume: float) -> void:
	burst_events.append({"sound": sound_name, "pitch": pitch, "volume_db": volume, "time": burst_time})


func check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
