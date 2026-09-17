class_name FoldlightBalancedCombat
extends FoldlightRogueCombatRuntime

const LAB_BOSS_SCENE := preload("res://rebuild/scenes/balanced_boss.tscn")

func bind(new_room: FoldlightRoomRuntime, new_player: FoldlightPlayer, run_seed: int = 330031) -> void:
	if player != null and player.dash_started.is_connected(_remove_dash_release_hit_stop):
		player.dash_started.disconnect(_remove_dash_release_hit_stop)
	super.bind(new_room, new_player, run_seed)
	if player != null:
		player.dash_started.connect(_remove_dash_release_hit_stop)

func add_lab_boss(settings: Dictionary) -> FoldlightBalancedBoss:
	if room == null:
		return null
	var boss := LAB_BOSS_SCENE.instantiate() as FoldlightBalancedBoss
	room.enemy_container.add_child(boss)
	boss.configure_lab(settings, room.room_bounds)
	boss.global_position = Vector2(960.0, 300.0)
	boss.set_meta("counts_for_room", false)
	boss.defeated.connect(_on_enemy_defeated)
	boss.volley_requested.connect(spawn_hostile_volley)
	boss.clear_hostiles_requested.connect(clear_hostiles)
	enemies.append(boss)
	enemy_spawned.emit(boss, {"boss_id": &"reef_crown_battery", "lab": true})
	return boss

func clear_hostiles() -> void:
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile) and projectile.hostile:
			_remove_projectile(projectile)

func _remove_dash_release_hit_stop(_direction: Vector2, _duration: float) -> void:
	_release_hit_stop_remaining = 0.0
	if player != null:
		player._hit_stop_timer = 0.0
