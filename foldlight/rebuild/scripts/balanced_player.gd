class_name FoldlightBalancedPlayer
extends FoldlightPlayer

var rejected_dash_requests: int = 0
var _ignore_fold_press_until_release: bool = false

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_PAUSABLE

func configure_lab(settings: Dictionary) -> void:
	configure_roguelite_combat(true)
	reset_player()
	max_health = int(settings["player_health"])
	health = max_health
	fold_component.roguelite_capacity = int(settings["capture_capacity"])
	capture_capacity = fold_component.get_capacity()
	fold_component.roguelite_cooldown = float(settings["fold_cooldown"])
	dash_component.base_cooldown = float(settings["dash_cooldown"])
	focus = 1.0
	focus_drain_multiplier = 0.0
	focus_regen_multiplier = 0.0
	active_item_slot.enabled = false
	weapon_mount.unequip_all()
	var weapon := FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern").duplicate(true) as FoldlightRogueWeaponDefinition
	weapon.base_damage = float(settings["weapon_damage"])
	weapon.fire_interval = float(settings["weapon_interval"])
	weapon.targeting_range = float(settings["weapon_range"])
	weapon_mount.equip(weapon)
	set_debug_invincible(false)
	rejected_dash_requests = 0
	_ignore_fold_press_until_release = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released(&"fold"):
		_ignore_fold_press_until_release = false
	elif _ignore_fold_press_until_release and event.is_action_pressed(&"fold"):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	if not Input.is_action_pressed(&"fold"):
		_ignore_fold_press_until_release = false
	super._physics_process(delta)

func request_dash(requested_direction: Vector2 = Vector2.ZERO) -> bool:
	if not play_enabled or not roguelite_combat or not dash_component.is_ready():
		rejected_dash_requests += 1
		return false
	if folding:
		if captured > 0:
			release_fold_action()
		else:
			cancel_fold()
	var direction := requested_direction.normalized() if not requested_direction.is_zero_approx() else _last_direction
	return dash_component.request(direction)

func tick_automatic_weapons(delta: float, has_valid_target: bool) -> void:
	if not folding:
		super.tick_automatic_weapons(delta, has_valid_target)

func reconcile_after_pause() -> void:
	_fold_buffer_timer = 0.0
	_dash_buffer_timer = 0.0
	_ignore_fold_press_until_release = true
	if folding and not Input.is_action_pressed(&"fold"):
		release_fold_action()
