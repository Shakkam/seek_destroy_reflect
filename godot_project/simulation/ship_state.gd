class_name ShipState
extends RefCounted

## Pure, deterministic ship simulation state.
## No references to Node, Godot's scene tree, or wall-clock time —
## see project-context.md, "Frontiere simulation/rendu" (Regle absolue n1).
##
## NOTE: `hp` here is a lightweight test-only counter so damage is visible
## while testing Stories 1.5-1.7. It is NOT the full Story 1.9 implementation
## (best-of-3 rounds, round reset, match win/loss) — that lands separately.

const SPEED := 420.0 # px/s — "relativement rapide, mais pas ultra" (GDD)
const START_HP := 100.0

var position: Vector2
var side: int # 0 = left half, 1 = right half
var half_extents: Vector2 # half width/height, used to keep the ship's edges (not just its center) in bounds
var hp: float

func _init(start_position: Vector2, ship_side: int, ship_half_extents: Vector2, start_hp: float = START_HP) -> void:
	position = start_position
	side = ship_side
	half_extents = ship_half_extents
	hp = start_hp

## update(state, input) -> new_state
## delta is passed explicitly (fixed physics tick, see project.godot) —
## never read from Time.* inside simulation code.
func update(input_direction: Vector2, delta: float, bounds: Rect2, frontier_x: float, speed_multiplier: float = 1.0) -> ShipState:
	var new_state := ShipState.new(position, side, half_extents, hp)
	var move := input_direction
	if move.length() > 1.0:
		move = move.normalized()
	new_state.position = position + move * SPEED * speed_multiplier * delta
	new_state.position = _clamp_to_half(new_state.position, bounds, frontier_x)
	return new_state

func damaged(amount: float) -> ShipState:
	return ShipState.new(position, side, half_extents, maxf(hp - amount, 0.0))

func _clamp_to_half(pos: Vector2, bounds: Rect2, frontier_x: float) -> Vector2:
	var min_x := bounds.position.x + half_extents.x
	var max_x := bounds.position.x + bounds.size.x - half_extents.x
	var min_y := bounds.position.y + half_extents.y
	var max_y := bounds.position.y + bounds.size.y - half_extents.y
	var clamped := pos
	clamped.y = clampf(clamped.y, min_y, max_y)
	if side == 0:
		clamped.x = clampf(clamped.x, min_x, frontier_x - half_extents.x)
	else:
		clamped.x = clampf(clamped.x, frontier_x + half_extents.x, max_x)
	return clamped
