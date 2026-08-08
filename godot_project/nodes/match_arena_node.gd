class_name MatchArenaNode
extends Node2D

## Sets up the arena, wires ships/ball/HUD together, and resolves the
## match-level rules (round end, best-of-3) that don't belong to any
## single entity's own state.

@export var arena_origin: Vector2 = Vector2(40, 60)
@export var arena_size: Vector2 = Vector2(1200, 600)

@onready var ship_1: ShipNode = $Ship1
@onready var ship_2: ShipNode = $Ship2
@onready var ball: BallNode = $Ball

@onready var p1_label: Label = $DebugHUD/P1Label
@onready var p2_label: Label = $DebugHUD/P2Label
@onready var round_label: Label = $DebugHUD/RoundLabel
@onready var match_label: Label = $DebugHUD/MatchLabel
@onready var ai_status_label: Label = $DebugHUD/AIStatusLabel
@onready var p1_hp_fill: ColorRect = $DebugHUD/P1HPBarFill
@onready var p2_hp_fill: ColorRect = $DebugHUD/P2HPBarFill
@onready var ready_label: Label = $DebugHUD/ReadyLabel

const HP_BAR_WIDTH := 240.0

var match_state: MatchState = MatchState.new()
var _round_active := true
var _ai_toggle_prev := false
var _beams: Dictionary = {} # ShipNode -> BeamNode, tracks each ship's active laser beam (juice pass)

# Epic 4, Story 4.5 — "match twist" support for campaign rival/boss fights.
# Campaign match-launch code (Story 4.6/4.8) sets active_twist before the
# pre-match ready gate; MatchArenaNode owns applying/ticking whichever twist
# is active for the whole encounter. null (the default) means "no twist" —
# every field below stays inert and normal-match behavior is untouched.
var active_twist: TwistData = null
var _extra_balls: Array = [] # of BallNode — "multi_ball"
var _hazard_spawn_timer := 0.0 # "hazard_zones"
var _decoy: DecoyNode = null # "visual_decoy"
var _energy_orb_timer := 0.0 # "energy_orb_pickup"
var _base_frontier_x: float # the un-twisted center — drift/shrink animate away from and back toward this
var _current_frontier_x: float # what ships/ball are actually fed each tick — animates for "drifting_neutral_zone"
var _current_arena_bounds: Rect2 # what ships/ball are actually fed each tick — animates for "shrinking_arena"
var _shrink_step := 0
var _shrink_step_timer := 0.0
var _shrink_anim_elapsed := 0.0
var _shrink_animating := false
var _shrink_start_bounds: Rect2
var _shrink_target_bounds: Rect2
var _drift_direction := 1.0 # "drifting_neutral_zone" — reverses at +/- drift_range from _base_frontier_x

# Pre-match gate (2026-08-01): nothing moves until a player confirms ready.
var _match_started := false

# Epic 4, Story 4.4/4.6/4.8 — true when this match was launched from the
# campaign map via CampaignContext, so _check_round_end() records the
# result to CampaignSave and returns to the map instead of just sitting on
# a "Match termine" label like a plain 1v1.
var _campaign_mode := false

func _ready() -> void:
	# Story 2.3 — if this scene was reached via CharacterSelect, apply the
	# picks over whatever character (if any) is hardcoded on the scene node
	# itself. Running MatchArena.tscn directly in the editor for quick
	# testing leaves MatchSetup's fields null, so the scene's own defaults
	# (or the Epic 1 placeholder kit) apply instead — no code path required.
	if MatchSetup.p1_character:
		ship_1.set_character(MatchSetup.p1_character)
	if MatchSetup.p2_character:
		ship_2.set_character(MatchSetup.p2_character)

	# Epic 4 — a campaign encounter (Story 4.4/4.6/4.8) overrides the plain
	# MatchSetup picks above: the player always plays their campaign
	# character, side 1 is always the AI-controlled mook/rival/organizer.
	if CampaignContext.has_pending_encounter():
		_campaign_mode = true
		ship_1.set_character(CampaignContext.campaign.character)
		ship_2.set_character(CampaignContext.encounter.opponent)
		ship_2.ai_controlled = true
		if CampaignContext.encounter.is_mook:
			ship_2.max_hp_override = ShipState.START_HP * CampaignContext.encounter.mook_hp_multiplier
		if CampaignContext.encounter.twist:
			active_twist = CampaignContext.encounter.twist

	var bounds := Rect2(arena_origin, arena_size)
	var frontier_x := arena_origin.x + arena_size.x / 2.0
	_base_frontier_x = frontier_x
	_current_frontier_x = frontier_x
	_current_arena_bounds = bounds

	ship_1.arena_bounds = bounds
	ship_1.frontier_x = frontier_x

	ship_2.arena_bounds = bounds
	ship_2.frontier_x = frontier_x

	ball.arena_bounds = bounds
	ball.frontier_x = frontier_x
	ball.ships = [ship_1, ship_2]

	if active_twist:
		apply_twist(active_twist)

	ship_1.opponent_ref = ship_2
	ship_2.opponent_ref = ship_1
	ship_1.ball_ref = ball
	ship_2.ball_ref = ball

	ship_1.weapon_fired.connect(_on_weapon_fired.bind(ship_1))
	ship_2.weapon_fired.connect(_on_weapon_fired.bind(ship_2))
	ship_1.gauge_filled.connect(_on_gauge_filled.bind(ship_1))
	ship_2.gauge_filled.connect(_on_gauge_filled.bind(ship_2))

	_update_round_label()

	ship_1.active = false
	ship_2.active = false
	ball.active = false
	ready_label.text = "Match 1\nPret ? (appuyez sur Tir pour commencer)"

func _process(_delta: float) -> void:
	p1_label.text = _debug_text(ship_1)
	p2_label.text = _debug_text(ship_2)
	p1_hp_fill.size.x = HP_BAR_WIDTH * clampf(ship_1.state.hp / ship_1.max_hp_override, 0.0, 1.0)
	p2_hp_fill.size.x = HP_BAR_WIDTH * clampf(ship_2.state.hp / ship_2.max_hp_override, 0.0, 1.0)

	_process_ai_toggle()
	_process_beams()

	if not _match_started:
		_process_ready_gate()
		return

	_check_round_end()

func _physics_process(delta: float) -> void:
	if active_twist and _match_started and _round_active:
		_process_twist(delta)

## Pre-match gate — waits for either player's fire input (keyboard or
## gamepad trigger, device 0 or 1) before unfreezing ships and ball.
func _process_ready_gate() -> void:
	var pressed := Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
		or Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if not pressed:
		return
	_match_started = true
	ship_1.active = true
	ship_2.active = true
	ball.active = true
	ready_label.text = ""

func _debug_text(ship: ShipNode) -> String:
	var lines := ["PV: %d" % int(ship.state.hp)]
	for i in ship.weapon_state.kit.size():
		var weapon: WeaponData = ship.weapon_state.kit[i]
		var gauge := ship.weapon_state.gauges[i]
		var marker := "> " if i == ship.weapon_state.selected_index else "  "
		lines.append("%s%s: %d / %d" % [marker, weapon.display_name, int(gauge), int(weapon.gauge_max)])
	return "\n".join(lines)

func _on_gauge_filled(amount: float, ship: ShipNode) -> void:
	var popup := FloatingTextNode.new()
	popup.position = ship.position + Vector2(0.0, -16.0)
	popup.text = "+%d" % int(amount)
	add_child(popup)

# Placeholder R-Type sprites (2026-08-02) — replace with final art later.
# Machine-gun shots are colored per-shooter (matches ship colors) so a spray
# from both sides stays readable; bazooka keeps its own look, already
# distinct by size, plus a 2-frame flicker (see ProjectileNode).
const MACHINE_GUN_TEX_P1 := preload("res://assets/art/vfx/mitraillette_shot_bleu.png")
const MACHINE_GUN_TEX_P2 := preload("res://assets/art/vfx/mitraillette_shot_rose.png")
const BAZOOKA_TEXTURES := [
	preload("res://assets/art/vfx/bazook.png"), # single custom sprite, replaced the extracted 2-frame R-Type version
]

## Epic 2 — the signal carries the full WeaponData resource so this handler
## can branch on effect_type instead of a bare damage/is_heavy pair.
## "beam" (laser) never reaches here — ShipNode intercepts it before
## emitting, same as "mobility_boost" — see MatchArenaNode._sync_beam().
## No dedicated art exists yet for the Epic 2 weapons (laser, boomerang,
## homing missile, mini-shot) — they reuse the bazooka look when is_heavy,
## otherwise the per-shooter machine-gun look, same as Epic 1.
func _on_weapon_fired(weapon: WeaponData, ship: ShipNode) -> void:
	if weapon.effect_type == "turret":
		_spawn_turret(weapon, ship)
		return

	# "Shmup juice pass" — projectile_count > 1 fans a burst instead of a
	# single shot (e.g. the missile swarm), staggered by burst_stagger.
	if weapon.projectile_count <= 1:
		_spawn_projectile(weapon, ship, 0.0)
		return
	for i in weapon.projectile_count:
		var t := float(i) / float(maxi(weapon.projectile_count - 1, 1))
		var angle_offset := lerpf(-weapon.burst_spread_deg / 2.0, weapon.burst_spread_deg / 2.0, t)
		if weapon.burst_stagger > 0.0 and i > 0:
			get_tree().create_timer(i * weapon.burst_stagger).timeout.connect(
				_spawn_projectile.bind(weapon, ship, angle_offset)
			)
		else:
			_spawn_projectile(weapon, ship, angle_offset)

func _spawn_projectile(weapon: WeaponData, ship: ShipNode, angle_offset_deg: float) -> void:
	if not is_instance_valid(ship):
		return # round may have reset mid-burst-stagger

	var projectile := ProjectileNode.new()
	projectile.position = ship.position
	var direction := 1.0 if ship.side == 0 else -1.0
	var spread_deg := angle_offset_deg
	# Random per-shot jitter is for single-projectile sprays (machine gun) —
	# a multi-projectile burst already has its own deliberate fan geometry
	# (burst_spread_deg), so layering jitter on top just made it wobble
	# instead of reading as a clean, repeatable pattern (2026-08-06 playtest:
	# "pas de random sur les angles" for the Éventail fan).
	if not weapon.is_heavy and weapon.projectile_count <= 1:
		spread_deg += randf_range(-weapon.spread_deg, weapon.spread_deg)
	var shot_velocity := Vector2(direction * 620.0, 0.0).rotated(deg_to_rad(spread_deg))
	projectile.velocity = shot_velocity
	projectile.flip_h = direction < 0.0
	if weapon.is_heavy:
		projectile.textures = BAZOOKA_TEXTURES
		# bazook.png's fireball ("front") points LEFT natively — opposite of the
		# machine-gun sprites — so it needs the inverse of the shared flip_h set
		# above (2026-08-02: confirmed by inspecting the sprite directly).
		projectile.flip_h = direction > 0.0
		projectile.visual_scale = 1.4 # +40% (2026-08-02 — reverted, stays consistent with the other projectiles)
	else:
		projectile.textures = [MACHINE_GUN_TEX_P1] if ship.side == 0 else [MACHINE_GUN_TEX_P2]
		projectile.visual_scale = 1.4 # native 16x10 is hard to read orientation on at real game scale
		# Verified 2026-08-02 by inspecting both sprites at 12x zoom: the colored
		# tip (the bullet's "front") points RIGHT natively in both files, so the
		# base flip_h = direction < 0.0 (set above) is already correct — the
		# earlier toggle here was a wrong guess and has been reverted.
	if weapon.projectile_count > 1:
		projectile.visual_scale *= 0.7 # each unit in a burst reads smaller than a lone shot
	projectile.visual_scale *= weapon.visual_scale_multiplier
	projectile.homing_strength = weapon.homing_strength
	projectile.damage = weapon.damage
	projectile.effect_type = weapon.effect_type
	projectile.effect_duration = weapon.effect_duration
	projectile.tint = _weapon_tint(weapon.id)
	projectile.target = ship_2 if ship == ship_1 else ship_1
	if weapon.is_boomerang:
		projectile.is_boomerang = true
		projectile.shooter = ship
		projectile.lifetime = 3.0 # default 2.0s can be tight for a full out-and-back arc if the shooter keeps moving
	add_child(projectile)

## "Shmup juice pass" — the laser is a continuous beam (ShipNode.beam_active,
## driven by WeaponSystemState.beam_tick()) rather than a discrete
## weapon_fired signal, so MatchArenaNode owns a BeamNode's whole lifecycle
## here instead of spawning-and-forgetting like a normal projectile.
func _process_beams() -> void:
	_sync_beam(ship_1, ship_2)
	_sync_beam(ship_2, ship_1)

func _sync_beam(shooter: ShipNode, target: ShipNode) -> void:
	if shooter.beam_active:
		if not _beams.has(shooter):
			var beam := BeamNode.new()
			beam.shooter = shooter
			beam.target = target
			beam.arena_bounds = Rect2(arena_origin, arena_size)
			var tint := _weapon_tint(shooter.beam_weapon.id) if shooter.beam_weapon else Color(0.4, 1.0, 0.5)
			beam.color = Color(tint.r, tint.g, tint.b, 0.7) # translucent — _weapon_tint returns opaque colors
			add_child(beam)
			_beams[shooter] = beam
		_beams[shooter].weapon = shooter.beam_weapon
	elif _beams.has(shooter):
		if is_instance_valid(_beams[shooter]):
			_beams[shooter].queue_free()
		_beams.erase(shooter)

## Epic 2 weapons without dedicated art yet reuse the machine-gun/bazooka
## sprites — a tint keeps them tellable apart from the base weapons and from
## each other while playtesting (2026-08-02, "ça tire juste une balle
## normale" — the boomerang was functionally correct but visually identical
## to the machine gun).
func _weapon_tint(weapon_id: String) -> Color:
	match weapon_id:
		"stun_boomerang":
			return Color(0.6, 0.8, 1.0) # matches the pale-blue stun tint used on the hit ship
		"homing_missile":
			return Color(1.0, 0.6, 0.2) # orange
		"laser":
			return Color(0.4, 1.0, 0.5) # green
		"mini_shot":
			return Color(1.0, 1.0, 0.4) # yellow
		_:
			return Color.WHITE # machine_gun / bazooka — unchanged

## Story 2.4 — turret weapons spawn a persistent autonomous-firing node at
## the shooter's position instead of a traveling projectile.
func _spawn_turret(weapon: WeaponData, ship: ShipNode) -> void:
	var turret := TurretNode.new()
	turret.position = ship.position
	turret.weapon = weapon
	turret.target = ship_2 if ship == ship_1 else ship_1
	turret.owner_side = ship.side
	add_child(turret)

## Story 1.9 — a round ends when a ship's HP reaches 0; award the round,
## then reset both ships and the ball, unless the match itself is over.
func _check_round_end() -> void:
	if not _round_active or match_state.match_over:
		return
	if ship_1.state.hp <= 0.0 or ship_2.state.hp <= 0.0:
		var winner_side := 1 if ship_1.state.hp <= 0.0 else 0
		match_state = match_state.round_won_by(winner_side)
		_round_active = false
		_update_round_label()
		_clear_round_entities() # turrets/projectiles/beams don't survive a round boundary

		if match_state.match_over:
			if _campaign_mode:
				_resolve_campaign_result(match_state.winner_side)
			else:
				match_label.text = "Match termine - Joueur %d gagne !" % (match_state.winner_side + 1)
		else:
			ship_1.reset_for_new_round()
			ship_2.reset_for_new_round()
			ball.reset_to_center()
			for extra in _extra_balls: # "multi_ball" twist — extra balls persist across rounds within the same twisted encounter, just re-center like the primary
				if is_instance_valid(extra):
					extra.reset_to_center()
			_round_active = true

## Epic 4, Story 4.4/4.6/4.8 — records the outcome to CampaignSave (mooks
## grant currency, the "real" rival grants a branch completion + unlock,
## the organizer completes the campaign run) and returns to the campaign
## map. A loss is never punished beyond the retry itself (Story 4.4 AC: no
## permadeath) — nothing is recorded, the player just goes back to the map.
func _resolve_campaign_result(winner_side: int) -> void:
	var character_id: String = CampaignContext.campaign.character.id

	if winner_side != 0: # side 1 (the mook/rival/organizer) won — no permadeath, just retry from the map (Story 4.4 AC)
		match_label.text = "Defaite..."
		await get_tree().create_timer(2.0).timeout
		CampaignContext.clear()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		return

	if CampaignContext.is_organizer_fight:
		CampaignSave.mark_organizer_defeated(character_id)
		match_label.text = "Tournoi remporte !"
		await get_tree().create_timer(2.0).timeout
		CampaignContext.clear()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		return

	if CampaignContext.encounter.is_mook:
		CampaignSave.add_currency(character_id, CampaignContext.encounter.reward_currency)
		match_label.text = "Victoire (+%d)" % CampaignContext.encounter.reward_currency
		await get_tree().create_timer(1.5).timeout
		if CampaignContext.advance_within_branch():
			get_tree().reload_current_scene() # straight into the next fight of the same mini-branch, no trip back to the map
		else:
			CampaignContext.clear()
			get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		return

	# The "real" rival, defeated.
	var unlock_id := ""
	if CampaignContext.encounter.unlock_reward:
		unlock_id = CampaignContext.encounter.unlock_reward.id
	CampaignSave.mark_branch_completed(character_id, CampaignContext.branch.id, unlock_id)
	match_label.text = "Rival vaincu !"
	await get_tree().create_timer(2.0).timeout
	CampaignContext.clear()
	get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")

## Round-end cleanup (2026-08-07 bug fix — "à la fin du round 1 les tourelles
## restent, elles devraient disparaître"): turrets, in-flight projectiles, and
## beams are all round-scoped side effects of weapon fire; none of them
## should survive into the next round (or linger past match end).
func _clear_round_entities() -> void:
	for child in get_children():
		if child is TurretNode or child is ProjectileNode or child is BeamNode or child is HazardZoneNode or child is EnergyOrbNode:
			child.queue_free()
	_beams.clear() # drop stale ShipNode -> BeamNode refs now that those nodes are queued for deletion
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null

func _update_round_label() -> void:
	round_label.text = "Round %d - %d" % [match_state.rounds_won[0], match_state.rounds_won[1]]

## Story 1.12 — F1 toggles a basic AI opponent on/off for Ship2, so solo
## testing doesn't require editing the scene.
func _process_ai_toggle() -> void:
	var pressed := Input.is_physical_key_pressed(KEY_F1)
	if pressed and not _ai_toggle_prev:
		ship_2.ai_controlled = not ship_2.ai_controlled
		ai_status_label.text = "IA J2: %s (F1)" % ("ON" if ship_2.ai_controlled else "OFF")
	_ai_toggle_prev = pressed

## Epic 4, Story 4.5 — configures the arena for one of the pool twists (or
## the boss-only energy_orb_pickup). Call before the pre-match ready gate,
## or set active_twist directly before this node enters the tree (_ready()
## calls this automatically when active_twist is already assigned).
func apply_twist(twist: TwistData) -> void:
	active_twist = twist
	match twist.twist_type:
		"multi_ball":
			_spawn_extra_balls(twist.ball_count - 1)
		"gauge_floor":
			for ship in [ship_1, ship_2]:
				ship.self_fill_locked = true
				ship.passive_trickle_rate = twist.passive_trickle_rate
		"invisible_opponent":
			for ship in [ship_1, ship_2]:
				if ship.ai_controlled:
					ship.hidden_from_opponent = true
		"visual_decoy":
			_spawn_decoy()
		# shrinking_arena / hazard_zones / drifting_neutral_zone /
		# energy_orb_pickup are pure timers/animations, handled continuously
		# in _process_twist() instead of a one-time setup step here.
		_:
			pass

func _process_twist(delta: float) -> void:
	match active_twist.twist_type:
		"shrinking_arena":
			_process_shrinking_arena(delta)
		"drifting_neutral_zone":
			_process_drifting_neutral_zone(delta)
		"hazard_zones":
			_process_hazard_spawns(delta)
		"energy_orb_pickup":
			_process_energy_orb_spawns(delta)

func _spawn_extra_balls(count: int) -> void:
	var ball_scene := preload("res://scenes/Ball.tscn")
	for i in count:
		var extra := ball_scene.instantiate() as BallNode
		extra.arena_bounds = _current_arena_bounds
		extra.frontier_x = _current_frontier_x
		extra.ships = [ship_1, ship_2]
		add_child(extra)
		extra.reset_to_center()
		extra.active = ball.active # stays in sync with the primary ball's pre-match gate / round resets
		_extra_balls.append(extra)

func _spawn_decoy() -> void:
	var mimicked := ship_2 if ship_2.ai_controlled else ship_1
	_decoy = DecoyNode.new()
	_decoy.position = mimicked.position
	_decoy.half_extents = mimicked.half_extents
	_decoy.arena_bounds = _current_arena_bounds
	_decoy.wander_speed = active_twist.decoy_wander_speed
	var mimicked_visual := mimicked.get_node_or_null("Visual") as Polygon2D
	_decoy.color = mimicked_visual.color if mimicked_visual else Color.WHITE
	add_child(_decoy)

## Shrinks arena_bounds by shrink_fraction per side every shrink_interval
## seconds, animated over shrink_animation_duration so no ship is ever
## snapped/ejected — ShipState's per-tick clamp (Regle absolue n1: already
## a pure function of the bounds it's given) naturally "pushes" any ship
## caught at the edge inward as _current_arena_bounds animates, for free.
func _process_shrinking_arena(delta: float) -> void:
	_shrink_step_timer += delta
	if _shrink_step_timer >= active_twist.shrink_interval:
		_shrink_step_timer = 0.0
		_start_next_shrink_step()
	if _shrink_animating:
		_shrink_anim_elapsed += delta
		var t := clampf(_shrink_anim_elapsed / active_twist.shrink_animation_duration, 0.0, 1.0)
		_current_arena_bounds = Rect2(
			_shrink_start_bounds.position.lerp(_shrink_target_bounds.position, t),
			_shrink_start_bounds.size.lerp(_shrink_target_bounds.size, t)
		)
		if t >= 1.0:
			_shrink_animating = false
		_sync_arena_bounds_to_entities()

func _start_next_shrink_step() -> void:
	_shrink_step += 1
	var total_shrink_x := arena_size.x * active_twist.shrink_fraction * _shrink_step
	total_shrink_x = minf(total_shrink_x, arena_size.x * 0.7) # never shrink the arena into an unplayable sliver
	_shrink_start_bounds = _current_arena_bounds
	_shrink_target_bounds = Rect2(
		Vector2(arena_origin.x + total_shrink_x / 2.0, arena_origin.y),
		Vector2(arena_size.x - total_shrink_x, arena_size.y)
	)
	_shrink_anim_elapsed = 0.0
	_shrink_animating = true

func _sync_arena_bounds_to_entities() -> void:
	ship_1.arena_bounds = _current_arena_bounds
	ship_2.arena_bounds = _current_arena_bounds
	ball.arena_bounds = _current_arena_bounds
	for extra in _extra_balls:
		if is_instance_valid(extra):
			extra.arena_bounds = _current_arena_bounds

## Continuous back-and-forth drift of the shared frontier_x (both the ship
## confinement boundary and the ball's neutral-zone center use the same
## value already, see ship_state.gd/ball_node.gd) — moving both together
## keeps them coherent, rather than letting the "safe zone" wander away
## from the wall ships actually can't cross.
func _process_drifting_neutral_zone(delta: float) -> void:
	_current_frontier_x += active_twist.drift_speed * _drift_direction * delta
	var offset := _current_frontier_x - _base_frontier_x
	if absf(offset) >= active_twist.drift_range:
		_current_frontier_x = _base_frontier_x + active_twist.drift_range * signf(offset)
		_drift_direction *= -1.0
	_sync_frontier_x_to_entities()

func _sync_frontier_x_to_entities() -> void:
	ship_1.frontier_x = _current_frontier_x
	ship_2.frontier_x = _current_frontier_x
	ball.frontier_x = _current_frontier_x
	for extra in _extra_balls:
		if is_instance_valid(extra):
			extra.frontier_x = _current_frontier_x

func _process_hazard_spawns(delta: float) -> void:
	_hazard_spawn_timer -= delta
	if _hazard_spawn_timer > 0.0:
		return
	_hazard_spawn_timer = active_twist.hazard_spawn_interval
	var hazard := HazardZoneNode.new()
	hazard.radius = active_twist.hazard_radius
	hazard.lifetime = active_twist.hazard_lifetime
	hazard.stuns_ships = active_twist.hazard_stuns_ships
	hazard.deflects_ball = active_twist.hazard_deflects_ball
	hazard.ships = [ship_1, ship_2]
	hazard.balls = [ball] + _extra_balls
	hazard.position = Vector2(
		randf_range(_current_arena_bounds.position.x + 60.0, _current_arena_bounds.position.x + _current_arena_bounds.size.x - 60.0),
		randf_range(_current_arena_bounds.position.y + 60.0, _current_arena_bounds.position.y + _current_arena_bounds.size.y - 60.0)
	)
	add_child(hazard)

func _process_energy_orb_spawns(delta: float) -> void:
	_energy_orb_timer -= delta
	if _energy_orb_timer > 0.0:
		return
	_energy_orb_timer = active_twist.orb_spawn_interval
	var orb := EnergyOrbNode.new()
	orb.gauge_bonus_percent = active_twist.orb_gauge_bonus_percent
	orb.ships = [ship_1, ship_2]
	orb.position = Vector2(
		_current_frontier_x,
		randf_range(_current_arena_bounds.position.y + 60.0, _current_arena_bounds.position.y + _current_arena_bounds.size.y - 60.0)
	)
	add_child(orb)
