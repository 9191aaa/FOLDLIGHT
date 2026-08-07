extends SceneTree

## Every authored upgrade modifier must have a runtime owner, including one-shot
## pickup effects and stateful dash/Fold/survival interactions.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FoldlightBuildResolver.modifier_validation_errors().is_empty(), "all thirty-six upgrades use supported runtime modifier keys")
	var world_scene := load("res://scenes/roguelite/rogue_world.tscn") as PackedScene
	var player_scene := load("res://scenes/player.tscn") as PackedScene
	var world := world_scene.instantiate() as FoldlightRogueWorld
	var player := player_scene.instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.global_position = Vector2(400, 540)
	world.load_room(player, &"upgrade_runtime", Vector2(2400, 1350), [], Color(0.32, 0.84, 0.82), 76001)
	world.activate()
	var combat := world.combat_runtime
	player.health = 4
	var levels := {
		"steady_lantern": 2, "rapid_crease": 2, "prism_echo": 2, "hunter_mark": 1,
		"wide_return": 2, "clean_crease": 1, "afterglow": 2, "perfect_release": 1,
		"double_step": 1, "razor_wake": 1, "foldstep": 2, "quick_recovery": 1, "phase_feather": 1, "kinetic_paper": 1,
		"thick_paper": 1, "mend_on_clear": 1, "last_lantern": 1, "glimmer_guard": 1, "large_burden": 1, "ink_immunity": 1, "steady_heart": 1,
	}
	var stats := combat.apply_run_build(levels, &"thick_paper")
	_check(player.max_health == 6 and player.health == 5, "max-health pickup applies its one-time heal after raising the cap")
	_check(player.dash_component.maximum_charges == 2 and player.dash_component.charges == 2, "Double Step grants a real second dash charge")
	_check(player.request_dash(Vector2.RIGHT), "first charged dash starts")
	player.dash_component.tick(player.dash_component.get_effective_duration() + 0.01)
	_check(player.request_dash(Vector2.UP), "second charge can be spent before the first recharge finishes")
	player.dash_component.tick(player.dash_component.get_effective_duration() + 0.01)
	_check(not player.request_dash(Vector2.LEFT), "empty dash charges still respect recharge")

	player.apply_status(&"wet_ink", 4.0)
	player.folding = true
	player.captured = player.get_capture_capacity()
	player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	player.dash_component.cooldown_remaining = 1.0
	player.dash_component.charges = 0
	var return_before := combat.projectiles.size()
	_check(player.release_fold_action(), "full loaded Fold releases through the live runtime")
	_check(not player.has_status(&"wet_ink"), "Clean Crease removes a status on full release")
	_check(combat._shield_charges == 2, "Afterglow grants its authored release shield layers")
	_check(player.fold_component.cooldown_remaining < player.fold_component.roguelite_cooldown, "Perfect Release refunds part of Fold cooldown")
	_check(player.dash_component.cooldown_remaining < 1.0, "Foldstep refunds dash cooldown from a meaningful release")
	_check(combat.projectiles.size() == return_before + player.get_capture_capacity(), "full Fold creates exactly one return projectile per stored light")
	_check(combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.style == &"return_light").all(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.damage > 3.0), "return and full-release multipliers reach the spawned damage snapshots")

	combat._shield_charges = 0
	combat._shield_remaining = 0.0
	player.health = 1
	player.invulnerability = 0.0
	combat._try_hit_player()
	_check(player.health == 1 and player.invulnerability >= 1.8, "Last Lantern consumes one fatal guard instead of permanent meta health")
	player.invulnerability = 0.0
	combat._try_hit_player()
	_check(player.health == 0, "fatal guard is one-use and does not make the run immortal")
	player.health = 3
	combat._on_room_cleared({})
	_check(player.health == 3, "single Mend on Clear stack banks half a heal")
	combat._on_room_cleared({})
	_check(player.health == 4, "banked room-clear healing resolves deterministically")

	combat._shield_charges = 0
	combat._shield_remaining = 0.0
	_check(combat.grant_region_shield(20) == 2, "Glimmer Guard converts a region boundary into at most two temporary shields")
	_check(is_equal_approx(combat.get_glimmer_gain_multiplier(), 1.25), "Large Burden exposes its promised glimmer upside")
	_check(is_equal_approx(player.hit_radius, 13.0 * 1.22), "Large Burden's visible body cost remains an honest physical hitbox")
	_check(player.damage_grace_add > 0.0 and player.status_effects.slow_severity_multiplier < 1.0, "survival resistance and damage grace reach player-owned components")

	player.health = 5
	player.invulnerability = 0.0
	player.active_item_slot.replace(FoldlightRogueContentCatalog.active_item_by_id(&"sun_stamp"))
	player.active_item_slot.cooldown_remaining = 0.0
	player.focus = 0.0
	_check(player.request_active_item(), "Sun Stamp activates from the same one-slot interface")
	combat._update_temporary_effects(0.0)
	_check(not player.fold_temporarily_locked and float(combat.get("_weapon_haste")) >= 2.0 and player.focus >= 0.49, "weapon overdrive now adds immediate Fold tempo instead of disabling the core mechanic")
	combat._update_temporary_effects(5.0)
	_check(float(combat.get("_weapon_haste")) >= 2.0, "weapon overdrive remains useful through its stated duration")
	combat._update_temporary_effects(1.1)
	_check(is_equal_approx(float(combat.get("_weapon_haste")), 1.0), "weapon overdrive cleanly ends after its visible duration")

	world.queue_free()
	player.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_UPGRADE_RUNTIME_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_UPGRADE_RUNTIME_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
