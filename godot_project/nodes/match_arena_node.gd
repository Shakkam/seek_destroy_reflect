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
@onready var campaign_label: Label = $DebugHUD/CampaignLabel
@onready var background: ColorRect = $Background
@onready var neutral_zone_visual: ColorRect = $NeutralZone
@onready var center_line: Line2D = $CenterLine

const HP_BAR_WIDTH := 240.0

var match_state: MatchState = MatchState.new()
var _round_active := true
var _ai_toggle_prev := false

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
		var encounter := CampaignContext.current_encounter()
		ship_1.set_character(CampaignContext.campaign.character)
		ship_2.set_character(encounter.opponent)
		ship_2.ai_controlled = true
		if encounter.is_mook:
			ship_2.max_hp_override = ShipState.START_HP * encounter.mook_hp_multiplier
			# ship_2._ready() already ran (children ready before their parent
			# in Godot) and built `state` using the *old* default max_hp_override
			# — rebuild it now that the reduced value is set, or the mook
			# starts with a full 100 HP `state.hp` and the HP bar (which now
			# divides by max_hp_override) reads as stuck near-full while HP
			# visibly drops in the debug text (2026-08-08 bug report).
			ship_2.reset_for_new_round()
		if encounter.twist:
			active_twist = encounter.twist
		_update_campaign_label()

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
	ship_1.charged_weapon_fired.connect(_on_charged_weapon_fired.bind(ship_1))
	ship_2.charged_weapon_fired.connect(_on_charged_weapon_fired.bind(ship_2))
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
	_sync_twist_visuals()

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
		var line := "%s%s: %d / %d" % [marker, weapon.display_name, int(gauge), int(weapon.gauge_max)]
		# 2026-08-09 (Camil: "il faudrait une petite jauge de cooldown qui
		# descend des qu'on tire") — visible heat readout, weapons without
		# heat_max (most of them) never show it.
		if weapon.heat_max > 0.0:
			line += " [chauffe %d/%d]" % [int(ship.weapon_state.heats[i]), int(weapon.heat_max)]
		lines.append(line)
	# Mitrailleur's charged-fire buff (2026-08-09): "un petit icone se met a
	# cote de la barre pour indiquer qu'on est en mode double tir" — a text
	# tag next to the weapon line, same placeholder-HUD convention as the
	# heat readout above (no icon-graphics system exists yet).
	if ship._double_fire_shots_remaining > 0:
		lines.append("  [DOUBLE x%d]" % ship._double_fire_shots_remaining)
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
const VORTEX_TEXTURES := [
	preload("res://assets/art/vfx/wind1.png"),
] # Vif's Tourbillon (2026-08-09, Camil: "vu la vitesse, pour le tourbillon, pas d'anim : garde uniquement wind1") — dropped the wind1-3 cycle, too fast to read once the loop motion was tuned up; the looping path itself carries the "spinning" read now.
const BONBON_TEXTURES := [
	preload("res://assets/art/vfx/bonbon.png"),
] # Mini/Éventail's fan shot (2026-08-09) — single sprite, spins via WeaponData.projectile_spin_speed (mini_shot.tres) since there's no multi-frame cycle for this one, unlike the Tourbillon.
const BOOMERANG_TEXTURES := [
	preload("res://assets/art/vfx/boomerang.png"),
] # Perturbateur's stun_boomerang (2026-08-10) — used to reuse the tinted machine-gun sprite; dedicated art now, spins via projectile_spin_speed (stun_boomerang.tres).

## Epic 2 — the signal carries the full WeaponData resource so this handler
## can branch on effect_type instead of a bare damage/is_heavy pair.
## No dedicated art exists yet for the Epic 2 weapons (boomerang, homing
## missile) — they reuse the bazooka look when is_heavy, otherwise the
## per-shooter machine-gun look, same as Epic 1.
func _on_weapon_fired(weapon: WeaponData, ship: ShipNode) -> void:
	if weapon.effect_type == "turret":
		_spawn_turret(weapon, ship)
		return

	if weapon.effect_type == "beam":
		_spawn_timed_beam(weapon, ship, weapon.beam_duration, weapon.beam_thickness_multiplier)
		return

	# Mitrailleur's charged-fire buff (2026-08-09): "les 10 missiles suivants
	# seront doubles (paralleles, separes de 10px verticalement)" — consumed
	# one at a time, bypasses the normal single/burst path entirely (moot
	# for machine_gun specifically, which never has projectile_count > 1).
	if ship._double_fire_shots_remaining > 0:
		ship._double_fire_shots_remaining -= 1
		var half_offset := weapon.charged_double_fire_offset / 2.0
		_spawn_projectile(weapon, ship, 0.0, 1.0, Vector2(0.0, -half_offset))
		_spawn_projectile(weapon, ship, 0.0, 1.0, Vector2(0.0, half_offset))
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

## Charged fire (2026-08-09) — the empowered variant released after holding
## Tir past WeaponData.charge_fire_duration, per Camil's per-character "tir
## charge" pass. Mirrors _on_weapon_fired()'s burst-spawning shape but reads
## the charged_* fields instead, so any weapon's charged release can be a
## different pattern (a straight staggered burst, a wide fan, a single
## empowered shot, ...) purely via data.
func _on_charged_weapon_fired(weapon: WeaponData, ship: ShipNode) -> void:
	if weapon.effect_type == "beam":
		var duration := weapon.charged_beam_duration if weapon.charged_beam_duration > 0.0 else weapon.beam_duration
		_spawn_timed_beam(weapon, ship, duration, weapon.charged_beam_thickness_multiplier)
		# 2026-08-10, Camil: "le gros laser est TRES puissant... reduire la
		# vitesse a 60% le temps du gros laser, histoire que l'adversaire
		# puisse un peu s'echapper" — shooter self-slow for the beam's whole
		# lifetime, so Zoneur can't keep perfectly tracking a dodging target.
		if weapon.charged_beam_shooter_slow_multiplier < 1.0:
			ship.apply_charged_beam_slow(duration, weapon.charged_beam_shooter_slow_multiplier)
		return
	if weapon.charged_double_fire_shots > 0:
		# Mitrailleur (2026-08-09) — a pure self-buff, no projectile at all;
		# see ShipNode.grant_double_fire() and _on_weapon_fired()'s consuming side.
		ship.grant_double_fire(weapon.charged_double_fire_shots)
		return
	if weapon.charged_projectile_count <= 1:
		# Perturbateur (2026-08-10): "plus on charge, plus le boomerang va
		# loin, jusqu'au fond du camp adverse" — the charged release just
		# sends it much further out before it curves back.
		_spawn_projectile(weapon, ship, 0.0, weapon.charged_speed_multiplier, Vector2.ZERO, weapon.charged_boomerang_out_duration)
		return
	for i in weapon.charged_projectile_count:
		var p := float(i) / float(maxi(weapon.charged_projectile_count - 1, 1))
		# Spreader (2026-08-09): "balayer de haut en bas puis remonter de bas
		# en haut" — a triangle wave (0 -> 1 -> 0 as p goes 0 -> 0.5 -> 1)
		# instead of the usual one-way linear sweep, so the burst goes out to
		# one extreme and back within the same charge release.
		var t := (1.0 - absf(2.0 * p - 1.0)) if weapon.charged_burst_ping_pong else p
		var angle_offset := lerpf(-weapon.charged_burst_spread_deg / 2.0, weapon.charged_burst_spread_deg / 2.0, t)
		if weapon.charged_stagger > 0.0 and i > 0:
			get_tree().create_timer(i * weapon.charged_stagger).timeout.connect(
				_spawn_projectile.bind(weapon, ship, angle_offset, weapon.charged_speed_multiplier)
			)
		else:
			_spawn_projectile(weapon, ship, angle_offset, weapon.charged_speed_multiplier)

func _spawn_projectile(weapon: WeaponData, ship: ShipNode, angle_offset_deg: float, speed_multiplier: float = 1.0, position_offset: Vector2 = Vector2.ZERO, boomerang_out_duration_override: float = 0.0) -> void:
	if not is_instance_valid(ship):
		return # round may have reset mid-burst-stagger

	var projectile := ProjectileNode.new()
	projectile.position = ship.position + position_offset # Mitrailleur's double-fire (2026-08-09): two parallel shots, offset vertically instead of angularly
	var direction := 1.0 if ship.side == 0 else -1.0
	var spread_deg := angle_offset_deg
	# Random per-shot jitter is for single-projectile sprays (machine gun) —
	# a multi-projectile burst already has its own deliberate fan geometry
	# (burst_spread_deg), so layering jitter on top just made it wobble
	# instead of reading as a clean, repeatable pattern (2026-08-06 playtest:
	# "pas de random sur les angles" for the Éventail fan).
	if not weapon.is_heavy and weapon.projectile_count <= 1:
		spread_deg += randf_range(-weapon.spread_deg, weapon.spread_deg)
	var shot_velocity := Vector2(direction * weapon.projectile_speed * speed_multiplier, 0.0).rotated(deg_to_rad(spread_deg))
	projectile.velocity = shot_velocity
	projectile.spin_speed = weapon.projectile_spin_speed
	projectile.is_looping = weapon.is_looping
	projectile.loop_radius = weapon.loop_radius
	projectile.loop_angular_speed = weapon.loop_angular_speed
	projectile.flip_h = direction < 0.0
	if weapon.id == "vortex":
		projectile.textures = VORTEX_TEXTURES # Vif's Tourbillon — 3-frame spin animation (wind1-3), loops via is_looping instead of a node rotation
		projectile.visual_scale = 2.4 # 2026-08-09 playtest: "tu peux doubler la taille des tourbillons" (was 1.2)
	elif weapon.id == "mini_shot":
		projectile.textures = BONBON_TEXTURES # Mini/Éventail — spins via projectile_spin_speed (mini_shot.tres), no multi-frame cycle
		projectile.visual_scale = 1.0
	elif weapon.id == "stun_boomerang":
		projectile.textures = BOOMERANG_TEXTURES
		projectile.visual_scale = 1.4
	elif weapon.is_heavy:
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
		var out_duration := boomerang_out_duration_override
		if out_duration <= 0.0:
			out_duration = weapon.boomerang_out_duration # 0 here too just leaves ProjectileNode's own built-in default in place
		if out_duration > 0.0:
			projectile.boomerang_out_duration = out_duration
		# 2026-08-10: lifetime needs to scale with range — a charged throw
		# that goes "jusqu'au fond du camp adverse" needs a lot more than the
		# flat 3.0s a normal short arc gets, or it expires mid-flight home.
		var effective_out := projectile.boomerang_out_duration
		projectile.lifetime = maxf(3.0, effective_out * 4.0 + 1.0)
	add_child(projectile)

## 2026-08-09 redesign (Zoneur: "un laser qui traverse toute la map, mais
## qui ne dure que 0.5 secondes... cooldown 0.8 seconde. Le tir charge
## lache le gros laser, qui dure 3 secondes... et est 2 fois plus epais.")
## A self-contained, timed pulse — spawn-and-forget like a normal
## projectile, no per-frame polling/lifecycle ownership needed anymore
## (BeamNode manages its own countdown and fades/despawns itself).
func _spawn_timed_beam(weapon: WeaponData, ship: ShipNode, duration: float, thickness_multiplier: float) -> void:
	var target := ship_2 if ship == ship_1 else ship_1
	var beam := BeamNode.new()
	beam.shooter = ship
	beam.target = target
	beam.arena_bounds = Rect2(arena_origin, arena_size)
	beam.weapon = weapon # must be set before add_child() — add_child() calls _ready() synchronously, which reads weapon.beam_range (2026-08-09 bug history)
	beam.lifetime = duration
	beam.thickness_multiplier = thickness_multiplier
	var tint := _weapon_tint(weapon.id)
	beam.color = Color(tint.r, tint.g, tint.b, 0.7) # translucent — _weapon_tint returns opaque colors
	add_child(beam)

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
			# 2026-08-08 bug report: "l'IA continue à bouger" after the match
			# ends — nothing previously froze ships/ball once match_over
			# flips, so an AI opponent kept wandering/firing on its own
			# through the "Victoire !"/"Match termine" pause. Same freeze
			# already used for the pre-match ready gate.
			ship_1.active = false
			ship_2.active = false
			ball.active = false
			for extra in _extra_balls:
				if is_instance_valid(extra):
					extra.active = false
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
## the organizer completes the campaign run) and returns to either
## MiniBranchMap (more fights left in this branch) or CampaignMap (branch
## complete, or this was the organizer fight). A loss is never punished
## beyond a retry of the SAME step (2026-08-08, Camil: "on ne peut jamais
## reculer") — branch_step itself never moves backward.
func _resolve_campaign_result(winner_side: int) -> void:
	var character_id: String = CampaignContext.campaign.character.id

	if CampaignContext.debug_encounter:
		# Cheat menu (2026-08-09) — no currency/unlock/progression side
		# effects, just report the result and bounce straight back so the
		# twist can be swapped and re-tested immediately.
		match_label.text = "Victoire" if winner_side == 0 else "Defaite"
		await get_tree().create_timer(1.5).timeout
		CampaignContext.clear()
		get_tree().change_scene_to_file("res://scenes/CampaignCheatMenu.tscn")
		return

	if winner_side != 0: # side 1 (the mook/rival/organizer) won — no permadeath, retry the same step (Story 4.4 AC)
		match_label.text = "Defaite..."
		await get_tree().create_timer(2.0).timeout
		if CampaignContext.is_organizer_fight:
			CampaignContext.clear()
			get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/MiniBranchMap.tscn")
		return

	if CampaignContext.is_organizer_fight:
		CampaignSave.mark_organizer_defeated(character_id)
		match_label.text = "Tournoi remporte !"
		await get_tree().create_timer(2.0).timeout
		CampaignContext.clear()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		return

	var current_encounter := CampaignContext.current_encounter()
	if current_encounter.is_mook:
		CampaignSave.add_currency(character_id, current_encounter.reward_currency)
		match_label.text = "Victoire (+%d)" % current_encounter.reward_currency
	else:
		# The "real" rival, defeated.
		var unlock_id := ""
		if current_encounter.unlock_reward:
			unlock_id = current_encounter.unlock_reward.id
		CampaignSave.mark_branch_completed(character_id, CampaignContext.branch.id, unlock_id)
		match_label.text = "Rival vaincu !"

	await get_tree().create_timer(1.5).timeout
	if CampaignContext.advance_branch_step():
		get_tree().change_scene_to_file("res://scenes/MiniBranchMap.tscn") # visible progress, per Camil's mini-map request — not a silent reload straight into the next fight
	else:
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
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null

func _update_round_label() -> void:
	round_label.text = "Round %d - %d" % [match_state.rounds_won[0], match_state.rounds_won[1]]

## Epic 4 — makes the active campaign encounter and twist legible on the HUD
## (2026-08-08 bug report: "je ne vois toujours pas de twist" — some twists
## like gauge_floor have no other visible tell at all, and seeing the same
## opponent for mook_1/mook_2 back to back otherwise reads as a stuck loop
## rather than the intended pacing beat).
func _update_campaign_label() -> void:
	if not _campaign_mode:
		campaign_label.text = ""
		return
	var encounter_name := "Organisateur du tournoi"
	if CampaignContext.debug_encounter:
		# Cheat menu (2026-08-09) — neither organizer nor branch is set here,
		# just a throwaway encounter; branch_step's step-name labeling
		# doesn't apply (2026-08-09 bug: crashed on CampaignContext.branch
		# being null, since debug fights are a third case that "not
		# is_organizer_fight" alone didn't account for).
		encounter_name = "Cheat menu — vs %s" % CampaignContext.debug_encounter.opponent.display_name
	elif not CampaignContext.is_organizer_fight:
		# branch_step (2026-08-08 rework) instead of comparing encounter
		# resource identity against branch.mook_1/mook_2 — unambiguous
		# regardless of how those two are authored.
		var step_names := ["Sous-adversaire 1/2", "Sous-adversaire 2/2", "Rival"]
		var step: String = step_names[clampi(CampaignContext.branch_step, 0, 2)]
		encounter_name = "%s — %s" % [CampaignContext.branch.display_name, step]
	var twist_text := ""
	if active_twist:
		twist_text = " | Twist : %s" % active_twist.display_name
	campaign_label.text = "%s%s" % [encounter_name, twist_text]

## Story 1.12 — F1 toggles a basic AI opponent on/off for Ship2, so solo
## testing doesn't require editing the scene.
func _process_ai_toggle() -> void:
	# 2026-08-08 bug report: "si j'appuie sur F1 en mode campagne, l'IA se
	# désactive" — this debug toggle (Story 1.12) exists so a solo dev can
	# test the 1v1 flow without a second human. A campaign mook/rival/
	# organizer has no second human to hand control to, ever — F1 must be a
	# no-op here instead of turning the opponent off.
	if _campaign_mode:
		return
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

## 2026-08-09 bug report (Camil, cheat-menu testing): "Le twist zone qui
## retrecit ne marche pas" — _sync_arena_bounds_to_entities()/
## _sync_frontier_x_to_entities() below were correctly updating the
## COLLISION bounds every twist tick, but nothing ever moved the
## Background/NeutralZone/CenterLine visuals, which stayed at their
## scene-authored full-size positions forever — the shrink/drift was real
## but completely invisible, indistinguishable from "not working". Called
## every frame from _process() so it stays correct for shrinking_arena AND
## drifting_neutral_zone (and is a harmless no-op the rest of the time,
## since _current_arena_bounds/_current_frontier_x already default to the
## untwisted values).
func _sync_twist_visuals() -> void:
	background.offset_left = _current_arena_bounds.position.x
	background.offset_top = _current_arena_bounds.position.y
	background.offset_right = _current_arena_bounds.position.x + _current_arena_bounds.size.x
	background.offset_bottom = _current_arena_bounds.position.y + _current_arena_bounds.size.y

	var half_width := ShipState.NEUTRAL_ZONE_HALF_WIDTH
	neutral_zone_visual.offset_left = _current_frontier_x - half_width
	neutral_zone_visual.offset_right = _current_frontier_x + half_width
	neutral_zone_visual.offset_top = _current_arena_bounds.position.y
	neutral_zone_visual.offset_bottom = _current_arena_bounds.position.y + _current_arena_bounds.size.y

	center_line.points = PackedVector2Array([
		Vector2(_current_frontier_x, _current_arena_bounds.position.y),
		Vector2(_current_frontier_x, _current_arena_bounds.position.y + _current_arena_bounds.size.y),
	])

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
	# 2026-08-09 bug report (Camil, cheat-menu test): "Billes d'energie...
	# ca apparait dans le no man's land" — spawning exactly on
	# _current_frontier_x put the orb inside the neutral strip neither ship
	# can ever enter (ShipState._clamp_to_half() keeps a NEUTRAL_ZONE_HALF_
	# WIDTH gap around the frontier), making it permanently unreachable.
	# Spawn on a random side's actual playable half instead — alternates
	# fairly between sides over repeated spawns.
	var side := randi() % 2
	var margin := ShipState.NEUTRAL_ZONE_HALF_WIDTH + 40.0
	var x: float
	if side == 0:
		x = randf_range(_current_arena_bounds.position.x + 40.0, _current_frontier_x - margin)
	else:
		x = randf_range(_current_frontier_x + margin, _current_arena_bounds.position.x + _current_arena_bounds.size.x - 40.0)
	orb.position = Vector2(
		x,
		randf_range(_current_arena_bounds.position.y + 60.0, _current_arena_bounds.position.y + _current_arena_bounds.size.y - 60.0)
	)
	add_child(orb)
