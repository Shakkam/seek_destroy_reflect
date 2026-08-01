class_name ShipNode
extends CharacterBody2D

## Thin Godot node: reads input, renders, and delegates all movement
## logic to simulation/ship_state.gd. Never contains simulation rules
## itself (see project-context.md, Regle absolue n1).

signal weapon_fired(damage: int, is_heavy: bool)
signal gauge_filled(amount: float)

@export var player_index: int = 1 # 1 or 2 — selects which local input scheme to read
@export var side: int = 0 # 0 = left half, 1 = right half
@export var half_extents: Vector2 = Vector2(14, 28) # matches the vertical "paddle" collision shape

var state: ShipState
var arena_bounds: Rect2
var frontier_x: float

var weapon_state: WeaponSystemState
var _weapon_select_prev := false
var _flash_timer := 0.0
const FLASH_DURATION := 0.08

var _vulnerability_timer := 0.0
const VULNERABILITY_DURATION := 0.7 # Story 1.8 — heavy weapons expose the shooter briefly (doubled 2026-08-01)
const VULNERABILITY_SPEED_MULTIPLIER := 0.35

# Lift/spin charge (redesigned 2026-08-01): holding the lift key freezes
# movement entirely and charges the lift over time, in tiers:
# <0.3s = 0%, 0.3-0.6s = 33%, 0.6-1.5s = 66%, >=1.5s = 100%.
var _lift_charge_timer := 0.0
const LIFT_CHARGE_CAP := 1.5

var _spawn_position: Vector2

# Story 1.12 — set by MatchArenaNode when this ship is AI-controlled.
var ai_controlled := false
var ball_ref: BallNode
var opponent_ref: ShipNode
var _ai_vertical_dir := 0.0 # persists between frames — hysteresis avoids jittery on/off "freeze"
const AI_LOOKAHEAD := 0.15 # seconds — anticipates where the ball is heading, not just where it is
const AI_DEADZONE_STOP := 4.0
const AI_DEADZONE_START := 14.0

var _ai_wander_timer := 0.0
var _ai_wander_target_y := 0.0
const AI_WANDER_INTERVAL_MIN := 1.2
const AI_WANDER_INTERVAL_MAX := 2.4

var _ai_weapon_switch_timer := randf_range(3.0, 6.0)
var _ai_pulse_select := false

var _ai_lift_timer := 0.0
var _ai_lift_decided := false

func _ready() -> void:
	_spawn_position = position
	state = ShipState.new(position, side, half_extents)
	# Story 1.4/1.5 test kit — shared placeholder until the full roster
	# (Epic 2, FR9) gives each character its own fixed, distinct kit.
	var kit: Array[WeaponData] = [
		load("res://data/weapons/machine_gun.tres"),
		load("res://data/weapons/bazooka.tres"),
	]
	weapon_state = WeaponSystemState.new(kit)

func _physics_process(delta: float) -> void:
	if ai_controlled:
		_ai_update_wander(delta)
		_ai_update_weapon_switch(delta)
		_ai_update_lift_attempt(delta)

	var lift_held := _read_lift_held()
	if lift_held:
		_lift_charge_timer = minf(_lift_charge_timer + delta, LIFT_CHARGE_CAP)
	else:
		_lift_charge_timer = 0.0

	# Charging the lift freezes movement entirely — that's the risk/reward trade.
	var input_direction := Vector2.ZERO if lift_held else _read_input()
	var speed_multiplier := VULNERABILITY_SPEED_MULTIPLIER if _vulnerability_timer > 0.0 else 1.0
	state = state.update(input_direction, delta, arena_bounds, frontier_x, speed_multiplier)
	position = state.position

	_process_weapon_selection()
	_ai_pulse_select = false # consumed for this frame, whether or not it was set
	weapon_state = weapon_state.with_cooldown_ticked(delta)
	if _read_fire_pressed():
		var result := weapon_state.fired()
		weapon_state = result.state
		if result.fired:
			_flash_timer = FLASH_DURATION
			if result.is_heavy:
				_vulnerability_timer = VULNERABILITY_DURATION # Story 1.8
			weapon_fired.emit(result.damage, result.is_heavy)
			print("%s fired %s for %d damage (gauge left: %.0f)" % [
				name, weapon_state.selected_weapon().display_name, result.damage,
				weapon_state.gauges[weapon_state.selected_index]
			])

	_vulnerability_timer = maxf(_vulnerability_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual:
		if _vulnerability_timer > 0.0:
			visual.modulate = Color(1.0, 0.45, 0.45) # reddish tint while vulnerable
		elif lift_held:
			var charge_fraction := clampf(_lift_charge_timer / LIFT_CHARGE_CAP, 0.0, 1.0)
			visual.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.84, 0.29), charge_fraction) # builds toward gold
		elif _flash_timer > 0.0:
			visual.modulate = Color(1.7, 1.7, 1.7)
		else:
			visual.modulate = Color(1.0, 1.0, 1.0)

## Story 1.9 (partial) — resets HP and position for a new round.
func reset_for_new_round() -> void:
	position = _spawn_position
	state = ShipState.new(_spawn_position, side, half_extents, ShipState.START_HP)
	_vulnerability_timer = 0.0

func _process_weapon_selection() -> void:
	var select_pressed := _read_weapon_select_pressed()
	if select_pressed and not _weapon_select_prev:
		weapon_state = weapon_state.with_selection(weapon_state.selected_index + 1)
		print("%s selected %s" % [name, weapon_state.selected_weapon().display_name])
	_weapon_select_prev = select_pressed

## Dedicated inputs, separate from movement keys (Story 1.4 AC: movement
## must never be blocked by weapon selection).
func _read_weapon_select_pressed() -> bool:
	if ai_controlled:
		return _ai_pulse_select
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_Q) # physical Q = "A" label on AZERTY
	return Input.is_physical_key_pressed(KEY_KP_0) # numpad — unambiguous across keyboard layouts

func _read_fire_pressed() -> bool:
	if ai_controlled:
		return _ai_should_fire()
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_SPACE)
	return Input.is_physical_key_pressed(KEY_ENTER)

## Placeholder raw-key input for Story 1.1 (single/local testing).
## A future pass can replace this with a proper InputMap-based scheme
## so key bindings are configurable.
func _read_input() -> Vector2:
	if ai_controlled:
		return _ai_read_input()
	var dir := Vector2.ZERO
	if player_index == 1:
		if Input.is_physical_key_pressed(KEY_D):
			dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			dir.y -= 1.0
	else:
		if Input.is_physical_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_UP):
			dir.y -= 1.0
	return dir

## Story 1.2 — aim on ball return reuses the movement direction currently
## held (Pong-style: where you're moving is where you aim).
func get_aim_input() -> Vector2:
	if ai_controlled:
		return Vector2.ZERO # Story 1.12 AC — AI doesn't need to be skilled, default reflection is enough
	return _read_input()

## Lift/spin key — holding it freezes movement and charges the lift (see
## _lift_charge_timer). AI attempts occasional lifts via _ai_lift_timer.
func _read_lift_held() -> bool:
	if ai_controlled:
		return _ai_lift_timer > 0.0
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_SHIFT)
	return Input.is_physical_key_pressed(KEY_CTRL)

## Returns the charge tier reached: <0.3s=0%, 0.3-0.6s=33%, 0.6-1.5s=66%, >=1.5s=100%.
## AI included — it now attempts occasional lifts (_ai_lift_timer -> _read_lift_held()).
func get_lift_charge() -> float:
	if _lift_charge_timer < 0.3:
		return 0.0
	elif _lift_charge_timer < 0.6:
		return 0.33
	elif _lift_charge_timer < 1.5:
		return 0.66
	return 1.0

## Story 1.12 — heuristic AI (still deliberately unskilled per AC, no
## reflex-tier precision): anticipates the ball's vertical trajectory
## with a short lookahead, uses a hysteresis band to avoid jittering in
## place near the target, and repositions horizontally (advance toward
## the frontier when the ball is on its side, retreat otherwise) so it
## reads as active rather than frozen in the x-axis.
func _ai_read_input() -> Vector2:
	if not ball_ref:
		return Vector2.ZERO

	var ball_on_my_side := ball_ref.position.x < frontier_x if side == 0 else ball_ref.position.x > frontier_x

	# Blend ball-tracking with an independent wander target so the AI doesn't
	# read as "glued" to the ball — more wander weight when the ball isn't
	# actually its problem right now, less (but never zero) when it's urgent.
	var ball_target_y := ball_ref.position.y + ball_ref.state.velocity.y * AI_LOOKAHEAD
	var wander_weight := 0.2 if ball_on_my_side else 0.6
	var target_y := lerpf(ball_target_y, _ai_wander_target_y, wander_weight)

	var diff := target_y - position.y
	if absf(diff) < AI_DEADZONE_STOP:
		_ai_vertical_dir = 0.0
	elif absf(diff) > AI_DEADZONE_START:
		_ai_vertical_dir = signf(diff)
	# else: within the hysteresis band — keep the previous direction rather
	# than flip-flopping every frame, which is what read as a "freeze".

	var horizontal := 0.0
	if ball_on_my_side:
		horizontal = 1.0 if side == 0 else -1.0 # push up to the frontier, ready to intercept
	else:
		horizontal = -1.0 if side == 0 else 1.0 # retreat toward the back wall, more time to react

	return Vector2(horizontal, _ai_vertical_dir)

## Periodically picks a new "idle" y target within the arena, so the AI
## keeps some independent motion instead of purely mirroring the ball.
func _ai_update_wander(delta: float) -> void:
	_ai_wander_timer -= delta
	if _ai_wander_timer > 0.0:
		return
	_ai_wander_timer = randf_range(AI_WANDER_INTERVAL_MIN, AI_WANDER_INTERVAL_MAX)
	var min_y := arena_bounds.position.y + half_extents.y
	var max_y := arena_bounds.position.y + arena_bounds.size.y - half_extents.y
	_ai_wander_target_y = randf_range(min_y, max_y)

## Occasionally cycles weapons, purely for variety — no strategic weighting.
func _ai_update_weapon_switch(delta: float) -> void:
	_ai_weapon_switch_timer -= delta
	if _ai_weapon_switch_timer <= 0.0:
		_ai_pulse_select = true
		_ai_weapon_switch_timer = randf_range(3.0, 6.0)

## Rolls a chance to attempt a lift whenever the ball is closing in on this
## ship's side — sets _ai_lift_timer, which _read_lift_held() then reuses
## through the same charge/freeze machinery as the human controls.
func _ai_update_lift_attempt(delta: float) -> void:
	if _ai_lift_timer > 0.0:
		_ai_lift_timer = maxf(_ai_lift_timer - delta, 0.0)
		return
	if not ball_ref:
		return
	var approaching := ball_ref.position.x < frontier_x if side == 0 else ball_ref.position.x > frontier_x
	if not approaching:
		_ai_lift_decided = false
		return
	var edge_x := arena_bounds.position.x if side == 0 else arena_bounds.position.x + arena_bounds.size.x
	if absf(ball_ref.position.x - edge_x) < 260.0 and not _ai_lift_decided:
		_ai_lift_decided = true
		if randf() < 0.3:
			_ai_lift_timer = [0.35, 0.75].pick_random()

## Story 1.12 — fires when roughly aligned with the opponent, basic reactive logic.
func _ai_should_fire() -> bool:
	if not opponent_ref:
		return false
	return absf(opponent_ref.position.y - position.y) < 90.0

## Story 1.9 (partial/test-only) — see ship_state.gd note.
func apply_damage(amount: float) -> void:
	state = state.damaged(amount)

## Stories 1.6/1.7 — fills the currently selected weapon's gauge.
func fill_selected_gauge(amount: float) -> void:
	weapon_state = weapon_state.with_gauge_added(amount)
	gauge_filled.emit(amount)
