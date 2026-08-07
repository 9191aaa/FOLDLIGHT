class_name FoldlightGame
extends Node2D

enum RunMode { TITLE, CAMPAIGN_MAP, PLAYING, BRIEFING, PAUSED, UPGRADE, SETTINGS, ARCHIVE, GAME_OVER, VICTORY }
enum EnemyType { DRIFTER, FAN, WEAVER, RAM, BLOOMER, LEECH, MIRROR, REWINDER, CARVER, BELL, THIEF, MOTH, HERALD, BOSS }
enum MirrorState { SEEK, FOLD, RELEASE }
enum RamState { STALK, TELEGRAPH, CHARGE, RECOVER }
enum RewindState { ROAM, TELEGRAPH, REWIND, RECOVER }
enum TutorialStep { INTRO, MOVE, CAPTURE, RELEASE, PRACTICE, COMPLETE }

const VIEW_SIZE := Vector2(1920.0, 1080.0)
const HOSTILE_CAP: int = 300
const ENEMY_CAP: int = 18
const PARTICLE_CAP: int = 420
const RITUAL_DURATION: float = 72.0
const FIRST_EVENT_TIME: float = 20.0
const SECOND_EVENT_TIME: float = 46.0
const COMBAT_TIDE_COUNT: int = 6
const FINAL_ACT: int = 7
const PAUSE_BROWSE_CODE: Array[StringName] = [&"ui_up", &"ui_up", &"ui_down", &"ui_down", &"ui_left", &"ui_right", &"ui_left", &"ui_right"]
const PATH_HISTORY_BUFFER_SCRIPT := preload("res://scripts/components/path_history_buffer.gd")
const DOCTRINE_LIBRARY: Array[FoldDoctrine] = [
	preload("res://resources/doctrines/wide_crease.tres"),
	preload("res://resources/doctrines/deep_breath.tres"),
	preload("res://resources/doctrines/lantern_pocket.tres"),
	preload("res://resources/doctrines/still_water.tres"),
	preload("res://resources/doctrines/bright_edge.tres"),
	preload("res://resources/doctrines/swift_return.tres"),
	preload("res://resources/doctrines/chain_bloom.tres"),
	preload("res://resources/doctrines/full_moon.tres"),
	preload("res://resources/doctrines/paper_heart.tres"),
	preload("res://resources/doctrines/slipstream.tres"),
	preload("res://resources/doctrines/mercy_blank.tres"),
	preload("res://resources/doctrines/golden_seam.tres"),
	preload("res://resources/doctrines/quiet_horizon.tres"),
	preload("res://resources/doctrines/ocean_fold.tres"),
	preload("res://resources/doctrines/sunward.tres"),
	preload("res://resources/doctrines/starfall.tres"),
	preload("res://resources/doctrines/afterglow.tres"),
	preload("res://resources/doctrines/dawn_vow.tres"),
]
const DOCTRINE_PATHS: Array = [
	[&"wide_crease", &"deep_breath", &"still_water", &"lantern_pocket", &"quiet_horizon", &"ocean_fold"],
	[&"swift_return", &"bright_edge", &"chain_bloom", &"full_moon", &"sunward", &"starfall"],
	[&"slipstream", &"paper_heart", &"mercy_blank", &"golden_seam", &"afterglow", &"dawn_vow"],
]
const PATH_NAMES: Array[String] = ["折域技艺", "返光技艺", "灯身技艺"]
const NEXT_TIDE_THREATS: Array[String] = [
	"", "基础潮线", "横风与墨覆", "回声与逆折域", "汲光与复合减益", "蓄力冲角与赤轮", "四秒回迹与百折混潮", "墨月三相",
]

const ACT_NAMES: Array[String] = ["", "静水", "纸鸢", "回声", "风眼", "赤轮", "倒流", "墨月"]
const ACT_TITLES: Array[String] = ["", "潮之一 · 静水", "潮之二 · 纸鸢", "潮之三 · 回声", "潮之四 · 风眼", "潮之五 · 赤轮", "潮之六 · 倒流", "终潮 · 墨月"]
const ACT_SUBTITLES: Array[String] = [
	"", "移动 · 按住 · 松开", "迎着扇面去折", "追着旋涡的空隙", "夜色也是你的弹药", "看清金线再横移", "四秒之前也会追上你", "把整轮月亮折回来"
]
const ACT_SCENE_TAGS: Array[String] = [
	"", "镜海微澜", "纸鸢横风", "回声花庭", "无灯风眼", "赤轮苇原", "倒流回廊", "墨月裂相"
]
const ACT_OBJECTIVES: Array[String] = [
	"", "收纳直线花瓣，练习返光", "穿过扇面边缘，辨认封钉", "错开环潮，等青环闭合", "保住折息，逐项洗净墨痕", "看清冲线，横移后收下撞墙震波", "不要贪站位，记住自己四秒前的路径", "读月相裂变，折回整片夜潮"
]

const STORY_BEATS: Dictionary = {
	1: {"id": &"c1_departure", "eyebrow": "第一章 · 残灯渡海", "speaker": "引灯人 · 岑", "title": "纸海没有太阳了", "body": "墨月吞走沿岸的名字，只剩未寄出的灯火漂在潮里。你要做的不是躲开它们——是把它们送回去。"},
	3: {"id": &"c1_echo", "eyebrow": "航行记录 · 回声花庭", "speaker": "折灯人 · 你", "title": "每一枚光都有来处", "body": "花庭里的弹幕正在模仿旧日灯讯。收下它们时，你听见整座港口在纸背面呼吸。"},
	5: {"id": &"c1_red_wheel", "eyebrow": "航行记录 · 赤轮苇原", "speaker": "潮使", "title": "潮水开始记住你的路", "body": "它们不再只追逐此刻。冲角会封住去路，而更深处的东西正沿四秒前的折痕倒流。"},
	7: {"id": &"c1_ink_moon", "eyebrow": "第一章 · 终幕", "speaker": "引灯人 · 岑", "title": "把夜色也折回来", "body": "墨月不是天体，是无数未能返航的愿望。折碎它，让第一束天光重新拥有方向。"},
}
const SETTINGS_KEYS: Array[StringName] = [
	&"master_volume", &"music_volume", &"sfx_volume", &"screen_shake",
	&"vibration", &"fullscreen", &"high_contrast",
]

@onready var player: FoldlightPlayer = $Player
@onready var hud: FoldlightHUD = $HUD/Interface
@onready var tip_queue: Node = $TipQueue
@onready var objective_tracker: FoldlightObjectiveTracker = $ObjectiveTracker
@onready var challenge_director: FoldlightChallengeDirector = $ChallengeDirector
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector
@onready var profile_manager: FoldlightProfileManager = get_node("/root/ProfileManager") as FoldlightProfileManager
@onready var rogue_session: FoldlightRogueSessionController = $RogueSession

var mode: RunMode = RunMode.TITLE
var _rogue_mode_active: bool = true
var score: int = 0
var run_time: float = 0.0
var act_time: float = 0.0
var act: int = 1
var combo: int = 0
var combo_timer: float = 0.0
var total_captures: int = 0
var total_kills: int = 0
var rank: String = ""
var doctrine_stacks: Dictionary = {}
var owned_doctrines: Array[Dictionary] = []
var current_mission_index: int = 0
var current_mission: FoldMissionDefinition

var enemies: Array[Dictionary] = []
var hostile_shots: Array[Dictionary] = []
var return_lights: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var ripples: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _ambient_time: float = 0.0
var _spawn_timer: float = 2.0
var _stage_timer: float = 0.0
var _stage_message: String = ""
var _stage_subtitle: String = ""
var _boss_spawned: bool = false
var _herald_active: bool = false
var _pending_act: int = 1
var _ritual_flags: Dictionary = {}
var _ritual_event_kind: int = 0
var _ritual_event_timer: float = 0.0
var _ritual_event_tick: float = 0.0
var _event_message: String = ""
var _event_message_timer: float = 0.0
var _seal_options: Array[FoldDoctrine] = []
var _seal_selected: int = 0
var _chosen_path: int = -1
var _path_step: int = 0
var _return_damage: int = 1
var _return_speed_multiplier: float = 1.0
var _fold_slow_multiplier: float = 1.0
var _chain_bloom: bool = false
var _full_moon: bool = false
var _golden_seam: bool = false
var _mercy_charges: int = 0
var _captures_since_bonus: int = 0
var _run_hits: int = 0
var _profile_recorded: bool = false
var _world_hit_stop: float = 0.0
var _menu_return_mode: RunMode = RunMode.TITLE
var _settings_selected: int = 0
var _next_enemy_id: int = 1
var _shake_amount: float = 0.0
var _shake_offset := Vector2.ZERO
var _capture_sound_cooldown: float = 0.0
var _last_device: StringName = &"keyboard"
var _pause_browse_code_index: int = 0
var _stars: Array[Dictionary] = []
var _fibers: Array[Dictionary] = []
var _lanterns: Array[Dictionary] = []
var _visual_capture_mode: bool = false
var _hostile_outline_points := PackedVector2Array()
var _hostile_outline_colors := PackedColorArray()
var _hostile_core_points := PackedVector2Array()
var _hostile_core_colors := PackedColorArray()
var _particle_line_points := PackedVector2Array()
var _particle_line_colors := PackedColorArray()
var _empty_doctrine_snapshots: Array[Dictionary] = []
var _mirror_tip_seen: bool = false
var _sealed_tip_seen: bool = false
var _briefing_queue: Array[Dictionary] = []
var _briefing_current: Dictionary = {}
var _briefing_return_mode: RunMode = RunMode.PLAYING
var _sanctuary_selected: int = 0
var _last_glimmer_reward: int = 0
var _starfall_mastery: bool = false
var _background_energy: float = 0.0
var _background_pulse: float = 0.0
var _campaign_selected: int = 0
var _mission_result: Dictionary = {}
var _mission_assisted: bool = false
var _checkpoint_seed: int = 0
var _objective_rewarded: bool = false
var _objective_failures: int = 0
var _objective_anchors: Array[Vector2] = []
var _escort_position := Vector2(220.0, 540.0)
var _escort_integrity: float = 1.0
var _last_release_count: int = 8
var _sea_mirror: bool = false
var _ocean_memory: bool = false
var _needle_light: bool = false
var _sun_chain: bool = false
var _walking_lantern: bool = false
var _mercy_fire: bool = false
var _sea_mirror_timer: float = 0.0
var _return_kill_chain: int = 0
var _challenge_active: bool = false
var _challenge_draft_pending: bool = false
var _challenge_drafts: int = 0
var _crease_rebuke: bool = false
var _tutorial_active: bool = false
var _tutorial_step: TutorialStep = TutorialStep.INTRO
var _tutorial_step_time: float = 0.0
var _tutorial_total_time: float = 0.0
var _tutorial_distance: float = 0.0
var _tutorial_last_position := Vector2.ZERO
var _tutorial_release_success: bool = false
var _tutorial_spawn_timer: float = 0.0
var _feedback_kills_pending: int = 0


func _ready() -> void:
	_rng.seed = int(Time.get_ticks_usec())
	current_mission = FoldlightCampaignCatalog.mission_at(0)
	player.fold_started.connect(_on_fold_started)
	player.fold_released.connect(_on_fold_released)
	player.focus_empty.connect(_on_focus_empty)
	player.statuses_cleansed.connect(_on_statuses_cleansed)
	player.feedback_budget.impact_batch_requested.connect(_on_feedback_impact_batch)
	player.feedback_budget.hit_stop_requested.connect(_on_feedback_hit_stop)
	objective_tracker.objective_completed.connect(_on_objective_completed)
	objective_tracker.objective_failed.connect(_on_objective_failed)
	challenge_director.event_started.connect(_on_challenge_event_started)
	challenge_director.draft_requested.connect(_on_challenge_draft_requested)
	challenge_director.tier_changed.connect(_on_challenge_tier_changed)
	_build_background_details()
	player.reset_player()
	player.global_position = Vector2(960.0, 696.0)
	player.scale = Vector2.ONE
	player.visible = true
	audio_director.set_intensity(0.06)
	_present_hud()
	queue_redraw()
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--capture-scene-1"):
		call_deferred("_setup_scene_capture", 1)
	elif user_args.has("--capture-scene-2"):
		call_deferred("_setup_scene_capture", 2)
	elif user_args.has("--capture-scene-3"):
		call_deferred("_setup_scene_capture", 3)
	elif user_args.has("--capture-scene-4"):
		call_deferred("_setup_scene_capture", 4)
	elif user_args.has("--capture-scene-5"):
		call_deferred("_setup_scene_capture", 5)
	elif user_args.has("--capture-scene-6"):
		call_deferred("_setup_scene_capture", 6)
	elif user_args.has("--capture-scene-7"):
		call_deferred("_setup_scene_capture", 7)
	elif user_args.has("--capture-gameplay"):
		call_deferred("_setup_visual_capture")
	elif user_args.has("--capture-briefing"):
		call_deferred("_setup_briefing_capture")
	elif user_args.has("--capture-new-threats"):
		call_deferred("_setup_new_threats_capture")
	elif user_args.has("--capture-upgrade"):
		call_deferred("_setup_upgrade_capture")
	elif user_args.has("--capture-boss"):
		call_deferred("_setup_boss_capture")
	elif user_args.has("--capture-settings"):
		call_deferred("_setup_settings_capture")
	elif user_args.has("--capture-archive"):
		call_deferred("_setup_archive_capture")
	elif user_args.has("--capture-campaign-map"):
		call_deferred("_setup_campaign_map_capture")
	elif user_args.has("--capture-campaign-threats"):
		call_deferred("_setup_campaign_threats_capture")
	elif user_args.has("--capture-campaign-finale"):
		call_deferred("_setup_campaign_finale_capture")
	elif user_args.has("--capture-challenge"):
		call_deferred("_setup_challenge_capture")
	elif user_args.has("--capture-challenge-draft"):
		call_deferred("_setup_challenge_draft_capture")
	elif user_args.has("--capture-tutorial"):
		call_deferred("_setup_tutorial_capture")
	elif user_args.has("--capture-challenge-result"):
		call_deferred("_setup_challenge_result_capture")


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton or absf(event.axis_value) > 0.35:
			_last_device = &"gamepad"
	elif event is InputEventKey and event.pressed:
		_last_device = &"keyboard"
		_track_pause_browse_code(event as InputEventKey)


func _track_pause_browse_code(event: InputEventKey) -> void:
	if event.is_echo() or not event.pressed:
		return
	if not _is_pause_screen_active():
		_pause_browse_code_index = 0
		return
	var direction: StringName = &""
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action):
			direction = action
			break
	if direction == &"":
		return
	if direction == PAUSE_BROWSE_CODE[_pause_browse_code_index]:
		_pause_browse_code_index += 1
	else:
		_pause_browse_code_index = 1 if direction == PAUSE_BROWSE_CODE[0] else 0
	if _pause_browse_code_index >= PAUSE_BROWSE_CODE.size():
		_pause_browse_code_index = 0
		_enable_browse_invincibility()


func _is_pause_screen_active() -> bool:
	if _rogue_mode_active:
		return rogue_session != null and rogue_session.is_paused()
	return mode == RunMode.PAUSED


func _enable_browse_invincibility() -> void:
	player.set_debug_invincible(true)
	if _rogue_mode_active and rogue_session != null:
		rogue_session.set_browse_mode_enabled(true)
	else:
		_show_event("浏览模式已开启", "玩家伤害无效 · 本次启动持续生效")
		hud.flash(Color(0.44, 1.0, 0.82), 0.24)
		audio_director.play_sfx(&"release", 1.18, -4.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"mute_audio") and not event.is_echo():
		audio_director.toggle_mute()
		get_viewport().set_input_as_handled()
		return
	if _rogue_mode_active:
		# The roguelite owns the entire input surface until its explicit
		# "classic campaign" menu signal hands control back. Legacy shortcuts
		# must never tear down a run, especially while a modal reward owns focus.
		if event.is_action_pressed(&"menu_settings") or event.is_action_pressed(&"open_archive") or event.is_action_pressed(&"open_challenge") or event.is_action_pressed(&"open_tutorial"):
			get_viewport().set_input_as_handled()
		return

	if mode == RunMode.BRIEFING and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed(&"fold") or event.is_action_pressed(&"ui_accept"):
			_advance_briefing()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"pause_game") and not event.is_echo():
		if mode == RunMode.PLAYING:
			mode = RunMode.PAUSED
			player.suspend_for_overlay()
			audio_director.set_intensity(0.08)
			audio_director.play_sfx(&"ui")
		elif mode == RunMode.PAUSED:
			mode = RunMode.PLAYING
			player.resume_from_overlay(0.25)
			audio_director.set_intensity(_music_intensity())
			audio_director.play_sfx(&"ui", 1.15)
		elif mode == RunMode.SETTINGS or mode == RunMode.ARCHIVE:
			mode = _menu_return_mode
			audio_director.play_sfx(&"ui", 0.90)
		elif mode == RunMode.CAMPAIGN_MAP:
			mode = RunMode.TITLE
			audio_director.play_sfx(&"ui", 0.90)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"menu_settings") and not event.is_echo():
		if mode == RunMode.GAME_OVER and current_mission != null and not _mission_assisted and int(_mission_result.get("failure_count", 0)) >= 2:
			if profile_manager.enable_campaign_assist(current_mission.mission_id):
				_mission_assisted = true
				_mission_result["assist_enabled"] = true
				audio_director.play_sfx(&"release", 1.12, -2.0)
				hud.flash(Color(0.42, 0.88, 0.78), 0.20)
			get_viewport().set_input_as_handled()
			return
		if mode == RunMode.TITLE or mode == RunMode.CAMPAIGN_MAP or mode == RunMode.PAUSED:
			_menu_return_mode = mode
			mode = RunMode.SETTINGS
			_settings_selected = 0
			audio_director.play_sfx(&"ui", 1.08)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"open_archive") and not event.is_echo():
		if mode == RunMode.TITLE or mode == RunMode.CAMPAIGN_MAP or mode == RunMode.GAME_OVER or mode == RunMode.VICTORY:
			_menu_return_mode = mode
			mode = RunMode.ARCHIVE
			_sanctuary_selected = 0
			audio_director.play_sfx(&"ui", 1.18)
			get_viewport().set_input_as_handled()
			return

	if mode == RunMode.TITLE and event.is_action_pressed(&"open_challenge") and not event.is_echo():
		start_challenge_run()
		get_viewport().set_input_as_handled()
		return

	if mode == RunMode.TITLE and event.is_action_pressed(&"open_tutorial") and not event.is_echo():
		start_tutorial()
		get_viewport().set_input_as_handled()
		return

	if mode == RunMode.ARCHIVE and event.is_pressed() and not event.is_echo():
		var catalog_size := FoldlightProfileManager.META_CATALOG.size()
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			_sanctuary_selected = posmod(_sanctuary_selected - 1, catalog_size)
			audio_director.play_sfx(&"ui", 0.94)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			_sanctuary_selected = posmod(_sanctuary_selected + 1, catalog_size)
			audio_director.play_sfx(&"ui", 1.04)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_sanctuary_selected = posmod(_sanctuary_selected - 3, catalog_size)
			audio_director.play_sfx(&"ui", 0.94)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_sanctuary_selected = posmod(_sanctuary_selected + 3, catalog_size)
			audio_director.play_sfx(&"ui", 1.04)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"fold"):
			var definition: Dictionary = FoldlightProfileManager.META_CATALOG[_sanctuary_selected]
			if profile_manager.purchase_meta_upgrade(StringName(definition["id"])):
				audio_director.play_sfx(&"release", 1.16, -2.0)
				hud.flash(definition.get("accent", Color(1.0, 0.70, 0.29)), 0.18)
			else:
				audio_director.play_sfx(&"empty", 0.86)
			get_viewport().set_input_as_handled()
			return

	if mode == RunMode.SETTINGS and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_settings_selected = posmod(_settings_selected - 1, SETTINGS_KEYS.size())
			audio_director.play_sfx(&"ui", 0.94)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_settings_selected = posmod(_settings_selected + 1, SETTINGS_KEYS.size())
			audio_director.play_sfx(&"ui", 1.04)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			_adjust_setting(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"fold"):
			_adjust_setting(1)
			get_viewport().set_input_as_handled()
			return

	if mode == RunMode.CAMPAIGN_MAP and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			_campaign_selected = posmod(_campaign_selected - 1, FoldlightCampaignCatalog.mission_count())
			audio_director.play_sfx(&"ui", 0.94)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			_campaign_selected = posmod(_campaign_selected + 1, FoldlightCampaignCatalog.mission_count())
			audio_director.play_sfx(&"ui", 1.04)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_campaign_selected = posmod(_campaign_selected - 4, FoldlightCampaignCatalog.mission_count())
			audio_director.play_sfx(&"ui", 0.90)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_campaign_selected = posmod(_campaign_selected + 4, FoldlightCampaignCatalog.mission_count())
			audio_director.play_sfx(&"ui", 1.08)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"fold") or event.is_action_pressed(&"ui_accept"):
			_start_selected_campaign_mission()
			get_viewport().set_input_as_handled()
			return

	if mode == RunMode.UPGRADE and event.is_pressed() and not event.is_echo():
		if _seal_options.is_empty():
			push_error("Technique seal opened without an authored option")
			return
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
			_seal_selected = posmod(_seal_selected - 1, _seal_options.size())
			audio_director.play_sfx(&"ui", 0.92)
			hud.flash(Color(0.30, 0.88, 0.86), 0.035)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
			_seal_selected = posmod(_seal_selected + 1, _seal_options.size())
			audio_director.play_sfx(&"ui", 1.08)
			hud.flash(Color(1.0, 0.70, 0.29), 0.035)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"fold"):
			_apply_selected_doctrine()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"fold") and not event.is_echo():
		if mode == RunMode.TITLE:
			open_campaign_map()
			get_viewport().set_input_as_handled()
		elif mode == RunMode.GAME_OVER:
			if _challenge_active:
				start_challenge_run()
			else:
				_retry_campaign_checkpoint()
			get_viewport().set_input_as_handled()
		elif mode == RunMode.VICTORY:
			open_campaign_map(true)
			get_viewport().set_input_as_handled()


func _adjust_setting(direction: int) -> void:
	var key := SETTINGS_KEYS[_settings_selected]
	var current: Variant = profile_manager.get_setting(key)
	match key:
		&"master_volume", &"music_volume", &"sfx_volume":
			profile_manager.set_setting(key, clampf(float(current) + float(direction) * 0.1, 0.0, 1.0))
		&"screen_shake":
			profile_manager.set_setting(key, clampf(float(current) + float(direction) * 0.25, 0.0, 1.0))
		&"vibration", &"fullscreen", &"high_contrast":
			profile_manager.set_setting(key, not bool(current))
	audio_director.play_sfx(&"ui", 1.12 if direction > 0 else 0.88)


func _enqueue_briefing(data: Dictionary, return_mode: RunMode = RunMode.PLAYING) -> void:
	if data.is_empty() or _visual_capture_mode:
		return
	var entry := data.duplicate(true)
	entry["kind"] = StringName(entry.get("kind", &"stage"))
	entry["accent"] = entry.get("accent", CYAN())
	_briefing_queue.append(entry)
	if not _briefing_current.is_empty():
		return
	if mode != RunMode.BRIEFING:
		_briefing_return_mode = return_mode
	_activate_next_briefing()


func _activate_next_briefing() -> void:
	if _briefing_queue.is_empty():
		_briefing_current.clear()
		mode = _briefing_return_mode
		if mode == RunMode.PLAYING:
			player.resume_from_overlay(0.70)
			audio_director.set_intensity(_music_intensity())
		return
	_briefing_current = _briefing_queue.pop_front()
	mode = RunMode.BRIEFING
	player.suspend_for_overlay()
	audio_director.set_intensity(0.075)
	audio_director.play_sfx(&"ui", 0.92)
	_background_pulse = maxf(_background_pulse, 0.45)


func _advance_briefing(persist: bool = true) -> void:
	if mode != RunMode.BRIEFING:
		return
	var story_id := StringName(_briefing_current.get("story_id", &""))
	if not story_id.is_empty():
		profile_manager.mark_story_seen(story_id, persist)
	var intro_id := StringName(_briefing_current.get("intro_id", &""))
	if not intro_id.is_empty():
		profile_manager.acknowledge_intro(intro_id, persist)
	_briefing_current.clear()
	_activate_next_briefing()


func _queue_story_for_act(stage_index: int) -> void:
	if not STORY_BEATS.has(stage_index):
		return
	var story: Dictionary = STORY_BEATS[stage_index]
	var story_id := StringName(story["id"])
	if profile_manager.has_story_seen(story_id):
		return
	_enqueue_briefing({
		"kind": &"story",
		"story_id": story_id,
		"eyebrow": story["eyebrow"],
		"title": story["title"],
		"body": story["body"],
		"counter": story["speaker"],
		"accent": Color(1.0, 0.70, 0.29),
	}, RunMode.PLAYING)


func _queue_basic_briefings() -> void:
	var basics: Array[Dictionary] = [
		{"intro_id": &"basics:move", "eyebrow": "守灯课 · 一", "title": "先让纸灯活下来", "body": "WASD / 方向键 / 左摇杆移动。你不需要瞄准，返光会自己找到敌人。", "counter": "只管走位 · 一只手就够", "accent": Color(0.30, 0.88, 0.86)},
		{"intro_id": &"basics:fold", "eyebrow": "守灯课 · 二", "title": "把危险收进折域", "body": "按住 空格 / A 展开折域。普通敌弹进入青色折域后，会变成你的弹药。", "counter": "按住不放 · 收到金色花瓣", "accent": Color(0.42, 0.84, 0.92)},
		{"intro_id": &"basics:return", "eyebrow": "守灯课 · 三", "title": "松开，让整片光返航", "body": "松开 空格 / A，所有收纳花瓣会自动追敌。一次收得越多，回击越响。", "counter": "收得越险 · 返得越爽", "accent": Color(1.0, 0.70, 0.29)},
	]
	for basic in basics:
		var intro_id := StringName(basic["intro_id"])
		if profile_manager.has_acknowledged_intro(intro_id):
			continue
		var entry := basic.duplicate(true)
		entry["kind"] = &"stage"
		_enqueue_briefing(entry, RunMode.PLAYING)


func _apply_meta_progression() -> void:
	var lantern_level := profile_manager.get_meta_level(&"lantern_frame")
	var memory_level := profile_manager.get_meta_level(&"wide_memory")
	var reservoir_level := profile_manager.get_meta_level(&"deep_reservoir")
	var edge_level := profile_manager.get_meta_level(&"return_edge")
	_crease_rebuke = profile_manager.get_meta_level(&"crease_rebuke") > 0
	player.max_health += int(lantern_level / 2)
	player.health = player.max_health
	player.fold_radius_multiplier *= 1.0 + float(memory_level) * 0.04
	player.capture_capacity += reservoir_level
	player.focus_regen_multiplier *= 1.0 + float(reservoir_level) * 0.035
	_return_speed_multiplier *= 1.0 + float(edge_level) * 0.045
	if edge_level >= 5:
		_return_damage += 1
	if lantern_level > 0:
		player.grant_invulnerability(0.25 + float(lantern_level) * 0.10)


func _process(delta: float) -> void:
	if _rogue_mode_active:
		return
	_ambient_time += delta * (0.36 if mode == RunMode.BRIEFING else 1.0)
	_background_energy = move_toward(_background_energy, clampf(float(hostile_shots.size()) / 210.0, 0.0, 1.0), delta * 0.32)
	_background_pulse = maxf(0.0, _background_pulse - delta * 0.72)
	if mode == RunMode.PLAYING or mode == RunMode.UPGRADE:
		if _stage_timer > 0.0:
			_stage_timer = maxf(0.0, _stage_timer - delta)
		_capture_sound_cooldown = maxf(0.0, _capture_sound_cooldown - delta)
		_event_message_timer = maxf(0.0, _event_message_timer - delta)
	if mode == RunMode.PLAYING:
		tip_queue.tick(delta)
	_shake_amount = maxf(0.0, _shake_amount - delta * 18.0)
	if _shake_amount > 0.01:
		var shake_scale := float(profile_manager.get_setting(&"screen_shake", 1.0))
		_shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake_amount * shake_scale
	else:
		_shake_offset = Vector2.ZERO
	_present_hud()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _rogue_mode_active:
		return
	if mode != RunMode.PLAYING:
		return
	if _visual_capture_mode:
		return
	if _world_hit_stop > 0.0:
		_world_hit_stop = maxf(0.0, _world_hit_stop - delta)
		return
	run_time += delta
	act_time += delta
	if _tutorial_active:
		_update_tutorial(delta)
		if mode != RunMode.PLAYING:
			return
		_update_enemies(delta)
		_update_hostile_shots(delta)
		_update_return_lights(delta)
		_update_effects(delta)
		audio_director.set_intensity(0.16)
		return
	if _challenge_active:
		challenge_director.tick(delta)
		if mode != RunMode.PLAYING:
			return
		_apply_challenge_runtime(delta)
		_update_challenge_spawning(delta)
		if mode != RunMode.PLAYING:
			return
		_update_enemies(delta)
		if mode != RunMode.PLAYING:
			return
		_update_hostile_shots(delta)
		_update_return_lights(delta)
		_update_effects(delta)
		audio_director.set_intensity(_music_intensity())
		return
	objective_tracker.tick(delta)
	_update_spatial_objective(delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	_sea_mirror_timer = maxf(0.0, _sea_mirror_timer - delta)
	if combo_timer <= 0.0:
		combo = 0
	_update_ritual(delta)
	if mode != RunMode.PLAYING:
		return
	_update_spawning(delta)
	if mode != RunMode.PLAYING:
		return
	_update_enemies(delta)
	if mode != RunMode.PLAYING:
		return
	_update_hostile_shots(delta)
	_update_return_lights(delta)
	_update_effects(delta)
	audio_director.set_intensity(_music_intensity())


func open_campaign_map(advance_after_result: bool = false) -> void:
	_ensure_classic_control()
	mode = RunMode.CAMPAIGN_MAP
	player.suspend_for_overlay()
	player.visible = false
	_briefing_queue.clear()
	_briefing_current.clear()
	_mission_result = {} if not advance_after_result else _mission_result
	var checkpoint := profile_manager.get_active_checkpoint()
	if not checkpoint.is_empty():
		var checkpoint_index := FoldlightCampaignCatalog.index_of(StringName(checkpoint.get("mission_id", &"")))
		if checkpoint_index >= 0:
			_campaign_selected = checkpoint_index
	elif advance_after_result and current_mission != null:
		_campaign_selected = mini(current_mission_index + 1, FoldlightCampaignCatalog.mission_count() - 1)
	else:
		var campaign := profile_manager.get_campaign_snapshot()
		var unlocked: Array = campaign.get("unlocked_missions", ["c1m1"])
		_campaign_selected = maxi(0, unlocked.size() - 1)
	audio_director.set_intensity(0.055)
	audio_director.play_sfx(&"ui", 1.08)
	hud.flash(Color(0.30, 0.88, 0.86), 0.10)


func activate_classic_campaign() -> void:
	_ensure_classic_control()
	open_campaign_map()


func _ensure_classic_control() -> void:
	if not _rogue_mode_active:
		return
	_rogue_mode_active = false
	if rogue_session != null:
		rogue_session.deactivate_for_classic()
	$HUD.show()


func _start_selected_campaign_mission() -> void:
	var mission := FoldlightCampaignCatalog.mission_at(_campaign_selected)
	if mission == null or not profile_manager.is_mission_unlocked(mission.mission_id):
		audio_director.play_sfx(&"empty", 0.82)
		hud.flash(Color(0.86, 0.22, 0.42), 0.08)
		return
	var checkpoint := profile_manager.get_active_checkpoint()
	if StringName(checkpoint.get("mission_id", &"")) != mission.mission_id:
		checkpoint = {}
	start_campaign_mission(_campaign_selected, checkpoint)


func _retry_campaign_checkpoint() -> void:
	var checkpoint := profile_manager.get_active_checkpoint()
	if checkpoint.is_empty():
		start_campaign_mission(current_mission_index)
		return
	var mission_index := FoldlightCampaignCatalog.index_of(StringName(checkpoint.get("mission_id", &"")))
	if mission_index < 0:
		start_campaign_mission(current_mission_index)
		return
	start_campaign_mission(mission_index, checkpoint)


func start_new_run() -> void:
	_ensure_classic_control()
	start_campaign_mission(0)


func start_campaign_mission(mission_index: int, checkpoint: Dictionary = {}) -> void:
	_ensure_classic_control()
	var mission := FoldlightCampaignCatalog.mission_at(mission_index)
	if mission == null:
		push_error("FoldlightGame: unknown campaign mission index %d" % mission_index)
		return
	_challenge_active = false
	_tutorial_active = false
	challenge_director.reset()
	current_mission_index = mission_index
	current_mission = mission
	_reset_mission_runtime(checkpoint)


func start_challenge_run(seed: int = 0) -> void:
	_ensure_classic_control()
	_challenge_active = true
	_tutorial_active = false
	_challenge_draft_pending = false
	_challenge_drafts = 0
	current_mission_index = mini(8, FoldlightCampaignCatalog.mission_count() - 1)
	current_mission = FoldlightCampaignCatalog.mission_at(current_mission_index)
	var resolved_seed := seed if seed != 0 else int(Time.get_ticks_usec())
	challenge_director.start(resolved_seed)
	_reset_mission_runtime({"seed": resolved_seed})
	player.play_bounds = challenge_director.get_arena_bounds().grow(-44.0)
	player.position = challenge_director.get_arena_bounds().get_center()
	player.grant_invulnerability(1.2)
	_show_event("无尽折潮", "地图会逐渐展开 · 事件每轮都不同")
	_stage_message = "挑　战　模　式"
	_stage_subtitle = "撑得越久，纸海越辽阔"
	_stage_timer = 3.5


func start_tutorial() -> void:
	_ensure_classic_control()
	_tutorial_active = true
	_challenge_active = false
	challenge_director.reset()
	current_mission_index = 0
	current_mission = FoldlightCampaignCatalog.mission_at(0)
	_reset_mission_runtime({"seed": 20260727})
	_tutorial_step = TutorialStep.INTRO
	_tutorial_step_time = 0.0
	_tutorial_total_time = 0.0
	_tutorial_distance = 0.0
	_tutorial_last_position = player.position
	_tutorial_release_success = false
	_tutorial_spawn_timer = 0.0
	player.play_bounds = Rect2(260.0, 220.0, 1400.0, 690.0)
	player.position = Vector2(960.0, 660.0)
	player.grant_invulnerability(60.0)
	_stage_message = "三十秒学会折光"
	_stage_subtitle = "移动 · 收纳 · 松开"
	_stage_timer = 3.5


func _reset_mission_runtime(checkpoint: Dictionary = {}) -> void:
	mode = RunMode.PLAYING
	score = 0
	run_time = 0.0
	act_time = 0.0
	act = 1
	combo = 0
	combo_timer = 0.0
	total_captures = 0
	total_kills = 0
	rank = ""
	doctrine_stacks.clear()
	owned_doctrines.clear()
	_spawn_timer = 2.8
	_boss_spawned = false
	_herald_active = false
	_pending_act = 1
	_ritual_flags.clear()
	_ritual_event_kind = 0
	_ritual_event_timer = 0.0
	_event_message = ""
	_event_message_timer = 0.0
	_seal_options.clear()
	_seal_selected = 0
	_chosen_path = -1
	_path_step = 0
	_return_damage = 1
	_return_speed_multiplier = 1.0
	_fold_slow_multiplier = 1.0
	_chain_bloom = false
	_full_moon = false
	_golden_seam = false
	_starfall_mastery = false
	_sea_mirror = false
	_ocean_memory = false
	_needle_light = false
	_sun_chain = false
	_walking_lantern = false
	_mercy_fire = false
	_sea_mirror_timer = 0.0
	_return_kill_chain = 0
	_mercy_charges = 0
	_captures_since_bonus = 0
	_run_hits = 0
	_profile_recorded = false
	_world_hit_stop = 0.0
	_next_enemy_id = 1
	_mirror_tip_seen = false
	_sealed_tip_seen = false
	_briefing_queue.clear()
	_briefing_current.clear()
	_briefing_return_mode = RunMode.PLAYING
	_last_glimmer_reward = 0
	_background_energy = 0.0
	_background_pulse = 0.0
	_mission_result.clear()
	_mission_assisted = profile_manager.is_campaign_assisted(current_mission.mission_id) if current_mission != null else false
	_checkpoint_seed = int(checkpoint.get("seed", Time.get_ticks_usec() + current_mission_index * 7919))
	_rng.seed = _checkpoint_seed
	_objective_rewarded = false
	_objective_failures = int(checkpoint.get("objective_failures", 0))
	tip_queue.reset()
	objective_tracker.reset()
	enemies.clear()
	hostile_shots.clear()
	return_lights.clear()
	particles.clear()
	ripples.clear()
	player.reset_player()
	_apply_meta_progression()
	if _mission_assisted:
		player.max_health += 1
		player.health = player.max_health
	if not checkpoint.is_empty():
		_restore_campaign_checkpoint(checkpoint)
	player.scale = Vector2.ONE
	player.visible = true
	player.set_play_enabled(true)
	if _tutorial_active or _challenge_active:
		_briefing_queue.clear()
		_briefing_current.clear()
		objective_tracker.reset()
		_spawn_ripple(player.position, CYAN(), 52.0, 340.0, 0.9, 4.0)
		_burst(player.position, Color(0.98, 0.76, 0.35), 34, 220.0)
		audio_director.play_sfx(&"start")
		audio_director.set_intensity(0.18)
		hud.flash(Color(0.72, 1.0, 0.92), 0.34)
		return
	if current_mission_index == 0:
		_queue_basic_briefings()
	if checkpoint.is_empty():
		_queue_mission_opening()
	_commit_campaign_checkpoint()
	if act >= FINAL_ACT:
		_spawn_boss()
	else:
		_show_stage(act)
		_begin_tide_objective()
	_spawn_ripple(player.position, CYAN(), 52.0, 340.0, 0.9, 4.0)
	_burst(player.position, Color(0.98, 0.76, 0.35), 34, 220.0)
	audio_director.play_sfx(&"start")
	audio_director.set_intensity(0.18)
	hud.flash(Color(0.72, 1.0, 0.92), 0.34)


func _queue_mission_opening() -> void:
	if current_mission == null or current_mission.opening_title.is_empty():
		return
	var story_id := StringName("mission:%s:opening" % current_mission.mission_id)
	if profile_manager.has_story_seen(story_id):
		return
	_enqueue_briefing({
		"kind": &"story",
		"story_id": story_id,
		"eyebrow": "%s / %s" % [current_mission.chapter_title, current_mission.location],
		"title": current_mission.opening_title,
		"body": current_mission.opening_body,
		"counter": current_mission.opening_speaker,
		"accent": current_mission.accent,
	}, RunMode.PLAYING)


func _restore_campaign_checkpoint(checkpoint: Dictionary) -> void:
	act = clampi(int(checkpoint.get("tide", 1)), 1, FINAL_ACT)
	run_time = maxf(0.0, float(checkpoint.get("run_time", 0.0)))
	score = maxi(0, int(checkpoint.get("score", 0)))
	total_captures = maxi(0, int(checkpoint.get("captures", 0)))
	total_kills = maxi(0, int(checkpoint.get("kills", 0)))
	_run_hits = maxi(0, int(checkpoint.get("hits", 0)))
	_chosen_path = clampi(int(checkpoint.get("chosen_path", -1)), -1, DOCTRINE_PATHS.size() - 1)
	_path_step = clampi(int(checkpoint.get("path_step", 0)), 0, 6)
	_mercy_charges = maxi(0, int(checkpoint.get("mercy_charges", 0)))
	var saved_stacks: Dictionary = checkpoint.get("doctrine_stacks", {})
	var doctrine_ids: Array = checkpoint.get("owned_doctrine_ids", [])
	for doctrine_value in doctrine_ids:
		var doctrine_id := StringName(doctrine_value)
		var doctrine := _doctrine_by_id(doctrine_id)
		if doctrine == null:
			continue
		var key := String(doctrine_id)
		var stacks := maxi(1, int(saved_stacks.get(key, 1)))
		doctrine_stacks[key] = stacks
		_apply_doctrine_effect(key, true)
		owned_doctrines.append(doctrine.to_snapshot(stacks))
	_refresh_build_synergies(true)
	player.health = clampi(int(checkpoint.get("health", player.health)), 1, player.max_health)
	player.focus = clampf(float(checkpoint.get("focus", 1.0)), 0.05, 1.0)
	player.captured = clampi(int(checkpoint.get("captured_light", 0)), 0, player.get_capture_capacity())
	player.position = Vector2(960.0, 696.0)
	_checkpoint_seed = int(checkpoint.get("seed", _checkpoint_seed))
	_rng.seed = _checkpoint_seed


func _campaign_checkpoint_snapshot() -> Dictionary:
	var doctrine_ids: Array[String] = []
	for doctrine in owned_doctrines:
		doctrine_ids.append(String(doctrine.get("id", "")))
	return {
		"version": 1,
		"campaign_id": String(FoldlightCampaignCatalog.CAMPAIGN_ID),
		"content_revision": FoldlightCampaignCatalog.CONTENT_REVISION,
		"mission_id": String(current_mission.mission_id),
		"mission_revision": current_mission.revision,
		"tide": act,
		"seed": _checkpoint_seed,
		"run_time": run_time,
		"health": player.health,
		"focus": player.focus,
		"captured_light": player.captured,
		"score": score,
		"captures": total_captures,
		"kills": total_kills,
		"hits": _run_hits,
		"chosen_path": _chosen_path,
		"path_step": _path_step,
		"owned_doctrine_ids": doctrine_ids,
		"doctrine_stacks": doctrine_stacks.duplicate(true),
		"mercy_charges": _mercy_charges,
		"objective_failures": _objective_failures,
	}


func _commit_campaign_checkpoint() -> bool:
	if current_mission == null or _visual_capture_mode or _challenge_active or _tutorial_active:
		return true
	_checkpoint_seed = absi(hash("%s:%d:%d:%d" % [current_mission.mission_id, act, _path_step, int(run_time)])) + 1
	return profile_manager.commit_campaign_checkpoint(_campaign_checkpoint_snapshot())


func _current_arena_bounds() -> Rect2:
	if _challenge_active:
		return challenge_director.get_arena_bounds()
	if _tutorial_active:
		return Rect2(216.0, 176.0, 1488.0, 778.0)
	return Rect2(76.0, 122.0, 1768.0, 840.0)


func _apply_challenge_runtime(_delta: float) -> void:
	act = clampi(challenge_director.tier, 1, 6)
	player.play_bounds = challenge_director.get_arena_bounds().grow(-44.0)
	player.temporary_fold_radius_multiplier = challenge_director.get_fold_radius_scale()


func _update_challenge_spawning(delta: float) -> void:
	_spawn_timer -= delta
	var challenge_cap := mini(ENEMY_CAP, 7 + challenge_director.tier)
	if _spawn_timer > 0.0 or enemies.size() >= challenge_cap:
		return
	var interval := maxf(0.52, 1.95 / (1.0 + float(challenge_director.tier - 1) * 0.115))
	_spawn_timer = interval * _rng.randf_range(0.78, 1.18)
	var roster: Array[EnemyType] = [EnemyType.DRIFTER]
	if challenge_director.tier >= 2:
		roster.append_array([EnemyType.FAN, EnemyType.WEAVER])
	if challenge_director.tier >= 3:
		roster.append_array([EnemyType.BLOOMER, EnemyType.LEECH])
	if challenge_director.tier >= 4:
		roster.append_array([EnemyType.RAM, EnemyType.MIRROR])
	if challenge_director.tier >= 5:
		roster.append_array([EnemyType.CARVER, EnemyType.BELL])
	if challenge_director.tier >= 6:
		roster.append_array([EnemyType.REWINDER, EnemyType.MOTH])
	if challenge_director.tier >= 8:
		roster.append(EnemyType.THIEF)
	var chosen := roster[_rng.randi_range(0, roster.size() - 1)]
	var elite_chance := minf(0.30, 0.025 + float(challenge_director.tier - 1) * 0.018)
	_spawn_enemy(chosen, _active_elite_count() < 2 and _rng.randf() < elite_chance)


func _on_challenge_tier_changed(tier: int) -> void:
	if not _challenge_active:
		return
	_show_event("潮压提升 · %02d" % tier, "敌群更快，精英出现率上升")
	_stage_message = "潮　压　%02d" % tier
	_stage_subtitle = "纸海仍在向外展开"
	_stage_timer = 2.8
	player.focus = minf(1.0, player.focus + 0.18)


func _on_challenge_event_started(event: Dictionary) -> void:
	if not _challenge_active:
		return
	var title := str(event.get("title", "潮汐异变"))
	var detail := str(event.get("detail", "纸海改变了流向"))
	_show_event(title, detail)
	var accent: Color = event.get("accent", CYAN())
	var event_id := StringName(event.get("id", &""))
	match event_id:
		&"lantern_rain", &"golden_cache":
			_spawn_challenge_capture_ring(18 if event_id == &"lantern_rain" else 12)
			if event_id == &"golden_cache":
				score += 1200 + challenge_director.tier * 120
		&"clear_sky":
			var remove_count := hostile_shots.size() / 2
			for remove_index in remove_count:
				if hostile_shots.is_empty():
					break
				hostile_shots.remove_at(hostile_shots.size() - 1)
			score += remove_count * 18
		&"dawn_breath":
			player.health = mini(player.max_health, player.health + 1)
			player.focus = 1.0
		&"black_squall":
			_spawn_challenge_edge_storm(false, 22)
		&"elite_hunt":
			_spawn_enemy(EnemyType.RAM if challenge_director.tier >= 4 else EnemyType.FAN, true)
			_spawn_enemy(EnemyType.WEAVER if challenge_director.tier < 6 else EnemyType.REWINDER, true)
		&"sealed_storm":
			_spawn_challenge_edge_storm(true, 14)
		_: pass
	_spawn_ripple(player.position, accent, 42.0, 420.0, 0.72, 5.0)
	hud.flash(accent, 0.16)


func _spawn_challenge_capture_ring(count: int) -> void:
	for shot_index in count:
		var angle := float(shot_index) * TAU / float(count)
		var origin := player.position + Vector2.from_angle(angle) * 330.0
		_spawn_hostile(origin, angle + PI, 82.0, sin(angle * 3.0) * 0.06, Color(1.0, 0.72, 0.28), 0)


func _spawn_challenge_edge_storm(sealed: bool, count: int) -> void:
	var arena := _current_arena_bounds().grow(-18.0)
	for shot_index in count:
		var side := shot_index % 4
		var ratio := float(shot_index / 4 + 1) / float(int(ceil(float(count) / 4.0)) + 1)
		var origin := Vector2.ZERO
		match side:
			0: origin = Vector2(arena.position.x, lerpf(arena.position.y, arena.end.y, ratio))
			1: origin = Vector2(arena.end.x, lerpf(arena.position.y, arena.end.y, ratio))
			2: origin = Vector2(lerpf(arena.position.x, arena.end.x, ratio), arena.position.y)
			_: origin = Vector2(lerpf(arena.position.x, arena.end.x, ratio), arena.end.y)
		var aim := origin.direction_to(player.position).angle() + _rng.randf_range(-0.13, 0.13)
		if sealed:
			_spawn_sealed_hostile(origin, aim, 172.0)
		else:
			_spawn_hostile(origin, aim, 188.0, _rng.randf_range(-0.08, 0.08), Color(0.88, 0.22, 0.50), 0)


func _on_challenge_draft_requested() -> void:
	if not _challenge_active or mode != RunMode.PLAYING:
		return
	_challenge_draft_pending = true
	mode = RunMode.UPGRADE
	player.cancel_fold()
	player.set_play_enabled(false)
	player.clear_statuses()
	return_lights.clear()
	_seal_options = _build_challenge_draft_options()
	_seal_selected = 0
	audio_director.set_intensity(0.08)
	audio_director.play_sfx(&"act", 1.18)
	hud.flash(Color(1.0, 0.80, 0.44), 0.22)


func _build_challenge_draft_options() -> Array[FoldDoctrine]:
	var pool: Array[FoldDoctrine] = []
	for doctrine in DOCTRINE_LIBRARY:
		var stacks := int(doctrine_stacks.get(String(doctrine.doctrine_id), 0))
		if stacks < doctrine.max_stacks:
			pool.append(doctrine)
	if pool.size() < 3:
		pool.assign(DOCTRINE_LIBRARY)
	var options: Array[FoldDoctrine] = []
	while options.size() < 3 and not pool.is_empty():
		var index := _rng.randi_range(0, pool.size() - 1)
		options.append(pool[index])
		pool.remove_at(index)
	return options


func _update_tutorial(delta: float) -> void:
	_tutorial_total_time += delta
	_tutorial_step_time += delta
	player.grant_invulnerability(1.0)
	_tutorial_distance += player.position.distance_to(_tutorial_last_position)
	_tutorial_last_position = player.position
	match _tutorial_step:
		TutorialStep.INTRO:
			if _tutorial_step_time >= 3.0:
				_advance_tutorial_step(TutorialStep.MOVE)
		TutorialStep.MOVE:
			if _tutorial_distance >= 180.0:
				_advance_tutorial_step(TutorialStep.CAPTURE)
		TutorialStep.CAPTURE:
			_tutorial_spawn_timer -= delta
			if _tutorial_spawn_timer <= 0.0:
				_tutorial_spawn_timer = 0.52
				var angle := _rng.randf_range(0.0, TAU)
				var origin := player.position + Vector2.from_angle(angle) * 285.0
				_spawn_hostile(origin, angle + PI, 82.0, sin(angle) * 0.04, Color(0.82, 0.32, 0.72), 0)
			if player.captured >= 3:
				_advance_tutorial_step(TutorialStep.RELEASE)
		TutorialStep.RELEASE:
			if enemies.is_empty():
				_spawn_enemy(EnemyType.DRIFTER, false)
				enemies[-1]["position"] = player.position + Vector2(0.0, -260.0)
				enemies[-1]["shoot"] = 99.0
			if _tutorial_release_success:
				_advance_tutorial_step(TutorialStep.PRACTICE)
		TutorialStep.PRACTICE:
			_tutorial_spawn_timer -= delta
			if _tutorial_spawn_timer <= 0.0:
				_tutorial_spawn_timer = 1.25
				_spawn_challenge_capture_ring(5)
			if _tutorial_total_time >= 32.0 and _tutorial_step_time >= 6.0:
				_advance_tutorial_step(TutorialStep.COMPLETE)
		TutorialStep.COMPLETE:
			if _tutorial_step_time >= 3.0:
				_finish_tutorial()


func _advance_tutorial_step(next_step: TutorialStep) -> void:
	_tutorial_step = next_step
	_tutorial_step_time = 0.0
	_tutorial_spawn_timer = 0.0
	match next_step:
		TutorialStep.MOVE:
			_show_event("第一折 · 移动", "WASD / 左摇杆，先走一小圈")
		TutorialStep.CAPTURE:
			hostile_shots.clear()
			_show_event("第二折 · 收纳", "按住空格 / A，让紫色花瓣进入青色圆界")
		TutorialStep.RELEASE:
			_show_event("第三折 · 返光", "收下三枚后松开，返光会自动追敌")
		TutorialStep.PRACTICE:
			enemies.clear()
			_show_event("自由练习", "移动、收纳、松开——活下来并打出节奏")
		TutorialStep.COMPLETE:
			hostile_shots.clear()
			enemies.clear()
			_show_event("折光已会", "现在可以去战役，或直接挑战无尽潮")
			_stage_message = "教　程　完　成"
			_stage_subtitle = "一只手，也能把夜色折回来"
			_stage_timer = 3.0
		_: pass


func _finish_tutorial() -> void:
	profile_manager.mark_tutorial_complete()
	_tutorial_active = false
	mode = RunMode.TITLE
	player.cancel_fold()
	player.set_play_enabled(false)
	player.reset_player()
	player.position = Vector2(960.0, 696.0)
	player.scale = Vector2.ONE * 1.24
	player.visible = true
	hostile_shots.clear()
	return_lights.clear()
	enemies.clear()
	audio_director.set_intensity(0.06)
	hud.flash(Color(1.0, 0.78, 0.34), 0.32)


func _begin_tide_objective() -> void:
	_objective_rewarded = false
	_objective_anchors.clear()
	_escort_position = Vector2(220.0, 540.0)
	_escort_integrity = 1.0
	if current_mission == null or act >= FINAL_ACT:
		objective_tracker.reset()
		return
	var tide_index := clampi(act - 1, 0, FoldMissionDefinition.TIDE_COUNT - 1)
	var objective_id := StringName(current_mission.tide_value(current_mission.objective_ids, tide_index, &"survive"))
	var objective_target := int(current_mission.tide_value(current_mission.objective_targets, tide_index, 1))
	var objective_label := str(current_mission.tide_value(current_mission.tide_objective_labels, tide_index, "完成本潮"))
	objective_tracker.begin(objective_id, objective_target, objective_label, _current_tide_duration())
	if objective_id == &"beacon_charge" or objective_id == &"cleanse":
		var anchor_count := 3 if objective_target >= 80 else 2
		for anchor_index in anchor_count:
			var angle := -PI * 0.82 + float(anchor_index) * PI * 0.82
			_objective_anchors.append(Vector2(960.0, 560.0) + Vector2.from_angle(angle) * Vector2(520.0, 280.0))
	elif objective_id == &"ram_relay":
		_objective_anchors = [Vector2(140.0, 300.0), Vector2(1780.0, 540.0), Vector2(140.0, 800.0)]


func _update_spatial_objective(delta: float) -> void:
	if objective_tracker.state != FoldlightObjectiveTracker.ObjectiveState.ACTIVE:
		return
	if objective_tracker.objective_id == &"escort":
		var ratio := clampf(act_time / _current_tide_duration(), 0.0, 1.0)
		_escort_position = Vector2(lerpf(220.0, 1700.0, ratio), 570.0 + sin(ratio * TAU * 1.5 + act) * 170.0)
		var protected := player.position.distance_to(_escort_position) <= player.get_fold_radius() + 120.0 and player.folding
		if protected:
			objective_tracker.report(&"escort_tick", delta * 2.8)
			_escort_integrity = minf(1.0, _escort_integrity + delta * 0.08)
		else:
			_escort_integrity = maxf(0.25, _escort_integrity - delta * 0.012)


func _on_objective_completed(snapshot: Dictionary) -> void:
	if _objective_rewarded or mode != RunMode.PLAYING:
		return
	_objective_rewarded = true
	var bonus := 900 + current_mission_index * 90 + act * 80
	score += bonus
	player.focus = minf(1.0, player.focus + 0.22)
	if player.health < player.max_health and act % 2 == 0:
		player.health += 1
	_show_event("航契完成", "+%d · 折息回满一段" % bonus)
	_spawn_ripple(player.position, current_mission.accent, 54.0, 420.0, 0.72, 5.0)
	_burst(player.position, Color(1.0, 0.78, 0.34), 30, 230.0)
	audio_director.play_sfx(&"release", 1.28, -1.0)
	hud.flash(current_mission.accent, 0.16)


func _on_objective_failed(_snapshot: Dictionary) -> void:
	_objective_failures += 1
	_show_event("航契未竟", "航路仍可继续 · 本潮奖励未取得")
	audio_director.play_sfx(&"empty", 0.84)


func _setup_visual_capture() -> void:
	_visual_capture_mode = true
	start_new_run()
	run_time = 126.0
	act = 4
	act_time = 34.0
	_stage_timer = 0.0
	enemies.clear()
	hostile_shots.clear()
	return_lights.clear()
	particles.clear()
	ripples.clear()
	player.position = Vector2(960.0, 640.0)
	player.velocity = Vector2(80.0, -20.0)
	player.folding = true
	player.fold_time = 1.18
	player.focus = 0.72
	player.captured = 11
	_event_message = "封钉　/　黑金十字无法收纳 · 只能避开"
	_event_message_timer = 9.0
	var types: Array[EnemyType] = [EnemyType.DRIFTER, EnemyType.FAN, EnemyType.WEAVER, EnemyType.BLOOMER, EnemyType.LEECH, EnemyType.MIRROR, EnemyType.RAM]
	var positions: Array[Vector2] = [
		Vector2(330, 350), Vector2(650, 240), Vector2(1260, 260),
		Vector2(1580, 405), Vector2(410, 790), Vector2(1430, 800), Vector2(1640, 690)
	]
	for index in types.size():
		_spawn_enemy(types[index], index == 5)
		enemies[-1]["position"] = positions[index]
		enemies[-1]["age"] = 2.4 + float(index) * 0.19
		if types[index] == EnemyType.MIRROR:
			enemies[-1]["mirror_state"] = int(MirrorState.FOLD)
			enemies[-1]["mirror_timer"] = 1.8
			enemies[-1]["stored_light"] = 6
		elif types[index] == EnemyType.WEAVER:
			enemies[-1]["skill_charge"] = 0.58
	tip_queue.reset()
	var capture_enemy_tip := _enemy_tip_data(EnemyType.MIRROR)
	capture_enemy_tip["duration"] = 30.0
	tip_queue.enqueue_once(&"enemy", &"mirror", capture_enemy_tip)
	var capture_effect_tip := _effect_tip_data(&"paper_seal")
	capture_effect_tip["duration"] = 30.0
	tip_queue.enqueue_once(&"effect", &"paper_seal", capture_effect_tip)
	player.apply_status(&"wet_ink", 24.8)
	player.apply_status(&"veiled_fold", 23.6)
	for ring in 2:
		var count := 22 + ring * 8
		var radius := 355.0 + ring * 145.0
		for shot_index in count:
			var angle := float(shot_index) * TAU / float(count) + float(ring) * 0.17
			var origin := player.position + Vector2.from_angle(angle) * radius
			_spawn_hostile(origin, angle + PI * 0.5, 120.0, (0.16 if ring == 0 else -0.1), Color(0.82 - ring * 0.18, 0.24, 0.66 + ring * 0.08), ring)
	var sealed_source := Vector2(1260.0, 260.0)
	var sealed_aim := (player.position - sealed_source).angle()
	var sealed_forward := Vector2.from_angle(sealed_aim)
	var sealed_side := sealed_forward.rotated(PI * 0.5)
	for sealed_index in 5:
		var lane := (float(sealed_index) - 2.0) * 18.0
		var sealed_origin := sealed_source + sealed_forward * (96.0 + sealed_index * 68.0) + sealed_side * lane
		_spawn_sealed_hostile(sealed_origin, sealed_aim, 208.0, -0.025 + sealed_index * 0.0125)
	for light_index in 6:
		var angle := -PI * 0.9 + float(light_index) * 0.32
		return_lights.append({
			"position": player.position + Vector2.from_angle(angle) * (80.0 + light_index * 14.0),
			"velocity": Vector2.from_angle(angle) * 270.0,
			"angle": angle,
			"orbit": 60.0,
			"delay": 0.0,
			"age": 0.6,
			"life": 4.0,
			"power": 1,
		})
	_spawn_ripple(player.position, Color(0.34, 0.91, 0.86), 120.0, 45.0, 1.0, 4.0)
	_burst(player.position + Vector2(50, -25), Color(1.0, 0.74, 0.31), 42, 220.0)
	player.set_play_enabled(false)
	_present_hud()


func _setup_scene_capture(scene_act: int) -> void:
	_setup_visual_capture()
	act = clampi(scene_act, 1, FINAL_ACT)
	_event_message = "%s　/　%s" % [ACT_TITLES[act], ACT_SCENE_TAGS[act]]
	_event_message_timer = 9.0
	_present_hud()


func _setup_briefing_capture() -> void:
	_setup_new_threats_capture()
	var briefing := _enemy_tip_data(EnemyType.REWINDER)
	briefing["kind"] = &"enemy"
	briefing["intro_id"] = &"enemy:rewinder"
	_briefing_current = briefing
	_briefing_queue = [{
		"kind": &"stage", "eyebrow": "航行记录 / 倒流回廊", "title": "潮之六 · 倒流",
		"body": "四秒之前也会追上你", "counter": "看清旧路 · 立刻离轨", "accent": Color(0.96, 0.46, 0.30),
	}]
	_briefing_return_mode = RunMode.PLAYING
	mode = RunMode.BRIEFING
	player.suspend_for_overlay()
	_present_hud()


func _setup_new_threats_capture() -> void:
	_visual_capture_mode = true
	start_new_run()
	act = 6
	act_time = 48.0
	run_time = 512.0
	_stage_timer = 0.0
	enemies.clear()
	hostile_shots.clear()
	return_lights.clear()
	particles.clear()
	ripples.clear()
	player.position = Vector2(960.0, 720.0)
	player.folding = true
	player.fold_time = 1.15
	player.focus = 0.68
	player.captured = 9
	_spawn_enemy(EnemyType.RAM, true)
	enemies[-1]["position"] = Vector2(350.0, 720.0)
	enemies[-1]["age"] = 6.0
	enemies[-1]["ram_state"] = int(RamState.TELEGRAPH)
	enemies[-1]["ram_timer"] = 0.42
	enemies[-1]["charge_direction"] = Vector2.RIGHT
	_spawn_enemy(EnemyType.REWINDER, true)
	enemies[-1]["position"] = Vector2(1450.0, 460.0)
	enemies[-1]["age"] = 6.0
	enemies[-1]["rewind_state"] = int(RewindState.TELEGRAPH)
	enemies[-1]["rewind_timer"] = 0.58
	var old_path := PackedVector2Array()
	for path_index in 28:
		var path_ratio := float(path_index) / 27.0
		old_path.append(Vector2(1510.0 - path_ratio * 720.0, 310.0 + sin(path_ratio * TAU * 1.35) * 170.0 + path_ratio * 210.0))
	enemies[-1]["rewind_path"] = old_path
	enemies[-1]["rewind_index"] = old_path.size() - 1
	for shot_index in 38:
		var angle := float(shot_index) * TAU / 38.0 + 0.18
		var origin := player.position + Vector2.from_angle(angle) * (250.0 + float(shot_index % 3) * 92.0)
		_spawn_hostile(origin, angle + PI * 0.5, 108.0, 0.07 if shot_index % 2 == 0 else -0.07, Color(0.90, 0.28, 0.56), shot_index % 2)
	for light_index in 7:
		var light_angle := -2.7 + float(light_index) * 0.26
		return_lights.append({"position": player.position + Vector2.from_angle(light_angle) * (76.0 + light_index * 13.0), "velocity": Vector2.from_angle(light_angle) * 260.0, "angle": light_angle, "orbit": 58.0, "delay": 0.0, "age": 0.45, "life": 4.0, "power": 1})
	_event_message = "四秒回声　/　橙线是旧路 · 金线是冲线"
	_event_message_timer = 9.0
	_background_energy = 0.88
	_background_pulse = 0.76
	player.set_play_enabled(false)
	_present_hud()


func _setup_upgrade_capture() -> void:
	_visual_capture_mode = true
	start_new_run()
	act = 3
	act_time = 0.0
	_pending_act = 4
	mode = RunMode.UPGRADE
	_stage_timer = 0.0
	player.cancel_fold()
	player.set_play_enabled(false)
	_chosen_path = 1
	_path_step = 2
	_seal_options = _build_seal_options()
	_seal_selected = 0
	owned_doctrines = [_doctrine_by_id(&"swift_return").to_snapshot(1), _doctrine_by_id(&"bright_edge").to_snapshot(1)]
	_present_hud()


func _setup_boss_capture() -> void:
	_visual_capture_mode = true
	start_new_run()
	act = FINAL_ACT
	act_time = 0.0
	_boss_spawned = false
	_spawn_boss()
	_stage_timer = 0.0
	var boss_index := _nearest_enemy_index(Vector2(960.0, 240.0))
	if boss_index >= 0:
		enemies[boss_index]["position"] = Vector2(960.0, 270.0)
		enemies[boss_index]["age"] = 8.0
		enemies[boss_index]["health"] = 44
		enemies[boss_index]["boss_phase"] = 3
	player.position = Vector2(960.0, 750.0)
	player.folding = true
	player.fold_time = 1.35
	player.focus = 0.62
	player.captured = 14
	for ring in 3:
		var count := 22 + ring * 6
		var radius := 235.0 + ring * 115.0
		for shot_index in count:
			var angle := float(shot_index) * TAU / float(count) + ring * 0.19
			var origin := Vector2(960.0, 270.0) + Vector2.from_angle(angle) * radius
			_spawn_hostile(origin, angle + PI * 0.5, 128.0 + ring * 16.0, 0.12 if ring % 2 == 0 else -0.10, Color(0.84, 0.22 + ring * 0.05, 0.58 + ring * 0.05), 1)
	owned_doctrines = [DOCTRINE_LIBRARY[0].to_snapshot(1), DOCTRINE_LIBRARY[4].to_snapshot(1), DOCTRINE_LIBRARY[6].to_snapshot(1), DOCTRINE_LIBRARY[9].to_snapshot(1)]
	_event_message = "墨月开裂 · 3　/　终相：把整轮月亮折回来"
	_event_message_timer = 9.0
	_present_hud()


func _setup_settings_capture() -> void:
	_visual_capture_mode = true
	_menu_return_mode = RunMode.TITLE
	mode = RunMode.SETTINGS
	_settings_selected = 3
	_stage_timer = 0.0
	_present_hud()


func _setup_archive_capture() -> void:
	_visual_capture_mode = true
	_menu_return_mode = RunMode.TITLE
	mode = RunMode.ARCHIVE
	_stage_timer = 0.0
	var preview_profile := profile_manager.profile.duplicate(true)
	preview_profile["best_score"] = maxi(28460, int(preview_profile.get("best_score", 0)))
	preview_profile["best_rank"] = "A"
	preview_profile["total_runs"] = maxi(7, int(preview_profile.get("total_runs", 0)))
	preview_profile["victories"] = maxi(2, int(preview_profile.get("victories", 0)))
	preview_profile["glimmer"] = 13
	preview_profile["highest_tide"] = 6
	preview_profile["chapter_one_complete"] = false
	preview_profile["meta_upgrades"] = {"lantern_frame": 1, "wide_memory": 2, "deep_reservoir": 1, "return_edge": 0, "crease_rebuke": 0}
	preview_profile["discovered_enemies"] = ["drifter", "fan", "weaver", "ram", "bloomer", "leech", "mirror", "rewinder", "herald", "ink_moon"]
	preview_profile["discovered_doctrines"] = ["wide_crease", "deep_breath", "lantern_pocket", "still_water", "bright_edge", "swift_return", "chain_bloom", "full_moon", "paper_heart", "slipstream", "mercy_blank", "golden_seam", "quiet_horizon", "ocean_fold", "sunward", "starfall", "afterglow", "dawn_vow"]
	profile_manager.profile = preview_profile
	_present_hud()


func _setup_challenge_capture() -> void:
	_visual_capture_mode = true
	start_challenge_run(26117)
	challenge_director.elapsed = 238.0
	challenge_director.tier = 6
	challenge_director.events_seen = 7
	challenge_director.current_event = {
		"id": &"crosswind", "title": "折向横风", "detail": "敌弹持续向东偏航",
		"polarity": &"negative", "remaining": 8.4, "accent": Color(0.50, 0.42, 0.92),
	}
	_apply_challenge_runtime(0.0)
	run_time = 238.0
	act_time = 13.0
	score = 28760
	_challenge_drafts = 3
	_stage_timer = 0.0
	enemies.clear()
	hostile_shots.clear()
	return_lights.clear()
	particles.clear()
	ripples.clear()
	var arena := challenge_director.get_arena_bounds()
	player.position = arena.get_center() + Vector2(40.0, 120.0)
	player.folding = true
	player.fold_time = 1.32
	player.focus = 0.64
	player.captured = 12
	for data in [
		[EnemyType.RAM, Vector2(-325.0, 80.0), true],
		[EnemyType.REWINDER, Vector2(350.0, -155.0), true],
		[EnemyType.WEAVER, Vector2(-210.0, -230.0), false],
		[EnemyType.MOTH, Vector2(280.0, 210.0), false],
	]:
		_spawn_enemy(data[0], data[2])
		enemies[-1]["position"] = arena.get_center() + data[1]
		enemies[-1]["age"] = 6.0
	enemies[0]["ram_state"] = int(RamState.CHARGE)
	enemies[0]["charge_direction"] = Vector2.RIGHT
	enemies[0]["velocity"] = Vector2.RIGHT * 840.0
	enemies[1]["rewind_state"] = int(RewindState.TELEGRAPH)
	enemies[1]["rewind_timer"] = 0.55
	var old_path := PackedVector2Array()
	for path_index in 24:
		var ratio := float(path_index) / 23.0
		old_path.append(arena.get_center() + Vector2(380.0 - ratio * 680.0, -180.0 + sin(ratio * TAU) * 150.0))
	enemies[1]["rewind_path"] = old_path
	for shot_index in 46:
		var angle := float(shot_index) * TAU / 46.0 + 0.12
		var origin := player.position + Vector2.from_angle(angle) * (245.0 + float(shot_index % 3) * 72.0)
		_spawn_hostile(origin, angle + PI * 0.5, 126.0, 0.08 if shot_index % 2 == 0 else -0.08, Color(0.82, 0.24, 0.68), shot_index % 2)
	owned_doctrines = [DOCTRINE_LIBRARY[0].to_snapshot(1), DOCTRINE_LIBRARY[4].to_snapshot(1), DOCTRINE_LIBRARY[6].to_snapshot(1)]
	_event_message = "凶潮 · 折向横风　/　沿风向预留半步"
	_event_message_timer = 9.0
	player.set_play_enabled(false)
	_present_hud()


func _setup_challenge_draft_capture() -> void:
	_setup_challenge_capture()
	mode = RunMode.PLAYING
	_on_challenge_draft_requested()
	_present_hud()


func _setup_tutorial_capture() -> void:
	_visual_capture_mode = true
	start_tutorial()
	_tutorial_step = TutorialStep.CAPTURE
	_tutorial_total_time = 14.2
	_tutorial_step_time = 4.0
	_stage_timer = 0.0
	player.position = Vector2(960.0, 650.0)
	player.folding = true
	player.fold_time = 0.96
	player.focus = 0.74
	player.captured = 2
	hostile_shots.clear()
	for shot_index in 16:
		var angle := float(shot_index) * TAU / 16.0
		var origin := player.position + Vector2.from_angle(angle) * (245.0 + float(shot_index % 2) * 70.0)
		_spawn_hostile(origin, angle + PI, 82.0, 0.04 if shot_index % 2 == 0 else -0.04, Color(0.82, 0.32, 0.72), 0)
	_event_message = "第二折 · 收纳　/　让三枚花瓣进入青色圆界"
	_event_message_timer = 9.0
	player.set_play_enabled(false)
	_present_hud()


func _setup_challenge_result_capture() -> void:
	_setup_challenge_capture()
	player.cancel_fold()
	player.set_play_enabled(false)
	mode = RunMode.GAME_OVER
	run_time = 387.0
	score = 68420
	_last_glimmer_reward = 8
	_mission_result = {"challenge": true, "tier": 9, "events": 13, "drafts": 5, "kills": 82}
	_present_hud()


func _setup_campaign_map_capture() -> void:
	_visual_capture_mode = true
	var preview_profile := profile_manager.profile.duplicate(true)
	var campaign: Dictionary = (preview_profile.get("campaign", {}) as Dictionary).duplicate(true)
	var unlocked: Array[String] = []
	var completed: Dictionary = {}
	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		if mission_index <= 7:
			unlocked.append(String(mission.mission_id))
		if mission_index <= 5:
			completed[String(mission.mission_id)] = {
				"rank": ["S", "A", "A", "B", "A", "S"][mission_index],
				"best_time": float(mission.expected_seconds - 18 - mission_index * 3),
			}
	campaign["unlocked_missions"] = unlocked
	campaign["completed"] = completed
	campaign["campaign_seconds"] = 3186.0
	campaign["active_checkpoint"] = {
		"mission_id": "c2m3",
		"tide": 4,
		"run_time": 356.0,
		"health": 5,
		"focus": 0.74,
		"captured_light": 7,
	}
	preview_profile["campaign"] = campaign
	preview_profile["glimmer"] = 24
	profile_manager.profile = preview_profile
	_campaign_selected = 6
	open_campaign_map()
	_present_hud()


func _setup_campaign_threats_capture() -> void:
	_visual_capture_mode = true
	start_campaign_mission(10)
	_briefing_queue.clear()
	_briefing_current.clear()
	mode = RunMode.PLAYING
	act = 5
	act_time = 46.0
	run_time = 514.0
	_stage_timer = 0.0
	enemies.clear()
	hostile_shots.clear()
	return_lights.clear()
	particles.clear()
	ripples.clear()
	player.position = Vector2(960.0, 706.0)
	player.folding = true
	player.fold_time = 1.22
	player.focus = 0.66
	player.captured = 12
	var threat_types: Array[EnemyType] = [EnemyType.CARVER, EnemyType.BELL, EnemyType.THIEF, EnemyType.MOTH]
	var threat_positions: Array[Vector2] = [Vector2(330, 330), Vector2(965, 250), Vector2(1560, 430), Vector2(1480, 790)]
	for threat_index in threat_types.size():
		_spawn_enemy(threat_types[threat_index], threat_index < 2)
		var threat := enemies[-1]
		threat["position"] = threat_positions[threat_index]
		threat["age"] = 7.0 + threat_index
		threat["special"] = 0.32 + threat_index * 0.11
		threat["skill_charge"] = 0.76 if threat_index == 0 else 0.48
		threat["echo_count"] = 12
	for shot_index in 62:
		var shot_angle := float(shot_index) * TAU / 62.0 + float(shot_index % 4) * 0.07
		var shot_radius := 230.0 + float(shot_index % 4) * 92.0
		var shot_origin := player.position + Vector2.from_angle(shot_angle) * shot_radius
		_spawn_hostile(shot_origin, shot_angle + PI * 0.5, 112.0 + float(shot_index % 3) * 18.0, 0.08 if shot_index % 2 == 0 else -0.08, Color(0.72, 0.28, 0.86), shot_index % 3)
	_objective_anchors = [Vector2(470, 660), Vector2(1450, 620), Vector2(960, 390)]
	objective_tracker.begin(&"beacon_charge", 90, "Charge all three lantern beacons", 82.0)
	objective_tracker.report(&"beacon_charge", 58.0)
	_event_message = "HUNDRED-FOLD NIGHT / FOUR THREATS, ONE FOLD"
	_event_message_timer = 9.0
	owned_doctrines = [DOCTRINE_LIBRARY[0].to_snapshot(1), DOCTRINE_LIBRARY[4].to_snapshot(1), DOCTRINE_LIBRARY[6].to_snapshot(1), DOCTRINE_LIBRARY[9].to_snapshot(1)]
	_sea_mirror = true
	_ocean_memory = true
	player.set_play_enabled(false)
	_present_hud()


func _setup_campaign_finale_capture() -> void:
	_visual_capture_mode = true
	start_campaign_mission(11)
	_briefing_queue.clear()
	_briefing_current.clear()
	mode = RunMode.PLAYING
	act = FINAL_ACT
	_stage_timer = 0.0
	enemies.clear()
	hostile_shots.clear()
	_spawn_boss()
	_stage_timer = 0.0
	var boss_index := _nearest_enemy_index(Vector2(960.0, 260.0))
	if boss_index >= 0:
		enemies[boss_index]["position"] = Vector2(960.0, 265.0)
		enemies[boss_index]["age"] = 12.0
		enemies[boss_index]["health"] = int(float(enemies[boss_index]["max_health"]) * 0.34)
		enemies[boss_index]["boss_phase"] = 3
	player.position = Vector2(960.0, 790.0)
	player.folding = true
	player.fold_time = 1.45
	player.focus = 0.58
	player.captured = 16
	_last_release_count = 16
	for ring in 4:
		var shot_count := 18 + ring * 8
		for shot_index in shot_count:
			var angle := float(shot_index) * TAU / float(shot_count) + ring * 0.21
			var radius := 210.0 + ring * 105.0
			var origin := Vector2(960.0, 265.0) + Vector2.from_angle(angle) * radius
			_spawn_hostile(origin, angle + PI * 0.5, 122.0 + ring * 15.0, 0.11 if ring % 2 == 0 else -0.09, current_mission.accent, ring % 3)
	_event_message = "NAMELESS SUN / THIRD PHASE — FOLD THE WHOLE TIDE BACK"
	_event_message_timer = 9.0
	owned_doctrines = [DOCTRINE_LIBRARY[0].to_snapshot(2), DOCTRINE_LIBRARY[4].to_snapshot(2), DOCTRINE_LIBRARY[6].to_snapshot(1), DOCTRINE_LIBRARY[9].to_snapshot(1), DOCTRINE_LIBRARY[13].to_snapshot(1)]
	_sea_mirror = true
	_ocean_memory = true
	_sun_chain = true
	player.set_play_enabled(false)
	_present_hud()


func _update_ritual(delta: float) -> void:
	if act >= FINAL_ACT or _herald_active:
		return
	if act_time >= _current_first_event_time() and not bool(_ritual_flags.get("first", false)):
		_ritual_flags["first"] = true
		_trigger_ritual_event(false)
	if act_time >= _current_second_event_time() and not bool(_ritual_flags.get("second", false)):
		_ritual_flags["second"] = true
		_trigger_ritual_event(true)
	_update_ritual_event(delta)
	if act_time >= _current_tide_duration() and not _herald_active:
		objective_tracker.settle_at_tide_end()
		_spawn_herald()


func _trigger_ritual_event(second: bool) -> void:
	_ritual_event_timer = 9.0 if not second else 7.0
	_ritual_event_tick = 0.0
	if current_mission != null and current_mission_index > 0:
		var pair_text := str(current_mission.tide_value(current_mission.ritual_event_pairs, act - 1, "lamp_rain,tide_seam"))
		var pair := pair_text.split(",", false)
		var event_id := StringName(pair[mini(1 if second else 0, pair.size() - 1)].strip_edges()) if not pair.is_empty() else &"lamp_rain"
		_trigger_authored_ritual_event(event_id)
		audio_director.play_sfx(&"act", 0.84 + float(act) * 0.06)
		hud.flash(current_mission.accent, 0.13)
		return
	_ritual_event_kind = act * 2 - (0 if second else 1)
	match _ritual_event_kind:
		1:
			_show_event("灯雨", "慢弹从天而降 · 这是你的弹药")
		2:
			_show_event("潮缝", "环潮合拢 · 找到缺口或把它折走")
		3:
			_show_event("横风", "弹道向东偏折")
			_queue_effect_tip(&"crosswind")
		4:
			_show_event("墨针", "紫针会墨覆 · 织潮者蓄力时准备躲开封钉")
			_spawn_enemy(EnemyType.WEAVER, true)
		5:
			_show_event("回声庭", "花灯扎根 · 每圈都能成为你的光")
			_spawn_enemy(EnemyType.BLOOMER, true)
			_spawn_enemy(EnemyType.BLOOMER, false)
		6:
			_show_event("逆折域", "青环展开时暂缓返还 · 它会截光并反射")
			_spawn_enemy(EnemyType.MIRROR, true)
			enemies[-1]["mirror_state"] = int(MirrorState.FOLD)
			enemies[-1]["mirror_timer"] = 2.6
			_mirror_tip_seen = true
		7:
			_show_event("风眼", "汲光者施加湿墨 · 返还 6 光即可洗净")
			_spawn_enemy(EnemyType.LEECH, true)
			_spawn_enemy(EnemyType.LEECH, false)
		8:
			_show_event("无灯时刻", "冲角会缚住脚步 · 返还 3 光即可挣脱")
			_queue_effect_tip(&"lights_out")
			_spawn_enemy(EnemyType.RAM, true)
			for ring in 3:
				_fire_ring(Vector2(960.0, 540.0), 16 + ring * 3, 116.0 + ring * 24.0, ring * 0.31, Color(0.64, 0.18, 0.60))
		9:
			_show_event("赤轮冲线", "金线定向后冲角不会转弯 · 横移再反击")
			_spawn_enemy(EnemyType.RAM, true)
			_spawn_enemy(EnemyType.RAM, false)
		10:
			_show_event("苇原震波", "冲角撞岸会炸出整圈可收纳花瓣")
			_spawn_enemy(EnemyType.RAM, true)
			_spawn_enemy(EnemyType.LEECH, true)
		11:
			_show_event("四秒回声", "回痕兽正在记录旧路 · 路径亮起立刻离轨")
			_spawn_enemy(EnemyType.REWINDER, true)
		12:
			_show_event("百折归潮", "现在与四秒之前同时逼近")
			_spawn_enemy(EnemyType.REWINDER, true)
			_spawn_enemy(EnemyType.RAM, true)
			_spawn_enemy(EnemyType.MIRROR, false)
	audio_director.play_sfx(&"act", 0.84 + float(act) * 0.06)
	hud.flash(Color(0.32, 0.86, 0.84), 0.13)


func _trigger_authored_ritual_event(event_id: StringName) -> void:
	match event_id:
		&"lamp_rain", &"petal_rain", &"nameless_dawn":
			_ritual_event_kind = 1
			_show_event("灯雨", "慢弹从纸背落下 · 这是下一轮返光")
			if event_id == &"nameless_dawn":
				_spawn_enemy(EnemyType.MOTH, true)
		&"tide_seam":
			_ritual_event_kind = 2
			_show_event("潮缝", "环潮合拢 · 找到缺口或把它折走")
		&"crosswind":
			_ritual_event_kind = 3
			_show_event("横风", "弹道持续偏折 · 沿风向预留半步")
			_queue_effect_tip(&"crosswind")
		&"paper_seal":
			_ritual_event_kind = 4
			_show_event("墨针", "刻线与封钉同时落下 · 先看预告")
			_spawn_enemy(EnemyType.WEAVER, true)
		&"echo_bloom", &"ink_roots":
			_ritual_event_kind = 5
			_show_event("回声花庭", "整圈慢弹正在扎根 · 靠近一次收下")
			_spawn_enemy(EnemyType.BLOOMER, event_id == &"ink_roots")
		&"return_echo":
			_ritual_event_kind = 6
			_show_event("返光回声", "上一轮释放会再次成为可收纳花瓣")
			_spawn_enemy(EnemyType.MOTH, true)
		&"lights_out", &"black_tide":
			_ritual_event_kind = 8
			_show_event("无灯时刻", "跟随金线 · 保留折息")
			_queue_effect_tip(&"lights_out")
			_spawn_enemy(EnemyType.RAM, true)
		&"red_line":
			_ritual_event_kind = 9
			_show_event("赤轮冲线", "金线锁定后不会转向 · 横移再反击")
			_spawn_enemy(EnemyType.RAM, true)
		&"ram_wave":
			_ritual_event_kind = 10
			_show_event("苇原震波", "冲角撞岸会炸出整圈弹药")
			_spawn_enemy(EnemyType.RAM, true)
		&"rewind_trace":
			_ritual_event_kind = 11
			_show_event("四秒回声", "旧路亮起时立刻离轨")
			_spawn_enemy(EnemyType.REWINDER, true)
		&"carved_lane":
			_ritual_event_kind = 3
			_show_event("刻潮线", "蓝线完成前换边 · 刻线散去后收弹")
			_spawn_enemy(EnemyType.CARVER, true)
		&"bell_pull":
			_ritual_event_kind = 5
			_show_event("引潮钟带", "花瓣将被牵成旋转带")
			_spawn_enemy(EnemyType.BELL, true)
		&"courier":
			_ritual_event_kind = 3
			_show_event("寄灯追函", "先攒返光 · 再截住逃逸名字")
			_spawn_enemy(EnemyType.THIEF, true)
		&"hundred_fold", &"final_mix":
			_ritual_event_kind = 12
			_show_event("百折归潮", "现在、旧路与回声同时逼近")
			_spawn_enemy(EnemyType.REWINDER, true)
			_spawn_enemy(EnemyType.MOTH, false)
			_spawn_enemy(EnemyType.CARVER, false)
		_:
			_ritual_event_kind = 1
			_show_event("灯雨", "慢弹从纸背落下")


func _update_ritual_event(delta: float) -> void:
	if _ritual_event_timer <= 0.0:
		return
	_ritual_event_timer = maxf(0.0, _ritual_event_timer - delta)
	_ritual_event_tick -= delta
	if _ritual_event_tick > 0.0:
		return
	match _ritual_event_kind:
		1:
			_ritual_event_tick = 0.24
			var x := _rng.randf_range(150.0, 1770.0)
			_spawn_hostile(Vector2(x, 130.0), PI * 0.5 + _rng.randf_range(-0.08, 0.08), _rng.randf_range(90.0, 126.0), _rng.randf_range(-0.04, 0.04), Color(0.84, 0.35, 0.65), 1)
		2:
			_ritual_event_tick = 1.55
			_fire_ring(Vector2(960.0, 540.0), 18, 122.0, _ambient_time * 0.24, Color(0.68, 0.26, 0.70))
		3:
			_ritual_event_tick = 0.62
			_spawn_hostile(Vector2(100.0, _rng.randf_range(200.0, 900.0)), _rng.randf_range(-0.12, 0.12), 174.0, 0.10, Color(0.42, 0.39, 0.84), 1)
		5:
			_ritual_event_tick = 2.4
			_fire_ring(Vector2(_rng.randf_range(360.0, 1560.0), _rng.randf_range(280.0, 790.0)), 11, 108.0, _ambient_time, Color(0.54, 0.34, 0.80))
		6:
			_ritual_event_tick = 1.3
			var origin := player.position + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(310.0, 480.0)
			var aim := (player.position - origin).angle()
			for spread in [-0.24, 0.0, 0.24]:
				_spawn_hostile(origin, aim + spread, 146.0, -spread * 0.25, Color(0.67, 0.28, 0.76), 0)
		7:
			_ritual_event_tick = 2.15
			player.add_focus(-0.025)
		8:
			_ritual_event_tick = 1.15
			var edge := Vector2(_rng.randf_range(180.0, 1740.0), 145.0 if _rng.randf() < 0.5 else 935.0)
			for spread in [-0.16, 0.0, 0.16]:
				_spawn_hostile(edge, (player.position - edge).angle() + spread, 188.0, spread * 0.18, Color(0.78, 0.20, 0.57), 0)
		9:
			_ritual_event_tick = 1.85
			var red_origin := Vector2(960.0, 540.0) + Vector2.from_angle(_ambient_time * 0.42) * 360.0
			_fire_ring(red_origin, 8, 128.0, _ambient_time * 0.6, Color(0.90, 0.26, 0.46))
		10:
			_ritual_event_tick = 1.45
			var bank := Vector2(110.0 if _rng.randf() < 0.5 else 1810.0, _rng.randf_range(220.0, 880.0))
			var bank_aim := (player.position - bank).angle()
			for spread in [-0.22, 0.0, 0.22]:
				_spawn_hostile(bank, bank_aim + spread, 178.0, -spread * 0.10, Color(0.88, 0.30, 0.50), 0)
		11:
			_ritual_event_tick = 2.35
			_background_pulse = maxf(_background_pulse, 0.28)
		12:
			_ritual_event_tick = 1.25
			var reverse_origin := Vector2(_rng.randf_range(180.0, 1740.0), _rng.randf_range(160.0, 920.0))
			var reverse_aim := (player.position - reverse_origin).angle()
			for spread in [-0.28, 0.0, 0.28]:
				_spawn_hostile(reverse_origin, reverse_aim + spread, 196.0, spread * 0.22, Color(0.94, 0.34, 0.46), 0)


func _show_event(title: String, subtitle: String) -> void:
	_event_message = "%s　/　%s" % [title, subtitle]
	_event_message_timer = 4.2


func _queue_enemy_tip(enemy_type: int) -> void:
	var data := _enemy_tip_data(enemy_type)
	if data.is_empty():
		return
	var tip_id := StringName(data["id"])
	if not tip_queue.enqueue_once(&"enemy", tip_id, data):
		return
	var intro_id := StringName("enemy:%s" % tip_id)
	if not profile_manager.has_acknowledged_intro(intro_id) and (mode == RunMode.PLAYING or mode == RunMode.BRIEFING):
		var intro := data.duplicate(true)
		intro["kind"] = &"enemy"
		intro["intro_id"] = intro_id
		_enqueue_briefing(intro, RunMode.PLAYING)


func _enemy_tip_data(enemy_type: int) -> Dictionary:
	match enemy_type:
		EnemyType.DRIFTER:
			return {"id": &"drifter", "eyebrow": "潮兽图鉴 01 / 游移", "title": "漂灯", "body": "缓慢追踪并发射直线花瓣", "counter": "保持移动 · 迎面折走", "accent": Color(0.52, 0.84, 0.82), "glyph": enemy_type}
		EnemyType.FAN:
			return {"id": &"fan", "eyebrow": "潮兽图鉴 02 / 扇射", "title": "棱翼", "body": "保持距离，展开五枚扇形花瓣", "counter": "穿过扇缘 · 或迎面收纳", "accent": Color(0.88, 0.36, 0.64), "glyph": enemy_type}
		EnemyType.WEAVER:
			return {"id": &"weaver", "eyebrow": "潮兽图鉴 03 / 技能", "title": "织潮者", "body": "紫针施加墨覆；蓄力钉下黑金封钉", "counter": "满蓄返还洗净 · 封钉只能躲", "accent": Color(0.68, 0.48, 0.96), "glyph": enemy_type, "duration": 6.8}
		EnemyType.RAM:
			return {"id": &"ram", "eyebrow": "潮兽图鉴 04 / 冲撞", "title": "冲角", "body": "金线锁定后沿直线贯穿；冲出后不再转向", "counter": "等导线定向 · 横移一步 · 回身返光", "accent": Color(0.95, 0.36, 0.57), "glyph": enemy_type}
		EnemyType.BLOOMER:
			return {"id": &"bloomer", "eyebrow": "潮兽图鉴 05 / 环潮", "title": "回声花", "body": "驻留花庭，周期释放整圈慢弹", "counter": "靠近开折 · 一次收下整圈", "accent": Color(0.72, 0.42, 0.91), "glyph": enemy_type}
		EnemyType.LEECH:
			return {"id": &"leech", "eyebrow": "潮兽图鉴 06 / 汲取", "title": "汲光者", "body": "近身抽走折息，并留下湿墨", "counter": "拉开距离 · 返还 6 光洗净", "accent": Color(0.34, 0.86, 0.84), "glyph": enemy_type}
		EnemyType.MIRROR:
			return {"id": &"mirror", "eyebrow": "潮兽图鉴 07 / 反制", "title": "逆折者", "body": "青环展开时截获返光并储存", "counter": "先收不放 · 等青环闭合再返还", "accent": Color(0.25, 0.88, 0.84), "glyph": enemy_type, "duration": 6.8}
		EnemyType.REWINDER:
			return {"id": &"rewinder", "eyebrow": "潮兽图鉴 08 / 回迹", "title": "回痕兽", "body": "点亮最近四秒的旧路，再沿旧路高速倒冲", "counter": "旧路亮起立即离轨 · 冲完回身返光", "accent": Color(0.96, 0.46, 0.30), "glyph": enemy_type, "duration": 7.2}
		EnemyType.CARVER:
			return {"id": &"carver", "eyebrow": "潮兽图鉴 09 / 刻线", "title": "刻潮者", "body": "停驻预告后，在纸面刻出短时危险折线", "counter": "看见蓝线就换边 · 线散后贴近收弹", "accent": Color(0.36, 0.70, 0.96), "glyph": enemy_type, "duration": 6.8}
		EnemyType.BELL:
			return {"id": &"bell", "eyebrow": "潮兽图鉴 10 / 引潮", "title": "引潮铃", "body": "敲响时牵动附近花瓣，重排成旋转弹带", "counter": "跟着钟弧走半圈 · 收下密集带", "accent": Color(0.82, 0.48, 0.96), "glyph": enemy_type, "duration": 6.8}
		EnemyType.THIEF:
			return {"id": &"thief", "eyebrow": "潮兽图鉴 11 / 逃逸", "title": "盗名舟", "body": "携带名字横穿战场，只会被返光稳定击破", "counter": "先收弹再追船 · 击破会爆出弹药环", "accent": Color(1.0, 0.63, 0.28), "glyph": enemy_type, "duration": 6.8}
		EnemyType.MOTH:
			return {"id": &"moth", "eyebrow": "潮兽图鉴 12 / 复唱", "title": "回声蛾", "body": "记住你上一轮返光数量，再复唱同量慢弹", "counter": "上一轮放得越爽 · 下一轮收得越满", "accent": Color(0.44, 0.90, 0.76), "glyph": enemy_type, "duration": 6.8}
		EnemyType.HERALD:
			return {"id": &"herald", "eyebrow": "潮关 / 本潮终局", "title": "潮使", "body": "驱散杂潮，以高速花瓣守住潮核", "counter": "折返弹幕 · 击破潮核进入下一潮", "accent": Color(1.0, 0.67, 0.28), "glyph": enemy_type}
		EnemyType.BOSS:
			return {"id": current_mission.boss_id if current_mission != null else &"ink_moon", "eyebrow": "终潮 / 多相潮核", "title": current_mission.boss_title if current_mission != null else "墨月", "body": "血量降低时裂相并重写弹幕节奏", "counter": "裂相会清场 · 借空窗重新站位", "accent": current_mission.accent if current_mission != null else Color(0.96, 0.24, 0.54), "glyph": enemy_type, "duration": 7.2}
		_:
			return {}


func _queue_effect_tip(effect_id: StringName) -> void:
	var data := _effect_tip_data(effect_id)
	if data.is_empty():
		return
	if not tip_queue.enqueue_once(&"effect", effect_id, data):
		return
	var intro_id := StringName("effect:%s" % effect_id)
	if not profile_manager.has_acknowledged_intro(intro_id) and (mode == RunMode.PLAYING or mode == RunMode.BRIEFING):
		var intro := data.duplicate(true)
		intro["kind"] = &"effect"
		intro["intro_id"] = intro_id
		_enqueue_briefing(intro, RunMode.PLAYING)


func _effect_tip_data(effect_id: StringName) -> Dictionary:
	match effect_id:
		&"wet_ink":
			return {"eyebrow": "墨痕 / 折息受阻", "title": "湿墨", "body": "折息恢复速度降低 45%", "counter": "返还 6 光即可洗净", "accent": Color(0.30, 0.78, 0.88), "glyph": 0}
		&"bound_crease":
			return {"eyebrow": "墨痕 / 行动受限", "title": "缚折", "body": "移动速度降低 30%", "counter": "返还 3 光即可挣脱", "accent": Color(0.94, 0.42, 0.56), "glyph": 1}
		&"veiled_fold":
			return {"eyebrow": "墨痕 / 折域受限", "title": "墨覆", "body": "折域最大半径缩小 28%", "counter": "蓄满后返还即可洗去", "accent": Color(0.62, 0.42, 0.90), "glyph": 2}
		&"paper_seal":
			return {"eyebrow": "特殊弹幕 / 黑金十字", "title": "封钉", "body": "穿过折域，不会成为返光弹药", "counter": "折域仍会减速 · 立刻走位避开", "accent": Color(1.0, 0.45, 0.16), "glyph": 3, "duration": 6.4}
		&"crosswind":
			return {"eyebrow": "场景效果 / 纸鸢横风", "title": "横风", "body": "场上敌弹持续向东偏移", "counter": "沿风向预留半个身位", "accent": Color(0.42, 0.66, 0.94), "glyph": 4}
		&"lights_out":
			return {"eyebrow": "场景效果 / 无灯时刻", "title": "风眼熄灯", "body": "纸海压暗，冲角从边缘突入", "counter": "跟随金色导线 · 保留折息", "accent": Color(0.96, 0.32, 0.54), "glyph": 5}
		_:
			return {}


func _show_sealed_tip(source: String) -> void:
	if _sealed_tip_seen:
		return
	_sealed_tip_seen = true
	_queue_effect_tip(&"paper_seal")
	_show_event("封钉", "%s · 黑金十字无法收纳，只能避开" % source)
	hud.flash(Color(1.0, 0.42, 0.18), 0.16)


func _spawn_herald() -> void:
	_herald_active = true
	_ritual_event_timer = 0.0
	_show_event("潮使现身", "折返它的弹幕，完成本潮")
	hostile_shots.clear()
	for enemy_index in range(enemies.size() - 1, -1, -1):
		if int(enemies[enemy_index]["type"]) != EnemyType.HERALD:
			_burst(enemies[enemy_index]["position"], Color(0.38, 0.76, 0.76), 7, 90.0)
			enemies.remove_at(enemy_index)
	var hp := 24 + act * 10
	enemies.append({
		"id": _next_enemy_id,
		"type": int(EnemyType.HERALD),
		"position": Vector2(960.0, 164.0),
		"velocity": Vector2.ZERO,
		"health": hp,
		"max_health": hp,
		"radius": 61.0,
		"age": 0.0,
		"shoot": 1.4,
		"special": 3.3,
		"phase": _rng.randf_range(0.0, TAU),
		"elite": true,
		"affix": act,
		"ritual_variant": act,
		"flash": 0.0,
		"skill_charge": 0.0,
	})
	_next_enemy_id += 1
	_queue_enemy_tip(EnemyType.HERALD)
	audio_director.play_sfx(&"boss", 1.18, -3.0)
	_shake_amount = 15.0


func _open_technique_seal(next_act: int) -> void:
	mode = RunMode.UPGRADE
	_stage_timer = 0.0
	_pending_act = next_act
	player.cancel_fold()
	player.set_play_enabled(false)
	player.clear_statuses()
	hostile_shots.clear()
	return_lights.clear()
	_seal_options = _build_seal_options()
	_seal_selected = 0
	_event_message_timer = 0.0
	audio_director.set_intensity(0.08)
	audio_director.play_sfx(&"act", 1.22)
	hud.flash(Color(1.0, 0.80, 0.44), 0.24)


func _build_seal_options() -> Array[FoldDoctrine]:
	var result: Array[FoldDoctrine] = []
	if _chosen_path < 0:
		for path: Array in DOCTRINE_PATHS:
			var starter := _doctrine_by_id(path[0])
			if starter != null:
				result.append(starter)
		return result
	if _chosen_path >= DOCTRINE_PATHS.size() or _path_step >= DOCTRINE_PATHS[_chosen_path].size():
		return result
	var next_doctrine := _doctrine_by_id(DOCTRINE_PATHS[_chosen_path][_path_step])
	if next_doctrine != null:
		result.append(next_doctrine)
	return result


func _doctrine_by_id(doctrine_id: StringName) -> FoldDoctrine:
	for doctrine in DOCTRINE_LIBRARY:
		if doctrine.doctrine_id == doctrine_id:
			return doctrine
	return null


func _apply_selected_doctrine() -> void:
	if mode != RunMode.UPGRADE or _seal_options.is_empty():
		return
	var doctrine := _seal_options[clampi(_seal_selected, 0, _seal_options.size() - 1)]
	if not _challenge_active and _chosen_path < 0:
		for path_index in DOCTRINE_PATHS.size():
			if DOCTRINE_PATHS[path_index][0] == doctrine.doctrine_id:
				_chosen_path = path_index
				break
	var key := String(doctrine.doctrine_id)
	var stacks := int(doctrine_stacks.get(key, 0)) + 1
	doctrine_stacks[key] = stacks
	profile_manager.discover_doctrine(doctrine.doctrine_id)
	_apply_doctrine_effect(key)
	owned_doctrines.append(doctrine.to_snapshot(stacks))
	_refresh_build_synergies()
	if _challenge_active and _challenge_draft_pending:
		_challenge_drafts += 1
		_challenge_draft_pending = false
		challenge_director.complete_draft()
		mode = RunMode.PLAYING
		player.set_play_enabled(true)
		player.grant_invulnerability(0.9)
		_seal_options.clear()
		_spawn_ripple(player.position, Color(1.0, 0.74, 0.30), 48.0, 540.0, 0.82, 6.0)
		_burst(player.position, Color(0.48, 0.94, 0.84), 46, 290.0)
		audio_director.set_intensity(_music_intensity())
		return
	_path_step += 1
	audio_director.play_sfx(&"release", 1.24, -1.0)
	_spawn_ripple(player.position, Color(1.0, 0.74, 0.30), 48.0, 540.0, 0.82, 6.0)
	_burst(player.position, Color(0.48, 0.94, 0.84), 46, 290.0)
	mode = RunMode.PLAYING
	act = _pending_act
	act_time = 0.0
	_herald_active = false
	_ritual_flags.clear()
	_ritual_event_kind = 0
	_ritual_event_timer = 0.0
	_spawn_timer = 2.3
	player.grant_invulnerability(0.9)
	player.set_play_enabled(true)
	_seal_options.clear()
	if act >= FINAL_ACT:
		_commit_campaign_checkpoint()
		_spawn_boss()
	else:
		_mercy_charges = 1 if doctrine_stacks.has("mercy_blank") else 0
		_show_stage(act)
		_begin_tide_objective()
		_commit_campaign_checkpoint()
		audio_director.set_intensity(_music_intensity())


func _apply_doctrine_effect(key: String, restoring: bool = false) -> void:
	match key:
		"wide_crease": player.fold_radius_multiplier *= 1.18
		"deep_breath":
			player.focus_drain_multiplier *= 0.80
			player.focus_regen_multiplier *= 1.18
		"lantern_pocket": player.capture_capacity += 4
		"still_water": _fold_slow_multiplier *= 0.78
		"bright_edge": _return_damage += 1
		"swift_return": _return_speed_multiplier *= 1.22
		"chain_bloom": _chain_bloom = true
		"full_moon": _full_moon = true
		"paper_heart":
			player.max_health += 1
			if not restoring:
				player.health = mini(player.max_health, player.health + 1)
		"slipstream":
			player.move_speed_multiplier *= 1.12
			player.fold_speed_multiplier *= 1.16
		"mercy_blank": _mercy_charges = 1
		"golden_seam": _golden_seam = true
		"quiet_horizon":
			player.fold_radius_multiplier *= 1.12
			player.focus_drain_multiplier *= 0.90
		"ocean_fold":
			player.capture_capacity += 6
			_fold_slow_multiplier *= 0.80
		"sunward":
			_return_damage += 1
			_return_speed_multiplier *= 1.12
		"starfall":
			_return_speed_multiplier *= 1.25
			_starfall_mastery = true
		"afterglow":
			if not restoring:
				player.health = mini(player.max_health, player.health + 2)
			player.focus_regen_multiplier *= 1.18
		"dawn_vow":
			player.max_health += 1
			if not restoring:
				player.health += 1
			_mercy_charges += 1


func _refresh_build_synergies(restoring: bool = false) -> void:
	var previous := [_sea_mirror, _ocean_memory, _needle_light, _sun_chain, _walking_lantern, _mercy_fire]
	_sea_mirror = doctrine_stacks.has("still_water") and doctrine_stacks.has("quiet_horizon")
	_ocean_memory = doctrine_stacks.has("deep_breath") and doctrine_stacks.has("ocean_fold")
	_needle_light = doctrine_stacks.has("swift_return") and doctrine_stacks.has("bright_edge")
	_sun_chain = doctrine_stacks.has("chain_bloom") and doctrine_stacks.has("starfall")
	_walking_lantern = doctrine_stacks.has("slipstream") and doctrine_stacks.has("golden_seam")
	_mercy_fire = doctrine_stacks.has("mercy_blank") and doctrine_stacks.has("dawn_vow")
	if restoring:
		return
	var current := [_sea_mirror, _ocean_memory, _needle_light, _sun_chain, _walking_lantern, _mercy_fire]
	var names: Array[String] = ["海镜", "潮忆", "针光", "日链", "行灯", "慈火"]
	for index in current.size():
		if bool(current[index]) and not bool(previous[index]):
			_show_event("折法共鸣 · %s" % names[index], "两枚折法开始互相回应")
			_spawn_ripple(player.position, Color(1.0, 0.72, 0.28), 42.0, 390.0, 0.72, 5.0)


func _synergy_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = [
		[_sea_mirror, "海镜", "大返光留下减速潮域"],
		[_ocean_memory, "潮忆", "十二枚返光额外回充折息"],
		[_needle_light, "针光", "少量满蓄返光获得锋锐加伤"],
		[_sun_chain, "日链", "五次返光击杀生成重返光"],
		[_walking_lantern, "行灯", "高速移动后的返光加伤"],
		[_mercy_fire, "慈火", "留白触发时自动释放八枚返光"],
	]
	for entry in entries:
		if bool(entry[0]):
			result.append({"title": entry[1], "detail": entry[2]})
	return result


func _show_stage(stage_index: int) -> void:
	_stage_message = _current_stage_title(stage_index)
	_stage_subtitle = _current_stage_subtitle(stage_index)
	_stage_timer = 3.5
	if current_mission_index == 0:
		_queue_story_for_act(stage_index)
	_enqueue_briefing({
		"kind": &"stage",
		"eyebrow": "航路展开 / %s" % _current_scene_tag(stage_index),
		"title": _current_stage_title(stage_index),
		"body": _current_stage_subtitle(stage_index),
		"counter": _current_objective_label(stage_index),
		"accent": _scene_accent(),
	}, RunMode.PLAYING)


func _current_tide_duration() -> float:
	return current_mission.tide_duration if current_mission != null else RITUAL_DURATION


func _current_first_event_time() -> float:
	return _current_tide_duration() * 0.30


func _current_second_event_time() -> float:
	return _current_tide_duration() * 0.64


func _current_modifier_id() -> StringName:
	if current_mission == null or act >= FINAL_ACT:
		return &"calm"
	return StringName(current_mission.tide_value(current_mission.modifier_ids, act - 1, &"calm"))


func _current_act_name(stage_index: int) -> String:
	if current_mission == null:
		return ACT_NAMES[clampi(stage_index, 0, ACT_NAMES.size() - 1)]
	if stage_index >= FINAL_ACT:
		return current_mission.boss_title
	return str(current_mission.tide_value(current_mission.tide_names, stage_index - 1, "潮之%d" % stage_index))


func _current_scene_tag(stage_index: int) -> String:
	if current_mission == null:
		return ACT_SCENE_TAGS[clampi(stage_index, 0, ACT_SCENE_TAGS.size() - 1)]
	if stage_index >= FINAL_ACT:
		return current_mission.location
	return str(current_mission.tide_value(current_mission.tide_scene_tags, stage_index - 1, current_mission.location))


func _current_objective_label(stage_index: int) -> String:
	if current_mission == null:
		return ACT_OBJECTIVES[clampi(stage_index, 0, ACT_OBJECTIVES.size() - 1)]
	if stage_index >= FINAL_ACT:
		return current_mission.boss_subtitle
	return str(current_mission.tide_value(current_mission.tide_objective_labels, stage_index - 1, "完成本潮"))


func _current_stage_title(stage_index: int) -> String:
	if current_mission == null:
		return ACT_TITLES[clampi(stage_index, 0, ACT_TITLES.size() - 1)]
	if stage_index >= FINAL_ACT:
		return "终潮 · %s" % current_mission.boss_title
	return "潮之%s · %s" % [_chinese_number(stage_index), _current_act_name(stage_index)]


func _current_stage_subtitle(stage_index: int) -> String:
	if current_mission == null:
		return ACT_SUBTITLES[clampi(stage_index, 0, ACT_SUBTITLES.size() - 1)]
	if stage_index >= FINAL_ACT:
		return current_mission.boss_subtitle
	return _current_objective_label(stage_index)


func _chinese_number(value: int) -> String:
	var values: Array[String] = ["零", "一", "二", "三", "四", "五", "六", "七"]
	return values[clampi(value, 0, values.size() - 1)]


func _update_spawning(delta: float) -> void:
	if _boss_spawned or _herald_active or act_time < 3.0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0 or enemies.size() >= ENEMY_CAP:
		return
	var interval := 1.85
	match act:
		1: interval = 1.82
		2: interval = 1.48
		3: interval = 1.22
		4: interval = 1.06
		5: interval = 0.94
		6: interval = 0.88
	if current_mission != null:
		interval /= clampf(sqrt(current_mission.difficulty), 0.88, 1.34)
	_spawn_timer = interval * _rng.randf_range(0.78, 1.18)
	var enemy_type := _choose_enemy_type()
	var elite_chance := maxf(0.0, float(act - 1) * 0.035 + float(current_mission_index) * 0.010)
	elite_chance = minf(elite_chance, 0.22)
	_spawn_enemy(enemy_type, _active_elite_count() < 2 and _rng.randf() < elite_chance)


func _active_elite_count() -> int:
	var count := 0
	for enemy in enemies:
		if bool(enemy.get("elite", false)) and int(enemy.get("type", EnemyType.DRIFTER)) < EnemyType.HERALD:
			count += 1
	return count


func _choose_enemy_type() -> EnemyType:
	if current_mission != null and act < FINAL_ACT:
		var roster_text := str(current_mission.tide_value(current_mission.enemy_rosters, act - 1, "drifter"))
		var roster: PackedStringArray = roster_text.split(",", false)
		if not roster.is_empty():
			var chosen_id := StringName(roster[_rng.randi_range(0, roster.size() - 1)].strip_edges())
			return _enemy_type_from_id(chosen_id)
	var roll := _rng.randf()
	match act:
		1:
			return EnemyType.DRIFTER
		2:
			return EnemyType.FAN if roll < 0.40 else EnemyType.DRIFTER
		3:
			if act_time >= 40.0 and roll < 0.14:
				return EnemyType.MIRROR
			if roll < 0.29:
				return EnemyType.BLOOMER
			if roll < 0.50:
				return EnemyType.WEAVER
			return EnemyType.FAN if roll < 0.74 else EnemyType.DRIFTER
		4:
			if roll < 0.14:
				return EnemyType.MIRROR
			if roll < 0.30:
				return EnemyType.LEECH
			if roll < 0.52:
				return EnemyType.WEAVER
			return EnemyType.FAN if roll < 0.78 else EnemyType.DRIFTER
		5:
			if roll < 0.24:
				return EnemyType.RAM
			if roll < 0.42:
				return EnemyType.LEECH
			if roll < 0.58:
				return EnemyType.MIRROR
			if roll < 0.76:
				return EnemyType.WEAVER
			return EnemyType.FAN
		6:
			if roll < 0.20:
				return EnemyType.REWINDER
			if roll < 0.38:
				return EnemyType.RAM
			if roll < 0.54:
				return EnemyType.MIRROR
			if roll < 0.70:
				return EnemyType.LEECH
			if roll < 0.84:
				return EnemyType.WEAVER
			return EnemyType.FAN
	return EnemyType.DRIFTER


func _enemy_type_from_id(enemy_id: StringName) -> EnemyType:
	match enemy_id:
		&"drifter": return EnemyType.DRIFTER
		&"fan": return EnemyType.FAN
		&"weaver": return EnemyType.WEAVER
		&"ram": return EnemyType.RAM
		&"bloomer": return EnemyType.BLOOMER
		&"leech": return EnemyType.LEECH
		&"mirror": return EnemyType.MIRROR
		&"rewinder": return EnemyType.REWINDER
		&"carver": return EnemyType.CARVER
		&"bell": return EnemyType.BELL
		&"thief": return EnemyType.THIEF
		&"moth": return EnemyType.MOTH
		_: return EnemyType.DRIFTER


func _spawn_enemy(enemy_type: EnemyType, elite: bool = false) -> void:
	if enemy_type < EnemyType.HERALD:
		var regular_enemy_count := 0
		var replacement_index := -1
		var oldest_age := -1.0
		for active_enemy in enemies:
			if int(active_enemy.get("type", EnemyType.DRIFTER)) < EnemyType.HERALD:
				regular_enemy_count += 1
		var active_index := 0
		while regular_enemy_count >= ENEMY_CAP and active_index < enemies.size():
			var candidate: Dictionary = enemies[active_index]
			if int(candidate.get("type", EnemyType.DRIFTER)) < EnemyType.HERALD and not bool(candidate.get("elite", false)):
				var candidate_age := float(candidate.get("age", 0.0))
				if candidate_age > oldest_age:
					oldest_age = candidate_age
					replacement_index = active_index
			active_index += 1
		if regular_enemy_count >= ENEMY_CAP:
			if replacement_index < 0:
				for fallback_index in enemies.size():
					if int(enemies[fallback_index].get("type", EnemyType.DRIFTER)) < EnemyType.HERALD:
						replacement_index = fallback_index
						break
			if replacement_index >= 0:
				enemies.remove_at(replacement_index)
	var arena := _current_arena_bounds().grow(-16.0)
	var side := _rng.randi_range(0, 3)
	var spawn_position := Vector2.ZERO
	match side:
		0: spawn_position = Vector2(arena.position.x, _rng.randf_range(arena.position.y, arena.end.y))
		1: spawn_position = Vector2(arena.end.x, _rng.randf_range(arena.position.y, arena.end.y))
		2: spawn_position = Vector2(_rng.randf_range(arena.position.x, arena.end.x), arena.position.y)
		_: spawn_position = Vector2(_rng.randf_range(arena.position.x, arena.end.x), arena.end.y)
	if enemy_type == EnemyType.THIEF:
		spawn_position = Vector2(arena.position.x, _rng.randf_range(arena.position.y + 40.0, arena.end.y - 40.0))
	var hp := 2
	var radius := 27.0
	match enemy_type:
		EnemyType.FAN:
			hp = 4
			radius = 34.0
		EnemyType.WEAVER:
			hp = 6
			radius = 38.0
		EnemyType.RAM:
			hp = 8
			radius = 42.0
		EnemyType.BLOOMER:
			hp = 9
			radius = 45.0
		EnemyType.LEECH:
			hp = 10
			radius = 43.0
		EnemyType.MIRROR:
			hp = 11
			radius = 48.0
		EnemyType.REWINDER:
			hp = 12
			radius = 45.0
		EnemyType.CARVER:
			hp = 10
			radius = 41.0
		EnemyType.BELL:
			hp = 13
			radius = 48.0
		EnemyType.THIEF:
			hp = 8
			radius = 36.0
		EnemyType.MOTH:
			hp = 9
			radius = 40.0
		_: pass
	if current_mission != null:
		hp = maxi(1, int(ceil(float(hp) * clampf(0.88 + current_mission.difficulty * 0.12, 0.96, 1.12))))
	if _challenge_active:
		hp = maxi(1, int(ceil(float(hp) * (1.0 + float(challenge_director.tier - 1) * 0.065))))
	var affix := 0
	if elite:
		hp += 3
		radius += 4.0
		affix = _rng.randi_range(1, 6)
		if affix == 1:
			hp += 2
		elif affix == 3:
			hp += 5
		elif affix == 6:
			hp += 2
	var path_buffer: Variant = null
	if enemy_type == EnemyType.REWINDER:
		path_buffer = PATH_HISTORY_BUFFER_SCRIPT.new(54, 0.08)
		path_buffer.reset(spawn_position, 0.0)
	enemies.append({
		"id": _next_enemy_id,
		"type": int(enemy_type),
		"position": spawn_position,
		"velocity": Vector2.ZERO,
		"health": hp,
		"max_health": hp,
		"radius": radius,
		"age": 0.0,
		"shoot": _rng.randf_range(0.75, 1.8),
		"special": _rng.randf_range(2.0, 3.8),
		"phase": _rng.randf_range(0.0, TAU),
		"elite": elite,
		"affix": affix,
		"flash": 0.0,
		"mirror_state": int(MirrorState.SEEK),
		"mirror_timer": _rng.randf_range(2.2, 3.0),
		"stored_light": 0,
		"skill_charge": 0.0,
		"ram_state": int(RamState.STALK),
		"ram_timer": _rng.randf_range(1.7, 2.5),
		"charge_direction": Vector2.ZERO,
		"dash_hit": false,
		"rewind_state": int(RewindState.ROAM),
		"rewind_timer": _rng.randf_range(4.2, 5.0),
		"path_buffer": path_buffer,
		"rewind_path": PackedVector2Array(),
		"rewind_index": -1,
		"telegraph_direction": Vector2.ZERO,
		"escaped": false,
		"echo_count": _last_release_count,
		"affix_timer": _rng.randf_range(2.8, 4.8),
		"return_shield": 3 if affix == 6 else 0,
	})
	_next_enemy_id += 1
	var enemy_ids: Array[StringName] = [&"drifter", &"fan", &"weaver", &"ram", &"bloomer", &"leech", &"mirror", &"rewinder", &"carver", &"bell", &"thief", &"moth", &"herald", current_mission.boss_id if current_mission != null else &"ink_moon"]
	profile_manager.discover_enemy(enemy_ids[int(enemy_type)])
	_queue_enemy_tip(enemy_type)


func _spawn_boss() -> void:
	_boss_spawned = true
	act = FINAL_ACT
	_show_stage(FINAL_ACT)
	audio_director.play_sfx(&"boss")
	audio_director.set_intensity(1.0)
	hud.flash(Color(0.86, 0.18, 0.46), 0.38)
	_shake_amount = 18.0
	# The finale begins as a clean, readable composition.
	for enemy in enemies:
		_burst(enemy["position"], Color(0.42, 0.78, 0.78), 9, 110.0)
	enemies.clear()
	for shot in hostile_shots:
		shot["velocity"] = shot["velocity"] * 0.28
	var boss_hp := 138
	if current_mission != null:
		boss_hp = 118 + current_mission_index * 8 + (52 if current_mission.chapter_finale else 0)
	enemies.append({
		"id": _next_enemy_id,
		"type": int(EnemyType.BOSS),
		"position": Vector2(960.0, -120.0),
		"velocity": Vector2.ZERO,
		"health": boss_hp,
		"max_health": boss_hp,
		"radius": 92.0,
		"age": 0.0,
		"shoot": 2.6,
		"special": 4.5,
		"phase": 0.0,
		"elite": true,
		"affix": 0,
		"boss_phase": 1,
		"boss_id": current_mission.boss_id if current_mission != null else &"ink_moon",
		"boss_variant": current_mission_index,
		"last_echo_count": _last_release_count,
		"flash": 0.0,
		"skill_charge": 0.0,
	})
	_next_enemy_id += 1
	profile_manager.discover_enemy(current_mission.boss_id if current_mission != null else &"ink_moon")
	_queue_enemy_tip(EnemyType.BOSS)


func _update_ram_enemy(enemy: Dictionary, delta: float, direction: Vector2, speed_multiplier: float) -> Vector2:
	var state := int(enemy.get("ram_state", RamState.STALK))
	var timer := float(enemy.get("ram_timer", 2.0)) - delta
	var velocity_value: Vector2 = enemy.get("velocity", Vector2.ZERO)
	match state:
		RamState.STALK:
			var to_player: Vector2 = player.position - Vector2(enemy["position"])
			var distance := to_player.length()
			var radial := direction * clampf((distance - 470.0) * 0.28, -62.0, 82.0)
			var orbit := direction.rotated(PI * 0.5) * sin(float(enemy["age"]) * 0.9 + float(enemy["phase"])) * 72.0
			velocity_value = velocity_value.lerp((radial + orbit) * speed_multiplier, minf(1.0, delta * 2.0))
			if timer <= 0.0:
				enemy["ram_state"] = int(RamState.TELEGRAPH)
				enemy["ram_timer"] = 0.95 if not bool(enemy["elite"]) else 0.82
				enemy["charge_direction"] = direction
				enemy["dash_hit"] = false
				_background_pulse = maxf(_background_pulse, 0.34)
				audio_director.play_sfx(&"act", 0.74, -7.0)
				return velocity_value
		RamState.TELEGRAPH:
			# The first 0.30 s may aim; the remaining warning locks the gold line.
			var warning_total := 0.95 if not bool(enemy["elite"]) else 0.82
			if timer > warning_total - 0.30:
				enemy["charge_direction"] = direction
			velocity_value = velocity_value.move_toward(Vector2.ZERO, 720.0 * delta)
			if timer <= 0.0:
				enemy["ram_state"] = int(RamState.CHARGE)
				enemy["ram_timer"] = 0.72
				var charge_direction: Vector2 = enemy.get("charge_direction", direction)
				velocity_value = charge_direction.normalized() * (920.0 if bool(enemy["elite"]) else 840.0)
				_background_pulse = maxf(_background_pulse, 0.72)
				audio_director.play_sfx(&"release", 0.68, -4.0)
				return velocity_value
		RamState.CHARGE:
			var charge_direction: Vector2 = enemy.get("charge_direction", direction)
			velocity_value = charge_direction.normalized() * (920.0 if bool(enemy["elite"]) else 840.0)
			if timer <= 0.0:
				enemy["ram_state"] = int(RamState.RECOVER)
				enemy["ram_timer"] = 0.78
				velocity_value *= 0.18
				return velocity_value
		RamState.RECOVER:
			velocity_value = velocity_value.move_toward(Vector2.ZERO, 980.0 * delta)
			if timer <= 0.0:
				enemy["ram_state"] = int(RamState.STALK)
				enemy["ram_timer"] = _rng.randf_range(2.0, 2.8)
				return velocity_value
	enemy["ram_timer"] = timer
	return velocity_value


func _update_rewinder_enemy(enemy: Dictionary, delta: float, direction: Vector2, speed_multiplier: float) -> Vector2:
	var state := int(enemy.get("rewind_state", RewindState.ROAM))
	var timer := float(enemy.get("rewind_timer", 4.5)) - delta
	var velocity_value: Vector2 = enemy.get("velocity", Vector2.ZERO)
	var history: Variant = enemy.get("path_buffer")
	match state:
		RewindState.ROAM:
			if history != null:
				history.sample(delta, Vector2(enemy["position"]), float(enemy["age"]))
			var orbit := direction.rotated(PI * 0.5) * (88.0 + sin(float(enemy["age"]) * 1.1 + float(enemy["phase"])) * 24.0)
			velocity_value = velocity_value.lerp((direction * 78.0 + orbit) * speed_multiplier, minf(1.0, delta * 2.3))
			if timer <= 0.0 and history != null and history.history_span() >= 3.75:
				var snapshot: PackedVector2Array = history.snapshot_since(float(enemy["age"]) - 4.0)
				if snapshot.size() >= 12:
					enemy["rewind_path"] = snapshot
					enemy["rewind_index"] = snapshot.size() - 1
					enemy["rewind_state"] = int(RewindState.TELEGRAPH)
					enemy["rewind_timer"] = 1.20 if not bool(enemy["elite"]) else 1.02
					enemy["dash_hit"] = false
					_background_pulse = maxf(_background_pulse, 0.52)
					audio_director.play_sfx(&"act", 0.62, -6.0)
					return velocity_value
				timer = 0.35
		RewindState.TELEGRAPH:
			velocity_value = velocity_value.move_toward(Vector2.ZERO, 760.0 * delta)
			if timer <= 0.0:
				enemy["rewind_state"] = int(RewindState.REWIND)
				enemy["rewind_timer"] = 5.2
				_background_pulse = maxf(_background_pulse, 0.88)
				audio_director.play_sfx(&"release", 0.56, -2.0)
				return velocity_value
		RewindState.REWIND:
			var path: PackedVector2Array = enemy.get("rewind_path", PackedVector2Array())
			var path_index := int(enemy.get("rewind_index", -1))
			var speed := 980.0 if bool(enemy["elite"]) else 900.0
			while path_index >= 0 and Vector2(enemy["position"]).distance_to(path[path_index]) <= maxf(20.0, speed * delta * 1.25):
				path_index -= 1
			enemy["rewind_index"] = path_index
			if path_index < 0 or timer <= 0.0:
				enemy["rewind_state"] = int(RewindState.RECOVER)
				enemy["rewind_timer"] = 0.85
				velocity_value *= 0.12
				return velocity_value
			velocity_value = Vector2(enemy["position"]).direction_to(path[path_index]) * speed
		RewindState.RECOVER:
			velocity_value = velocity_value.move_toward(Vector2.ZERO, 1050.0 * delta)
			if timer <= 0.0:
				enemy["rewind_state"] = int(RewindState.ROAM)
				enemy["rewind_timer"] = _rng.randf_range(4.4, 5.3)
				enemy["rewind_path"] = PackedVector2Array()
				if history != null:
					history.reset(Vector2(enemy["position"]), float(enemy["age"]))
				return velocity_value
	enemy["rewind_timer"] = timer
	return velocity_value


func _update_enemies(delta: float) -> void:
	var index := 0
	while index < enemies.size():
		var enemy: Dictionary = enemies[index]
		enemy["age"] = float(enemy["age"]) + delta
		enemy["shoot"] = float(enemy["shoot"]) - delta
		enemy["special"] = float(enemy["special"]) - delta
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - delta * 5.5)
		var enemy_type := int(enemy["type"])
		var position_value: Vector2 = enemy["position"]
		var previous_position := position_value
		var velocity_value: Vector2 = enemy["velocity"]
		var to_player := player.position - position_value
		var direction := to_player.normalized() if to_player.length_squared() > 1.0 else Vector2.UP
		var phase: float = float(enemy["phase"])
		var age: float = float(enemy["age"])
		var affix := int(enemy.get("affix", 0))
		var speed_multiplier := 1.18 if affix == 4 else 1.0
		if _challenge_active:
			speed_multiplier *= minf(1.72, (1.0 + float(challenge_director.tier - 1) * 0.025) * challenge_director.get_enemy_speed_scale())
		if bool(enemy.get("elite", false)) and affix > 0 and enemy_type < EnemyType.HERALD:
			var affix_timer := float(enemy.get("affix_timer", 4.0)) - delta
			if affix_timer <= 0.0:
				if affix == 1:
					_fire_ring(position_value, 6, 92.0, age, Color(0.42, 0.90, 0.78))
					affix_timer = 5.5
				elif affix == 2:
					var echo_aim := (player.position - position_value).angle()
					for echo_spread in [-0.20, 0.20]:
						_spawn_hostile(position_value, echo_aim + echo_spread, 152.0, -echo_spread * 0.16, Color(0.76, 0.48, 0.94), 0)
					affix_timer = 4.4
				else:
					affix_timer = 4.8
			enemy["affix_timer"] = affix_timer

		match enemy_type:
			EnemyType.DRIFTER:
				var drift := direction.rotated(PI * 0.5) * sin(age * 1.8 + phase) * 34.0
				velocity_value = velocity_value.lerp((direction * (58.0 + act * 5.0) + drift) * speed_multiplier, minf(1.0, delta * 1.8))
				if float(enemy["shoot"]) <= 0.0:
					_fire_drifter(enemy)
					enemy["shoot"] = _rng.randf_range(1.65, 2.3) / (1.0 + float(act - 1) * 0.06)
			EnemyType.FAN:
				var distance := to_player.length()
				var radial := direction * clampf((distance - 520.0) * 0.32, -72.0, 72.0)
				var orbit := direction.rotated(PI * 0.5) * (64.0 + sin(phase) * 14.0)
				velocity_value = velocity_value.lerp((radial + orbit) * speed_multiplier, minf(1.0, delta * 2.2))
				if float(enemy["shoot"]) <= 0.0:
					_fire_fan(enemy)
					enemy["shoot"] = _rng.randf_range(2.2, 2.75)
			EnemyType.WEAVER:
				var anchor := Vector2(960.0, 535.0) + Vector2.from_angle(age * 0.24 + phase) * 470.0
				velocity_value = velocity_value.lerp((anchor - position_value).limit_length(105.0 * speed_multiplier), minf(1.0, delta * 1.9))
				var weaver_charge := float(enemy.get("skill_charge", 0.0))
				if weaver_charge > 0.0:
					weaver_charge = maxf(0.0, weaver_charge - delta)
					enemy["skill_charge"] = weaver_charge
					velocity_value *= 0.55
					if weaver_charge <= 0.0:
						_fire_weaver_seal(enemy)
						enemy["special"] = 5.8 if bool(enemy["elite"]) else 6.6
				elif float(enemy["special"]) <= 0.0:
					enemy["skill_charge"] = 0.95
					enemy["special"] = 6.6
					_show_sealed_tip("织潮者正在钉死纸面")
				elif float(enemy["shoot"]) <= 0.0:
					_fire_weaver(enemy)
					enemy["shoot"] = 0.34 if act >= 4 else 0.46
			EnemyType.RAM:
				velocity_value = _update_ram_enemy(enemy, delta, direction, speed_multiplier)
			EnemyType.BLOOMER:
				var bloom_anchor := Vector2(960.0, 535.0) + Vector2.from_angle(phase) * 420.0
				velocity_value = velocity_value.lerp((bloom_anchor - position_value).limit_length(82.0 * speed_multiplier), minf(1.0, delta * 1.6))
				if float(enemy["shoot"]) <= 0.0:
					_fire_ring(position_value, 12 if bool(enemy["elite"]) else 9, 112.0, age * 0.31, Color(0.58, 0.31, 0.79))
					enemy["shoot"] = 2.05 if bool(enemy["elite"]) else 2.65
			EnemyType.LEECH:
				var leech_distance := to_player.length()
				var leech_motion := direction * clampf((leech_distance - 225.0) * 0.52, -84.0, 116.0)
				leech_motion += direction.rotated(PI * 0.5) * sin(age * 1.4 + phase) * 54.0
				velocity_value = velocity_value.lerp(leech_motion * speed_multiplier, minf(1.0, delta * 2.1))
				if leech_distance < 245.0:
					player.add_focus(-delta * (0.060 if bool(enemy["elite"]) else 0.040))
					if float(enemy["special"]) <= 0.0:
						_apply_player_status(&"wet_ink", 5.4)
						enemy["special"] = 3.6
				if float(enemy["shoot"]) <= 0.0:
					var leech_aim := (player.position - position_value).angle()
					for spread in [-0.20, 0.0, 0.20]:
						_spawn_hostile(position_value, leech_aim + spread, 164.0, spread * 0.14, Color(0.86, 0.22, 0.58), 0, &"wet_ink", 5.4)
					enemy["shoot"] = 2.25
			EnemyType.MIRROR:
				var mirror_distance := to_player.length()
				var mirror_motion := direction * clampf((mirror_distance - 410.0) * 0.38, -86.0, 108.0)
				mirror_motion += direction.rotated(PI * 0.5) * (58.0 + sin(age * 1.2 + phase) * 18.0)
				var mirror_state := int(enemy.get("mirror_state", MirrorState.SEEK))
				var mirror_timer := float(enemy.get("mirror_timer", 2.4)) - delta
				if mirror_state == MirrorState.FOLD:
					mirror_motion *= 0.24
				elif mirror_state == MirrorState.RELEASE:
					mirror_motion *= 0.55
				velocity_value = velocity_value.lerp(mirror_motion * speed_multiplier, minf(1.0, delta * 2.0))
				if mirror_state == MirrorState.SEEK and float(enemy["shoot"]) <= 0.0:
					var mirror_aim := (player.position - position_value).angle()
					for spread in [-0.12, 0.12]:
						_spawn_hostile(position_value, mirror_aim + spread, 172.0, -spread * 0.16, Color(0.28, 0.72, 0.80), 0)
					enemy["shoot"] = 1.75
				if mirror_timer <= 0.0:
					match mirror_state:
						MirrorState.SEEK:
							enemy["mirror_state"] = int(MirrorState.FOLD)
							enemy["mirror_timer"] = 1.85
							if not _mirror_tip_seen:
								_mirror_tip_seen = true
								_show_event("逆折者展开青环", "暂缓返还 · 等青环闭合再出手")
						MirrorState.FOLD:
							enemy["mirror_state"] = int(MirrorState.RELEASE)
							enemy["mirror_timer"] = 0.55
							_release_mirror_volley(enemy)
						MirrorState.RELEASE:
							enemy["mirror_state"] = int(MirrorState.SEEK)
							enemy["mirror_timer"] = 2.65
				else:
					enemy["mirror_timer"] = mirror_timer
			EnemyType.REWINDER:
				velocity_value = _update_rewinder_enemy(enemy, delta, direction, speed_multiplier)
			EnemyType.CARVER:
				var carver_anchor := Vector2(960.0, 540.0) + Vector2.from_angle(phase) * 510.0
				velocity_value = velocity_value.lerp((carver_anchor - position_value).limit_length(96.0 * speed_multiplier), minf(1.0, delta * 1.8))
				var carve_charge := float(enemy.get("skill_charge", 0.0))
				if carve_charge > 0.0:
					carve_charge = maxf(0.0, carve_charge - delta)
					enemy["skill_charge"] = carve_charge
					velocity_value *= 0.18
					if carve_charge <= 0.0:
						_fire_carver_line(enemy)
				elif float(enemy["special"]) <= 0.0:
					enemy["skill_charge"] = 0.92 if not bool(enemy["elite"]) else 0.76
					enemy["telegraph_direction"] = direction
					enemy["special"] = 5.6
					_background_pulse = maxf(_background_pulse, 0.36)
				elif float(enemy["shoot"]) <= 0.0:
					var carve_aim := (player.position - position_value).angle()
					for spread in [-0.16, 0.16]:
						_spawn_hostile(position_value, carve_aim + spread, 158.0, -spread * 0.12, Color(0.36, 0.68, 0.94), 0)
					enemy["shoot"] = 2.15
			EnemyType.BELL:
				var bell_distance := to_player.length()
				var bell_motion := direction * clampf((bell_distance - 480.0) * 0.30, -68.0, 76.0)
				bell_motion += direction.rotated(PI * 0.5) * (72.0 + sin(age + phase) * 22.0)
				velocity_value = velocity_value.lerp(bell_motion * speed_multiplier, minf(1.0, delta * 1.9))
				var bell_charge := float(enemy.get("skill_charge", 0.0))
				if bell_charge > 0.0:
					bell_charge = maxf(0.0, bell_charge - delta)
					enemy["skill_charge"] = bell_charge
					velocity_value *= 0.36
					if bell_charge <= 0.0:
						_fire_bell_pull(enemy)
				elif float(enemy["special"]) <= 0.0:
					enemy["skill_charge"] = 1.05
					enemy["special"] = 5.2
					_background_pulse = maxf(_background_pulse, 0.48)
				elif float(enemy["shoot"]) <= 0.0:
					_fire_ring(position_value, 7, 106.0, age * 0.2, Color(0.72, 0.40, 0.88))
					enemy["shoot"] = 3.0
			EnemyType.THIEF:
				velocity_value = Vector2(178.0 + current_mission_index * 5.0, sin(age * 2.2 + phase) * 82.0) * speed_multiplier
				if float(enemy["shoot"]) <= 0.0:
					for spread in [-0.22, 0.0, 0.22]:
						_spawn_hostile(position_value, PI + spread, 118.0, spread * 0.10, Color(0.96, 0.56, 0.26), 0)
					enemy["shoot"] = 2.4
			EnemyType.MOTH:
				var moth_anchor := player.position + Vector2.from_angle(age * 0.34 + phase) * 430.0
				velocity_value = velocity_value.lerp((moth_anchor - position_value).limit_length(112.0 * speed_multiplier), minf(1.0, delta * 2.0))
				var moth_charge := float(enemy.get("skill_charge", 0.0))
				if moth_charge > 0.0:
					moth_charge = maxf(0.0, moth_charge - delta)
					enemy["skill_charge"] = moth_charge
					velocity_value *= 0.42
					if moth_charge <= 0.0:
						_fire_moth_echo(enemy)
				elif float(enemy["special"]) <= 0.0:
					enemy["skill_charge"] = 0.82
					enemy["echo_count"] = _last_release_count
					enemy["special"] = 5.4
				elif float(enemy["shoot"]) <= 0.0:
					var moth_aim := (player.position - position_value).angle()
					_spawn_hostile(position_value, moth_aim, 132.0, sin(age) * 0.12, Color(0.42, 0.86, 0.72), 0)
					enemy["shoot"] = 1.9
			EnemyType.HERALD:
				var variant := int(enemy.get("ritual_variant", 1))
				var herald_target := Vector2(960.0 + sin(age * 0.68 + phase) * 480.0, 235.0 + cos(age * 0.43) * 70.0)
				velocity_value = velocity_value.lerp((herald_target - position_value).limit_length(126.0), minf(1.0, delta * 1.8))
				var herald_charge := float(enemy.get("skill_charge", 0.0))
				if herald_charge <= 0.0 and float(enemy["shoot"]) <= 0.0:
					_fire_herald(enemy, variant)
					enemy["shoot"] = maxf(0.34, 0.72 - float(variant) * 0.07)
				if herald_charge > 0.0:
					herald_charge = maxf(0.0, herald_charge - delta)
					enemy["skill_charge"] = herald_charge
					velocity_value *= 0.62
					if herald_charge <= 0.0:
						_fire_herald_seal(enemy)
						enemy["special"] = 4.2
				elif float(enemy["special"]) <= 0.0:
					if variant >= 4:
						enemy["skill_charge"] = 1.05
						enemy["special"] = 4.2
						_show_sealed_tip("终潮使者正在落下六枚封钉")
					else:
						_fire_ring(position_value, 15 + variant * 2, 126.0 + variant * 8.0, age * 0.26, Color(0.87, 0.25, 0.60))
						enemy["special"] = maxf(2.4, 3.7 - float(variant) * 0.22)
			EnemyType.BOSS:
				var target := Vector2(960.0 + sin(age * 0.42) * 390.0, 270.0 + sin(age * 0.73) * 62.0)
				velocity_value = velocity_value.lerp((target - position_value).limit_length(138.0), minf(1.0, delta * 1.5))
				_update_boss_fire(enemy)

		position_value += velocity_value * delta
		var arena := _current_arena_bounds()
		if enemy_type == EnemyType.THIEF and position_value.x > arena.end.x + 1.0:
			_burst(position_value, Color(0.94, 0.46, 0.28), 12, 170.0)
			enemies.remove_at(index)
			_show_event("盗名舟逃逸", "下一艘会更快 · 先攒返光再追")
			continue
		var hit_boundary := not arena.has_point(position_value)
		position_value.x = clampf(position_value.x, arena.position.x, arena.end.x)
		position_value.y = clampf(position_value.y, arena.position.y, arena.end.y)
		if enemy_type == EnemyType.RAM and int(enemy.get("ram_state", RamState.STALK)) == RamState.CHARGE and hit_boundary:
			enemy["ram_state"] = int(RamState.RECOVER)
			enemy["ram_timer"] = 0.78
			velocity_value = Vector2.ZERO
			_ram_wall_impact(position_value, phase + age)
		enemy["position"] = position_value
		enemy["velocity"] = velocity_value
		enemies[index] = enemy

		var contact_radius := float(enemy["radius"]) + player.get_hit_radius()
		if _enemy_contact_is_dangerous(enemy) and _segment_hits_player(previous_position, position_value, contact_radius):
			if player.take_hit():
				if enemy_type == EnemyType.RAM or enemy_type == EnemyType.REWINDER:
					enemy["dash_hit"] = true
					enemies[index] = enemy
				var hurt_applied := _on_player_hurt()
				if hurt_applied and player.health > 0:
					var contact_status := _contact_status_for_enemy(enemy_type)
					if not contact_status.is_empty():
						_apply_player_status(contact_status, 4.6)
				if enemy_type != EnemyType.BOSS and index < enemies.size():
					_destroy_enemy(index, false)
					continue
		index += 1


func _enemy_contact_is_dangerous(enemy: Dictionary) -> bool:
	match int(enemy["type"]):
		EnemyType.RAM:
			return int(enemy.get("ram_state", RamState.STALK)) == RamState.CHARGE and not bool(enemy.get("dash_hit", false))
		EnemyType.REWINDER:
			return int(enemy.get("rewind_state", RewindState.ROAM)) == RewindState.REWIND and not bool(enemy.get("dash_hit", false))
		_:
			return true


func _segment_hits_player(from_position: Vector2, to_position: Vector2, combined_radius: float) -> bool:
	var segment := to_position - from_position
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return from_position.distance_squared_to(player.position) <= combined_radius * combined_radius
	var projection := clampf((player.position - from_position).dot(segment) / length_squared, 0.0, 1.0)
	var nearest := from_position + segment * projection
	return nearest.distance_squared_to(player.position) <= combined_radius * combined_radius


func _ram_wall_impact(origin: Vector2, rotation_offset: float) -> void:
	_fire_ring(origin, 10, 168.0, rotation_offset, Color(0.94, 0.32, 0.48))
	_spawn_ripple(origin, Color(1.0, 0.61, 0.26), 26.0, 430.0, 0.62, 5.0)
	_burst(origin, Color(0.98, 0.45, 0.32), 24, 270.0)
	_world_hit_stop = maxf(_world_hit_stop, 0.045)
	player.add_hit_stop(0.045)
	_shake_amount = maxf(_shake_amount, 9.0)
	_background_pulse = maxf(_background_pulse, 0.78)
	audio_director.play_sfx(&"kill", 0.62, -5.0)
	if objective_tracker.objective_id == &"ram_relay":
		objective_tracker.report(&"ram_relay", 1.0)


func _fire_carver_line(enemy: Dictionary) -> void:
	var origin: Vector2 = enemy["position"]
	var direction: Vector2 = enemy.get("telegraph_direction", Vector2.DOWN)
	if direction.length_squared() < 0.01:
		direction = Vector2.DOWN
	var side := direction.rotated(PI * 0.5)
	for lane in range(-4, 5):
		var shot_origin := origin + side * float(lane) * 34.0
		_spawn_hostile(shot_origin, direction.angle(), 206.0, float(lane) * 0.012, Color(0.30, 0.68, 0.96), 1)
	_spawn_ripple(origin, Color(0.34, 0.72, 0.98), 38.0, 360.0, 0.64, 4.0)
	audio_director.play_sfx(&"act", 0.78, -5.0)


func _fire_bell_pull(enemy: Dictionary) -> void:
	var origin: Vector2 = enemy["position"]
	var affected := 0
	for shot in hostile_shots:
		var offset := Vector2(shot["position"]) - origin
		if offset.length_squared() > 420.0 * 420.0 or offset.length_squared() < 16.0:
			continue
		var tangent := offset.normalized().rotated(PI * 0.5)
		var speed := maxf(92.0, Vector2(shot["velocity"]).length())
		shot["velocity"] = Vector2(shot["velocity"]).lerp(tangent * speed, 0.72)
		affected += 1
	_fire_ring(origin, 12, 112.0, float(enemy["age"]) * 0.22, Color(0.76, 0.42, 0.92))
	_spawn_ripple(origin, Color(0.74, 0.46, 0.96), 48.0, 540.0, 0.86, 6.0)
	_show_event("引潮铃", "花瓣被牵成旋转带 · 顺着钟弧收下")
	audio_director.play_sfx(&"boss", 0.56 + minf(0.18, float(affected) * 0.004), -6.0)


func _fire_moth_echo(enemy: Dictionary) -> void:
	var origin: Vector2 = enemy["position"]
	var count := clampi(int(enemy.get("echo_count", 8)), 6, 18)
	_fire_ring(origin, count, 94.0, float(enemy["age"]) * -0.18, Color(0.42, 0.88, 0.72))
	_spawn_ripple(origin, Color(0.46, 0.92, 0.76), 34.0, 310.0, 0.72, 4.0)
	_show_event("回声复唱", "上一轮 %d 枚返光，化成下一轮弹药" % count)
	audio_director.play_sfx(&"release", 0.66, -5.0)


func _fire_herald(enemy: Dictionary, variant: int) -> void:
	var origin: Vector2 = enemy["position"]
	var aim := (player.position - origin).angle()
	match variant:
		1:
			for spread in [-0.28, 0.0, 0.28]:
				_spawn_hostile(origin, aim + spread, 158.0, spread * 0.14, Color(0.78, 0.27, 0.68), 0)
		2:
			for offset in [-PI * 0.5, 0.0, PI * 0.5]:
				_spawn_hostile(origin, aim + offset, 172.0, 0.18 if offset <= 0.0 else -0.18, Color(0.47, 0.38, 0.84), 1)
		3:
			for spread in [-0.40, -0.20, 0.0, 0.20, 0.40]:
				_spawn_hostile(origin, aim + spread, 150.0 + absf(spread) * 54.0, -spread * 0.22, Color(0.62, 0.31, 0.80), 0)
		_:
			_spawn_hostile(origin, aim, 214.0, sin(float(enemy["age"])) * 0.12, Color(0.94, 0.25, 0.54), 0)
			_spawn_hostile(origin, aim + PI, 156.0, -0.22, Color(0.44, 0.43, 0.86), 1)


func _update_boss_fire(enemy: Dictionary) -> void:
	var hp_ratio := float(enemy["health"]) / float(enemy["max_health"])
	var age: float = float(enemy["age"])
	var target_phase := 3 if hp_ratio <= 0.34 else (2 if hp_ratio <= 0.67 else 1)
	if target_phase > int(enemy.get("boss_phase", 1)):
		enemy["boss_phase"] = target_phase
		_boss_phase_shift(target_phase, enemy["position"])
	var boss_phase := int(enemy.get("boss_phase", 1))
	var boss_id := StringName(enemy.get("boss_id", &"ink_moon"))
	var variant := int(enemy.get("boss_variant", 0))
	if float(enemy["shoot"]) <= 0.0 and age > 2.5:
		if boss_id == &"red_wheel_king" or boss_id == &"four_second_well":
			_boss_fire_locked_lines(enemy, boss_phase, hp_ratio)
		elif boss_id == &"reverse_tide_bell" or boss_id == &"petal_mother" or boss_id == &"mirror_crown":
			_boss_fire_bell_orbit(enemy, boss_phase, hp_ratio)
		elif boss_id == &"nameless_sun" or boss_id == &"hundred_fold_night":
			_boss_fire_nameless(enemy, boss_phase, hp_ratio)
		elif variant % 3 == 1:
			_boss_fire_locked_lines(enemy, boss_phase, hp_ratio)
		elif variant % 3 == 2:
			_boss_fire_bell_orbit(enemy, boss_phase, hp_ratio)
		else:
			_boss_fire_ink(enemy, boss_phase, hp_ratio)
	if float(enemy["special"]) <= 0.0 and age > 3.0:
		var count := 18 + boss_phase * 5
		if boss_id == &"nameless_sun":
			count = clampi(_last_release_count, 12, 28)
			enemy["last_echo_count"] = count
			_show_event("日轮复写", "你上一轮的 %d 枚返光正在回潮" % count)
		elif boss_id == &"reverse_tide_bell":
			_fire_bell_pull(enemy)
			_show_event("逆潮晚钟", "当前弹带会在四秒后再响一次")
		elif boss_id == &"four_second_well":
			_show_event("四秒井回响", "旧路两端同时开花")
		_fire_ring(enemy["position"], count, 126.0 + (1.0 - hp_ratio) * 42.0, age * (0.25 if variant % 2 == 0 else -0.23), current_mission.accent if current_mission != null else Color(0.78, 0.24, 0.61), &"wet_ink" if boss_phase >= 3 and variant % 3 == 0 else &"", 4.6)
		_spawn_ripple(enemy["position"], current_mission.accent if current_mission != null else Color(0.88, 0.22, 0.58), 42.0, 360.0, 0.95, 5.0)
		enemy["special"] = 4.45 - float(boss_phase) * 0.46
		audio_director.play_sfx(&"act", 0.68, -5.0)
		_shake_amount = maxf(_shake_amount, 8.0)


func _boss_fire_ink(enemy: Dictionary, boss_phase: int, hp_ratio: float) -> void:
	var age := float(enemy["age"])
	var base_angle := age * (1.15 + float(boss_phase) * 0.34)
	_spawn_hostile(enemy["position"], base_angle, 158.0 + (1.0 - hp_ratio) * 48.0, 0.22, Color(0.86, 0.22, 0.58), 1)
	_spawn_hostile(enemy["position"], -base_angle + PI, 148.0 + (1.0 - hp_ratio) * 55.0, -0.18, Color(0.40, 0.42, 0.88), 1)
	if boss_phase >= 2:
		var aim := (player.position - Vector2(enemy["position"])).angle()
		for spread in range(-boss_phase + 1, boss_phase):
			_spawn_hostile(enemy["position"], aim + float(spread) * 0.16, 218.0 + boss_phase * 12.0, sin(age) * 0.08, Color(0.95, 0.40, 0.50), 0, &"veiled_fold", 4.8)
	enemy["shoot"] = 0.12 if boss_phase >= 3 else (0.16 if boss_phase == 2 else 0.20)


func _boss_fire_locked_lines(enemy: Dictionary, boss_phase: int, hp_ratio: float) -> void:
	var origin: Vector2 = enemy["position"]
	var aim := (player.position - origin).angle()
	var lanes := 3 + boss_phase * 2
	for lane in lanes:
		var offset := (float(lane) - float(lanes - 1) * 0.5) * 0.13
		_spawn_hostile(origin, aim + offset, 184.0 + (1.0 - hp_ratio) * 52.0, -offset * 0.10, Color(0.98, 0.45, 0.28), 0, &"bound_crease" if boss_phase >= 3 and lane == lanes / 2 else &"", 4.2)
	enemy["shoot"] = 0.54 - float(boss_phase) * 0.07


func _boss_fire_bell_orbit(enemy: Dictionary, boss_phase: int, hp_ratio: float) -> void:
	var age := float(enemy["age"])
	var origin: Vector2 = enemy["position"]
	for pair in 2 + boss_phase:
		var angle := age * (0.72 + boss_phase * 0.14) + float(pair) * TAU / float(2 + boss_phase)
		_spawn_hostile(origin, angle, 132.0 + (1.0 - hp_ratio) * 46.0, 0.24 if pair % 2 == 0 else -0.24, Color(0.66, 0.42, 0.94), 1)
	if boss_phase >= 2:
		var aim := (player.position - origin).angle()
		_spawn_hostile(origin, aim, 216.0, sin(age) * 0.10, Color(0.42, 0.88, 0.78), 0)
	enemy["shoot"] = 0.30 if boss_phase >= 3 else 0.38


func _boss_fire_nameless(enemy: Dictionary, boss_phase: int, hp_ratio: float) -> void:
	var age := float(enemy["age"])
	var origin: Vector2 = enemy["position"]
	var spokes := 2 + boss_phase
	for spoke in spokes:
		var angle := -PI * 0.5 + sin(age * 0.72 + spoke) * 0.72 + float(spoke - spokes / 2) * 0.20
		_spawn_hostile(origin, angle, 176.0 + (1.0 - hp_ratio) * 58.0, 0.08 if spoke % 2 == 0 else -0.08, Color(1.0, 0.62, 0.28), 0)
	enemy["shoot"] = 0.24 if boss_phase >= 3 else 0.32


func _boss_phase_shift(new_phase: int, origin: Vector2) -> void:
	hostile_shots.clear()
	player.grant_invulnerability(0.8)
	_world_hit_stop = 0.085
	player.add_hit_stop(0.085)
	var boss_name := current_mission.boss_title if current_mission != null else "墨月"
	var accent := current_mission.accent if current_mission != null else Color(0.92, 0.30, 0.56)
	_show_event("%s裂相 · %d" % [boss_name, new_phase], "弹幕散去 · 安全窗正在展开")
	_spawn_ripple(origin, accent.lerp(Color(1.0, 0.70, 0.28), 0.42), 62.0, 660.0, 1.0, 8.0)
	_burst(origin, accent, 70, 390.0)
	if current_mission_index < 4 and new_phase == 2:
		_spawn_enemy(EnemyType.FAN, true)
		enemies[-1]["position"] = Vector2(310.0, 270.0)
		_spawn_enemy(EnemyType.MIRROR, true)
		enemies[-1]["position"] = Vector2(1610.0, 270.0)
		enemies[-1]["mirror_state"] = int(MirrorState.FOLD)
		enemies[-1]["mirror_timer"] = 2.1
	elif current_mission_index < 4 and new_phase == 3:
		for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
			var bloom_position := Vector2(960.0, 520.0) + Vector2.from_angle(angle) * 430.0
			_spawn_enemy(EnemyType.BLOOMER, false)
			enemies[-1]["position"] = bloom_position
	elif current_mission_index < 8 and new_phase == 2:
		_spawn_enemy(EnemyType.CARVER, true)
		enemies[-1]["position"] = Vector2(300.0, 330.0)
		_spawn_enemy(EnemyType.BELL, true)
		enemies[-1]["position"] = Vector2(1620.0, 330.0)
	elif current_mission_index < 8 and new_phase == 3:
		_spawn_enemy(EnemyType.RAM, true)
		enemies[-1]["position"] = Vector2(220.0, 620.0)
		_spawn_enemy(EnemyType.MOTH, true)
		enemies[-1]["position"] = Vector2(1700.0, 620.0)
	elif new_phase == 2:
		_spawn_enemy(EnemyType.THIEF, true)
		_spawn_enemy(EnemyType.MOTH, true)
		enemies[-1]["position"] = Vector2(1560.0, 360.0)
	elif new_phase == 3:
		_spawn_enemy(EnemyType.REWINDER, true)
		enemies[-1]["position"] = Vector2(310.0, 350.0)
		_spawn_enemy(EnemyType.CARVER, true)
		enemies[-1]["position"] = Vector2(1610.0, 350.0)
	audio_director.play_sfx(&"boss", 1.0 + new_phase * 0.08)
	_shake_amount = 25.0


func _fire_drifter(enemy: Dictionary) -> void:
	var aim := (player.position - Vector2(enemy["position"])).angle()
	if bool(enemy["elite"]):
		for spread in [-0.17, 0.0, 0.17]:
			_spawn_hostile(enemy["position"], aim + spread, 174.0, spread * 0.25, Color(0.71, 0.25, 0.65), 0)
	else:
		_spawn_hostile(enemy["position"], aim, 160.0, 0.0, Color(0.68, 0.27, 0.70), 0)


func _fire_fan(enemy: Dictionary) -> void:
	var aim := (player.position - Vector2(enemy["position"])).angle()
	var count := 7 if bool(enemy["elite"]) else 5
	for shot_index in count:
		var offset := (float(shot_index) - float(count - 1) * 0.5) * 0.19
		_spawn_hostile(enemy["position"], aim + offset, 152.0 + absf(offset) * 44.0, offset * 0.08, Color(0.82, 0.25, 0.61), 0)


func _fire_weaver(enemy: Dictionary) -> void:
	var age: float = float(enemy["age"])
	var angle := age * 2.08 + float(enemy["phase"])
	_spawn_hostile(enemy["position"], angle, 146.0, 0.31, Color(0.47, 0.37, 0.83), 1, &"veiled_fold", 5.2)
	if bool(enemy["elite"]):
		_spawn_hostile(enemy["position"], angle + PI, 146.0, -0.31, Color(0.47, 0.37, 0.83), 1, &"veiled_fold", 5.2)


func _fire_weaver_seal(enemy: Dictionary) -> void:
	var origin: Vector2 = enemy["position"]
	var aim := (player.position - origin).angle()
	var count := 5 if bool(enemy["elite"]) else 3
	for shot_index in count:
		var offset := (float(shot_index) - float(count - 1) * 0.5) * 0.22
		_spawn_sealed_hostile(origin, aim + offset, 208.0 + absf(offset) * 38.0, -offset * 0.08)
	_spawn_ripple(origin, Color(1.0, 0.48, 0.20), 34.0, 280.0, 0.48, 4.0)
	_burst(origin, Color(1.0, 0.46, 0.18), 14, 185.0)
	audio_director.play_sfx(&"act", 1.34, -5.0)
	_rumble(0.18, 0.10, 0.08)


func _fire_herald_seal(enemy: Dictionary) -> void:
	var origin: Vector2 = enemy["position"]
	var aim := (player.position - origin).angle() + PI / 6.0
	for shot_index in 6:
		var angle := aim + float(shot_index) * TAU / 6.0
		_spawn_sealed_hostile(origin, angle, 226.0, 0.045 if shot_index % 2 == 0 else -0.045)
	_spawn_ripple(origin, Color(1.0, 0.42, 0.18), 58.0, 390.0, 0.62, 5.0)
	_burst(origin, Color(1.0, 0.52, 0.22), 26, 250.0)
	audio_director.play_sfx(&"boss", 1.26, -4.0)
	_shake_amount = maxf(_shake_amount, 10.0)
	_rumble(0.32, 0.20, 0.12)


func _fire_ring(origin: Vector2, count: int, speed: float, rotation_offset: float, color: Color, status_id: StringName = &"", status_duration: float = 0.0) -> void:
	for shot_index in count:
		var angle := rotation_offset + float(shot_index) * TAU / float(count)
		_spawn_hostile(origin, angle, speed, sin(float(shot_index) * 1.7) * 0.055, color, 1, status_id, status_duration)


func _spawn_sealed_hostile(origin: Vector2, angle: float, speed: float, curve: float = 0.0) -> void:
	_spawn_hostile(origin, angle, speed, curve, Color(1.0, 0.42, 0.16), 2, &"", 0.0, false, &"paper_seal")


func _spawn_hostile(origin: Vector2, angle: float, speed: float, curve: float, color: Color, kind: int, status_id: StringName = &"", status_duration: float = 0.0, reflectable: bool = true, skill_id: StringName = &"") -> void:
	if hostile_shots.size() >= HOSTILE_CAP:
		return
	hostile_shots.append({
		"position": origin,
		"velocity": Vector2.from_angle(angle) * speed,
		"curve": curve,
		"color": color,
		"kind": kind,
		"age": 0.0,
		"life": 11.0,
		"radius": 10.0 if kind == 0 else 8.5,
		"status": status_id,
		"status_duration": status_duration,
		"reflectable": reflectable,
		"skill": skill_id,
	})


func _update_hostile_shots(delta: float) -> void:
	var index := 0
	while index < hostile_shots.size():
		var shot: Dictionary = hostile_shots[index]
		shot["age"] = float(shot["age"]) + delta
		shot["life"] = float(shot["life"]) - delta
		var position_value: Vector2 = shot["position"]
		var velocity_value: Vector2 = shot["velocity"]
		velocity_value = velocity_value.rotated(float(shot["curve"]) * delta)
		if _ritual_event_kind == 3 and _ritual_event_timer > 0.0:
			velocity_value.x += 42.0 * delta
		if _challenge_active:
			velocity_value.x += challenge_director.get_crosswind_force() * delta
		var modifier := _current_modifier_id()
		if modifier == &"crosswind_east":
			velocity_value.x += 28.0 * delta
		elif modifier == &"crosswind_west":
			velocity_value.x -= 28.0 * delta
		elif modifier == &"crosswind_flip":
			velocity_value.x += sin(act_time * 0.42) * 36.0 * delta
		var motion_scale := 1.0
		if player.folding:
			var fold_radius := player.get_fold_radius()
			var distance := position_value.distance_to(player.position)
			if distance < fold_radius:
				motion_scale = clampf(lerpf(0.10, 0.36, distance / maxf(1.0, fold_radius)) * _fold_slow_multiplier, 0.055, 0.42)
				if bool(shot.get("reflectable", true)) and player.capture_one():
					_on_capture(position_value)
					hostile_shots.remove_at(index)
					continue
		var shot_speed_scale := 1.0
		if current_mission != null:
			shot_speed_scale = clampf(0.97 + (current_mission.difficulty - 1.0) * 0.09, 0.96, 1.08)
		if _mission_assisted:
			shot_speed_scale *= 0.90
		if _sea_mirror_timer > 0.0:
			shot_speed_scale *= 0.62
		if _challenge_active:
			shot_speed_scale *= challenge_director.get_shot_speed_scale()
		position_value += velocity_value * delta * motion_scale * shot_speed_scale
		shot["position"] = position_value
		shot["velocity"] = velocity_value
		hostile_shots[index] = shot

		var hit_radius := float(shot["radius"]) + player.get_hit_radius()
		if position_value.distance_squared_to(player.position) < hit_radius * hit_radius:
			hostile_shots.remove_at(index)
			if player.take_hit():
				var hurt_applied := _on_player_hurt()
				var status_id := StringName(shot.get("status", &""))
				if hurt_applied and player.health > 0 and status_id != &"":
					_apply_player_status(status_id, float(shot.get("status_duration", 0.0)))
			continue
		var removal_bounds := _current_arena_bounds().grow(170.0)
		if float(shot["life"]) <= 0.0 or not removal_bounds.has_point(position_value):
			hostile_shots.remove_at(index)
			continue
		index += 1


func _on_capture(position_value: Vector2) -> void:
	score += 6 + combo
	total_captures += 1
	_captures_since_bonus += 1
	_background_energy = minf(1.0, _background_energy + 0.012)
	_background_pulse = maxf(_background_pulse, 0.10)
	combo = mini(99, maxi(combo, player.captured))
	combo_timer = 3.2
	_burst(position_value, Color(0.98, 0.72, 0.30), 6, 125.0)
	_spawn_ripple(position_value, Color(0.33, 0.88, 0.84), 7.0, 66.0, 0.28, 2.0)
	if _capture_sound_cooldown <= 0.0:
		_capture_sound_cooldown = 0.055
		audio_director.play_sfx(&"capture", 0.88 + float(player.captured) * 0.025, -4.0)
	if _golden_seam and _captures_since_bonus >= 8:
		_captures_since_bonus = 0
		_spawn_bonus_return_light(position_value)


func _on_fold_started() -> void:
	if _rogue_mode_active:
		return
	audio_director.play_sfx(&"fold", 1.0, -2.0)
	_spawn_ripple(player.position, Color(0.34, 0.91, 0.86), 32.0, 168.0, 0.42, 3.0)


func _on_fold_released(captured_count: int, charge_ratio: float) -> void:
	if _rogue_mode_active:
		return
	if _tutorial_active and captured_count >= 3:
		_tutorial_release_success = true
	if _crease_rebuke and charge_ratio >= 0.12:
		var release_radius := lerpf(FoldlightPlayer.FOLD_RADIUS_MIN, FoldlightPlayer.FOLD_RADIUS_MAX, ease(charge_ratio, 0.55))
		release_radius *= player.fold_radius_multiplier * player.temporary_fold_radius_multiplier
		_damage_charging_enemies_on_fold_boundary(release_radius)
	_release_captured_light(captured_count, charge_ratio)


func _on_focus_empty(captured_count: int, charge_ratio: float) -> void:
	if _rogue_mode_active:
		return
	if _tutorial_active and captured_count >= 3:
		_tutorial_release_success = true
	_release_captured_light(captured_count, charge_ratio)
	hud.flash(Color(0.90, 0.24, 0.52), 0.13)


func _damage_charging_enemies_on_fold_boundary(radius: float) -> int:
	var hits := 0
	for enemy_index in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[enemy_index]
		var enemy_type := int(enemy.get("type", EnemyType.DRIFTER))
		var charging := enemy_type == EnemyType.RAM and int(enemy.get("ram_state", RamState.STALK)) == RamState.CHARGE
		charging = charging or (enemy_type == EnemyType.REWINDER and int(enemy.get("rewind_state", RewindState.ROAM)) == RewindState.REWIND)
		if not charging:
			continue
		var from_position: Vector2 = enemy.get("position", Vector2.ZERO)
		var velocity_value: Vector2 = enemy.get("velocity", Vector2.ZERO)
		var to_position := from_position + velocity_value * 0.16
		var thickness := float(enemy.get("radius", 32.0)) + 13.0
		if not _segment_crosses_circle_boundary(from_position, to_position, player.position, radius, thickness):
			continue
		if enemy_type == EnemyType.RAM:
			enemy["ram_state"] = int(RamState.RECOVER)
			enemy["ram_timer"] = 1.05
		else:
			enemy["rewind_state"] = int(RewindState.RECOVER)
			enemy["rewind_timer"] = 1.05
		enemy["velocity"] = velocity_value * 0.12
		enemies[enemy_index] = enemy
		_damage_enemy(enemy_index, 5, from_position, false)
		_spawn_ripple(from_position, Color(1.0, 0.48, 0.70), 22.0, 250.0, 0.48, 4.0)
		hits += 1
	if hits > 0:
		_show_event("折界反刺", "冲撞穿界受创 · 破绽已打开")
		audio_director.play_sfx(&"kill", 0.78, -3.0)
		_shake_amount = maxf(_shake_amount, 10.0)
	return hits


func _segment_crosses_circle_boundary(from_position: Vector2, to_position: Vector2, center: Vector2, radius: float, thickness: float) -> bool:
	var from_delta := from_position.distance_to(center) - radius
	var to_delta := to_position.distance_to(center) - radius
	if absf(from_delta) <= thickness or absf(to_delta) <= thickness:
		return true
	return signf(from_delta) != signf(to_delta)


func _release_captured_light(captured_count: int, charge_ratio: float) -> void:
	if captured_count <= 0:
		audio_director.play_sfx(&"empty")
		_spawn_ripple(player.position, Color(0.65, 0.68, 0.76), 46.0, 125.0, 0.34, 2.0)
		return
	_last_release_count = captured_count
	if _sea_mirror and captured_count >= 10:
		_sea_mirror_timer = 2.0
		_show_event("海镜潮域", "整片敌弹短暂放缓")
	if _ocean_memory and captured_count >= 12:
		player.add_focus(0.14)
	objective_tracker.report(&"large_release", 1.0, {"volley_size": captured_count, "required_volley": 12})
	if objective_tracker.objective_id == &"beacon_charge":
		for anchor in _objective_anchors:
			if player.position.distance_to(anchor) <= 310.0:
				objective_tracker.report(&"beacon_charge", float(captured_count))
				_spawn_ripple(anchor, current_mission.accent, 30.0, 270.0, 0.55, 4.0)
				break
	elif objective_tracker.objective_id == &"cleanse" and captured_count >= 10 and charge_ratio >= 0.72:
		objective_tracker.report(&"cleanse", 1.0)
	elif objective_tracker.objective_id == &"escort" and player.position.distance_to(_escort_position) <= 330.0:
		objective_tracker.report(&"escort_repair", float(captured_count) * 0.75)
		_escort_integrity = minf(1.0, _escort_integrity + float(captured_count) * 0.012)
	_background_energy = minf(1.0, _background_energy + float(captured_count) * 0.018)
	_background_pulse = maxf(_background_pulse, minf(1.0, 0.22 + float(captured_count) * 0.035))
	var arc_span := minf(TAU * 0.76, 0.33 * float(captured_count))
	var synergy_damage := 0
	if _needle_light and captured_count <= 4 and charge_ratio >= 0.92:
		synergy_damage += 2
	if _walking_lantern and player.velocity.length() >= FoldlightPlayer.MOVE_SPEED * player.move_speed_multiplier * 0.72:
		synergy_damage += 1
	for light_index in captured_count:
		var t := 0.5 if captured_count == 1 else float(light_index) / float(captured_count - 1)
		var angle := -PI * 0.5 - arc_span * 0.5 + t * arc_span
		return_lights.append({
			"position": player.position + Vector2.from_angle(angle) * 54.0,
			"velocity": Vector2.from_angle(angle) * (190.0 + charge_ratio * 80.0) * _return_speed_multiplier,
			"angle": angle,
			"orbit": 54.0 + float(light_index % 4) * 7.0,
			"delay": float(light_index) * 0.035,
			"age": 0.0,
			"life": 5.6,
			"power": _return_damage + synergy_damage,
			"volley_size": captured_count,
		})
	if _full_moon and captured_count >= 12:
		player.add_focus(0.22)
		player.grant_invulnerability(0.55 if _starfall_mastery else 0.35)
		_show_event("满月回息", "折域回充 · 短暂无伤")
	combo = mini(99, maxi(combo, captured_count))
	combo_timer = 4.4
	score += captured_count * 10
	_spawn_ripple(player.position, Color(1.0, 0.72, 0.28), 52.0, 420.0 + charge_ratio * 120.0, 0.78, 6.0)
	_burst(player.position, Color(0.95, 0.78, 0.42), 18 + captured_count, 260.0)
	audio_director.play_sfx(&"release", 0.9 + minf(0.35, float(captured_count) * 0.015))
	_shake_amount = minf(16.0, 4.0 + float(captured_count) * 0.55)
	_world_hit_stop = minf(0.072, 0.030 + float(captured_count) * 0.0018)
	player.add_hit_stop(_world_hit_stop)
	_rumble(0.16 + float(captured_count) * 0.012, 0.08, 0.11)
	hud.flash(Color(0.88, 1.0, 0.78), minf(0.3, 0.08 + float(captured_count) * 0.012))


func _spawn_bonus_return_light(origin: Vector2) -> void:
	var angle := (player.position - origin).angle()
	return_lights.append({
		"position": origin,
		"velocity": Vector2.from_angle(angle) * 420.0 * _return_speed_multiplier,
		"angle": angle,
		"orbit": 0.0,
		"delay": 0.0,
		"age": 0.0,
		"life": 4.2,
		"power": _return_damage,
	})
	_burst(origin, Color(1.0, 0.76, 0.31), 12, 180.0)


func _release_mirror_volley(enemy: Dictionary) -> void:
	var stored := int(enemy.get("stored_light", 0))
	enemy["stored_light"] = 0
	if stored <= 0:
		return
	var origin: Vector2 = enemy["position"]
	var count := mini(12, stored)
	var aim := (player.position - origin).angle()
	var span := minf(1.05, 0.12 * float(count - 1))
	for shot_index in count:
		var ratio := 0.5 if count == 1 else float(shot_index) / float(count - 1)
		var offset := lerpf(-span * 0.5, span * 0.5, ratio)
		_spawn_hostile(origin, aim + offset, 186.0 + float(stored) * 3.0, -offset * 0.10, Color(0.28, 0.80, 0.82), 0, &"veiled_fold", 5.0)
	_spawn_ripple(origin, Color(0.30, 0.88, 0.86), 45.0, 410.0, 0.72, 5.0)
	_burst(origin, Color(0.42, 0.92, 0.86), 16 + count, 230.0)
	audio_director.play_sfx(&"release", 0.74, -3.0)
	_shake_amount = maxf(_shake_amount, 7.0)


func _update_return_lights(delta: float) -> void:
	var index := 0
	while index < return_lights.size():
		var light: Dictionary = return_lights[index]
		light["age"] = float(light["age"]) + delta
		light["life"] = float(light["life"]) - delta
		var position_value: Vector2 = light["position"]
		var velocity_value: Vector2 = light["velocity"]
		if float(light["delay"]) > 0.0:
			light["delay"] = float(light["delay"]) - delta
			light["angle"] = float(light["angle"]) + delta * 4.2
			position_value = player.position + Vector2.from_angle(float(light["angle"])) * float(light["orbit"])
		else:
			var target_index := _nearest_enemy_index(position_value)
			if target_index >= 0:
				var target_position: Vector2 = enemies[target_index]["position"]
				var desired := (target_position - position_value).normalized() * 610.0 * _return_speed_multiplier
				velocity_value = velocity_value.lerp(desired, minf(1.0, delta * 7.5))
			else:
				velocity_value = velocity_value.lerp(Vector2.UP * 420.0, minf(1.0, delta * 1.5))
			position_value += velocity_value * delta
		light["position"] = position_value
		light["velocity"] = velocity_value
		return_lights[index] = light
		var mirror_index := _mirror_interceptor_index(position_value)
		if mirror_index >= 0:
			var mirror: Dictionary = enemies[mirror_index]
			mirror["stored_light"] = mini(18, int(mirror.get("stored_light", 0)) + 1)
			mirror["flash"] = 0.72
			enemies[mirror_index] = mirror
			return_lights.remove_at(index)
			_burst(position_value, Color(0.36, 0.92, 0.88), 5, 92.0)
			_spawn_ripple(position_value, Color(0.34, 0.86, 0.84), 8.0, 74.0, 0.24, 2.0)
			continue

		var hit_enemy := -1
		for enemy_index in enemies.size():
			var enemy: Dictionary = enemies[enemy_index]
			var hit_radius := float(enemy["radius"]) + 12.0
			if position_value.distance_squared_to(enemy["position"]) < hit_radius * hit_radius:
				hit_enemy = enemy_index
				break
		if hit_enemy >= 0:
			return_lights.remove_at(index)
			_damage_enemy(hit_enemy, int(light["power"]), position_value, true, int(light.get("volley_size", 1)))
			continue
		if float(light["life"]) <= 0.0:
			return_lights.remove_at(index)
			continue
		index += 1


func _mirror_interceptor_index(light_position: Vector2) -> int:
	for enemy_index in enemies.size():
		var enemy: Dictionary = enemies[enemy_index]
		if int(enemy["type"]) != EnemyType.MIRROR:
			continue
		if int(enemy.get("mirror_state", MirrorState.SEEK)) != MirrorState.FOLD:
			continue
		var intercept_radius := 138.0 + minf(24.0, float(enemy.get("stored_light", 0)) * 2.0)
		if light_position.distance_squared_to(enemy["position"]) <= intercept_radius * intercept_radius:
			return enemy_index
	return -1


func _nearest_enemy_index(from_position: Vector2) -> int:
	var best_index := -1
	var best_distance := INF
	for index in enemies.size():
		var distance := from_position.distance_squared_to(enemies[index]["position"])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _damage_enemy(index: int, damage: int, hit_position: Vector2, from_return: bool = true, volley_size: int = 1) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: Dictionary = enemies[index]
	var enemy_type := int(enemy["type"])
	if from_return:
		var affix := int(enemy.get("affix", 0)) if enemy_type < EnemyType.HERALD else 0
		if affix == 6 and int(enemy.get("return_shield", 0)) > 0:
			enemy["return_shield"] = int(enemy.get("return_shield", 0)) - 1
			enemy["flash"] = 0.65
			enemies[index] = enemy
			_show_event("吞光折印", "再返 %d 枚即可打开破绽" % int(enemy["return_shield"]))
			_burst(hit_position, Color(0.72, 0.42, 0.90), 6, 110.0)
			return
		if affix == 3 and volley_size < 4:
			enemy["flash"] = 0.48
			enemies[index] = enemy
			_show_event("复纸护层", "同一轮至少四枚返光才能穿透")
			return
		objective_tracker.report(&"return_hit", float(damage), {"near_anchor": _near_objective_anchor(hit_position)})
		if enemy_type == EnemyType.RAM and int(enemy.get("ram_state", RamState.STALK)) == RamState.RECOVER:
			damage += 1
		elif enemy_type == EnemyType.REWINDER and int(enemy.get("rewind_state", RewindState.ROAM)) == RewindState.RECOVER:
			damage += 1
	enemy["health"] = int(enemy["health"]) - damage
	enemy["flash"] = 1.0
	enemies[index] = enemy
	score += 14 * damage + combo
	_burst(hit_position, Color(1.0, 0.78, 0.34), 3, 120.0)
	player.feedback_budget.register_impact(clampf(0.16 + float(damage) * 0.08, 0.16, 0.52), false)
	if int(enemy["health"]) <= 0:
		_destroy_enemy(index, true, from_return)


func _destroy_enemy(index: int, award_score: bool, from_return: bool = false) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: Dictionary = enemies[index]
	var enemy_type := int(enemy["type"])
	var position_value: Vector2 = enemy["position"]
	var was_boss := enemy_type == EnemyType.BOSS
	var was_herald := enemy_type == EnemyType.HERALD
	var affix := int(enemy.get("affix", 0))
	_background_energy = minf(1.0, _background_energy + (0.24 if enemy_type >= EnemyType.HERALD else 0.045))
	_background_pulse = maxf(_background_pulse, 1.0 if was_boss else (0.72 if was_herald else 0.24))
	enemies.remove_at(index)
	_burst(position_value, Color(0.92, 0.43, 0.58), 56 if was_boss else (36 if was_herald else 18), 340.0 if was_boss else 210.0)
	_spawn_ripple(position_value, Color(1.0, 0.70, 0.28), 20.0, 520.0 if was_boss else (390.0 if was_herald else 210.0), 1.0 if was_boss else 0.55, 7.0 if was_boss else 3.0)
	if award_score:
		var values: Array[int] = [120, 220, 330, 460, 540, 620, 760, 900, 980, 1080, 900, 960, 1800, 5000]
		combo = mini(99, combo + 1)
		combo_timer = 4.2
		score += values[enemy_type] * maxi(1, mini(8, combo))
		total_kills += 1
		if from_return:
			objective_tracker.report(&"return_kill", 1.0, {"required_chain": 5})
			if _sun_chain and not was_boss and not was_herald:
				_return_kill_chain += 1
				if _return_kill_chain >= 5:
					_return_kill_chain = 0
					_spawn_bonus_return_light(position_value)
					_show_event("日链重返", "第五次返光击杀再次折回")
	if enemy_type == EnemyType.THIEF and award_score:
		objective_tracker.report(&"courier_destroyed", 1.0)
		_fire_ring(position_value, 14, 106.0, _ambient_time, Color(1.0, 0.64, 0.28))
		_show_event("名字截回", "盗名舟化成一整圈返航弹药")
	if affix == 5 and not was_boss and not was_herald:
		_fire_ring(position_value, 8, 116.0, _ambient_time, Color(0.92, 0.50, 0.66))
	if _chain_bloom and from_return and not was_boss:
		for split in [-0.34, 0.34]:
			return_lights.append({
				"position": position_value,
				"velocity": Vector2.from_angle(-PI * 0.5 + split) * 330.0 * _return_speed_multiplier,
				"angle": -PI * 0.5 + split,
				"orbit": 0.0,
				"delay": 0.04,
				"age": 0.0,
				"life": 3.8,
				"power": maxi(1, _return_damage - 1),
			})
	_feedback_kills_pending += 1
	player.feedback_budget.register_impact(1.0 if was_boss or was_herald else 0.62, was_boss or was_herald)
	if was_boss:
		_shake_amount = maxf(_shake_amount, 18.0)
	if was_boss:
		_win_run()
	elif was_herald:
		_open_technique_seal(act + 1)


func _on_feedback_impact_batch(weight: float, count: int) -> void:
	if _rogue_mode_active:
		return
	var pitch := clampf(0.88 + weight * 0.18 + minf(0.08, float(count) * 0.004), 0.88, 1.14)
	if _feedback_kills_pending > 0:
		audio_director.play_sfx(&"kill", pitch, -4.5)
	else:
		audio_director.play_sfx(&"hit", pitch, -7.0)
	_shake_amount = maxf(_shake_amount, minf(4.0, 0.5 + weight * 2.4))
	_feedback_kills_pending = 0


func _on_feedback_hit_stop(duration: float) -> void:
	if _rogue_mode_active:
		return
	_world_hit_stop = maxf(_world_hit_stop, minf(duration, player.feedback_budget.maximum_hit_stop))


func _on_player_hurt() -> bool:
	if _mercy_charges > 0:
		_mercy_charges -= 1
		player.health = mini(player.max_health, player.health + 1)
		player.grant_invulnerability(1.6)
		_show_event("留白", "这一击没有留下折痕")
		audio_director.play_sfx(&"act", 1.35, -4.0)
		_spawn_ripple(player.position, Color(0.94, 0.88, 0.62), 30.0, 430.0, 0.7, 5.0)
		if _mercy_fire:
			_release_captured_light(8, 1.0)
		return false
	_run_hits += 1
	combo = 0
	combo_timer = 0.0
	_shake_amount = 22.0
	hud.flash(Color(0.96, 0.18, 0.38), 0.55)
	audio_director.play_sfx(&"hurt")
	_rumble(0.72, 0.45, 0.22)
	_burst(player.position, Color(0.94, 0.25, 0.45), 28, 280.0)
	_spawn_ripple(player.position, Color(0.94, 0.22, 0.46), 20.0, 310.0, 0.65, 5.0)
	# Mercy clear prevents unavoidable repeat hits without erasing the whole pattern.
	var index := hostile_shots.size() - 1
	while index >= 0:
		if Vector2(hostile_shots[index]["position"]).distance_to(player.position) < 150.0:
			hostile_shots.remove_at(index)
		index -= 1
	if player.health <= 0:
		_lose_run()
	return true


func _contact_status_for_enemy(enemy_type: int) -> StringName:
	match enemy_type:
		EnemyType.RAM: return &"bound_crease"
		EnemyType.LEECH: return &"wet_ink"
		EnemyType.MIRROR: return &"veiled_fold"
		_: return &""


func _apply_player_status(status_id: StringName, duration: float) -> void:
	if status_id == &"" or not player.apply_status(status_id, duration):
		return
	_queue_effect_tip(status_id)
	match status_id:
		&"wet_ink": _show_event("湿墨", "折息恢复下降 · 返还 6 光洗净")
		&"bound_crease": _show_event("缚折", "移动速度下降 · 返还 3 光挣脱")
		&"veiled_fold": _show_event("墨覆", "折域缩小 · 蓄满后返还洗去")
		_: pass
	hud.flash(Color(0.72, 0.38, 0.78), 0.12)


func _on_statuses_cleansed(status_ids: Array[StringName]) -> void:
	if _rogue_mode_active:
		return
	var names: Array[String] = []
	for status_id in status_ids:
		match status_id:
			&"wet_ink": names.append("湿墨")
			&"bound_crease": names.append("缚折")
			&"veiled_fold": names.append("墨覆")
			_: pass
	_show_event("净折", "%s已洗净" % "、".join(names))
	_spawn_ripple(player.position, Color(0.54, 0.96, 0.88), 34.0, 260.0, 0.46, 4.0)
	audio_director.play_sfx(&"capture", 1.32, -2.0)
	objective_tracker.report(&"cleanse", float(status_ids.size()))


func _near_objective_anchor(position_value: Vector2) -> bool:
	for anchor in _objective_anchors:
		if position_value.distance_to(anchor) <= 260.0:
			return true
	return false


func _lose_run() -> void:
	mode = RunMode.GAME_OVER
	player.set_play_enabled(false)
	player.visible = true
	return_lights.clear()
	audio_director.set_intensity(0.04)
	_stage_timer = 0.0
	_record_profile_run(false)
	if _challenge_active:
		return
	var failure_count := int(_mission_result.get("failure_count", 1))
	if failure_count == 1 and not profile_manager.has_story_seen(&"campaign_first_fall"):
		_enqueue_briefing({
			"kind": &"story", "story_id": &"campaign_first_fall",
			"eyebrow": "折光庭 · 失航记录", "title": "折痕不会白白留下",
			"body": "岑从夜潮里捞回熄灭的纸灯。最近的潮界已经保存，下一次只需从这一道折痕继续。",
			"counter": "引灯人 · 岑", "accent": Color(0.42, 0.82, 0.84),
		}, RunMode.GAME_OVER)


func _win_run() -> void:
	mode = RunMode.VICTORY
	player.set_play_enabled(false)
	hostile_shots.clear()
	return_lights.clear()
	_stage_timer = 0.0
	var performance := score + player.health * 1800 + total_captures * 18
	if performance >= 47000:
		rank = "S"
	elif performance >= 30000:
		rank = "A"
	elif performance >= 18000:
		rank = "B"
	else:
		rank = "C"
	if _mission_assisted and (rank == "S" or rank == "A"):
		rank = "B"
	audio_director.set_intensity(0.08)
	audio_director.play_sfx(&"victory")
	hud.flash(Color(1.0, 0.88, 0.52), 0.72)
	for burst_index in 9:
		var origin := Vector2(_rng.randf_range(260.0, 1660.0), _rng.randf_range(220.0, 850.0))
		_burst(origin, Color.from_hsv(_rng.randf_range(0.09, 0.48), 0.42, 1.0), 22, 250.0)
	_record_profile_run(true)
	if current_mission != null:
		var ending_id := StringName("mission:%s:ending" % current_mission.mission_id)
		if not profile_manager.has_story_seen(ending_id):
			_enqueue_briefing({
				"kind": &"story", "story_id": ending_id,
				"eyebrow": "%s · 尾声" % current_mission.chapter_title,
				"title": current_mission.ending_title,
				"body": current_mission.ending_body,
				"counter": "%s完成" % current_mission.title, "accent": current_mission.accent,
			}, RunMode.VICTORY)
	elif not profile_manager.has_story_seen(&"c1_dawn"):
		_enqueue_briefing({
			"kind": &"story", "story_id": &"c1_dawn",
			"eyebrow": "第一章 · 尾声", "title": "港口重新拥有名字",
			"body": "墨月碎成一场温暖的雨。纸海仍然辽阔，但远岸第一次亮起了不是敌弹的光。下一封未寄出的灯讯，正在更深处等你。",
			"counter": "第一章《残灯渡海》完成", "accent": Color(1.0, 0.76, 0.34),
		}, RunMode.VICTORY)


func _record_profile_run(won: bool) -> void:
	if _profile_recorded:
		return
	_profile_recorded = true
	if _challenge_active:
		var challenge_result := {
			"time": run_time,
			"score": score,
			"tier": challenge_director.tier,
			"events": challenge_director.events_seen,
			"drafts": _challenge_drafts,
			"kills": total_kills,
		}
		_last_glimmer_reward = profile_manager.record_challenge_run(challenge_result)
		_mission_result = challenge_result
		_mission_result["challenge"] = true
		_mission_result["glimmer_reward"] = _last_glimmer_reward
		return
	if current_mission == null:
		_last_glimmer_reward = profile_manager.record_run(won, score, rank if not rank.is_empty() else "—", run_time, total_captures, total_kills, _run_hits == 0, act)
		return
	if won:
		var result := {
			"score": score,
			"rank": rank if not rank.is_empty() else "C",
			"time": run_time,
			"captures": total_captures,
			"kills": total_kills,
			"hits": _run_hits,
			"assisted": _mission_assisted,
			"objective_failures": _objective_failures,
		}
		_last_glimmer_reward = profile_manager.record_campaign_mission(current_mission.mission_id, result)
		_mission_result = result
		_mission_result["won"] = true
		_mission_result["glimmer_reward"] = _last_glimmer_reward
	else:
		var failure_count := profile_manager.record_campaign_failure(current_mission.mission_id)
		_mission_result = {
			"won": false,
			"failure_count": failure_count,
			"checkpoint_tide": int(profile_manager.get_active_checkpoint().get("tide", 1)),
			"assist_available": failure_count >= 2 and not _mission_assisted,
		}


func _rumble(weak: float, strong: float, duration: float) -> void:
	if _last_device != &"gamepad" or not bool(profile_manager.get_setting(&"vibration", true)):
		return
	Input.start_joy_vibration(0, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


func _update_effects(delta: float) -> void:
	var particle_index := 0
	while particle_index < particles.size():
		var particle: Dictionary = particles[particle_index]
		particle["life"] = float(particle["life"]) - delta
		particle["position"] = Vector2(particle["position"]) + Vector2(particle["velocity"]) * delta
		particle["velocity"] = Vector2(particle["velocity"]) * pow(0.075, delta)
		particle["rotation"] = float(particle["rotation"]) + float(particle["spin"]) * delta
		particles[particle_index] = particle
		if float(particle["life"]) <= 0.0:
			particles.remove_at(particle_index)
			continue
		particle_index += 1
	var ripple_index := 0
	while ripple_index < ripples.size():
		var ripple: Dictionary = ripples[ripple_index]
		ripple["life"] = float(ripple["life"]) - delta
		ripple["radius"] = float(ripple["radius"]) + float(ripple["speed"]) * delta
		ripples[ripple_index] = ripple
		if float(ripple["life"]) <= 0.0:
			ripples.remove_at(ripple_index)
			continue
		ripple_index += 1


func _burst(origin: Vector2, color: Color, count: int, speed: float) -> void:
	var actual_count := mini(count, PARTICLE_CAP - particles.size())
	for index in actual_count:
		var angle := _rng.randf_range(0.0, TAU)
		var velocity_value := Vector2.from_angle(angle) * _rng.randf_range(speed * 0.24, speed)
		particles.append({
			"position": origin + Vector2.from_angle(angle) * _rng.randf_range(0.0, 16.0),
			"velocity": velocity_value,
			"life": _rng.randf_range(0.32, 0.92),
			"max_life": 0.92,
			"color": color.lerp(Color.WHITE, _rng.randf_range(0.0, 0.35)),
			"size": _rng.randf_range(2.0, 7.5),
			"rotation": angle,
			"spin": _rng.randf_range(-8.0, 8.0),
		})


func _spawn_ripple(origin: Vector2, color: Color, start_radius: float, speed: float, life: float, width: float) -> void:
	ripples.append({
		"position": origin,
		"color": color,
		"radius": start_radius,
		"speed": speed,
		"life": life,
		"max_life": life,
		"width": width,
	})


func _present_hud() -> void:
	var boss_health := 0
	var boss_max := 0
	for enemy in enemies:
		if int(enemy["type"]) == EnemyType.BOSS:
			boss_health = int(enemy["health"])
			boss_max = int(enemy["max_health"])
			break
	var progress := float(challenge_director.snapshot().get("arena_ratio", 0.0)) if _challenge_active else _act_progress(boss_health, boss_max)
	var tutorial_data := _tutorial_text()
	var mode_name: StringName = &"title"
	match mode:
		RunMode.CAMPAIGN_MAP: mode_name = &"campaign_map"
		RunMode.PLAYING: mode_name = &"playing"
		RunMode.BRIEFING: mode_name = &"briefing"
		RunMode.PAUSED: mode_name = &"paused"
		RunMode.UPGRADE: mode_name = &"upgrade"
		RunMode.SETTINGS: mode_name = &"settings"
		RunMode.ARCHIVE: mode_name = &"archive"
		RunMode.GAME_OVER: mode_name = &"game_over"
		RunMode.VICTORY: mode_name = &"victory"
		_: mode_name = &"title"
	var stage_alpha := 0.0
	if _stage_timer > 0.0:
		var elapsed := 3.5 - _stage_timer
		stage_alpha = minf(1.0, minf(elapsed / 0.42, _stage_timer / 0.72))
	var seal_snapshots: Array[Dictionary] = _empty_doctrine_snapshots
	if mode == RunMode.UPGRADE:
		seal_snapshots = []
		for doctrine in _seal_options:
			seal_snapshots.append(doctrine.to_snapshot(int(doctrine_stacks.get(String(doctrine.doctrine_id), 0))))
	var meta_catalog: Array[Dictionary] = []
	if mode == RunMode.ARCHIVE:
		meta_catalog = profile_manager.get_meta_catalog_snapshots()
	var campaign_missions: Array[Dictionary] = []
	if mode == RunMode.CAMPAIGN_MAP:
		campaign_missions = _campaign_map_snapshots()
	var event_alpha := clampf(_event_message_timer / 0.6, 0.0, 1.0)
	hud.present({
		"mode": mode_name,
		"score": score,
		"health": player.health,
		"max_health": player.max_health,
		"debug_invincible": player.is_debug_invincible(),
		"focus": player.focus,
		"captured": player.captured,
		"capacity": player.get_capture_capacity(),
		"folding": player.folding,
		"charge_ratio": player.get_charge_ratio(),
		"act": act,
		"act_name": "无尽潮压" if _challenge_active else ("新手航灯" if _tutorial_active else _current_act_name(act)),
		"act_scene_tag": "疆界展开 %03d%%" % int(round(progress * 100.0)) if _challenge_active else ("三步上手" if _tutorial_active else _current_scene_tag(act)),
		"act_objective": "活下去 · 收纳 · 构筑" if _challenge_active else ("完成移动、收纳与返光" if _tutorial_active else _current_objective_label(act)),
		"progress": progress,
		"pressure": get_pressure_level(),
		"combo": combo,
		"boss_health": boss_health,
		"boss_max": boss_max,
		"tutorial": tutorial_data[0],
		"tutorial_alpha": tutorial_data[1],
		"stage_message": _stage_message,
		"stage_subtitle": _stage_subtitle,
		"stage_alpha": stage_alpha,
		"device": _last_device,
		"muted": audio_director.is_muted(),
		"run_time": run_time,
		"rank": rank,
		"event_message": _event_message,
		"event_alpha": event_alpha,
		"seal_options": seal_snapshots,
		"seal_selected": _seal_selected,
		"path_locked": _chosen_path >= 0,
		"path_name": PATH_NAMES[_chosen_path] if _chosen_path >= 0 else "",
		"path_step": _path_step,
		"next_threat": NEXT_TIDE_THREATS[clampi(_pending_act, 0, NEXT_TIDE_THREATS.size() - 1)],
		"owned_doctrines": owned_doctrines,
		"synergies": _synergy_snapshots(),
		"status_effects": player.get_status_snapshots(),
		"enemy_tip": tip_queue.get_snapshot(&"enemy"),
		"effect_tip": tip_queue.get_snapshot(&"effect"),
		"briefing": _briefing_current,
		"briefing_queue": _briefing_queue.size(),
		"profile": profile_manager.get_public_snapshot() if mode == RunMode.TITLE or mode == RunMode.CAMPAIGN_MAP or mode == RunMode.ARCHIVE or mode == RunMode.GAME_OVER or mode == RunMode.VICTORY else {},
		"settings": profile_manager.settings if mode == RunMode.SETTINGS else {},
		"settings_selected": _settings_selected,
		"meta_catalog": meta_catalog,
		"sanctuary_selected": _sanctuary_selected,
		"glimmer_reward": _last_glimmer_reward,
		"mission": current_mission.to_map_snapshot(false, {}) if current_mission != null else {},
		"mission_index": current_mission_index,
		"mission_assisted": _mission_assisted,
		"mission_result": _mission_result,
		"objective": objective_tracker.snapshot(),
		"campaign_missions": campaign_missions,
		"campaign_selected": _campaign_selected,
		"campaign": profile_manager.get_campaign_snapshot() if mode == RunMode.CAMPAIGN_MAP else {},
		"active_checkpoint": profile_manager.get_active_checkpoint() if mode == RunMode.CAMPAIGN_MAP or mode == RunMode.GAME_OVER else {},
		"challenge_active": _challenge_active,
		"challenge": challenge_director.snapshot() if _challenge_active else {},
		"challenge_draft": _challenge_draft_pending,
		"challenge_drafts": _challenge_drafts,
		"tutorial_active": _tutorial_active,
		"tutorial_step": int(_tutorial_step),
		"tutorial_total": _tutorial_total_time,
	})


func _campaign_map_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var campaign := profile_manager.get_campaign_snapshot()
	var completed: Dictionary = campaign.get("completed", {})
	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		var record: Dictionary = completed.get(String(mission.mission_id), {})
		snapshots.append(mission.to_map_snapshot(not profile_manager.is_mission_unlocked(mission.mission_id), record))
	return snapshots


func _act_progress(boss_health: int, boss_max: int) -> float:
	if act == FINAL_ACT:
		return 0.0 if boss_max <= 0 else 1.0 - float(boss_health) / float(boss_max)
	return clampf(act_time / _current_tide_duration(), 0.0, 1.0)


func get_pressure_level() -> int:
	if _challenge_active:
		return challenge_director.tier
	if _tutorial_active:
		return int(_tutorial_step) + 1
	if act >= FINAL_ACT:
		var boss_phase := 1
		for enemy in enemies:
			if int(enemy["type"]) == EnemyType.BOSS:
				boss_phase = int(enemy.get("boss_phase", 1))
				break
		return COMBAT_TIDE_COUNT * 2 + 1 + boss_phase
	var section := 0
	if act_time >= _current_first_event_time():
		section += 1
	if act_time >= _current_second_event_time():
		section += 1
	return (act - 1) * 2 + 1 + section


func _tutorial_text() -> Array:
	if mode != RunMode.PLAYING:
		return ["", 0.0]
	if _tutorial_active:
		match _tutorial_step:
			TutorialStep.INTRO: return ["只需移动与一个按键", 1.0]
			TutorialStep.MOVE: return ["移动：WASD / 方向键 / 左摇杆", 1.0]
			TutorialStep.CAPTURE: return ["按住 空格 / A：展开圆界，收纳三枚紫色花瓣", 1.0]
			TutorialStep.RELEASE: return ["松开 空格 / A：让金色返光自动追敌", 1.0]
			TutorialStep.PRACTICE: return ["自由练习：边移动，边把危险折成弹药", 1.0]
			TutorialStep.COMPLETE: return ["完成！战役与无尽挑战都已开放", 1.0]
	if _challenge_active:
		return ["", 0.0]
	var text := ""
	var start := 0.0
	var finish := 0.0
	if run_time < 7.2:
		text = "移动：WASD / 方向键 / 左摇杆"
		start = 1.2
		finish = 7.2
	elif run_time < 15.0:
		text = "按住 空格 / A：展开折域，收纳紫色弹幕"
		start = 7.2
		finish = 15.0
	elif run_time < 23.0:
		text = "松开：让收纳的光自动返航"
		start = 15.0
		finish = 23.0
	else:
		return ["", 0.0]
	var alpha := minf(1.0, minf((run_time - start) / 0.7, (finish - run_time) / 0.9))
	return [text, clampf(alpha, 0.0, 1.0)]


func _music_intensity() -> float:
	if _boss_spawned:
		return 1.0
	return clampf(0.16 + float(act - 1) * 0.18 + float(hostile_shots.size()) / 500.0, 0.0, 0.88)


func _build_background_details() -> void:
	for index in 118:
		_stars.append({
			"position": Vector2(_rng.randf_range(24.0, 1896.0), _rng.randf_range(20.0, 720.0)),
			"size": _rng.randf_range(0.7, 2.8),
			"phase": _rng.randf_range(0.0, TAU),
			"depth": _rng.randf_range(0.25, 1.0),
		})
	for index in 72:
		_fibers.append({
			"position": Vector2(_rng.randf_range(0.0, 1920.0), _rng.randf_range(0.0, 1080.0)),
			"length": _rng.randf_range(18.0, 100.0),
			"angle": _rng.randf_range(-0.18, 0.18),
			"alpha": _rng.randf_range(0.008, 0.025),
		})
	for index in 14:
		_lanterns.append({
			"position": Vector2(_rng.randf_range(110.0, 1810.0), _rng.randf_range(300.0, 860.0)),
			"phase": _rng.randf_range(0.0, TAU),
			"size": _rng.randf_range(2.0, 6.0),
		})


func _draw() -> void:
	# Roguelite rooms own their full world-space backdrop. Keeping the classic
	# 2.0 paper sea active here painted an opaque layer across the regional art,
	# making all three regions appear to share the same background.
	if _rogue_mode_active:
		return
	var extreme_visual_load := hostile_shots.size() >= 220 and particles.size() >= 300
	if extreme_visual_load:
		_draw_background_reduced()
	else:
		_draw_background()
	_draw_ritual_overlay()
	draw_set_transform(_shake_offset, 0.0, Vector2.ONE)
	if mode != RunMode.TITLE:
		_draw_arena_lines()
	_draw_objectives()
	_draw_ripples()
	if extreme_visual_load:
		_draw_enemies_reduced()
	else:
		_draw_enemies()
	if extreme_visual_load:
		_draw_hostile_shots_reduced()
	else:
		_draw_hostile_shots()
	_draw_return_lights()
	if extreme_visual_load:
		_draw_particles_reduced()
	else:
		_draw_particles()
	if mode == RunMode.TITLE:
		_draw_title_ornament()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_background_reduced() -> void:
	# The battlefield is already visually saturated at the hard bullet/particle
	# ceiling. Preserve the paper-sea silhouette and contrast while omitting tiny
	# decorative geometry that cannot be read through three hundred projectiles.
	var accent := _scene_accent()
	for band in 12:
		var ratio := float(band) / 11.0
		var color := Color(0.010, 0.018, 0.060).lerp(Color(0.025, 0.075, 0.105).lerp(accent, 0.065), pow(ratio, 1.35))
		draw_rect(Rect2(0.0, float(band) * 90.0, VIEW_SIZE.x, 91.0), color)
	var moon_position := Vector2(1560.0, 270.0)
	draw_circle(moon_position, 154.0, Color(accent.r, accent.g, accent.b, 0.025))
	draw_circle(moon_position, 122.0, Color(0.74, 0.80, 0.69, 0.065))
	draw_circle(moon_position + Vector2(-38, 24), 83.0, Color(0.012, 0.027, 0.067, 0.74))
	for layer in 4:
		var points := PackedVector2Array()
		for x_step in 33:
			var x := float(x_step) * 60.0
			var y := 795.0 + float(layer) * 72.0 + sin(x * (0.006 + layer * 0.001) + _ambient_time * (0.22 + layer * 0.045)) * (18.0 + layer * 3.0)
			points.append(Vector2(x, y))
		draw_polyline(points, Color(accent.r, accent.g, accent.b, 0.075 - layer * 0.012), 1.5, true)


func _draw_ritual_overlay() -> void:
	if mode == RunMode.TITLE or mode == RunMode.SETTINGS or mode == RunMode.ARCHIVE:
		return
	var act_washes: Array[Color] = [
		Color.TRANSPARENT,
		Color(0.10, 0.62, 0.64, 0.018),
		Color(0.25, 0.36, 0.78, 0.020),
		Color(0.52, 0.22, 0.68, 0.024),
		Color(0.68, 0.12, 0.38, 0.026),
		Color(0.78, 0.18, 0.20, 0.030),
		Color(0.62, 0.16, 0.48, 0.032),
		Color(0.72, 0.08, 0.32, 0.038),
	]
	var wash := act_washes[clampi(act, 0, act_washes.size() - 1)]
	wash.a *= 1.0 + _background_energy * 0.72 + _background_pulse * 0.34
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), wash)
	if _ritual_event_timer <= 0.0:
		return
	if _ritual_event_kind == 3:
		for line_index in 13:
			var y := 170.0 + line_index * 63.0
			var drift := fmod(_ambient_time * 180.0 + line_index * 83.0, 240.0)
			draw_line(Vector2(70.0 + drift, y), Vector2(260.0 + drift, y - 22.0), Color(0.42, 0.80, 0.88, 0.10), 2.0, true)
	elif _ritual_event_kind == 5 or _ritual_event_kind == 6:
		for echo in 5:
			var echo_radius := fmod(_ambient_time * 72.0 + echo * 145.0, 720.0)
			draw_arc(Vector2(960.0, 540.0), echo_radius, 0.0, TAU, 96, Color(0.59, 0.35, 0.78, 0.045), 2.0, true)
	elif _ritual_event_kind == 8:
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.005, 0.008, 0.028, 0.28))
		var safe_angle := sin(_ambient_time * 0.42) * 1.3 - PI * 0.5
		var safe_origin := player.position + Vector2.from_angle(safe_angle) * 120.0
		draw_line(player.position, safe_origin, Color(1.0, 0.67, 0.28, 0.23), 2.0, true)


func _draw_background() -> void:
	# Layered nocturne instead of a flat clear colour.
	var scene_accent := _scene_accent()
	for band in 36:
		var t := float(band) / 35.0
		var top_color := Color(0.010, 0.018, 0.060)
		var bottom_color := Color(0.025, 0.075, 0.105).lerp(scene_accent, 0.065 if mode != RunMode.TITLE else 0.0)
		var color := top_color.lerp(bottom_color, pow(t, 1.35))
		draw_rect(Rect2(0.0, float(band) * 30.0, VIEW_SIZE.x, 31.0), color)

	# Moon print: offset from the centered title so it supports rather than competes.
	var moon_position := Vector2(1560.0, 270.0)
	var moon_radius := 178.0 if mode == RunMode.TITLE else 122.0
	for ring in range(7, 0, -1):
		draw_circle(moon_position, moon_radius + float(ring) * 18.0, Color(0.46, 0.72, 0.72, 0.008 * float(8 - ring)))
	draw_circle(moon_position, moon_radius, Color(0.74, 0.80, 0.69, 0.065))
	draw_arc(moon_position, moon_radius, -PI * 0.7, PI * 0.44, 96, Color(0.91, 0.73, 0.41, 0.17).lerp(scene_accent, 0.28), 2.0, true)
	draw_circle(moon_position + Vector2(-38, 24), moon_radius * 0.68, Color(0.012, 0.027, 0.067, 0.74))

	for star in _stars:
		var alpha := (0.24 + sin(_ambient_time * (0.35 + float(star["depth"])) + float(star["phase"])) * 0.15) * float(star["depth"])
		var star_color := Color(0.62, 0.88, 0.86, alpha)
		draw_circle(star["position"], float(star["size"]), star_color)

	for lantern in _lanterns:
		var pos: Vector2 = lantern["position"]
		pos.y += sin(_ambient_time * 0.48 + float(lantern["phase"])) * 10.0
		var glow := 0.25 + sin(_ambient_time * 1.1 + float(lantern["phase"])) * 0.08
		draw_circle(pos, float(lantern["size"]) * 4.0, Color(1.0, 0.62, 0.24, glow * 0.045))
		draw_circle(pos, float(lantern["size"]), Color(1.0, 0.72, 0.32, glow))

	_draw_act_scenery(scene_accent)

	# Six wave plates, each with different frequency and drift.
	for layer in 7:
		var points := PackedVector2Array()
		var base_y := 780.0 + float(layer) * 48.0
		for x_step in 65:
			var x := float(x_step) * 30.0
			var y := base_y + sin(x * (0.006 + layer * 0.0008) + _ambient_time * (0.22 + layer * 0.045) + layer) * (18.0 + layer * 3.2)
			y += sin(x * 0.017 - _ambient_time * 0.16) * 5.0
			points.append(Vector2(x, y))
		var wave_color := Color(0.22, 0.67, 0.69, 0.10 - float(layer) * 0.008)
		draw_polyline(points, wave_color, 2.0 if layer < 3 else 1.0, true)

	for fiber in _fibers:
		var start: Vector2 = fiber["position"]
		var finish := start + Vector2.from_angle(float(fiber["angle"])) * float(fiber["length"])
		draw_line(start, finish, Color(0.88, 0.88, 0.76, float(fiber["alpha"])), 1.0, true)


func _scene_accent() -> Color:
	var mission_accent := current_mission.accent if current_mission != null else Color(0.28, 0.78, 0.78)
	match act:
		1: return mission_accent.lerp(Color(0.28, 0.78, 0.78), 0.28)
		2: return mission_accent.lerp(Color(0.40, 0.56, 0.92), 0.32)
		3: return mission_accent.lerp(Color(0.62, 0.36, 0.82), 0.30)
		4: return mission_accent.lerp(Color(0.88, 0.24, 0.52), 0.30)
		5: return mission_accent.lerp(Color(0.96, 0.38, 0.30), 0.34)
		6: return mission_accent.lerp(Color(0.86, 0.30, 0.58), 0.28)
		7: return mission_accent.lerp(Color(0.96, 0.19, 0.43), 0.30)
		_: return mission_accent


func _draw_objectives() -> void:
	if mode != RunMode.PLAYING and mode != RunMode.BRIEFING and mode != RunMode.UPGRADE:
		return
	if objective_tracker.state == FoldlightObjectiveTracker.ObjectiveState.PENDING:
		return
	var accent := _scene_accent()
	var pulse := 0.62 + sin(_ambient_time * 3.2) * 0.20
	for anchor_index in _objective_anchors.size():
		var anchor := _objective_anchors[anchor_index]
		var ring_radius := 38.0 + sin(_ambient_time * 2.1 + anchor_index) * 5.0
		draw_circle(anchor, 22.0, Color(0.012, 0.032, 0.068, 0.82))
		draw_arc(anchor, ring_radius, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, 0.28 * pulse), 3.0, true)
		draw_arc(anchor, ring_radius + 13.0, -_ambient_time + anchor_index, -_ambient_time + anchor_index + PI * 1.25, 28, Color(1.0, 0.74, 0.30, 0.30), 2.0, true)
		var diamond := _diamond(anchor, _ambient_time * 0.35, 18.0, 10.0)
		draw_colored_polygon(diamond, Color(accent.r, accent.g, accent.b, 0.34))
		draw_polyline(_closed(diamond), Color(0.96, 0.92, 0.72, 0.64), 1.4, true)
	if objective_tracker.objective_id == &"escort":
		for glow in range(4, 0, -1):
			draw_circle(_escort_position, 28.0 + glow * 9.0, Color(accent.r, accent.g, accent.b, 0.012 * float(5 - glow)))
		var skiff := PackedVector2Array([
			_escort_position + Vector2(-34, 0), _escort_position + Vector2(-8, -18),
			_escort_position + Vector2(35, 0), _escort_position + Vector2(-8, 18),
		])
		draw_colored_polygon(skiff, Color(0.92, 0.86, 0.68, 0.72))
		draw_polyline(_closed(skiff), Color(accent.r, accent.g, accent.b, 0.92), 2.0, true)
		draw_arc(_escort_position, 48.0, -PI * 0.5, -PI * 0.5 + TAU * _escort_integrity, 36, Color(1.0, 0.70, 0.28, 0.82), 3.0, true)


func _draw_act_scenery(accent: Color) -> void:
	if mode == RunMode.TITLE or mode == RunMode.SETTINGS or mode == RunMode.ARCHIVE:
		return
	match act:
		1:
			# Mirror pools and paper reeds establish a calm opening shore.
			for pool_index in 4:
				var radius := 82.0 + float(pool_index) * 48.0 + sin(_ambient_time * 0.42 + pool_index) * 8.0
				draw_arc(Vector2(280.0, 680.0), radius, -PI * 0.96, PI * 0.16, 48, Color(accent.r, accent.g, accent.b, 0.055), 1.6, true)
				draw_arc(Vector2(1640.0, 640.0), radius * 0.82, PI * 0.10, PI * 1.18, 48, Color(accent.r, accent.g, accent.b, 0.045), 1.3, true)
			for reed_index in 7:
				var x := 118.0 + float(reed_index) * 36.0
				var sway := sin(_ambient_time * 0.55 + reed_index) * 13.0
				draw_line(Vector2(x, 900.0), Vector2(x + sway, 790.0 - reed_index * 6.0), Color(0.72, 0.84, 0.70, 0.055), 2.0, true)
		2:
			# A moving kite procession and slanted wind script.
			for kite_index in 8:
				var travel := fmod(_ambient_time * (22.0 + kite_index * 1.4) + kite_index * 244.0, 2240.0) - 160.0
				var center := Vector2(travel, 220.0 + float(kite_index % 4) * 145.0 + sin(_ambient_time * 0.7 + kite_index) * 18.0)
				var kite := _diamond(center, -0.18, 24.0 + float(kite_index % 3) * 4.0, 13.0)
				draw_colored_polygon(kite, Color(accent.r, accent.g, accent.b, 0.045))
				draw_polyline(_closed(kite), Color(accent.r, accent.g, accent.b, 0.12), 1.2, true)
				draw_line(center + Vector2(-18, 8), center + Vector2(-94, 34), Color(0.82, 0.75, 0.58, 0.075), 1.0, true)
			for wind_index in 5:
				var wind_y := 250.0 + wind_index * 142.0
				var wind_x := fmod(_ambient_time * 90.0 + wind_index * 330.0, 2020.0) - 120.0
				draw_line(Vector2(wind_x, wind_y), Vector2(wind_x + 210.0, wind_y - 28.0), Color(accent.r, accent.g, accent.b, 0.065), 1.4, true)
		3:
			# Nested gates and expanding echoes make the paper sea feel architectural.
			for gate_index in 5:
				var inset := 26.0 + gate_index * 34.0
				var gate_size := Vector2(260.0 - gate_index * 28.0, 510.0 - gate_index * 42.0)
				draw_rect(Rect2(Vector2(inset, 275.0 + gate_index * 18.0), gate_size), Color(accent.r, accent.g, accent.b, 0.052), false, 1.3)
				draw_rect(Rect2(Vector2(VIEW_SIZE.x - inset - gate_size.x, 275.0 + gate_index * 18.0), gate_size), Color(accent.r, accent.g, accent.b, 0.052), false, 1.3)
			for echo_index in 4:
				var echo_radius := 165.0 + echo_index * 108.0 + sin(_ambient_time * 0.38 + echo_index) * 12.0
				draw_arc(Vector2(960.0, 555.0), echo_radius, -PI * 0.82, PI * 0.22, 64, Color(accent.r, accent.g, accent.b, 0.052), 1.5, true)
		4:
			# Broken vortex ribbons point toward the calm eye without drawing a hazard.
			var vortex := Vector2(960.0, 550.0)
			for ribbon_index in 9:
				var ribbon_radius := 190.0 + ribbon_index * 58.0
				var start_angle := _ambient_time * (0.025 + ribbon_index * 0.003) + ribbon_index * 0.74
				draw_arc(vortex, ribbon_radius, start_angle, start_angle + PI * 0.56, 38, Color(accent.r, accent.g, accent.b, 0.045 + float(ribbon_index % 3) * 0.01), 2.0 if ribbon_index < 4 else 1.2, true)
			for shard_index in 7:
				var shard_angle := float(shard_index) * TAU / 7.0 - _ambient_time * 0.035
				var shard_center := vortex + Vector2.from_angle(shard_angle) * (330.0 + shard_index * 34.0)
				var shard := _diamond(shard_center, shard_angle, 28.0, 7.0)
				draw_colored_polygon(shard, Color(0.92, 0.34, 0.57, 0.050))
		5:
			# Red wheels sweep over reeds; pulses from impact make the rings breathe.
			for wheel_index in 7:
				var wheel_center := Vector2(230.0 + wheel_index * 250.0, 700.0 + sin(wheel_index * 1.8) * 120.0)
				var wheel_radius := 72.0 + float(wheel_index % 3) * 28.0 + sin(_ambient_time * 0.8 + wheel_index) * (7.0 + _background_pulse * 13.0)
				draw_arc(wheel_center, wheel_radius, _ambient_time * 0.18 + wheel_index, _ambient_time * 0.18 + wheel_index + PI * 1.42, 46, Color(accent.r, accent.g, accent.b, 0.055 + _background_energy * 0.025), 2.0, true)
			for reed_index in 18:
				var reed_x := 70.0 + reed_index * 104.0
				var lean := sin(_ambient_time * 0.72 + reed_index * 0.6) * (16.0 + _background_energy * 13.0)
				draw_line(Vector2(reed_x, 950.0), Vector2(reed_x + lean, 790.0 - float(reed_index % 4) * 22.0), Color(0.94, 0.56, 0.34, 0.050), 1.7, true)
		6:
			# The corridor runs in both time directions: paired ribbons and reverse motes.
			for corridor_index in 8:
				var inset := 90.0 + corridor_index * 62.0
				var scroll := fmod(_ambient_time * (42.0 + corridor_index * 3.0), 180.0)
				draw_line(Vector2(inset, 170.0 + scroll), Vector2(inset + 330.0, 930.0 - scroll), Color(accent.r, accent.g, accent.b, 0.038 + _background_energy * 0.018), 1.5, true)
				draw_line(Vector2(VIEW_SIZE.x - inset, 170.0 + scroll), Vector2(VIEW_SIZE.x - inset - 330.0, 930.0 - scroll), Color(1.0, 0.58, 0.28, 0.036 + _background_pulse * 0.025), 1.5, true)
			for mote_index in 18:
				var mote_t := fmod(float(mote_index) / 18.0 - _ambient_time * (0.035 + _background_energy * 0.025), 1.0)
				if mote_t < 0.0:
					mote_t += 1.0
				var mote_pos := Vector2(220.0, 210.0).lerp(Vector2(1700.0, 870.0), mote_t)
				draw_circle(mote_pos, 2.0 + float(mote_index % 3), Color(1.0, 0.62, 0.32, 0.10))
		7:
			# Ink pools and radial cracks turn the familiar moon print into a finale.
			var moon := Vector2(1560.0, 270.0)
			for crack_index in 10:
				var crack_angle := -PI * 0.86 + crack_index * 0.19 + sin(_ambient_time * 0.2 + crack_index) * 0.025
				var crack_start := moon + Vector2.from_angle(crack_angle) * 102.0
				var crack_end := moon + Vector2.from_angle(crack_angle + sin(crack_index) * 0.08) * (190.0 + crack_index * 12.0)
				draw_line(crack_start, crack_end, Color(accent.r, accent.g, accent.b, 0.10), 1.6, true)
			for pool_index in 6:
				var pool_pos := Vector2(150.0 + pool_index * 330.0, 820.0 + sin(pool_index * 1.7) * 80.0)
				draw_circle(pool_pos, 48.0 + pool_index * 9.0, Color(0.10, 0.015, 0.09, 0.055))


func _draw_arena_lines() -> void:
	var boundary := _current_arena_bounds()
	if _challenge_active:
		var shade := Color(0.004, 0.008, 0.026, 0.62)
		draw_rect(Rect2(0.0, 0.0, VIEW_SIZE.x, boundary.position.y), shade)
		draw_rect(Rect2(0.0, boundary.end.y, VIEW_SIZE.x, VIEW_SIZE.y - boundary.end.y), shade)
		draw_rect(Rect2(0.0, boundary.position.y, boundary.position.x, boundary.size.y), shade)
		draw_rect(Rect2(boundary.end.x, boundary.position.y, VIEW_SIZE.x - boundary.end.x, boundary.size.y), shade)
		for echo in 3:
			draw_rect(boundary.grow(float(echo) * 5.0), Color(0.34, 0.88, 0.82, 0.12 - echo * 0.028), false, 2.0)
	draw_rect(boundary, Color(0.34, 0.82, 0.80, 0.16 if _challenge_active else 0.055), false, 2.0 if _challenge_active else 1.0)
	for corner in [boundary.position, Vector2(boundary.end.x, boundary.position.y), boundary.end, Vector2(boundary.position.x, boundary.end.y)]:
		draw_circle(corner, 3.0, Color(0.91, 0.69, 0.35, 0.28))


func _draw_title_ornament() -> void:
	var center := player.position
	for ring in 4:
		var radius := 72.0 + float(ring) * 34.0 + sin(_ambient_time * 0.8 + ring) * 6.0
		draw_arc(center, radius, -PI * 0.88 + ring, PI * 0.16 + ring, 48, Color(0.38, 0.84, 0.80, 0.08), 1.4, true)


func _draw_ripples() -> void:
	for ripple in ripples:
		var ratio := clampf(float(ripple["life"]) / float(ripple["max_life"]), 0.0, 1.0)
		var color: Color = ripple["color"]
		color.a = ratio * 0.62
		draw_arc(ripple["position"], float(ripple["radius"]), 0.0, TAU, 80, color, float(ripple["width"]) * ratio + 0.6, true)


func _draw_enemies() -> void:
	for enemy in enemies:
		_draw_enemy(enemy)


func _draw_enemies_reduced() -> void:
	for enemy in enemies:
		if int(enemy["type"]) == EnemyType.BOSS:
			_draw_boss(enemy, 1.0)
			continue
		var position_value: Vector2 = enemy["position"]
		var radius := float(enemy["radius"])
		var flash := float(enemy["flash"])
		var accent := Color(0.42, 0.88, 0.80) if int(enemy["type"]) % 2 == 0 else Color(0.92, 0.30, 0.58)
		draw_circle(position_value, radius, Color(0.035, 0.025, 0.075).lerp(Color.WHITE, flash * 0.62))
		draw_arc(position_value, radius + 5.0, 0.0, TAU, 18, accent, 2.0, true)
		draw_circle(position_value, 3.5, Color(1.0, 0.70, 0.30))


func _draw_enemy(enemy: Dictionary) -> void:
	var position_value: Vector2 = enemy["position"]
	var enemy_type := int(enemy["type"])
	var age: float = float(enemy["age"])
	# A non-zero floor prevents degenerate polygons during the exact spawn frame.
	var spawn_scale := maxf(0.055, ease(clampf(age / 0.52, 0.0, 1.0), -2.0))
	var flash: float = float(enemy["flash"])
	var dark := Color(0.035, 0.025, 0.075).lerp(Color.WHITE, flash * 0.72)
	var ink := Color(0.70, 0.18, 0.54).lerp(Color.WHITE, flash)
	match enemy_type:
		EnemyType.DRIFTER:
			for petal in 6:
				var angle := float(petal) * TAU / 6.0 + age * 0.34
				var petal_center := position_value + Vector2.from_angle(angle) * 14.0 * spawn_scale
				var points := _diamond(petal_center, angle, 27.0 * spawn_scale, 12.0 * spawn_scale)
				draw_colored_polygon(points, dark)
				draw_polyline(_closed(points), Color(ink.r, ink.g, ink.b, 0.52), 1.4, true)
			draw_circle(position_value, 9.0 * spawn_scale, ink)
			draw_circle(position_value, 3.0 * spawn_scale, Color(1.0, 0.68, 0.30))
		EnemyType.FAN:
			var rotation := (player.position - position_value).angle() + PI * 0.5
			var left := _rotated_points(position_value, rotation, [Vector2(0,-38), Vector2(-42,25), Vector2(0,12)])
			var right := _rotated_points(position_value, rotation, [Vector2(0,-38), Vector2(42,25), Vector2(0,12)])
			draw_colored_polygon(_scaled_points(left, position_value, spawn_scale), dark)
			draw_colored_polygon(_scaled_points(right, position_value, spawn_scale), Color(0.10, 0.06, 0.17).lerp(Color.WHITE, flash * 0.7))
			draw_line(left[0], left[1], Color(0.88, 0.24, 0.54, 0.76), 2.0, true)
			draw_line(right[0], right[1], Color(0.40, 0.68, 0.82, 0.72), 2.0, true)
			draw_circle(position_value, 5.0, Color(1.0, 0.69, 0.28))
		EnemyType.WEAVER:
			for ring in 3:
				var radius := (14.0 + ring * 10.0) * spawn_scale
				draw_arc(position_value, radius, age * (0.7 + ring * 0.2), age * (0.7 + ring * 0.2) + PI * 1.35, 30, Color(0.54, 0.31 + ring * 0.08, 0.78, 0.72 - ring * 0.14), 4.2 - ring, true)
			for spoke in 4:
				var angle := age * -0.6 + spoke * PI * 0.5
				draw_line(position_value + Vector2.from_angle(angle) * 7.0, position_value + Vector2.from_angle(angle) * 35.0 * spawn_scale, Color(ink.r, ink.g, ink.b, 0.42), 2.0, true)
			draw_circle(position_value, 7.0, dark)
			draw_circle(position_value, 2.8, Color(1.0, 0.72, 0.32))
		EnemyType.RAM:
			var ram_state := int(enemy.get("ram_state", RamState.STALK))
			var ram_direction: Vector2 = enemy.get("charge_direction", Vector2(enemy["velocity"]).normalized())
			var rotation := ram_direction.angle() if ram_state == RamState.TELEGRAPH or ram_state == RamState.CHARGE else Vector2(enemy["velocity"]).angle()
			if ram_state == RamState.TELEGRAPH:
				var warning_ratio := clampf(float(enemy.get("ram_timer", 0.0)) / 0.95, 0.0, 1.0)
				var line_end := position_value + ram_direction.normalized() * 1280.0
				draw_line(position_value, line_end, Color(0.68, 0.06, 0.18, 0.075 + (1.0 - warning_ratio) * 0.045), 68.0, true)
				draw_dashed_line(position_value, line_end, Color(1.0, 0.66, 0.24, 0.58), 2.5, 22.0, true)
				for warning_arc in 3:
					draw_arc(position_value, 62.0 + warning_ratio * 68.0 + warning_arc * 10.0, rotation - 0.68, rotation + 0.68, 28, Color(1.0, 0.48, 0.24, 0.42 - warning_arc * 0.09), 2.0, true)
			var body := _rotated_points(position_value, rotation, [Vector2(48,0), Vector2(3,31), Vector2(-36,18), Vector2(-25,0), Vector2(-36,-18), Vector2(3,-31)])
			body = _scaled_points(body, position_value, spawn_scale)
			draw_colored_polygon(body, dark)
			draw_polyline(_closed(body), Color(0.90, 0.23, 0.49, 0.72), 2.2, true)
			draw_line(position_value - Vector2.from_angle(rotation) * 22.0, position_value + Vector2.from_angle(rotation) * 34.0, Color(0.98, 0.69, 0.29, 0.72), 2.0, true)
			if ram_state == RamState.RECOVER:
				draw_circle(position_value, 12.0 + sin(age * 8.0) * 2.0, Color(1.0, 0.70, 0.28, 0.72), false, 3.0, true)
		EnemyType.BLOOMER:
			for petal in 8:
				var petal_angle := float(petal) * TAU / 8.0 + age * (0.20 if petal % 2 == 0 else -0.16)
				var petal_origin := position_value + Vector2.from_angle(petal_angle) * 25.0 * spawn_scale
				var petal_shape := _diamond(petal_origin, petal_angle, 23.0 * spawn_scale, 9.0 * spawn_scale)
				draw_colored_polygon(petal_shape, Color(0.075, 0.045, 0.13).lerp(Color.WHITE, flash * 0.64))
				draw_polyline(_closed(petal_shape), Color(0.55, 0.34, 0.81, 0.64), 1.5, true)
			draw_circle(position_value, 14.0 * spawn_scale, Color(0.52, 0.22, 0.66).lerp(Color.WHITE, flash))
			draw_circle(position_value, 4.2 * spawn_scale, Color(1.0, 0.70, 0.29))
		EnemyType.LEECH:
			var leech_rotation := (player.position - position_value).angle()
			var outer := _rotated_points(position_value, leech_rotation, [Vector2(42,0), Vector2(10,33), Vector2(-34,26), Vector2(-18,0), Vector2(-34,-26), Vector2(10,-33)])
			outer = _scaled_points(outer, position_value, spawn_scale)
			draw_colored_polygon(outer, Color(0.06, 0.025, 0.11).lerp(Color.WHITE, flash * 0.68))
			draw_polyline(_closed(outer), Color(0.90, 0.23, 0.55, 0.76), 2.1, true)
			draw_circle(position_value + Vector2.from_angle(leech_rotation) * 10.0, 7.0, Color(0.12, 0.75, 0.76))
			if position_value.distance_to(player.position) < 245.0:
				var tether_alpha := 0.20 + sin(age * 9.0) * 0.08
				draw_dashed_line(position_value, player.position, Color(0.88, 0.25, 0.58, tether_alpha), 2.0, 12.0, true)
		EnemyType.MIRROR:
			var mirror_rotation := (player.position - position_value).angle() + PI * 0.5
			var mirror_left := _rotated_points(position_value, mirror_rotation, [Vector2(-4,-17), Vector2(-53,-38), Vector2(-37,11), Vector2(-8,28)])
			var mirror_right := _rotated_points(position_value, mirror_rotation, [Vector2(4,-17), Vector2(53,-38), Vector2(37,11), Vector2(8,28)])
			mirror_left = _scaled_points(mirror_left, position_value, spawn_scale)
			mirror_right = _scaled_points(mirror_right, position_value, spawn_scale)
			draw_colored_polygon(mirror_left, Color(0.025, 0.10, 0.13).lerp(Color.WHITE, flash * 0.64))
			draw_colored_polygon(mirror_right, Color(0.07, 0.035, 0.12).lerp(Color.WHITE, flash * 0.64))
			draw_polyline(_closed(mirror_left), Color(0.30, 0.88, 0.86, 0.72), 2.0, true)
			draw_polyline(_closed(mirror_right), Color(0.94, 0.52, 0.42, 0.62), 2.0, true)
			draw_circle(position_value, 8.0 * spawn_scale, Color(1.0, 0.68, 0.30))
			var mirror_state := int(enemy.get("mirror_state", MirrorState.SEEK))
			var stored := int(enemy.get("stored_light", 0))
			if mirror_state == MirrorState.FOLD:
				var counter_radius := 138.0 + minf(24.0, float(stored) * 2.0)
				for counter_ring in 3:
					var ring_radius := counter_radius - counter_ring * 13.0 + sin(age * 5.0 + counter_ring) * 3.0
					draw_arc(position_value, ring_radius, -PI * 0.92 + counter_ring, PI * 0.16 + counter_ring, 64, Color(0.30, 0.88, 0.86, 0.58 - counter_ring * 0.13), 3.0 - counter_ring * 0.5, true)
					draw_circle(position_value, ring_radius, Color(0.18, 0.78, 0.80, 0.018))
				for pip in mini(12, stored):
					var pip_angle := float(pip) * TAU / float(maxi(1, mini(12, stored))) + age * 0.8
					draw_circle(position_value + Vector2.from_angle(pip_angle) * 110.0, 4.2, Color(1.0, 0.73, 0.30, 0.88))
			elif mirror_state == MirrorState.RELEASE:
				for ray in 8:
					var ray_angle := float(ray) * TAU / 8.0 + age
					draw_line(position_value + Vector2.from_angle(ray_angle) * 32.0, position_value + Vector2.from_angle(ray_angle) * 76.0, Color(0.40, 0.94, 0.88, 0.38), 2.0, true)
		EnemyType.REWINDER:
			var rewind_state := int(enemy.get("rewind_state", RewindState.ROAM))
			var path: PackedVector2Array = enemy.get("rewind_path", PackedVector2Array())
			if path.size() >= 2:
				var path_alpha := 0.24 if rewind_state == RewindState.TELEGRAPH else 0.16
				draw_polyline(path, Color(0.38, 0.04, 0.22, path_alpha), 15.0, true)
				draw_polyline(path, Color(1.0, 0.50, 0.25, 0.62 if rewind_state == RewindState.TELEGRAPH else 0.38), 2.2, true)
				var arrow_step := maxi(1, int(path.size() / 6))
				for arrow_index in range(path.size() - 1, 0, -arrow_step):
					var arrow_direction := path[arrow_index].direction_to(path[maxi(0, arrow_index - 1)])
					draw_line(path[arrow_index], path[arrow_index] + arrow_direction * 18.0, Color(1.0, 0.64, 0.28, 0.56), 3.0, true)
			for loop_index in 5:
				var loop_angle := age * (-1.4 if rewind_state == RewindState.REWIND else 0.46) + float(loop_index) * TAU / 5.0
				var loop_center := position_value + Vector2.from_angle(loop_angle) * 27.0 * spawn_scale
				var loop_shape := _diamond(loop_center, loop_angle + PI * 0.5, 22.0 * spawn_scale, 7.0 * spawn_scale)
				draw_colored_polygon(loop_shape, Color(0.07, 0.025, 0.10).lerp(Color.WHITE, flash * 0.64))
				draw_polyline(_closed(loop_shape), Color(0.94, 0.35, 0.48, 0.62), 1.5, true)
			draw_circle(position_value, 13.0 * spawn_scale, Color(0.96, 0.48, 0.25).lerp(Color.WHITE, flash))
			draw_circle(position_value, 4.0 * spawn_scale, Color(1.0, 0.82, 0.46))
			if rewind_state == RewindState.TELEGRAPH:
				var warning_radius := 54.0 + float(enemy.get("rewind_timer", 0.0)) * 34.0
				draw_arc(position_value, warning_radius, -PI, PI, 48, Color(1.0, 0.48, 0.24, 0.78), 3.0, true)
		EnemyType.CARVER:
			var carve_charge := float(enemy.get("skill_charge", 0.0))
			var carve_direction: Vector2 = enemy.get("telegraph_direction", Vector2.DOWN)
			if carve_charge > 0.0:
				var line_end := position_value + carve_direction.normalized() * 1180.0
				draw_line(position_value, line_end, Color(0.20, 0.52, 0.94, 0.09), 52.0, true)
				draw_dashed_line(position_value, line_end, Color(0.42, 0.78, 1.0, 0.72), 2.2, 18.0, true)
			var carve_rotation := Vector2(enemy.get("velocity", Vector2.DOWN)).angle()
			for blade in [-1.0, 1.0]:
				var blade_center := position_value + Vector2.from_angle(carve_rotation + blade * PI * 0.5) * 18.0 * spawn_scale
				var blade_shape := _diamond(blade_center, carve_rotation, 45.0 * spawn_scale, 9.0 * spawn_scale)
				draw_colored_polygon(blade_shape, Color(0.025, 0.06, 0.13).lerp(Color.WHITE, flash * 0.62))
				draw_polyline(_closed(blade_shape), Color(0.32, 0.70, 0.98, 0.78), 1.8, true)
			draw_circle(position_value, 8.0 * spawn_scale, Color(1.0, 0.70, 0.28))
		EnemyType.BELL:
			var bell_charge := float(enemy.get("skill_charge", 0.0))
			for bell_ring in 3:
				var bell_radius := (18.0 + bell_ring * 12.0 + (1.0 - bell_charge) * 9.0) * spawn_scale
				draw_arc(position_value, bell_radius, age * (0.36 + bell_ring * 0.08), age * (0.36 + bell_ring * 0.08) + PI * 1.42, 32, Color(0.72, 0.40, 0.94, 0.68 - bell_ring * 0.15), 2.5, true)
			var bell_body := _rotated_points(position_value, sin(age * 1.4) * 0.08, [Vector2(-30,-22), Vector2(30,-22), Vector2(40,24), Vector2(-40,24)])
			bell_body = _scaled_points(bell_body, position_value, spawn_scale)
			draw_colored_polygon(bell_body, Color(0.07, 0.035, 0.13).lerp(Color.WHITE, flash * 0.62))
			draw_polyline(_closed(bell_body), Color(0.76, 0.46, 0.96, 0.72), 2.0, true)
			draw_circle(position_value + Vector2(0, 27) * spawn_scale, 6.0 * spawn_scale, Color(1.0, 0.68, 0.28))
		EnemyType.THIEF:
			for wake in 3:
				var wake_start := position_value + Vector2(-38.0 - wake * 18.0, (wake - 1) * 9.0)
				draw_line(wake_start, wake_start + Vector2(-48.0, sin(age * 5.0 + wake) * 12.0), Color(1.0, 0.58, 0.24, 0.22 - wake * 0.04), 2.0, true)
			var thief_body := PackedVector2Array([position_value + Vector2(44,0), position_value + Vector2(-20,-25), position_value + Vector2(-42,0), position_value + Vector2(-20,25)])
			thief_body = _scaled_points(thief_body, position_value, spawn_scale)
			draw_colored_polygon(thief_body, Color(0.10, 0.045, 0.08).lerp(Color.WHITE, flash * 0.64))
			draw_polyline(_closed(thief_body), Color(1.0, 0.58, 0.26, 0.82), 2.0, true)
			draw_circle(position_value + Vector2(7, 0), 7.0 * spawn_scale, Color(0.98, 0.86, 0.48))
		EnemyType.MOTH:
			for wing in [-1.0, 1.0]:
				var wing_angle: float = float(wing) * (0.86 + sin(age * 4.2) * 0.18)
				var wing_center := position_value + Vector2.from_angle(wing_angle) * 27.0 * spawn_scale
				var wing_shape := _diamond(wing_center, wing_angle, 39.0 * spawn_scale, 18.0 * spawn_scale)
				draw_colored_polygon(wing_shape, Color(0.03, 0.11, 0.10).lerp(Color.WHITE, flash * 0.60))
				draw_polyline(_closed(wing_shape), Color(0.42, 0.90, 0.72, 0.78), 1.8, true)
			draw_circle(position_value, 12.0 * spawn_scale, Color(0.08, 0.18, 0.16).lerp(Color.WHITE, flash * 0.68))
			draw_circle(position_value, 4.0 * spawn_scale, Color(1.0, 0.74, 0.30))
			if float(enemy.get("skill_charge", 0.0)) > 0.0:
				var echo_count := clampi(int(enemy.get("echo_count", 8)), 6, 18)
				for echo in mini(10, echo_count):
					var echo_angle := float(echo) * TAU / float(mini(10, echo_count)) - age
					draw_circle(position_value + Vector2.from_angle(echo_angle) * 55.0, 3.5, Color(0.52, 0.94, 0.76, 0.66))
		EnemyType.HERALD:
			var variant := int(enemy.get("ritual_variant", 1))
			for blade in 10:
				var blade_angle := float(blade) * TAU / 10.0 + age * (0.18 + variant * 0.03)
				var blade_center := position_value + Vector2.from_angle(blade_angle) * 57.0 * spawn_scale
				var blade_points := _diamond(blade_center, blade_angle, 31.0 * spawn_scale, 8.0 * spawn_scale)
				draw_colored_polygon(blade_points, Color(0.045, 0.025, 0.09).lerp(Color.WHITE, flash * 0.65))
				draw_polyline(_closed(blade_points), Color(0.36 + variant * 0.10, 0.70 - variant * 0.09, 0.76, 0.66), 1.6, true)
			draw_circle(position_value, 42.0 * spawn_scale, Color(0.07, 0.035, 0.12).lerp(Color.WHITE, flash * 0.7))
			draw_arc(position_value, 38.0 * spawn_scale, -PI * 0.78, PI * 0.72, 42, Color(0.98, 0.62, 0.29, 0.82), 3.2, true)
			draw_circle(position_value + Vector2(-10, 7), 28.0 * spawn_scale, Color(0.018, 0.032, 0.075, 0.88))
		EnemyType.BOSS:
			_draw_boss(enemy, spawn_scale)

	var skill_charge := float(enemy.get("skill_charge", 0.0))
	if skill_charge > 0.0:
		_draw_sealed_charge(position_value, float(enemy["radius"]), skill_charge, age)

	if bool(enemy["elite"]) and enemy_type != EnemyType.BOSS and enemy_type != EnemyType.HERALD:
		var affix := int(enemy.get("affix", 0))
		var affix_colors: Array[Color] = [Color.TRANSPARENT, Color(0.34, 0.90, 0.84, 0.58), Color(0.70, 0.46, 0.96, 0.62), Color(1.0, 0.72, 0.28, 0.62), Color(0.96, 0.44, 0.28, 0.62), Color(0.95, 0.37, 0.62, 0.62), Color(0.42, 0.78, 0.94, 0.62)]
		var affix_color := affix_colors[clampi(affix, 0, affix_colors.size() - 1)]
		draw_arc(position_value, float(enemy["radius"]) + 10.0, -PI * 0.7 + age, PI * 0.5 + age, 28, affix_color, 2.0, true)
		for mark in affix:
			draw_circle(position_value + Vector2(-8.0 + mark * 8.0, -float(enemy["radius"]) - 15.0), 2.3, affix_color)


func _draw_boss(enemy: Dictionary, spawn_scale: float) -> void:
	var position_value: Vector2 = enemy["position"]
	var age: float = float(enemy["age"])
	var flash: float = float(enemy["flash"])
	var boss_phase := int(enemy.get("boss_phase", 1))
	var variant := int(enemy.get("boss_variant", 0))
	var accent := current_mission.accent if current_mission != null else Color(0.92, 0.25, 0.54)
	for glow in range(6, 0, -1):
		draw_circle(position_value, (82.0 + glow * 18.0) * spawn_scale, Color(accent.r, accent.g, accent.b, 0.012 * float(7 - glow)))
	var petal_count := 10 + boss_phase * 2 + variant % 4
	for petal in petal_count:
		var angle := float(petal) * TAU / float(petal_count) - age * (0.15 + boss_phase * 0.04) * (-1.0 if variant % 2 == 1 else 1.0)
		var center := position_value + Vector2.from_angle(angle) * 93.0 * spawn_scale
		var points := _diamond(center, angle + float(variant % 3) * 0.18, (32.0 + variant % 4 * 2.0) * spawn_scale, (11.0 + variant % 3 * 2.0) * spawn_scale)
		draw_colored_polygon(points, Color(0.05, 0.025, 0.09, 0.94))
		draw_polyline(_closed(points), Color(accent.r, accent.g, accent.b, 0.58), 1.5, true)
	var moon_color := Color(0.11, 0.035, 0.12).lerp(Color.WHITE, flash * 0.72)
	draw_circle(position_value, 79.0 * spawn_scale, moon_color)
	if variant < 4:
		draw_circle(position_value + Vector2(-22, 12) * spawn_scale, 62.0 * spawn_scale, Color(0.018, 0.022, 0.066, 0.88))
	elif variant < 8:
		for bell_arc in 3:
			draw_arc(position_value, (38.0 + bell_arc * 16.0) * spawn_scale, age * (0.18 + bell_arc * 0.05), age * (0.18 + bell_arc * 0.05) + PI * 1.4, 42, Color(accent.r, accent.g, accent.b, 0.62 - bell_arc * 0.13), 3.0, true)
	else:
		for sun_ray in 12 + boss_phase * 2:
			var ray_angle := float(sun_ray) * TAU / float(12 + boss_phase * 2) + age * 0.08
			draw_line(position_value + Vector2.from_angle(ray_angle) * 46.0 * spawn_scale, position_value + Vector2.from_angle(ray_angle) * 76.0 * spawn_scale, Color(accent.r, accent.g, accent.b, 0.46), 2.0, true)
	draw_arc(position_value, 79.0 * spawn_scale, -PI * 0.73, PI * 0.72, 72, Color(accent.r, accent.g, accent.b, 0.78), 4.0, true)
	for phase_ring in range(1, boss_phase):
		draw_arc(position_value, (92.0 + phase_ring * 15.0) * spawn_scale, age * 0.25 * phase_ring, age * 0.25 * phase_ring + PI * 1.3, 54, Color(1.0, 0.58, 0.30, 0.34), 2.2, true)
	for crack in 5:
		var angle := -1.9 + crack * 0.72 + sin(age * 0.22 + crack) * 0.1
		draw_line(position_value + Vector2.from_angle(angle) * 18.0, position_value + Vector2.from_angle(angle + 0.15) * 65.0, Color(0.98, 0.66, 0.32, 0.34), 1.6, true)


func _draw_sealed_charge(origin: Vector2, enemy_radius: float, remaining: float, age: float) -> void:
	var ratio := clampf(remaining / 1.05, 0.0, 1.0)
	var closing_radius := enemy_radius + 28.0 + ratio * 76.0
	draw_circle(origin, enemy_radius + 17.0, Color(0.015, 0.008, 0.025, 0.36 * (1.0 - ratio)))
	draw_arc(origin, closing_radius, 0.0, TAU, 72, Color(1.0, 0.43, 0.16, 0.82), 3.0, true)
	draw_arc(origin, closing_radius - 9.0, age * 1.8, age * 1.8 + PI * 1.42, 48, Color(0.10, 0.02, 0.04, 0.92), 4.5, true)
	for nail_index in 6:
		var angle := float(nail_index) * TAU / 6.0 + age * 0.18
		var nail_center := origin + Vector2.from_angle(angle) * closing_radius
		var nail := _diamond(nail_center, angle + PI, 13.0, 4.2)
		draw_colored_polygon(nail, Color(0.035, 0.012, 0.025, 0.96))
		draw_polyline(_closed(nail), Color(1.0, 0.54, 0.18, 0.88), 1.7, true)


func _draw_hostile_shots() -> void:
	var high_contrast := bool(profile_manager.get_setting(&"high_contrast", false))
	_hostile_outline_points.clear()
	_hostile_outline_colors.clear()
	_hostile_core_points.clear()
	_hostile_core_colors.clear()
	for shot in hostile_shots:
		var position_value: Vector2 = shot["position"]
		var color: Color = shot["color"]
		var age: float = float(shot["age"])
		var velocity_value: Vector2 = shot["velocity"]
		var angle := velocity_value.angle() + sin(age * 5.0) * 0.08
		var forward := Vector2.from_angle(angle)
		var side := forward.rotated(PI * 0.5)
		var reflectable := bool(shot.get("reflectable", true))
		var length := 18.0 if not reflectable else (12.0 if int(shot["kind"]) == 0 else 9.0)
		var width := 8.0 if not reflectable else 6.0
		var tip_front := position_value + forward * length
		var tip_right := position_value + side * width
		var tip_back := position_value - forward * length * 0.72
		var tip_left := position_value - side * width
		var stroke_color := Color(1.0, 0.50, 0.16, 0.98) if not reflectable else (Color(1.0, 0.96, 0.80, 0.96) if high_contrast else Color(color.r, color.g, color.b, 0.94))
		_hostile_outline_points.append(tip_front)
		_hostile_outline_points.append(tip_right)
		_hostile_outline_points.append(tip_right)
		_hostile_outline_points.append(tip_back)
		_hostile_outline_points.append(tip_back)
		_hostile_outline_points.append(tip_left)
		_hostile_outline_points.append(tip_left)
		_hostile_outline_points.append(tip_front)
		for edge in 4:
			_hostile_outline_colors.append(stroke_color)
		_hostile_core_points.append(position_value - forward * 2.2)
		_hostile_core_points.append(position_value + forward * 3.4)
		_hostile_core_colors.append(Color(0.06, 0.012, 0.025, 1.0) if not reflectable else Color(1.0, 0.82, 0.70, 0.96))
		if not reflectable:
			_hostile_core_points.append(position_value - side * 7.0)
			_hostile_core_points.append(position_value + side * 7.0)
			_hostile_core_colors.append(Color(1.0, 0.66, 0.20, 0.98))
			_hostile_core_points.append(position_value - forward * 13.0)
			_hostile_core_points.append(position_value - forward * 25.0)
			_hostile_core_colors.append(Color(0.94, 0.16, 0.18, 0.78))
		var shot_status := StringName(shot.get("status", &""))
		if shot_status != &"":
			_hostile_core_points.append(position_value - side * 5.0)
			_hostile_core_points.append(position_value + side * 5.0)
			var status_mark_color := Color(0.46, 0.92, 0.92, 0.94) if shot_status == &"wet_ink" else (Color(0.98, 0.48, 0.58, 0.94) if shot_status == &"bound_crease" else Color(0.72, 0.54, 1.0, 0.94))
			_hostile_core_colors.append(status_mark_color)
	if not _hostile_outline_points.is_empty():
		draw_multiline_colors(_hostile_outline_points, _hostile_outline_colors, 2.4, true)
		draw_multiline_colors(_hostile_core_points, _hostile_core_colors, 2.0, true)


func _draw_hostile_shots_reduced() -> void:
	var high_contrast := bool(profile_manager.get_setting(&"high_contrast", false))
	_hostile_outline_points.clear()
	_hostile_outline_colors.clear()
	_hostile_core_points.clear()
	_hostile_core_colors.clear()
	for shot in hostile_shots:
		var position_value: Vector2 = shot["position"]
		var velocity_value: Vector2 = shot["velocity"]
		var forward := velocity_value.normalized()
		if forward.is_zero_approx():
			forward = Vector2.RIGHT
		var reflectable := bool(shot.get("reflectable", true))
		var color: Color = shot["color"]
		var stroke := Color(1.0, 0.68, 0.20, 0.98) if not reflectable else (Color(1.0, 0.96, 0.80, 0.96) if high_contrast else Color(color.r, color.g, color.b, 0.94))
		_hostile_outline_points.append(position_value - forward * 7.0)
		_hostile_outline_points.append(position_value + forward * (15.0 if not reflectable else 10.0))
		_hostile_outline_colors.append(stroke)
		if not reflectable:
			var side := forward.orthogonal()
			_hostile_core_points.append(position_value - side * 7.0)
			_hostile_core_points.append(position_value + side * 7.0)
			_hostile_core_colors.append(Color(0.015, 0.008, 0.0, 1.0))
	if not _hostile_outline_points.is_empty():
		draw_multiline_colors(_hostile_outline_points, _hostile_outline_colors, 3.0, true)
	if not _hostile_core_points.is_empty():
		draw_multiline_colors(_hostile_core_points, _hostile_core_colors, 2.2, true)


func _draw_return_lights() -> void:
	for light in return_lights:
		var position_value: Vector2 = light["position"]
		var velocity_value: Vector2 = light["velocity"]
		var direction := velocity_value.normalized()
		draw_line(position_value - direction * 28.0, position_value, Color(0.32, 0.91, 0.85, 0.34), 5.0, true)
		draw_circle(position_value, 16.0, Color(1.0, 0.71, 0.27, 0.06))
		draw_colored_polygon(_diamond(position_value, velocity_value.angle(), 11.0, 5.0), Color(1.0, 0.78, 0.38, 0.96))
		draw_circle(position_value, 2.0, Color.WHITE)


func _draw_particles() -> void:
	_particle_line_points.clear()
	_particle_line_colors.clear()
	for particle in particles:
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var color: Color = particle["color"]
		color.a = life_ratio * 0.86
		var position_value: Vector2 = particle["position"]
		var particle_size := float(particle["size"]) * life_ratio
		var direction := Vector2.from_angle(float(particle["rotation"]))
		_particle_line_points.append(position_value - direction * particle_size)
		_particle_line_points.append(position_value + direction * particle_size)
		_particle_line_colors.append(color)
	if not _particle_line_points.is_empty():
		draw_multiline_colors(_particle_line_points, _particle_line_colors, 2.0, true)


func _draw_particles_reduced() -> void:
	_particle_line_points.clear()
	_particle_line_colors.clear()
	for index in range(0, particles.size(), 2):
		var particle: Dictionary = particles[index]
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var color: Color = particle["color"]
		color.a = life_ratio * 0.86
		var position_value: Vector2 = particle["position"]
		var particle_size := float(particle["size"]) * life_ratio
		var direction := Vector2.from_angle(float(particle["rotation"]))
		_particle_line_points.append(position_value - direction * particle_size)
		_particle_line_points.append(position_value + direction * particle_size)
		_particle_line_colors.append(color)
	if not _particle_line_points.is_empty():
		draw_multiline_colors(_particle_line_points, _particle_line_colors, 2.0, true)


func _diamond(center: Vector2, angle: float, length: float, width: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle)
	var side := forward.rotated(PI * 0.5)
	return PackedVector2Array([
		center + forward * length,
		center + side * width,
		center - forward * length * 0.72,
		center - side * width,
	])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _rotated_points(center: Vector2, angle: float, source: Array[Vector2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in source:
		result.append(center + point.rotated(angle))
	return result


func _scaled_points(points: PackedVector2Array, center: Vector2, scale_factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(center + (point - center) * scale_factor)
	return result


func CYAN() -> Color:
	return Color(0.30, 0.88, 0.86)
