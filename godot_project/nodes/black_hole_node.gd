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

# 2026-08-15 (Camil, screenshot with a green annotation ring): "je mettrai
# une deuxieme zone avec une couleur un poil moins marque (alpha 80)...
# avec un ralentissement un peu moins prononce" — an outer halo, bigger
# than the pull radius, that only slows (no pull — pull stays exclusive
# to `radius`, matching the black-hole-vs-outskirts read the screenshot's
# two rings suggest) and reads as fainter than the inner zone.
var outer_radius := 260.0
var outer_slow_multiplier := 0.6 # 2026-08-15 playtest: "dans la 2eme zone on ne se sent pas ralenti" — was 0.75, still milder than slow_multiplier (0.5)

# 2026-08-15 playtest: "on pourrait aussi faire avancer legerement le
# tourbillon vers le joueur adverse, vitesse lente mais suffisamment
# oppressante" — a slow, constant creep toward the opponent's LIVE
# position (not a snap/teleport), so camping at the far edge of the halo
# stops being a permanent safe harbor.
var drift_speed := 25.0 # px/s

const SLOW_REFRESH_DURATION := 0.2 # short — re-applied every tick the target is inside, so it fades quickly once they escape instead of lingering

var _visual: Polygon2D
var _outer_visual: Polygon2D
var _pulse_time := 0.0

func _ready() -> void:
	_outer_visual = _make_ring(outer_radius, Color(0.25, 0.05, 0.35, 80.0 / 255.0))
	add_child(_outer_visual) # added first so the inner zone draws on top of it
	_visual = _make_ring(radius, Color(0.25, 0.05, 0.35, 0.6))
	add_child(_visual)
	_spawn_vortex_particles()

func _make_ring(ring_radius: float, color: Color) -> Polygon2D:
	var ring := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * i / 24.0
		points.append(Vector2(cos(angle), sin(angle)) * ring_radius)
	ring.polygon = points
	ring.color = color
	return ring

## 2026-08-15 (Camil: "voir avec des particules si on peut faire une sorte
## de tourbillon"). CPUParticles2D's radial_accel (negative = pulls toward
## the emission origin) + tangential_accel (perpendicular = spin) together
## are exactly the "particles spiraling into a drain" look — no shader
## needed. A child of this node (not the parent, unlike MissileStrikeNode's
## explosion): it should live and die with the black hole itself, not
## outlive it.
func _spawn_vortex_particles() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var particles := CPUParticles2D.new()
	particles.texture = ImageTexture.create_from_image(img)
	particles.amount = 40
	particles.lifetime = 1.2
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.radial_accel_min = -140.0 # negative = pulled toward the center, like matter falling into the hole
	particles.radial_accel_max = -90.0
	particles.tangential_accel_min = 120.0 # perpendicular accel = the actual "spiral" (not a straight line inward)
	particles.tangential_accel_max = 180.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.color_ramp = _vortex_gradient()
	add_child(particles)
	particles.emitting = true

func _vortex_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.35, 1.0, 0.8)) # bright violet as it spawns near the edge
	gradient.set_color(1, Color(0.15, 0.0, 0.25, 0.0)) # fades to transparent dark purple as it's "swallowed"
	return gradient

func _physics_process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	_pulse_time += delta
	var pulse := 1.0 + sin(_pulse_time * 3.0) * 0.05 # a slow "breathing" pulse — reads as an active field, not a static decal
	if _visual:
		_visual.scale = Vector2.ONE * pulse
	if _outer_visual:
		_outer_visual.scale = Vector2.ONE * pulse

	if not is_instance_valid(target):
		return
	if drift_speed > 0.0:
		var to_target := target.position - position
		if to_target.length() > 1.0:
			position += to_target.normalized() * drift_speed * delta
	var dist := target.position.distance_to(position)
	if dist < radius:
		target.apply_external_slow(SLOW_REFRESH_DURATION, slow_multiplier)
		var direction := (position - target.position)
		if direction.length() >= 1.0:
			target.apply_knockback(direction.normalized() * pull_speed * delta)
	elif dist < outer_radius:
		target.apply_external_slow(SLOW_REFRESH_DURATION, outer_slow_multiplier) # outer halo: slow only, no pull
