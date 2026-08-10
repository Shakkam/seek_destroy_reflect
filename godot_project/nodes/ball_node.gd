class_name BallNode
extends Node2D

## Thin Godot node: detects contact with ships/walls and calls into
## simulation/ball_state.gd for all trajectory logic. Never contains
## simulation rules itself (see project-context.md, Regle absolue n1).

var state: BallState
var arena_bounds: Rect2
var frontier_x: float
var ships: Array[ShipNode] = []
var active := true # set false by MatchArenaNode during the pre-match "ready?" gate

var _return_cooldown := 0.0 # avoids re-triggering a return within the same frame(s)
var _last_half := -1 # -1 = unset, 0 = left half, 1 = right half — which side the ball currently occupies
var _blocked_side := -1 # side that already touched the ball during its current visit to a half; -1 = none

# Lourd's "heavy_push" rule (2026-08-09, Camil: "il faudrait donc que ca
# 'pousse' la balle et que cette derniere pousse le joueur adverse") — armed
# by a fully-charged (100%) lift return from a heavy_push character, consumed
# (knocks the ship back, then clears) the next time ANY ship's rect is hit —
# normally the opponent reaching for it, whether they successfully return it
# or not. Cleared on a fresh rally (reset_to_center()) so a stale arm from a
# ball that went out of bounds untouched can never carry into the next point.
var _push_pending := false
const HEAVY_PUSH_DISTANCE := 40.0 # px, instantaneous shove on contact

# Bugfix 2026-08-01 (v4): a ship parked at the frontier could trigger an
# instant "return" the moment the ball (re)spawns at center (ball appears to
# shoot backward immediately). Fixed with a "net" — a neutral zone straddling
# the frontier where ship collision never resolves, regardless of timers or
# how the ball got there. The ball always spawns from inside this zone.
# Since Story "neutral zone as a real movement wall" (2026-08-01), ships can
# no longer physically enter this band either — see ShipState.NEUTRAL_ZONE_HALF_WIDTH,
# the single source of truth both this check and the ship clamp read from.

const SPAWN_TILT_MAX_RAD := 0.35 # ~20 degrees either side of horizontal

# Placeholder sprite (2026-08-02, v2) — single static sprite, actually
# rotated in-engine instead of cycling 3 hand-drawn frames (the swap read as
# a janky/weird motion since those frames weren't a true rotation sequence).
const BALL_TEXTURE := preload("res://assets/art/vfx/ball_1.png")
const ROTATION_SPEED := 6.0 # rad/s
var _sprite: Sprite2D

## Random slight tilt at spawn so it doesn't always fire perfectly
## horizontal (which read as "the game isn't moving").
func _spawn_velocity() -> Vector2:
	return Vector2(BallState.BASE_SPEED, 0.0).rotated(randf_range(-SPAWN_TILT_MAX_RAD, SPAWN_TILT_MAX_RAD))

func _in_neutral_zone() -> bool:
	return absf(state.position.x - frontier_x) < ShipState.NEUTRAL_ZONE_HALF_WIDTH

func _ready() -> void:
	state = BallState.new(position, _spawn_velocity())
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = BALL_TEXTURE
	_sprite.scale = Vector2(1.4, 1.4) # engine-side bump — art reads small at native size (2026-08-02 feedback)
	add_child(_sprite)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_return_cooldown = maxf(_return_cooldown - delta, 0.0)

	state = state.update(delta)
	_resolve_walls()
	_resolve_half_crossing()

	if not _in_neutral_zone():
		_resolve_ships()
		_resolve_turrets()

	_resolve_out_of_bounds()

	position = state.position
	_sprite.rotation += ROTATION_SPEED * delta

## A ship can only return the ball once per visit to its own half — once
## the ball crosses back to the other half, the block clears. Prevents the
## "stuck" bug where chasing the ball re-triggers the return repeatedly.
func _resolve_half_crossing() -> void:
	var current_half := 0 if state.position.x < frontier_x else 1
	if current_half != _last_half:
		_blocked_side = -1
		_last_half = current_half

## Story 1.6 — a missed ball fills the opponent's gauge (never direct damage),
## then respawns at center so play can continue.
func _resolve_out_of_bounds() -> void:
	var missed_side := -1
	if state.position.x < arena_bounds.position.x - BallState.RADIUS * 4.0:
		missed_side = 0
	elif state.position.x > arena_bounds.position.x + arena_bounds.size.x + BallState.RADIUS * 4.0:
		missed_side = 1

	if missed_side != -1:
		var opponent_side := 1 if missed_side == 0 else 0
		for ship in ships:
			if ship.side == opponent_side:
				ship.fill_selected_gauge(WeaponSystemState.MISS_GAUGE_FILL)
				break

		reset_to_center()

const SPAWN_Y_MARGIN := 100.0 # keeps the random spawn Y away from the top/bottom walls

## Frontier X (always), random Y within a safe margin of the arena — so the
## ball doesn't always reappear at the exact same spot, and doesn't reliably
## line up with wherever a ship happens to be resting (2026-08-01 feedback).
func _random_spawn_position() -> Vector2:
	var min_y := arena_bounds.position.y + SPAWN_Y_MARGIN
	var max_y := arena_bounds.position.y + arena_bounds.size.y - SPAWN_Y_MARGIN
	return Vector2(frontier_x, randf_range(min_y, max_y))

## Story 1.9 — also used to re-center the ball at the start of a new round.
func reset_to_center() -> void:
	state = BallState.new(_random_spawn_position(), _spawn_velocity())
	position = state.position
	_blocked_side = -1
	_last_half = -1
	_return_cooldown = 0.0
	_push_pending = false # a heavy_push ball that went out of bounds untouched must not carry into the next rally

func _resolve_walls() -> void:
	var min_y := arena_bounds.position.y + BallState.RADIUS
	var max_y := arena_bounds.position.y + arena_bounds.size.y - BallState.RADIUS
	if state.position.y < min_y or state.position.y > max_y:
		state = state.bounced_off_wall(clampf(state.position.y, min_y, max_y))

func _ship_rect(ship: ShipNode) -> Rect2:
	return Rect2(
		ship.position - ship.half_extents - Vector2(BallState.RADIUS, BallState.RADIUS),
		ship.half_extents * 2.0 + Vector2(BallState.RADIUS, BallState.RADIUS) * 2.0
	)

func _resolve_ships() -> void:
	if _return_cooldown > 0.0:
		return
	for ship in ships:
		if ship.side == _blocked_side:
			continue
		if _ship_rect(ship).has_point(state.position):
			# Lourd's "heavy_push" rule (2026-08-09) — an empowered ball (armed
			# by a previous 100%-charged lift return) shoves whichever ship it
			# reaches next, whether or not they go on to return it too.
			if _push_pending:
				ship.apply_knockback(Vector2(signf(state.velocity.x) * HEAVY_PUSH_DISTANCE, 0.0))
				_push_pending = false

			var outgoing_side := 1 if ship.side == 0 else -1
			var lift_charge := ship.get_lift_charge()
			# Zoneur's "aim_reticle" rule (2026-08-09) — a return connecting
			# after holding Lift long enough carries a ball speed boost.
			state = state.returned(ship.get_aim_input(), lift_charge, outgoing_side, ship.get_return_speed_boost())
			_blocked_side = ship.side
			_return_cooldown = 0.15

			# Story 1.7 — fill scales with lift charge: 10 at 0% up to 15 at 100%.
			# Epic 4's "gauge_floor" twist can lock this self-fill specifically
			# (fill_selected_gauge_from_return), while Story 1.6's miss-fill
			# above always goes through the ungated fill_selected_gauge().
			var fill := lerpf(WeaponSystemState.RETURN_GAUGE_FILL, WeaponSystemState.RETURN_GAUGE_FILL_MAX_LIFT, lift_charge)
			ship.fill_selected_gauge_from_return(fill)

			# Arm the push for the NEXT contact if this return was itself a
			# fully-charged lift from a heavy_push character.
			_push_pending = ship.character != null and ship.character.special_rule == "heavy_push" and lift_charge >= 1.0
			return

## Turrets deflect the ball too (2026-08-09 playtest, Contrôleur: "vu qu'on
## parle d'un contrôleur, les tourelles pourraient renvoyer la balle aussi !
## ce serait genial"). No aim input and no lift charge — a stationary
## mirror-bounce (BallState.returned() with Vector2.ZERO aim falls back to
## reflecting the incoming angle), same _blocked_side/_return_cooldown
## gating as ships so a turret can't juggle the ball back and forth forever.
func _resolve_turrets() -> void:
	if _return_cooldown > 0.0:
		return
	for child in get_parent().get_children():
		if not (child is TurretNode):
			continue
		var turret: TurretNode = child
		if turret.owner_side == _blocked_side:
			continue
		if _turret_rect(turret).has_point(state.position):
			var outgoing_side := 1 if turret.owner_side == 0 else -1
			state = state.returned(Vector2.ZERO, 0.0, outgoing_side)
			_blocked_side = turret.owner_side
			_return_cooldown = 0.15
			return

func _turret_rect(turret: TurretNode) -> Rect2:
	return Rect2(
		turret.position - TurretNode.HALF_EXTENTS - Vector2(BallState.RADIUS, BallState.RADIUS),
		TurretNode.HALF_EXTENTS * 2.0 + Vector2(BallState.RADIUS, BallState.RADIUS) * 2.0
	)
