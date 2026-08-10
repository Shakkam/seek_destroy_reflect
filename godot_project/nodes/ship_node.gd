class_name ShipNode
extends CharacterBody2D

## Thin Godot node: reads input, renders, and delegates all movement
## logic to simulation/ship_state.gd. Never contains simulation rules
## itself (see project-context.md, Regle absolue n1).

signal weapon_fired(weapon: WeaponData) # carries the full weapon so callers can branch on effect_type
signal charged_weapon_fired(weapon: WeaponData) # 2026-08-09 "tir charge" — released at full charge, MatchArenaNode spawns the weapon's bespoke charged burst instead of a normal shot
signal gauge_filled(amount: float)

@export var player_index: int = 1 # 1 or 2 — selects which local input scheme to read
@export var side: int = 0 # 0 = left half, 1 = right half
@export var half_extents: Vector2 = Vector2(14, 28) # matches the vertical "paddle" collision shape
@export var character: CharacterData # Epic 2 — if unset, falls back to the Epic 1 placeholder kit

var _mobility_boost_timer := 0.0
var _mobility_boost_multiplier := 1.0
var _mobility_boost_active_multiplier := 1.0 # the multiplier captured at the moment the boost fired
var _stun_timer := 0.0 # Epic 2, Story 2.6 — movement and firing disabled while > 0

# Mitrailleur's charged fire (2026-08-09) — "les 10 missiles suivants
# seront doubles (paralleles, separes de 10px verticalement)". Consumed one
# at a time by MatchArenaNode._on_weapon_fired() on each subsequent normal
# shot, not tracked here beyond the counter itself (the doubling/offset
# logic lives in match_arena_node.gd, same as every other projectile-
# spawning concern).
var _double_fire_shots_remaining := 0

# Turbo afterimage trail (2026-08-06) — was flagged as deferred polish, done
# now that the Turbo has a tint to match. Ghost copies of the ship's own
# Visual polygon, spawned periodically while boosted and faded out via Tween.
var _trail_timer := 0.0
const TRAIL_INTERVAL := 0.05
const TRAIL_LIFETIME := 0.25
const TRAIL_COLOR := Color(0.5, 1.0, 1.0, 0.35) # matches the Turbo tint, translucent

# Epic 4, Story 4.5 — "match twist" support (campaign rival/boss fights).
# self_fill_locked/passive_trickle_rate back the "gauge_floor" twist:
# Story 1.7's self-fill-on-return is skippable per-ship, while
# MISS_GAUGE_FILL (Story 1.6) is never touched — see fill_selected_gauge()
# vs fill_selected_gauge_from_return() below.
var self_fill_locked := false
var passive_trickle_rate := 0.0 # % of gauge_max per second, applied to the selected weapon only
var hidden_from_opponent := false # "invisible_opponent" twist — rendering only, simulation untouched

## Epic 4, Story 4.4 — mook fights use a reduced starting HP instead of a
## new AI system (RivalEncounterData.mook_hp_multiplier). Left at
## ShipState.START_HP for every non-campaign match.
var max_hp_override: float = ShipState.START_HP

var state: ShipState
var arena_bounds: Rect2
var frontier_x: float
var active := true # set false by MatchArenaNode during the pre-match "ready?" gate

var weapon_state: WeaponSystemState
var _weapon_select_prev := false
var _flash_timer := 0.0
const FLASH_DURATION := 0.08

var _vulnerability_timer := 0.0
const VULNERABILITY_DURATION := 0.7 # Story 1.8 — heavy weapons expose the shooter briefly (doubled 2026-08-01)
const VULNERABILITY_SPEED_MULTIPLIER := 0.35

# 2026-08-10, Camil: "le gros laser est TRES puissant... faudrait un petit
# nerf. Je pense reduire la vitesse a 60% le temps du gros laser, histoire
# que l'adversaire puisse un peu s'echapper" — Zoneur's own move speed drops
# while their charged beam is alive, so a slowed shooter can't keep tracking
# a dodging opponent. Armed by MatchArenaNode when it spawns the charged
# pulse (see _on_charged_weapon_fired()); multiplier comes from
# weapon.charged_beam_shooter_slow_multiplier so it stays data-driven.
var _charged_beam_slow_timer := 0.0
var _charged_beam_slow_multiplier := 1.0

func apply_charged_beam_slow(duration: float, multiplier: float) -> void:
	_charged_beam_slow_timer = duration
	_charged_beam_slow_multiplier = multiplier

const FIRE_HOLD_SPEED_MULTIPLIER := 0.5 # -50% while the fire button is held (2026-08-01 — "balance la sauce", was -40%)

# Lift/spin charge (redesigned 2026-08-01): holding the lift key freezes
# movement entirely and charges the lift over time, in tiers:
# <0.3s = 0%, 0.3-0.6s = 33%, 0.6-1.5s = 66%, >=1.5s = 100%.
# Only applies when character.special_rule != "dash_lift" — see the dash
# fields right below for Vif's replacement mechanic.
var _lift_charge_timer := 0.0
const LIFT_CHARGE_CAP := 1.5

# Vif's rewrite (2026-08-09, Camil): "il ne peut pas charger pour faire des
# lift. en revanche, le bouton 'lift' lui permet de faire un petit dash
# dans une direction choisie. s'il tape en dashant, ca fait un leger lift."
# The MINUS: get_lift_charge() always reads 0% outside a dash for this
# character — no hold-to-charge at all. The PLUS: tapping Lift fires a
# short, fast burst in the currently-held movement direction (or the last
# one held, or straight ahead if none) instead of freezing in place; a ball
# return connecting during that burst carries a small fixed lift charge.
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_direction := Vector2.ZERO
var _lift_prev := false # edge-detects the Lift press for dash characters (charge characters read it as a held state instead)
var _last_nonzero_move_dir := Vector2.ZERO

## Perturbateur's boomerang (2026-08-10): "par defaut ca part du haut (30 ->
## -30). Si je descends, ca part du bas (-30 -> 30). Si je monte, ca part du
## haut." — MatchArenaNode reads this at throw time to pick the arc's
## starting side; reuses the same tracked direction Vif's dash already does.
func get_last_move_direction() -> Vector2:
	return _last_nonzero_move_dir

const DASH_DURATION := 0.15 # seconds the burst itself lasts
const DASH_SPEED_MULTIPLIER := 3.0
const DASH_COOLDOWN := 0.5 # can't chain dashes back to back
const DASH_LIFT_CHARGE := 0.33 # "un leger lift" — fixed, since there's no charging to reach higher

# Charged fire (2026-08-09, per-weapon — see WeaponData.charge_fire_duration).
# Redesigned after playtesting the first version (Camil: "je laisse appuye,
# ca tire normalement. si au bout d'une seconde je suis toujours en appui,
# la charge commence") — holding fires NORMALLY for the first
# NORMAL_FIRE_GRACE seconds, exactly like any other weapon; only past that
# grace window does normal fire suspend and the charge gauge start building
# (with charge_fire_slow_multiplier kicking in). Releasing before
# charge_fire_duration is reached (but past the grace) wastes the charge
# attempt — releasing at/after it fires the empowered burst instead.
var _fire_held_duration := 0.0 # how long the CURRENT press has been held, resets to 0 the instant fire is released
const CHARGE_READY_BLINK_PERIOD := 0.15 # seconds per full on/off cycle once fully charged (2026-08-09 playtest: "pas mal le clignotement, tu peux le faire beaucoup plus rapide" — was 0.5)
const NORMAL_FIRE_GRACE := 1.0 # seconds of normal fire before a sustained hold starts charging
# 2026-08-09: a "release grace" (forgiving a brief fire_held dip so a charge
# attempt wouldn't lose its slow for one frame) was tried here and reverted
# — it caused a WORSE bug ("dès fois quand je relache pendant la charge, la
# charge continue"): releasing and quickly re-pressing within the grace
# window read as one unbroken hold, so the charge never actually reset. The
# real slow-down bug (see charge_fire_slow_multiplier below) had a
# different root cause entirely (a missing field on vortex.tres), so this
# workaround was never needed — release now always ends the attempt
# immediately, no forgiveness window.

# Full-auto vs. semi-auto (2026-08-09, Camil: "seul mitrailleur tire
# plusieurs fois d'affilee quand on laisse appuye... pour les autres, il
# faut appuyer plusieurs fois pour tirer plusieurs fois") — see
# CharacterData.full_auto. Edge-detected for everyone except Mitrailleur:
# normal fire (including a charge-capable weapon's grace window) only
# triggers on the rising edge of a press, not every frame it's held.
var _fire_prev := false

var _spawn_position: Vector2

# Story 1.12 — set by MatchArenaNode when this ship is AI-controlled.
var ai_controlled := false
var ball_ref: BallNode
var opponent_ref: ShipNode
var _ai_vertical_dir := 0.0 # persists between frames — hysteresis avoids jittery on/off "freeze"
const AI_LOOKAHEAD := 0.15 # seconds — anticipates where the ball is heading, not just where it is
const AI_DEADZONE_STOP := 4.0
const AI_DEADZONE_START := 14.0

var _ai_wander_timer := 0.0
var _ai_wander_target_y := 0.0
const AI_WANDER_INTERVAL_MIN := 1.2
const AI_WANDER_INTERVAL_MAX := 2.4

var _ai_weapon_switch_timer := randf_range(3.0, 6.0)
var _ai_pulse_select := false

var _ai_lift_timer := 0.0
var _ai_lift_decided := false

# Positional depth (2026-08-01 — was "glued to the net"): the AI now mostly
# holds a wandering mid/back position and only pushes up to the frontier
# when the ball has actually closed the distance to it specifically.
var _ai_depth_timer := 0.0
var _ai_preferred_depth := 0.35 # 0 = back wall, 1 = frontier — re-picked periodically
const AI_DEPTH_INTERVAL_MIN := 2.0
const AI_DEPTH_INTERVAL_MAX := 4.0
const AI_DEPTH_MIN := 0.1
const AI_DEPTH_MAX := 0.5
const AI_APPROACH_DISTANCE := 260.0
var _ai_horizontal_dir := 0.0
const AI_H_DEADZONE_STOP := 6.0
const AI_H_DEADZONE_START := 18.0

# Epic 2, Story 2.7 — per-archetype AI tuning, keyed by CharacterData.id.
# Reuses the exact heuristic framework above (wander/depth/lift/weapon-switch)
# with different parameters per character, rather than a parallel AI system.
# "signature_bias" = 0 keeps the legacy Epic 1 unconditional weapon-cycle
# behavior; >0 biases the AI toward staying on kit index 0 (the character's
# signature weapon), e.g. a Controleur AI mostly keeps its turret selected
# instead of cycling away from it right after placing one.
const AI_PROFILES := {
	"lourd": {"depth_min": 0.05, "depth_max": 0.25, "approach_distance": 200.0, "lift_chance": 0.15, "signature_bias": 0.85},
	"controleur": {"depth_min": 0.1, "depth_max": 0.3, "approach_distance": 200.0, "lift_chance": 0.2, "signature_bias": 0.85},
	"mitrailleur": {"depth_min": 0.2, "depth_max": 0.5, "approach_distance": 280.0, "lift_chance": 0.3, "signature_bias": 0.55},
	"vif": {"depth_min": 0.35, "depth_max": 0.65, "approach_distance": 340.0, "lift_chance": 0.45, "signature_bias": 0.7},
	"zoneur": {"depth_min": 0.3, "depth_max": 0.55, "approach_distance": 240.0, "lift_chance": 0.2, "signature_bias": 0.75},
	"perturbateur": {"depth_min": 0.25, "depth_max": 0.5, "approach_distance": 280.0, "lift_chance": 0.35, "signature_bias": 0.75},
	"missiles": {"depth_min": 0.15, "depth_max": 0.35, "approach_distance": 220.0, "lift_chance": 0.2, "signature_bias": 0.8},
	"mini": {"depth_min": 0.3, "depth_max": 0.6, "approach_distance": 340.0, "lift_chance": 0.4, "signature_bias": 0.85},
}
var _ai_depth_min := AI_DEPTH_MIN
var _ai_depth_max := AI_DEPTH_MAX
var _ai_approach_distance := AI_APPROACH_DISTANCE
var _ai_lift_chance := 0.3
var _ai_signature_bias := 0.0

# Gamepad support (2026-08-01) — Xbox 360 / XInput-compatible pad, additive
# to the keyboard scheme (either works, whichever the player actually uses).
# Device index = player_index - 1, so a 2nd connected pad serves Player 2.
const GAMEPAD_STICK_DEADZONE := 0.25
const GAMEPAD_TRIGGER_THRESHOLD := 0.4

func _ready() -> void:
	_spawn_position = position
	state = ShipState.new(position, side, half_extents, max_hp_override)
	var kit: Array = []
	if character and character.kit.size() > 0:
		kit = character.kit
	else:
		# Story 1.4/1.5 placeholder — used until a character is assigned
		# (Story 2.3, character selection) or for quick scene testing.
		kit = [
			load("res://data/weapons/machine_gun.tres"),
			load("res://data/weapons/bazooka.tres"),
		]
	weapon_state = WeaponSystemState.new(kit)
	_apply_ai_profile()

## Epic 2, Story 2.3 — assigns a character (and rebuilds the weapon kit from
## it) after the ship already exists, e.g. from a character-select screen.
func set_character(new_character: CharacterData) -> void:
	character = new_character
	if character and character.kit.size() > 0:
		weapon_state = WeaponSystemState.new(character.kit)
	_apply_ai_profile()

## Story 2.7 — loads this ship's AI tuning from AI_PROFILES if its character
## has one, else falls back to the original Story 1.12 defaults.
func _apply_ai_profile() -> void:
	if not character or not AI_PROFILES.has(character.id):
		_ai_depth_min = AI_DEPTH_MIN
		_ai_depth_max = AI_DEPTH_MAX
		_ai_approach_distance = AI_APPROACH_DISTANCE
		_ai_lift_chance = 0.3
		_ai_signature_bias = 0.0
		return
	var profile: Dictionary = AI_PROFILES[character.id]
	_ai_depth_min = profile.depth_min
	_ai_depth_max = profile.depth_max
	_ai_approach_distance = profile.approach_distance
	_ai_lift_chance = profile.lift_chance
	_ai_signature_bias = profile.signature_bias

func _physics_process(delta: float) -> void:
	if not active:
		return
	if ai_controlled:
		_ai_update_wander(delta)
		_ai_update_depth(delta)
		_ai_update_weapon_switch(delta)
		_ai_update_lift_attempt(delta)

	var lift_held := _read_lift_held()
	var is_dash_character := character != null and character.special_rule == "dash_lift"

	if is_dash_character:
		# Vif's rewrite: never charges (the MINUS) — Lift is edge-triggered
		# into a short dash instead (the PLUS). See field comments above.
		_lift_charge_timer = 0.0
		_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
		if lift_held and not _lift_prev and _dash_timer <= 0.0 and _dash_cooldown_timer <= 0.0:
			var chosen_dir := _read_input()
			if chosen_dir.length() < 0.01:
				chosen_dir = _last_nonzero_move_dir
			if chosen_dir.length() < 0.01:
				chosen_dir = Vector2(1.0 if side == 0 else -1.0, 0.0) # default: push toward the frontier
			_dash_direction = chosen_dir.normalized()
			_dash_timer = DASH_DURATION
			_dash_cooldown_timer = DASH_COOLDOWN
	elif lift_held:
		_lift_charge_timer = minf(_lift_charge_timer + delta, LIFT_CHARGE_CAP)
	else:
		_lift_charge_timer = 0.0
	_lift_prev = lift_held

	var fire_held := _read_fire_pressed() and _stun_timer <= 0.0 # Story 2.6 — stunned ships can't fire
	var dashing := is_dash_character and _dash_timer > 0.0
	var selected := weapon_state.selected_weapon()

	# Charged fire (2026-08-09) — tracked before movement, since a weapon's
	# charge_fire_slow_multiplier needs to factor into this frame's speed.
	# Holding fires NORMALLY for the first NORMAL_FIRE_GRACE seconds, exactly
	# like any other weapon; only past that grace window does normal fire
	# suspend and the charge gauge start building. Releasing before
	# charge_fire_duration is reached (but past the grace) wastes the charge
	# attempt (nothing extra fires) — releasing at/after it fires the
	# empowered burst instead of a normal shot.
	var charge_capable := selected.charge_fire_duration > 0.0
	var released_charge_attempt := false # true only the exact frame fire is released after having charged past the grace window
	var charge_duration_at_release := 0.0
	if charge_capable:
		if fire_held:
			_fire_held_duration += delta
		elif _fire_held_duration > NORMAL_FIRE_GRACE:
			# only a release AFTER the grace window is a "charge attempt" —
			# releasing during/at the grace window just stops normal fire,
			# already handled frame-by-frame below like any other weapon.
			released_charge_attempt = true
			charge_duration_at_release = _fire_held_duration
			_fire_held_duration = 0.0
		else:
			_fire_held_duration = 0.0
	else:
		_fire_held_duration = 0.0
	# 2026-08-09 bug report: "parfois pendant la charge, la vitesse n'est pas
	# diminuee. le joueur DOIT rester a 30% de vitesse tant que le bouton de
	# tir n'a pas ete relache" — derived from the persisted _fire_held_duration
	# (the actual state), not re-gated on this frame's live fire_held read, so
	# it can never desync from the slow for even a single frame while a charge
	# attempt is genuinely still in progress.
	var is_charging := charge_capable and _fire_held_duration > NORMAL_FIRE_GRACE

	# Charging the lift freezes movement entirely — that's the risk/reward trade
	# (dash characters never freeze this way; the dash burst below replaces it).
	# Holding the fire button ("je balance la sauce") also slows movement —
	# spraying continuously has a real positioning cost, not just ammo cost.
	var input_direction: Vector2
	if dashing:
		input_direction = _dash_direction # steer-locked for the burst's duration
	elif (lift_held and not is_dash_character) or _stun_timer > 0.0:
		input_direction = Vector2.ZERO
	else:
		input_direction = _read_input()
		if input_direction.length() > 0.01:
			_last_nonzero_move_dir = input_direction.normalized()

	var speed_multiplier := _mobility_boost_multiplier
	if dashing:
		speed_multiplier = maxf(speed_multiplier, DASH_SPEED_MULTIPLIER)
	if is_charging:
		speed_multiplier = minf(speed_multiplier, selected.charge_fire_slow_multiplier)
	if _vulnerability_timer > 0.0:
		speed_multiplier = minf(speed_multiplier, VULNERABILITY_SPEED_MULTIPLIER)
	if _charged_beam_slow_timer > 0.0:
		speed_multiplier = minf(speed_multiplier, _charged_beam_slow_multiplier)
	if fire_held and not is_charging:
		speed_multiplier = minf(speed_multiplier, FIRE_HOLD_SPEED_MULTIPLIER) # normal firing (including a charge-capable weapon's grace window) always carries this slow; charge_fire_slow_multiplier takes over once actually charging
	state = state.update(input_direction, delta, arena_bounds, frontier_x, speed_multiplier)
	position = state.position
	_dash_timer = maxf(_dash_timer - delta, 0.0)

	_process_weapon_selection()
	_ai_pulse_select = false # consumed for this frame, whether or not it was set
	weapon_state = weapon_state.with_cooldown_ticked(delta)
	weapon_state = weapon_state.with_heat_ticked(delta, fire_held)
	# 2026-08-09 — "beam" (Zoneur's laser) used to bypass this whole dispatch
	# for a continuous hold-to-channel effect; redesigned into a discrete,
	# timed pulse fired through this exact same cooldown/charge flow as
	# every other weapon (MatchArenaNode decides how to render the effect
	# based on weapon.effect_type — see _on_weapon_fired()/_spawn_timed_beam()).
	var is_full_auto := character != null and character.full_auto
	if charge_capable and is_charging:
		pass # normal fire suspended while actively charging (past the grace window)
	elif fire_held and (is_full_auto or not _fire_prev):
		# Either a non-charge-capable weapon, or a charge-capable one still
		# within its NORMAL_FIRE_GRACE window — fires exactly like normal.
		# Full-auto (Mitrailleur only) repeats every held frame; everyone
		# else only fires on the rising edge of a fresh press.
		var result := weapon_state.fired()
		weapon_state = result.state
		if result.fired:
			var weapon: WeaponData = result.weapon
			_flash_timer = FLASH_DURATION
			if weapon.is_heavy:
				_vulnerability_timer = VULNERABILITY_DURATION # Story 1.8
			if weapon.effect_type == "mobility_boost":
				# Story 2.5 — self-applied instantly, no projectile spawned.
				_mobility_boost_timer = weapon.effect_duration
				_mobility_boost_active_multiplier = weapon.effect_speed_multiplier
			else:
				weapon_fired.emit(weapon)
			print("%s fired %s (gauge left: %.0f)" % [
				name, weapon.display_name, weapon_state.gauges[weapon_state.selected_index]
			])

	if charge_capable and released_charge_attempt:
		if charge_duration_at_release >= selected.charge_fire_duration:
			var result := weapon_state.fired()
			weapon_state = result.state
			if result.fired:
				_flash_timer = FLASH_DURATION
				charged_weapon_fired.emit(result.weapon)
				print("%s CHARGED-fired %s" % [name, result.weapon.display_name])
		# else: released mid-charge (past the grace window, before full) — the attempt is lost, nothing fires

	_fire_prev = fire_held

	_mobility_boost_timer = maxf(_mobility_boost_timer - delta, 0.0)
	_mobility_boost_multiplier = _mobility_boost_active_multiplier if _mobility_boost_timer > 0.0 else 1.0
	if _mobility_boost_timer > 0.0:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = TRAIL_INTERVAL
			_spawn_trail_ghost()
	else:
		_trail_timer = 0.0
	_apply_passive_trickle(delta)
	_stun_timer = maxf(_stun_timer - delta, 0.0)
	_vulnerability_timer = maxf(_vulnerability_timer - delta, 0.0)
	_charged_beam_slow_timer = maxf(_charged_beam_slow_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual:
		visual.scale = Vector2.ONE # reset here, overridden below only while charging a lift (2026-08-10: "le lift meriterait un effet un peu plus gros")
		if hidden_from_opponent:
			visual.modulate = Color(1.0, 1.0, 1.0, 0.0) # "invisible_opponent" twist — rendering only; targeting (homing/turrets) still uses the real position
		elif _stun_timer > 0.0:
			visual.modulate = Color(0.75, 0.75, 1.0) # pale blue-white — distinct from vulnerability/lift tints
		elif _vulnerability_timer > 0.0:
			visual.modulate = Color(1.0, 0.45, 0.45) # reddish tint while vulnerable
		elif dashing:
			visual.modulate = Color(0.4, 0.75, 1.0) # electric blue burst — distinct from Turbo's cyan and the charge tint's gold
		elif charge_capable and is_charging and _fire_held_duration >= selected.charge_fire_duration:
			# Fully charged and ready to release (2026-08-09, Camil: "quand la
			# charge est fini, tu peux faire clignoter rapidement (1/2s) le
			# joueur pour qu'on sache que c'est bon") — a fast blink instead of
			# just holding the gradient's end color, so "ready" is unmistakable.
			var blink_on := fmod(_fire_held_duration, CHARGE_READY_BLINK_PERIOD) < CHARGE_READY_BLINK_PERIOD / 2.0
			visual.modulate = Color(1.7, 1.7, 1.7) if blink_on else Color(1.0, 0.35, 0.1)
		elif is_charging:
			var fire_charge_fraction := clampf(_fire_held_duration / maxf(selected.charge_fire_duration, 0.001), 0.0, 1.0)
			visual.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.35, 0.1), fire_charge_fraction) # builds toward orange-red — distinct from the lift charge's gold
		elif lift_held and not is_dash_character:
			var charge_fraction := clampf(_lift_charge_timer / LIFT_CHARGE_CAP, 0.0, 1.0)
			visual.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.84, 0.29), charge_fraction) # builds toward gold
			# 2026-08-10, Camil: "le lift meriterait un effet un peu plus gros" —
			# the tint alone was the only feedback; the ship itself now visibly
			# swells as the charge builds (up to +35% at 100%), on top of the
			# color, so a fully-charged lift reads as an obviously bigger threat.
			visual.scale = Vector2.ONE * lerpf(1.0, 1.35, charge_fraction)
		elif _double_fire_shots_remaining > 0:
			visual.modulate = Color(1.0, 0.95, 0.3) # bright yellow — Mitrailleur's "double fire" buff
		elif _flash_timer > 0.0:
			visual.modulate = Color(1.7, 1.7, 1.7)
		elif _mobility_boost_timer > 0.0:
			visual.modulate = Color(0.5, 1.0, 1.0) # cyan glow — Turbo had zero visual feedback before (2026-08-05: "le turbo n'est pas fait ?"), it was working but untinted
		else:
			visual.modulate = Color(1.0, 1.0, 1.0)
	queue_redraw() # cheap even when DebugOverlay.show_hitboxes is false — _draw() below just no-ops

## 2026-08-10, Camil: "les hitbox autour de TOUTES les armes, activables en
## appuyant sur la touche TAB... pour comprendre pourquoi certaines fois je
## ne touche pas" — draws the EXACT rect ProjectileNode._segment_crosses_
## rect() checks a weapon's shot against (see its `target_rect`), so what's
## drawn is provably what determines a hit, not an approximation of it.
## Local space, so no need to track position separately — Node2D draws
## relative to its own transform. Ship's Visual (a Polygon2D child, drawn
## AFTER this node's own _draw()) exactly matches half_extents in size, so
## a thin stroke here would sit entirely under it and never be seen; an
## unfilled draw_rect's stroke straddles the boundary (half in, half out —
## same as any vector-graphics stroke), so a wide-enough stroke's OUTER half
## still pokes past Visual's edge and stays visible regardless of draw
## order, with no need to touch Visual's z_index (which would have real
## side effects on cross-ship/ball render ordering, not just this overlay).
##
## Looked up via get_node_or_null("/root/DebugOverlay") rather than a
## direct `DebugOverlay.show_hitboxes` reference — smoke_test.gd builds
## ShipNode instances outside any scene/autoload context (a project-wide
## constraint: autoloads must never be referenced anywhere reachable from
## smoke_test.gd), and a static reference to an autoload's global class
## name fails class registration entirely in that context, not just at
## this call site — every ShipNode.new() in the whole test suite would
## silently degrade to an uncallable raw GDScript object.
func _draw() -> void:
	var debug := get_node_or_null("/root/DebugOverlay")
	if debug and debug.show_hitboxes:
		draw_rect(Rect2(-half_extents, half_extents * 2.0), Color(1.0, 0.15, 0.15, 0.9), false, 4.0)

## Turbo afterimage — a faint, fading copy of this ship's own Visual shape
## left behind at the current position, purely cosmetic (no gameplay effect).
func _spawn_trail_ghost() -> void:
	var visual := get_node_or_null("Visual") as Polygon2D
	if not visual or not get_parent():
		return
	var ghost := Polygon2D.new()
	ghost.polygon = visual.polygon
	ghost.color = TRAIL_COLOR
	ghost.position = position
	ghost.z_index = -1 # render behind ships/ball
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.finished.connect(ghost.queue_free)

## Story 1.9 (partial) — resets HP and position for a new round.
func reset_for_new_round() -> void:
	position = _spawn_position
	state = ShipState.new(_spawn_position, side, half_extents, max_hp_override)
	_vulnerability_timer = 0.0
	_charged_beam_slow_timer = 0.0
	# 2026-08-08 bug report: weapon gauges carried over between rounds
	# (a maxed gauge from round 1's rally could open round 2 with a free
	# shot). Rebuild fresh — same kit, gauges/cooldown back to 0 — keeping
	# whichever weapon was selected rather than resetting to index 0.
	weapon_state = WeaponSystemState.new(weapon_state.kit, weapon_state.selected_index)

func _process_weapon_selection() -> void:
	var select_pressed := _read_weapon_select_pressed()
	if select_pressed and not _weapon_select_prev:
		weapon_state = weapon_state.with_selection(weapon_state.selected_index + 1)
		print("%s selected %s" % [name, weapon_state.selected_weapon().display_name])
	_weapon_select_prev = select_pressed

## Dedicated inputs, separate from movement keys (Story 1.4 AC: movement
## must never be blocked by weapon selection).
func _read_weapon_select_pressed() -> bool:
	if ai_controlled:
		return _ai_pulse_select
	if Input.is_joy_button_pressed(_gamepad_device(), JOY_BUTTON_A):
		return true
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_Q) # physical Q = "A" label on AZERTY
	return Input.is_physical_key_pressed(KEY_KP_0) # numpad — unambiguous across keyboard layouts

func _read_fire_pressed() -> bool:
	if ai_controlled:
		return _ai_should_fire()
	if Input.get_joy_axis(_gamepad_device(), JOY_AXIS_TRIGGER_RIGHT) > GAMEPAD_TRIGGER_THRESHOLD:
		return true
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_SPACE)
	return Input.is_physical_key_pressed(KEY_ENTER)

## Which local joypad device serves this ship: device 0 for Player 1,
## device 1 for Player 2. Harmless if nothing is connected at that index.
func _gamepad_device() -> int:
	return player_index - 1

## Placeholder raw-key input for Story 1.1 (single/local testing), now with
## an Xbox 360 / XInput-compatible left-stick reading OR'd in (2026-08-01).
## A future pass can replace this with a proper InputMap-based scheme
## so key bindings are configurable.
func _read_input() -> Vector2:
	if ai_controlled:
		return _ai_read_input()
	var dir := Vector2.ZERO
	if player_index == 1:
		if Input.is_physical_key_pressed(KEY_D):
			dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			dir.y -= 1.0
	else:
		if Input.is_physical_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_UP):
			dir.y -= 1.0

	var stick := Vector2(
		Input.get_joy_axis(_gamepad_device(), JOY_AXIS_LEFT_X),
		Input.get_joy_axis(_gamepad_device(), JOY_AXIS_LEFT_Y)
	)
	if stick.length() > GAMEPAD_STICK_DEADZONE:
		dir += stick

	return dir

## Story 1.2 — aim on ball return reuses the movement direction currently
## held (Pong-style: where you're moving is where you aim).
func get_aim_input() -> Vector2:
	if ai_controlled:
		return Vector2.ZERO # Story 1.12 AC — AI doesn't need to be skilled, default reflection is enough
	return _read_input()

## Lift/spin key — holding it freezes movement and charges the lift (see
## _lift_charge_timer). AI attempts occasional lifts via _ai_lift_timer.
func _read_lift_held() -> bool:
	if ai_controlled:
		return _ai_lift_timer > 0.0
	if Input.get_joy_axis(_gamepad_device(), JOY_AXIS_TRIGGER_LEFT) > GAMEPAD_TRIGGER_THRESHOLD:
		return true
	if player_index == 1:
		return Input.is_physical_key_pressed(KEY_SHIFT)
	return Input.is_physical_key_pressed(KEY_CTRL)

## Returns the charge tier reached: <0.3s=0%, 0.3-0.6s=33%, 0.6-1.5s=66%, >=1.5s=100%.
## AI included — it now attempts occasional lifts (_ai_lift_timer -> _read_lift_held()).
## Vif's rewrite (special_rule == "dash_lift"): never charges — always 0%
## except during the dash window, where a connecting return gets a fixed
## "leger lift" (DASH_LIFT_CHARGE) instead.
func get_lift_charge() -> float:
	if character != null and character.special_rule == "dash_lift":
		return DASH_LIFT_CHARGE if _dash_timer > 0.0 else 0.0
	if _lift_charge_timer < 0.3:
		return 0.0
	elif _lift_charge_timer < 0.6:
		return 0.33
	elif _lift_charge_timer < 1.5:
		return 0.66
	return 1.0

## Story 1.12 — heuristic AI (still deliberately unskilled per AC, no
## reflex-tier precision): anticipates the ball's vertical trajectory with a
## short lookahead, uses hysteresis bands (both axes) to avoid jittering in
## place, and mostly holds a wandering mid/back position — only pushing up
## to the frontier when the ball has actually closed in on it specifically
## (2026-08-01: was reflexively rushing the net any time the ball was
## technically on its side, which read as "glued to the net").
func _ai_read_input() -> Vector2:
	if not ball_ref:
		return Vector2.ZERO

	var ball_on_my_side := ball_ref.position.x < frontier_x if side == 0 else ball_ref.position.x > frontier_x

	# Vertical: blend ball-tracking with an independent wander target so the
	# AI doesn't read as "glued" to the ball — more wander weight when the
	# ball isn't actually its problem right now, less (but never zero) when urgent.
	var ball_target_y := ball_ref.position.y + ball_ref.state.velocity.y * AI_LOOKAHEAD
	var wander_weight := 0.2 if ball_on_my_side else 0.6
	var target_y := lerpf(ball_target_y, _ai_wander_target_y, wander_weight)

	var diff_y := target_y - position.y
	if absf(diff_y) < AI_DEADZONE_STOP:
		_ai_vertical_dir = 0.0
	elif absf(diff_y) > AI_DEADZONE_START:
		_ai_vertical_dir = signf(diff_y)
	# else: within the hysteresis band — keep the previous direction rather
	# than flip-flopping every frame, which is what read as a "freeze".

	# Horizontal: default to a wandering point in the mid/back of the half
	# (_ai_preferred_depth), only committing to the frontier when the ball
	# has genuinely closed the distance — approaching the net is a deliberate
	# choice for a better angle, not a reflex.
	var forward_sign := 1.0 if side == 0 else -1.0
	var back_x := arena_bounds.position.x + half_extents.x if side == 0 else arena_bounds.position.x + arena_bounds.size.x - half_extents.x
	var frontier_reach_x := frontier_x - ShipState.NEUTRAL_ZONE_HALF_WIDTH - half_extents.x if side == 0 else frontier_x + ShipState.NEUTRAL_ZONE_HALF_WIDTH + half_extents.x
	var span := absf(frontier_reach_x - back_x)
	var default_target_x := back_x + forward_sign * span * _ai_preferred_depth

	var ball_close := ball_on_my_side and absf(ball_ref.position.x - position.x) < _ai_approach_distance
	var target_x := frontier_reach_x if ball_close else default_target_x

	var diff_x := target_x - position.x
	if absf(diff_x) < AI_H_DEADZONE_STOP:
		_ai_horizontal_dir = 0.0
	elif absf(diff_x) > AI_H_DEADZONE_START:
		_ai_horizontal_dir = signf(diff_x)

	return Vector2(_ai_horizontal_dir, _ai_vertical_dir)

## Periodically picks a new "idle" y target within the arena, so the AI
## keeps some independent motion instead of purely mirroring the ball.
func _ai_update_wander(delta: float) -> void:
	_ai_wander_timer -= delta
	if _ai_wander_timer > 0.0:
		return
	_ai_wander_timer = randf_range(AI_WANDER_INTERVAL_MIN, AI_WANDER_INTERVAL_MAX)
	var min_y := arena_bounds.position.y + half_extents.y
	var max_y := arena_bounds.position.y + arena_bounds.size.y - half_extents.y
	_ai_wander_target_y = randf_range(min_y, max_y)

## Periodically re-picks how deep in its half the AI prefers to sit
## (0 = back wall, 1 = frontier), biased toward the back/mid via
## AI_DEPTH_MIN/MAX, so it isn't parked at a single fixed depth either.
func _ai_update_depth(delta: float) -> void:
	_ai_depth_timer -= delta
	if _ai_depth_timer > 0.0:
		return
	_ai_depth_timer = randf_range(AI_DEPTH_INTERVAL_MIN, AI_DEPTH_INTERVAL_MAX)
	_ai_preferred_depth = randf_range(_ai_depth_min, _ai_depth_max)

## Story 1.12 default: cycles weapons unconditionally, purely for variety.
## Story 2.7: when the character has a signature_bias (>0), instead of
## blindly cycling, the AI rolls whether it "wants" its signature weapon
## (kit index 0) and only pulses select when that doesn't match its current
## selection — e.g. a Controleur AI mostly stays on its turret rather than
## alternating away from it every few seconds.
func _ai_update_weapon_switch(delta: float) -> void:
	_ai_weapon_switch_timer -= delta
	if _ai_weapon_switch_timer > 0.0:
		return
	_ai_weapon_switch_timer = randf_range(3.0, 6.0)
	if _ai_signature_bias <= 0.0 or weapon_state.kit.size() < 2:
		_ai_pulse_select = true
		return
	var wants_signature := randf() < _ai_signature_bias
	var has_signature := weapon_state.selected_index == 0
	if wants_signature != has_signature:
		_ai_pulse_select = true

## Rolls a chance to attempt a lift whenever the ball is closing in on this
## ship's side — sets _ai_lift_timer, which _read_lift_held() then reuses
## through the same charge/freeze machinery as the human controls.
func _ai_update_lift_attempt(delta: float) -> void:
	if _ai_lift_timer > 0.0:
		_ai_lift_timer = maxf(_ai_lift_timer - delta, 0.0)
		return
	if not ball_ref:
		return
	var approaching := ball_ref.position.x < frontier_x if side == 0 else ball_ref.position.x > frontier_x
	if not approaching:
		_ai_lift_decided = false
		return
	var edge_x := arena_bounds.position.x if side == 0 else arena_bounds.position.x + arena_bounds.size.x
	if absf(ball_ref.position.x - edge_x) < 260.0 and not _ai_lift_decided:
		_ai_lift_decided = true
		if randf() < _ai_lift_chance:
			_ai_lift_timer = [0.35, 0.75].pick_random()

## Story 1.12 — fires when roughly aligned with the opponent, basic reactive logic.
func _ai_should_fire() -> bool:
	if not opponent_ref:
		return false
	return absf(opponent_ref.position.y - position.y) < 90.0

## Story 1.9 (partial/test-only) — see ship_state.gd note.
func apply_damage(amount: float) -> void:
	state = state.damaged(amount)

## Epic 2, Story 2.6 — disables movement and firing for `duration` seconds.
## HP and gauges are untouched: a stun removes agency, it is not damage.
func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)

## Lourd's "heavy_push" rule (2026-08-09) — see BallNode._resolve_ships().
func apply_knockback(offset: Vector2) -> void:
	state = state.knocked_back(offset, arena_bounds, frontier_x)
	position = state.position

## Mitrailleur's charged fire (2026-08-09) — see WeaponData.charged_double_fire_shots.
func grant_double_fire(shots: int) -> void:
	_double_fire_shots_remaining = shots

## Epic 4, Story 4.5 — "gauge_floor" twist's regen guarantee: a small
## trickle to the selected weapon's gauge, independent of self_fill_locked
## (which only gates the Story 1.7 return-bonus path, not this).
func _apply_passive_trickle(delta: float) -> void:
	if passive_trickle_rate <= 0.0:
		return
	var trickle_weapon: WeaponData = weapon_state.selected_weapon()
	weapon_state = weapon_state.with_gauge_added(trickle_weapon.gauge_max * passive_trickle_rate / 100.0 * delta)

## Stories 1.6/1.7 — fills the currently selected weapon's gauge. Used
## directly by Story 1.6's "opponent missed" fill, which must NEVER be
## gated by self_fill_locked (Camil: "sinon on perd le core game").
func fill_selected_gauge(amount: float) -> void:
	weapon_state = weapon_state.with_gauge_added(amount)
	gauge_filled.emit(amount)

## Epic 4, Story 4.5 — self-fill path for Story 1.7's successful-return
## bonus specifically. The "gauge_floor" twist locks this (self_fill_locked)
## while leaving fill_selected_gauge() (Story 1.6) fully active.
func fill_selected_gauge_from_return(amount: float) -> void:
	if self_fill_locked:
		return
	fill_selected_gauge(amount)
