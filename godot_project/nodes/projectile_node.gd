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
var damage: int = 0
var target: ShipNode = null
var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (bazooka only)
var effect_type: String = "damage" # Epic 2 — "damage" (default) or "stun"
var effect_duration: float = 0.0 # Epic 2 — stun length applied on hit when effect_type == "stun"
var spin_speed: float = 0.0 # deg/sec — rotates the whole node; unused by the Tourbillon (its 3-frame texture cycle already reads as spinning) but left generic for any future weapon that wants it

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
var _drift_velocity := Vector2.ZERO # the straight-line velocity captured at spawn; the loop orbits this drifting reference

# "Shmup juice pass" (2026-08-05) — boomerang motion: curves outward for
# BOOMERANG_OUT_DURATION, then arcs back toward `shooter`. Mutually exclusive
# with homing_strength (boomerang weapons don't set it). Unlike a normal
# projectile it does NOT despawn on hit, so it can land once on the way out
# and once on the way back — each guarded separately below.
var is_boomerang := false
var shooter: ShipNode = null
const BOOMERANG_CURVE_RATE := 70.0 # degrees/sec — bends the outbound path into a gentle arc. Was 160 (2026-08-05 playtest: "part vers le bas" — over 0.45s that swung ~72°, nearly a right angle off "straight at the opponent"; 70°/s only swings ~31°, so it still clearly travels forward first.
const BOOMERANG_OUT_DURATION := 0.45 # seconds before it curves back
const BOOMERANG_RETURN_TURN_RATE := 260.0 # degrees/sec — how fast it re-aims at the shooter on the way back
const BOOMERANG_CATCH_DISTANCE := 24.0 # despawns once this close to the shooter on the return leg
var _boomerang_timer := 0.0
var _boomerang_returning := false
var _boomerang_hit_outbound := false
var _boomerang_hit_return := false

var textures: Array = [] # of Texture2D — 1 = static sprite; 2+ = simple flicker/pulse animation
var flip_h := false # sprites face right by default; flipped for shots travelling left
var visual_scale := 1.0 # engine-side size bump, independent of the source art (2026-08-02 feedback)
var fallback_color: Color = Color.WHITE # used only when no textures are assigned (no art yet for a weapon)
var tint: Color = Color.WHITE # Epic 2 — modulate on top of a reused texture, so weapons sharing placeholder art stay visually distinct

var _sprite: Sprite2D
var _anim_timer := 0.0
var _anim_index := 0
const ANIM_FRAME_DURATION := 0.1

func _ready() -> void:
	if is_looping:
		_drift_velocity = velocity
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
	elif target and homing_strength > 0.0:
		# Only steer vertically — horizontal (left/right) speed stays constant.
		var desired_vy := clampf((target.position.y - position.y) * 2.0, -260.0, 260.0)
		velocity.y = lerpf(velocity.y, desired_vy, clampf(homing_strength * delta, 0.0, 1.0))

	position += velocity * delta
	lifetime -= delta
	if spin_speed != 0.0:
		rotation += deg_to_rad(spin_speed) * delta

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
			var turret_rect := Rect2(turret.position - TurretNode.HALF_EXTENTS, TurretNode.HALF_EXTENTS * 2.0)
			if _segment_crosses_rect(position_before, position, turret_rect):
				turret.take_damage(damage)
				queue_free()
				return

	if target:
		var target_rect := Rect2(target.position - target.half_extents, target.half_extents * 2.0)
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
		queue_free()

	if textures.size() > 1:
		_anim_timer += delta
		if _anim_timer >= ANIM_FRAME_DURATION:
			_anim_timer = 0.0
			_anim_index = (_anim_index + 1) % textures.size()
			_update_sprite_texture()

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

func _apply_hit_effect() -> void:
	if effect_type == "stun":
		target.apply_stun(effect_duration)
	else:
		target.apply_damage(damage)

## Outbound leg: arcs via a constant angular curve. Return leg: re-aims at
## the shooter's current (live) position each frame, homing-style, then
## despawns once close enough to be "caught".
func _update_boomerang(delta: float) -> void:
	_boomerang_timer += delta
	if not _boomerang_returning:
		velocity = velocity.rotated(deg_to_rad(BOOMERANG_CURVE_RATE * delta))
		if _boomerang_timer >= BOOMERANG_OUT_DURATION:
			_boomerang_returning = true
	elif is_instance_valid(shooter):
		var to_shooter := shooter.position - position
		if to_shooter.length() > 1.0:
			# Rotate toward the shooter by a clamped angular step rather than
			# lerping the velocity vector directly — lerping two same-length
			# vectors pointing in different directions shortens the result
			# (chord vs. arc), which bled off speed each frame and could leave
			# it crawling back too slowly to ever reach BOOMERANG_CATCH_DISTANCE.
			var angle_diff := wrapf(to_shooter.angle() - velocity.angle(), -PI, PI)
			var max_turn := deg_to_rad(BOOMERANG_RETURN_TURN_RATE) * delta
			velocity = velocity.rotated(clampf(angle_diff, -max_turn, max_turn))
		if position.distance_to(shooter.position) < BOOMERANG_CATCH_DISTANCE:
			queue_free()
	else:
		queue_free() # shooter gone (round reset mid-flight) — nothing to return to
