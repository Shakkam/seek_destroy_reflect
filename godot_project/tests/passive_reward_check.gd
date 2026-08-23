extends Node2D

## One-off scene-boot verification for the 2026-08-16 reward system, TWICE
## reworked same day: first pass (Camil: "on va mettre des trucs en face
## des recompenses. pour chaque rival vaincu.") had all 8 reduce to one
## verb ("auto-fire this weapon's own shot"); second pass ("on est un peu
## sur le meme pattern. Il faut etre plus creatif") replaced 7 of the 8
## with bespoke, hand-specified effects (Controleur's turret was already
## fine, untouched). Confirms: (1) no-unlock baseline, (2) stacked unlocks
## wire up exactly the 6 PERIODIC ones (not vortex/stun_boomerang — those
## two are handled differently, see below), (3) firing is gated on
## _round_playing, (4) each of the 7 bespoke effects actually does its own
## distinct thing. IMPORTANT: mark_branch_completed() below writes to the
## REAL save file (user://campaign_save.json) — reset_all() before AND
## after, same convention campaign_setup_check.gd already established.
## Run with:
##   Godot --headless --path godot_project res://tests/passive_reward_check.tscn --quit-after 300

func _ready() -> void:
	CampaignSave.reset_all()

	# --- (1) no unlocks -> no passive timers, no permanent bonus ---
	MatchSetup.p1_character = load("res://data/characters/vif.tres")
	MatchSetup.p2_character = load("res://data/characters/lourd.tres")
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena_bare := arena_scene.instantiate() as MatchArenaNode
	add_child(arena_bare)
	await get_tree().process_frame
	var no_unlock_ok: bool = _count_timers(arena_bare.ship_1) == 0 and is_equal_approx(arena_bare.ship_1._passive_speed_multiplier, 1.0)
	print("PASS: a character with no unlocks gets no passive timers or bonuses" if no_unlock_ok else "FAIL: a fresh character somehow got a passive effect")
	arena_bare.queue_free()
	await get_tree().process_frame

	# --- (2) all 8 unlocked at once on ship_1 (playing Vif) ---
	var all_weapon_ids := ["bazooka", "turret", "machine_gun", "vortex", "laser", "stun_boomerang", "homing_missile", "mini_shot"]
	for id in all_weapon_ids:
		CampaignSave.mark_branch_completed("vif", "fake_vs_%s" % id, id)
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var bazooka: WeaponData = load("res://data/weapons/bazooka.tres")
	var turret: WeaponData = load("res://data/weapons/turret.tres")
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var laser: WeaponData = load("res://data/weapons/laser.tres")
	var homing_missile: WeaponData = load("res://data/weapons/homing_missile.tres")
	var mini_shot: WeaponData = load("res://data/weapons/mini_shot.tres")

	# Only 6 of the 8 are periodic (Timer-driven) — vortex (Vif, permanent)
	# and stun_boomerang (Perturbateur, reactive on the ship's own Ultra)
	# deliberately get NO timer at all.
	var timer_count_ok: bool = _count_timers(arena.ship_1) == 6
	print(("PASS: exactly the 6 periodic rewards get a timer, not vortex/stun_boomerang (%d found)" % _count_timers(arena.ship_1)) if timer_count_ok else ("FAIL: expected 6 passive timers, found %d" % _count_timers(arena.ship_1)))
	var vif_permanent_ok: bool = is_equal_approx(arena.ship_1._passive_speed_multiplier, MatchArenaNode.PASSIVE_VIF_SPEED_MULTIPLIER)
	print(("PASS: Vif's passive is applied as a permanent multiplier at setup time (%.2f)" % arena.ship_1._passive_speed_multiplier) if vif_permanent_ok else "FAIL: Vif's permanent speed bonus was never applied")

	# --- (3) firing: gated on _round_playing ---
	arena._round_playing = false
	arena.ship_1.active = false
	var count_before_frozen := _count_projectiles(arena)
	arena._fire_passive_reward(arena.ship_1, bazooka)
	var frozen_gate_ok: bool = _count_projectiles(arena) == count_before_frozen
	print("PASS: a passive never fires while the match is frozen (_round_playing == false)" if frozen_gate_ok else "FAIL: a passive fired despite the match being frozen")

	arena._unfreeze_round() # real _round_playing = true + ship.active = true, same helper every other campaign test already uses

	# --- (4) the 7 bespoke effects ---

	# Controleur (untouched from the first pass): turret, own short lifetime.
	arena._fire_passive_reward(arena.ship_1, turret)
	var spawned_turret: TurretNode = null
	for child in arena.get_children():
		if child is TurretNode and child.weapon == turret:
			spawned_turret = child
	var turret_ok: bool = spawned_turret != null and is_equal_approx(spawned_turret.lifetime_override, MatchArenaNode.PASSIVE_TURRET_LIFETIME)
	print("PASS: Controleur's passive spawns a turret with its own short lifetime" if turret_ok else "FAIL: Controleur's passive turret was wrong or missing")
	if spawned_turret: # its own live autofire would otherwise pollute the Mitrailleur projectile-count check below (it waits real frames)
		spawned_turret.queue_free()

	# Mitrailleur (2026-08-22 rework, Camil: "ca ne me plait pas... ce soit
	# exactement le tir de mitrailleur (avec le meme sprite), mais lance
	# automatiquement, salve de 4, toutes les 3 secondes. Pas de module.")
	# — a real 4-shot burst of the exact normal projectile, no TurretNode
	# module at all. First shot lands immediately; the other 3 are staggered
	# via real Timers, so this needs actual frames to elapse before they
	# all land.
	var mg_projectiles_before := _count_projectiles(arena)
	arena._fire_passive_reward(arena.ship_1, machine_gun)
	var mg_immediate_ok: bool = _count_projectiles(arena) == mg_projectiles_before + 1
	print("PASS: Mitrailleur's passive fires the first shot immediately" if mg_immediate_ok else "FAIL: the immediate first burst shot never appeared")
	var mg_no_module_ok: bool = arena.get_children().filter(func(c): return c is TurretNode and c.weapon == machine_gun).is_empty()
	print("PASS: no satellite module spawns anymore ('pas de module')" if mg_no_module_ok else "FAIL: a TurretNode module still appeared")
	for i in 30: # stagger = 1.0/fire_rate (~0.11s/shot) * 3 remaining shots — well within 0.5s
		await get_tree().physics_frame
	var mg_burst_ok: bool = _count_projectiles(arena) == mg_projectiles_before + MatchArenaNode.PASSIVE_MITRAILLEUR_BURST_COUNT
	print(("PASS: the full 4-shot burst lands (%d new projectiles)" % (_count_projectiles(arena) - mg_projectiles_before)) if mg_burst_ok else ("FAIL: expected %d new projectiles, got %d" % [MatchArenaNode.PASSIVE_MITRAILLEUR_BURST_COUNT, _count_projectiles(arena) - mg_projectiles_before]))

	# Lourd: two Pluie-de-Scuds-style missile strikes (reticle + falling
	# shell) per interval (2026-08-22, Camil: "Passer a 2 scuds qui tombent
	# aleatoirement toutes les 3 secondes" — was 1 scud / 10s).
	var count_before_scud := 0
	for child in arena.get_children():
		if child is MissileStrikeNode:
			count_before_scud += 1
	arena._fire_passive_reward(arena.ship_1, bazooka)
	var count_after_scud := 0
	for child in arena.get_children():
		if child is MissileStrikeNode:
			count_after_scud += 1
	var scud_ok: bool = count_after_scud == count_before_scud + 2
	print("PASS: Lourd's passive drops two Scud-style missile strikes" if scud_ok else ("FAIL: expected 2 new missile strikes, got %d" % (count_after_scud - count_before_scud)))

	# Zoneur: one VERTICAL laser wall (start.x == end.x), confined to the
	# opponent's half.
	arena._fire_passive_reward(arena.ship_1, laser)
	var spawned_wall: LaserMeshNode = null
	for child in arena.get_children():
		if child is LaserMeshNode:
			spawned_wall = child
	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	var frontier_x: float = arena.arena_origin.x + arena.arena_size.x / 2.0
	var wall_vertical_ok: bool = spawned_wall != null and is_equal_approx(spawned_wall.start.x, spawned_wall.end.x)
	var wall_in_opponent_half_ok: bool = spawned_wall != null and spawned_wall.start.x >= frontier_x # ship_2 (the opponent here) is side 1, the right half
	var wall_spans_top_to_bottom_ok: bool = spawned_wall != null and is_equal_approx(spawned_wall.start.y, bounds.position.y) and is_equal_approx(spawned_wall.end.y, bounds.position.y + bounds.size.y)
	print("PASS: Zoneur's passive is a vertical laser wall (start.x == end.x)" if wall_vertical_ok else "FAIL: Zoneur's passive laser wasn't vertical")
	print("PASS: the wall stays confined to the opponent's half" if wall_in_opponent_half_ok else "FAIL: the wall wasn't in the opponent's half")
	print("PASS: the wall spans the full top-to-bottom height" if wall_spans_top_to_bottom_ok else "FAIL: the wall didn't span the full height")

	# 2026-08-22 (Camil: "il faudrait que le laser se deplace jusqu'au
	# centre (s'il apparait vers le fond) ou vers le fond (s'il apparait
	# vers le centre)") — sweeps toward whichever edge it's farther from,
	# timed to land there exactly as its lifetime ends.
	var back_edge_x: float = bounds.position.x + bounds.size.x # ship_2 is side 1 (right half) — the frontier is its OWN near edge, the arena's right wall is its back edge
	var target_edge_x: float = back_edge_x if spawned_wall != null and absf(spawned_wall.start.x - frontier_x) < absf(spawned_wall.start.x - back_edge_x) else frontier_x
	var expected_velocity: float = (target_edge_x - spawned_wall.start.x) / MatchArenaNode.PASSIVE_ZONEUR_LASER_LIFETIME if spawned_wall != null else 0.0
	var wall_sweeps_ok: bool = spawned_wall != null and is_equal_approx(spawned_wall.horizontal_velocity, expected_velocity)
	print(("PASS: the wall sweeps toward the farther edge (velocity %.1f px/s)" % spawned_wall.horizontal_velocity) if wall_sweeps_ok else "FAIL: the wall's sweep velocity didn't aim at the expected far edge")
	# Only tick halfway into its lifetime — ticking all the way to
	# PASSIVE_ZONEUR_LASER_LIFETIME would queue_free() the node (its own
	# expiry check), leaving nothing left to read start.x from afterward.
	var spawn_x: float = spawned_wall.start.x
	for i in 45: # half of PASSIVE_ZONEUR_LASER_LIFETIME (1.5s) @ 60fps
		spawned_wall._physics_process(1.0 / 60.0)
	var expected_halfway_x: float = spawn_x + expected_velocity * (45.0 / 60.0)
	var wall_sweep_progress_ok: bool = is_equal_approx(spawned_wall.start.x, expected_halfway_x) and is_equal_approx(spawned_wall.end.x, expected_halfway_x)
	print(("PASS: the sweep actually moves the wall toward the far edge (%.1f -> %.1f)" % [spawn_x, spawned_wall.start.x]) if wall_sweep_progress_ok else "FAIL: the wall didn't move as expected while sweeping")

	# Traqueur: exactly ONE homing missile (not the normal 3-burst, not the
	# 6-missile charged rafale).
	var count_before_missile := _count_projectiles(arena)
	arena._fire_passive_reward(arena.ship_1, homing_missile)
	var single_missile_ok: bool = _count_projectiles(arena) - count_before_missile == 1
	print(("PASS: Traqueur's passive fires exactly 1 missile (not %d normal or %d charged)" % [homing_missile.projectile_count, homing_missile.charged_projectile_count]) if single_missile_ok else ("FAIL: expected exactly 1 new projectile, got %d" % (_count_projectiles(arena) - count_before_missile)))

	# Spreader: heals 15% of MAX hp (not a flat number), plus the cosmetic
	# orbiting-fan flourish actually spawns.
	arena.ship_1.apply_damage(40.0) # chip HP first so the heal is observable
	var hp_before_heal: float = arena.ship_1.state.hp
	arena._fire_passive_reward(arena.ship_1, mini_shot)
	var expected_heal: float = arena.ship_1.max_hp_override * MatchArenaNode.PASSIVE_SPREADER_HEAL_FRACTION
	var heal_ok: bool = is_equal_approx(arena.ship_1.state.hp - hp_before_heal, expected_heal)
	print(("PASS: Spreader's passive heals 15%% of max HP (%.1f -> %.1f, +%.1f)" % [hp_before_heal, arena.ship_1.state.hp, expected_heal]) if heal_ok else "FAIL: Spreader's heal amount was wrong"
	)
	var fan_fx_ok: bool = false
	for child in arena.ship_1.get_children():
		if child is PassiveHealFxNode:
			fan_fx_ok = true
	print("PASS: the orbiting-fan flourish actually spawns on the ship" if fan_fx_ok else "FAIL: no PassiveHealFxNode appeared")

	# 2026-08-22 (Camil: "on devrait voir un '+X' en vert qui monte pour
	# indiquer qu'on gagne des PV") — a green FloatingTextNode popup, same
	# convention as the gauge-fill "+X" (_on_gauge_filled()), distinct color.
	var heal_popup_ok: bool = false
	for child in arena.get_children():
		if child is FloatingTextNode and child.color.is_equal_approx(MatchArenaNode.PASSIVE_HEAL_POPUP_COLOR) and child.text == "+%d" % int(expected_heal):
			heal_popup_ok = true
	print(("PASS: the heal shows a green '+%d' popup" % int(expected_heal)) if heal_popup_ok else "FAIL: no matching green heal popup appeared")

	# Perturbateur: reactive on the SHIP'S OWN Ultra cast, not a timer —
	# call the hook directly (same thing _on_ultra_triggered() does after
	# resolving the real Ultra effect) and confirm the OPPONENT gets a 5s
	# scramble.
	var scramble_before_ok: bool = arena.ship_2._controls_scrambled_timer <= 0.0 # sanity: nothing armed yet
	arena._apply_perturbateur_ultra_passive(arena.ship_1)
	var scramble_ok: bool = arena.ship_2._controls_scrambled_timer > 0.0 and arena.ship_2._controls_scrambled_timer <= MatchArenaNode.PASSIVE_PERTURBATEUR_ULTRA_SCRAMBLE_DURATION + 0.01
	print("PASS: Perturbateur's passive scrambles the opponent for 5s when the player's OWN Ultra fires" if scramble_before_ok and scramble_ok else "FAIL: the Ultra-linked scramble wasn't applied correctly")

	CampaignSave.reset_all() # never leave fake progress in the real save file
	MatchSetup.p1_character = null
	MatchSetup.p2_character = null

	var all_ok := no_unlock_ok and timer_count_ok and vif_permanent_ok and frozen_gate_ok \
		and turret_ok and mg_immediate_ok and mg_no_module_ok and mg_burst_ok and scud_ok \
		and wall_vertical_ok and wall_in_opponent_half_ok and wall_spans_top_to_bottom_ok and wall_sweeps_ok and wall_sweep_progress_ok \
		and single_missile_ok and heal_ok and fan_fx_ok and heal_popup_ok and scramble_before_ok and scramble_ok
	get_tree().quit(0 if all_ok else 1)

func _count_timers(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Timer:
			n += 1
	return n

func _count_projectiles(arena: Node) -> int:
	var n := 0
	for child in arena.get_children():
		if child is ProjectileNode:
			n += 1
	return n
