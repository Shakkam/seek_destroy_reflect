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

@onready var round_label: Label = $DebugHUD/RoundLabel
@onready var match_label: Label = $DebugHUD/MatchLabel
@onready var ai_status_label: Label = $DebugHUD/AIStatusLabel
@onready var p1_hp_fill: ColorRect = $DebugHUD/P1HPBarFill
@onready var p2_hp_fill: ColorRect = $DebugHUD/P2HPBarFill
@onready var p1_ultra_meter: UltraMeterNode = $DebugHUD/P1UltraMeter
@onready var p2_ultra_meter: UltraMeterNode = $DebugHUD/P2UltraMeter
@onready var ready_label: Label = $DebugHUD/ReadyLabel
@onready var campaign_label: Label = $DebugHUD/CampaignLabel
@onready var debug_hud: CanvasLayer = $DebugHUD
# 2026-08-16 UX audit (Sally) — replaces the old "PV: 100 / Mitraillette /
# Jauge: 0/100" plain-text readout (see the removed _debug_text()) with a
# per-weapon color swatch + a real gauge bar, same bar language the HP
# bar/ultra meter already use. See _update_weapon_hud().
@onready var p1_weapon_swatch: ColorRect = $DebugHUD/P1WeaponSwatch
@onready var p1_weapon_name: Label = $DebugHUD/P1WeaponName
@onready var p1_gauge_fill: ColorRect = $DebugHUD/P1GaugeBarFill
@onready var p1_heat_fill: ColorRect = $DebugHUD/P1HeatBarFill
@onready var p1_buff_label: Label = $DebugHUD/P1BuffLabel
@onready var p2_weapon_swatch: ColorRect = $DebugHUD/P2WeaponSwatch
@onready var p2_weapon_name: Label = $DebugHUD/P2WeaponName
@onready var p2_gauge_fill: ColorRect = $DebugHUD/P2GaugeBarFill
@onready var p2_heat_fill: ColorRect = $DebugHUD/P2HeatBarFill
@onready var p2_buff_label: Label = $DebugHUD/P2BuffLabel
# 2026-08-16 UX audit (Sally) — "Versus mode ends in a dead screen": see
# _show_post_match_choice()/_process_post_match_choice().
@onready var post_match_label: Label = $DebugHUD/PostMatchLabel
# 2026-08-16 (Camil: "on pourrait ajouter 'vous avez gagne XXXXX' => icone
# + nom + description de l'arme") — shown alongside "Rival vaincu !" on a
# real rival win, see _resolve_campaign_result().
@onready var reward_icon: ColorRect = $DebugHUD/RewardIcon
@onready var reward_label: Label = $DebugHUD/RewardLabel
# 2026-08-16 UX audit (Sally) — "the full control legend is glued to the
# screen, forever": see _begin_round_ready_gate(), now hides these after
# round 1.
@onready var controls_p1: Label = $DebugHUD/ControlsP1
@onready var controls_p2: Label = $DebugHUD/ControlsP2
@onready var background: ColorRect = $Background
@onready var neutral_zone_visual: ColorRect = $NeutralZone
@onready var center_line: Line2D = $CenterLine

const HP_BAR_WIDTH := 240.0
# 2026-08-13 (Camil: "on a bien le 'go!' mais pas 'Ready...... go !'.
# Donc y'a bien 2 steps. Ready (1.5 secondes) Go ! 1 sec") — a real two-
# phase beat, not a single flash: "Ready..." holds first, THEN "GO !".
const READY_FLASH_DURATION := 1.5
const GO_FLASH_DURATION := 1.0 # was a single 0.6s flash before the two-phase split

var match_state: MatchState = MatchState.new()
var _round_active := true
var _ai_toggle_prev := false
var _escape_prev := false

# 2026-08-16 UX audit (Sally): "Versus mode ends in a dead screen" — on a
# non-campaign match end, the arena used to just sit on "Match termine..."
# forever with no way back to anything. Same up/down + confirm scheme as
# every other menu in the project (TitleScreenNode/CampaignMapNode), shown
# a beat after the result so it reads on its own first — see
# _show_post_match_choice()/_process_post_match_choice().
const POST_MATCH_CHOICES := ["Revanche", "Choix des personnages"]
var _post_match_choice_active := false
var _post_match_choice_index := 0
var _post_match_move_prev := 0.0
var _post_match_confirm_prev := true # seeded true — same held-key carryover guard as every other menu (2026-08-08 bug pattern)

# Dev-only in-match cheat keys (2026-08-13, Camil: "des cheats shortcuts
# pour tests ingame") — global, not per-player-device-scoped, same
# convention as F1 (AI toggle)/TAB (hitbox overlay). Always target ship_1
# as "self"/the tester and ship_2 as "the opponent", mirroring how F1's
# AI toggle only ever touches ship_2 — matches the assumption a solo dev
# is testing AS Player 1 against an AI or a second human on ship_2.
var _cheat_kill_prev := false
var _cheat_ultra_prev := false
var _cheat_ammo_prev := false

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

# Pre-round gate (2026-08-01, extended 2026-08-13 to a real two-phase
# "Ready...Go!" beat and to every round, not just round 1). True while
# the current round's gameplay is actually unfrozen; false while sitting
# in the ready/READY/GO gate (see _begin_round_ready_gate()/
# _process_ready_gate()).
var _round_playing := false
enum RoundStartPhase { WAITING_FOR_INPUT, READY_FLASH, GO_FLASH }
var _round_start_phase := RoundStartPhase.WAITING_FOR_INPUT
var _round_start_phase_timer := 0.0

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

	# Epic 4 reward system (2026-08-16) — after every character-assignment
	# path above has settled (MatchSetup/CharacterSelect, or the campaign
	# override just above), wire up whatever each ship's character has
	# unlocked so far.
	_setup_passive_rewards(ship_1)
	_setup_passive_rewards(ship_2)

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
	# 2026-08-15 (Camil): the gauge-fill effect's yellow ball needs to aim
	# at the actual next-empty ultra pip, not an approximate anchor point.
	ball.p1_ultra_meter = p1_ultra_meter
	ball.p2_ultra_meter = p2_ultra_meter

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
	ship_1.ultra_triggered.connect(_on_ultra_triggered.bind(ship_1))
	ship_2.ultra_triggered.connect(_on_ultra_triggered.bind(ship_2))
	ship_1.ultra_denied.connect(p1_ultra_meter.flash_denied)
	ship_2.ultra_denied.connect(p2_ultra_meter.flash_denied)

	_update_round_label()
	_begin_round_ready_gate()

func _process(delta: float) -> void:
	_update_weapon_hud(ship_1, p1_weapon_swatch, p1_weapon_name, p1_gauge_fill, p1_heat_fill, p1_buff_label)
	_update_weapon_hud(ship_2, p2_weapon_swatch, p2_weapon_name, p2_gauge_fill, p2_heat_fill, p2_buff_label)
	p1_hp_fill.size.x = HP_BAR_WIDTH * clampf(ship_1.state.hp / ship_1.max_hp_override, 0.0, 1.0)
	p2_hp_fill.size.x = HP_BAR_WIDTH * clampf(ship_2.state.hp / ship_2.max_hp_override, 0.0, 1.0)
	p1_ultra_meter.pips = ship_1.weapon_state.ultra_pips
	p2_ultra_meter.pips = ship_2.weapon_state.ultra_pips

	_process_ai_toggle()
	_process_cheat_keys()
	_process_escape()
	_sync_twist_visuals()

	if _post_match_choice_active:
		_process_post_match_choice()
		return

	if not _round_playing:
		_process_ready_gate(delta)
		return

	_check_round_end()

func _physics_process(delta: float) -> void:
	if active_twist and _round_playing and _round_active:
		_process_twist(delta)

## Freezes ships/ball and shows the "Pret ?" label — called once from
## _ready() (round 1) AND again from _check_round_end() before every
## following round (2026-08-13: Sally's 2026-08-11 UX review flagged round
## 1's instant, pacing-less start; re-checking round TRANSITIONS while
## fixing it surfaced they had no gate at ALL, not even round 1's original
## single "press Tir" — HP/gauges reset but ships/ball never re-froze, so
## round 2/3 began the instant round 1 ended). Same freeze either way.
func _begin_round_ready_gate() -> void:
	_round_playing = false
	_round_start_phase = RoundStartPhase.WAITING_FOR_INPUT
	ship_1.active = false
	ship_2.active = false
	ball.active = false
	for extra in _extra_balls: # multi_ball twist — extra balls stay in sync with the primary's active flag (see _spawn_extra_balls)
		if is_instance_valid(extra):
			extra.active = false
	ready_label.remove_theme_font_size_override("font_size")
	ready_label.remove_theme_color_override("font_color")
	var round_number := match_state.rounds_won[0] + match_state.rounds_won[1] + 1
	ready_label.text = "Round %d\nPret ? (appuyez sur Tir pour commencer)" % round_number
	# 2026-08-16 UX audit (Sally): "the full control legend is glued to the
	# screen, forever" — both players' entire key list used to sit fixed at
	# the bottom of every single match. Round 1 still gets the full
	# reference (that's exactly when it's needed); round 2 onward, players
	# already know their keys, so it steps aside instead of sitting as
	# permanent clutter under the action.
	controls_p1.visible = round_number == 1
	controls_p2.visible = round_number == 1

## Pre-round gate — waits for either player's fire input (keyboard or
## gamepad trigger, device 0 or 1), then runs the two-phase "Ready...Go!"
## beat (READY_FLASH_DURATION, then GO_FLASH_DURATION) before actually
## unfreezing, replacing the old instant press-to-unfreeze.
func _process_ready_gate(delta: float) -> void:
	match _round_start_phase:
		RoundStartPhase.WAITING_FOR_INPUT:
			var pressed := Input.is_physical_key_pressed(KEY_SPACE) \
				or Input.is_physical_key_pressed(KEY_ENTER) \
				or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
				or Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.4
			if not pressed:
				return
			_round_start_phase = RoundStartPhase.READY_FLASH
			_round_start_phase_timer = READY_FLASH_DURATION
			ready_label.text = "Ready......"
		RoundStartPhase.READY_FLASH:
			_round_start_phase_timer -= delta
			if _round_start_phase_timer <= 0.0:
				_round_start_phase = RoundStartPhase.GO_FLASH
				_round_start_phase_timer = GO_FLASH_DURATION
				ready_label.add_theme_font_size_override("font_size", 48) # bigger for the flash
				ready_label.add_theme_color_override("font_color", Color(1, 0.84, 0.29, 1)) # same gold as MatchLabel's "Victoire !"/"Match termine" announcements
				ready_label.text = "GO !"
		RoundStartPhase.GO_FLASH:
			_round_start_phase_timer -= delta
			if _round_start_phase_timer <= 0.0:
				_unfreeze_round()

func _unfreeze_round() -> void:
	_round_start_phase = RoundStartPhase.WAITING_FOR_INPUT
	_round_playing = true
	ship_1.active = true
	ship_2.active = true
	ball.active = true
	for extra in _extra_balls:
		if is_instance_valid(extra):
			extra.active = true
	ready_label.text = ""

## 2026-08-16 UX audit (Sally): "the entire in-match HUD is a literal node
## named DebugHUD" — replaces the old plain-text "PV: 100 / Mitraillette /
## Jauge: 0/100" readout (the removed _debug_text()) with a color swatch
## (the SAME tint _weapon_tint() already gives that weapon's own
## projectiles, so the HUD and the actual shots on screen read as the same
## thing) and a real gauge bar instead of a bare fraction — same bar
## language the HP bar/ultra meter already use.
## Always reads the SELECTED weapon only, not the whole kit: every roster
## character carries exactly one weapon (see smoke_test.gd's "no two
## characters share the same weapon" check) — the multi-weapon kit is Epic
## 1 placeholder scaffolding that only shows up running MatchArena.tscn
## directly with no character assigned, not something a real player sees.
func _update_weapon_hud(ship: ShipNode, swatch: ColorRect, name_label: Label, gauge_fill: ColorRect, heat_fill: ColorRect, buff_label: Label) -> void:
	var index := ship.weapon_state.selected_index
	if index < 0 or index >= ship.weapon_state.kit.size():
		return
	var weapon: WeaponData = ship.weapon_state.kit[index]
	var tint := _weapon_tint(weapon.id)
	swatch.color = tint
	name_label.text = weapon.display_name
	var gauge_ratio := clampf(ship.weapon_state.gauges[index] / weapon.gauge_max, 0.0, 1.0) if weapon.gauge_max > 0.0 else 0.0
	gauge_fill.color = tint
	gauge_fill.size.x = HP_BAR_WIDTH * gauge_ratio
	# 2026-08-09 (Camil: "il faudrait une petite jauge de cooldown qui
	# descend des qu'on tire") — a real bar now instead of the old
	# "[chauffe %d/%d]" text tag; only Mitraillette (machine_gun) carries
	# heat_max > 0, everyone else's bar just stays hidden.
	if weapon.heat_max > 0.0:
		heat_fill.visible = true
		heat_fill.size.x = HP_BAR_WIDTH * clampf(ship.weapon_state.heats[index] / weapon.heat_max, 0.0, 1.0)
	else:
		heat_fill.visible = false
	# Mitrailleur's charged-fire buff (2026-08-09): "un petit icone se met a
	# cote de la barre pour indiquer qu'on est en mode double tir" — still a
	# text tag (no icon-graphics system exists yet), but it's the only text
	# left in this whole widget now instead of three lines of readout.
	buff_label.text = "DOUBLE x%d" % ship._double_fire_shots_remaining if ship._double_fire_shots_remaining > 0 else ""

func _on_gauge_filled(amount: float, ship: ShipNode) -> void:
	var popup := FloatingTextNode.new()
	popup.position = ship.position + Vector2(0.0, -16.0)
	popup.text = "+%d" % int(amount)
	add_child(popup)

# "Systeme des 5 balles" (2026-08-13 party-mode brainstorm, Epic 4 memlog)
# — per-character Ultra dispatch. Roster locked in that session; built
# incrementally here, one character at a time (same cadence as the
# original per-character weapon rollout), falling back to a flat generic
# placeholder for anyone not implemented yet. Named "ultra" not "super"
# — collides with the GDD's existing "arme 'super'/lourde" weapon-tier
# naming otherwise. Locked design pattern for every Ultra: always some
# guaranteed damage (applied directly, bypassing weapons/projectiles) +
# a larger, genuinely dodgeable-by-movement part — never 100% avoidable,
# never a pure coin-flip.
const GENERIC_ULTRA_DAMAGE := 25.0 # fallback for any character without a bespoke Ultra yet
const ULTRA_LA_MEUTE := preload("res://data/weapons/ultra_la_meute.tres")
const ULTRA_PLUIE_DE_BONBONS := preload("res://data/weapons/ultra_pluie_de_bonbons.tres")
const ULTRA_MITRAILLEUSES_SATELLITES := preload("res://data/weapons/ultra_mitrailleuses_satellites.tres")

## 2026-08-14 (Camil): "quand un ultra se declenche, le jeu se met en
## pause. une barre blanche et le mot 'ultra' arrivent de la droite, le
## perso en -image arrive de la gauche... puis [ils] sortent... le jeu se
## de-freeze et l'ULTRA se lance." Freezes ships/ball (same freeze
## ShipNode/BallNode already read via `active`), plays UltraIntroNode to
## completion, unfreezes, THEN resolves the actual effect — the intro
## gates the attack, it doesn't just play alongside it.
func _on_ultra_triggered(ship: ShipNode) -> void:
	ship_1.active = false
	ship_2.active = false
	ball.active = false
	for extra in _extra_balls:
		if is_instance_valid(extra):
			extra.active = false

	var intro := UltraIntroNode.new()
	intro.character = ship.character
	debug_hud.add_child(intro) # inside the CanvasLayer, not the world-space root, so it draws over the HP bars/labels too — this is meant to cover the whole screen
	await intro.finished
	intro.queue_free()

	if not is_instance_valid(ship) or not _round_playing:
		return # round ended/reset mid-intro (e.g. the K cheat, or a real KO landing from elsewhere) — bail out rather than un-freezing into a stale state or firing a stale ultra
	ship_1.active = true
	ship_2.active = true
	ball.active = true
	for extra in _extra_balls:
		if is_instance_valid(extra):
			extra.active = true
	_resolve_ultra_effect(ship)
	_apply_perturbateur_ultra_passive(ship)

## Epic 4 reward system (2026-08-16, Camil: "lors de l'ultra du joueur,
## applique aussi le brouillage, mais uniquement 5 sec") — Perturbateur's
## passive, unlike every other reward, isn't tied to a timer or a weapon
## id at all: reactive, re-checked live every time THIS ship triggers ITS
## OWN Ultra (any character's), stacking a short control-scramble onto
## whatever that Ultra already did. No state needs to persist between
## casts, so this just re-queries CampaignSave directly rather than
## caching anything from _setup_passive_rewards().
func _apply_perturbateur_ultra_passive(ship: ShipNode) -> void:
	if not is_instance_valid(ship) or not ship.character:
		return
	if "stun_boomerang" not in CampaignSave.unlocks_for(ship.character.id):
		return
	var opponent := ship_2 if ship == ship_1 else ship_1
	if is_instance_valid(opponent):
		opponent.apply_control_scramble(PASSIVE_PERTURBATEUR_ULTRA_SCRAMBLE_DURATION)

func _resolve_ultra_effect(ship: ShipNode) -> void:
	var opponent := ship_2 if ship == ship_1 else ship_1
	var character_id := ship.character.id if ship.character else ""
	match character_id:
		"missiles": # Traqueur
			_ultra_la_meute(ship, opponent)
		"lourd": # Lourd
			_ultra_pluie_de_scuds(ship, opponent)
		"mini": # Spreader
			_ultra_pluie_de_bonbons(ship, opponent)
		"mitrailleur": # Mitrailleur
			_ultra_mitrailleuses_satellites(ship, opponent)
		"zoneur": # Zoneur
			_ultra_grille_laser(ship, opponent)
		"controleur": # Contrôleur
			_ultra_trou_noir(ship, opponent)
		"perturbateur": # Perturbateur
			_ultra_brouillage_de_commandes(ship, opponent)
		"vif": # Vif
			_ultra_bourrasque(ship, opponent)
		_:
			opponent.apply_damage(GENERIC_ULTRA_DAMAGE) # placeholder until this character's Ultra is designed/built

## Traqueur's Ultra — "La Meute" (2026-08-13 Epic 4 memlog: "missiles qui
## pourchassent, resserrent avec le temps"). A guaranteed-floor hit (the
## pack always gets at least one bite in) plus a big, more aggressively-
## homing missile swarm than her base kit (ultra_la_meute.tres:
## homing_strength 3.2 vs. homing_missile.tres's 2.0) — ProjectileNode's
## homing already re-reads the live target position every tick, so the
## stronger value alone reads as the pack "tightening" its aim as it
## closes in, no new engine code needed.
const LA_MEUTE_GUARANTEED_DAMAGE := 8.0
# LA_MEUTE_LIFETIME/EXPLOSION_RADIUS/EXPLOSION_DAMAGE (missile lifetime x2,
# small on-timeout blast) moved to ProjectileFactory.spawn() 2026-08-18 —
# only ever consumed there, see its own doc comments for the history.

func _ultra_la_meute(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(LA_MEUTE_GUARANTEED_DAMAGE)
	for i in ULTRA_LA_MEUTE.projectile_count:
		var p := float(i) / float(maxi(ULTRA_LA_MEUTE.projectile_count - 1, 1))
		var angle_offset := lerpf(-ULTRA_LA_MEUTE.burst_spread_deg / 2.0, ULTRA_LA_MEUTE.burst_spread_deg / 2.0, p)
		if ULTRA_LA_MEUTE.burst_stagger > 0.0 and i > 0:
			get_tree().create_timer(i * ULTRA_LA_MEUTE.burst_stagger).timeout.connect(_spawn_projectile.bind(ULTRA_LA_MEUTE, ship, angle_offset))
		else:
			_spawn_projectile(ULTRA_LA_MEUTE, ship, angle_offset)

## Lourd's Ultra — "Pluie de Scuds" (reworked 2026-08-15, Camil: "il
## envoie juste quelques missiles: bof. j'aurais plus vu une pluie de
## missiles qui arrivent du haut... ca doit etre tres dur a eviter. On peut
## faire apparaitre petit a petit des cibles au sol, et le missile arrive du
## haut et tombe dans la cible en 1/2s. L'explosion de chaque missile
## pourrait provoquer une petite vague de push autour du point d'impact,
## donc degats de zone."). Same guaranteed-floor-plus-dodgeable-bulk
## pattern as every Ultra, but the bulk is now a genuine field bombardment:
## MISSILE_COUNT reticles land across the opponent's ENTIRE half (not a
## narrow spread from Lourd's own position like the old shell burst), each
## telegraphed for FALL_DURATION by a MissileStrikeNode (closing ring +
## shrinking shell), staggered STAGGER apart so they keep raining down
## rather than all landing near-simultaneously — one alone is trivial to
## sidestep, but weaving between 20 is the actual challenge.
const PLUIE_DE_SCUDS_GUARANTEED_DAMAGE := 8.0
const PLUIE_DE_SCUDS_MISSILE_COUNT := 50 # 2026-08-15 playtest (Camil): 20 -> 25 ("5 de plus"), then "j'arrive encore a eviter. Multiplie par 2 le nombre de scuds. C'est un ultra, faut que ca poutre." -> x2
const PLUIE_DE_SCUDS_STAGGER := 0.1
const PLUIE_DE_SCUDS_FALL_DURATION := 1.0 / 3.0 # 2026-08-15 playtest: "au lieu de 1/2 seconde pour tomber, tu peux faire 1/3 de seconde. Plus dur a eviter." — was 0.5
const PLUIE_DE_SCUDS_IMPACT_RADIUS := 82.5 # 2026-08-15 playtest: bumped from 40 then 55, now x1.5 again ("cercles rouge plus gros x1.5, zone d'impact x1.5") — the closing ring and the hit radius are the same field, so one bump covers both
const PLUIE_DE_SCUDS_IMPACT_DAMAGE := 6.0 # 2026-08-15 playtest: x1.5 ("degats x1.5 aussi") — was 4.0
const PLUIE_DE_SCUDS_IMPACT_PUSH := 30.0
const PLUIE_DE_SCUDS_TARGET_MARGIN := 40.0 # keeps target reticles off the arena's outer walls

func _ultra_pluie_de_scuds(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(PLUIE_DE_SCUDS_GUARANTEED_DAMAGE)
	var bounds := Rect2(arena_origin, arena_size)
	var min_x := bounds.position.x + PLUIE_DE_SCUDS_TARGET_MARGIN if opponent.side == 0 else _current_frontier_x
	var max_x := _current_frontier_x if opponent.side == 0 else bounds.position.x + bounds.size.x - PLUIE_DE_SCUDS_TARGET_MARGIN
	var min_y := bounds.position.y + PLUIE_DE_SCUDS_TARGET_MARGIN
	var max_y := bounds.position.y + bounds.size.y - PLUIE_DE_SCUDS_TARGET_MARGIN
	for i in PLUIE_DE_SCUDS_MISSILE_COUNT:
		var target := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if i > 0:
			get_tree().create_timer(i * PLUIE_DE_SCUDS_STAGGER).timeout.connect(_spawn_missile_strike.bind(target, opponent))
		else:
			_spawn_missile_strike(target, opponent)

func _spawn_missile_strike(target: Vector2, opponent: ShipNode) -> void:
	if not is_instance_valid(opponent):
		return # the round/rally ended mid-rain (K cheat, a real KO from something else) — don't strike a freed/reset ship
	var missile := MissileStrikeNode.new()
	missile.target_position = target
	missile.fall_duration = PLUIE_DE_SCUDS_FALL_DURATION
	missile.impact_radius = PLUIE_DE_SCUDS_IMPACT_RADIUS
	missile.impact_damage = PLUIE_DE_SCUDS_IMPACT_DAMAGE
	missile.impact_push_distance = PLUIE_DE_SCUDS_IMPACT_PUSH
	missile.opponent = opponent
	add_child(missile)

## Spreader's Ultra — "Pluie de Bonbons" (2026-08-13 Epic 4 memlog: "pluie
## de bonbons (saturation totale de l'arene, contraste mignon/letal)");
## reworked 2026-08-15 (Camil: "je ne m'y suis toujours pas fait. Idee :
## faire tomber verticalement des eventails sur le champ adverse, en
## grand nombre et toujours avec un petit decalage (genre pluie verticale
## qui traverse l'ecran de haut en bas)"). The old horizontal fan
## diverged from Spreader's own fixed position — same core problem as
## Lourd's original shell burst — so most candies never got anywhere near
## a target at range. This drops PLUIE_DE_BONBONS_COUNT candies from
## above the OPPONENT's half, each at a random X with a random spawn
## delay ("petit decalage"), falling straight down — plain ProjectileNode
## instances built directly (not via _spawn_projectile(), which always
## launches horizontally off the shooter's own side) so "down" doesn't
## depend on shooter side at all. Then, same day: "j'en ferai tomber 2x
## plus. J'accelererai legerement la vitesse (1.3x plus rapide)."
const PLUIE_DE_BONBONS_GUARANTEED_DAMAGE := 8.0
const PLUIE_DE_BONBONS_COUNT := 40 # 2026-08-15 playtest: "j'en ferai tomber 2x plus" — was 20
const PLUIE_DE_BONBONS_SPAWN_WINDOW := 1.5
const PLUIE_DE_BONBONS_FALL_SPEED := 546.0 # 2026-08-15 playtest: "j'accelererai legerement la vitesse (1.3x plus rapide)" — was 420
const PLUIE_DE_BONBONS_MARGIN := 30.0 # keeps drops off the arena's left/right walls
# 2026-08-15 playtest: "je laisserai [les eventails] a taille normale" —
# already the case (visual_scale below reads ULTRA_PLUIE_DE_BONBONS.
# visual_scale_multiplier = 1.4, same as mini_shot.tres's normal fire),
# noted here so it's obvious this was a deliberate confirm, not an
# oversight, if it comes up again. "Attention a ne pas modifier le tir
# normal !" — this whole function/its helper are the only things that
# touch this Ultra; mini_shot.tres itself is never written to.

func _ultra_pluie_de_bonbons(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(PLUIE_DE_BONBONS_GUARANTEED_DAMAGE)
	var bounds := Rect2(arena_origin, arena_size)
	var min_x := bounds.position.x + PLUIE_DE_BONBONS_MARGIN if opponent.side == 0 else _current_frontier_x
	var max_x := _current_frontier_x if opponent.side == 0 else bounds.position.x + bounds.size.x - PLUIE_DE_BONBONS_MARGIN
	for i in PLUIE_DE_BONBONS_COUNT:
		var x := randf_range(min_x, max_x)
		var delay := randf_range(0.0, PLUIE_DE_BONBONS_SPAWN_WINDOW) # random, not evenly staggered — "un petit decalage" reads more like rain than a metronome
		if delay > 0.0:
			get_tree().create_timer(delay).timeout.connect(_spawn_bonbon_raindrop.bind(x, opponent))
		else:
			_spawn_bonbon_raindrop(x, opponent)

func _spawn_bonbon_raindrop(x: float, opponent: ShipNode) -> void:
	if not is_instance_valid(opponent):
		return # round/rally ended mid-spawn-window
	var bounds := Rect2(arena_origin, arena_size)
	var drop := ProjectileNode.new()
	drop.position = Vector2(x, bounds.position.y - 20.0)
	drop.velocity = Vector2(0.0, PLUIE_DE_BONBONS_FALL_SPEED)
	drop.damage = ULTRA_PLUIE_DE_BONBONS.damage
	drop.textures = ProjectileFactory.BONBON_TEXTURES
	drop.visual_scale = ULTRA_PLUIE_DE_BONBONS.visual_scale_multiplier
	drop.spin_speed = ULTRA_PLUIE_DE_BONBONS.projectile_spin_speed
	drop.target = opponent
	drop.lifetime = 3.0
	add_child(drop)

## Mitrailleur's Ultra — "Mitrailleuses Satellites" (2026-08-13 Epic 4
## memlog: "double full-auto temporaire"; reworked 2026-08-15, Camil: "les
## petites tourelles se mettent au bon endroit mais doivent suivre le
## vaisseau. Ensuite elles ne doivent pas tirer toutes seules : elles
## envoient des tirs de mitraillette quand on tire normalement", then
## again same day: "les tirs doivent etre des tirs normaux de
## mitraillette (la tu as mis des carres verts qui visent l'ennemi =>
## non)". Same guaranteed-floor pattern, then two escort TurretNodes
## spawn flanking him above/below purely as a visual/destructible
## presence (follow_ship keeps them locked to his position every tick,
## autofire=false — they never fire themselves via TurretNode._fire_at_
## target(), which aims directly at the target and has no sprite,
## reading as the reported "green squares that aim at the enemy").
## Actual shots are real _spawn_projectile() calls with his own weapon —
## same machine-gun sprite/straight-forward trajectory as his normal
## fire, just offset to originate from each satellite — triggered by his
## weapon_fired signal (NOT charged_weapon_fired — only normal fire
## echoes to the satellites).
const MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE := 8.0
const MITRAILLEUSES_SATELLITES_OFFSET_Y := 50.0

## ship -> Array[TurretNode], the CURRENT set of live satellites for
## whichever ship last cast this Ultra. 2026-08-15 bug report (Camil):
## "quand il a utilise son ultra, s'il le reutilise, les tirs des modules
## ne marchent plus" — the previous design connected a freshly-bind()'d
## _on_satellite_fire to ship.weapon_fired on every single cast, but
## connecting the same (self, "_on_satellite_fire") method to the same
## signal twice ERRORS in Godot (regardless of different bind() args, the
## duplicate check is keyed on the base method) — so the SECOND cast's
## connect() call silently failed, leaving the second wave of satellites
## permanently unwired. Fixed by wiring each ship's signals ONCE ever
## (guarded by set_meta(), checked below — a plain is_connected() can't
## guard a lambda the same way since each lambda is a distinct Callable
## every time one is created) and keeping the live turret list in this
## dictionary instead — re-casting just overwrites the entry.
var _satellite_turrets_by_ship: Dictionary = {}
const SATELLITE_FIRE_WIRED_META := "_satellite_fire_wired"

func _ultra_mitrailleuses_satellites(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE)
	var turrets: Array[TurretNode] = []
	for offset_y in [-MITRAILLEUSES_SATELLITES_OFFSET_Y, MITRAILLEUSES_SATELLITES_OFFSET_Y]:
		var turret := TurretNode.new()
		turret.follow_ship = ship
		turret.follow_offset = Vector2(0.0, offset_y)
		turret.autofire = false
		turret.weapon = ULTRA_MITRAILLEUSES_SATELLITES
		turret.target = opponent
		turret.owner_side = ship.side
		add_child(turret)
		turrets.append(turret)
	_satellite_turrets_by_ship[ship] = turrets
	# 2026-08-15 (Camil): "si on est en ultra + tir charge, il faut bien les
	# tirs sur les modules + les 2 tirs classiques du tir chargee" — echo on
	# BOTH normal fire and a charged release, not just normal fire. Lambdas
	# (not a bound method reference) so `ship` travels with the connection
	# without needing .bind() — .bind()'d or not, reconnecting the SAME
	# method to the SAME signal twice still errors, but a lambda is a
	# fresh, distinct Callable every time one is created, so set_meta() is
	# the actual guard here, not is_connected().
	if not ship.has_meta(SATELLITE_FIRE_WIRED_META):
		ship.set_meta(SATELLITE_FIRE_WIRED_META, true)
		ship.weapon_fired.connect(func(weapon: WeaponData): _on_satellite_fire(weapon, ship))
		ship.charged_weapon_fired.connect(func(weapon: WeaponData): _on_satellite_fire(weapon, ship))

## Fires a real normal-looking shot (correct machine-gun sprite, straight
## trajectory, via the shared _spawn_projectile() every other shot uses)
## from each satellite's position, instead of TurretNode's own aimed/no-
## sprite _fire_at_target(). `weapon` is whatever the ship actually fired
## (always machine_gun for Mitrailleur today, since every character's kit
## is currently a single weapon) — not hardcoded to a specific resource,
## so this keeps working if his kit ever grows. Silently does nothing if
## every satellite for this ship has expired (turret_lifetime) or none
## were ever cast this match — no need to disconnect anything, the
## connection is meant to be permanent and harmless while inactive.
func _on_satellite_fire(weapon: WeaponData, ship: ShipNode) -> void:
	if not is_instance_valid(ship) or not _satellite_turrets_by_ship.has(ship):
		return
	var any_satellite_alive := false
	for turret in _satellite_turrets_by_ship[ship]:
		if is_instance_valid(turret):
			any_satellite_alive = true
			break
	if not any_satellite_alive:
		return
	for offset_y in [-MITRAILLEUSES_SATELLITES_OFFSET_Y, MITRAILLEUSES_SATELLITES_OFFSET_Y]:
		_spawn_projectile(weapon, ship, 0.0, 1.0, Vector2(0.0, offset_y))

## Zoneur's Ultra rework — "Grille Laser" (2026-08-15, Camil: "ca fait
## trois lasers horizontaux. On avait dit que ca devait faire des laser en
## maillage, qui apparaissent au fur et a mesure (10 lasers sur 1
## seconde), dans tous les sens, et uniquement dans le champ adverse,
## direction random"). Guaranteed floor, then GRILLE_LASER_COUNT diagonal
## LaserMeshNode segments (see that file — BeamNode's horizontal-only
## model doesn't support arbitrary angles), each a random angle through a
## random point, clipped to the OPPONENT's half only, staggered over
## GRILLE_LASER_SPAWN_WINDOW so the web visibly builds up. Each segment
## outlives the spawn window (GRILLE_LASER_LIFETIME > the per-laser
## stagger), so by the time the last one lands, most of the earlier ones
## are still up — that's what makes it read as a dense mesh instead of a
## sequence of single lines.
const GRILLE_LASER_GUARANTEED_DAMAGE := 8.0
const GRILLE_LASER_COUNT := 14 # 2026-08-15 playtest ("c'est parfait :)", then "je rajouterai 4 lasers") — was 10
const GRILLE_LASER_SPAWN_WINDOW := 1.0
const GRILLE_LASER_LIFETIME := 1.5
const GRILLE_LASER_DAMAGE_PER_TICK := 1.0
const GRILLE_LASER_THICKNESS := 5.0

func _ultra_grille_laser(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(GRILLE_LASER_GUARANTEED_DAMAGE)
	var full_bounds := Rect2(arena_origin, arena_size)
	var half_bounds := Rect2(full_bounds)
	if opponent.side == 0:
		half_bounds.size.x = _current_frontier_x - full_bounds.position.x
	else:
		half_bounds.position.x = _current_frontier_x
		half_bounds.size.x = full_bounds.position.x + full_bounds.size.x - _current_frontier_x
	var stagger := GRILLE_LASER_SPAWN_WINDOW / float(GRILLE_LASER_COUNT - 1)
	for i in GRILLE_LASER_COUNT:
		if i > 0:
			get_tree().create_timer(i * stagger).timeout.connect(_spawn_laser_mesh_segment.bind(half_bounds, opponent))
		else:
			_spawn_laser_mesh_segment(half_bounds, opponent)

func _spawn_laser_mesh_segment(bounds: Rect2, opponent: ShipNode) -> void:
	if not is_instance_valid(opponent):
		return # round/rally ended mid-spawn-stagger
	var endpoints := LaserMeshNode.random_clipped_to(bounds)
	var laser := LaserMeshNode.new()
	laser.start = endpoints[0]
	laser.end = endpoints[1]
	laser.lifetime = GRILLE_LASER_LIFETIME
	laser.damage_per_tick = GRILLE_LASER_DAMAGE_PER_TICK
	laser.thickness = GRILLE_LASER_THICKNESS
	laser.target = opponent
	add_child(laser)

## Center of the given ship's own playable half — used by area-hazard
## Ultras (Trou noir, Bourrasque) that need to open where the OPPONENT
## actually spends their time, not at the frontier. 2026-08-15 playtest
## (Camil): the frontier spot both used originally is often nowhere near
## wherever the opponent happens to be standing, especially for a PUSH
## effect (self-limiting — the target leaves the radius the moment it's
## pushed, unlike a pull which drags them back in) — Vif's Bourrasque read
## as "does nothing at all" because of exactly this.
func _half_center(for_ship: ShipNode) -> Vector2:
	var bounds := Rect2(arena_origin, arena_size)
	var x := (bounds.position.x + _current_frontier_x) / 2.0 if for_ship.side == 0 else (_current_frontier_x + bounds.position.x + bounds.size.x) / 2.0
	return Vector2(x, bounds.position.y + bounds.size.y / 2.0)

## Contrôleur's Ultra — "Trou noir" (2026-08-13 Epic 4 memlog: "champ
## continu, attire+ralentit, synergie avec ses tourelles"). Guaranteed
## floor, then a BlackHoleNode opens in the middle of the OPPONENT's own
## half (2026-08-15 playtest: was the frontier — "il faut qu'il apparaisse
## au milieu du terrain adverse, et dure au moins 2x plus longtemps"),
## rather than on top of the opponent (which would give the pull nothing
## to actually pull FROM) or chasing them, so it reads as a real
## battlefield hazard the opponent has to fight the pull of, not a homing
## effect.
const TROU_NOIR_GUARANTEED_DAMAGE := 8.0
const TROU_NOIR_RADIUS := 165.0 # 2026-08-15 playtest: x1.5 ("vortex x1.5") — was 110
const TROU_NOIR_PULL_SPEED := 140.0
const TROU_NOIR_SLOW_MULTIPLIER := 0.5
const TROU_NOIR_DURATION := 6.0 # 2026-08-15 playtest: at least 2x the old 3.0
# 2026-08-15 (Camil, screenshot): a second, fainter outer halo — slow only
# (no pull), milder than the inner zone's slow.
const TROU_NOIR_OUTER_RADIUS := 260.0
const TROU_NOIR_OUTER_SLOW_MULTIPLIER := 0.6 # 2026-08-15 playtest: "on ne se sent pas ralenti" — was 0.75

func _ultra_trou_noir(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(TROU_NOIR_GUARANTEED_DAMAGE)
	var black_hole := BlackHoleNode.new()
	black_hole.position = _half_center(opponent)
	black_hole.radius = TROU_NOIR_RADIUS
	black_hole.pull_speed = TROU_NOIR_PULL_SPEED
	black_hole.slow_multiplier = TROU_NOIR_SLOW_MULTIPLIER
	black_hole.outer_radius = TROU_NOIR_OUTER_RADIUS
	black_hole.outer_slow_multiplier = TROU_NOIR_OUTER_SLOW_MULTIPLIER
	black_hole.duration = TROU_NOIR_DURATION
	black_hole.target = opponent
	add_child(black_hole)

## Perturbateur's Ultra — "Brouillage de commandes" (2026-08-13 Epic 4
## memlog: "scramble les controles adverses"). Guaranteed floor, then the
## opponent's own movement input inverts for a duration
## (ShipNode.apply_control_scramble()) — a skilled player can consciously
## counter-invert their own inputs, matching the "reducible by skill"
## half of the locked Ultra pattern even without a projectile burst.
const BROUILLAGE_GUARANTEED_DAMAGE := 8.0
const BROUILLAGE_DURATION := 12.5 # 2026-08-15 playtest: x5 ("ca dure 5x plus longtemps") — was 2.5

func _ultra_brouillage_de_commandes(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(BROUILLAGE_GUARANTEED_DAMAGE)
	opponent.apply_control_scramble(BROUILLAGE_DURATION)

## Vif's Ultra rework — "Bourrasque" (2026-08-15, Camil, with a reference
## image): the old fixed-point wind vortex (WindVortexNode, "ca fait just
## un espece de rond bleu au milieu") is gone entirely. Now: 10 slightly
## bigger Tourbillon vortices appear from OFF-SCREEN behind the caster's
## own outer wall, at FIXED (not random) vertical slots matching the
## reference image's layout — see BOURRASQUE_VORTEX_Y_FRACTIONS — then
## race straight across toward the opponent's half, speeding up the whole
## way (ProjectileNode.acceleration, not constant velocity). Alongside
## them, a WindGustNode shoves the opponent toward THEIR OWN outer wall
## for the whole attack — a continuous positioning debuff distinct from
## the vortices' own damage.
const BOURRASQUE_GUARANTEED_DAMAGE := 8.0
const BOURRASQUE_VORTEX_COUNT := 10
# Fixed vertical spawn slots, as a fraction of the arena's height (0 =
# top wall, 1 = bottom wall) — read off Camil's reference screenshot,
# NOT randomized per cast ("pas de random, respecte bien l'emplacement
# que j'ai mis").
const BOURRASQUE_VORTEX_Y_FRACTIONS: Array[float] = [0.21, 0.17, 0.12, 0.38, 0.50, 0.67, 0.63, 0.79, 0.91, 0.91]
# 2026-08-15 playtest: "attention avec l'apparition, c'est comme dans mon
# screenshot : les tourbillons ne doivent pas etre sur le meme axe
# vertical" — same order as Y_FRACTIONS above, read off the same
# reference image; varies how far off-screen each one starts (see
# BOURRASQUE_VORTEX_MIN/MAX_SPAWN_OFFSET below) so they don't all pop in
# on a single vertical line.
const BOURRASQUE_VORTEX_DEPTH_FRACTIONS: Array[float] = [0.24, 0.63, 0.93, 0.87, 0.40, 0.26, 0.73, 0.90, 0.55, 0.17]
const BOURRASQUE_VORTEX_MIN_SPAWN_OFFSET := 40.0 # px off-screen behind the caster's own outer wall, nearest
# 2026-08-15 playtest, re-sharing the reference screenshot: "pas mal MAIS
# il faut beaucoup plus d'espace horizontalement entre les tourbillons."
# 180 was too shallow — every vortex shares the same start speed and
# acceleration, so a small depth gap collapses almost instantly once
# they're moving, reading as clustered rather than spread. Widened a lot
# (was 180) so the horizontal spacing seen in the reference actually
# lasts while they cross the arena, not just at the very first instant.
const BOURRASQUE_VORTEX_MAX_SPAWN_OFFSET := 600.0 # px off-screen, furthest back
const BOURRASQUE_VORTEX_START_SPEED := 200.0
const BOURRASQUE_VORTEX_ACCELERATION := 220.0 # px/s^2 — "avancent de plus en plus vite"
const BOURRASQUE_VORTEX_VISUAL_SCALE := 3.2 # "un peu plus gros" than the normal Tourbillon's 2.4 (see _spawn_projectile())
# 2026-08-16 playtest: "les tourbillons ne doivent pas tourner sur eux meme" -
# node self-rotation is gone (no more spin_speed assignment below); the
# tornado read now comes purely from the wind1/wind2/wind3 texture cycle,
# see BOURRASQUE_VORTEX_TEXTURES.
const BOURRASQUE_VORTEX_DAMAGE := 4
const BOURRASQUE_VORTEX_LIFETIME := 4.0
# 2026-08-16 playtest: "Animation c'est enchainement des 3 states wind1 wind2
# wind3" - a dedicated 3-frame cycle for Bourrasque only. Deliberately
# separate from VORTEX_TEXTURES (the base Tourbillon weapon), which stays
# single-frame per the 2026-08-09 decision noted on that constant - these
# vortices are slower/bigger and read fine with a real animation.
const BOURRASQUE_VORTEX_TEXTURES := [
	preload("res://assets/art/vfx/wind1.png"),
	preload("res://assets/art/vfx/wind2.png"),
	preload("res://assets/art/vfx/wind3.png"),
]
const BOURRASQUE_GUST_DURATION := 3.0
# 2026-08-16 playtest correction: "bourrasque ne pousse pas au contact, ca
# pousse tout le temps de l'ultra. Et plus les tourbillons avancent vite,
# plus la poussee est forte (a la fin ... il doit meme un poil reculer)" —
# the push IS the WindGustNode's continuous every-frame shove (already
# running for the whole attack), not a one-off on-hit effect; it just
# needed to ramp up instead of holding a flat speed. Strength is derived
# straight from the vortices' OWN accelerating speed formula
# (BOURRASQUE_VORTEX_START_SPEED + BOURRASQUE_VORTEX_ACCELERATION * t —
# see the spawn loop below) so it literally reads "the vortices are moving
# faster, so the wind is stronger", scaled down so the ultra opens with a
# mild nudge but by BOURRASQUE_GUST_DURATION comfortably clears
# ShipState.SPEED (420 px/s) — the opponent can't advance at all by then
# and actually drifts backward while holding forward.
const BOURRASQUE_GUST_PUSH_SCALE := 0.55

func _ultra_bourrasque(ship: ShipNode, opponent: ShipNode) -> void:
	opponent.apply_damage(BOURRASQUE_GUARANTEED_DAMAGE)
	var bounds := Rect2(arena_origin, arena_size)
	var direction := 1.0 if ship.side == 0 else -1.0
	for i in BOURRASQUE_VORTEX_Y_FRACTIONS.size():
		var y_fraction: float = BOURRASQUE_VORTEX_Y_FRACTIONS[i]
		var depth_offset := lerpf(BOURRASQUE_VORTEX_MIN_SPAWN_OFFSET, BOURRASQUE_VORTEX_MAX_SPAWN_OFFSET, BOURRASQUE_VORTEX_DEPTH_FRACTIONS[i])
		var spawn_x := bounds.position.x - depth_offset if ship.side == 0 else bounds.position.x + bounds.size.x + depth_offset
		var vortex := ProjectileNode.new()
		vortex.position = Vector2(spawn_x, bounds.position.y + bounds.size.y * y_fraction)
		vortex.velocity = Vector2(direction * BOURRASQUE_VORTEX_START_SPEED, 0.0)
		vortex.acceleration = BOURRASQUE_VORTEX_ACCELERATION
		vortex.textures = BOURRASQUE_VORTEX_TEXTURES
		vortex.visual_scale = BOURRASQUE_VORTEX_VISUAL_SCALE
		vortex.damage = BOURRASQUE_VORTEX_DAMAGE
		vortex.target = opponent
		vortex.lifetime = BOURRASQUE_VORTEX_LIFETIME
		add_child(vortex)

	var gust := WindGustNode.new()
	gust.duration = BOURRASQUE_GUST_DURATION
	gust.push_speed_start = BOURRASQUE_VORTEX_START_SPEED * BOURRASQUE_GUST_PUSH_SCALE
	gust.push_speed_end = (BOURRASQUE_VORTEX_START_SPEED + BOURRASQUE_VORTEX_ACCELERATION * BOURRASQUE_GUST_DURATION) * BOURRASQUE_GUST_PUSH_SCALE
	gust.target = opponent
	add_child(gust)

# Placeholder R-Type sprites (2026-08-02) — replace with final art later.
# 2026-08-18: the actual texture consts (MACHINE_GUN_TEX_P1/P2, BAZOOKA_/
# VORTEX_/BONBON_/BOOMERANG_TEXTURES) moved to ProjectileFactory, the only
# place that still directly assigns them — BONBON_TEXTURES' one other call
# site (the Pluie de Bonbons drop, above) now reads ProjectileFactory.
# BONBON_TEXTURES directly.

## Epic 4 reward system (2026-08-16, Camil: "on va mettre des trucs en
## face des recompenses. pour chaque rival vaincu.") — the 8 base kit
## weapons, keyed by WeaponData.id, the exact same string CampaignSave.
## unlocks_for(character_id) stores (see RivalEncounterData.unlock_reward
## being set to the defeated rival's own weapon resource, and
## _resolve_campaign_result() recording its `.id`). Used to resolve an
## unlocked id back into the real resource (with its passive_interval)
## when wiring up passive rewards for a ship — see _setup_passive_rewards().
const BASE_WEAPONS_BY_ID := {
	"bazooka": preload("res://data/weapons/bazooka.tres"),
	"turret": preload("res://data/weapons/turret.tres"),
	"machine_gun": preload("res://data/weapons/machine_gun.tres"),
	"vortex": preload("res://data/weapons/vortex.tres"),
	"laser": preload("res://data/weapons/laser.tres"),
	"stun_boomerang": preload("res://data/weapons/stun_boomerang.tres"),
	"homing_missile": preload("res://data/weapons/homing_missile.tres"),
	"mini_shot": preload("res://data/weapons/mini_shot.tres"),
}
# Controleur's own passive turret ("dure 6s", distinct from the normal 25s
# and the charged 5s) — the one number from Camil's original example that
# isn't just weapon.passive_interval, so it lives here instead of on the
# .tres.
const PASSIVE_TURRET_LIFETIME := 6.0
# 2026-08-16 playtest: "on est un peu sur le meme pattern (une arme qui
# apparait tous les X). Il faut etre plus creatif" — the first pass had
# all 8 passives reduce to the exact same verb. 2026-08-16 same-day
# follow-up gave each of the 7 (Controleur's turret was already fine, its
# own idea from the very start) a bespoke effect instead — see
# _fire_passive_reward()'s dispatch for the full rundown. These are the
# tuning for the non-weapon-.tres effects (a lone satellite module, one
# Scud strike, a vertical laser wall, a lone homing missile, Perturbateur's
# Ultra-linked scramble, Spreader's heal) that don't belong on a
# WeaponData.tres since most aren't shot patterns at all.
# 2026-08-22 (Camil: "ca ne me plait pas. Il faudrait finalement que ce soit
# exactement le tir de mitrailleur (avec le meme sprite), mais lance
# automatiquement, salve de 4 [tirs], toutes les 3 secondes. Pas de
# module.") — replaces the old self-firing satellite TurretNode module
# entirely (that const/behavior is gone, see _fire_passive_reward()).
const PASSIVE_MITRAILLEUR_BURST_COUNT := 4
const PASSIVE_ZONEUR_LASER_LIFETIME := GRILLE_LASER_LIFETIME # reuses Grille Laser's own tick rate/fade, just one segment
const PASSIVE_PERTURBATEUR_ULTRA_SCRAMBLE_DURATION := 5.0 # "lors de l'ultra du joueur, applique aussi le brouillage, mais uniquement 5 sec"
const PASSIVE_VIF_SPEED_MULTIPLIER := 1.2 # "une acceleration de +20%, tout le temps" — PERMANENT, see ShipNode.apply_permanent_speed_bonus()
const PASSIVE_SPREADER_HEAL_FRACTION := 0.15 # "lui redonne 15% de PV" — of max_hp_override, not a flat number
# 2026-08-22 (Camil: "la rotation de l'eventail devrait durer 2x plus
# longtemps, on n'a pas le temps de le voir") — was 1.0.
const PASSIVE_SPREADER_FAN_DURATION := 2.0 # "un eventail apparait et tourne autour du joueur pendant 1 sec"
const PASSIVE_HEAL_POPUP_COLOR := Color(0.35, 0.9, 0.35, 1.0) # green, distinct from the gold gauge-fill "+X" popup — this one's HP, not weapon charge

## Wires up every reward this ship's CURRENT character has unlocked (scope
## locked 2026-08-11: always active for that character, campaign AND
## Versus, forever; multiple unlocked rewards stack — no equip screen).
## Called once per ship right after its character is finalized in
## _ready() (covers both the MatchSetup/CharacterSelect path and the
## campaign-override path, since this runs after both).
## Most rewards are periodic — one repeating Timer per unlocked passive
## weapon, parented to the ship itself so it naturally lives/dies with the
## ship's own lifetime (spans the whole match, survives round transitions)
## without needing round-reset code. Two are NOT periodic (2026-08-16
## same-day rework) and are handled here directly instead of via a timer:
## Vif's is a permanent stat applied once; Perturbateur's is reactive,
## re-checked live at Ultra-trigger time in _on_ultra_triggered() instead
## of needing any state kept here at all.
func _setup_passive_rewards(ship: ShipNode) -> void:
	if not ship.character:
		return
	for unlock_id in CampaignSave.unlocks_for(ship.character.id):
		if unlock_id == "vortex":
			ship.apply_permanent_speed_bonus(PASSIVE_VIF_SPEED_MULTIPLIER)
			continue
		if unlock_id == "stun_boomerang":
			continue # reactive, nothing to wire up in advance — see _on_ultra_triggered()
		var weapon: WeaponData = BASE_WEAPONS_BY_ID.get(unlock_id)
		if not weapon or weapon.passive_interval <= 0.0:
			continue
		var timer := Timer.new()
		timer.wait_time = weapon.passive_interval
		timer.autostart = true
		timer.timeout.connect(_fire_passive_reward.bind(ship, weapon))
		ship.add_child(timer)

## Fires one unlocked PERIODIC passive reward, no player input at all —
## Vif's permanent bonus and Perturbateur's Ultra-linked scramble never
## reach this function at all (see _setup_passive_rewards()/
## _on_ultra_triggered()). Dispatches by weapon id into 6 different
## bespoke effects (2026-08-16 same-day rework, "il faut etre plus
## creatif" — the first pass had every one reduce to "auto-fire this
## weapon's own shot"), each still tied to that character's own
## established identity/Ultra:
##   - Controleur (turret): the entity itself, own short 6s lifetime.
##   - Mitrailleur (machine_gun): a real 4-shot burst of the exact normal
##     machine_gun projectile (2026-08-22 rework — was a self-firing
##     satellite module; Camil: "pas de module").
##   - Lourd (bazooka): two Pluie-de-Scuds-style missile strikes (reticle +
##     falling shell), each on its own random point in the opponent's half.
##   - Zoneur (laser): one vertical LaserMeshNode wall, top to bottom of
##     the opponent's half, spawning at a random X and sweeping toward
##     whichever edge (center line or back wall) it's farther from.
##   - Traqueur (homing_missile): a single real homing missile (not the
##     normal 3-burst, not the 6-missile charged rafale).
##   - Spreader (mini_shot): a self-heal (15% of max HP) with a cosmetic
##     orbiting-fan flourish — flips her own stated weakness ("no
##     defensive tool of her own") into exactly that.
## Weapon/entity-based ones fire/land with no aim assist, same "never
## guaranteed" spirit as every other damage source in this game (the
## vertical laser and the satellite module are the exception — both cover
## real space rather than needing to be aimed at all); the heal always lands.
func _fire_passive_reward(ship: ShipNode, weapon: WeaponData) -> void:
	if not _round_playing or not is_instance_valid(ship) or not ship.active:
		return
	var opponent := ship_2 if ship == ship_1 else ship_1
	if not is_instance_valid(opponent):
		return
	match weapon.id:
		"turret":
			_spawn_turret(weapon, ship, false, PASSIVE_TURRET_LIFETIME)
		"machine_gun":
			# 2026-08-22 (Camil: "ca ne me plait pas. Il faudrait finalement
			# que ce soit exactement le tir de mitrailleur (avec le meme
			# sprite), mais lance automatiquement, salve de 4 [tirs], toutes
			# les 3 secondes. Pas de module.") — was a self-firing satellite
			# TurretNode module; now just the real machine_gun projectile
			# (same _spawn_projectile() every normal press uses, same
			# sprite/damage) fired 4 times in a row, staggered at the gun's
			# own natural fire interval so it reads as a real burst, not a
			# single reskinned shot.
			var stagger := 1.0 / weapon.fire_rate
			for i in PASSIVE_MITRAILLEUR_BURST_COUNT:
				if i == 0:
					_spawn_projectile(weapon, ship, 0.0)
				else:
					get_tree().create_timer(i * stagger).timeout.connect(_spawn_projectile.bind(weapon, ship, 0.0))
		"bazooka":
			# 2026-08-22 (Camil: "Passer a 2 scuds qui tombent aleatoirement
			# toutes les 3 secondes") — was one strike per interval; now two,
			# each its own independently-randomized point.
			var bounds := Rect2(arena_origin, arena_size)
			var min_x := bounds.position.x + PLUIE_DE_SCUDS_TARGET_MARGIN if opponent.side == 0 else _current_frontier_x
			var max_x := _current_frontier_x if opponent.side == 0 else bounds.position.x + bounds.size.x - PLUIE_DE_SCUDS_TARGET_MARGIN
			var min_y := bounds.position.y + PLUIE_DE_SCUDS_TARGET_MARGIN
			var max_y := bounds.position.y + bounds.size.y - PLUIE_DE_SCUDS_TARGET_MARGIN
			for i in 2:
				_spawn_missile_strike(Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y)), opponent)
		"laser":
			var full_bounds := Rect2(arena_origin, arena_size)
			var half_bounds := Rect2(full_bounds)
			if opponent.side == 0:
				half_bounds.size.x = _current_frontier_x - full_bounds.position.x
			else:
				half_bounds.position.x = _current_frontier_x
				half_bounds.size.x = full_bounds.position.x + full_bounds.size.x - _current_frontier_x
			var random_x := randf_range(half_bounds.position.x, half_bounds.position.x + half_bounds.size.x)
			var wall := LaserMeshNode.new()
			wall.start = Vector2(random_x, half_bounds.position.y)
			wall.end = Vector2(random_x, half_bounds.position.y + half_bounds.size.y)
			wall.lifetime = PASSIVE_ZONEUR_LASER_LIFETIME
			wall.damage_per_tick = GRILLE_LASER_DAMAGE_PER_TICK
			wall.thickness = GRILLE_LASER_THICKNESS
			wall.target = opponent
			# 2026-08-22 (Camil: "il faudrait que le laser se deplace jusqu'au
			# centre (s'il apparait vers le fond) ou vers le fond (s'il
			# apparait vers le centre)") — was a static wall; now it always
			# sweeps toward whichever edge of the half it did NOT spawn
			# closer to, timed to arrive exactly as its lifetime runs out.
			var center_edge_x := _current_frontier_x
			var back_edge_x := half_bounds.position.x if is_equal_approx(center_edge_x, half_bounds.position.x + half_bounds.size.x) else half_bounds.position.x + half_bounds.size.x
			var target_edge_x := back_edge_x if absf(random_x - center_edge_x) < absf(random_x - back_edge_x) else center_edge_x
			wall.horizontal_velocity = (target_edge_x - random_x) / PASSIVE_ZONEUR_LASER_LIFETIME
			add_child(wall)
		"homing_missile":
			_spawn_projectile(weapon, ship, 0.0)
		"mini_shot":
			var heal_amount := ship.max_hp_override * PASSIVE_SPREADER_HEAL_FRACTION
			ship.apply_heal(heal_amount)
			# 2026-08-22 (Camil: "on devrait voir un '+X' en vert qui monte
			# pour indiquer qu'on gagne des PV") — same FloatingTextNode the
			# gauge-fill "+X" popup already uses (_on_gauge_filled() above),
			# just green instead of gold so it reads as HP, not weapon charge.
			var popup := FloatingTextNode.new()
			popup.position = ship.position + Vector2(0.0, -16.0)
			popup.text = "+%d" % int(heal_amount)
			popup.color = PASSIVE_HEAL_POPUP_COLOR
			add_child(popup)
			var fx := PassiveHealFxNode.new()
			fx.duration = PASSIVE_SPREADER_FAN_DURATION
			ship.add_child(fx)

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
	if weapon.effect_type == "turret":
		# Controleur (2026-08-10): "pose une tourelle ephemere, qui tire 4x
		# plus vite, mais ne dure que 5 secondes".
		_spawn_turret(weapon, ship, true)
		return
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
		# loin, jusqu'au fond du camp adverse" — the charged release sends it
		# much further out before it curves back. "Tir charge: un enorme
		# boomerang (5 fois la taille, 5x degats)" — charged_damage_multiplier/
		# charged_visual_scale_multiplier default to 1.0 for every other
		# weapon, so this only actually changes anything for the boomerang.
		_spawn_projectile(weapon, ship, 0.0, weapon.charged_speed_multiplier, Vector2.ZERO, weapon.charged_boomerang_out_duration, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier, true)
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
				_spawn_projectile.bind(weapon, ship, angle_offset, weapon.charged_speed_multiplier, Vector2.ZERO, 0.0, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier)
			)
		else:
			_spawn_projectile(weapon, ship, angle_offset, weapon.charged_speed_multiplier, Vector2.ZERO, 0.0, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier)

## 2026-08-18 — extracted into ProjectileFactory.spawn() so BreakoutNode
## can reuse the EXACT same per-weapon texture/trajectory logic (Camil,
## after Breakout's first-pass generic visuals: "il faut que le joueur
## garde ses armes habituelles"). This is now a thin wrapper preserving
## every existing call site's signature/behavior unchanged.
func _spawn_projectile(weapon: WeaponData, ship: ShipNode, angle_offset_deg: float, speed_multiplier: float = 1.0, position_offset: Vector2 = Vector2.ZERO, boomerang_out_duration_override: float = 0.0, damage_multiplier: float = 1.0, size_multiplier: float = 1.0, force_no_burst_shrink: bool = false) -> void:
	if not is_instance_valid(ship):
		return # round may have reset mid-burst-stagger
	var target := ship_2 if ship == ship_1 else ship_1
	var projectile := ProjectileFactory.spawn(weapon, ship, target, angle_offset_deg, speed_multiplier, position_offset, boomerang_out_duration_override, damage_multiplier, size_multiplier, force_no_burst_shrink)
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
## 2026-08-18 — moved to ProjectileFactory.weapon_tint() (BreakoutNode
## needs the exact same per-weapon color); kept as a thin wrapper since
## every existing call site here calls it as a bound instance method.
func _weapon_tint(weapon_id: String) -> Color:
	return ProjectileFactory.weapon_tint(weapon_id)

## Story 2.4 — turret weapons spawn a persistent autonomous-firing node at
## the shooter's position instead of a traveling projectile.
func _spawn_turret(weapon: WeaponData, ship: ShipNode, is_charged: bool = false, lifetime_override: float = 0.0) -> void:
	var turret := TurretNode.new()
	turret.position = ship.position
	turret.weapon = weapon
	turret.target = ship_2 if ship == ship_1 else ship_1
	turret.owner_side = ship.side
	if is_charged:
		# Controleur (2026-08-10): "pose une tourelle ephemere, qui tire 4x
		# plus vite, mais ne dure que 5 secondes".
		turret.fire_rate_multiplier = weapon.charged_turret_fire_rate_multiplier
		turret.lifetime_override = weapon.charged_turret_lifetime
	elif lifetime_override > 0.0:
		# 2026-08-16 reward system — Controleur's passive turret gets its
		# own short lifetime (6s), distinct from both the normal 25s and
		# the charged 5s above. See _fire_passive_reward().
		turret.lifetime_override = lifetime_override
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
				_show_post_match_choice()
		else:
			ship_1.reset_for_new_round()
			ship_2.reset_for_new_round()
			ball.reset_to_center()
			for extra in _extra_balls: # "multi_ball" twist — extra balls persist across rounds within the same twisted encounter, just re-center like the primary
				if is_instance_valid(extra):
					extra.reset_to_center()
			# 2026-08-22 bug report (Camil: "deuxieme game contre mon rival,
			# la zone est toujours retrecie, elle devrait revenir a
			# l'origine") — shrinking_arena's accumulated _shrink_step/
			# _current_arena_bounds carried over from round 1 into round 2/3
			# untouched; nothing here ever put the arena back to full size
			# for a fresh round.
			_reset_shrinking_arena()
			_round_active = true
			_begin_round_ready_gate() # 2026-08-13: round 2/3 used to start the instant round 1 ended — no freeze, no "Pret ?" gate at all

## 2026-08-16 UX audit (Sally): "Versus mode ends in a dead screen" — a
## short beat to let "Match termine..." read on its own, then the same
## up/down + confirm menu every other screen already uses, offering a
## rematch or a trip back to character select. Never runs in campaign mode
## (_resolve_campaign_result() already bounces onward on its own).
func _show_post_match_choice() -> void:
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(self) or _campaign_mode:
		return # round/match got reset from under us mid-wait (K cheat etc.) — bail rather than showing a stale menu
	_post_match_choice_active = true
	_post_match_choice_index = 0
	_post_match_move_prev = 0.0
	_post_match_confirm_prev = true # seeded true — the SAME keypress that just confirmed the last "Ready ?" gate must not immediately confirm this menu's default entry
	_refresh_post_match_choice_label()

func _refresh_post_match_choice_label() -> void:
	var lines: Array[String] = []
	for i in POST_MATCH_CHOICES.size():
		var marker := "> " if i == _post_match_choice_index else "  "
		lines.append("%s%s" % [marker, POST_MATCH_CHOICES[i]])
	post_match_label.text = "\n".join(lines)

## Same physical-key convention as TitleScreenNode/CampaignMapNode (Up/Down
## to navigate, Space/Enter or either gamepad's right trigger to confirm) —
## safe to reuse P1's fire key (Space) and P2's fire key (Enter) here since
## both ships are frozen (active = false) by the time this menu shows.
func _process_post_match_choice() -> void:
	var move := 0.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		move += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		move -= 1.0
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(stick_y) > 0.3:
		move = stick_y
	if absf(move) > 0.5 and absf(_post_match_move_prev) <= 0.5:
		var step := 1 if move > 0.0 else -1
		_post_match_choice_index = wrapi(_post_match_choice_index + step, 0, POST_MATCH_CHOICES.size())
		_refresh_post_match_choice_label()
	_post_match_move_prev = move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
		or Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _post_match_confirm_prev:
		match _post_match_choice_index:
			0: # Revanche — MatchSetup still holds both picks, _ready() re-applies them on reload
				get_tree().reload_current_scene()
			1: # Choix des personnages
				get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")
	_post_match_confirm_prev = confirm

## Epic 4, Story 4.4/4.6/4.8 — records the outcome to CampaignSave (mooks
## grant currency, the "real" rival grants an unlock, the organizer
## completes the campaign run) and returns to CampaignMap, now the single
## world-map screen for the whole campaign (2026-08-24 rework — used to
## also route to a separate MiniBranchMap mid-branch). A loss is never
## punished beyond a retry of the SAME step (2026-08-08, Camil: "on ne peut
## jamais reculer") — campaign_step itself never moves backward.
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
		# 2026-08-24 world-map rework — a loss always bounces back to the
		# same single CampaignMap (campaign_step untouched, so it's still
		# showing/re-fighting this exact step); there's no separate
		# MiniBranchMap to return to anymore.
		CampaignContext.return_to_map()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		return

	if CampaignContext.is_organizer_fight():
		CampaignSave.mark_organizer_defeated(character_id)
		match_label.text = "Tournoi remporte !"
		# 2026-08-16 UX audit (Sally): "'Rival vaincu !' gets the same second
		# and a half as a routine mook kill" — the whole campaign's biggest
		# beat used to hold for barely longer than a throwaway fight. Bigger
		# flash (same "big moment" font-bump the round-start GO! beat already
		# uses) plus a real hold to let it land.
		match_label.add_theme_font_size_override("font_size", 48)
		await get_tree().create_timer(3.0).timeout
		match_label.remove_theme_font_size_override("font_size")
		# 2026-08-22 (Camil: "fin du tournoi => Tournoi remporte, il
		# faudrait revenir a l'accueil ensuite") — was CampaignMap.tscn
		# (this character's own map, nothing left to do there once its
		# organizer is beaten); TitleScreen is the actual home screen.
		CampaignContext.clear()
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
		return

	var current_encounter := CampaignContext.current_encounter()
	var hold_duration := 1.5
	if current_encounter.is_mook:
		CampaignSave.add_currency(character_id, current_encounter.reward_currency)
		match_label.text = "Victoire (+%d)" % current_encounter.reward_currency
	else:
		# The "real" rival, defeated.
		if current_encounter.unlock_reward:
			CampaignSave.grant_unlock(character_id, current_encounter.unlock_reward.id)
		match_label.text = "Rival vaincu !"
		# 2026-08-16 UX audit (Sally) — same reasoning as the organizer win
		# above, one notch smaller: a branch rival is a real story beat, not
		# routine mook progress, so it gets its own weight instead of
		# sharing the flat 1.5s hold every mook kill uses.
		match_label.add_theme_font_size_override("font_size", 40)
		hold_duration = 2.6
		# 2026-08-16 (Camil): "on pourrait ajouter la recompense: icone + nom + description" - shown alongside "Rival vaincu !", see WeaponData.passive_description.
		if current_encounter.unlock_reward:
			var reward: WeaponData = current_encounter.unlock_reward
			reward_icon.color = _weapon_tint(reward.id)
			reward_icon.visible = true
			reward_label.text = "Vous avez gagne : %s\n%s" % [reward.display_name, reward.passive_description]
			reward_label.visible = true
			hold_duration = 3.4

	await get_tree().create_timer(hold_duration).timeout
	match_label.remove_theme_font_size_override("font_size")
	# 2026-08-31 graph-mode (Camil: "la campagne DOIT se baser uniquement sur
	# la carte"): mark this specific node resolved by id rather than advancing
	# a linear integer step. Branch-mode characters use the old path.
	if CampaignContext.is_graph_mode:
		CampaignSave.add_resolved_case_id(character_id, CampaignContext.current_graph_node_id)
	else:
		# 2026-08-24 world-map rework — one flat step counter now instead of a
		# per-branch one; always the same CampaignMap on return.
		CampaignContext.advance_step()
		CampaignSave.set_campaign_progress(character_id, CampaignContext.campaign_step)
	CampaignContext.return_to_map()
	get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")

## Round-end cleanup (2026-08-07 bug fix — "à la fin du round 1 les tourelles
## restent, elles devraient disparaître"): turrets, in-flight projectiles, and
## beams are all round-scoped side effects of weapon fire; none of them
## should survive into the next round (or linger past match end).
## 2026-08-15 bug report (Camil): "quand un joueur perd un round il faut
## remettre tous les compteurs a 0 y compris les effets d'ultra" —
## BlackHoleNode/WindGustNode/LaserMeshNode/MissileStrikeNode/
## GaugeFillEffectNode were missing from this list entirely, so a round
## ending mid-Ultra (Trou noir still pulling, a wind gust still blowing,
## laser mesh segments still landing) would leave those hazards alive and
## running into the next round.
func _clear_round_entities() -> void:
	for child in get_children():
		if child is TurretNode or child is ProjectileNode or child is BeamNode or child is HazardZoneNode or child is EnergyOrbNode or child is BlackHoleNode or child is WindGustNode or child is LaserMeshNode or child is MissileStrikeNode or child is GaugeFillEffectNode:
			child.queue_free()
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null
	# The Ultra satellite-fire bookkeeping (Mitrailleur) tracks turrets that
	# just got queue_free()'d above — is_instance_valid() in _on_satellite_
	# fire() will correctly read them as gone from here on, so no explicit
	# clear is needed, but the dictionary itself should still drop stale
	# ship keys (e.g. a ship freed between matches) rather than grow forever.
	for ship_key in _satellite_turrets_by_ship.keys():
		if not is_instance_valid(ship_key):
			_satellite_turrets_by_ship.erase(ship_key)

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
		# Cheat menu (2026-08-09) — neither the organizer nor a branch is
		# set here, just a throwaway encounter; the step-name labeling
		# below doesn't apply (2026-08-09 bug: crashed on this case being
		# mistaken for the organizer fight).
		encounter_name = "Cheat menu — vs %s" % CampaignContext.debug_encounter.opponent.display_name
	elif not CampaignContext.is_organizer_fight():
		var branch := CampaignContext.current_branch()
		if branch:
			# Branch-based mode: "Contre Vif — Sous-adversaire 1/2" etc.
			var step_names := ["Sous-adversaire 1/2", "Sous-adversaire 2/2", "Rival"]
			var step: String = step_names[clampi(CampaignContext.campaign_step % 3, 0, 2)]
			encounter_name = "%s — %s" % [branch.display_name, step]
		else:
			# JSON-first mode (2026-08-29): branch concept doesn't apply —
			# show the encounter type + opponent name from the encounter data.
			var enc := CampaignContext.current_encounter()
			var opp_name := enc.opponent.display_name if enc and enc.opponent else "?"
			if enc and enc.is_mook:
				encounter_name = "Etape %d — vs %s" % [CampaignContext.campaign_step + 1, opp_name]
			else:
				encounter_name = "Rival — vs %s" % opp_name
	var twist_text := ""
	if active_twist:
		twist_text = " | Twist : %s" % active_twist.display_name
	campaign_label.text = "%s%s" % [encounter_name, twist_text]

## Story 1.12 — F1 toggles a basic AI opponent on/off for Ship2, so solo
## testing doesn't require editing the scene.
## Bug report (Ben's playtest via Camil, 2026-08-31: "Faudrait pouvoir
## revenir au menu avec echap") — every OTHER screen in the project already
## treats Echap as "go to TitleScreen" (2026-08-18, "quand je fais Echap,
## que ca revienne en arriere"), but MatchArena itself had no Escape
## handling at all: once in a fight, there was no way out short of losing
## or winning it. Abandoning mid-fight forfeits nothing campaign-side (no
## resolved case is recorded) — CampaignContext.return_to_map() just clears
## the transient debug/pending-encounter state, same cleanup a real
## win/loss already does before leaving this scene.
func _process_escape() -> void:
	var pressed := Input.is_physical_key_pressed(KEY_ESCAPE)
	if pressed and not _escape_prev:
		CampaignContext.return_to_map()
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
	_escape_prev = pressed

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

## Dev-only cheat keys for faster manual testing (2026-08-13): K instantly
## kills the opponent (ship_2), U maxes ship_1's ultra meter (skip
## grinding 5 real misses to test an ultra trigger), M fills ship_1's
## ammo/weapon gauges to 100. Gated on _round_playing so they can't fire
## mid-freeze (ready gate / match-over pause) and do something undefined.
func _process_cheat_keys() -> void:
	if not _round_playing:
		return

	var kill_pressed := Input.is_physical_key_pressed(KEY_K)
	if kill_pressed and not _cheat_kill_prev:
		ship_2.apply_damage(ship_2.state.hp) # HP to exactly 0 regardless of current value — _check_round_end() resolves it normally next frame, same as a real kill
	_cheat_kill_prev = kill_pressed

	var ultra_pressed := Input.is_physical_key_pressed(KEY_U)
	if ultra_pressed and not _cheat_ultra_prev:
		while not ship_1.weapon_state.ultra_ready():
			ship_1.add_ultra_pip()
	_cheat_ultra_prev = ultra_pressed

	var ammo_pressed := Input.is_physical_key_pressed(KEY_M)
	if ammo_pressed and not _cheat_ammo_prev:
		for i in ship_1.weapon_state.kit.size():
			ship_1.weapon_state = ship_1.weapon_state.with_gauge_added(ship_1.weapon_state.kit[i].gauge_max, i)
	_cheat_ammo_prev = ammo_pressed

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
##
## 2026-08-11 bug report: "elle ne retrecit qu'horizontalement, il faudrait
## aussi verticalement. Et pas plus de 6x (sinon il reste vraiment plus
## rien)" — was width-only; now shrinks height by the same fraction each
## step too, and stops applying new steps past MAX_SHRINK_STEPS (a timer
## tick past that point is simply ignored, not just clamped smaller — the
## old fraction-of-original-width cap alone let steps keep "landing" at the
## same clamped size indefinitely, which is harmless for size but not what
## "pas plus de 6x" asks for).
const MAX_SHRINK_STEPS := 6

func _process_shrinking_arena(delta: float) -> void:
	_shrink_step_timer += delta
	if _shrink_step_timer >= active_twist.shrink_interval and _shrink_step < MAX_SHRINK_STEPS:
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

## 2026-08-22 (Camil: "deuxieme game contre mon rival, la zone est toujours
## retrecie, elle devrait revenir a l'origine") — puts the arena back to its
## full, un-shrunk size and clears every bit of shrink progress, so a fresh
## round of the SAME encounter starts exactly like round 1 did. Called from
## _check_round_end()'s round-continuation branch; harmless to call even
## when shrinking_arena was never the active twist (every field it touches
## already defaults to "untwisted").
func _reset_shrinking_arena() -> void:
	_shrink_step = 0
	_shrink_step_timer = 0.0
	_shrink_anim_elapsed = 0.0
	_shrink_animating = false
	_current_arena_bounds = Rect2(arena_origin, arena_size)
	_sync_arena_bounds_to_entities()

func _start_next_shrink_step() -> void:
	_shrink_step += 1
	var total_shrink_x := arena_size.x * active_twist.shrink_fraction * _shrink_step
	total_shrink_x = minf(total_shrink_x, arena_size.x * 0.7) # never shrink the arena into an unplayable sliver
	var total_shrink_y := arena_size.y * active_twist.shrink_fraction * _shrink_step
	total_shrink_y = minf(total_shrink_y, arena_size.y * 0.7)
	_shrink_start_bounds = _current_arena_bounds
	_shrink_target_bounds = Rect2(
		Vector2(arena_origin.x + total_shrink_x / 2.0, arena_origin.y + total_shrink_y / 2.0),
		Vector2(arena_size.x - total_shrink_x, arena_size.y - total_shrink_y)
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
