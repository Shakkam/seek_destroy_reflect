class_name HazardZoneNode
extends Node2D

## Epic 4, Story 4.5 — "hazard_zones" twist: a temporary obstacle that
## blocks/stuns ships standing in it and deflects the ball off its surface
## ("billard volontaire", per the brainstorm). Placeholder colored circle —
## same "engine-side, no art yet" approach used throughout the project.

var radius := 24.0
var lifetime := 6.0
var stuns_ships := true
var deflects_ball := true
var ships: Array = [] # of ShipNode
var balls: Array = [] # of BallNode

const STUN_DURATION := 0.4 # short — a tap, not a lockout; it's an environmental hazard, not a weapon
const DEFLECT_COOLDOWN := 0.3 # avoid re-deflecting the same ball every frame while it lingers inside the radius

var _visual: Polygon2D
var _deflect_cooldowns: Dictionary = {} # BallNode -> float

func _ready() -> void:
	_visual = Polygon2D.new()
	var points := PackedVector2Array()
	for i in 12:
		var angle := TAU * i / 12.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_visual.polygon = points
	_visual.color = Color(1.0, 0.4, 0.2, 0.75)
	add_child(_visual)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	if stuns_ships:
		for ship in ships:
			if is_instance_valid(ship) and ship.position.distance_to(position) < radius + maxf(ship.half_extents.x, ship.half_extents.y):
				ship.apply_stun(STUN_DURATION)

	if deflects_ball:
		for ball in balls:
			if not is_instance_valid(ball):
				continue
			var cooldown: float = _deflect_cooldowns.get(ball, 0.0)
			cooldown = maxf(cooldown - delta, 0.0)
			if cooldown <= 0.0 and ball.position.distance_to(position) < radius + BallState.RADIUS:
				ball.state = ball.state.bounced_off_hazard(position)
				cooldown = DEFLECT_COOLDOWN
			_deflect_cooldowns[ball] = cooldown
