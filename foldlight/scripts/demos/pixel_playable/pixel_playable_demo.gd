class_name FoldlightPixelPlayableDemo
extends Node2D

signal room_started(room_index: int)
signal room_cleared(room_index: int)
signal run_finished(victory: bool)

const CANVAS_SIZE := Vector2(1254.0, 705.0)
const PLAY_BOUNDS := Rect2(44.0, 150.0, 1166.0, 490.0)
const ROOM_ONE_BACKGROUND := "res://assets/demos/pixel_playable/room_one_clean_v1.png"
const BOSS_BACKGROUND := "res://assets/demos/pixel_playable/boss_water_v1.png"
const ACTOR_ATLAS := "res://assets/demos/pixel/paper_reef_actor_atlas.png"
const TERRAIN_ATLAS := "res://assets/demos/pixel/paper_reef_terrain_atlas.png"

const PLAYER_SPEED := 350.0
const DASH_SPEED := 990.0
const DASH_DURATION := 0.18
const AUTO_FIRE_INTERVAL := 0.27
const MAX_PROJECTILES := 190

const HEAL_CENTER := Vector2(220.0, 394.0)
const HEAL_RADIUS := 68.0
const HAZARD_RECT := Rect2(1010.0, 224.0, 200.0, 296.0)

@onready var stage: Node2D = $Stage
@onready var backdrop: FoldlightPixelPlayableBackdrop = $Stage/Backdrop
@onready var terrain: FoldlightPixelPlayableTerrain = $Stage/Terrain
@onready var arena_fx: FoldlightPixelPlayableArenaFx = $Stage/ArenaFx
@onready var actors_layer: Node2D = $Stage/Actors
@onready var projectiles_layer: Node2D = $Stage/Projectiles
@onready var vfx: FoldlightPixelPlayableVfx = $Stage/Vfx
@onready var hud: FoldlightPixelPlayableHud = $Hud/HudRoot

var player: FoldlightPixelPlayableActor
var boss: FoldlightPixelPlayableActor
var current_target: FoldlightPixelPlayableActor
var enemies: Array[FoldlightPixelPlayableActor] = []
var projectiles: Array[FoldlightPixelPlayableProjectile] = []
var enemy_ai: Dictionary = {}

var room_index: int = 1
var run_state: StringName = &"playing"
var elapsed_time: float = 0.0
var tutorial_time: float = 4.5
var gate_open: bool = false
var gate_position := Vector2(1160.0, 390.0)

var capture_capacity: int = 8
var captured_count: int = 0
var folding: bool = false
var fold_charge: float = 0.0
var fold_cooldown: float = 0.0
var fold_cooldown_duration: float = 1.5
var dash_cooldown: float = 0.0
var dash_cooldown_duration: float = 2.0
var dash_time: float = 0.0
var dash_direction := Vector2.RIGHT
var active_cooldown: float = 0.0
var active_cooldown_duration: float = 8.0
var auto_fire_timer: float = 0.0
var player_invulnerability: float = 0.0
var last_move_direction := Vector2.RIGHT
var heal_timer: float = 0.0
var hazard_tick: float = 0.0

var boss_phase: int = 1
var arena_center := Vector2(650.0, 390.0)
var arena_radius: float = 9999.0
var boss_pattern_rotation: float = 0.0

var shake_strength: float = 0.0
var _room_one_texture: Texture2D
var _boss_texture: Texture2D
var _actor_texture: Texture2D
var _terrain_texture: Texture2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_room_one_texture = load(ROOM_ONE_BACKGROUND) as Texture2D
	_boss_texture = load(BOSS_BACKGROUND) as Texture2D
	_actor_texture = load(ACTOR_ATLAS) as Texture2D
	_terrain_texture = load(TERRAIN_ATLAS) as Texture2D
	arena_fx.bind_game(self)
	hud.bind_game(self)
	start_room_one()
	if OS.has_feature(&"pixel_demo"):
		print("FOLDLIGHT_PIXEL_PLAYABLE_READY scene=%s canvas=%dx%d rooms=2 resample=false" % [scene_file_path, int(CANVAS_SIZE.x), int(CANVAS_SIZE.y)])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game") or event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and run_state in [&"dead", &"victory"]:
			_restart_current_room()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_1:
			start_room_one()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_2:
			start_boss_room()
			get_viewport().set_input_as_handled()
			return
	if run_state in [&"dead", &"victory"] and event.is_action_pressed(&"ui_accept"):
		_restart_current_room()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	elapsed_time += delta
	_update_stage_shake(delta)
	_tick_actor_status(delta)
	if run_state in [&"dead", &"victory"]:
		return

	tutorial_time = maxf(0.0, tutorial_time - delta)
	fold_cooldown = maxf(0.0, fold_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	active_cooldown = maxf(0.0, active_cooldown - delta)
	player_invulnerability = maxf(0.0, player_invulnerability - delta)
	auto_fire_timer = maxf(0.0, auto_fire_timer - delta)
	heal_timer = maxf(0.0, heal_timer - delta)
	hazard_tick = maxf(0.0, hazard_tick - delta)

	_handle_player_actions(delta)
	_update_room_terrain(delta)
	current_target = _nearest_living_enemy(player.global_position if is_instance_valid(player) else Vector2.ZERO)
	_update_auto_fire()
	_update_enemy_ai(delta)
	_resolve_projectile_interactions()
	_update_room_completion()


func start_room_one() -> void:
	_clear_combat()
	room_index = 1
	run_state = &"playing"
	tutorial_time = 4.5
	gate_open = false
	boss = null
	boss_phase = 1
	arena_radius = 9999.0
	backdrop.configure(_room_one_texture, CANVAS_SIZE)
	terrain.configure(_terrain_texture, room_index)
	_spawn_player(Vector2(304, 402))
	_spawn_enemy(FoldlightPixelPlayableActor.ActorKind.TURRET, Vector2(951, 216), 26, 0.0)
	_spawn_enemy(FoldlightPixelPlayableActor.ActorKind.CRAB, Vector2(812, 422), 24, 145.0)
	_spawn_enemy(FoldlightPixelPlayableActor.ActorKind.WARDEN, Vector2(1014, 548), 30, 112.0)
	_spawn_enemy(FoldlightPixelPlayableActor.ActorKind.SKIFF, Vector2(714, 246), 22, 188.0)
	vfx.show_banner("房间一 · 纸礁伏击", Color("63e4d1"), 2.0)
	room_started.emit(room_index)


func start_boss_room() -> void:
	_clear_combat()
	room_index = 2
	run_state = &"playing"
	tutorial_time = 2.4
	gate_open = false
	boss_phase = 1
	arena_radius = 9999.0
	boss_pattern_rotation = 0.0
	backdrop.configure(_boss_texture, CANVAS_SIZE)
	terrain.configure(_terrain_texture, room_index)
	_spawn_player(Vector2(242, 398))
	boss = _spawn_enemy(FoldlightPixelPlayableActor.ActorKind.BOSS, Vector2(892, 370), 280, 82.0)
	vfx.show_banner("房间二 · 礁冠炮城", Color("f17858"), 2.2)
	room_started.emit(room_index)


func _spawn_player(position: Vector2) -> void:
	player = FoldlightPixelPlayableActor.new()
	player.name = "Player"
	actors_layer.add_child(player)
	player.configure(FoldlightPixelPlayableActor.ActorKind.PLAYER, _actor_texture, 0, Vector2(142, 142), 20.0, 6, PLAYER_SPEED, PLAY_BOUNDS)
	player.global_position = position
	player.died.connect(_on_actor_died)
	player.damaged.connect(_on_actor_damaged)


func _spawn_enemy(kind: FoldlightPixelPlayableActor.ActorKind, position: Vector2, health: int, speed: float) -> FoldlightPixelPlayableActor:
	var actor := FoldlightPixelPlayableActor.new()
	actor.name = "Enemy_%s_%d" % [FoldlightPixelPlayableActor.ActorKind.keys()[kind], enemies.size()]
	actors_layer.add_child(actor)
	var cell := int(kind)
	var visual_size := Vector2(162, 162)
	var radius := 30.0
	if kind == FoldlightPixelPlayableActor.ActorKind.TURRET:
		visual_size = Vector2(174, 174)
		radius = 32.0
	elif kind == FoldlightPixelPlayableActor.ActorKind.WARDEN:
		visual_size = Vector2(176, 176)
		radius = 30.0
	elif kind == FoldlightPixelPlayableActor.ActorKind.SKIFF:
		visual_size = Vector2(172, 172)
		radius = 29.0
	elif kind == FoldlightPixelPlayableActor.ActorKind.BOSS:
		visual_size = Vector2(420, 420)
		radius = 108.0
	actor.configure(kind, _actor_texture, cell, visual_size, radius, health, speed, PLAY_BOUNDS)
	actor.global_position = position
	actor.died.connect(_on_actor_died)
	actor.damaged.connect(_on_actor_damaged)
	enemies.append(actor)
	var seed_value := float(enemies.size()) * 0.71
	enemy_ai[actor.get_instance_id()] = {
		"fire": 0.55 + seed_value * 0.28,
		"pattern": 0,
		"orbit": seed_value,
		"anchor": position,
	}
	return actor


func _handle_player_actions(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var ui_direction := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if ui_direction.length_squared() > direction.length_squared():
		direction = ui_direction
	if direction.length_squared() > 0.01:
		last_move_direction = direction.normalized()

	if Input.is_action_just_pressed(&"dash") and dash_cooldown <= 0.0:
		_start_dash()
	if dash_time > 0.0:
		dash_time = maxf(0.0, dash_time - delta)
		player.move_controlled(dash_direction, delta, DASH_SPEED)
		if int(elapsed_time * 45.0) % 2 == 0:
			vfx.add_capture(player.global_position - dash_direction * 18.0)
	else:
		var terrain_multiplier := 0.62 if room_index == 1 and HAZARD_RECT.has_point(player.global_position) else 1.0
		player.move_controlled(direction, delta, PLAYER_SPEED * terrain_multiplier)

	if Input.is_action_just_pressed(&"fold") and fold_cooldown <= 0.0 and dash_time <= 0.0:
		folding = true
		fold_charge = 0.0
	if folding:
		fold_charge = minf(1.0, fold_charge + delta / 0.9)
		if Input.is_action_just_released(&"fold") or not Input.is_action_pressed(&"fold"):
			_release_fold()
	if Input.is_action_just_pressed(&"active_item") and active_cooldown <= 0.0:
		_use_active_skill()

	if room_index == 2 and arena_radius < 900.0:
		var offset := player.global_position - arena_center
		if offset.length() > arena_radius - 18.0:
			player.global_position = (arena_center + offset.normalized() * (arena_radius - 18.0)).round()


func _cancel_fold() -> void:
	folding = false
	fold_charge = 0.0
	captured_count = 0


func _start_dash() -> bool:
	if dash_cooldown > 0.0 or (folding and captured_count > 0):
		return false
	if folding:
		_cancel_fold()
	dash_direction = last_move_direction
	dash_time = DASH_DURATION
	dash_cooldown = dash_cooldown_duration
	player_invulnerability = DASH_DURATION + 0.08
	shake_strength = maxf(shake_strength, 4.0)
	return true


func _release_fold() -> void:
	if not folding:
		return
	folding = false
	fold_cooldown = fold_cooldown_duration
	var target := _nearest_living_enemy(player.global_position)
	if is_instance_valid(target):
		for index in captured_count:
			var angle_offset := (float(index) - float(captured_count - 1) * 0.5) * 0.075
			var direction := player.global_position.direction_to(target.global_position).rotated(angle_offset)
			var projectile := _spawn_projectile(FoldlightPixelPlayableProjectile.Faction.PLAYER, player.global_position + direction * 28.0, direction * 720.0, 6, 8.0, false, 4.0)
			projectile.homing_target = target
			projectile.homing_strength = 5.5
		vfx.add_capture(player.global_position)
		shake_strength = maxf(shake_strength, minf(9.0, 2.0 + float(captured_count)))
	captured_count = 0
	fold_charge = 0.0


func get_fold_radius() -> float:
	return lerpf(92.0, 142.0, fold_charge)


func _use_active_skill() -> void:
	active_cooldown = active_cooldown_duration
	var cleared := 0
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile) and projectile.faction == FoldlightPixelPlayableProjectile.Faction.ENEMY and projectile.global_position.distance_to(player.global_position) <= 220.0:
			vfx.add_capture(projectile.global_position)
			projectile.consume()
			cleared += 1
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive and enemy.global_position.distance_to(player.global_position) <= 250.0:
			enemy.take_damage(5, player.global_position.direction_to(enemy.global_position))
	var target := _nearest_living_enemy(player.global_position)
	if is_instance_valid(target):
		for index in 8:
			var direction := Vector2.from_angle(TAU * float(index) / 8.0)
			var projectile := _spawn_projectile(FoldlightPixelPlayableProjectile.Faction.PLAYER, player.global_position + direction * 30.0, direction * 610.0, 3, 7.0, false, 4.0)
			projectile.homing_target = target
			projectile.homing_strength = 3.6
	vfx.add_explosion(player.global_position, Color("55ead5"), 1.5)
	vfx.show_banner("潮爆 · 清弹 %d" % cleared, Color("61ead7"), 1.2)
	shake_strength = maxf(shake_strength, 10.0)


func _update_room_terrain(_delta: float) -> void:
	if room_index != 1 or not is_instance_valid(player):
		return
	if player.global_position.distance_to(HEAL_CENTER) <= HEAL_RADIUS:
		if heal_timer <= 0.0 and player.heal(1):
			heal_timer = 4.0
			vfx.add_capture(player.global_position)
	if HAZARD_RECT.has_point(player.global_position) and hazard_tick <= 0.0:
		hazard_tick = 1.15
		_damage_player(Vector2.LEFT)


func _update_auto_fire() -> void:
	if auto_fire_timer > 0.0 or not is_instance_valid(current_target) or not is_instance_valid(player):
		return
	auto_fire_timer = AUTO_FIRE_INTERVAL
	var direction := player.global_position.direction_to(current_target.global_position)
	var projectile := _spawn_projectile(FoldlightPixelPlayableProjectile.Faction.PLAYER, player.global_position + direction * 25.0, direction * 650.0, 2, 7.0, false, 4.0)
	projectile.homing_target = current_target
	projectile.homing_strength = 2.8


func _update_enemy_ai(delta: float) -> void:
	if not is_instance_valid(player):
		return
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var id: int = enemy.get_instance_id()
		var data := enemy_ai.get(id, {}) as Dictionary
		data.fire = float(data.get("fire", 0.0)) - delta
		data.orbit = float(data.get("orbit", 0.0)) + delta
		match enemy.actor_kind:
			FoldlightPixelPlayableActor.ActorKind.TURRET:
				_update_turret(enemy, data)
			FoldlightPixelPlayableActor.ActorKind.CRAB:
				_update_crab(enemy, data, delta)
			FoldlightPixelPlayableActor.ActorKind.WARDEN:
				_update_warden(enemy, data, delta)
			FoldlightPixelPlayableActor.ActorKind.SKIFF:
				_update_skiff(enemy, data, delta)
			FoldlightPixelPlayableActor.ActorKind.BOSS:
				_update_boss(enemy, data, delta)
		enemy_ai[id] = data


func _update_turret(enemy: FoldlightPixelPlayableActor, data: Dictionary) -> void:
	if float(data.fire) > 0.0:
		return
	var pattern := int(data.get("pattern", 0))
	_spawn_enemy_fan(enemy, 3, 0.16, 350.0, true)
	if pattern % 3 == 2:
		_spawn_enemy_aimed(enemy, 470.0, false, 0.0)
	data.pattern = pattern + 1
	data.fire = 1.55


func _update_crab(enemy: FoldlightPixelPlayableActor, data: Dictionary, delta: float) -> void:
	var to_player := enemy.global_position.direction_to(player.global_position)
	var distance := enemy.global_position.distance_to(player.global_position)
	var strafe := to_player.orthogonal() * sin(float(data.orbit) * 1.8)
	var direction := to_player * clampf((distance - 230.0) / 160.0, -0.55, 0.8) + strafe * 0.75
	enemy.move_ai(direction, delta)
	if float(data.fire) <= 0.0:
		_spawn_enemy_fan(enemy, 3, 0.18, 330.0, true)
		data.fire = 1.25


func _update_warden(enemy: FoldlightPixelPlayableActor, data: Dictionary, delta: float) -> void:
	var to_player := enemy.global_position.direction_to(player.global_position)
	var distance := enemy.global_position.distance_to(player.global_position)
	var direction := to_player if distance > 300.0 else -to_player * 0.42
	enemy.move_ai(direction + to_player.orthogonal() * 0.35, delta)
	if float(data.fire) <= 0.0:
		_spawn_enemy_fan(enemy, 5, 0.14, 300.0, true)
		_spawn_enemy_aimed(enemy, 415.0, false, 0.07)
		data.fire = 2.05


func _update_skiff(enemy: FoldlightPixelPlayableActor, data: Dictionary, delta: float) -> void:
	var anchor := data.get("anchor", enemy.global_position) as Vector2
	var orbit_target := anchor + Vector2(cos(float(data.orbit) * 0.9), sin(float(data.orbit) * 1.25)) * Vector2(110, 72)
	enemy.move_ai(enemy.global_position.direction_to(orbit_target), delta)
	if float(data.fire) <= 0.0:
		_spawn_enemy_aimed(enemy, 505.0, false, 0.0)
		_spawn_enemy_fan(enemy, 2, 0.24, 340.0, true)
		data.fire = 1.75


func _update_boss(enemy: FoldlightPixelPlayableActor, data: Dictionary, delta: float) -> void:
	var ratio := enemy.get_health_ratio()
	var requested_phase := 1 if ratio > 0.67 else (2 if ratio > 0.34 else 3)
	if requested_phase != boss_phase:
		boss_phase = requested_phase
		vfx.show_banner("礁冠阶段 %d" % boss_phase, Color("ff7658"), 1.5)
		vfx.add_explosion(enemy.global_position, Color("ff5d45"), 1.8)
		shake_strength = maxf(shake_strength, 16.0)
		_clear_enemy_projectiles(0.48)
	arena_radius = 9999.0 if boss_phase == 1 else (286.0 if boss_phase == 2 else 232.0)
	boss_pattern_rotation += delta * (0.34 + float(boss_phase) * 0.11)
	var anchor := Vector2(892, 370)
	var target_position := anchor + Vector2(cos(float(data.orbit) * 0.42) * 76.0, sin(float(data.orbit) * 0.58) * 42.0)
	enemy.move_ai(enemy.global_position.direction_to(target_position), delta, 0.72)
	if float(data.fire) > 0.0:
		return
	var pattern := int(data.get("pattern", 0))
	if boss_phase == 1:
		_spawn_enemy_fan(enemy, 7, 0.12, 340.0, true)
		if pattern % 3 == 2:
			_spawn_enemy_ring(enemy, 12, 290.0, true, boss_pattern_rotation)
		data.fire = 0.96
	elif boss_phase == 2:
		_spawn_enemy_ring(enemy, 14, 315.0, true, boss_pattern_rotation)
		if pattern % 2 == 1:
			_spawn_enemy_ring(enemy, 5, 420.0, false, -boss_pattern_rotation * 0.7)
		data.fire = 0.82
	else:
		_spawn_enemy_fan(enemy, 9, 0.10, 390.0, true)
		_spawn_enemy_ring(enemy, 6, 455.0, false, boss_pattern_rotation)
		if pattern % 3 == 2:
			_spawn_enemy_ring(enemy, 18, 330.0, true, -boss_pattern_rotation * 0.8)
		data.fire = 0.66
	data.pattern = pattern + 1


func _spawn_enemy_aimed(source: FoldlightPixelPlayableActor, speed: float, reflectable: bool, angle_offset: float) -> void:
	if not is_instance_valid(player):
		return
	var direction := source.global_position.direction_to(player.global_position).rotated(angle_offset)
	_spawn_enemy_projectile(source, direction, speed, reflectable)


func _spawn_enemy_fan(source: FoldlightPixelPlayableActor, count: int, spacing: float, speed: float, reflectable: bool) -> void:
	if not is_instance_valid(player):
		return
	var base := source.global_position.direction_to(player.global_position)
	for index in count:
		var offset := (float(index) - float(count - 1) * 0.5) * spacing
		_spawn_enemy_projectile(source, base.rotated(offset), speed, reflectable)


func _spawn_enemy_ring(source: FoldlightPixelPlayableActor, count: int, speed: float, reflectable: bool, rotation: float) -> void:
	for index in count:
		var direction := Vector2.from_angle(rotation + TAU * float(index) / float(count))
		_spawn_enemy_projectile(source, direction, speed, reflectable)


func _spawn_enemy_projectile(source: FoldlightPixelPlayableActor, direction: Vector2, speed: float, reflectable: bool) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		return
	var spawn_distance := source.hit_radius + (24.0 if source.is_boss else 15.0)
	_spawn_projectile(FoldlightPixelPlayableProjectile.Faction.ENEMY, source.global_position + direction * spawn_distance, direction * speed, 1, 8.0 if reflectable else 10.0, reflectable, 7.0)


func _spawn_projectile(
		faction: FoldlightPixelPlayableProjectile.Faction,
		position: Vector2,
		velocity: Vector2,
		damage: int,
		radius: float,
		reflectable: bool,
		life: float
	) -> FoldlightPixelPlayableProjectile:
	var projectile := FoldlightPixelPlayableProjectile.new()
	projectiles_layer.add_child(projectile)
	projectile.configure(faction, position, velocity, damage, radius, reflectable, life)
	projectile.expired.connect(_on_projectile_expired)
	projectiles.append(projectile)
	return projectile


func _resolve_projectile_interactions() -> void:
	if not is_instance_valid(player):
		return
	for projectile in projectiles.duplicate():
		if not is_instance_valid(projectile) or projectile.consumed:
			continue
		if not Rect2(-90, -90, CANVAS_SIZE.x + 180, CANVAS_SIZE.y + 180).has_point(projectile.global_position):
			projectile.consume()
			continue
		if projectile.faction == FoldlightPixelPlayableProjectile.Faction.ENEMY:
			if folding and projectile.reflectable and captured_count < capture_capacity and projectile.global_position.distance_to(player.global_position) <= get_fold_radius():
				captured_count += 1
				vfx.add_capture(projectile.global_position)
				projectile.consume()
				continue
			if projectile.global_position.distance_to(player.global_position) <= projectile.radius + player.hit_radius:
				if player_invulnerability <= 0.0 and dash_time <= 0.0:
					_damage_player(projectile.velocity.normalized())
				projectile.consume()
		else:
			for enemy in enemies.duplicate():
				if not is_instance_valid(enemy) or not enemy.alive:
					continue
				if projectile.global_position.distance_to(enemy.global_position) <= projectile.radius + enemy.hit_radius:
					enemy.take_damage(projectile.damage, projectile.velocity.normalized())
					vfx.add_hit(projectile.global_position, Color("f6d77b"), 0.8 if enemy.is_boss else 1.0)
					shake_strength = maxf(shake_strength, 3.5 if enemy.is_boss else 5.0)
					projectile.consume()
					break


func _damage_player(impact_direction: Vector2) -> void:
	if not is_instance_valid(player) or player_invulnerability > 0.0 or dash_time > 0.0 or run_state != &"playing":
		return
	player_invulnerability = 0.82
	player.invulnerability = 0.82
	player.take_damage(1, impact_direction)
	vfx.add_explosion(player.global_position, Color("ff6b52"), 0.7)
	shake_strength = maxf(shake_strength, 13.0)


func _update_room_completion() -> void:
	if run_state != &"playing":
		if run_state == &"room_clear" and gate_open and is_instance_valid(player) and player.global_position.distance_to(gate_position) <= 54.0:
			start_boss_room()
		return
	var living := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive:
			living += 1
	if room_index == 1 and living == 0:
		run_state = &"room_clear"
		gate_open = true
		_clear_enemy_projectiles()
		vfx.show_banner("房间肃清 · 潮门开启", Color("5cebd5"), 2.2)
		room_cleared.emit(room_index)


func _nearest_living_enemy(origin: Vector2) -> FoldlightPixelPlayableActor:
	var nearest: FoldlightPixelPlayableActor
	var nearest_distance := INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest


func _on_actor_damaged(actor: FoldlightPixelPlayableActor, _amount: int, _impact_direction: Vector2) -> void:
	if actor.is_boss:
		shake_strength = maxf(shake_strength, 3.0)


func _on_actor_died(actor: FoldlightPixelPlayableActor) -> void:
	if actor == player:
		run_state = &"dead"
		folding = false
		_clear_enemy_projectiles()
		vfx.show_banner("折光熄灭", Color("ff6650"), 2.4)
		run_finished.emit(false)
		return
	vfx.add_explosion(actor.global_position, Color("ff8157") if actor.is_boss else Color("f3c968"), 2.4 if actor.is_boss else 1.2)
	shake_strength = maxf(shake_strength, 24.0 if actor.is_boss else 10.0)
	if actor.is_boss:
		run_state = &"victory"
		arena_radius = 9999.0
		_clear_enemy_projectiles()
		vfx.show_banner("礁冠崩解 · Demo 完成", Color("f5ca62"), 3.5)
		run_finished.emit(true)
	call_deferred("_remove_dead_actor", actor)


func _remove_dead_actor(actor: FoldlightPixelPlayableActor) -> void:
	enemies.erase(actor)
	enemy_ai.erase(actor.get_instance_id())
	if is_instance_valid(actor):
		actor.queue_free()


func _on_projectile_expired(projectile: FoldlightPixelPlayableProjectile) -> void:
	projectiles.erase(projectile)


func _clear_enemy_projectiles(keep_ratio: float = 0.0) -> void:
	var index := 0
	for projectile in projectiles.duplicate():
		if not is_instance_valid(projectile) or projectile.faction != FoldlightPixelPlayableProjectile.Faction.ENEMY:
			continue
		if keep_ratio > 0.0 and float(index % 10) / 10.0 < keep_ratio:
			index += 1
			continue
		projectile.consume()
		index += 1


func _tick_actor_status(delta: float) -> void:
	if is_instance_valid(player):
		player.tick_status(delta)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.tick_status(delta)


func _update_stage_shake(delta: float) -> void:
	shake_strength = move_toward(shake_strength, 0.0, 34.0 * delta)
	if shake_strength <= 0.05:
		stage.position = Vector2.ZERO
		return
	var x := sin(elapsed_time * 93.0) * shake_strength
	var y := cos(elapsed_time * 71.0) * shake_strength * 0.72
	stage.position = Vector2(x, y).round()


func _clear_combat() -> void:
	for child in actors_layer.get_children():
		child.queue_free()
	for child in projectiles_layer.get_children():
		child.queue_free()
	enemies.clear()
	projectiles.clear()
	enemy_ai.clear()
	player = null
	boss = null
	current_target = null
	captured_count = 0
	folding = false
	fold_charge = 0.0
	fold_cooldown = 0.0
	dash_cooldown = 0.0
	dash_time = 0.0
	active_cooldown = 0.0
	auto_fire_timer = 0.15
	player_invulnerability = 0.0
	heal_timer = 0.0
	hazard_tick = 0.0
	shake_strength = 0.0
	stage.position = Vector2.ZERO


func _restart_current_room() -> void:
	if room_index == 2:
		start_boss_room()
	else:
		start_room_one()


func get_playable_contract() -> Dictionary:
	return {
		"playable": true,
		"finished_room_count": 2,
		"random_map": false,
		"base_resolution": Vector2i(1254, 705),
		"default_window_resolution": Vector2i(1254, 705),
		"background_resampling": false,
		"texture_filter": &"nearest",
		"changes_display_mode": false,
		"layer_stack": [&"backdrop", &"terrain_modules", &"arena_fx", &"y_sorted_actors", &"projectiles", &"vfx", &"hud_canvas"],
		"terrain_vocabulary": terrain.get_module_vocabulary(),
		"terrain_recomposable": true,
		"terrain_modules_native_scale": true,
		"mechanics": {
			"auto_homing_weapon": true,
			"capture_capacity": capture_capacity,
			"fold_cooldown": fold_cooldown_duration,
			"dash_cooldown": dash_cooldown_duration,
			"active_skill": true,
			"reflectable_and_forbidden_projectiles": true,
		},
		"room_one": {
			"fixed_encounter": true,
			"enemy_kinds": [&"turret", &"crab", &"warden", &"skiff"],
			"positive_terrain": true,
			"negative_terrain": true,
			"clear_gate": true,
		},
		"boss_room": {
			"uses_image_four_background": true,
			"uses_image_three_boss": true,
			"phase_count": 3,
			"movement_cage": true,
			"boss_health": 280,
		},
	}


func get_runtime_snapshot() -> Dictionary:
	var living := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive:
			living += 1
	return {
		"room_index": room_index,
		"run_state": run_state,
		"living_enemies": living,
		"projectile_count": projectiles.size(),
		"boss_phase": boss_phase,
		"arena_radius": arena_radius,
		"player_health": player.health if is_instance_valid(player) else 0,
	}


func debug_defeat_all_enemies() -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive:
			enemy.take_damage(enemy.health)


func debug_set_boss_health_ratio(ratio: float) -> void:
	if not is_instance_valid(boss):
		return
	boss.health = clampi(int(round(float(boss.max_health) * clampf(ratio, 0.0, 1.0))), 1, boss.max_health)
