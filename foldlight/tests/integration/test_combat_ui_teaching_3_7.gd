extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene
	var presentation := packed.instantiate() as FoldlightRoguePresentation if packed != null else null
	_check(presentation != null, "combat presentation scene instantiates")
	if presentation == null:
		_finish()
		return
	root.add_child(presentation)
	await process_frame

	presentation.show_mechanic_card({
		"content_id": &"paper_turret",
		"preview_kind": &"enemy",
		"preview_id": &"paper_turret",
		"attack_style": &"aimed_volley",
		"title": "折纸炮台",
		"description": "固定炮台，会先锁定一条直线。",
		"role_title": "阵地单位",
		"rule": "红线锁定后，沿直线齐射五枚可反射弹。",
		"counterplay": "看到红线就横向离开；齐射结束再贴近输出。",
		"accent": Color(1.0, 0.37, 0.27),
	})
	var enemy_brief := presentation.get_mechanic_briefing_snapshot()
	var enemy_preview: Dictionary = enemy_brief.get("preview", {})
	_check(enemy_brief.get("rule_heading", "") == "它怎么打" and enemy_brief.get("counterplay_heading", "") == "怎么躲", "briefing uses direct natural-language headings")
	_check(bool(enemy_preview.get("animated", false)) and bool(enemy_preview.get("shows_actor", false)) and bool(enemy_preview.get("shows_attack", false)), "first enemy briefing animates both silhouette and attack")
	_check(StringName(enemy_preview.get("preview_id", &"")) == &"paper_turret" and StringName(enemy_preview.get("attack_style", &"")) == &"aimed_volley", "enemy preview preserves authored identity and attack style")
	_check(presentation._mechanic_intro_attack_caption.text.contains("五弹齐射"), "attack vignette names the demonstrated sequence")

	presentation.show_boss_card({
		"content_id": &"reef_crown_battery", "preview_id": &"reef_crown_battery",
		"attack_style": &"tide_gap", "title": "礁冠炮城", "description": "第一海域首领。",
		"role_title": "区域首领", "rule": "橙色潮环向外扩散，但环上始终留有缺口。",
		"counterplay": "沿青色缺口方向移动，不要穿过橙色实体环。", "accent": Color(1.0, 0.62, 0.24),
	})
	var boss_preview: Dictionary = presentation.get_mechanic_briefing_snapshot().get("preview", {})
	_check(StringName(boss_preview.get("preview_kind", &"")) == &"boss" and StringName(boss_preview.get("attack_style", &"")) == &"tide_gap", "bosses share the same animated briefing with boss-specific attacks")
	_check(presentation._mechanic_intro_attack_caption.text.contains("青色缺口"), "first boss preview explains the orange ring through its safe gap")

	presentation.flash_player_damage()
	_check(presentation.visual_canvas.get_damage_flash_strength() >= 0.99, "player damage API starts a full edge-weighted red flash")
	await create_timer(0.28).timeout
	_check(presentation.visual_canvas.get_damage_flash_strength() <= 0.01, "damage flash clears quickly and cannot obscure bullet reading")

	presentation.show_title({"prologue_complete": true})
	var has_endless := false
	for node in _descendants(presentation.interface):
		if node is Button and (node as Button).text.contains("无尽生存"):
			has_endless = true
			break
	_check(has_endless and presentation.has_signal("endless_requested"), "title exposes a controller-focusable endless survival entry")

	presentation.show_hud()
	_check(presentation.interface.find_child("HealthCard", true, false) != null and presentation._hud_health_bar != null, "health has a dedicated high-visibility card and bar")
	_check(presentation._hud_dash_bar != null and presentation._hud_active_bar != null and presentation._hud_weapon_bar != null, "dash, active item, and automatic weapon have independent status bars")
	_check(presentation.interface.find_child("FoldCorePanel", true, false) != null, "new HUD keeps Fold as its central 2.0 anchor")

	var purple := FoldlightRogueUITheme.comfort_accent(Color(0.70, 0.36, 0.84))
	var orange := FoldlightRogueUITheme.comfort_accent(Color(1.0, 0.62, 0.24))
	_check(purple.s <= 0.45 and purple.v <= 0.73, "chapter-two purple is saturation and luminance capped")
	_check(orange.s <= 0.59 and orange.v <= 0.81, "chapter-three orange is saturation and luminance capped")

	presentation.queue_free()
	await process_frame
	_finish()


func _descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_COMBAT_UI_TEACHING_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_COMBAT_UI_TEACHING_3_7: FAIL — %s" % ", ".join(_failures))
		quit(1)
