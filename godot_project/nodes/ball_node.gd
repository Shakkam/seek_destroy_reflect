class_name BallNode
extends Node2D

## Thin Godot node: detects contact with ships/walls and calls into
## simulation/ball_state.gd for all trajectory logic. Never contains
## simulation rules itself (see project-context.md, Regle absolue n1).

var state: BallState
var arena_bounds: Rect2
var frontier_x: float
var ships: Array[ShipNode] = []

var _return_cooldown := 0.0 # avoids re-triggering a return within the same frame(s)
var _last_half := -1 # -1 = unset, 0 = left half, 1 = right half — which side the ball currently occupies
var _blocked_side := -1 # side that already touched the ball during its current visit to a half; -1 = none

# Bugfix 2026-08-01: if a ship is parked right at the frontier when the ball
# (re)spawns at center, its inflated hit-rect can already overlap the spawn
# point, triggering an instant "return" the very first frame (ball appears
# to shoot backward immediately). A brief spawn grace period skips ship
# collision resolution until the ball has had a moment to actually travel.
var _spawn_grace := 0.0
const SPAWN_GRACE_DURATION := 0.25

func _ready() -> void:
	state = BallState.new(position, Vector2(BallState.BASE_SPEED, 0.0))
	_spawn_grace = SPAWN_GRACE_DURATION

func _physics_process(delta: float) -> void:
	_return_cooldown = maxf(_return_cooldown - delta, 0.0)
	_spawn_grace = maxf(_spawn_grace - delta, 0.0)

	state = state.update(delta)
	_resolve_walls()
	_resolve_half_crossing()
	if _spawn_grace <= 0.0:
		_resolve_ships()
	_resolve_out_of_bounds()

	position = state.position
	queue_redraw()

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

## Story 1.9 — also used to re-center the ball at the start of a new round.
func reset_to_center() -> void:
	var center := arena_bounds.position + arena_bounds.size / 2.0
	state = BallState.new(center, Vector2(BallState.BASE_SPEED, 0.0))
	position = state.position
	_blocked_side = -1
	_last_half = -1
	_return_cooldown = 0.0
	_spawn_grace = SPAWN_GRACE_DURATION

func _resolve_walls() -> void:
	var min_y := arena_bounds.position.y + BallState.RADIUS
	var max_y := arena_bounds.position.y + arena_bounds.size.y - BallState.RADIUS
	if state.position.y < min_y or state.position.y > max_y:
		state = state.bounced_off_wall(clampf(state.position.y, min_y, max_y))

func _resolve_ships() -> void:
	if _return_cooldown > 0.0:
		return
	for ship in ships:
		if ship.side == _blocked_side:
			continue
		var ship_rect := Rect2(ship.position - ship.half_extents - Vector2(BallState.RADIUS, BallState.RADIUS), ship.half_extents * 2.0 + Vector2(BallState.RADIUS, BallState.RADIUS) * 2.0)
		if ship_rect.has_point(state.position):
			var outgoing_side := 1 if ship.side == 0 else -1
			var lift_charge := ship.get_lift_charge()
			state = state.returned(ship.get_aim_input(), lift_charge, outgoing_side)
			_blocked_side = ship.side
			_return_cooldown = 0.15

			# Story 1.7 — fill scales with lift charge: 10 at 0% up to 15 at 100%.
			var fill := lerpf(WeaponSystemState.RETURN_GAUGE_FILL, WeaponSystemState.RETURN_GAUGE_FILL_MAX_LIFT, lift_charge)
			ship.fill_selected_gauge(fill)
			return

func _draw() -> void:
	draw_circle(Vector2.ZERO, BallState.RADIUS, Color(1.0, 0.84, 0.29, 1.0)) # liseré doré-inspired ball color
