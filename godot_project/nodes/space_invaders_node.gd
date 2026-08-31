class_name SpaceInvadersNode
extends Node2D

## Space Invaders mini-jeu (2026-08-22) — a campaign-map "mook" encounter
## slot can be this instead of a real fight (RivalEncounterData.
## challenge_type == "space_invaders"). Second mini-jeu after Breakout,
## built on the exact same lessons: reuse the real game systems wholesale
## instead of a bolted-on arcade clone.
##
##   - Ship1 is a REAL ShipNode (full 2D movement/lift/weapon, side 0,
##     same controls as Player 1 always has), same left-of-frontier zone
##     as Breakout.
##   - Weapon fire reuses ProjectileFactory.spawn() directly — real
##     textures/boomerang arc/vortex sine/homing, same as Breakout and a
##     real match. Turret/beam/double-fire charged releases supported too.
##   - No ball this time ("aucun rapport avec la balle" per the original
##     brainstorm) — so the normal ball-touch gauge economy doesn't apply.
##     ship_1.passive_trickle_rate (an existing mechanic — the "gauge_floor"
##     campaign twist already uses it for a similar "fills over time, no
##     ball needed" case) funds the gauge instead.
##   - The enemy formation is TurretNode instances (owner_side=1, autofire
##     on, target=ship_1) — same reused HP/destruction/weapon-hit-detection
##     as every other turret-based entity this project has built. Moved
##     externally (position is a plain Node2D property, safe to update
##     every tick — TurretNode itself never needed to know how to move).
##   - target = a bare ShipNode.new() (side=1, never added to the tree) for
##     weapon-projectile hit-detection's target.side filter — identical
##     trick to Breakout's _dummy_target.
##   - Win: whole formation destroyed. Lose: ship_1 HP hits 0, OR any
##     alien's leading edge actually touches FRONTIER_X (the center line).

const ARENA_BOUNDS := Rect2(Vector2(40.0, 60.0), Vector2(1200.0, 600.0))
const FRONTIER_X := 580.0 # same as Breakout, for visual consistency between the two mini-jeux
# 2026-08-22 (Camil: "la barre de tirs monte pas assez vite. il faudrait
# booster un peu sa montee dans ce mode uniquement (150%)") — was 6.0;
# ShipNode.passive_trickle_rate is the ONLY gauge source here (no ball to
# fund it like Breakout's paddle-return does), so a slow trickle reads as
# a much bigger drought here than elsewhere. 9.0 = 6.0 * 1.5, scoped to
# this file's own constant only — Breakout/the real match's gauge economy
# is untouched.
const GAUGE_TRICKLE_RATE := 9.0 # % of gauge_max/sec — ShipNode.passive_trickle_rate, no ball to fund it otherwise

# 2026-08-22 follow-up ("faut les positionner verticalement") — Camil
# wants the formation taller than it is wide, not the classic-Invaders
# wide/short block. Swapped COLS/ROWS (was 8x5 landscape, now 5x8
# portrait) — same 40 aliens total, same difficulty/gauge pacing, just
# reshaped to fill the arena's own right-hand band (which is itself
# taller than it is wide: ~660px tall vs. ~520px wide past the frontier).
const FORMATION_COLS := 5
const FORMATION_ROWS := 8
const FORMATION_HALF_EXTENTS := Vector2(20.0, 20.0)
const FORMATION_PITCH_X := 68.0
const FORMATION_PITCH_Y := 60.0
# 2026-08-22 bug report ("ils sont mal positionnees") — was 780.0: with
# 8 cols at 68px pitch (476px span), the last column's center+half_extent
# landed at 1276, past the arena's own right edge (1240) — the formation
# spilled off the visible background. First fix pass overshot to 680,
# which left the FRONT column only 40px from FRONTIER_X+INVASION_MARGIN
# (640) — an invasion within ~5s of a fresh level even before killing a
# single alien (caught by the regression suite silently dying mid-run,
# the same self-inflicted-real-loss class of bug as breakout_check.gd's
# own history). 780 (then bumped again below) keeps the front column's
# own runway comfortable and, now that there are only 5 columns, the
# last column stays well clear of the 1240 right edge either way.
# 2026-08-22 follow-up, live playtest ("c'est vraiment chaud la, surtout
# avec le tir de vif") — 780 still felt too close/fast to react to,
# especially with Vif's own weapon pattern. Pushed further right: 860
# puts the last column's edge at 1152 (88px inside the 1240 right edge)
# while giving the front column ~260px of runway before the center line.
# 2026-08-22 follow-up #2 ("tu peux encore decaler les ennemis de 50px a
# droite") — 910 now: last column's edge lands at 1202 (38px inside the
# 1240 right edge), front column runway grows to ~310px.
const FORMATION_START_X := 910.0
# Centered vertically for the new 8-row portrait shape: with 8 rows at a
# 60px pitch (420px between first/last row centers) plus 20px of
# half-extent margin on each end, 150 leaves an even ~70px gap at both
# the arena's top (60) and bottom (660) edges.
const FORMATION_START_Y := 150.0
const ALIEN_HP := 2.0
const ALIEN_FIRE_RATE := 0.35 # a basic single shot, more frequent than Breakout's occasional popups — this IS the core threat here
const ALIEN_DAMAGE := 6.0
const ALIEN_COLOR := Color(0.85, 0.3, 0.35)

const ADVANCE_SPEED := 8.0 # px/s leftward drift, scales up as the formation thins out
const BOB_AMPLITUDE := 10.0
const BOB_ANGULAR_SPEED := 1.2 # rad/s

@onready var ship_1: ShipNode = $Ship1
@onready var hp_fill: ColorRect = $HUD/HPFill
@onready var gauge_fill: ColorRect = $HUD/GaugeBarFill
@onready var status_label: Label = $HUD/StatusLabel
@onready var message_label: Label = $HUD/MessageLabel

const GAUGE_BAR_WIDTH := 240.0

var _dummy_target: ShipNode
var _formation: Array[TurretNode] = []
var _formation_total := 0
var _bob_time := 0.0
var _resolved := false
var _cheat_win_prev := false

func _ready() -> void:
	var character: CharacterData = CampaignContext.campaign.character if CampaignContext.campaign else null

	_dummy_target = ShipNode.new()
	_dummy_target.side = 1
	_dummy_target.position = Vector2(FORMATION_START_X + (FORMATION_COLS - 1) * FORMATION_PITCH_X / 2.0, FORMATION_START_Y + (FORMATION_ROWS - 1) * FORMATION_PITCH_Y / 2.0)
	_dummy_target.state = ShipState.new(_dummy_target.position, 1, _dummy_target.half_extents, ShipState.START_HP) # never added to the tree, its own _ready() never runs — see BreakoutNode's identical fix for why this must not stay null

	ship_1.set_character(character)
	ship_1.side = 0
	ship_1.player_index = 1
	ship_1.arena_bounds = ARENA_BOUNDS
	ship_1.frontier_x = FRONTIER_X
	ship_1.passive_trickle_rate = GAUGE_TRICKLE_RATE
	ship_1.weapon_fired.connect(_on_weapon_fired)
	ship_1.charged_weapon_fired.connect(_on_charged_weapon_fired)
	ship_1.gauge_filled.connect(_on_gauge_filled)

	_spawn_formation()
	message_label.text = ""

# 2026-08-22 — real alien art (Camil supplied two frames via Gemini, see
# sources/alien-1.png and alien-2.png). Loaded once and shared across every
# alien instance — TurretNode.sprite_textures just needs the array, it never
# mutates the textures themselves.
const ALIEN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/enemies/alien_1.png"),
	preload("res://assets/art/enemies/alien_2.png"),
]

func _spawn_formation() -> void:
	var alien_weapon := WeaponData.new()
	alien_weapon.turret_hp = ALIEN_HP
	alien_weapon.fire_rate = ALIEN_FIRE_RATE
	alien_weapon.damage = ALIEN_DAMAGE
	for row in FORMATION_ROWS:
		for col in FORMATION_COLS:
			var alien := TurretNode.new()
			alien.weapon = alien_weapon
			alien.owner_side = 1
			alien.autofire = true
			alien.target = ship_1
			alien.lifetime_override = 999999.0
			alien.half_extents = FORMATION_HALF_EXTENTS
			alien.color_override = ALIEN_COLOR
			alien.sprite_textures = ALIEN_TEXTURES
			alien.ball_bounce_damage = 0.0 # no ball in this mini-jeu at all
			alien.position = Vector2(FORMATION_START_X + col * FORMATION_PITCH_X, FORMATION_START_Y + row * FORMATION_PITCH_Y)
			add_child(alien)
			# 2026-08-22 bug report ("ils tirent tous en meme temps") —
			# TurretNode._ready() seeds _fire_cooldown from the SAME shared
			# alien_weapon.fire_rate for every alien, and they're all added
			# to the tree in the same frame, so every cooldown counted down
			# in perfect lockstep — a synchronized volley instead of
			# individually-timed fire. Re-randomize each one's cooldown
			# right after _ready() has already set it once.
			alien._fire_cooldown = randf_range(0.0, 1.0 / ALIEN_FIRE_RATE)
			_formation.append(alien)
	_formation_total = _formation.size()

func _physics_process(delta: float) -> void:
	if _resolved:
		return

	# Camil: "on peut garder la touche 'K' pour finir le niveau direct ?"
	# — same cheat key/convention as a normal match's own K (instant-kill
	# ship_2, ungated by OS.is_debug_build()), adapted to this mode's own
	# win condition: clearing the whole formation.
	var cheat_win_pressed := Input.is_physical_key_pressed(KEY_K)
	if cheat_win_pressed and not _cheat_win_prev:
		for alien in _formation.duplicate():
			if is_instance_valid(alien):
				alien.queue_free()
	_cheat_win_prev = cheat_win_pressed

	_update_hud()

	var alive: Array[TurretNode] = _formation.filter(func(a): return is_instance_valid(a))
	if alive.is_empty():
		_resolved = true
		_freeze_gameplay()
		_resolve.call_deferred(true)
		return
	if ship_1.state.hp <= 0.0:
		_resolved = true
		_freeze_gameplay()
		_resolve.call_deferred(false, "Vous avez ete detruit")
		return

	# Fewer aliens left -> faster advance, same "the room gets smaller"
	# tension curve the genre is built on.
	var alive_ratio := float(alive.size()) / float(_formation_total)
	var speed_scale := lerpf(1.0, 2.5, 1.0 - alive_ratio)
	_bob_time += delta
	var bob_offset := sin(_bob_time * BOB_ANGULAR_SPEED) * BOB_AMPLITUDE * delta
	for alien in alive:
		alien.position.x -= ADVANCE_SPEED * speed_scale * delta
		alien.position.y += bob_offset
		# 2026-08-22 (Camil: "c'est quasi impossible. Il faudrait attendre
		# que l'ennemi touche vraiment la ligne centrale pour la defaite")
		# — was FRONTIER_X + INVASION_MARGIN (a 60px buffer before the
		# line), which combined with the new 8-row portrait formation made
		# invasion trigger way too early. Now only the alien's own leading
		# edge actually crossing the line counts.
		if alien.position.x - FORMATION_HALF_EXTENTS.x <= FRONTIER_X:
			_resolved = true
			_freeze_gameplay()
			_resolve.call_deferred(false, "L'ennemi a atteint la ligne centrale")
			return

func _freeze_gameplay() -> void:
	ship_1.active = false
	for alien in _formation:
		if is_instance_valid(alien):
			alien.autofire = false
	for child in get_children():
		if child is ProjectileNode and child.target == ship_1:
			child.queue_free()

func _update_hud() -> void:
	hp_fill.size.x = 240.0 * clampf(ship_1.state.hp / ship_1.max_hp_override, 0.0, 1.0)
	if not ship_1.weapon_state:
		return
	var weapon := ship_1.weapon_state.selected_weapon()
	var index := ship_1.weapon_state.selected_index
	gauge_fill.color = _weapon_tint(weapon.id)
	gauge_fill.size.x = GAUGE_BAR_WIDTH * (clampf(ship_1.weapon_state.gauges[index] / weapon.gauge_max, 0.0, 1.0) if weapon.gauge_max > 0.0 else 0.0)
	var alive_count := _formation.filter(func(a): return is_instance_valid(a)).size()
	status_label.text = "%s   Envahisseurs restants: %d" % [weapon.display_name, alive_count]

func _on_gauge_filled(amount: float) -> void:
	var popup := FloatingTextNode.new()
	popup.position = ship_1.position + Vector2(0.0, -16.0)
	popup.text = "+%d" % int(amount)
	add_child(popup)

## Mirrors BreakoutNode's own weapon dispatch exactly (itself mirroring
## MatchArenaNode._on_weapon_fired()/_on_charged_weapon_fired()) — see
## those files for why this isn't further de-duplicated yet (BreakoutNode
## was already live/tuned before this one existed; worth a real shared
## base class if a third mini-jeu ever needs the same dispatch again).
func _on_weapon_fired(weapon: WeaponData) -> void:
	if weapon.projectile_count <= 1:
		_fire_shot(weapon, 0.0)
		return
	for i in weapon.projectile_count:
		var p := float(i) / float(maxi(weapon.projectile_count - 1, 1))
		var angle_offset := lerpf(-weapon.burst_spread_deg / 2.0, weapon.burst_spread_deg / 2.0, p)
		if weapon.burst_stagger > 0.0 and i > 0:
			get_tree().create_timer(i * weapon.burst_stagger).timeout.connect(_fire_shot.bind(weapon, angle_offset))
		else:
			_fire_shot(weapon, angle_offset)

func _on_charged_weapon_fired(weapon: WeaponData) -> void:
	if weapon.effect_type == "turret":
		_spawn_player_turret(weapon, true)
		return
	if weapon.effect_type == "beam":
		var duration := weapon.charged_beam_duration if weapon.charged_beam_duration > 0.0 else weapon.beam_duration
		_spawn_beam(weapon, duration, weapon.charged_beam_thickness_multiplier)
		if weapon.charged_beam_shooter_slow_multiplier < 1.0:
			ship_1.apply_charged_beam_slow(duration, weapon.charged_beam_shooter_slow_multiplier)
		return
	if weapon.charged_double_fire_shots > 0:
		ship_1.grant_double_fire(weapon.charged_double_fire_shots)
		return
	if weapon.charged_projectile_count <= 1:
		_fire_shot(weapon, 0.0, weapon.charged_damage_multiplier, weapon.charged_speed_multiplier, weapon.charged_boomerang_out_duration, weapon.charged_visual_scale_multiplier, true)
		return
	for i in weapon.charged_projectile_count:
		var p := float(i) / float(maxi(weapon.charged_projectile_count - 1, 1))
		var t := (1.0 - absf(2.0 * p - 1.0)) if weapon.charged_burst_ping_pong else p
		var angle_offset := lerpf(-weapon.charged_burst_spread_deg / 2.0, weapon.charged_burst_spread_deg / 2.0, t)
		if weapon.charged_stagger > 0.0 and i > 0:
			get_tree().create_timer(i * weapon.charged_stagger).timeout.connect(_fire_shot.bind(weapon, angle_offset, weapon.charged_damage_multiplier, weapon.charged_speed_multiplier))
		else:
			_fire_shot(weapon, angle_offset, weapon.charged_damage_multiplier, weapon.charged_speed_multiplier)

func _spawn_player_turret(weapon: WeaponData, is_charged: bool = false) -> void:
	var turret := TurretNode.new()
	turret.position = ship_1.position
	turret.weapon = weapon
	turret.target = _dummy_target
	turret.owner_side = 0
	if is_charged:
		turret.fire_rate_multiplier = weapon.charged_turret_fire_rate_multiplier
		turret.lifetime_override = weapon.charged_turret_lifetime
	add_child(turret)

func _spawn_beam(weapon: WeaponData, duration: float, thickness_multiplier: float) -> void:
	var beam := BeamNode.new()
	beam.shooter = ship_1
	beam.target = _dummy_target
	beam.arena_bounds = ARENA_BOUNDS
	beam.weapon = weapon
	beam.lifetime = duration
	beam.thickness_multiplier = thickness_multiplier
	var tint := _weapon_tint(weapon.id)
	beam.color = Color(tint.r, tint.g, tint.b, 0.7)
	add_child(beam)

func _fire_shot(weapon: WeaponData, angle_offset_deg: float, damage_multiplier: float = 1.0, speed_multiplier: float = 1.0, boomerang_out_duration_override: float = 0.0, size_multiplier: float = 1.0, force_no_burst_shrink: bool = false) -> void:
	if not is_instance_valid(ship_1):
		return
	var projectile := ProjectileFactory.spawn(weapon, ship_1, _dummy_target, angle_offset_deg, speed_multiplier, Vector2.ZERO, boomerang_out_duration_override, damage_multiplier, size_multiplier, force_no_burst_shrink)
	add_child(projectile)

func _weapon_tint(weapon_id: String) -> Color:
	return ProjectileFactory.weapon_tint(weapon_id)

## Mirrors MatchArenaNode._resolve_campaign_result()'s mook/non-organizer
## branch — this mini-jeu is never the rival/organizer slot either.
## `loss_reason` (Camil: "lors de la defaite dire pourquoi") names which of
## the two loss conditions fired — ignored on a win.
func _resolve(won: bool, loss_reason: String = "") -> void:
	var character_id: String = CampaignContext.campaign.character.id
	var current_encounter := CampaignContext.current_encounter()
	if won:
		CampaignSave.add_currency(character_id, current_encounter.reward_currency)
		message_label.text = "Victoire (+%d)" % current_encounter.reward_currency
		await get_tree().create_timer(1.5).timeout
		# 2026-08-31 graph-mode: mark node resolved by id; branch-mode uses
		# the old linear step counter.
		if CampaignContext.is_graph_mode:
			CampaignSave.add_resolved_case_id(character_id, CampaignContext.current_graph_node_id)
		else:
			# 2026-08-24 world-map rework — one flat step counter, always the
			# same single CampaignMap on return (no separate MiniBranchMap).
			CampaignContext.advance_step()
			CampaignSave.set_campaign_progress(character_id, CampaignContext.campaign_step)
		CampaignContext.return_to_map()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
	else:
		message_label.text = "Defaite... (%s)" % loss_reason if loss_reason != "" else "Defaite..."
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
