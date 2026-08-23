class_name GaugeFillEffectNode
extends Node2D

## 2026-08-15 (Camil): "quand un joueur perd la balle, ce serait bien
## qu'il y ait un petit effet — une petite boule (pour l'instant) va de
## l'endroit ou la balle a ete perdue jusqu'a la jauge qui va se remplir,
## avec un petit arc de cercle et une acceleration (rapide, 1/2 seconde
## max). Plusieurs mini boules (1px?) blanches qui vont direct de
## l'endroit ou la balle a ete perdue vers le joueur qui a gagne le
## point, pareil avec acceleration, effet 1/2s max, et c'est en
## 'touchant' le joueur que le '+50' apparait." Two purely cosmetic
## travel effects sharing one timer: a single ball arcs from the loss
## point toward an approximate gauge anchor (a true screen-space target
## would need this drawn in a CanvasLayer instead of world space —
## deferred, "pour l'instant" per Camil's own words: BallNode passes a
## rough world-space stand-in near where the HUD gauge reads), while
## several tiny white dots fly straight at the ship that just won the
## point. The "+50" FloatingTextNode popup — normally spawned instantly
## by MatchArenaNode._on_gauge_filled() — is DEFERRED to fire from here
## instead, once the mini-dots actually arrive; see ShipNode.
## fill_selected_gauge_silently() for the other half of that (the real
## gauge value still updates immediately, only the popup's timing moves).
## 2026-08-15, same day, after actually seeing it: "on va passer sur 1
## seconde, la ca va vraiment trop vite" — EFFECT_DURATION revised up
## from 0.45s to a full second; the original "1/2 seconde max" above is
## historical context for the request, not the current spec.

const EFFECT_DURATION := 1.0 # seconds — 2026-08-15 playtest: "on va passer sur 1 seconde, la ca va vraiment trop vite" (was 0.45, under Camil's own original 0.5s cap — since revised)
const MINI_BALL_COUNT := 7
const MINI_BALL_STAGGER := 0.04 # spread out a bit more now that the whole flight is longer
const ARC_HEIGHT := 60.0 # px, perpendicular bow of the gauge-ball's path
const MINI_BALL_SPREAD := 40.0 # px, perpendicular bulge at each dot's own midpoint — "faudrait les envoyer un peu en spread (la ils se suivent tous, on dirait un trait)"
# 2026-08-16 (Camil): "pour les points blancs et jaune, je verrais bien des
# petites particules derriere, type etoiles filantes (un peu comme les ames
# de Ori and the Blind Forest)" — both travelers already move along a known
# analytic bezier curve (see _bezier() below), so the trail is just that
# same curve resampled a few ticks EARLIER than the head's current
# position, shrinking + fading with distance from the head — no actual
# particle nodes needed, same "shapes via code" spirit as the rest of this
# file. A small random perpendicular jitter (redrawn fresh every frame)
# gives it the flickering "sparkle" read instead of a smooth solid streak.
const TRAIL_LENGTH := 5
const TRAIL_STEP := 0.035 # seconds of "head start" between each trailing spark
const TRAIL_JITTER := 3.0 # px, gauge ball's trail — a little looser since it's the bigger/slower traveler
const MINI_TRAIL_JITTER := 1.5 # px, mini dots' trail — tighter, they're tiny

var loss_position: Vector2
var target_ship: ShipNode
var gauge_anchor: Vector2
var fill_amount: float
## 2026-08-15 (Camil): "si les 5 cases sont remplies, on n'envoie pas de
## boule jaune" — BallNode sets this to false when the ultra meter was
## already full before this miss (nowhere empty to aim at); the mini
## white dots + the "+50" popup still happen either way.
var send_gauge_ball := true

var _elapsed := 0.0

func _physics_process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= EFFECT_DURATION:
		_spawn_popup()
		queue_free()

func _spawn_popup() -> void:
	if not is_instance_valid(target_ship) or not get_parent():
		return
	var popup := FloatingTextNode.new()
	popup.position = target_ship.position + Vector2(0.0, -16.0)
	popup.text = "+%d" % int(fill_amount)
	get_parent().add_child(popup)

## Quadratic-bezier arc (loss_position -> a control point bowed
## perpendicular to the straight line -> gauge_anchor) for the gauge-bound
## ball; each mini dot gets the SAME bezier treatment now, with its own
## perpendicular bulge fanned evenly across MINI_BALL_SPREAD so they read
## as a little burst converging on the ship instead of a single trail
## (they still start exactly at loss_position and land exactly on the
## ship either way). Both use an eased (t*t) progress so motion visibly
## speeds up over the flight — "avec une acceleration".
func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(control, t).lerp(control.lerp(b, t), t)

func _draw() -> void:
	var t := clampf(_elapsed / EFFECT_DURATION, 0.0, 1.0)
	var eased := t * t

	if send_gauge_ball:
		var mid := loss_position.lerp(gauge_anchor, 0.5)
		var perp := (gauge_anchor - loss_position).orthogonal().normalized()
		var control := mid + perp * ARC_HEIGHT
		var gauge_ball_pos := _bezier(loss_position, control, gauge_anchor, eased)
		_draw_sparkle_trail(loss_position, control, gauge_anchor, t, EFFECT_DURATION, Color(1.0, 0.9, 0.4, 1.0), 5.0, TRAIL_JITTER)
		draw_circle(gauge_ball_pos, 5.0, Color(1.0, 0.9, 0.4, 1.0))

	if is_instance_valid(target_ship):
		var dot_perp := (target_ship.position - loss_position).orthogonal().normalized()
		for i in MINI_BALL_COUNT:
			var delay := i * MINI_BALL_STAGGER
			var local_duration := EFFECT_DURATION - delay
			if local_duration <= 0.0:
				continue
			var local_t := clampf((_elapsed - delay) / local_duration, 0.0, 1.0)
			if local_t <= 0.0:
				continue
			var local_eased := local_t * local_t
			var fan := lerpf(-MINI_BALL_SPREAD, MINI_BALL_SPREAD, float(i) / float(MINI_BALL_COUNT - 1)) if MINI_BALL_COUNT > 1 else 0.0
			var dot_mid := loss_position.lerp(target_ship.position, 0.5) + dot_perp * fan
			var dot_pos := _bezier(loss_position, dot_mid, target_ship.position, local_eased)
			_draw_sparkle_trail(loss_position, dot_mid, target_ship.position, local_t, local_duration, Color(1.0, 1.0, 1.0, 1.0), 1.0, MINI_TRAIL_JITTER)
			draw_rect(Rect2(dot_pos - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), Color(1.0, 1.0, 1.0, 1.0))

## "Etoiles filantes" trail (2026-08-16): resamples the SAME bezier curve a
## few ticks behind the head's current raw progress `t` (each step worth
## TRAIL_STEP seconds of `total_duration`), applying the same t*t easing at
## each sample so the trail sits exactly on the head's real path rather
## than drifting off it. Shrinks + fades with distance from the head, and
## gets a fresh random perpendicular jitter every call (i.e. every redrawn
## frame) for a flickering sparkle instead of a smooth solid streak.
func _draw_sparkle_trail(a: Vector2, control: Vector2, b: Vector2, head_t: float, total_duration: float, base_color: Color, head_radius: float, jitter: float) -> void:
	if total_duration <= 0.0:
		return
	var step_norm := TRAIL_STEP / total_duration
	var travel_dir := (b - a).normalized()
	if travel_dir == Vector2.ZERO:
		return
	var perp := travel_dir.orthogonal()
	for k in range(1, TRAIL_LENGTH + 1):
		var sample_t := head_t - k * step_norm
		if sample_t <= 0.0:
			break
		var fade := 1.0 - float(k) / float(TRAIL_LENGTH + 1)
		var sample_eased := sample_t * sample_t
		var pos := _bezier(a, control, b, sample_eased) + perp * randf_range(-jitter, jitter) * fade
		var spark_color := Color(base_color.r, base_color.g, base_color.b, base_color.a * fade * 0.8)
		draw_circle(pos, maxf(0.5, head_radius * fade), spark_color)
