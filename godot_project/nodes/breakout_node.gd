class_name BreakoutNode
extends Node2D

## Breakout mini-jeu (2026-08-18) — a campaign-map "mook" encounter slot
## can be this instead of a real fight (RivalEncounterData.challenge_type
## == "breakout"). REBUILT after live feedback: "il faudrait vraiment
## garder le pattern actuel (deplacements 2D, ligne au milieu, les
## briques et ennemis apparaitraient a droite)... la tu m'as 'juste' fait
## un breakout qui est en dehors du systeme de jeu." First pass was
## custom from-scratch simulation classes — a separate arcade clone, not
## actually IN the game. This version reuses the real game systems
## wholesale instead of reinventing them:
##   - Ship1 is a REAL ShipNode (full 2D movement/lift/weapon, side 0,
##     same controls as Player 1 always has) — not a horizontal-only paddle.
##   - Ball is a REAL BallNode/BallState — same wall bounce, same
##     paddle-return-with-aim, same speed-up-per-rally.
##   - Bricks AND popup enemies are BOTH just TurretNode instances
##     (owner_side=1, color_override for a distinct look) — HP/destruction,
##     ball-deflection (BallNode._resolve_turrets(), unmodified), and
##     weapon-projectile hit detection (ProjectileNode's existing swept
##     turret-hit check, unmodified) all come for free. Bricks: autofire
##     off, don't shoot. Enemies: autofire on, target=ship_1, "tir banal"
##     (Camil: "un tir banal... mais qui popent par groupes de 2 ou 3").
##   - A single "combat" no-side-1-ship means BallNode's normal miss/OOB
##     scoring loop finds no side-1 recipient — added BallNode.ball_missed
##     signal so this scene can dock ship_1's own HP on a miss instead
##     (reuses ShipNode.apply_damage(), same HP bar/death-at-0 the main
##     game already has — no separate "lives" counter needed). The far
##     side (past the bricks) is the opposite: Camil wanted it to bounce
##     like a wall instead of vanishing/respawning center-screen like a
##     classic Breakout — BallNode.bounces_off_right_wall (opt-in, unused
##     by the real match) handles that.
##   - Weapon fire reuses ProjectileFactory.spawn() (2026-08-18, extracted
##     from MatchArenaNode._spawn_projectile() after Camil's follow-up:
##     "pas mal mais il faut que le joueur garde ses armes habituelles" —
##     a first pass with generic tinted shapes/straight trajectories
##     wasn't good enough) — the exact same textures/boomerang arc/vortex
##     sine/homing every character's weapon has in a real match. Turret
##     (Controleur)/beam (Zoneur)/double-fire (Mitrailleur) charged
##     releases are also supported, reusing TurretNode/BeamNode directly.
##   - target = a bare ShipNode.new() (side=1, never added to the tree —
##     only `.side`/`.position` are ever read by the reused hit-detection
##     code) so the existing turret-hit-check's `target.side` filter
##     resolves correctly without a second real, playable ship.

const ARENA_BOUNDS := Rect2(Vector2(40.0, 60.0), Vector2(1200.0, 600.0))
# 2026-08-18 (Camil, reference screenshot: "ligne de separation plus proche
# du centre... remplissage de l'espace") — was 420, moved right so the
# player's own zone reads closer to a normal match's own half instead of
# a narrow strip, while the brick wall gets pushed to fill what's left.
const FRONTIER_X := 580.0
const MISS_DAMAGE := 18.0 # HP lost when the ball gets past the player, reuses ShipNode.apply_damage()

# 2026-08-18 (Camil: "briques plus longues, serrees, et couleurs
# differentes") — bigger per-brick footprint (TurretNode.half_extents,
# now an instance field, see that file) and PITCH == 2x half_extents
# (touching, zero gap) instead of the old spaced-out grid.
# 2026-08-18 follow-up, after playing it ("mega dur... les briques
# apparaissent toujours carrees, il faudrait qu'elles soient
# rectangulaires 56*96, qu'il y en ait moins") — the first 10x10 pass
# (56x48 bricks, 100 of them) read as squarish and was too much of a
# grind. Taller (56x96) rectangles naturally fit far fewer per column,
# so cutting COLS too gives 8x5=40 total (was 100) without a separate
# HP-pool rebalance.
const BRICK_HALF_EXTENTS := Vector2(28.0, 48.0)
const BRICK_COLS := 8
const BRICK_ROWS := 5
const BRICK_PITCH_X := BRICK_HALF_EXTENTS.x * 2.0
const BRICK_PITCH_Y := BRICK_HALF_EXTENTS.y * 2.0
const BRICK_FIELD_START_X := 690.0
const BRICK_FIELD_START_Y := 130.0
const BRICK_HP := 1.0
# 2026-08-18: one color per COLUMN, matching the reference's rainbow
# columns, cycled if BRICK_COLS ever exceeds this list's length.
const BRICK_COLUMN_COLORS := [
	Color(0.8, 0.3, 0.9), Color(0.3, 0.55, 0.95), Color(0.35, 0.85, 0.4),
	Color(0.95, 0.85, 0.25), Color(0.95, 0.6, 0.2), Color(0.9, 0.3, 0.3),
]

# 2026-08-18 (Camil, after playing it: "mega dur... les ennemis
# apparaissent 2x moins souvent") — was 6.0.
const ENEMY_SPAWN_INTERVAL := 12.0
const ENEMY_MAX_ALIVE := 5
const ENEMY_HP := 4.0
const ENEMY_FIRE_RATE := 0.6 # a basic, occasional shot — "un tir banal... pas de mitraillage"
const ENEMY_DAMAGE := 4.0
const ENEMY_COLOR := Color(0.85, 0.3, 0.9)

@onready var ship_1: ShipNode = $Ship1
@onready var ball: BallNode = $Ball
@onready var hp_fill: ColorRect = $HUD/HPFill
@onready var gauge_fill: ColorRect = $HUD/GaugeBarFill
@onready var status_label: Label = $HUD/StatusLabel
@onready var message_label: Label = $HUD/MessageLabel

const GAUGE_BAR_WIDTH := 240.0

var _dummy_target: ShipNode
var _bricks: Array[TurretNode] = []
var _enemies: Array[TurretNode] = []
var _enemy_spawn_timer := ENEMY_SPAWN_INTERVAL
var _resolved := false
var _cheat_win_prev := false

# 2026-08-18 (Camil: "quand on perd la balle faudrait un petit decompte
# '3-2-1' et hop ca repart") — freezes ship_1/ball/enemy fire for a beat
# after a miss instead of resuming instantly, same "Pret?/GO!" pacing
# idea MatchArenaNode's own round-start gate already uses, just simpler
# (a plain numeric count, no separate ready/go phases).
const COUNTDOWN_TICK := 1.0
var _countdown_value := 0
var _countdown_timer := 0.0

func _ready() -> void:
	var character: CharacterData = CampaignContext.campaign.character if CampaignContext.campaign else null

	_dummy_target = ShipNode.new()
	_dummy_target.side = 1
	_dummy_target.position = Vector2(BRICK_FIELD_START_X + (BRICK_COLS - 1) * BRICK_PITCH_X / 2.0, BRICK_FIELD_START_Y + (BRICK_ROWS - 1) * BRICK_PITCH_Y / 2.0)
	# Never added to the tree (only `.side`/`.position` are meant to be
	# read by the reused hit-detection code) — its own _ready() never
	# runs, so `.state` stays null. A player-fired projectile whose
	# straight path happens to actually reach this point (it sits inside
	# the brick field, deliberately, so homing weapons have somewhere
	# sane to curve toward) still runs the normal ship-hit check and
	# calls apply_damage() on it — crashed live ("Nonexistent function
	# 'damaged' in base 'Nil'") without a real state to damage. The
	# resulting "damage" is never read by anything; this only exists to
	# make that incidental call a harmless no-op instead of a crash.
	_dummy_target.state = ShipState.new(_dummy_target.position, 1, _dummy_target.half_extents, ShipState.START_HP)

	ship_1.set_character(character)
	ship_1.side = 0
	ship_1.player_index = 1
	ship_1.arena_bounds = ARENA_BOUNDS
	ship_1.frontier_x = FRONTIER_X
	ship_1.weapon_fired.connect(_on_weapon_fired)
	ship_1.charged_weapon_fired.connect(_on_charged_weapon_fired)
	# Camil: "il faudrait afficher la jauge d'arme et les +x quand on
	# gagne des munitions" — ship_1.gauge_filled ALREADY fires every time
	# it returns the ball (BallNode._resolve_ships() -> ShipNode.
	# fill_selected_gauge_from_return(), unmodified real match code); this
	# was just never listened to here. Mirrors MatchArenaNode._on_gauge_
	# filled() exactly (same FloatingTextNode popup).
	ship_1.gauge_filled.connect(_on_gauge_filled)

	ball.ships = [ship_1]
	ball.arena_bounds = ARENA_BOUNDS
	ball.frontier_x = FRONTIER_X
	ball.bounces_off_right_wall = true # Camil: "la balle rebondisse aussi au fond oppose, au lieu de reapparaitre au milieu"
	# Camil: "dans ce mode (uniquement) il faudrait que la balle commence
	# a une vitesse un peu moindre. disons 70%". Ball1's own _ready()
	# already ran (children ready before their parent) and spawned a
	# FULL-speed velocity before this line ever executes — re-spawn now
	# that the multiplier is actually set, or the very first launch would
	# stay at 100% and only respawns-after-a-miss would be slowed.
	ball.initial_speed_multiplier = 0.7
	# Camil: "le taux d'acceleration de la balle au rebond doit etre moins
	# fort dans ce mode de jeu uniquement" — halved; Breakout racks up far
	# more bounces per rally (bricks, not just one paddle exchange) than
	# the normal match this rate was tuned for.
	ball.speed_increment_multiplier = 0.5
	ball.reset_to_center()
	ball.ball_missed.connect(_on_ball_missed)

	_spawn_brick_grid()
	message_label.text = ""

func _spawn_brick_grid() -> void:
	var brick_weapon := WeaponData.new()
	brick_weapon.turret_hp = BRICK_HP
	brick_weapon.fire_rate = 1.0
	for row in BRICK_ROWS:
		for col in BRICK_COLS:
			var brick := TurretNode.new()
			brick.weapon = brick_weapon
			brick.owner_side = 1
			brick.autofire = false
			brick.target = _dummy_target # liveness check in _physics_process needs SOME valid target even when autofire is off
			brick.lifetime_override = 999999.0 # persists until destroyed, never expires on a timer
			brick.half_extents = BRICK_HALF_EXTENTS
			# 2026-08-18 (bug report: "les tirs s'arretent sur du vide") —
			# bricks touch edge-to-edge on the full hitbox; the default 0.8
			# visual ratio left a visible gap between them that didn't
			# match, so shots/the ball appeared to stop short of anything
			# visible. Close to 1.0 instead, just enough seam left to still
			# read as separate bricks.
			brick.visual_fill_ratio = 0.96
			brick.color_override = BRICK_COLUMN_COLORS[col % BRICK_COLUMN_COLORS.size()]
			brick.ball_bounce_damage = 1.0 # classic Breakout — every ball bounce also chips it, unlike a real Controleur turret
			brick.position = Vector2(BRICK_FIELD_START_X + col * BRICK_PITCH_X, BRICK_FIELD_START_Y + row * BRICK_PITCH_Y)
			add_child(brick)
			_bricks.append(brick)

func _physics_process(delta: float) -> void:
	if _resolved:
		return

	# Camil: "on peut garder la touche 'K' pour finir le niveau direct ?"
	# — same cheat key/convention as a normal match's own K (instant-kill
	# ship_2, ungated by OS.is_debug_build()), adapted to this mode's own
	# win condition: clearing every brick.
	var cheat_win_pressed := Input.is_physical_key_pressed(KEY_K)
	if cheat_win_pressed and not _cheat_win_prev:
		for brick in _bricks.duplicate():
			if is_instance_valid(brick):
				brick.queue_free()
	_cheat_win_prev = cheat_win_pressed

	if _countdown_value > 0:
		_countdown_timer -= delta
		if _countdown_timer <= 0.0:
			_countdown_value -= 1
			_countdown_timer = COUNTDOWN_TICK
			if _countdown_value > 0:
				message_label.text = str(_countdown_value)
			else:
				_end_countdown()
	else:
		_enemy_spawn_timer -= delta
		if _enemy_spawn_timer <= 0.0:
			_enemy_spawn_timer = ENEMY_SPAWN_INTERVAL
			_spawn_enemy_group()

	_update_hud()

	var bricks_alive := _bricks.any(func(b): return is_instance_valid(b))
	if not bricks_alive:
		_resolved = true
		_freeze_gameplay() # Camil: "quand il y a 'defaite' il faut tout freezer" — same for a win, nothing should keep moving/firing during the result message
		_resolve.call_deferred(true)
	elif ship_1.state.hp <= 0.0:
		_resolved = true
		_freeze_gameplay()
		_resolve.call_deferred(false)

func _spawn_enemy_group() -> void:
	var alive_count := _enemies.filter(func(e): return is_instance_valid(e)).size()
	if alive_count >= ENEMY_MAX_ALIVE:
		return
	var enemy_weapon := WeaponData.new()
	enemy_weapon.turret_hp = ENEMY_HP
	enemy_weapon.fire_rate = ENEMY_FIRE_RATE
	enemy_weapon.damage = ENEMY_DAMAGE
	var group_size: int = [2, 3].pick_random()
	for i in group_size:
		var enemy := TurretNode.new()
		enemy.weapon = enemy_weapon
		enemy.owner_side = 1
		enemy.autofire = true
		enemy.target = ship_1 # enemies actually shoot AT the player, unlike bricks
		enemy.color_override = ENEMY_COLOR
		enemy.ball_bounce_damage = 1.0 # Camil: "il faudrait que la balle fasse des degats aux ennemis. On casse les regles pour ce mode." — a real Controleur turret still never takes ball-bounce damage (see the field's own doc comment), Breakout's enemies now do too, same as bricks
		# 2026-08-18: the denser 10x10 grid (see BRICK_FIELD_START_Y) leaves
		# no headroom above it anymore — enemies now pop up scattered
		# across the field's own vertical extent instead of strictly above
		# it, reading as "emerging from among the bricks."
		enemy.position = Vector2(
			randf_range(BRICK_FIELD_START_X - 20.0, BRICK_FIELD_START_X + (BRICK_COLS - 1) * BRICK_PITCH_X + 20.0),
			randf_range(BRICK_FIELD_START_Y - 10.0, BRICK_FIELD_START_Y + (BRICK_ROWS - 1) * BRICK_PITCH_Y + 10.0)
		)
		add_child(enemy)
		_enemies.append(enemy)

func _on_ball_missed(side: int) -> void:
	if side != 0:
		return
	ship_1.apply_damage(MISS_DAMAGE)
	_start_countdown()

## Freezes ship_1/ball (same "active" flag MatchArenaNode's own ready gate
## uses), pauses enemy fire, and clears any enemy shot already in flight —
## a frozen player still eating a shot fired before the freeze (or unable
## to dodge one at all) would feel unfair. Shared by the 3-2-1 countdown
## and the win/loss freeze (Camil: "quand il y a 'defaite' il faut tout
## freezer").
func _freeze_gameplay() -> void:
	ship_1.active = false
	ball.active = false
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.autofire = false
	for child in get_children():
		if child is ProjectileNode and child.target == ship_1: # enemy shots specifically — the player's own target the dummy, never ship_1
			child.queue_free()

func _start_countdown() -> void:
	_freeze_gameplay()
	_countdown_value = 3
	_countdown_timer = COUNTDOWN_TICK
	message_label.text = str(_countdown_value)

func _end_countdown() -> void:
	message_label.text = ""
	ship_1.active = true
	ball.active = true
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.autofire = true

func _update_hud() -> void:
	hp_fill.size.x = 240.0 * clampf(ship_1.state.hp / ship_1.max_hp_override, 0.0, 1.0)
	var bricks_left := _bricks.filter(func(b): return is_instance_valid(b)).size()
	if not ship_1.weapon_state:
		return
	var weapon := ship_1.weapon_state.selected_weapon()
	var index := ship_1.weapon_state.selected_index
	gauge_fill.color = _weapon_tint(weapon.id)
	gauge_fill.size.x = GAUGE_BAR_WIDTH * (clampf(ship_1.weapon_state.gauges[index] / weapon.gauge_max, 0.0, 1.0) if weapon.gauge_max > 0.0 else 0.0)
	status_label.text = "%s   Briques restantes: %d" % [weapon.display_name, bricks_left]

func _on_gauge_filled(amount: float) -> void:
	var popup := FloatingTextNode.new()
	popup.position = ship_1.position + Vector2(0.0, -16.0)
	popup.text = "+%d" % int(amount)
	add_child(popup)

## 2026-08-18 (Camil, after seeing the first pass's generic visuals: "pas
## mal mais il faut que le joueur garde ses armes habituelles") — mirrors
## MatchArenaNode._on_weapon_fired()'s burst/stagger/spread shape exactly,
## calling ProjectileFactory.spawn() for the real per-weapon texture/
## trajectory instead of a trimmed local fallback.
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

## Mirrors MatchArenaNode._on_charged_weapon_fired() — including the
## turret (Controleur)/beam (Zoneur)/double-fire (Mitrailleur) special
## cases, reusing TurretNode/BeamNode directly (same "just configure the
## real node differently" approach already used for bricks/enemies).
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
	beam.weapon = weapon # must be set before add_child() — add_child() calls _ready() synchronously, which reads weapon.beam_range
	beam.lifetime = duration
	beam.thickness_multiplier = thickness_multiplier
	var tint := _weapon_tint(weapon.id)
	beam.color = Color(tint.r, tint.g, tint.b, 0.7)
	add_child(beam)

## Same ProjectileFactory.spawn() the real match uses — real textures,
## real boomerang arc/vortex sine/homing, not a generic fallback shape.
func _fire_shot(weapon: WeaponData, angle_offset_deg: float, damage_multiplier: float = 1.0, speed_multiplier: float = 1.0, boomerang_out_duration_override: float = 0.0, size_multiplier: float = 1.0, force_no_burst_shrink: bool = false) -> void:
	if not is_instance_valid(ship_1):
		return
	var projectile := ProjectileFactory.spawn(weapon, ship_1, _dummy_target, angle_offset_deg, speed_multiplier, Vector2.ZERO, boomerang_out_duration_override, damage_multiplier, size_multiplier, force_no_burst_shrink)
	add_child(projectile)

func _weapon_tint(weapon_id: String) -> Color:
	return ProjectileFactory.weapon_tint(weapon_id)

## Mirrors MatchArenaNode._resolve_campaign_result()'s mook/non-organizer
## branch — Breakout is never the rival/organizer slot, so that's the
## only subset this needs to replicate.
func _resolve(won: bool) -> void:
	var character_id: String = CampaignContext.campaign.character.id
	var current_encounter := CampaignContext.current_encounter()
	if won:
		CampaignSave.add_currency(character_id, current_encounter.reward_currency)
		message_label.text = "Victoire (+%d)" % current_encounter.reward_currency
		await get_tree().create_timer(1.5).timeout
		# 2026-08-24 world-map rework — one flat step counter, always the
		# same single CampaignMap on return (no separate MiniBranchMap).
		CampaignContext.advance_step()
		CampaignSave.set_campaign_progress(character_id, CampaignContext.campaign_step)
		CampaignContext.return_to_map()
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
	else:
		message_label.text = "Defaite..."
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
