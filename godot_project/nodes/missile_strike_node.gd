class_name MissileStrikeNode
extends Node2D

## Lourd's Ultra rework — "Pluie de Scuds" (2026-08-15, Camil: "actuellement
## il envoie juste quelques missiles: bof. j'aurais plus vu une pluie de
## missiles qui arrivent du haut... ca doit etre tres dur a eviter. On peut
## faire apparaitre petit a petit des cibles au sol, et le missile arrive du
## haut et tombe dans la cible en 1/2s."). One instance = one falling shell:
## a ground reticle (a closing ring, drawn via _draw() same as every other
## placeholder-shape effect in this project) telegraphs the impact point for
## `fall_duration`, while the shell sprite sells "falling from above" purely
## through scale + a small starting Y offset — there's no real height axis
## at this top-down camera angle, so the illusion is exactly what Camil
## described: spawn it big (`start_scale`) and offset upward, then shrink/
## slide it down onto the target over the fall. MatchArenaNode spawns many
## of these staggered (see _ultra_pluie_de_scuds()) — one alone is trivial
## to sidestep, the accumulating field of reticles is what makes standing
## still the losing move.

const SHELL_TEXTURE := preload("res://assets/art/vfx/bazook.png")
const SPAWN_Y_OFFSET := 24.0 # px the shell starts above its own target, purely cosmetic

var target_position: Vector2
var fall_duration := 0.5
var start_scale := 4.0
var impact_radius := 40.0
var impact_damage := 4.0
var impact_push_distance := 30.0
var opponent: ShipNode

var _elapsed := 0.0
var _sprite: Sprite2D

func _ready() -> void:
	position = target_position
	_sprite = Sprite2D.new()
	_sprite.texture = SHELL_TEXTURE
	_sprite.scale = Vector2.ONE * start_scale
	_sprite.position = Vector2(0.0, -SPAWN_Y_OFFSET)
	add_child(_sprite)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / fall_duration, 0.0, 1.0)
	_sprite.scale = Vector2.ONE * lerpf(start_scale, 1.0, t)
	_sprite.position = Vector2(0.0, lerpf(-SPAWN_Y_OFFSET, 0.0, t))
	queue_redraw()
	if _elapsed >= fall_duration:
		_impact()

## Closing ring — starts as a bare outline and sweeps shut over fall_duration,
## reading as a countdown to impact (same pulse-driven-clarity idea as
## BlackHoleNode/WindVortexNode, just a timer instead of a breathing loop).
func _draw() -> void:
	var t := clampf(_elapsed / fall_duration, 0.0, 1.0)
	draw_arc(Vector2.ZERO, impact_radius, -PI / 2.0, -PI / 2.0 + TAU * t, 32, Color(1.0, 0.35, 0.1, 0.85), 3.0)

func _impact() -> void:
	if is_instance_valid(opponent) and opponent.position.distance_to(target_position) < impact_radius:
		opponent.apply_damage(impact_damage)
		var direction := opponent.position - target_position
		if direction.length() < 1.0:
			direction = Vector2(1.0 if opponent.side == 0 else -1.0, 0.0) # degenerate case: opponent's center exactly on the impact point
		opponent.apply_knockback(direction.normalized() * impact_push_distance)
	_spawn_explosion()
	queue_free()

const EXPLOSION_PARTICLE_COUNT := 18
const EXPLOSION_LIFETIME := 0.35

## 2026-08-15 (Camil: "une petite explosion avec des particules pour chaque
## impact"). CPUParticles2D, not GPUParticles2D — no shader/material resource
## to author, everything is set from code (same "shapes via code, no
## imported dependencies" spirit as this project's other placeholder VFX).
## Parented to get_parent() (MatchArenaNode), not self: this node calls
## queue_free() on itself right after, which would free the burst
## mid-animation if it were a child of self.
func _spawn_explosion() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var particles := CPUParticles2D.new()
	particles.texture = ImageTexture.create_from_image(img)
	particles.position = target_position
	particles.amount = EXPLOSION_PARTICLE_COUNT
	particles.lifetime = EXPLOSION_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0 # full radial burst, not a directional cone
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 160.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color_ramp = _fade_out_gradient()
	get_parent().add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

func _fade_out_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.6, 0.2, 1.0)) # matches the closing ring's orange
	gradient.set_color(1, Color(0.4, 0.1, 0.05, 0.0)) # fades to transparent, not just a hard cutoff at end of lifetime
	return gradient
