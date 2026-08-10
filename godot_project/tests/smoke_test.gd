extends SceneTree

## Headless smoke test for the "shmup juice pass" (2026-08-05) — exercises the
## pure simulation classes directly (no Input simulation needed/possible in
## headless mode) plus the node-level boomerang math via manual _physics_process
## calls. Run with:
##   Godot --headless --path godot_project -s res://tests/smoke_test.gd
## Not a permanent CI fixture — ad hoc verification for code written without
## a Godot runtime available. Safe to delete once trusted.

var _failures := 0

func _initialize() -> void:
	print("--- smoke test start ---")
	_test_beam_tick()
	_test_missile_swarm_data()
	_test_boomerang_motion()
	_test_mini_shot_data()
	_test_turret_destructible()
	_test_turret_ball_deflection()
	_test_turbo_trail()
	_test_gauge_floor_twist()
	_test_hazard_zone()
	_test_decoy_wander()
	_test_energy_orb_pickup()
	_test_ball_hazard_bounce()
	_test_twist_pool_authoring()
	_test_campaign_data_resources()
	_test_campaign_save()
	_test_campaign_context_sequencing()
	_test_campaign_context_debug_fight()
	_test_campaign_save_progress_tracking()
	_test_vif_campaign_authoring()
	_test_gauges_reset_between_rounds()
	_test_weapon_heat_gauge()
	_test_mitrailleur_heat_immunity_rule()
	_test_vif_dash_lift_rule()
	_test_weapon_exclusivity()
	_test_every_charge_capable_weapon_actually_slows()
	_test_vortex_weapon()
	_test_charged_fire_burst()
	_test_heavy_push_rule()
	# NOTE: a round-end turret cleanup test belongs here in spirit, but
	# MatchArenaNode can't be loaded under this harness — this file runs via
	# `-s`, which does not initialize project autoloads (confirmed 2026-08-07),
	# and match_arena_node.gd references the MatchSetup autoload at compile
	# time. See tests/round_end_check.gd for the scene-boot-based equivalent.
	print("--- smoke test done: %d failure(s) ---" % _failures)
	quit(1 if _failures > 0 else 0)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		_failures += 1

func _test_beam_tick() -> void:
	var laser: WeaponData = load("res://data/weapons/laser.tres")
	_check("laser effect_type == beam", laser.effect_type == "beam")
	_check("laser beam_range capped below full arena width (2026-08-05 playtest: force advancing)", laser.beam_range > 0.0 and laser.beam_range < 1000.0)
	var state := WeaponSystemState.new([laser])
	state = state.with_gauge_added(100.0)
	_check("laser gauge starts at max", state.gauges[0] == laser.gauge_max)

	# Drain across several ticks; must stay active while gauge lasts, then stop.
	var ticks := 0
	var active := true
	while active and ticks < 1000:
		var result := state.beam_tick(0.1)
		state = result.state
		active = result.active
		ticks += 1
	var expected_ticks := int(laser.gauge_max / (laser.gauge_cost_per_shot * 0.1))
	_check("beam drains over ~%d ticks (got %d)" % [expected_ticks, ticks], absi(ticks - expected_ticks) <= 1)
	_check("beam reports inactive once gauge is dry", not active)
	_check("gauge does not go negative", state.gauges[0] >= 0.0)

func _test_missile_swarm_data() -> void:
	var missile: WeaponData = load("res://data/weapons/homing_missile.tres")
	_check("missile projectile_count > 1", missile.projectile_count > 1)
	_check("missile burst_spread_deg > 0", missile.burst_spread_deg > 0.0)
	_check("missile still homes", missile.homing_strength > 0.0)

func _test_mini_shot_data() -> void:
	# Redesigned 2026-08-06: "mini zonk" idea dropped in favor of a fan burst
	# (Air Zonk-style card weapons) — max 1 shot/sec, 5 projectiles fanned out,
	# reusing the same projectile_count/burst_spread_deg system as the missile
	# swarm rather than the earlier "rapid single bullets" bullet-rain tuning.
	var mini: WeaponData = load("res://data/weapons/mini_shot.tres")
	_check("mini_shot fires at most once per second", mini.fire_rate <= 1.0)
	_check("mini_shot fans out 5 projectiles per shot", mini.projectile_count == 5)
	# 2026-08-06 playtest: "je resserrerais l'angle" — narrowed from the
	# original 70° fan, but still a fan (not a single tight line).
	_check("mini_shot fan is narrower than the original 70°", mini.burst_spread_deg > 0.0 and mini.burst_spread_deg < 70.0)
	_check("mini_shot fan fires simultaneously, not staggered like the missile swarm", mini.burst_stagger == 0.0)
	_check("mini_shot projectiles read 2x bigger (2026-08-06 playtest)", mini.visual_scale_multiplier >= 2.0)
	_check("mini_shot has no per-shot angle jitter (2026-08-06: 'pas de random sur les angles')", mini.spread_deg == 0.0)
	# 2026-08-09 (Camil, now that bonbon.png art exists): "l'animation : il
	# tourne sur lui meme assez vite. Tu peux doubler sa taille."
	_check("mini_shot's size was doubled with real art, then trimmed back to 70% (2026-08-09: 'un peu gros')", is_equal_approx(mini.visual_scale_multiplier, 2.8))
	_check("mini_shot spins in place (single-sprite art, no multi-frame cycle like the Tourbillon)", mini.projectile_spin_speed > 0.0)

	# 2026-08-09 — Mini's charged fire ("Tir charge : lance 10 des eventails
	# de haut en bas (un peu comme un arroseur automatique) avec un espace
	# de 1/8 de seconde entre chaque eventail"), reusing the same generic
	# charged_* burst framework as Lourd/Vif — no new engine code needed.
	_check("mini_shot has a charged fire configured", mini.charge_fire_duration > 0.0)
	_check("mini_shot's charged fire launches 10 shots", mini.charged_projectile_count == 10)
	_check("mini_shot's charged shots are staggered 1/8s apart", is_equal_approx(mini.charged_stagger, 0.125))
	_check("mini_shot's charged fire sweeps a wide vertical spread (top to bottom)", mini.charged_burst_spread_deg > 45.0)

	# 2026-08-09: "il faudrait resserer encore l'angle: 60, par contre
	# balayer de haut en bas puis remonter de bas en haut. ce serait bien
	# plus fun" — a triangle-wave sweep instead of one-way linear. The
	# actual burst spawn loop lives in MatchArenaNode (needs a scene/
	# autoloads), so just the formula is checked here directly, same
	# approach as the blink-period math above.
	_check("mini_shot's charged spread was narrowed to 60 deg", is_equal_approx(mini.charged_burst_spread_deg, 60.0))
	_check("mini_shot's charged sweep is a ping-pong (out and back), not one-way", mini.charged_burst_ping_pong)
	var count := mini.charged_projectile_count
	var mid := int(float(count - 1) / 2.0)
	var t_first := 1.0 - absf(2.0 * (0.0 / float(count - 1)) - 1.0)
	var t_mid := 1.0 - absf(2.0 * (float(mid) / float(count - 1)) - 1.0)
	var t_last := 1.0 - absf(2.0 * (float(count - 1) / float(count - 1)) - 1.0)
	_check("the ping-pong sweep starts at one extreme (t=0)", is_zero_approx(t_first))
	_check("the ping-pong sweep reaches near the other extreme around the middle shot", t_mid > 0.8) # an even shot count never lands exactly on the peak index
	_check("the ping-pong sweep returns to the start extreme by the last shot (t=0)", is_zero_approx(t_last))

func _test_boomerang_motion() -> void:
	var boomerang_data: WeaponData = load("res://data/weapons/stun_boomerang.tres")
	_check("stun_boomerang is_boomerang flag set", boomerang_data.is_boomerang)

	var shooter := ShipNode.new()
	shooter.position = Vector2(200, 300)

	var projectile := ProjectileNode.new()
	projectile.is_boomerang = true
	projectile.shooter = shooter
	projectile.position = shooter.position
	projectile.velocity = Vector2(620, 0)
	projectile.lifetime = 3.0
	projectile.textures = [] # forces the fallback Polygon2D path in _ready(), no art needed

	root.add_child(shooter)
	root.add_child(projectile)
	# _ready() only fires once the node is inside the tree and processes a
	# frame; manually invoke the physics step instead of waiting on real
	# engine ticks so this stays a synchronous, deterministic test.
	var outbound_start := projectile.position
	for i in 3: # ~0.1s in — should still be heading mostly toward the opponent, not diving off-axis
		projectile._physics_process(1.0 / 30.0)
	var early_angle_deg := absf(rad_to_deg(projectile.velocity.angle()))
	_check("boomerang still heads mostly forward early on (angle=%.0f°, was ~180° swing before the 2026-08-05 fix)" % early_angle_deg, early_angle_deg < 45.0)
	for i in 17: # remaining frames up to ~0.67s total — well past BOOMERANG_OUT_DURATION (0.45s)
		projectile._physics_process(1.0 / 30.0)
	_check("boomerang left its spawn point", projectile.position.distance_to(outbound_start) > 1.0)
	_check("boomerang has entered the return phase after 0.67s", projectile._boomerang_returning)

	# queue_free() defers actual deallocation to the next idle frame, which
	# never happens here since we're driving _physics_process manually rather
	# than running the real engine loop — so track the closest approach
	# instead of relying on is_instance_valid() to observe the free() call.
	var closest := INF
	for i in 60: # give it time to actually arc back toward the shooter
		if not is_instance_valid(projectile):
			break
		projectile._physics_process(1.0 / 30.0)
		closest = minf(closest, projectile.position.distance_to(shooter.position))
	_check("boomerang comes within catch distance of the shooter (closest=%.1f)" % closest, closest < ProjectileNode.BOOMERANG_CATCH_DISTANCE)

	shooter.queue_free()

func _test_turret_destructible() -> void:
	var turret_data: WeaponData = load("res://data/weapons/turret.tres")
	_check("turret has HP defined", turret_data.turret_hp > 0.0)
	_check("turret lifetime is 20-30s (2026-08-05 playtest: was a flat 6s)", turret_data.turret_lifetime >= 20.0 and turret_data.turret_lifetime <= 30.0)

	var enemy_ship := ShipNode.new()
	enemy_ship.side = 0 # the turret below defends side 0, against fire aimed at a side-0 ship

	var turret := TurretNode.new()
	turret.weapon = turret_data
	turret.owner_side = 0
	turret.position = Vector2(300, 300)
	turret.target = enemy_ship
	turret.hp = turret_data.turret_hp # normally set in _ready(), which the engine never calls in this synchronous harness

	root.add_child(enemy_ship)
	root.add_child(turret)

	var starting_hp := turret.hp
	var incoming := ProjectileNode.new()
	incoming.position = turret.position # overlapping the turret's hitbox
	incoming.damage = 5
	incoming.target = enemy_ship # target.side == turret.owner_side -> recognized as a threat to this turret
	incoming.textures = []
	root.add_child(incoming)

	turret._check_incoming_fire()
	_check("turret takes damage from an overlapping enemy projectile", turret.hp == starting_hp - 5)
	_check("the consumed projectile is queued for deletion", incoming.is_queued_for_deletion())
	# queue_free() only defers deletion to the next idle frame (which this
	# synchronous harness never reaches — same caveat as the boomerang test
	# above) — detach it immediately so it can't be re-matched by the next
	# _check_incoming_fire() call below and skew that assertion.
	root.remove_child(incoming)

	# A friendly shot (target on the OTHER side) passing through must NOT hurt it.
	var friendly := ProjectileNode.new()
	friendly.position = turret.position
	friendly.damage = 99
	var opponent_ship := ShipNode.new()
	opponent_ship.side = 1
	root.add_child(opponent_ship)
	friendly.target = opponent_ship
	friendly.textures = []
	root.add_child(friendly)
	var hp_before_friendly := turret.hp
	turret._check_incoming_fire()
	_check("turret ignores an overlapping friendly-side projectile", turret.hp == hp_before_friendly)

	enemy_ship.queue_free()
	opponent_ship.queue_free()
	if is_instance_valid(turret):
		turret.queue_free()

func _test_turret_ball_deflection() -> void:
	# 2026-08-09 playtest (Contrôleur): "les tourelles pourraient renvoyer la
	# balle aussi ! ce serait genial" — a turret now acts like a stationary
	# paddle, mirror-bouncing the ball just like a ship would.
	_check("turret HALF_EXTENTS is 1.5x the old 10x10 (2026-08-09 playtest: easier to aim at)", TurretNode.HALF_EXTENTS == Vector2(15, 15))

	var turret_data: WeaponData = load("res://data/weapons/turret.tres")
	var turret := TurretNode.new()
	turret.weapon = turret_data
	turret.owner_side = 0
	turret.position = Vector2(200, 300)
	root.add_child(turret)

	var ball := BallNode.new()
	ball.arena_bounds = Rect2(0, 0, 1280, 720)
	ball.frontier_x = 640.0
	ball.state = BallState.new(turret.position, Vector2(-BallState.BASE_SPEED, 0.0)) # heading away from the opponent, into the turret
	root.add_child(ball)

	ball._resolve_turrets()
	_check("ball bounces off an overlapping turret (velocity reverses toward the opponent)", ball.state.velocity.x > 0.0)

	var velocity_after_first_bounce := ball.state.velocity
	ball._resolve_turrets()
	_check("a turret can't re-bounce the ball within the same cooldown/visit", ball.state.velocity == velocity_after_first_bounce)

	turret.queue_free()
	ball.queue_free()

func _test_turbo_trail() -> void:
	var ship := ShipNode.new()
	ship.position = Vector2(400, 300)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([Vector2(-14, -28), Vector2(14, -28), Vector2(14, 28), Vector2(-14, 28)])
	ship.add_child(visual)
	root.add_child(ship)

	var children_before := root.get_child_count()
	ship._spawn_trail_ghost()
	_check("turbo trail spawns a ghost node", root.get_child_count() == children_before + 1)
	var ghost: Node = root.get_child(root.get_child_count() - 1)
	_check("ghost copies the ship's polygon", ghost is Polygon2D and (ghost as Polygon2D).polygon == visual.polygon)
	_check("ghost is translucent (not opaque)", (ghost as Polygon2D).color.a < 1.0)

	ghost.queue_free()
	ship.queue_free()

func _test_gauge_floor_twist() -> void:
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])

	ship.self_fill_locked = true
	ship.fill_selected_gauge(10.0)
	_check("gauge_floor twist never blocks the miss-fill path (Story 1.6)", ship.weapon_state.gauges[0] == 10.0)

	ship.fill_selected_gauge_from_return(10.0)
	_check("gauge_floor twist blocks the self-fill-on-return path when locked", ship.weapon_state.gauges[0] == 10.0)

	ship.self_fill_locked = false
	ship.fill_selected_gauge_from_return(10.0)
	_check("self-fill-on-return works normally once unlocked", ship.weapon_state.gauges[0] == 20.0)

	ship.weapon_state = WeaponSystemState.new([machine_gun]) # reset to 0
	ship.passive_trickle_rate = 100.0
	ship._apply_passive_trickle(0.5)
	var expected_trickle := machine_gun.gauge_max * 0.5
	_check(
		"passive trickle adds gauge over time (%.1f expected, got %.1f)" % [expected_trickle, ship.weapon_state.gauges[0]],
		is_equal_approx(ship.weapon_state.gauges[0], expected_trickle)
	)

	ship.queue_free()

func _test_hazard_zone() -> void:
	var target_ship := ShipNode.new()
	target_ship.position = Vector2(300, 300)
	target_ship.half_extents = Vector2(14, 28)

	var hazard := HazardZoneNode.new()
	hazard.position = Vector2(300, 300) # overlapping the ship
	hazard.radius = 24.0
	hazard.stuns_ships = true
	hazard.deflects_ball = false
	hazard.ships = [target_ship]

	root.add_child(target_ship)
	root.add_child(hazard)

	hazard._physics_process(1.0 / 30.0)
	_check("hazard zone stuns an overlapping ship", target_ship._stun_timer > 0.0)

	target_ship.queue_free()
	hazard.queue_free()

func _test_decoy_wander() -> void:
	var decoy := DecoyNode.new()
	decoy.arena_bounds = Rect2(Vector2(40, 60), Vector2(1200, 600))
	decoy.wander_speed = 500.0
	decoy.position = Vector2(640, 360)
	root.add_child(decoy)

	var start := decoy.position
	for i in 30:
		decoy._physics_process(1.0 / 30.0)
	_check("decoy moves over time (wanders)", decoy.position.distance_to(start) > 1.0)
	_check("decoy stays within arena bounds", decoy.arena_bounds.has_point(decoy.position))

	decoy.queue_free()

func _test_energy_orb_pickup() -> void:
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])
	ship.half_extents = Vector2(14, 28)
	ship.position = Vector2(300, 300)

	var orb := EnergyOrbNode.new()
	orb.position = Vector2(300, 300) # overlapping
	orb.gauge_bonus_percent = 20.0
	orb.ships = [ship]

	root.add_child(ship)
	root.add_child(orb)

	orb._physics_process(1.0 / 30.0)
	var expected_orb := machine_gun.gauge_max * 0.2
	_check("energy orb grants +20% gauge on pickup", is_equal_approx(ship.weapon_state.gauges[0], expected_orb))
	_check("energy orb despawns after pickup", orb.is_queued_for_deletion())

	ship.queue_free()

func _test_ball_hazard_bounce() -> void:
	var state := BallState.new(Vector2(100, 0), Vector2(200, 0)) # moving right, hazard just ahead
	var hazard_center := Vector2(120, 0)
	var bounced := state.bounced_off_hazard(hazard_center)
	_check("hazard bounce reverses velocity on a head-on hit", bounced.velocity.x < 0.0)
	_check("hazard bounce preserves speed", is_equal_approx(bounced.velocity.length(), state.velocity.length()))

func _test_twist_pool_authoring() -> void:
	# 2026-08-09 bug report (Camil, cheat-menu testing): "Le twist zone du
	# milieu bouge n'existe pas" — drifting_neutral_zone (and visual_decoy,
	# multi_ball) had full engine support in match_arena_node.gd but no
	# authored .tres, so the cheat menu (which lists whatever's actually on
	# disk under data/twists/) never offered them. Every twist_type in
	# TwistData's enum except "none" and the boss-exclusive
	# "energy_orb_pickup" (data/twists/energy_orb_boss.tres) should now have
	# exactly one authored resource here.
	var expected_types := ["multi_ball", "gauge_floor", "shrinking_arena", "invisible_opponent", "hazard_zones", "drifting_neutral_zone", "visual_decoy"]
	var dir := DirAccess.open("res://data/twists")
	var found_types := {}
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var twist: TwistData = load("res://data/twists/%s" % f)
			found_types[twist.twist_type] = true
		f = dir.get_next()
	dir.list_dir_end()
	for expected in expected_types:
		_check("twist pool has an authored .tres for '%s'" % expected, found_types.has(expected))

	var drift: TwistData = load("res://data/twists/drifting_neutral_zone.tres")
	_check("drifting_neutral_zone has a positive drift_speed and drift_range", drift.drift_speed > 0.0 and drift.drift_range > 0.0)

func _test_campaign_data_resources() -> void:
	var mook_data: WeaponData = load("res://data/weapons/machine_gun.tres")
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	var vif: CharacterData = load("res://data/characters/vif.tres")

	var mook_encounter := RivalEncounterData.new()
	mook_encounter.opponent = lourd
	mook_encounter.is_mook = true
	mook_encounter.mook_hp_multiplier = 0.6
	mook_encounter.reward_currency = 100

	var rival_encounter := RivalEncounterData.new()
	rival_encounter.opponent = lourd
	rival_encounter.is_mook = false
	var gauge_floor := TwistData.new()
	gauge_floor.twist_type = "gauge_floor"
	rival_encounter.twist = gauge_floor
	rival_encounter.unlock_reward = mook_data # placeholder unlock for the smoke test, not a real design choice

	var branch := MiniBranchData.new()
	branch.id = "vs_lourd"
	branch.display_name = "Contre Lourd"
	branch.mook_1 = mook_encounter
	branch.mook_2 = mook_encounter
	branch.rival = rival_encounter

	var campaign := CampaignData.new()
	campaign.character = vif
	campaign.mini_branches = [branch]
	campaign.required_branch_count = 3

	_check("CampaignData wires a character + mini-branches", campaign.character == vif and campaign.mini_branches.size() == 1)
	_check("MiniBranchData carries mook + rival encounters", branch.rival.opponent == lourd and branch.rival.twist.twist_type == "gauge_floor")
	_check("required_branch_count matches the brainstorm's 3-4 range", campaign.required_branch_count >= 3 and campaign.required_branch_count <= 4)

func _test_campaign_save() -> void:
	# Loaded directly rather than via the CampaignSave autoload — this -s
	# harness doesn't initialize project autoloads (see round_end_check.gd's
	# note), but campaign_save.gd doesn't reference any autoload itself, so
	# instancing its script directly works fine for testing the plain data
	# API in isolation.
	var save_script := load("res://nodes/campaign_save.gd")
	var save = save_script.new()
	save.load_from_disk() # picks up whatever real save (if any) already exists on this machine

	const TEST_CHARACTER := "_smoke_test_character" # underscore-prefixed so it can never collide with a real roster id

	_check("fresh character starts with 0 currency", save.get_currency(TEST_CHARACTER) == 0)
	save.add_currency(TEST_CHARACTER, 100)
	save.add_currency(TEST_CHARACTER, 50)
	_check("currency accumulates across calls", save.get_currency(TEST_CHARACTER) == 150)

	_check("branch starts uncompleted", not save.is_branch_completed(TEST_CHARACTER, "vs_lourd"))
	save.mark_branch_completed(TEST_CHARACTER, "vs_lourd", "trace_lourd")
	_check("branch is completed after marking", save.is_branch_completed(TEST_CHARACTER, "vs_lourd"))
	_check("completed_branch_count reflects it", save.completed_branch_count(TEST_CHARACTER) == 1)
	_check("unlock is recorded", "trace_lourd" in save.unlocks_for(TEST_CHARACTER))
	save.mark_branch_completed(TEST_CHARACTER, "vs_lourd", "trace_lourd") # re-marking the same branch must not duplicate it
	_check("re-completing the same branch does not duplicate it", save.completed_branch_count(TEST_CHARACTER) == 1)

	_check("organizer starts undefeated", not save.is_organizer_defeated(TEST_CHARACTER))
	save.mark_organizer_defeated(TEST_CHARACTER)
	_check("organizer marked defeated persists in memory", save.is_organizer_defeated(TEST_CHARACTER))

	# Round-trip through the real save file, then verify a fresh instance reads it back.
	var reloaded_script := load("res://nodes/campaign_save.gd")
	var reloaded = reloaded_script.new()
	reloaded.load_from_disk()
	_check("a fresh instance reloads persisted currency from disk", reloaded.get_currency(TEST_CHARACTER) == 150)
	_check("a fresh instance reloads persisted branch completion from disk", reloaded.is_branch_completed(TEST_CHARACTER, "vs_lourd"))

	# Clean up: this test's entry should never linger in the player's real save file.
	save._data.erase(TEST_CHARACTER)
	save.save_to_disk()
	save.free()
	reloaded.free()

func _test_campaign_context_sequencing() -> void:
	# Loaded directly rather than via the CampaignContext autoload — same
	# rationale as _test_campaign_save(): this script references no other
	# autoload itself, so instancing it works fine under the -s harness.
	var context_script := load("res://nodes/campaign_context.gd")
	var context = context_script.new()

	var mook_1 := RivalEncounterData.new()
	mook_1.is_mook = true
	var mook_2 := RivalEncounterData.new()
	mook_2.is_mook = true
	var rival := RivalEncounterData.new()
	rival.is_mook = false

	var branch := MiniBranchData.new()
	branch.id = "vs_test"
	branch.mook_1 = mook_1
	branch.mook_2 = mook_2
	branch.rival = rival

	var campaign := CampaignData.new()
	context.start_branch(campaign, branch)
	_check("branch starts at step 0 (mook_1)", context.branch_step == 0 and context.current_encounter() == mook_1)

	_check("advance from step 0 moves to mook_2, reports more fights left", context.advance_branch_step() and context.current_encounter() == mook_2)
	_check("advance from step 1 moves to the rival, reports more fights left", context.advance_branch_step() and context.current_encounter() == rival)
	_check("advance from the rival reports the branch is complete", not context.advance_branch_step())
	_check("branch_step reached 3 (complete)", context.branch_step == 3)

	# 2026-08-08 regression: even if mook_1 and mook_2 happened to be
	# authored as the same resource, step-based sequencing must still tell
	# them apart (identity-based comparison couldn't).
	var context2 = context_script.new()
	var shared_mook := RivalEncounterData.new()
	shared_mook.is_mook = true
	var branch2 := MiniBranchData.new()
	branch2.mook_1 = shared_mook
	branch2.mook_2 = shared_mook
	branch2.rival = rival
	context2.start_branch(campaign, branch2)
	_check("step 0 reads as mook_1 even when mook_1 == mook_2 by identity", context2.branch_step == 0)
	context2.advance_branch_step()
	_check("step 1 reads as mook_2 even when mook_1 == mook_2 by identity", context2.branch_step == 1)
	context2.free()

	context.free()

func _test_campaign_context_debug_fight() -> void:
	# Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
	# campagne, pour que je puisse tester tous les twists ?") — a THIRD case
	# alongside branch/organizer fights, distinct from both (2026-08-09 bug:
	# _update_campaign_label() assumed "not organizer" implied "branch is
	# set", crashing on CampaignContext.branch being null during a debug
	# fight — this test guards the CampaignContext side of that regression).
	var context_script := load("res://nodes/campaign_context.gd")
	var context = context_script.new()
	var campaign := CampaignData.new()
	var encounter := RivalEncounterData.new()
	encounter.is_mook = false

	context.start_debug_fight(campaign, encounter)
	_check("debug fight registers as a pending encounter", context.has_pending_encounter())
	_check("debug fight is neither a branch nor the organizer", context.branch == null and not context.is_organizer_fight)
	_check("current_encounter() returns the debug encounter", context.current_encounter() == encounter)

	context.clear()
	_check("clear() resets debug_encounter too", context.debug_encounter == null and not context.has_pending_encounter())
	context.free()

func _test_campaign_save_progress_tracking() -> void:
	# Title screen (2026-08-09) — "Nouvelle partie" only warns/wipes when
	# there's real progress to lose; "Continuer la partie" needs to know
	# which character to resume.
	var save_script := load("res://nodes/campaign_save.gd")
	var save = save_script.new()
	save._data = {} # start from a clean slate, independent of any real save on disk

	const TEST_CHARACTER := "_smoke_test_progress_character"

	_check("no progress on a fresh save", not save.has_any_progress())
	_check("character_with_progress() is empty with nothing saved", save.character_with_progress() == "")

	save.add_currency(TEST_CHARACTER, 50)
	_check("has_any_progress() becomes true once currency is earned", save.has_any_progress())
	_check("character_with_progress() finds the right character", save.character_with_progress() == TEST_CHARACTER)

	save.reset_all()
	_check("reset_all() wipes progress back to none", not save.has_any_progress())
	_check("reset_all() clears character_with_progress() too", save.character_with_progress() == "")

func _test_vif_campaign_authoring() -> void:
	# Sanity-checks the one fully-authored example campaign (content for the
	# other 7 characters is tracked separately, not an engineering gap).
	var campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var vif: CharacterData = load("res://data/characters/vif.tres")

	_check("Vif campaign is authored for the right character", campaign.character == vif)
	_check("Vif campaign has at least required_branch_count mini-branches", campaign.mini_branches.size() >= campaign.required_branch_count)
	_check("required_branch_count is in the brainstorm's 3-4 range", campaign.required_branch_count >= 3 and campaign.required_branch_count <= 4)

	for b in campaign.mini_branches:
		var branch: MiniBranchData = b
		_check("branch '%s' has both mooks set" % branch.id, branch.mook_1 != null and branch.mook_2 != null)
		# 2026-08-08 bug: mook_1 and mook_2 were the same resource instance in
		# every branch, which made _update_campaign_label()'s identity check
		# always report "Sous-adversaire 1/2" and read to the player as a
		# stuck loop rather than real progress.
		_check("branch '%s' mook_1 and mook_2 are distinct resources" % branch.id, branch.mook_1 != branch.mook_2)
		_check("branch '%s' rival has a twist assigned" % branch.id, branch.rival.twist != null)
		_check("branch '%s' rival grants an unlock" % branch.id, branch.rival.unlock_reward != null)

	_check("organizer encounter is set", campaign.organizer_encounter != null)
	_check("organizer encounter has its signature twist", campaign.organizer_encounter.twist != null and campaign.organizer_encounter.twist.twist_type == "energy_orb_pickup")

func _test_gauges_reset_between_rounds() -> void:
	# 2026-08-08 bug report: "quand un round se termine, les compteurs
	# d'armes ne se remettent pas à 0" — reset_for_new_round() rebuilt HP
	# but never touched weapon_state, so a maxed gauge from round 1 carried
	# straight into round 2.
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])
	ship.weapon_state = ship.weapon_state.with_gauge_added(machine_gun.gauge_max) # simulate a maxed gauge at round end
	_check("gauge is maxed before the round reset (test setup sanity check)", ship.weapon_state.gauges[0] == machine_gun.gauge_max)

	ship.reset_for_new_round()
	_check("gauge is back to 0 after reset_for_new_round()", ship.weapon_state.gauges[0] == 0.0)
	_check("cooldown is also reset", ship.weapon_state.cooldown == 0.0)
	_check("the kit itself is unchanged (still the same weapon)", ship.weapon_state.kit.size() == 1 and ship.weapon_state.kit[0] == machine_gun)

	ship.queue_free()

func _test_weapon_heat_gauge() -> void:
	# 2026-08-08 playtest: "Mitraillette, c'est trop fort. Il faudrait un
	# cooldown de 1s tous les... 6 tirs ?" — then 2026-08-09, after the
	# first (hard burst-limit) version: "je tire 4 balles, j'attends 3
	# secondes, et je ne peux tirer que 2 balles => frustrant". Redesigned
	# as a continuous heat gauge instead: any pause drains it a little,
	# rather than a flat shot counter that only ever resets after a full
	# lockout.
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	_check("machine_gun has a heat limit configured", machine_gun.heat_max > 0.0)
	_check("machine_gun's heat drains at 1 full cooldown's worth per second", is_equal_approx(machine_gun.heat_cooldown_rate, machine_gun.heat_max))

	var weapon := WeaponData.new()
	weapon.fire_rate = 10.0
	weapon.gauge_max = 1000.0
	weapon.gauge_cost_per_shot = 1.0
	weapon.heat_max = 6.0
	weapon.heat_per_shot = 1.0
	weapon.heat_cooldown_rate = 6.0 # full cool from max in 1s
	var state := WeaponSystemState.new([weapon])
	state = state.with_gauge_added(1000.0)

	for i in 6:
		var result := state.fired()
		_check("shot %d fires" % (i + 1), result.fired)
		state = result.state
		state = state.with_cooldown_ticked(state.cooldown) # fast-forward the normal per-shot cooldown; heat is the only remaining gate
		state = state.with_heat_ticked(0.1, true) # is_firing=true — heat must NOT drain mid-burst

	_check("after 6 shots the gauge is fully heated", is_equal_approx(state.heats[0], 6.0))
	var blocked_result := state.fired()
	_check("firing while fully heated is blocked", not blocked_result.fired)

	# 2026-08-09 regression: a SHORT pause (well under the full 1s cooldown)
	# must still measurably help, not be wasted like the old hard-lockout
	# counter — the exact "4 shots, wait 3s, still only 2 left" complaint.
	state = state.with_heat_ticked(0.5, false) # released fire for half a second
	_check("a partial pause drains heat proportionally, not all-or-nothing", is_equal_approx(state.heats[0], 3.0))
	var resumed_result := state.fired()
	_check("firing resumes as soon as heat drops below max, not only after a full cooldown", resumed_result.fired)

	# Heat must never drain while the trigger is still held.
	var still_firing_state := WeaponSystemState.new([weapon])
	still_firing_state = still_firing_state.with_gauge_added(1000.0)
	still_firing_state = still_firing_state.fired().state
	still_firing_state = still_firing_state.with_heat_ticked(1.0, true)
	_check("heat does not drain while is_firing is true", is_equal_approx(still_firing_state.heats[0], 1.0))

func _test_mitrailleur_heat_immunity_rule() -> void:
	# 2026-08-09 party-mode pitch, implemented: "puisque tout le monde a
	# maintenant un tir charge, le sien pourrait etre l'inverse des autres —
	# charger desactive completement la surchauffe pendant quelques
	# secondes. Le mec qui charge pour arroser sans limite, brievement."
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	_check("machine_gun has a charged fire configured", machine_gun.charge_fire_duration > 0.0)
	_check("machine_gun's charge actually slows movement (the vortex.tres bug can never recur silently)", machine_gun.charge_fire_slow_multiplier < 1.0 and machine_gun.charge_fire_slow_multiplier > 0.0)
	_check("machine_gun's charged fire grants heat immunity instead of a projectile burst", machine_gun.charged_grants_heat_immunity)
	_check("machine_gun's heat immunity lasts a few seconds", machine_gun.charged_heat_immunity_duration > 0.0)

	# WeaponSystemState.fired(ignore_heat) — bypasses the gate AND freezes
	# heat accumulation for that shot.
	var state := WeaponSystemState.new([machine_gun])
	state = state.with_gauge_added(1000.0)
	# Heat the gun up to its max first.
	for i in 6:
		state = state.fired().state
		state = state.with_cooldown_ticked(state.cooldown)
	_check("setup: machine_gun is fully heated", is_equal_approx(state.heats[0], machine_gun.heat_max))

	var blocked := state.fired()
	_check("normally, firing while overheated is blocked", not blocked.fired)

	var immune_result := state.fired(true) # ignore_heat = true
	_check("with ignore_heat, firing succeeds even while overheated", immune_result.fired)
	state = immune_result.state
	_check("with ignore_heat, heat does not increase further either", is_equal_approx(state.heats[0], machine_gun.heat_max))

	# ShipNode.grant_heat_immunity() / _on_charged_weapon_fired() short-circuit.
	var ship := ShipNode.new()
	ship.grant_heat_immunity(machine_gun.charged_heat_immunity_duration)
	_check("grant_heat_immunity() sets the timer", ship._heat_immunity_timer > 0.0)
	ship.queue_free()

func _test_vif_dash_lift_rule() -> void:
	# 2026-08-09 (Camil): "vif est pas interessant... chaque perso devrait
	# avoir une regle bien a lui. un + et un -. Proposition pour vif: il ne
	# peut pas charger pour faire des lift. en revanche, le bouton lift lui
	# permet de faire un petit dash... s'il tape en dashant, ca fait un
	# leger lift."
	var vif: CharacterData = load("res://data/characters/vif.tres")
	_check("Vif's special_rule is dash_lift", vif.special_rule == "dash_lift")
	_check("Vif's kit is just his Tourbillon (2026-08-09: weapons became per-character exclusive, mitraillette went to Mitrailleur)", vif.kit.size() == 1 and vif.kit[0].id == "vortex")

	var ship := ShipNode.new()
	ship.character = vif
	_check("get_lift_charge() reads 0% for a dash character with no dash active (the MINUS: no charging at all)", ship.get_lift_charge() == 0.0)

	ship._dash_timer = 0.1
	_check("get_lift_charge() reads a fixed 'leger lift' while a dash is active (the PLUS)", ship.get_lift_charge() == ShipNode.DASH_LIFT_CHARGE)

	ship._dash_timer = 0.0
	_check("get_lift_charge() drops back to 0% once the dash window ends", ship.get_lift_charge() == 0.0)

	# A normal (non-dash) character is completely untouched by this rewrite.
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	var lourd_ship := ShipNode.new()
	lourd_ship.character = lourd
	lourd_ship._lift_charge_timer = 1.5 # full charge
	_check("a normal character still uses the hold-to-charge tiers unaffected", lourd_ship.get_lift_charge() == 1.0)

	ship.queue_free()
	lourd_ship.queue_free()

func _test_every_charge_capable_weapon_actually_slows() -> void:
	# 2026-08-09 — a general invariant, added after vortex.tres shipped with
	# charge_fire_duration set but no charge_fire_slow_multiplier (silently
	# defaulting to 1.0 = no slow at all), which read as an intermittent
	# "sometimes not slowed" bug through several rounds of ship_node.gd
	# fixes that were actually solving a different problem. Scans every
	# weapon under data/weapons/ so this can never silently regress again.
	var dir := DirAccess.open("res://data/weapons")
	var all_ok := true
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var weapon: WeaponData = load("res://data/weapons/%s" % f)
			if weapon.charge_fire_duration > 0.0 and weapon.charge_fire_slow_multiplier >= 1.0:
				all_ok = false
				print("FAIL: %s has charge_fire_duration but charge_fire_slow_multiplier is %s (no slow)" % [f, weapon.charge_fire_slow_multiplier])
		f = dir.get_next()
	dir.list_dir_end()
	_check("every charge-capable weapon actually slows movement while charging", all_ok)

func _test_weapon_exclusivity() -> void:
	# 2026-08-09 (Camil): "je pense que la mitraillette devrait etre
	# reservee a mitrailleur. Pour eviter de se prendre la tete avec des
	# changements d'arme, chaque joueur a sa propre arme." Every roster
	# character now carries exactly one weapon, and no two characters share
	# the same one.
	var character_ids := ["lourd", "controleur", "mitrailleur", "vif", "zoneur", "perturbateur", "missiles", "mini"]
	var seen_weapon_ids := {}
	var all_mono_weapon := true
	var all_unique := true
	for character_id in character_ids:
		var character: CharacterData = load("res://data/characters/%s.tres" % character_id)
		if character.kit.size() != 1:
			all_mono_weapon = false
		var weapon: WeaponData = character.kit[0]
		if seen_weapon_ids.has(weapon.id):
			all_unique = false
		seen_weapon_ids[weapon.id] = character_id
	_check("every roster character carries exactly one weapon", all_mono_weapon)
	_check("no two characters share the same weapon", all_unique)

	# 2026-08-09 (Camil): "seul mitrailleur tire plusieurs fois d'affilee
	# quand on laisse appuye... pour les autres, il faut appuyer plusieurs
	# fois pour tirer plusieurs fois."
	var mitrailleur: CharacterData = load("res://data/characters/mitrailleur.tres")
	_check("only Mitrailleur is full-auto", mitrailleur.full_auto)
	var vif: CharacterData = load("res://data/characters/vif.tres")
	_check("everyone else defaults to semi-auto (e.g. Vif)", not vif.full_auto)

func _test_vortex_weapon() -> void:
	# 2026-08-09 (Camil): Vif's new signature weapon — "un petit tourbillon
	# qui tourne sur lui meme en avancant et qui va tres vite. tir charge,
	# trois tourbillons qui vont tout droit (toujours en tournant sur eux
	# meme)." Redesigned after Camil's drawing: "je veux qu'il fasse des
	# cercles" — small forward-advancing loops, not a straight line, and not
	# a node rotation either. Then: "vu la vitesse, pour le tourbillon, pas
	# d'anim : garde uniquement wind1" — the wind1-3 cycle was dropped, too
	# fast to read once the loop motion was tuned up; the loop itself
	# carries the "spinning" read now.
	var vortex: WeaponData = load("res://data/weapons/vortex.tres")
	_check("Tourbillon travels faster than the shared default projectile speed", vortex.projectile_speed > 620.0)
	_check("Tourbillon loops instead of flying straight", vortex.is_looping and vortex.loop_radius > 0.0 and vortex.loop_angular_speed > 0.0)
	_check("Tourbillon does not also spin the node (the loop motion already conveys spin)", vortex.projectile_spin_speed == 0.0)
	_check("Tourbillon has a charged fire configured", vortex.charge_fire_duration > 0.0)
	_check("Tourbillon's charge duration is 3s (2026-08-09 playtest: 'augmenter le temps de charge : 3 secondes')", is_equal_approx(vortex.charge_fire_duration, 3.0))
	# 2026-08-09 bug (the REAL root cause of the recurring "ralentissement"
	# reports for Vif): charge_fire_slow_multiplier was never set on
	# vortex.tres at all, silently defaulting to 1.0 (no slowdown) — every
	# ship_node.gd fix attempt was solving a different, hypothetical problem.
	_check("Tourbillon's charge actually slows movement (was silently defaulting to 1.0 = no slow)", vortex.charge_fire_slow_multiplier < 1.0 and vortex.charge_fire_slow_multiplier > 0.0)
	_check("Tourbillon's cooldown was increased 1.5x (2026-08-09 playtest: 'un peu court')", vortex.fire_rate < 4.0 / 1.4) # fire_rate=4.0/1.5 -> cooldown*1.5; loose upper bound so exact rounding doesn't matter
	_check("Tourbillon's charged fire launches 3 vortices", vortex.charged_projectile_count == 3)
	_check("Tourbillon's charged vortices still go straight (no burst spread)", vortex.charged_burst_spread_deg == 0.0)

	var projectile := ProjectileNode.new()
	projectile.velocity = Vector2(vortex.projectile_speed, 0.0)
	projectile.is_looping = true
	projectile.loop_radius = vortex.loop_radius
	projectile.loop_angular_speed = vortex.loop_angular_speed
	projectile._ready() # captures _drift_velocity — never called automatically by .new() under this harness
	var start_position := projectile.position
	var off_the_straight_line := false
	var net_forward_progress := false
	for i in 20: # ~0.33s at a 60fps-equivalent step
		projectile._physics_process(1.0 / 60.0)
		if absf(projectile.position.y - start_position.y) > 2.0:
			off_the_straight_line = true
		if projectile.position.x - start_position.x > 20.0:
			net_forward_progress = true
	_check("a looping projectile deviates off the straight line (traces circles)", off_the_straight_line)
	_check("a looping projectile still makes real net forward progress (drifts, doesn't just spin in place)", net_forward_progress)

	# 2026-08-09 (Camil: "attention quand il tourne, sa zone de contact
	# tourne avec lui !") — the hit check uses the same `position` the loop
	# actually moves through (no separate visual-only offset), so a target
	# placed only in the loop's swept path — off the straight drift line —
	# must still register a hit.
	var off_line_target := ShipNode.new()
	off_line_target.position = start_position + Vector2(10.0, vortex.loop_radius) # well off the straight (dy=0) line, but within the loop's sweep
	off_line_target.half_extents = Vector2(14, 28)
	off_line_target.state = ShipState.new(off_line_target.position, 0, off_line_target.half_extents) # apply_damage() needs this — normally built in _ready(), never called by this harness
	var probe := ProjectileNode.new()
	probe.velocity = Vector2(vortex.projectile_speed, 0.0)
	probe.is_looping = true
	probe.loop_radius = vortex.loop_radius
	probe.loop_angular_speed = vortex.loop_angular_speed
	probe.damage = 2
	probe.target = off_line_target
	probe.position = start_position
	probe._ready()
	var hit_off_line_target := false
	for i in 60: # ~1s — long enough to sweep through a full loop
		probe._physics_process(1.0 / 60.0)
		if not is_instance_valid(probe) or probe.is_queued_for_deletion():
			hit_off_line_target = true
			break
	_check("the loop's hit detection actually follows the curved path (an off-line target still gets hit)", hit_off_line_target)
	off_line_target.queue_free()
	if is_instance_valid(probe) and not probe.is_queued_for_deletion():
		probe.queue_free()
	projectile.queue_free()

func _test_charged_fire_burst() -> void:
	# 2026-08-09 — WeaponData.charged_* fields feeding
	# MatchArenaNode._on_charged_weapon_fired()/_spawn_projectile(): the
	# framework is generic, proven here with Lourd's bazooka (2 faster
	# shells) rather than re-deriving ship_node.gd's Input-driven charge
	# state machine, which can't be simulated headless (same limitation as
	# every other keypress-driven behavior in this suite).
	var bazooka: WeaponData = load("res://data/weapons/bazooka.tres")
	_check("bazooka has a charged fire configured (Lourd's 3s charge)", is_equal_approx(bazooka.charge_fire_duration, 3.0))
	_check("bazooka's charge slows movement by 70%", is_equal_approx(bazooka.charge_fire_slow_multiplier, 0.3))
	_check("bazooka's charged release fires 2 shells", bazooka.charged_projectile_count == 2)
	_check("bazooka's charged shells are faster than normal", bazooka.charged_speed_multiplier > 1.0)

	# 2026-08-09 redesign after playtesting the first version (Camil: "je
	# laisse appuye, ca tire normalement. si au bout d'une seconde je suis
	# toujours en appui, la charge commence") — normal fire for the first
	# NORMAL_FIRE_GRACE seconds of a hold, THEN it starts charging.
	_check("NORMAL_FIRE_GRACE is about 1 second, per Camil's spec", is_equal_approx(ShipNode.NORMAL_FIRE_GRACE, 1.0))

	# 2026-08-09 recurring bug report: "y'a toujours le pb du ralentissement
	# quand on charge. Il faut que le ralentissement reste tant qu'on a pas
	# relache (meme si la charge est finie)" — a momentary fire_held dip
	# (e.g. analog trigger jitter) must not be treated as an instant real
	# release. FIRE_RELEASE_GRACE's exact state-machine behavior needs live
	# Input to exercise (same limitation as the rest of this suite) — just
	# checking the constant exists with a sane, non-zero, sub-second value.
	_check("FIRE_RELEASE_GRACE tolerates a brief input dip without losing the charge", ShipNode.FIRE_RELEASE_GRACE > 0.0 and ShipNode.FIRE_RELEASE_GRACE < 0.5)

	# 2026-08-09 (Camil): "quand la charge est fini, tu peux faire clignoter
	# rapidement le joueur pour qu'on sache que c'est bon", then after
	# seeing it: "pas mal le clignotement, tu peux le faire beaucoup plus
	# rapide" (0.5s -> 0.15s). The blink ITSELF (visual.modulate toggling in
	# _physics_process()) can't be simulated headless — it's gated behind
	# live fire_held/Input state, same limitation as every other keypress-
	# driven behavior in this suite — but the formula
	# (fmod(_fire_held_duration, PERIOD) < PERIOD/2.0) is pure math, checked
	# here directly with period-relative offsets (not a fixed elapsed time
	# like 3.0s, which risked landing on a float-precision edge case against
	# an arbitrary period value).
	_check("CHARGE_READY_BLINK_PERIOD was made much faster (0.5s -> 0.15s)", is_equal_approx(ShipNode.CHARGE_READY_BLINK_PERIOD, 0.15))
	# Sampled at the middle of each half (0.25/0.75 of a period), not on the
	# exact half/full-period boundary — a boundary sample is one float
	# rounding error away from landing on the wrong side of "< period/2.0".
	var period := ShipNode.CHARGE_READY_BLINK_PERIOD
	_check("the blink formula is ON in the first half of a period", fmod(period * 0.25, period) < period / 2.0)
	_check("the blink formula toggles OFF in the second half", not (fmod(period * 0.75, period) < period / 2.0))
	_check("the blink formula toggles back ON a full period later", fmod(period + period * 0.25, period) < period / 2.0)

func _test_heavy_push_rule() -> void:
	# 2026-08-09 (Camil): "Lourd bonne idee le lift a fond, il faudrait donc
	# que ca 'pousse' la balle et que cette derniere pousse le joueur
	# adverse." A fully-charged (100%) lift return arms the ball; the NEXT
	# ship it reaches gets shoved back.
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	_check("Lourd's special_rule is heavy_push", lourd.special_rule == "heavy_push")

	# Pure ShipState.knocked_back() — offset applied and clamped like normal movement.
	var bounds := Rect2(0, 0, 1280, 720)
	var state := ShipState.new(Vector2(200, 300), 0, Vector2(14, 28))
	var pushed_state := state.knocked_back(Vector2(40.0, 0.0), bounds, 640.0)
	_check("knocked_back() moves the ship by the offset", is_equal_approx(pushed_state.position.x, 240.0))
	var pushed_into_wall := state.knocked_back(Vector2(-1000.0, 0.0), bounds, 640.0)
	_check("knocked_back() is clamped, can't push a ship out of bounds", pushed_into_wall.position.x >= bounds.position.x)

	# End-to-end: arm on a 100%-charge return, consume on the next ship contact.
	var pusher := ShipNode.new()
	pusher.side = 0
	pusher.character = lourd
	pusher.position = Vector2(200, 300)
	pusher.state = ShipState.new(pusher.position, pusher.side, pusher.half_extents)
	pusher.weapon_state = WeaponSystemState.new(lourd.kit) # normally built in _ready(), which this harness never calls
	pusher._lift_charge_timer = ShipNode.LIFT_CHARGE_CAP # forces get_lift_charge() == 1.0
	root.add_child(pusher)

	var opponent := ShipNode.new()
	opponent.side = 1
	opponent.position = Vector2(1000, 300)
	opponent.arena_bounds = Rect2(0, 0, 1280, 720)
	opponent.frontier_x = 640.0
	opponent.state = ShipState.new(opponent.position, opponent.side, opponent.half_extents)
	opponent.weapon_state = WeaponSystemState.new([load("res://data/weapons/machine_gun.tres")])
	root.add_child(opponent)

	var ball := BallNode.new()
	ball.arena_bounds = Rect2(0, 0, 1280, 720)
	ball.frontier_x = 640.0
	ball.ships = [pusher, opponent]
	ball.state = BallState.new(pusher.position, Vector2(-1.0, 0.0)) # overlapping pusher, heading further left (a "return" reverses this)
	root.add_child(ball)

	ball._resolve_ships()
	_check("a 100%-charge heavy_push return arms the ball", ball._push_pending)

	# Move the (now rightward-traveling, post-return) ball onto the opponent and resolve again.
	ball._return_cooldown = 0.0
	ball.state = BallState.new(opponent.position, Vector2(500.0, 0.0))
	var opponent_x_before := opponent.position.x
	ball._resolve_ships()
	_check("the armed push knocks the opponent back on the next contact", opponent.position.x > opponent_x_before)
	_check("the push is consumed (single-use), not reusable", not ball._push_pending)

	pusher.queue_free()
	opponent.queue_free()
	ball.queue_free()
