class_name FireTrailNode
extends Node2D

## Perturbateur's charged Boomerang de Feu (2026-08-17, Camil: "on lance un
## gros boomerang, mais il laisse une trainee de feu (particules) derriere
## lui, qui font des degats si on les touche. Les trainees durent 3s").
## Dropped periodically along the charged boomerang's flight path (see
## ProjectileNode.leaves_fire_trail/FIRE_TRAIL_DROP_INTERVAL) — a stationary
## damage-over-time puddle, same "engine-side placeholder shape" approach as
## HazardZoneNode. Ticks damage repeatedly while `victim` overlaps it (a
## lingering ship should keep burning, not take one hit and walk through
## for free) rather than a single-hit-then-consumed design.
##
## 2026-08-18 look pass, two rounds of live feedback from Camil:
## 1) "pas mal les flammes! par contre niveau look c'est pas ouf" — first
##    pass was one flat, static, solid-orange Polygon2D circle (not
##    actually particles). Added a CPUParticles2D flame on top.
## 2) "un peu mieux, mais je ferais des particules plus grosses, plus
##    'feu', sur une ligne continue et pas les ronds marron" — the ground
##    "scorch mark" decal (meant to telegraph the hitbox) was exactly the
##    "ronds marron" he didn't want; REMOVED outright. Consecutive puddles
##    also read as separate dots because FIRE_TRAIL_DROP_INTERVAL (0.12s)
##    left real gaps between them at the boomerang's ~620px/s travel speed
##    — halved to 0.06s (see ProjectileNode) so puddles physically overlap
##    into one strip, radius/particle scale/count all raised so each one
##    alone reads as a real gout of flame instead of a sparkle.

var victim: ShipNode = null
var radius := 24.0
var lifetime := 3.0
var damage_per_tick := 2.0
const TICK_INTERVAL := 0.4 # repeat while lingering — see file doc comment
const FADE_OUT_DURATION := 0.6 # last stretch of lifetime — flame dies down instead of popping out

var _flame: CPUParticles2D
var _tick_cooldown := 0.0

func _ready() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	_flame = CPUParticles2D.new()
	_flame.texture = ImageTexture.create_from_image(img)
	_flame.amount = 14
	_flame.lifetime = 0.55
	_flame.preprocess = 0.55 # already mid-flicker on the frame it appears, not an empty puddle for the first half-second
	_flame.explosiveness = 0.0 # continuous, not a burst
	_flame.direction = Vector2.UP
	_flame.spread = 45.0
	_flame.gravity = Vector2(0.0, -50.0) # flames rise
	_flame.initial_velocity_min = 20.0
	_flame.initial_velocity_max = 55.0
	_flame.scale_amount_min = 1.1
	_flame.scale_amount_max = 2.4
	_flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flame.emission_sphere_radius = radius * 0.7
	_flame.emitting = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.98, 0.75, 1.0)) # near-white-hot core
	gradient.add_point(0.3, Color(1.0, 0.7, 0.15, 1.0)) # yellow-orange body
	gradient.add_point(0.7, Color(1.0, 0.35, 0.05, 0.85)) # deep orange-red
	gradient.set_color(1, Color(0.6, 0.05, 0.0, 0.0)) # dies to transparent ember-red
	_flame.color_ramp = gradient
	add_child(_flame)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if lifetime < FADE_OUT_DURATION and _flame:
		_flame.emitting = false # let already-spawned particles finish their own lifetime instead of vanishing mid-flicker

	_tick_cooldown = maxf(_tick_cooldown - delta, 0.0)
	if _tick_cooldown > 0.0 or not is_instance_valid(victim):
		return
	var reach := Vector2(radius, radius) + victim.half_extents
	if absf(victim.position.x - position.x) < reach.x and absf(victim.position.y - position.y) < reach.y:
		victim.apply_damage(damage_per_tick)
		_tick_cooldown = TICK_INTERVAL
