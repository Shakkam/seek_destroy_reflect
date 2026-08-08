class_name BallState
extends RefCounted

## Pure, deterministic ball simulation state. No Node/Godot references —
## see project-context.md, "Frontiere simulation/rendu" (Regle absolue n1).
## The ball never deals damage — it is purely a resource-catch mechanic (GDD).

const BASE_SPEED := 418.0 # +10% (2026-08-01 playtest feedback: felt a bit slow to start)
const RADIUS := 10.0
const SPEED_INCREMENT_PER_RETURN := 18.0 # Story 1.3 — ball speeds up slightly each rally exchange
const SPIN_STRENGTH := 1.5 # rad/s of curvature at full (100%) lift charge
const SPIN_DECAY := 1.0 # rad/s^2 — spin fades out over the flight instead of curving forever

var position: Vector2
var velocity: Vector2
var spin: float # rad/s of curvature applied to the velocity direction over time (Story 1.2 lift/spin effect)
var rally_count: int # number of successful returns in the current rally (Story 1.3); resets to 0 whenever a fresh BallState is constructed

func _init(start_position: Vector2, start_velocity: Vector2, start_spin: float = 0.0, start_rally_count: int = 0) -> void:
	position = start_position
	velocity = start_velocity
	spin = start_spin
	rally_count = start_rally_count

func update(delta: float) -> BallState:
	var new_velocity := velocity
	if spin != 0.0:
		new_velocity = velocity.rotated(spin * delta)
	var new_spin := move_toward(spin, 0.0, SPIN_DECAY * delta)
	return BallState.new(position + new_velocity * delta, new_velocity, new_spin, rally_count)

func bounced_off_wall(clamped_y: float) -> BallState:
	return BallState.new(Vector2(position.x, clamped_y), Vector2(velocity.x, -velocity.y), spin, rally_count)

## Epic 4, Story 4.5 — "hazard_zones" twist: reflects velocity off a
## circular obstacle's surface normal (same speed, new direction), the
## "billard volontaire" deflection called for in the brainstorm.
func bounced_off_hazard(hazard_center: Vector2) -> BallState:
	var normal := (position - hazard_center).normalized()
	if normal.length() < 0.01:
		normal = Vector2.RIGHT # degenerate case: ball position exactly on the hazard's center
	return BallState.new(position, velocity.bounce(normal), spin, rally_count)

## Player-initiated return.
## aim_direction: raw directional input at the moment of contact (Vector2.ZERO if none held).
## lift_charge: 0.0-1.0, how charged the lift/spin was (see WeaponSystemState-adjacent
## charge tiers on ShipNode: hold-to-charge, 0/33/66/100%).
## outgoing_side: +1 to send the ball right, -1 to send it left.
func returned(aim_direction: Vector2, lift_charge: float, outgoing_side: int) -> BallState:
	var dir: Vector2
	if aim_direction.length() > 0.01:
		dir = Vector2(outgoing_side, clampf(aim_direction.y, -1.0, 1.0)).normalized()
	else:
		# No aim input -> default straightforward reflection (AC, Story 1.2):
		# a true mirror bounce off the paddle, exact opposite horizontal angle,
		# vertical direction preserved (not flattened to a straight horizontal shot).
		var mirrored := Vector2(-velocity.x, velocity.y)
		dir = mirrored.normalized() if mirrored.length() > 0.01 else Vector2(outgoing_side, 0.0)

	var new_spin := SPIN_STRENGTH * lift_charge
	if outgoing_side < 0:
		new_spin = -new_spin

	var new_rally_count := rally_count + 1
	var speed := BASE_SPEED + SPEED_INCREMENT_PER_RETURN * new_rally_count
	return BallState.new(position, dir * speed, new_spin, new_rally_count)
