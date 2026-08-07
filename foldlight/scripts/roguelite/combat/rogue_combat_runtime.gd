class_name FoldlightRogueCombatRuntime
extends Node2D

signal enemy_spawned(actor: Node2D, entry: Dictionary)
signal enemy_defeated(enemy_id: StringName)
signal enemy_defeated_detailed(enemy_id: StringName, entry: Dictionary)
signal projectile_spawned(projectile: FoldlightRogueProjectile)
signal projectile_captured(captured_count: int, position: Vector2)
signal player_hit(health_remaining: int)
signal active_item_resolved(item_id: StringName, snapshot: Dictionary)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/roguelite/combat/rogue_projectile.tscn")
const TELEGRAPH_SCENE: PackedScene = preload("res://scenes/roguelite/combat/spawn_telegraph.tscn")
const ZONE_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/ink_denial_zone.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
const BOSS_TELEGRAPH_SCENE: PackedScene = preload("res://scenes/roguelite/bosses/boss_attack_telegraph.tscn")
const MAX_PROJECTILES: int = 260
const HIT_VFX_BUDGET_MAX: float = 8.0
const HIT_VFX_REFILL_PER_SECOND: float = 18.0
const HIT_VFX_MAX_BURSTS: int = 18
const HIT_VFX_DURATION: float = 0.22
const RETURN_NAV_CELL_SIZE: float = 52.0
const RETURN_NAV_CLEARANCE: float = 18.0
const RETURN_NAV_CACHE_LIMIT: int = 256
const RETURN_NAV_TARGET_LIMIT: int = 10

var active: bool = false
var room: FoldlightRoomRuntime
var player: FoldlightPlayer
var enemies: Array[Node2D] = []
var projectiles: Array[FoldlightRogueProjectile] = []

var _spawn_serial: int = 0
var _support_refresh: float = 0.0
var _hostile_slow_remaining: float = 0.0
var _hostile_time_scale: float = 1.0
var _hostile_slow_scale: float = 0.55
var _weapon_overdrive_remaining: float = 0.0
var _weapon_haste: float = 1.0
var _weapon_haste_value: float = 1.0
var _fold_lock_remaining: float = 0.0
var _decoy_remaining: float = 0.0
var _decoy_position: Vector2 = Vector2.ZERO
var _shield_charges: int = 0
var _shield_remaining: float = 0.0
var _build_stats: Dictionary = {}
var _fatal_guards_remaining: int = 0
var _clear_heal_progress: float = 0.0
var _dash_trail_remaining: float = 0.0
var _terrain_cleanse_remaining: float = 0.0
var _terrain_hurt_remaining: float = 0.0
var _release_hit_stop_remaining: float = 0.0
var _active_flashes: Array[Dictionary] = []
var _enemy_hit_bursts: Array[Dictionary] = []
var _hit_vfx_tokens: float = HIT_VFX_BUDGET_MAX
var _return_navigation_grid: AStarGrid2D
var _return_navigation_size: Vector2i = Vector2i.ZERO
var _return_route_cache: Dictionary = {}
var _return_nav_queries: int = 0
var _return_nav_cache_hits: int = 0
var _return_nav_rebuilds: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	_rng.seed = 330031


func bind(new_room: FoldlightRoomRuntime, new_player: FoldlightPlayer, run_seed: int = 330031) -> void:
	_unbind_signals()
	clear_combat()
	room = new_room
	player = new_player
	_rng.seed = run_seed
	if room != null:
		room.encounter_spawn_telegraph.connect(_on_spawn_telegraph)
		room.encounter_enemy_requested.connect(_on_enemy_requested)
	if player != null:
		player.weapon_mount.shot_requested.connect(_on_player_shot_requested)
		player.fold_released.connect(_on_player_fold_released)
		player.active_item_slot.item_used.connect(_on_active_item_used)
		player.dash_started.connect(_on_player_dash_started)
		player.dash_ended.connect(_on_player_dash_ended)
		apply_build_stats(player.rogue_build_stats)
	if room != null:
		room.encounter_cleared.connect(_on_room_cleared)
	_build_return_navigation_grid()


func set_active(value: bool) -> void:
	active = value
	set_physics_process(active)


func apply_build_stats(stats: Dictionary) -> void:
	_build_stats = stats.duplicate(true)
	_fatal_guards_remaining = maxi(_fatal_guards_remaining, int(round(float(_build_stats.get("fatal_guard_count", 0.0)))))
	if player != null:
		player.weapon_mount.configure_build(_build_stats)


func apply_run_build(upgrade_levels: Dictionary, newly_acquired_id: StringName = &"") -> Dictionary:
	if player == null:
		return {}
	var stats := player.apply_roguelite_build(upgrade_levels)
	apply_build_stats(stats)
	if not newly_acquired_id.is_empty():
		var definition := FoldlightRogueContentCatalog.upgrade_by_id(newly_acquired_id)
		if definition != null:
			player.health = mini(player.max_health, player.health + int(round(float(definition.stat_modifiers.get("instant_heal", 0.0)))))
	return stats


func grant_region_shield(glimmer: int) -> int:
	var layers_per_ten := int(round(float(_build_stats.get("region_shield_per_ten_glimmer", 0.0))))
	var granted := mini(2, maxi(0, glimmer / 10 * layers_per_ten))
	_shield_charges = maxi(_shield_charges, granted)
	_shield_remaining = 9999.0 if granted > 0 else _shield_remaining
	return granted


func get_glimmer_gain_multiplier() -> float:
	return maxf(1.0, float(_build_stats.get("glimmer_gain_multiplier", 1.0)))


func clear_combat() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	_hostile_slow_remaining = 0.0
	_hostile_time_scale = 1.0
	_hostile_slow_scale = 0.55
	_weapon_overdrive_remaining = 0.0
	_weapon_haste = 1.0
	_weapon_haste_value = 1.0
	_fold_lock_remaining = 0.0
	if player != null:
		player.fold_temporarily_locked = false
	_decoy_remaining = 0.0
	_shield_charges = 0
	_shield_remaining = 0.0
	_dash_trail_remaining = 0.0
	_terrain_cleanse_remaining = 0.0
	_terrain_hurt_remaining = 0.0
	_release_hit_stop_remaining = 0.0
	_active_flashes.clear()
	_enemy_hit_bursts.clear()
	_hit_vfx_tokens = HIT_VFX_BUDGET_MAX
	_return_route_cache.clear()
	_return_nav_queries = 0
	_return_nav_cache_hits = 0
	queue_redraw()


func spawn_hostile_volley(snapshot: Dictionary) -> int:
	var count := clampi(int(snapshot.get("projectile_count", 1)), 1, 18)
	var origin := Vector2(snapshot.get("origin", Vector2.ZERO))
	var exact_projectiles: Array = snapshot.get("projectiles", [])
	if not exact_projectiles.is_empty():
		count = mini(18, exact_projectiles.size())
		for index in count:
			var exact: Dictionary = exact_projectiles[index]
			var exact_direction := Vector2(exact.get("direction", Vector2.DOWN)).normalized()
			if exact_direction.is_zero_approx():
				exact_direction = Vector2.DOWN
			_spawn_projectile({
				"origin": origin,
				"velocity": exact_direction * float(exact.get("speed", snapshot.get("speed", 300.0))),
				"hostile": true,
				"reflectable": bool(snapshot.get("reflectable", true)),
				"damage": float(snapshot.get("damage", 1.0)),
				"radius": float(snapshot.get("radius", 7.0)),
				"lifetime": float(snapshot.get("lifetime", 5.0)),
				"style": StringName(snapshot.get("style", &"hostile_petal")),
				"kind": int(snapshot.get("kind", 0)),
				"color": Color(snapshot.get("color", Color(0.68, 0.27, 0.70))),
				"curve": float(exact.get("curve", snapshot.get("curve", 0.0))),
				"status": StringName(snapshot.get("status", &"")),
				"status_duration": float(snapshot.get("status_duration", 0.0)),
			})
		return count
	var base_direction := Vector2(snapshot.get("direction", Vector2.DOWN)).normalized()
	if base_direction.is_zero_approx():
		base_direction = Vector2.DOWN
	var spread := float(snapshot.get("spread_radians", 0.0))
	var base_curve := float(snapshot.get("curve", 0.0))
	var burst_count := clampi(int(snapshot.get("burst_count", 1)), 1, 4)
	var burst_interval := clampf(float(snapshot.get("burst_interval", 0.0)), 0.0, 0.4)
	var burst_angle_step := clampf(float(snapshot.get("burst_angle_step", 0.0)), -0.5, 0.5)
	for burst_index in burst_count:
		for index in count:
			var direction: Vector2
			var curve := base_curve
			var burst_rotation := float(burst_index) * burst_angle_step
			if bool(snapshot.get("radial", false)):
				direction = base_direction.rotated(float(index) / float(count) * TAU + burst_rotation)
				curve *= sin(float(index) * 1.7)
			else:
				var unit := 0.0 if count <= 1 else float(index) / float(count - 1) - 0.5
				direction = base_direction.rotated(unit * spread + burst_rotation)
				if count > 1:
					curve *= unit * spread
			_spawn_projectile({
				"origin": origin,
				"velocity": direction * float(snapshot.get("speed", 300.0)),
				"hostile": true,
				"reflectable": bool(snapshot.get("reflectable", true)),
				"damage": float(snapshot.get("damage", 1.0)),
				"radius": float(snapshot.get("radius", 7.0)),
				"lifetime": float(snapshot.get("lifetime", 5.0)),
				"style": StringName(snapshot.get("style", &"hostile_petal")),
				"kind": int(snapshot.get("kind", 0)),
				"color": Color(snapshot.get("color", Color(0.68, 0.27, 0.70))),
				"curve": curve,
				"launch_delay": float(burst_index) * burst_interval,
				"status": StringName(snapshot.get("status", &"")),
				"status_duration": float(snapshot.get("status_duration", 0.0)),
			})
	return count * burst_count


## Adapter entry for modes that add scheduling around the 2.0 combat runtime.
## Callers choose when and where a wave appears; the factory, actors, attacks,
## projectiles, damage and hit feedback remain the original combat chain.
func spawn_directed_wave(entries: Array[Dictionary]) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for source_entry in entries:
		var entry := source_entry.duplicate(true)
		if not entry.has("spawn_position"):
			entry["spawn_position"] = Vector2(entry.get("position", Vector2.ZERO))
		var actor := _spawn_enemy_from_entry(entry, false)
		if actor != null:
			spawned.append(actor)
	return spawned


func damage_all_enemies(amount: float) -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.call("take_damage", amount)
			_register_enemy_hit_feedback(_enemy_feedback_key(enemy), enemy.global_position, Vector2.ZERO, amount)


func _physics_process(delta: float) -> void:
	if not active or room == null or player == null:
		return
	_update_temporary_effects(delta)
	if _release_hit_stop_remaining > 0.0:
		_release_hit_stop_remaining = maxf(0.0, _release_hit_stop_remaining - delta)
		return
	_update_terrain_effects(delta)
	player.tick_automatic_weapons(delta * _weapon_haste, not enemies.is_empty())
	_update_support_links(delta)
	_update_enemies(delta)
	_update_dash_trail(delta)
	_update_projectiles(delta)
	_update_denial_zones()


func _update_temporary_effects(delta: float) -> void:
	_hostile_slow_remaining = maxf(0.0, _hostile_slow_remaining - delta)
	_hostile_time_scale = _hostile_slow_scale if _hostile_slow_remaining > 0.0 else 1.0
	_weapon_overdrive_remaining = maxf(0.0, _weapon_overdrive_remaining - delta)
	_fold_lock_remaining = maxf(0.0, _fold_lock_remaining - delta)
	player.fold_temporarily_locked = _fold_lock_remaining > 0.0
	_weapon_haste = _weapon_haste_value if _weapon_overdrive_remaining > 0.0 else 1.0
	_decoy_remaining = maxf(0.0, _decoy_remaining - delta)
	_shield_remaining = maxf(0.0, _shield_remaining - delta)
	_terrain_cleanse_remaining = maxf(0.0, _terrain_cleanse_remaining - delta)
	_terrain_hurt_remaining = maxf(0.0, _terrain_hurt_remaining - delta)
	if _shield_remaining <= 0.0:
		_shield_charges = 0
	if not _active_flashes.is_empty():
		for index in range(_active_flashes.size() - 1, -1, -1):
			var flash := _active_flashes[index]
			flash["remaining"] = maxf(0.0, float(flash.get("remaining", 0.0)) - delta)
			if float(flash.get("remaining", 0.0)) <= 0.0:
				_active_flashes.remove_at(index)
		queue_redraw()
	_update_enemy_hit_vfx(delta)


func _update_enemies(delta: float) -> void:
	var target := _decoy_position if _decoy_remaining > 0.0 else player.global_position
	var ally_center := _enemy_center()
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy is FoldlightBellBinder:
			(enemy as FoldlightBellBinder).advance_simulation(delta, player.global_position, ally_center, _hostile_time_scale)
		elif enemy is FoldlightPrismBulwark:
			(enemy as FoldlightPrismBulwark).advance_simulation(delta, target, _hostile_time_scale)
		elif enemy is FoldlightBroodLantern:
			(enemy as FoldlightBroodLantern).advance_simulation(delta, target, _hostile_time_scale)
		elif enemy is FoldlightShearScribe:
			(enemy as FoldlightShearScribe).advance_simulation(delta, target, _hostile_time_scale)
		elif enemy is FoldlightPaperTurret:
			(enemy as FoldlightPaperTurret).advance_simulation(delta, target, _hostile_time_scale)
		elif enemy is FoldlightInkWarden:
			(enemy as FoldlightInkWarden).advance_simulation(delta, player.global_position, _hostile_time_scale)
		elif enemy is FoldlightRogueBossActor:
			(enemy as FoldlightRogueBossActor).advance_simulation(delta, player.global_position, _hostile_time_scale)
		elif enemy is FoldlightRogueEnemyActor:
			(enemy as FoldlightRogueEnemyActor).advance_simulation(delta, target, _hostile_time_scale)
		if enemy is CharacterBody2D:
			var contact_radius := float(enemy.call("get_contact_radius")) if enemy.has_method("get_contact_radius") else 24.0
			var dangerous := bool(enemy.call("is_contact_dangerous")) if enemy.has_method("is_contact_dangerous") else true
			if dangerous and enemy.global_position.distance_to(player.global_position) <= player.get_hit_radius() + contact_radius:
				_try_hit_player(player.global_position - enemy.global_position)


func _update_support_links(delta: float) -> void:
	_support_refresh -= delta
	if _support_refresh > 0.0:
		return
	_support_refresh = 0.18
	var snapshots: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("get_combat_snapshot"):
			continue
		var snapshot := enemy.call("get_combat_snapshot") as Dictionary
		snapshots.append(snapshot)
		by_id[StringName(snapshot.get("id", &""))] = enemy
		if enemy.has_method("set_support_buff"):
			enemy.call("set_support_buff", 1.0)
	for enemy in enemies:
		if not enemy is FoldlightBellBinder:
			continue
		var binder := enemy as FoldlightBellBinder
		binder.update_tethers(snapshots)
		var buff := binder.get_buff_snapshot()
		for target_id in binder.get_tether_ids():
			var target_variant: Variant = by_id.get(target_id)
			if target_variant is Node and (target_variant as Node).has_method("set_support_buff"):
				(target_variant as Node).call("set_support_buff", float(buff.get("attack_interval_multiplier", 0.78)))


func _update_projectiles(delta: float) -> void:
	for projectile in projectiles.duplicate():
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			projectiles.erase(projectile)
			continue
		var projectile_scale := _hostile_time_scale if projectile.hostile else 1.0
		if not projectile.hostile and projectile.style == &"return_light":
			_update_return_light_navigation(projectile, delta)
		elif not projectile.hostile and projectile.homing_strength > 0.0 and not projectile.has_valid_homing_target():
			projectile.set_homing_target(_select_homing_target(projectile.global_position, projectile.homing_range))
		if projectile.hostile and player.folding and projectile.global_position.distance_to(player.global_position) <= player.get_fold_radius():
			var fold_radius := maxf(1.0, player.get_fold_radius())
			var fold_distance: float = projectile.global_position.distance_to(player.global_position)
			var fold_scale: float = clampf(lerpf(0.10, 0.36, fold_distance / fold_radius), 0.055, 0.42)
			if projectile.reflectable and player.capture_one():
				_add_active_flash(projectile.global_position, Color(0.42, 0.94, 0.86), 66.0, 0.24)
				projectile_captured.emit(player.captured, projectile.global_position)
				_remove_projectile(projectile)
				continue
			projectile.fold_slowed = true
			projectile_scale *= fold_scale
		else:
			projectile.fold_slowed = false
		if projectile.advance_simulation(delta, projectile_scale):
			_remove_projectile(projectile)
			continue
		if not room.room_bounds.grow(120.0).has_point(projectile.global_position):
			_remove_projectile(projectile)
			continue
		if _resolve_projectile_terrain(projectile, delta):
			_remove_projectile(projectile)
			continue
		if projectile.hostile:
			if projectile.global_position.distance_to(player.global_position) <= projectile.radius + player.get_hit_radius():
				if _try_hit_player(projectile.velocity) and not projectile.status_id.is_empty():
					player.apply_status(projectile.status_id, projectile.status_duration)
				_remove_projectile(projectile)
		else:
			if _try_mirror_interception(projectile):
				_remove_projectile(projectile)
			else:
				_resolve_friendly_collision(projectile)


func _update_terrain_effects(delta: float) -> void:
	if room == null or player == null:
		return
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_meta("thorn_cooldown", maxf(0.0, float(enemy.get_meta("thorn_cooldown", 0.0)) - delta))
	for piece in room.get_terrain_pieces():
		var player_inside := piece.contains_world_point(player.global_position)
		if piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL and player_inside and _terrain_cleanse_remaining <= 0.0:
			player.apply_status(&"wet_ink", 0.28)
		elif piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE and player_inside:
			player.velocity += piece.effect_direction.rotated(piece.rotation) * piece.effect_strength * 520.0 * delta
		elif piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH and player_inside:
			player.apply_status(&"sunlit", 0.28)
			player.add_focus(0.09 * piece.effect_strength * delta)
		elif piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER and player_inside and _terrain_cleanse_remaining <= 0.0 and _terrain_hurt_remaining <= 0.0:
			_try_hit_player(-player.velocity)
			_terrain_hurt_remaining = 0.9
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is CharacterBody2D or not piece.contains_world_point((enemy as Node2D).global_position):
				continue
			if piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE:
				(enemy as CharacterBody2D).velocity += piece.effect_direction.rotated(piece.rotation) * piece.effect_strength * 260.0 * delta
			elif piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER and float(enemy.get_meta("thorn_cooldown", 0.0)) <= 0.0 and enemy.has_method("take_damage"):
				enemy.call("take_damage", 1.6 * piece.effect_strength)
				_register_enemy_hit_feedback(_enemy_feedback_key(enemy), enemy.global_position, -piece.effect_direction.rotated(piece.rotation), 1.6 * piece.effect_strength)
				enemy.set_meta("thorn_cooldown", 0.72)


func _resolve_projectile_terrain(projectile: FoldlightRogueProjectile, delta: float) -> bool:
	# The 2.0 return ribbon is still stored light while it orbits the player;
	# nearby cover must not erase ammunition before its staggered launch.
	if not projectile.hostile and projectile.launch_delay > 0.0:
		return false
	var grace := maxf(0.0, float(projectile.get_meta("terrain_grace", 0.0)) - delta)
	projectile.set_meta("terrain_grace", grace)
	if grace > 0.0:
		return false
	for piece in room.get_terrain_pieces():
		if piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH and not projectile.hostile and piece.contains_world_point(projectile.global_position):
			var accelerated_speed := minf(1500.0, projectile.velocity.length() * (1.0 + 0.75 * delta))
			projectile.velocity = projectile.velocity.normalized() * accelerated_speed
			continue
		if not piece.kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
			continue
		if not piece.contains_world_point(projectile.global_position):
			continue
		if not projectile.hostile and projectile.style == &"return_light":
			projectile.recover_from_solid(piece.global_position)
			projectile.set_meta("terrain_grace", 0.055)
			return false
		if piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR and projectile.reflectable:
			var radial := piece.global_position.direction_to(projectile.global_position)
			if radial.is_zero_approx():
				radial = Vector2.RIGHT
			var incoming := projectile.velocity.normalized()
			var tangent := radial.orthogonal()
			if tangent.dot(incoming) < 0.0:
				tangent = -tangent
			projectile.velocity = tangent * projectile.velocity.length()
			projectile.global_position = piece.global_position + radial * (minf(piece.piece_size.x, piece.piece_size.y) * 0.5 + projectile.radius + 6.0)
			projectile.set_meta("terrain_grace", 0.16)
			return false
		return true
	return false


func _resolve_friendly_collision(projectile: FoldlightRogueProjectile) -> void:
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.has_method("take_damage"):
			continue
		var actor_id := StringName(enemy.get("actor_id"))
		if projectile.hit_actor_ids.has(actor_id):
			continue
		if projectile.global_position.distance_to(enemy.global_position) > projectile.radius + 27.0:
			continue
		projectile.hit_actor_ids[actor_id] = true
		var applied_damage := projectile.damage
		var enemy_health := float(enemy.get("health"))
		var maximum_health := enemy_health
		if enemy.has_method("get_combat_snapshot"):
			maximum_health = float((enemy.call("get_combat_snapshot") as Dictionary).get("maximum_health", enemy_health))
		if maximum_health > 0.0 and enemy_health / maximum_health <= 0.30:
			applied_damage *= projectile.execute_damage_multiplier
		var target_defeated := false
		if projectile.style == &"tide_bell":
			_damage_enemies_in_radius(projectile.global_position, 150.0, applied_damage)
		elif enemy is FoldlightRogueBossActor:
			var source: StringName = &"return" if projectile.style == &"return_light" else &"weapon"
			target_defeated = (enemy as FoldlightRogueBossActor).take_damage(applied_damage, source)
		elif enemy.has_method("take_projectile_damage"):
			target_defeated = bool(enemy.call("take_projectile_damage", applied_damage, projectile.velocity, projectile.style))
		else:
			target_defeated = bool(enemy.call("take_damage", applied_damage))
		if projectile.style != &"tide_bell":
			_register_enemy_hit_feedback(actor_id, projectile.global_position, projectile.velocity, applied_damage)
		if not projectile.is_echo and projectile.echo_chance > 0.0 and _rng.randf() <= projectile.echo_chance:
			var echo_direction := projectile.velocity.normalized().rotated(0.32 if _rng.randf() > 0.5 else -0.32)
			_spawn_projectile({"origin": projectile.global_position + echo_direction * 34.0, "velocity": echo_direction * projectile.velocity.length(), "hostile": false, "reflectable": false, "damage": applied_damage * 0.45, "radius": projectile.radius * 0.8, "lifetime": 1.6, "pierce": 0, "style": projectile.style, "echo_chance": 0.0, "is_echo": true})
		player.feedback_budget.register_impact(0.18, false)
		if _try_activate_return_chain(projectile):
			return
		if _try_activate_return_relay(projectile, enemy, target_defeated):
			return
		if projectile.consume_pierce() or projectile.style == &"tide_bell":
			_remove_projectile(projectile)
		return


func _try_activate_return_chain(projectile: FoldlightRogueProjectile) -> bool:
	if not projectile.can_activate_return_chain():
		return false
	var assignment := _select_reachable_homing_assignment(projectile.global_position, projectile.homing_range, 0, projectile.hit_actor_ids)
	var target_variant: Variant = assignment.get("target")
	var target := target_variant as Node2D if target_variant is Node2D else null
	var route_variant: Variant = assignment.get("route", PackedVector2Array())
	var route := PackedVector2Array(route_variant) if route_variant is PackedVector2Array else PackedVector2Array()
	if target == null or route.is_empty():
		return false
	return projectile.activate_return_chain(target, route)


func _try_activate_return_relay(projectile: FoldlightRogueProjectile, defeated_enemy: Node2D, target_defeated: bool) -> bool:
	if not target_defeated or defeated_enemy is FoldlightRogueBossActor or not projectile.can_activate_return_relay():
		return false
	var assignment := _select_reachable_homing_assignment(projectile.global_position, projectile.homing_range, 0, projectile.hit_actor_ids)
	var target_variant: Variant = assignment.get("target")
	var target := target_variant as Node2D if target_variant is Node2D else null
	var route_variant: Variant = assignment.get("route", PackedVector2Array())
	var route := PackedVector2Array(route_variant) if route_variant is PackedVector2Array else PackedVector2Array()
	if target == null or route.is_empty():
		return false
	return projectile.activate_return_relay(target, route)


func _damage_enemies_in_radius(center: Vector2, radius: float, amount: float, style: StringName = &"") -> void:
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.global_position.distance_to(center) > radius:
			continue
		if style == &"return_light" and enemy is FoldlightRogueBossActor:
			(enemy as FoldlightRogueBossActor).take_damage(amount, &"return")
		elif style != &"" and enemy.has_method("take_projectile_damage"):
			enemy.call("take_projectile_damage", amount, Vector2.ZERO, style)
		elif enemy.has_method("take_damage"):
			enemy.call("take_damage", amount)
		_register_enemy_hit_feedback(_enemy_feedback_key(enemy), enemy.global_position, enemy.global_position - center, amount)


func _try_hit_player(impact_direction: Vector2 = Vector2.ZERO) -> bool:
	if not active or player == null or not player.play_enabled:
		return false
	if _shield_charges > 0 and _shield_remaining > 0.0:
		_shield_charges -= 1
		return false
	if player.health <= 1 and _fatal_guards_remaining > 0 and player.invulnerability <= 0.0:
		_fatal_guards_remaining -= 1
		player.health = 1
		player.grant_invulnerability(1.8)
		return false
	if player.take_hit(impact_direction):
		player.dash_component.refund_cooldown(float(_build_stats.get("dash_refund_on_damage", 0.0)))
		player_hit.emit(player.health)
		return true
	return false


func _on_spawn_telegraph(entry: Dictionary, duration: float) -> void:
	if room == null:
		return
	var telegraph := TELEGRAPH_SCENE.instantiate() as FoldlightSpawnTelegraph
	room.add_child(telegraph)
	telegraph.configure(entry, duration)


func _on_enemy_requested(entry: Dictionary) -> void:
	_spawn_enemy_from_entry(entry, true)


func _spawn_enemy_from_entry(entry: Dictionary, counts_for_room: bool) -> Node2D:
	var boss_definition := FoldlightRogueContentCatalog.boss_by_id(StringName(entry.get("boss_id", &"")))
	if boss_definition != null:
		return _spawn_boss_actor(boss_definition, entry, counts_for_room)
	var definition := FoldlightRogueContentCatalog.enemy_by_id(StringName(entry.get("enemy_id", &"")))
	if definition == null or room == null:
		return null
	_spawn_serial += 1
	var actor_id := StringName("%s_%d" % [definition.content_id, _spawn_serial])
	var actor := FoldlightRogueEnemyFactory.create(definition, actor_id)
	if actor == null:
		return null
	room.enemy_container.add_child(actor)
	if actor is FoldlightRogueEnemyActor:
		(actor as FoldlightRogueEnemyActor).set_arena_center(room.room_bounds.get_center())
	actor.global_position = Vector2(entry.get("spawn_position", Vector2.ZERO))
	if actor.has_signal("defeated"):
		actor.connect("defeated", _on_enemy_defeated)
	if actor.has_signal("attack_requested"):
		actor.connect("attack_requested", spawn_hostile_volley)
	if actor.has_signal("player_pressure_requested"):
		actor.connect("player_pressure_requested", _on_player_pressure_requested)
	if actor.has_signal("volley_requested"):
		actor.connect("volley_requested", spawn_hostile_volley)
	if actor.has_signal("zone_requested"):
		actor.connect("zone_requested", _on_zone_requested)
	if actor.has_signal("spawn_requested"):
		actor.connect("spawn_requested", _on_minion_requested)
	actor.set_meta("counts_for_room", counts_for_room)
	actor.set_meta("spawned_by", StringName(entry.get("spawned_by", &"")))
	actor.set_meta("directed_spawn_entry", entry.duplicate(true))
	var health_multiplier := maxf(0.1, float(entry.get("health_multiplier", 1.0)))
	if not is_equal_approx(health_multiplier, 1.0):
		var scaled_health := maxf(1.0, float(actor.get("health")) * health_multiplier)
		actor.set("health", scaled_health)
		actor.set_meta("directed_maximum_health", scaled_health)
	enemies.append(actor)
	enemy_spawned.emit(actor, entry.duplicate(true))
	return actor


func _on_player_pressure_requested(snapshot: Dictionary) -> void:
	if player == null:
		return
	player.add_focus(float(snapshot.get("focus_delta", 0.0)))
	var status_id := StringName(snapshot.get("status", &""))
	if not status_id.is_empty():
		player.apply_status(status_id, float(snapshot.get("status_duration", 0.0)))


func _try_mirror_interception(projectile: FoldlightRogueProjectile) -> bool:
	if projectile.style != &"return_light":
		return false
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("can_intercept_return_light"):
			continue
		if not bool(enemy.call("can_intercept_return_light")):
			continue
		if projectile.global_position.distance_to(enemy.global_position) > 138.0:
			continue
		return bool(enemy.call("capture_return_light"))
	return false


func _spawn_boss_actor(definition: FoldlightRogueBossDefinition, entry: Dictionary, counts_for_room: bool) -> FoldlightRogueBossActor:
	if room == null:
		return null
	var boss := BOSS_SCENE.instantiate() as FoldlightRogueBossActor
	room.enemy_container.add_child(boss)
	boss.configure(definition, room.room_bounds, _rng.randi())
	boss.global_position = Vector2(entry.get("spawn_position", room.room_bounds.get_center()))
	boss.defeated.connect(_on_enemy_defeated)
	boss.volley_requested.connect(_on_boss_volley_requested)
	boss.telegraph_requested.connect(_on_boss_telegraph_requested)
	boss.zone_requested.connect(_on_zone_requested)
	boss.minion_requested.connect(_on_boss_minion_requested)
	boss.arena_hit_requested.connect(_try_hit_player)
	boss.set_meta("counts_for_room", counts_for_room)
	enemies.append(boss)
	enemy_spawned.emit(boss, entry.duplicate(true))
	return boss


func _on_boss_telegraph_requested(snapshot: Dictionary) -> void:
	if room == null:
		return
	var telegraph := BOSS_TELEGRAPH_SCENE.instantiate() as FoldlightBossAttackTelegraph
	room.projectile_container.add_child(telegraph)
	telegraph.configure(snapshot)


func _on_boss_volley_requested(snapshot: Dictionary) -> void:
	spawn_hostile_volley(snapshot)
	var style := StringName(snapshot.get("style", &""))
	var origin := Vector2(snapshot.get("origin", Vector2.ZERO))
	match style:
		&"judgement_petal":
			_add_active_flash(origin, Color(1.0, 0.58, 0.18), 330.0, 0.46)
		&"frame_petal":
			_add_active_flash(origin, Color(1.0, 0.78, 0.34), 460.0, 0.62)
		&"black_gold_cut":
			_add_active_flash(origin, Color(1.0, 0.25, 0.14), 280.0, 0.34)
		_:
			_add_active_flash(origin, Color(0.56, 0.92, 0.84), 220.0, 0.28)


func _on_enemy_defeated(actor: Node2D) -> void:
	if not enemies.has(actor):
		return
	var definition_variant: Variant = actor.get("definition")
	var enemy_id := (definition_variant as FoldlightRogueEnemyDefinition).content_id if definition_variant is FoldlightRogueEnemyDefinition else &"enemy"
	if actor is FoldlightRogueBossActor:
		enemy_id = (actor as FoldlightRogueBossActor).definition.content_id
	var directed_entry_variant: Variant = actor.get_meta("directed_spawn_entry", {})
	var directed_entry := (directed_entry_variant as Dictionary).duplicate(true) if directed_entry_variant is Dictionary else {}
	enemies.erase(actor)
	enemy_defeated.emit(enemy_id)
	enemy_defeated_detailed.emit(enemy_id, directed_entry)
	if actor is FoldlightBroodLantern:
		var source_id := StringName(actor.get("actor_id"))
		for spawned in enemies.duplicate():
			if is_instance_valid(spawned) and StringName(spawned.get_meta("spawned_by", &"")) == source_id:
				enemies.erase(spawned)
				spawned.queue_free()
	if room != null and bool(actor.get_meta("counts_for_room", true)):
		room.notify_enemy_defeated()
	if actor is FoldlightRogueBossActor:
		for minion in enemies.duplicate():
			if is_instance_valid(minion) and not bool(minion.get_meta("counts_for_room", true)):
				enemies.erase(minion)
				minion.queue_free()
	actor.queue_free()


func _on_minion_requested(snapshot: Dictionary) -> void:
	var source_id := StringName(snapshot.get("source_id", &""))
	var enemy_id := StringName(snapshot.get("enemy_id", &"paper_drifter"))
	var maximum := clampi(int(snapshot.get("maximum", 4)), 0, 8)
	var existing := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and StringName(enemy.get_meta("spawned_by", &"")) == source_id:
			existing += 1
	var positions_variant: Variant = snapshot.get("positions", [])
	if not positions_variant is Array:
		return
	for position_variant: Variant in positions_variant:
		if existing >= maximum:
			break
		var spawn_position := Vector2(position_variant)
		if room != null:
			spawn_position = spawn_position.clamp(room.room_bounds.position + Vector2(80, 80), room.room_bounds.end - Vector2(80, 80))
		_spawn_enemy_from_entry({"enemy_id": enemy_id, "spawn_position": spawn_position, "spawned_by": source_id}, false)
		existing += 1


func _on_boss_minion_requested(snapshot: Dictionary) -> void:
	var enemy_ids: Array[StringName] = []
	var enemy_ids_variant: Variant = snapshot.get("enemy_ids", [])
	if enemy_ids_variant is Array:
		for enemy_id_variant: Variant in enemy_ids_variant:
			var staged_id := StringName(enemy_id_variant)
			if not staged_id.is_empty() and not enemy_ids.has(staged_id):
				enemy_ids.append(staged_id)
	if enemy_ids.is_empty():
		enemy_ids.append(StringName(snapshot.get("enemy_id", &"paper_turret")))
	var maximum := clampi(int(snapshot.get("maximum", 1)), 0, 6)
	var total_maximum := clampi(int(snapshot.get("total_maximum", maximum)), maximum, 6)
	var existing := 0
	var total_existing := 0
	for enemy in enemies:
		var enemy_definition: Variant = enemy.get("definition") if is_instance_valid(enemy) else null
		if not enemy_definition is FoldlightRogueEnemyDefinition or bool(enemy.get_meta("counts_for_room", true)):
			continue
		total_existing += 1
		if enemy_ids.has((enemy_definition as FoldlightRogueEnemyDefinition).content_id):
			existing += 1
	var positions_variant: Variant = snapshot.get("positions", [])
	if not positions_variant is Array:
		return
	var spawn_cursor := 0
	for position_variant: Variant in positions_variant:
		if existing >= maximum or total_existing >= total_maximum:
			break
		var enemy_id := enemy_ids[spawn_cursor % enemy_ids.size()]
		_spawn_enemy_from_entry({"enemy_id": enemy_id, "spawn_position": Vector2(position_variant)}, false)
		existing += 1
		total_existing += 1
		spawn_cursor += 1


func _on_zone_requested(snapshot: Dictionary) -> void:
	if room == null:
		return
	var zone := ZONE_SCENE.instantiate() as FoldlightInkDenialZone
	room.projectile_container.add_child(zone)
	zone.configure(snapshot)


func _update_denial_zones() -> void:
	if room == null:
		return
	for child in room.projectile_container.get_children():
		if child is FoldlightInkDenialZone:
			var zone := child as FoldlightInkDenialZone
			if zone.global_position.distance_to(player.global_position) <= zone.radius + player.get_hit_radius():
				player.apply_status(&"bound_crease", 0.3)


func _on_player_shot_requested(snapshot: Dictionary) -> void:
	var target := _select_target(int(snapshot.get("targeting", 0)), float(snapshot.get("targeting_range", 900.0)))
	if target == null:
		return
	var direction := player.global_position.direction_to(target.global_position)
	if int(snapshot.get("targeting", 0)) == FoldlightRogueWeaponDefinition.TargetingMode.FORWARD_CONE and not player.velocity.is_zero_approx():
		direction = player.velocity.normalized()
	var count := clampi(int(snapshot.get("volley_count", 1)), 1, 8)
	for index in count:
		var unit := 0.0 if count <= 1 else float(index) / float(count - 1) - 0.5
		var shot_direction := direction.rotated(unit * 0.28)
		var shot_damage := float(snapshot.get("damage", 1.0))
		if _rng.randf() <= float(snapshot.get("critical_chance", 0.0)):
			shot_damage *= 2.0
		_spawn_projectile({
			"origin": player.global_position,
			"velocity": shot_direction * float(snapshot.get("projectile_speed", 800.0)),
			"hostile": false,
			"reflectable": false,
			"damage": shot_damage,
			"radius": 7.0 * float(snapshot.get("projectile_size_multiplier", 1.0)),
			"lifetime": 3.0,
			"pierce": int(snapshot.get("pierce", 0)),
			"style": StringName(snapshot.get("projectile_style", &"crease_petal")),
			"target_position": target.global_position,
			"echo_chance": float(snapshot.get("projectile_echo_chance", 0.0)),
			"execute_damage_multiplier": float(snapshot.get("execute_damage_multiplier", 1.0)),
		})


func _on_player_fold_released(captured_count: int, charge_ratio: float) -> void:
	if captured_count <= 0:
		return
	var release_duration := minf(0.072, 0.030 + float(captured_count) * 0.0018)
	_release_hit_stop_remaining = maxf(_release_hit_stop_remaining, release_duration)
	player.add_hit_stop(release_duration)
	_add_active_flash(
		player.global_position,
		Color(0.94, 0.82, 0.42),
		420.0 + charge_ratio * 120.0,
		0.56 + minf(0.18, float(captured_count) * 0.012)
	)
	var full_release := captured_count >= player.get_capture_capacity()
	if full_release and bool(_build_stats.get("cleanse_on_full_release", false)):
		player.clear_statuses()
	var shield_threshold := maxi(1, 4 + int(round(float(_build_stats.get("release_shield_threshold", 0.0)))))
	if captured_count >= shield_threshold:
		_shield_charges += int(round(float(_build_stats.get("release_shield_layers", 0.0))))
		if _shield_charges > 0:
			_shield_remaining = maxf(_shield_remaining, 2.5)
	if captured_count >= 3:
		player.dash_component.refund_cooldown(float(_build_stats.get("dash_refund_on_release", 0.0)))
	if full_release:
		player.fold_component.cooldown_remaining *= 1.0 - clampf(float(_build_stats.get("full_release_cooldown_refund", 0.0)), 0.0, 0.8)
	var return_multiplier := float(_build_stats.get("return_damage_multiplier", 1.0))
	if full_release:
		return_multiplier *= float(_build_stats.get("full_release_damage_multiplier", 1.0))
	var return_damage := (1.45 + charge_ratio * 1.35) * return_multiplier
	var return_speed_multiplier := float(_build_stats.get("return_speed_multiplier", 1.0))
	var return_chain_add := maxi(0, int(round(float(_build_stats.get("return_chain_add", 0.0)))))
	var arc_span := minf(TAU * 0.76, 0.33 * float(captured_count))
	for index in captured_count:
		var unit := 0.5 if captured_count == 1 else float(index) / float(captured_count - 1)
		var launch_angle := -PI * 0.5 - arc_span * 0.5 + unit * arc_span
		_spawn_return_missile(player.global_position, return_damage, 0, captured_count, {
			"angle": launch_angle,
			"delay": float(index) * 0.035,
			"orbit_radius": 54.0 + float(index % 4) * 7.0,
			"orbit_anchor": player,
			"speed": (190.0 + charge_ratio * 80.0) * return_speed_multiplier,
			"homing_speed": 610.0 * return_speed_multiplier,
			"return_chain_remaining": return_chain_add,
			"lifetime": 5.6,
		})


func _on_active_item_used(definition: FoldlightRogueActiveItemDefinition) -> void:
	var resolved: Dictionary = {"effect_id": definition.effect_id, "power": definition.power, "duration": definition.duration}
	match definition.effect_id:
		&"radial_push":
			var converted := _convert_nearby_projectiles(12, 520.0, 1.35)
			_damage_enemies_in_radius(player.global_position, 330.0, definition.power, &"return_light")
			_add_active_flash(player.global_position, Color(1.0, 0.66, 0.26), 540.0, definition.duration)
			resolved["removed_projectiles"] = converted
			resolved["return_missiles"] = converted
		&"dash_decoy":
			player.dash_component.cooldown_remaining = 0.0
			player.dash_component.charges = player.dash_component.maximum_charges
			player.grant_invulnerability(1.0)
			_decoy_position = player.global_position
			_decoy_remaining = definition.duration
			_add_active_flash(player.global_position, Color(0.36, 0.78, 1.0), 260.0, 0.65)
		&"cleanse_heal":
			player.clear_statuses()
			player.health = mini(player.max_health, player.health + int(round(definition.power)))
			player.add_focus(1.0)
			_terrain_cleanse_remaining = definition.duration
			resolved["cleared_zones"] = _clear_denial_zones()
			_add_active_flash(player.global_position, Color(0.54, 1.0, 0.82), 460.0, 0.8)
		&"anchor_shield":
			_shield_charges = maxi(1, int(round(definition.power)))
			_shield_remaining = definition.duration
			resolved["return_missiles"] = _convert_nearby_projectiles(8, 430.0, 1.1)
			_add_active_flash(player.global_position, Color(0.34, 0.94, 0.92), 430.0, 0.8)
		&"hostile_slow":
			_hostile_slow_remaining = definition.duration
			_hostile_slow_scale = clampf(definition.power, 0.2, 0.8)
			_add_active_flash(player.global_position, Color(0.82, 0.48, 1.0), 620.0, 1.0)
		&"weapon_overdrive":
			_weapon_overdrive_remaining = definition.duration
			_fold_lock_remaining = 0.0
			_weapon_haste_value = maxf(1.0, definition.power)
			_weapon_haste = _weapon_haste_value
			player.add_focus(0.5)
			_add_active_flash(player.global_position, Color(1.0, 0.54, 0.20), 380.0, 0.8)
	active_item_resolved.emit(definition.content_id, resolved)


func _convert_nearby_projectiles(maximum: int, radius: float, missile_damage: float) -> int:
	var origins: Array[Vector2] = []
	for projectile in projectiles.duplicate():
		if origins.size() >= maximum:
			break
		if not projectile.hostile or not projectile.reflectable or projectile.global_position.distance_to(player.global_position) > radius:
			continue
		origins.append(projectile.global_position)
		_remove_projectile(projectile)
	for index in origins.size():
		_spawn_return_missile(origins[index], missile_damage, index, origins.size())
	return origins.size()


func _clear_denial_zones() -> int:
	if room == null:
		return 0
	var removed := 0
	for child in room.projectile_container.get_children():
		if child is FoldlightInkDenialZone:
			child.queue_free()
			removed += 1
	return removed


func _add_active_flash(position_value: Vector2, color: Color, maximum_radius: float, duration: float) -> void:
	_active_flashes.append({"position": position_value, "color": color, "radius": maximum_radius, "duration": maxf(0.1, duration), "remaining": maxf(0.1, duration)})
	queue_redraw()


func _register_enemy_hit_feedback(target_key: StringName, position_value: Vector2, incoming_velocity: Vector2, damage: float) -> void:
	var direction := incoming_velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	for burst in _enemy_hit_bursts:
		if StringName(burst.get("target_key", &"")) != target_key:
			continue
		burst["position"] = position_value
		burst["direction"] = direction
		burst["remaining"] = maxf(float(burst.get("remaining", 0.0)), HIT_VFX_DURATION * 0.62)
		burst["strength"] = minf(1.85, float(burst.get("strength", 0.0)) + 0.12 + minf(0.18, damage * 0.012))
		burst["hit_count"] = int(burst.get("hit_count", 1)) + 1
		queue_redraw()
		return
	if _hit_vfx_tokens < 1.0:
		return
	_hit_vfx_tokens -= 1.0
	if _enemy_hit_bursts.size() >= HIT_VFX_MAX_BURSTS:
		_enemy_hit_bursts.pop_front()
	_enemy_hit_bursts.append({
		"target_key": target_key,
		"position": position_value,
		"direction": direction,
		"duration": HIT_VFX_DURATION,
		"remaining": HIT_VFX_DURATION,
		"strength": clampf(0.92 + damage * 0.045, 0.92, 1.48),
		"hit_count": 1,
	})
	queue_redraw()


func _update_enemy_hit_vfx(delta: float) -> void:
	_hit_vfx_tokens = minf(HIT_VFX_BUDGET_MAX, _hit_vfx_tokens + maxf(0.0, delta) * HIT_VFX_REFILL_PER_SECOND)
	if _enemy_hit_bursts.is_empty():
		return
	for index in range(_enemy_hit_bursts.size() - 1, -1, -1):
		var burst := _enemy_hit_bursts[index]
		burst["remaining"] = maxf(0.0, float(burst.get("remaining", 0.0)) - delta)
		if float(burst.get("remaining", 0.0)) <= 0.0:
			_enemy_hit_bursts.remove_at(index)
	queue_redraw()


func get_enemy_hit_vfx_snapshot() -> Dictionary:
	var total_hits := 0
	for burst in _enemy_hit_bursts:
		total_hits += int(burst.get("hit_count", 0))
	return {
		"active_bursts": _enemy_hit_bursts.size(),
		"tokens": _hit_vfx_tokens,
		"maximum_bursts": HIT_VFX_MAX_BURSTS,
		"total_hits": total_hits,
	}


func _enemy_feedback_key(enemy: Node2D) -> StringName:
	var key := StringName(enemy.get("actor_id"))
	if key == &"":
		key = StringName("enemy_%s" % enemy.get_instance_id())
	return key


func _on_player_dash_started(_direction: Vector2, _duration: float) -> void:
	_dash_trail_remaining = 0.0


func _on_player_dash_ended() -> void:
	var haste := float(_build_stats.get("dash_weapon_haste", 0.0))
	if haste > 0.0:
		_weapon_haste_value = 1.0 + haste
		_weapon_overdrive_remaining = maxf(_weapon_overdrive_remaining, float(_build_stats.get("dash_weapon_haste_duration", 0.0)))


func _update_dash_trail(delta: float) -> void:
	var trail_damage := float(_build_stats.get("dash_trail_damage", 0.0))
	if trail_damage <= 0.0 or not player.dash_component.is_dashing():
		return
	_dash_trail_remaining -= delta
	if _dash_trail_remaining > 0.0:
		return
	_dash_trail_remaining = 0.09
	_damage_enemies_in_radius(player.global_position, 58.0, trail_damage)
	player.feedback_budget.register_impact(0.12, false)


func _on_room_cleared(_performance: Dictionary) -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and not bool(enemy.get_meta("counts_for_room", true)):
			enemies.erase(enemy)
			enemy.queue_free()
	_clear_heal_progress += maxf(0.0, float(_build_stats.get("clear_heal_progress", 0.0)))
	var heal := int(floor(_clear_heal_progress))
	if heal > 0:
		player.health = mini(player.max_health, player.health + heal)
		_clear_heal_progress -= float(heal)


func _select_target(targeting: int, maximum_range: float) -> Node2D:
	var candidates: Array[Node2D] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.global_position.distance_to(player.global_position) <= maximum_range:
			candidates.append(enemy)
	if candidates.is_empty():
		return null
	if targeting == FoldlightRogueWeaponDefinition.TargetingMode.RANDOM:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	if targeting == FoldlightRogueWeaponDefinition.TargetingMode.LOWEST_HEALTH:
		candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool: return float(a.get("health")) < float(b.get("health")))
		return candidates[0]
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	return candidates[0]


func _update_return_light_navigation(projectile: FoldlightRogueProjectile, delta: float) -> void:
	projectile.advance_navigation_refresh(delta)
	var target_invalid := not projectile.has_valid_homing_target()
	if not target_invalid:
		var current_target := projectile.homing_target
		var current_actor_id := StringName(current_target.get("actor_id"))
		target_invalid = float(current_target.get("health")) <= 0.0 or projectile.hit_actor_ids.has(current_actor_id)
	if not target_invalid and not projectile.navigation_refresh_due():
		return
	var assignment := _select_reachable_homing_assignment(projectile.global_position, projectile.homing_range, 0, projectile.hit_actor_ids)
	var target_variant: Variant = assignment.get("target")
	var target := target_variant as Node2D if target_variant is Node2D else null
	var route_variant: Variant = assignment.get("route", PackedVector2Array())
	var route := PackedVector2Array(route_variant) if route_variant is PackedVector2Array else PackedVector2Array()
	projectile.set_navigation_route(target, route)


func _select_reachable_homing_assignment(origin: Vector2, maximum_range: float, preferred_index: int = 0, excluded_actor_ids: Dictionary = {}) -> Dictionary:
	var candidates: Array[Node2D] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if float(enemy.get("health")) <= 0.0 or excluded_actor_ids.has(StringName(enemy.get("actor_id"))):
			continue
		if enemy.global_position.distance_squared_to(origin) <= maximum_range * maximum_range:
			candidates.append(enemy)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	var reachable: Array[Dictionary] = []
	for candidate in candidates.slice(0, mini(candidates.size(), RETURN_NAV_TARGET_LIMIT)):
		var route := _find_return_route(origin, candidate.global_position)
		if route.is_empty():
			continue
		reachable.append({
			"target": candidate,
			"route": route,
			"cost": _return_route_length(origin, route),
		})
	if reachable.is_empty():
		return {}
	reachable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("cost", INF)) < float(b.get("cost", INF))
	)
	# Salvos distribute across the closest reachable targets. An unreachable near
	# enemy can never steal a missile from a farther enemy with a valid route.
	return reachable[posmod(preferred_index, reachable.size())]


func _build_return_navigation_grid() -> void:
	_return_navigation_grid = null
	_return_navigation_size = Vector2i.ZERO
	_return_route_cache.clear()
	if room == null or room.room_bounds.size.x <= 0.0 or room.room_bounds.size.y <= 0.0:
		return
	_return_navigation_size = Vector2i(
		maxi(1, int(ceil(room.room_bounds.size.x / RETURN_NAV_CELL_SIZE))),
		maxi(1, int(ceil(room.room_bounds.size.y / RETURN_NAV_CELL_SIZE)))
	)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, _return_navigation_size)
	grid.cell_size = Vector2.ONE * RETURN_NAV_CELL_SIZE
	grid.offset = room.room_bounds.position + Vector2.ONE * RETURN_NAV_CELL_SIZE * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in _return_navigation_size.y:
		for x in _return_navigation_size.x:
			var point_id := Vector2i(x, y)
			if _return_navigation_point_blocked(grid.get_point_position(point_id)):
				grid.set_point_solid(point_id, true)
	_return_navigation_grid = grid
	_return_nav_rebuilds += 1


func _return_navigation_point_blocked(world_point: Vector2) -> bool:
	if room == null:
		return false
	for piece in room.get_terrain_pieces():
		if not piece.kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
			continue
		var local_point := piece.to_local(world_point)
		if piece.kind == FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR:
			var pillar_radius := minf(piece.piece_size.x, piece.piece_size.y) * 0.5 + RETURN_NAV_CLEARANCE
			if local_point.length_squared() <= pillar_radius * pillar_radius:
				return true
		elif Rect2(-piece.piece_size * 0.5, piece.piece_size).grow(RETURN_NAV_CLEARANCE).has_point(local_point):
			return true
	return false


func _find_return_route(origin: Vector2, target: Vector2) -> PackedVector2Array:
	if _return_navigation_grid == null:
		_build_return_navigation_grid()
	if _return_navigation_grid == null:
		return PackedVector2Array([target])
	var from_id := _nearest_open_return_navigation_id(_world_to_return_navigation_id(origin))
	var target_id := _nearest_open_return_navigation_id(_world_to_return_navigation_id(target))
	if from_id.x < 0 or target_id.x < 0:
		return PackedVector2Array()
	var cache_key := "%d:%d>%d:%d" % [from_id.x, from_id.y, target_id.x, target_id.y]
	var cached_variant: Variant = _return_route_cache.get(cache_key)
	var route := PackedVector2Array()
	if cached_variant is PackedVector2Array:
		route = PackedVector2Array(cached_variant)
		_return_nav_cache_hits += 1
	else:
		_return_nav_queries += 1
		# A partial path is not a reachable assignment: appending the target to a
		# partial result would draw the last segment straight through solid cover.
		var id_path := _return_navigation_grid.get_id_path(from_id, target_id, false)
		if id_path.is_empty():
			return PackedVector2Array()
		for point_id in id_path:
			route.append(_return_navigation_grid.get_point_position(point_id))
		if _return_route_cache.size() >= RETURN_NAV_CACHE_LIMIT:
			_return_route_cache.clear()
		_return_route_cache[cache_key] = route
	# The first grid center is behind the projectile and causes a visible hook.
	while not route.is_empty() and origin.distance_squared_to(route[0]) <= RETURN_NAV_CELL_SIZE * RETURN_NAV_CELL_SIZE * 1.5:
		route.remove_at(0)
	if route.is_empty() or route[-1].distance_squared_to(target) > 4.0:
		route.append(target)
	else:
		route[-1] = target
	return route


func _world_to_return_navigation_id(world_point: Vector2) -> Vector2i:
	if room == null or _return_navigation_size == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var local_point := world_point - room.room_bounds.position
	return Vector2i(
		clampi(int(floor(local_point.x / RETURN_NAV_CELL_SIZE)), 0, _return_navigation_size.x - 1),
		clampi(int(floor(local_point.y / RETURN_NAV_CELL_SIZE)), 0, _return_navigation_size.y - 1)
	)


func _nearest_open_return_navigation_id(origin_id: Vector2i) -> Vector2i:
	if _return_navigation_grid == null or origin_id.x < 0:
		return Vector2i(-1, -1)
	if not _return_navigation_grid.is_point_solid(origin_id):
		return origin_id
	for radius in range(1, 5):
		for y in range(origin_id.y - radius, origin_id.y + radius + 1):
			for x in range(origin_id.x - radius, origin_id.x + radius + 1):
				if x < 0 or y < 0 or x >= _return_navigation_size.x or y >= _return_navigation_size.y:
					continue
				if abs(x - origin_id.x) != radius and abs(y - origin_id.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if not _return_navigation_grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func _return_route_length(origin: Vector2, route: PackedVector2Array) -> float:
	var total := 0.0
	var previous := origin
	for point in route:
		total += previous.distance_to(point)
		previous = point
	return total


func get_return_navigation_snapshot() -> Dictionary:
	return {
		"grid_size": _return_navigation_size,
		"cell_size": RETURN_NAV_CELL_SIZE,
		"queries": _return_nav_queries,
		"cache_hits": _return_nav_cache_hits,
		"cache_entries": _return_route_cache.size(),
		"rebuilds": _return_nav_rebuilds,
		"target_limit": RETURN_NAV_TARGET_LIMIT,
	}


func preview_return_route(origin: Vector2, target: Vector2) -> PackedVector2Array:
	return _find_return_route(origin, target)


func _select_homing_target(origin: Vector2, maximum_range: float, preferred_index: int = 0) -> Node2D:
	var assignment := _select_reachable_homing_assignment(origin, maximum_range, preferred_index)
	var target_variant: Variant = assignment.get("target")
	return target_variant as Node2D if target_variant is Node2D else null


func _spawn_return_missile(origin: Vector2, damage: float, preferred_index: int = 0, salvo_size: int = 1, ribbon: Dictionary = {}) -> FoldlightRogueProjectile:
	var assignment := _select_reachable_homing_assignment(origin, 1650.0, preferred_index)
	var target_variant: Variant = assignment.get("target")
	var target := target_variant as Node2D if target_variant is Node2D else null
	var route_variant: Variant = assignment.get("route", PackedVector2Array())
	var route := PackedVector2Array(route_variant) if route_variant is PackedVector2Array else PackedVector2Array()
	var base_direction := origin.direction_to(target.global_position) if target != null else Vector2.UP
	var spread_unit := 0.0 if salvo_size <= 1 else float(preferred_index) / float(salvo_size - 1) - 0.5
	var launch_angle := float(ribbon.get("angle", base_direction.rotated(spread_unit * 0.78).angle()))
	var launch_speed := float(ribbon.get("speed", 880.0))
	return _spawn_projectile({
		"origin": origin,
		"velocity": Vector2.from_angle(launch_angle) * launch_speed,
		"hostile": false,
		"reflectable": false,
		"damage": damage,
		"radius": 9.0,
		"lifetime": float(ribbon.get("lifetime", 3.2)),
		"pierce": int(round(float(_build_stats.get("return_pierce_add", 0.0)))),
		"style": &"return_light",
		"homing_target": target,
		"homing_strength": 7.5 if not ribbon.is_empty() else 8.5,
		"homing_range": 1650.0,
		"homing_speed": float(ribbon.get("homing_speed", 880.0)),
		"navigation_waypoints": route,
		"navigation_repath_interval": 0.24,
		"navigation_repath_delay": 0.12 + float(preferred_index % 5) * 0.024,
		"launch_delay": float(ribbon.get("delay", 0.0)),
		"orbit_anchor": ribbon.get("orbit_anchor"),
		"orbit_radius": float(ribbon.get("orbit_radius", 0.0)),
		"orbit_angle": launch_angle,
		"orbit_speed": 4.2,
		"return_chain_remaining": int(ribbon.get("return_chain_remaining", 0)),
	})


func _spawn_projectile(snapshot: Dictionary) -> FoldlightRogueProjectile:
	if room == null:
		return null
	while projectiles.size() >= MAX_PROJECTILES:
		_remove_projectile(projectiles[0])
	var projectile := PROJECTILE_SCENE.instantiate() as FoldlightRogueProjectile
	room.projectile_container.add_child(projectile)
	projectile.configure(snapshot)
	projectiles.append(projectile)
	projectile_spawned.emit(projectile)
	return projectile


func _remove_projectile(projectile: FoldlightRogueProjectile) -> void:
	if projectile == null:
		return
	projectiles.erase(projectile)
	if is_instance_valid(projectile):
		projectile.queue_free()


func _enemy_center() -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for enemy in enemies:
		if is_instance_valid(enemy):
			center += enemy.global_position
			count += 1
	return center / float(count) if count > 0 else (player.global_position if player != null else Vector2.ZERO)


func _draw() -> void:
	for burst in _enemy_hit_bursts:
		var duration := maxf(0.01, float(burst.get("duration", HIT_VFX_DURATION)))
		var remaining := clampf(float(burst.get("remaining", 0.0)), 0.0, duration)
		var progress := 1.0 - remaining / duration
		var center := Vector2(burst.get("position", Vector2.ZERO))
		var direction := Vector2(burst.get("direction", Vector2.RIGHT)).normalized()
		var strength := float(burst.get("strength", 1.0))
		var alpha := pow(1.0 - progress, 1.65)
		var radius := lerpf(8.0, 33.0 + strength * 7.0, ease(progress, -1.35))
		draw_circle(center, radius * 0.72, Color(1.0, 0.66, 0.22, alpha * 0.14))
		draw_arc(center, radius, -PI * 0.88, PI * 0.88, 28, Color(1.0, 0.88, 0.54, alpha * 0.96), 4.2 - progress * 1.8, true)
		draw_arc(center, radius * 0.72, PI * 0.12, PI * 1.08, 18, Color(0.38, 0.96, 0.90, alpha * 0.62), 2.2, true)
		for shard_index in 5:
			var shard_angle := direction.angle() + (float(shard_index) - 2.0) * 0.42
			var shard_direction := Vector2.from_angle(shard_angle)
			var shard_start := center + shard_direction * (4.0 + progress * 8.0)
			var shard_end := center + shard_direction * (19.0 + progress * (24.0 + strength * 6.0))
			draw_line(shard_start, shard_end, Color(1.0, 0.70 + float(shard_index) * 0.045, 0.28, alpha * (0.96 - float(abs(shard_index - 2)) * 0.08)), 3.8 - progress * 1.5, true)
			draw_circle(shard_end, maxf(0.8, 2.4 - progress * 1.3), Color(1.0, 0.94, 0.72, alpha * 0.82))
	for flash in _active_flashes:
		var duration := maxf(0.1, float(flash.get("duration", 0.1)))
		var remaining := clampf(float(flash.get("remaining", 0.0)), 0.0, duration)
		var progress := 1.0 - remaining / duration
		var center := Vector2(flash.get("position", Vector2.ZERO))
		var color := Color(flash.get("color", Color.WHITE))
		var radius := lerpf(28.0, float(flash.get("radius", 320.0)), ease(progress, -1.8))
		var alpha := pow(1.0 - progress, 1.4)
		draw_circle(center, radius, Color(color.r, color.g, color.b, alpha * 0.055))
		draw_arc(center, radius, 0.0, TAU, 72, Color(color.r, color.g, color.b, alpha * 0.92), 5.0 - progress * 2.0, true)
		draw_arc(center, radius * 0.72, -PI * 0.2, PI * 1.18, 56, Color(1.0, 0.88, 0.56, alpha * 0.58), 2.0, true)


func _unbind_signals() -> void:
	if room != null:
		if room.encounter_spawn_telegraph.is_connected(_on_spawn_telegraph):
			room.encounter_spawn_telegraph.disconnect(_on_spawn_telegraph)
		if room.encounter_enemy_requested.is_connected(_on_enemy_requested):
			room.encounter_enemy_requested.disconnect(_on_enemy_requested)
	if player != null:
		if player.weapon_mount.shot_requested.is_connected(_on_player_shot_requested):
			player.weapon_mount.shot_requested.disconnect(_on_player_shot_requested)
		if player.fold_released.is_connected(_on_player_fold_released):
			player.fold_released.disconnect(_on_player_fold_released)
		if player.active_item_slot.item_used.is_connected(_on_active_item_used):
			player.active_item_slot.item_used.disconnect(_on_active_item_used)
		if player.dash_started.is_connected(_on_player_dash_started):
			player.dash_started.disconnect(_on_player_dash_started)
		if player.dash_ended.is_connected(_on_player_dash_ended):
			player.dash_ended.disconnect(_on_player_dash_ended)
	if room != null and room.encounter_cleared.is_connected(_on_room_cleared):
		room.encounter_cleared.disconnect(_on_room_cleared)
