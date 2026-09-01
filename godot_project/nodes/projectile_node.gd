class_name ProjectileNode
extends Node2D

## Visual + damage-application placeholder for a fired shot — travels in a
## straight line (or gently homes, bazooka only), applies its damage to
## `target` on contact (a lightweight slice of Story 1.9's HP, see
## ship_state.gd note), and disappears. Rendered via placeholder R-Type
## sprites (2026-08-02) instead of a plain circle — see match_arena_node.gd
## for which textures are assigned per weapon/shooter.

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 2.0
var damage: float = 0.0 # matches WeaponData.damage's own type (float since 2026-09-01, to allow fractional per-hit values like Boomerang's 1.5)
var target: ShipNode = null
var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (bazooka only)
# 2026-08-15 (Camil, Traqueur's La Meute ultra): "il faut vraiment que les
# missiles cherchent l'ennemi (quitte a revenir en arriere...)" — true 2D
# pursuit (full velocity vector rotates toward the target, can reverse
# direction) instead of the base homing_missile's gentler Y-only steering.
# Then same day: "attention, sur traqueur en touchant a l'ultra tu as
# egalement modifie le comportement du tir normal ! il faut revenir en
# arriere, et garder le cote 'dur a esquiver' uniquement pour l'ultra" —
# so this is an opt-in flag (default false = the original Y-only
# behavior, still used by the base homing_missile), set true only for
# ultra_la_meute (see MatchArenaNode._spawn_projectile()), not a change
# to what plain `homing_strength > 0.0` means everywhere.
var homing_full_turn: bool = false
var effect_type: String = "damage" # Epic 2 — "damage" (default) or "stun"
var effect_duration: float = 0.0 # Epic 2 — stun length applied on hit when effect_type == "stun"
# 2026-08-16 (Camil, Traqueur's La Meute): "quand ils disparaissent, on
# pourrait mettre une petite explosion, petit degat de zone (genre 2X la
# taille du missile) avec particules" — fires once, when a missile times
# out WITHOUT ever landing a direct hit (see the lifetime<=0.0 branch
# below), not on contact (contact already applies `damage` via
# _apply_hit_effect() and despawns immediately, no double-dip). 0 (default,
# every other weapon) = just vanishes silently, unchanged.
var expiry_explosion_damage: float = 0.0
var expiry_explosion_radius: float = 0.0
var spin_speed: float = 0.0 # deg/sec — rotates the whole node; unused by the Tourbillon (its 3-frame texture cycle already reads as spinning) but left generic for any future weapon that wants it

# Perturbateur's charged Boomerang de Feu (2026-08-17, Camil: "le tir
# charge n'est pas bien... on lance un gros boomerang, mais il laisse une
# trainee de feu (particules) derriere lui, qui font des degats si on les
# touche. Les trainees durent 3s") — replaces the flat "5x damage/5x size"
# charged release's own identity with a real over-time threat. Opt-in
# (false for every other weapon/release), set only on the charged
# stun_boomerang spawn (MatchArenaNode._on_charged_weapon_fired). Drops a
# FireTrailNode hazard every FIRE_TRAIL_DROP_INTERVAL of flight — both
# legs, since "derriere lui" doesn't distinguish outbound from return —
# targeting `target` (the opponent, never the shooter).
var leaves_fire_trail: bool = false
# 2026-08-18 (Camil, live feedback: "je ferais [...] une ligne continue et
# pas les ronds marron") — at 0.12s and ~620px/s travel speed, consecutive
# FireTrailNode puddles (radius 24 -> 48px wide) landed ~74px apart,
# clearly separate dots. Halved so they land ~37px apart, comfortably
# inside each other's radius — reads as one continuous strip instead of a
# dotted line.
const FIRE_TRAIL_DROP_INTERVAL := 0.06
var _fire_trail_timer := 0.0

# Vif's Tourbillon (2026-08-09) — Camil's drawing: not a straight line, small
# forward-advancing loops the whole way. A trochoid: constant drift velocity
# (captured once at spawn) plus a constant-radius circular velocity added on
# top each frame, so position integrates into tight repeating loops instead
# of a spiral (which a naively-rotating velocity with no drift reference
# would produce). Mutually exclusive with is_boomerang/homing_strength.
var is_looping := false
var loop_radius: float = 18.0 # px
var loop_angular_speed: float = 1080.0 # deg/sec — how fast/tight each loop is
var _loop_elapsed := 0.0

# Vif's Ultra "Bourrasque" rework (2026-08-15, Camil: "les tourbillons
# avancent de plus en plus vite") — a straight line that speeds up over
# time instead of holding constant speed, distinct from every other
# motion mode (no turning, no wave, no loop). 0 = no effect (every other
# weapon), so this is purely additive/opt-in.
var acceleration: float = 0.0 # px/s^2, applied along the current velocity direction
var _drift_velocity := Vector2.ZERO # the straight-line velocity captured at spawn; is_looping's loop AND is_sine's wave both orbit/ride this drifting reference

# 2026-08-13, Vif's Tourbillon rework (Camil: "je n'aime pas [l'arme de
# vif]... que son tir ne fasse plus des cercles, mais parte tout droit
# avec une trajectoire sinusoidale") — a straight-line drift (like a
# normal shot) with a lateral oscillation added on top, instead of
# is_looping's closed circular orbit. Same trochoid-style construction as
# is_looping: velocity = constant drift + a perpendicular component that
# oscillates (there, tangential/circular; here, sinusoidal), so position
# integrates cleanly without drifting off-axis. Mutually exclusive with
# is_looping/is_boomerang/homing_strength.
var is_sine := false
var sine_amplitude: float = 40.0 # px, lateral swing either side of the straight path
var sine_angular_speed: float = 720.0 # deg/sec — how fast the wave oscillates
var _sine_elapsed := 0.0

# "Shmup juice pass" (2026-08-05) — boomerang motion: curves outward for
# BOOMERANG_OUT_DURATION, then arcs back toward `shooter`. Mutually exclusive
# with homing_strength (boomerang weapons don't set it). Unlike a normal
# projectile it does NOT despawn on hit, so it can land once on the way out
# and once on the way back — each guarded separately below.
var is_boomerang := false
var shooter: ShipNode = null
# 2026-08-10, Camil, in order:
# 1) "boomerang ne marche pas du tout" — a hardcoded always-positive
#    rotation, blind to shooter side or target position.
# 2) A fix chasing the target's LIVE position every frame landed hits, but
#    "les boomerangs ne doivent pas etre teleguides !" — read as homing.
# 3) Final design: "plutot que 'vers le haut'/'vers le bas', une trajectoire
#    unique: ca part sur un angle a 30 deg et revient sur -30 deg. Par
#    defaut ca part du haut (30 -> -30). Si je descends, ca part du bas
#    (-30 -> 30). Si je monte, ca part du haut (30 -> -30)." — a fixed,
#    deterministic banana arc between +/-BOOMERANG_ARC_ANGLE_DEG, linearly
#    swept over the whole outbound leg. No target reference at all anymore
#    (can't be "guided" by definition) — only the shooter's own vertical
#    movement at throw time (boomerang_descending_throw) picks which end it
#    starts from. See _ready() (captures _boomerang_base_velocity/start/end)
#    and _update_boomerang() (does the actual lerp).
const BOOMERANG_ARC_ANGLE_DEG := 30.0
var boomerang_descending_throw: bool = false # set by MatchArenaNode._spawn_projectile() from the shooter's last movement direction
var _boomerang_base_velocity := Vector2.ZERO # the straight-line velocity captured at spawn, before any arc is applied — the arc always rotates around this baseline, never accumulates
var _boomerang_start_deg := BOOMERANG_ARC_ANGLE_DEG
var _boomerang_end_deg := -BOOMERANG_ARC_ANGLE_DEG
var boomerang_out_duration: float = 0.45 # seconds before it curves back — a var (not const) so charged_boomerang_out_duration (Perturbateur, 2026-08-09: "plus on charge, plus le boomerang va loin, jusqu'au fond du camp adverse") can send it much further out on a charged release
const BOOMERANG_RETURN_TURN_RATE := 260.0 # degrees/sec — how fast it re-aims at the shooter on the way back (the RETURN leg still homes onto the shooter's live position — that's "catching your own throw", never complained about, and unrelated to tracking the opponent)
const BOOMERANG_CATCH_DISTANCE := 24.0 # despawns once this close to the shooter on the return leg
# 2026-08-11, Camil: "les boomerangs, a leur retour, ne doivent pas
# forcement revenir sur le joueur qui les a lance. Si le joueur bouge trop
# vite et 'evite' son propre boomerang, alors celui-ci continue sa
# trajectoire et part dans le fond du joueur." — the return leg used to home
# on the shooter's live position FOREVER (bounded turn rate, but no give-up
# condition), so a shooter who kept dodging could get chased indefinitely.
# Track the closest approach; once distance starts growing again by more
# than BOOMERANG_MISS_MARGIN without ever reaching catch distance, the
# shooter dodged it — stop turning and let it coast in a straight line
# (which, by construction, is already heading roughly toward the shooter's
# own back wall, since it just overshot them on the way back).
const BOOMERANG_MISS_MARGIN := 15.0
# Right at the outbound->return transition, velocity is still pointed
# wherever the outbound arc left it — essentially arbitrary relative to the
# shooter — so distance-to-shooter can grow for the first frame or two
# simply because the turn hasn't caught up yet, well before any real dodge
# happened. Only "arm" miss-detection once it's actually closed to within
# this range at least once, so a genuine close pass (not just the turn
# warming up) is what triggers giving up.
const BOOMERANG_MISS_ENGAGE_DISTANCE := 100.0
var _boomerang_return_closest_dist := INF
var _boomerang_missed_catch := false
var _boomerang_timer := 0.0
var _boomerang_returning := false
var _boomerang_hit_outbound := false
var _boomerang_hit_return := false

var textures: Array = [] # of Texture2D — 1 = static sprite; 2+ = simple flicker/pulse animation
var flip_h := false # sprites face right by default; flipped for shots travelling left
var visual_scale := 1.0 # engine-side size bump, independent of the source art (2026-08-02 feedback)
var fallback_color: Color = Color.WHITE # used only when no textures are assigned (no art yet for a weapon)
var tint: Color = Color.WHITE # Epic 2 — modulate on top of a reused texture, so weapons sharing placeholder art stay visually distinct

# 2026-08-11, Camil (after seeing the hitbox overlay on a charged giant
# boomerang): "avec la hit box on voit bien que celle des projectiles ne
# font pas la taille du sprite" — hit resolution used to test the
# projectile's exact center POINT against the target's rect, completely
# ignoring how big the sprite was actually drawn (a 5x-scaled giant
# boomerang had the exact same hit precision as a base machine-gun bullet).
# Computed once in _ready() from the actual rendered footprint (texture
# size * visual_scale, or the small fallback square's size when no art is
# assigned yet), then used to inflate the swept hit-test — see
# _physics_process()'s ship/turret checks below, and confirmed against the
# generic case, not just boomerangs ("il faut le faire sur tous les
# projectiles bien sur").
var hit_half_size := Vector2(4.0, 4.0) # matches the fallback square's size by default

func _update_hit_half_size() -> void:
	if textures.is_empty():
		return # keep the (4,4) fallback default — matches the fallback Polygon2D drawn in _ready()
	var texture: Texture2D = textures[0]
	if texture:
		hit_half_size = texture.get_size() * visual_scale * 0.5

var _sprite: Sprite2D
var _anim_timer := 0.0
var _anim_index := 0
const ANIM_FRAME_DURATION := 0.1

func _ready() -> void:
	if is_looping or is_sine:
		_drift_velocity = velocity
		
	if is_boomerang:
		# Captured once here — the arc always rotates around this baseline,
		# never accumulates frame to frame (see the field's comment above).
		_boomerang_base_velocity = velocity
		# Godot's Vector2.rotated() is clockwise-positive (y grows downward),
		# so a POSITIVE angle on a rightward vector points DOWN, not up —
		# the reverse of the everyday "30deg = tilted up" reading. Swap here
		# so the field names stay true to Camil's wording ("par defaut ca
		# part du haut") rather than to Godot's rotation sign convention.
		if boomerang_descending_throw:
			_boomerang_start_deg = BOOMERANG_ARC_ANGLE_DEG # starts DOWN
			_boomerang_end_deg = -BOOMERANG_ARC_ANGLE_DEG # ends UP
		else:
			_boomerang_start_deg = -BOOMERANG_ARC_ANGLE_DEG # starts UP
			_boomerang_end_deg = BOOMERANG_ARC_ANGLE_DEG # ends DOWN
	_update_hit_half_size()
	if textures.is_empty():
		# Epic 2 weapons without dedicated art yet (e.g. turret shots) still
		# need to be visible — a small colored square beats an invisible hit.
		var fallback := Polygon2D.new()
		fallback.polygon = PackedVector2Array([
			Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4),
		])
		fallback.color = fallback_color
		add_child(fallback)
		return
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # keep pixel art crisp
	_sprite.flip_h = flip_h
	_sprite.scale = Vector2(visual_scale, visual_scale)
	_sprite.modulate = tint
	add_child(_sprite)
	_update_sprite_texture()

var position_before: Vector2 = Vector2.ZERO # last frame's pre-move position; exposed so TurretNode's swept hit-check (see turret_node.gd) always brackets a real, freshly-moved segment instead of racing physics-process order

func _physics_process(delta: float) -> void:
	position_before = position
	if is_boomerang:
		_update_boomerang(delta)
	elif is_looping:
		_loop_elapsed += delta
		var loop_angle := deg_to_rad(loop_angular_speed) * _loop_elapsed
		var tangential_speed := loop_radius * deg_to_rad(loop_angular_speed) # |d/dt of R*(cos,sin)(w*t)| = R*w
		velocity = _drift_velocity + Vector2(-sin(loop_angle), cos(loop_angle)) * tangential_speed
	elif is_sine:
		_sine_elapsed += delta
		var wave_angle := deg_to_rad(sine_angular_speed) * _sine_elapsed
		var perp_dir := _drift_velocity.normalized().orthogonal()
		var lateral_speed := sine_amplitude * deg_to_rad(sine_angular_speed) * cos(wave_angle) # d/dt of amplitude*sin(w*t) = amplitude*w*cos(w*t)
		velocity = _drift_velocity + perp_dir * lateral_speed
	elif target and homing_strength > 0.0 and homing_full_turn:
		# True 2D pursuit (Traqueur's La Meute only, see the field comment
		# above) — the FULL velocity vector rotates toward the target at up
		# to `homing_strength` rad/s, speed preserved, so a target that
		# ends up behind the missile genuinely pulls it into a U-turn
		# instead of just tracking its height. flip_h follows the sign of
		# the resulting horizontal speed every frame (not just once at
		# spawn) so the sprite's nose always faces the actual direction of
		# travel, mirroring mid-flight exactly when a turn crosses 90deg.
		var speed := velocity.length()
		if speed > 0.01:
			var current_dir := velocity / speed
			var desired_dir := (target.position - position).normalized()
			var max_turn := homing_strength * delta
			var turn := clampf(current_dir.angle_to(desired_dir), -max_turn, max_turn)
			velocity = current_dir.rotated(turn) * speed
			if _sprite:
				_sprite.flip_h = velocity.x < 0.0
	elif target and homing_strength > 0.0:
		# Original behavior (base homing_missile, and anything else that
		# doesn't opt into homing_full_turn): only steer vertically —
		# horizontal (left/right) speed stays constant, so it can never
		# actually turn around.
		var desired_vy := clampf((target.position.y - position.y) * 2.0, -260.0, 260.0)
		velocity.y = lerpf(velocity.y, desired_vy, clampf(homing_strength * delta, 0.0, 1.0))
	elif acceleration != 0.0 and velocity.length() > 0.01:
		velocity += velocity.normalized() * acceleration * delta

	position += velocity * delta
	lifetime -= delta
	if spin_speed != 0.0:
		rotation += deg_to_rad(spin_speed) * delta

	if leaves_fire_trail and get_parent():
		_fire_trail_timer -= delta
		if _fire_trail_timer <= 0.0:
			_fire_trail_timer = FIRE_TRAIL_DROP_INTERVAL
			var puddle := FireTrailNode.new()
			puddle.position = position
			puddle.victim = target
			get_parent().add_child(puddle)

	# 2026-08-10 bug report: "j'ai l'impression que tous les tirs ne touchent
	# pas les tourelles de controleur" — same tunneling class as the vortex
	# bug above, but TurretNode used to poll for this itself with a point-only
	# check on the projectile's post-move position (see git history), AND
	# that poll ran in the turret's own _physics_process — whichever frame
	# order the two nodes happened to run in, the turret could easily be
	# checking a projectile that hadn't moved yet THIS frame, collapsing the
	# segment to a single (stale) point and reintroducing the exact same
	# skip-over. Doing the sweep here instead guarantees position_before/
	# position always bracket THIS frame's real movement.
	if target and get_parent(): # get_parent() is null in tests that drive _physics_process() directly without adding the projectile to a tree
		for child in get_parent().get_children():
			if not (child is TurretNode):
				continue
			var turret: TurretNode = child
			if turret.owner_side != target.side:
				continue # this turret guards MY side, not the target's — not in the way
			# Inflated by hit_half_size (Minkowski sum) — a swept ROUGH-RECT vs
			# RECT test reduces to a swept POINT vs (RECT grown by the moving
			# rect's own half-size) test, so a big sprite (e.g. the 5x charged
			# boomerang) actually hits as easily as it visually looks like it should.
			var turret_rect := Rect2(turret.position - turret.half_extents - hit_half_size, turret.half_extents * 2.0 + hit_half_size * 2.0)
			if _segment_crosses_rect(position_before, position, turret_rect):
				turret.take_damage(damage)
				queue_free()
				return

	if target:
		# Inflated by hit_half_size (2026-08-11: "avec la hit box on voit bien
		# que celle des projectiles ne font pas la taille du sprite") — see
		# the turret check above for the Minkowski-sum reasoning, identical here.
		var target_rect := Rect2(target.position - target.half_extents - hit_half_size, target.half_extents * 2.0 + hit_half_size * 2.0)
		# 2026-08-09 bug report: "il y a plein de cas ou les tourbillons de
		# Vif ne touchent pas... l'animation va tellement vite qu'on saute
		# des frames" — a point check on the post-move position only, with
		# no idea where the projectile WAS a moment ago, tunnels straight
		# through the ship's ~28px-wide hitbox whenever a single frame's
		# movement (loop tangential speed + drift, can exceed 30-40px/frame)
		# is wider than the target. Sweep the whole frame's travel instead.
		if _segment_crosses_rect(position_before, position, target_rect):
			if is_boomerang:
				# Can land once per leg (out/back) instead of despawning on contact.
				if _boomerang_returning and not _boomerang_hit_return:
					_boomerang_hit_return = true
					_apply_hit_effect()
				elif not _boomerang_returning and not _boomerang_hit_outbound:
					_boomerang_hit_outbound = true
					_apply_hit_effect()
			else:
				_apply_hit_effect()
				queue_free()
				return

	if lifetime <= 0.0:
		if expiry_explosion_radius > 0.0:
			_explode_on_expiry()
		queue_free()
		return

	if textures.size() > 1:
		_anim_timer += delta
		if _anim_timer >= ANIM_FRAME_DURATION:
			_anim_timer = 0.0
			_anim_index = (_anim_index + 1) % textures.size()
			_update_sprite_texture()

	queue_redraw() # cheap even when DebugOverlay.show_hitboxes is false — _draw() below just no-ops

## Cheap swept collision check (2026-08-09 tunneling fix): samples the whole
## from->to travel segment at a fixed step size rather than only testing the
## single post-move position, so a fast (or fast-looping) projectile can't
## skip clean over a target rect narrower than one frame's movement.
func _segment_crosses_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(to):
		return true
	var travel := to - from
	var dist := travel.length()
	if dist < 0.01:
		return rect.has_point(from)
	const SAMPLE_STEP := 8.0 # px — comfortably smaller than the ship hitbox's ~28px width
	var steps := int(ceil(dist / SAMPLE_STEP))
	for i in steps:
		var t := float(i) / float(steps)
		if rect.has_point(from.lerp(to, t)):
			return true
	return false

func _update_sprite_texture() -> void:
	if textures.size() > 0 and _sprite:
		_sprite.texture = textures[_anim_index]

## 2026-08-11, Camil: "les hitbox doivent etre sur les projectiles aussi.
## tous !" (follow-up to the ship/turret hitbox overlay, 2026-08-10) — draws
## hit_half_size, the REAL rect now used to inflate the swept hit-test (see
## _physics_process() above), not an arbitrary marker — what's drawn here is
## provably what determines a hit, same guarantee as ShipNode/TurretNode's
## outlines. Same red outline style for visual consistency. Looked up via
## get_node_or_null("/root/DebugOverlay") rather than a direct reference —
## same "must never break outside a scene/autoload context" constraint as
## ShipNode._draw(), and smoke_test.gd constructs ProjectileNode instances
## directly in several places.
func _draw() -> void:
	var debug := get_node_or_null("/root/DebugOverlay")
	if debug and debug.show_hitboxes:
		draw_rect(Rect2(-hit_half_size, hit_half_size * 2.0), Color(1.0, 0.15, 0.15, 0.9), false, 3.0)

func _apply_hit_effect() -> void:
	if effect_type == "stun":
		target.apply_stun(effect_duration)
		# 2026-08-10: a "stun" hit used to ignore `damage` entirely, so
		# Perturbateur's "tir charge: 5x degats" request had nothing to
		# actually multiply — the field was inert against ships (only ever
		# read against turrets, see the swept turret-hit check above). Chip
		# real HP on top of the stun whenever damage is set, so a charged
		# giant boomerang's 5x damage multiplier is felt, not just seen.
		if damage > 0:
			target.apply_damage(damage)
	else:
		target.apply_damage(damage)

const EXPIRY_EXPLOSION_PARTICLE_COUNT := 14
const EXPIRY_EXPLOSION_LIFETIME := 0.3

## 2026-08-16 (Traqueur's La Meute): a missile that times out without ever
## landing a hit still goes out with a small area-damage puff instead of
## just vanishing. Same CPUParticles2D-burst recipe as MissileStrikeNode's
## impact explosion (see that file), independently duplicated rather than
## shared — this project's other placeholder VFX (BlackHoleNode's swirl,
## MissileStrikeNode's burst) each own their particle setup rather than
## going through a shared helper, so this follows the same pattern.
## Parented to get_parent(), not self: self calls queue_free() right after
## this returns, which would free the burst mid-animation if it were a
## child of self.
func _explode_on_expiry() -> void:
	if is_instance_valid(target) and target.position.distance_to(position) < expiry_explosion_radius:
		target.apply_damage(expiry_explosion_damage)
	if not get_parent():
		return # tests that drive _physics_process() directly without adding this to a tree
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var particles := CPUParticles2D.new()
	particles.texture = ImageTexture.create_from_image(img)
	particles.position = position
	particles.amount = EXPIRY_EXPLOSION_PARTICLE_COUNT
	particles.lifetime = EXPIRY_EXPLOSION_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0 # full radial burst, not a directional cone
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 110.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.55, 0.15, 1.0))
	gradient.set_color(1, Color(0.4, 0.1, 0.05, 0.0))
	particles.color_ramp = gradient
	get_parent().add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

## Outbound leg: a FIXED, deterministic banana arc — velocity is recomputed
## every frame straight from _boomerang_base_velocity (captured at spawn)
## rotated by an angle linearly swept from _boomerang_start_deg to
## _boomerang_end_deg over boomerang_out_duration. No reference to `target`
## at all (see the field block's history above) — not homing by
## construction, just a real toss with a predictable, learnable shape.
## Return leg: re-aims at the shooter's current (live) position each frame,
## homing-style, then despawns once close enough to be "caught" — that part
## is unaffected: "catching your own throw" was never the complaint.
func _update_boomerang(delta: float) -> void:
	_boomerang_timer += delta
	if not _boomerang_returning:
		var t := clampf(_boomerang_timer / boomerang_out_duration, 0.0, 1.0)
		var current_deg := lerpf(_boomerang_start_deg, _boomerang_end_deg, t)
		velocity = _boomerang_base_velocity.rotated(deg_to_rad(current_deg))
		if _boomerang_timer >= boomerang_out_duration:
			_boomerang_returning = true
	elif is_instance_valid(shooter):
		var current_dist := position.distance_to(shooter.position)
		if current_dist < BOOMERANG_CATCH_DISTANCE:
			queue_free() # caught, regardless of _boomerang_missed_catch — see its comment: a lucky drift back into range still counts
			return
		if not _boomerang_missed_catch:
			if current_dist < _boomerang_return_closest_dist:
				_boomerang_return_closest_dist = current_dist
			elif _boomerang_return_closest_dist <= BOOMERANG_MISS_ENGAGE_DISTANCE and current_dist > _boomerang_return_closest_dist + BOOMERANG_MISS_MARGIN:
				_boomerang_missed_catch = true # dodged — give up homing, coast straight from here (see the field's comment)
			if not _boomerang_missed_catch:
				# Rotate toward the shooter by a clamped angular step rather than
				# lerping the velocity vector directly — lerping two same-length
				# vectors pointing in different directions shortens the result
				# (chord vs. arc), which bled off speed each frame and could leave
				# it crawling back too slowly to ever reach BOOMERANG_CATCH_DISTANCE.
				var to_shooter := shooter.position - position
				if to_shooter.length() > 1.0:
					var angle_diff := wrapf(to_shooter.angle() - velocity.angle(), -PI, PI)
					var max_turn := deg_to_rad(BOOMERANG_RETURN_TURN_RATE) * delta
					velocity = velocity.rotated(clampf(angle_diff, -max_turn, max_turn))
		# else: _boomerang_missed_catch — velocity is left untouched, so it
		# just keeps coasting in whatever direction it was last heading.
	else:
		queue_free() # shooter gone (round reset mid-flight) — nothing to return to
