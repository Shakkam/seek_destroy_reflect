class_name BallNode
extends Node2D

## Thin Godot node: detects contact with ships/walls and calls into
## simulation/ball_state.gd for all trajectory logic. Never contains
## simulation rules itself (see project-context.md, Regle absolue n1).

var state: BallState
var arena_bounds: Rect2
var frontier_x: float
var ships: Array[ShipNode] = []
var active := true # set false by MatchArenaNode during the pre-match "ready?" gate

# Breakout mini-jeu (2026-08-18) — see _resolve_walls()/BallState.
# bounced_off_side_wall(). False (default) everywhere else — a real
# match's own far side is a scoring/miss zone, not a wall.
var bounces_off_right_wall := false

# Breakout mini-jeu (2026-08-18, Camil: "dans ce mode (uniquement) il
# faudrait que la balle commence a une vitesse un peu moindre... disons
# 70%") — scales every launch (_ready() AND every reset_to_center() after
# a miss) via _spawn_velocity(). 1.0 (default) everywhere else — a real
# match keeps its normal BASE_SPEED start.
var initial_speed_multiplier := 1.0

# Breakout mini-jeu (2026-08-18, Camil: "le taux d'acceleration de la
# balle au rebond doit etre moins fort dans ce mode de jeu uniquement")
# — applies to BOTH _resolve_ships()' paddle-return AND _resolve_turrets()'
# brick/enemy deflection, since Breakout bounces off bricks far more often
# per rally than a normal 2-ship exchange ever does. 1.0 (default)
# everywhere else — a real match keeps its normal per-return escalation.
var speed_increment_multiplier := 1.0

## 2026-08-15 (Camil): "il faut bien viser la prochaine case vide" — the
## gauge-fill effect's yellow ball needs to aim at the real next-empty
## ultra pip, not an approximate anchor. Set by MatchArenaNode alongside
## arena_bounds/ships.
var p1_ultra_meter: UltraMeterNode
var p2_ultra_meter: UltraMeterNode

# 2026-08-22 (Camil, VS/campaign match: "quand on perd la balle, quand
# elle reapparait, faudrait qu'elle reste immobile pendant 1 seconde
# histoire qu'on ait le temps de se replacer") — opt-in via
# reset_to_center()'s own freeze_on_respawn param, used only by the
# post-miss respawn in _resolve_out_of_bounds() (NOT Breakout's own
# reset_to_center() call, which already has its own separate 3-2-1
# countdown/freeze, and NOT a fresh round's ball placement, which is
# already gated behind the "Ready...Go!" ship/ball freeze).
const RESPAWN_FREEZE_DURATION := 1.0
var _respawn_freeze_timer := 0.0
var _pending_launch_velocity := Vector2.ZERO

var _return_cooldown := 0.0 # avoids re-triggering a return within the same frame(s)
var _last_half := -1 # -1 = unset, 0 = left half, 1 = right half — which side the ball currently occupies
var _blocked_side := -1 # side that already touched the ball during its current visit to a half; -1 = none

# Lourd's "heavy_push" rule (2026-08-09, Camil: "il faudrait donc que ca
# 'pousse' la balle et que cette derniere pousse le joueur adverse") — armed
# by a fully-charged (100%) lift return from a heavy_push character, consumed
# (knocks the ship back, then clears) the next time ANY ship's rect is hit —
# normally the opponent reaching for it, whether they successfully return it
# or not. Cleared on a fresh rally (reset_to_center()) so a stale arm from a
# ball that went out of bounds untouched can never carry into the next point.
var _push_pending := false
const HEAVY_PUSH_DISTANCE := 40.0 # px, instantaneous shove on contact

# Bugfix 2026-08-01 (v4): a ship parked at the frontier could trigger an
# instant "return" the moment the ball (re)spawns at center (ball appears to
# shoot backward immediately). Fixed with a "net" — a neutral zone straddling
# the frontier where ship collision never resolves, regardless of timers or
# how the ball got there. The ball always spawns from inside this zone.
# Since Story "neutral zone as a real movement wall" (2026-08-01), ships can
# no longer physically enter this band either — see ShipState.NEUTRAL_ZONE_HALF_WIDTH,
# the single source of truth both this check and the ship clamp read from.

const SPAWN_TILT_MAX_RAD := 0.35 # ~20 degrees either side of horizontal

# Placeholder sprite (2026-08-02, v2) — single static sprite, actually
# rotated in-engine instead of cycling 3 hand-drawn frames (the swap read as
# a janky/weird motion since those frames weren't a true rotation sequence).
const BALL_TEXTURE := preload("res://assets/art/vfx/ball_1.png")
const ROTATION_SPEED := 6.0 # rad/s
const BALL_SPRITE_SCALE := Vector2(1.4, 1.4) # engine-side bump — art reads small at native size (2026-08-02 feedback)
var _sprite: Sprite2D

# 2026-08-22 (Camil, on the new 1s respawn freeze: "c'est tres bien, mais il
# faudrait une petite anime. genre elle part de tout petit (20% de sa
# taille) et grossit en tournant, pendant 1s, pour arriver a sa taille
# normale de 100%") — purely cosmetic, read alongside RESPAWN_FREEZE_DURATION
# in _physics_process()'s freeze branch.
# 2026-08-22 follow-up, live playtest ("c'est bien la balle mais du coup on
# ne la voit pas arriver. je propose l'inverse : elle pope a 200% et
# retrecit a 100%") — starting tiny made it hard to spot appearing; popping
# in oversized and shrinking down reads much clearer. Same lerp, just a
# different starting scale.
const RESPAWN_POP_START_SCALE := 2.0

## 2026-08-15 bug report (Camil): "la balle spawn toujours en partant vers
## la droite... il faudrait qu'elle parte à gauche ou à droite au hasard,
## ensuite qu'elle parte vers le joueur qui l'a perdue." target_side picks
## which half the ball heads toward (0 = left, 1 = right); -1 (default,
## used for the very first spawn of a match/round) picks one at random.
## A slight random tilt is kept either way so it doesn't always fire
## perfectly horizontal (which read as "the game isn't moving").
func _spawn_velocity(target_side: int = -1) -> Vector2:
	var side := target_side if target_side != -1 else (0 if randf() < 0.5 else 1)
	var sign := -1.0 if side == 0 else 1.0
	return Vector2(BallState.BASE_SPEED * initial_speed_multiplier * sign, 0.0).rotated(randf_range(-SPAWN_TILT_MAX_RAD, SPAWN_TILT_MAX_RAD))

func _in_neutral_zone() -> bool:
	return absf(state.position.x - frontier_x) < ShipState.NEUTRAL_ZONE_HALF_WIDTH

func _ready() -> void:
	state = BallState.new(position, _spawn_velocity())
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = BALL_TEXTURE
	_sprite.scale = BALL_SPRITE_SCALE
	add_child(_sprite)

func _physics_process(delta: float) -> void:
	if not active:
		return

	if _respawn_freeze_timer > 0.0:
		_respawn_freeze_timer -= delta
		# Position/collision stay fully immobile — no movement/wall/ship/
		# turret resolution — but the sprite itself still pops in oversized
		# and shrinks-while-spinning down to full size, so the freeze
		# doesn't just look frozen on-screen with nothing happening
		# ("il faudrait une petite anime").
		var t := 1.0 - clampf(_respawn_freeze_timer / RESPAWN_FREEZE_DURATION, 0.0, 1.0)
		if _sprite:
			_sprite.scale = BALL_SPRITE_SCALE * lerpf(RESPAWN_POP_START_SCALE, 1.0, t)
			_sprite.rotation += ROTATION_SPEED * delta
		if _respawn_freeze_timer <= 0.0:
			state = BallState.new(state.position, _pending_launch_velocity)
			if _sprite:
				_sprite.scale = BALL_SPRITE_SCALE # land exactly on full size, no float-lerp shortfall
		return

	_return_cooldown = maxf(_return_cooldown - delta, 0.0)

	state = state.update(delta)
	_resolve_walls()
	_resolve_half_crossing()

	if not _in_neutral_zone():
		_resolve_ships()
		_resolve_turrets()

	_resolve_out_of_bounds()

	position = state.position
	_sprite.rotation += ROTATION_SPEED * delta

## A ship can only return the ball once per visit to its own half — once
## the ball crosses back to the other half, the block clears. Prevents the
## "stuck" bug where chasing the ball re-triggers the return repeatedly.
func _resolve_half_crossing() -> void:
	var current_half := 0 if state.position.x < frontier_x else 1
	if current_half != _last_half:
		_blocked_side = -1
		_last_half = current_half

## Story 1.6 — a missed ball fills the opponent's gauge (never direct damage),
## then respawns at center so play can continue.
## 2026-08-18 (Breakout mini-jeu) — a solo BreakoutNode only ever populates
## `ships` with a single side-0 player (no side-1 ship to receive the
## normal miss-reward loop below), so it needs its own way to know "the
## player just missed" to dock HP. Emitted for every miss regardless of
## `ships` contents — harmless/unlistened-to in the normal 2-ship game.
signal ball_missed(side: int)

func _resolve_out_of_bounds() -> void:
	var missed_side := -1
	if state.position.x < arena_bounds.position.x - BallState.RADIUS * 4.0:
		missed_side = 0
	elif state.position.x > arena_bounds.position.x + arena_bounds.size.x + BallState.RADIUS * 4.0:
		missed_side = 1

	if missed_side != -1:
		ball_missed.emit(missed_side)
		var opponent_side := 1 if missed_side == 0 else 0
		for ship in ships:
			if ship.side == opponent_side:
				# 2026-08-15 (Camil): "une petite boule va de l'endroit ou
				# la balle a ete perdue jusqu'a la jauge... et c'est en
				# 'touchant' le joueur que le '+50' apparait" — the gauge
				# still fills immediately (fair/correct for gameplay), but
				# _silently: the usual instant "+50" popup is suppressed in
				# favor of GaugeFillEffectNode's own, fired once its travel
				# animation actually reaches the ship. Captured BEFORE
				# add_ultra_pip() — the effect needs to know which pip was
				# still empty at the moment of the miss ("il faut bien
				# viser la prochaine case vide").
				var pips_before := ship.weapon_state.ultra_pips
				ship.fill_selected_gauge_silently(WeaponSystemState.MISS_GAUGE_FILL)
				ship.add_ultra_pip() # "systeme des 5 balles" — same trigger as the weapon-gauge miss fill
				_spawn_gauge_fill_effect(ship, WeaponSystemState.MISS_GAUGE_FILL, pips_before)
				break

		reset_to_center(missed_side, true) # serve toward whoever just missed it, not always the same fixed direction; freeze_on_respawn=true gives both players a beat to reposition

func _spawn_gauge_fill_effect(ship: ShipNode, amount: float, pips_before: int) -> void:
	if not get_parent():
		return
	var effect := GaugeFillEffectNode.new()
	effect.loss_position = state.position
	effect.target_ship = ship
	effect.fill_amount = amount

	# 2026-08-15 (Camil): "attention a bien viser la prochaine case vide.
	# Si les 5 cases sont remplies, on n'envoie pas de boule jaune." — the
	# yellow ball's destination is the actual next-empty ULTRA PIP square
	# (not a rough anchor), and it's skipped entirely once the meter was
	# already full before this miss (nowhere empty left to aim at).
	var meter: UltraMeterNode = p1_ultra_meter if ship.side == 0 else p2_ultra_meter
	if meter and pips_before < meter.max_pips:
		effect.send_gauge_ball = true
		effect.gauge_anchor = meter.global_position + Vector2(
			pips_before * (meter.pip_size + meter.spacing) + meter.pip_size / 2.0,
			meter.pip_size / 2.0
		)
	else:
		effect.send_gauge_ball = false
	get_parent().add_child(effect)

const SPAWN_Y_MARGIN := 100.0 # keeps the random spawn Y away from the top/bottom walls

## Frontier X (always), random Y within a safe margin of the arena — so the
## ball doesn't always reappear at the exact same spot, and doesn't reliably
## line up with wherever a ship happens to be resting (2026-08-01 feedback).
func _random_spawn_position() -> Vector2:
	var min_y := arena_bounds.position.y + SPAWN_Y_MARGIN
	var max_y := arena_bounds.position.y + arena_bounds.size.y - SPAWN_Y_MARGIN
	return Vector2(frontier_x, randf_range(min_y, max_y))

## Story 1.9 — also used to re-center the ball at the start of a new round
## (target_side left at -1 there too — a fresh round has no "who just missed
## it" to aim toward, so it stays random same as the very first serve).
## `freeze_on_respawn` (2026-08-22, Camil: "quand on perd la balle, quand
## elle reapparait, faudrait qu'elle reste immobile pendant 1 seconde") —
## opt-in, used only by the post-miss respawn below; a fresh round's own
## placement leaves it false (already covered by the separate "Ready...Go!"
## ship/ball freeze in MatchArenaNode).
func reset_to_center(target_side: int = -1, freeze_on_respawn: bool = false) -> void:
	var launch_velocity := _spawn_velocity(target_side)
	if freeze_on_respawn:
		state = BallState.new(_random_spawn_position(), Vector2.ZERO)
		_pending_launch_velocity = launch_velocity
		_respawn_freeze_timer = RESPAWN_FREEZE_DURATION
		if _sprite:
			_sprite.scale = BALL_SPRITE_SCALE * RESPAWN_POP_START_SCALE # pops in oversized, shrinks back over the freeze (see _physics_process())
	else:
		state = BallState.new(_random_spawn_position(), launch_velocity)
		_respawn_freeze_timer = 0.0
	position = state.position
	_blocked_side = -1
	_last_half = -1
	_return_cooldown = 0.0
	_push_pending = false # a heavy_push ball that went out of bounds untouched must not carry into the next rally

func _resolve_walls() -> void:
	var min_y := arena_bounds.position.y + BallState.RADIUS
	var max_y := arena_bounds.position.y + arena_bounds.size.y - BallState.RADIUS
	if state.position.y < min_y or state.position.y > max_y:
		state = state.bounced_off_wall(clampf(state.position.y, min_y, max_y))

	# Breakout mini-jeu (2026-08-18) — the far side (past the bricks) is a
	# solid wall, not a scoring/miss zone like a real match's own far
	# side: runs BEFORE _resolve_out_of_bounds() so the ball bounces back
	# here well short of that function's own OOB threshold.
	if bounces_off_right_wall:
		var max_x := arena_bounds.position.x + arena_bounds.size.x - BallState.RADIUS
		if state.position.x > max_x:
			state = state.bounced_off_side_wall(max_x)

func _ship_rect(ship: ShipNode) -> Rect2:
	return Rect2(
		ship.position - ship.half_extents - Vector2(BallState.RADIUS, BallState.RADIUS),
		ship.half_extents * 2.0 + Vector2(BallState.RADIUS, BallState.RADIUS) * 2.0
	)

func _resolve_ships() -> void:
	if _return_cooldown > 0.0:
		return
	for ship in ships:
		if ship.side == _blocked_side:
			continue
		if _ship_rect(ship).has_point(state.position):
			# Lourd's "heavy_push" rule (2026-08-09) — an empowered ball (armed
			# by a previous 100%-charged lift return) shoves whichever ship it
			# reaches next, whether or not they go on to return it too.
			if _push_pending:
				ship.apply_knockback(Vector2(signf(state.velocity.x) * HEAVY_PUSH_DISTANCE, 0.0))
				_push_pending = false

			var outgoing_side := 1 if ship.side == 0 else -1
			var lift_charge := ship.get_lift_charge()
			state = state.returned(ship.get_aim_input(), lift_charge, outgoing_side, BallState.SPEED_INCREMENT_PER_RETURN * speed_increment_multiplier)
			_blocked_side = ship.side
			_return_cooldown = 0.15

			# Story 1.7 — fill scales with lift charge: 10 at 0% up to 15 at 100%.
			# Epic 4's "gauge_floor" twist can lock this self-fill specifically
			# (fill_selected_gauge_from_return), while Story 1.6's miss-fill
			# above always goes through the ungated fill_selected_gauge().
			var fill := lerpf(WeaponSystemState.RETURN_GAUGE_FILL, WeaponSystemState.RETURN_GAUGE_FILL_MAX_LIFT, lift_charge)
			ship.fill_selected_gauge_from_return(fill)

			# Arm the push for the NEXT contact if this return was itself a
			# fully-charged lift from a heavy_push character.
			_push_pending = ship.character != null and ship.character.special_rule == "heavy_push" and lift_charge >= 1.0
			return

## Turrets deflect the ball too (2026-08-09 playtest, Contrôleur: "vu qu'on
## parle d'un contrôleur, les tourelles pourraient renvoyer la balle aussi !
## ce serait genial"). No aim input and no lift charge — a stationary
## mirror-bounce (BallState.returned() with Vector2.ZERO aim falls back to
## reflecting the incoming angle), same _blocked_side/_return_cooldown
## gating as ships so a turret can't juggle the ball back and forth forever.
func _resolve_turrets() -> void:
	if _return_cooldown > 0.0:
		return
	for child in get_parent().get_children():
		if not (child is TurretNode):
			continue
		var turret: TurretNode = child
		if turret.owner_side == _blocked_side:
			continue
		if _turret_rect(turret).has_point(state.position):
			var outgoing_side := 1 if turret.owner_side == 0 else -1
			state = state.returned(Vector2.ZERO, 0.0, outgoing_side, BallState.SPEED_INCREMENT_PER_RETURN * speed_increment_multiplier)
			_blocked_side = turret.owner_side
			_return_cooldown = 0.15
			if turret.ball_bounce_damage > 0.0: # bricks only (Breakout) — see TurretNode.ball_bounce_damage
				turret.take_damage(turret.ball_bounce_damage)
			return

func _turret_rect(turret: TurretNode) -> Rect2:
	return Rect2(
		turret.position - turret.half_extents - Vector2(BallState.RADIUS, BallState.RADIUS),
		turret.half_extents * 2.0 + Vector2(BallState.RADIUS, BallState.RADIUS) * 2.0
	)
