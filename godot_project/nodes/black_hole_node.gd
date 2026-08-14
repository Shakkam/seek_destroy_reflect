class_name BlackHoleNode
extends Node2D

## Contrôleur's Ultra — "Trou noir" (2026-08-13 Epic 4 party-mode memlog:
## "champ continu, attire+ralentit, synergie avec ses tourelles"). Same
## "self-contained continuous-effect node with its own lifetime" pattern
## as HazardZoneNode: while the target is inside `radius`, pulls it
## toward this node's position every tick (reuses ShipNode.apply_knockback(),
## the same one-shot positional shove Lourd's heavy_push already uses)
## and applies a short, continuously-refreshed slow
## (ShipNode.apply_external_slow()) that fades fast once they leave the
## radius rather than lingering. "Synergie avec ses tourelles" is
## emergent, not special-cased: dragging the opponent toward the black
## hole's position (placed on Contrôleur's own side, where her turrets
## already tend to be) naturally pulls them into turret range/fire.

var radius := 90.0
var pull_speed := 140.0 # px/s of pull while inside the radius
var slow_multiplier := 0.5
var duration := 3.0
var target: ShipNode

const SLOW_REFRESH_DURATION := 0.2 # short — re-applied every tick the target is inside, so it fades quickly once they escape instead of lingering

var _visual: Polygon2D
var _pulse_time := 0.0

func _ready() -> void:
	_visual = Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * i / 24.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_visual.polygon = points
	_visual.color = Color(0.25, 0.05, 0.35, 0.6)
	add_child(_visual)

func _physics_process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	_pulse_time += delta
	if _visual:
		_visual.scale = Vector2.ONE * (1.0 + sin(_pulse_time * 3.0) * 0.05) # a slow "breathing" pulse — reads as an active field, not a static decal

	if not is_instance_valid(target):
		return
	if target.position.distance_to(position) >= radius:
		return
	target.apply_external_slow(SLOW_REFRESH_DURATION, slow_multiplier)
	var direction := (position - target.position)
	if direction.length() < 1.0:
		return
	target.apply_knockback(direction.normalized() * pull_speed * delta)
