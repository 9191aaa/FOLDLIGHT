extends SceneTree

## Real native AudioStreamPlayers and imported Ogg assets, without gameplay.
## Only fade progression is stepped; the audio-server playback clocks remain real.
var _failures: Array[String] = []
var _audio: FoldlightAudioDirector


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_audio = root.get_node("AudioDirector") as FoldlightAudioDirector
	_audio.set_process(false)
	if _audio.get_music_state().loaded_themes.is_empty():
		_audio._build_music_player()
	_audio._process(1.0)
	_check(_voices().size() == 4 and _playing_count() == 2, "two fixed native banks begin with only one playing pair")
	_check(_loaded_count() == 2 and _audio.get_music_state().loaded_themes == [&"harbor"], "title loads only its own pair of Ogg assets")
	await create_timer(0.20).timeout
	_check(_audio._music_player.get_playback_position() > 0.0, "the native audio server advances the actual music clock")
	_audio.set_music_context(&"combat", &"paper_reef", 0.7)
	_audio._process(0.40)
	_check(_playing_count() == 4 and _loaded_count() == 4, "a native crossfade contains exactly the outgoing and incoming pairs")
	var audible_base_pairs := 0
	for voice in _voices():
		if voice.name.ends_with("Base") and voice.volume_linear > 0.0:
			audible_base_pairs += 1
	_check(audible_base_pairs == 2, "both real base streams contribute during native crossfade")
	# Menu spam during a fade must replace the pending destination, not create
	# an unbounded player queue or march through every abandoned screen.
	_audio.set_music_context(&"combat", &"inverted_ink_city", 0.6)
	_audio.set_music_context(&"boss", &"nameless_sun_court", 0.8)
	_audio.set_music_context(&"endless", &"nameless_sun_court", 0.55)
	_check(_playing_count() == 4 and _loaded_count() == 4 and _voices().size() == 4, "rapid contexts cannot allocate extra players or decode abandoned themes")
	_audio._process(2.01)
	_check(_playing_count() == 2 and _loaded_count() == 2, "completed crossfade retires the outgoing pair")
	_audio._process(0.01)
	_check(_audio.get_music_state().loaded_themes.has(&"eclipse") and not _audio.get_music_state().loaded_themes.has(&"archive") and not _audio.get_music_state().loaded_themes.has(&"boss"), "the latest requested destination wins after an in-flight transition")
	_audio._process(2.40)
	_check(_playing_count() == 2 and _loaded_count() == 2 and _audio.get_music_state().loaded_themes == [&"eclipse"], "latest destination settles back to two decoded layers")
	await create_timer(0.20).timeout
	var base_player := _audio._music_player
	var energy_player := _audio._music_energy_player
	var base_stream_id := base_player.stream.get_instance_id()
	var energy_stream_id := energy_player.stream.get_instance_id()
	var position_before := base_player.get_playback_position()
	_check(absf(position_before - energy_player.get_playback_position()) < 0.08, "actual base and energy clocks remain aligned")
	for context: StringName in [&"paused", &"reward", &"victory", &"defeat"]:
		_audio.set_music_context(context)
		_audio._process(0.30)
		_check(_audio.get_music_state().theme == &"eclipse" and not _audio.get_music_state().transitioning and base_player.stream.get_instance_id() == base_stream_id and energy_player.stream.get_instance_id() == energy_stream_id, "%s changes gain without replacing the current streams" % context)
	_audio.set_music_context(&"endless", &"nameless_sun_court", 0.55)
	await create_timer(0.16).timeout
	_check(base_player.get_playback_position() > position_before and base_player.playing and energy_player.playing, "quiet overlays and resume preserve the actual advancing phrase")
	var eclipse_position := base_player.get_playback_position()
	_audio.set_music_context(&"route", &"", 0.10)
	_audio._process(2.40)
	_check(base_player.stream == null and energy_player.stream == null and not base_player.playing and not energy_player.playing, "retired score players release both stream resources")
	_audio.set_music_context(&"endless", &"nameless_sun_court", 0.55)
	_audio._process(2.40)
	var resumed_position := _audio._music_player.get_playback_position()
	_check(resumed_position > 0.15 and absf(resumed_position - eclipse_position) < 0.25, "returning to a previous region resumes its saved phrase instead of its first bar")
	# Finish during a transition, the case most likely to leave an incoming
	# native player alive or to restart it from the next process tick.
	_audio.set_music_context(&"boss", &"nameless_sun_court", 0.9)
	_check(_playing_count() == 4, "shutdown scenario includes an incoming playing pair")
	_audio.shutdown()
	_check(_playing_count() == 0 and _loaded_count() == 0 and not _audio.get_music_state().enabled, "shutdown stops all native players and releases all score assets")
	_audio.set_music_context(&"combat", &"paper_reef", 1.0)
	_audio.set_intensity(1.0)
	_audio._process(5.0)
	_audio.shutdown()
	_check(_playing_count() == 0 and _loaded_count() == 0, "late contexts and repeated shutdown cannot revive music")
	await create_timer(0.30).timeout
	print("FOLDLIGHT_MUSIC_PLAYBACK: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _voices() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for child in _audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).bus == &"Music":
			result.append(child as AudioStreamPlayer)
	return result


func _playing_count() -> int:
	var count := 0
	for voice in _voices():
		if voice.playing:
			count += 1
	return count


func _loaded_count() -> int:
	var count := 0
	for voice in _voices():
		if voice.stream != null:
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
