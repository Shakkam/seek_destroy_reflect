class_name LaserMeshNode
extends Node2D

## Zoneur's Ultra rework — "Grille Laser" (2026-08-15, Camil: "ca fait
## trois lasers horizontaux. On avait dit que ca devait faire des laser en
## maillage, qui apparaissent au fur et a mesure (10 lasers sur 1 seconde),
## dans tous les sens, et uniquement dans le champ adverse, direction
## random"). One instance = one diagonal laser segment at a random angle,
## clipped to a bounding rect (the opponent's half) — BeamNode is built
## entirely around a horizontal "shooter fires toward the wall" model
## (_update_shape() always draws a Vector2(length, thickness) strip with
## no rotation), so bolting arbitrary angles onto it would fight its own
## assumptions; this is a dedicated node instead. MatchArenaNode spawns
## LASER_MESH_COUNT of these staggered over ~1s (see _ultra_grille_laser())
## so the web visibly builds up rather than appearing all at once.

const TICK_INTERVAL := 0.1
const FADE_DURATION := 0.15

var start: Vector2
var end: Vector2
var lifetime := 1.2
var damage_per_tick := 1.0
var target: ShipNode
var thickness := 5.0
var color := Color(0.4, 1.0, 0.5, 0.85)

# 2026-08-22 (Zoneur's passive reward — Camil: "il faudrait que le laser se
# deplace jusqu'au centre (s'il apparait vers le fond) ou vers le fond
# (s'il apparait vers le centre)") — opt-in, px/s applied to both start.x
# and end.x every tick. 0 (default) leaves every OTHER use (the real
# Grille Laser Ultra's random diagonal segments) exactly as static as
# before. See MatchArenaNode._fire_passive_reward()'s "laser" case for how
# this gets set (always aimed at the opposite edge of the opponent's half,
# sized to arrive exactly as `lifetime` runs out).
var horizontal_velocity: float = 0.0

var _elapsed := 0.0
var _hit_timer := 0.0

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	if horizontal_velocity != 0.0:
		start.x += horizontal_velocity * delta
		end.x += horizontal_velocity * delta
	queue_redraw()

	if not is_instance_valid(target):
		return
	_hit_timer -= delta
	if _hit_timer > 0.0:
		return
	_hit_timer = TICK_INTERVAL
	var hit_radius := thickness / 2.0 + maxf(target.half_extents.x, target.half_extents.y)
	if _distance_to_segment(target.position) <= hit_radius:
		target.apply_damage(damage_per_tick)

func _distance_to_segment(point: Vector2) -> float:
	var seg := end - start
	var len_sq := seg.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(seg) / len_sq, 0.0, 1.0)
	return point.distance_to(start + seg * t)

## Same quick fade in/out as BeamNode's own pulses, applied to a raw
## draw_line() rather than a rect — no rotation gymnastics needed since
## start/end are already the exact clipped endpoints in world space.
func _draw() -> void:
	var alpha := 1.0
	if _elapsed < FADE_DURATION:
		alpha = _elapsed / FADE_DURATION
	elif _elapsed > lifetime - FADE_DURATION:
		alpha = clampf((lifetime - _elapsed) / FADE_DURATION, 0.0, 1.0)
	draw_line(start, end, Color(color.r, color.g, color.b, color.a * alpha), thickness)

## Picks a random point inside `bounds` and a random angle, then clips the
## resulting infinite line to `bounds` (slab method) so the segment always
## spans edge-to-edge across the confined area, same visual weight as the
## reference screenshot's corner-to-corner crossing lines — not a short
## random segment floating in the middle.
static func random_clipped_to(bounds: Rect2) -> Array:
	var anchor := Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)
	var angle := randf() * PI
	var dir := Vector2(cos(angle), sin(angle))
	var t_min := -INF
	var t_max := INF
	for axis in [0, 1]:
		var d: float = dir.x if axis == 0 else dir.y
		var p: float = anchor.x if axis == 0 else anchor.y
		var lo: float = bounds.position.x if axis == 0 else bounds.position.y
		var hi: float = lo + (bounds.size.x if axis == 0 else bounds.size.y)
		if absf(d) > 0.0001:
			var t1 := (lo - p) / d
			var t2 := (hi - p) / d
			t_min = maxf(t_min, minf(t1, t2))
			t_max = minf(t_max, maxf(t1, t2))
	return [anchor + dir * t_min, anchor + dir * t_max]
