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
	_test_turbo_trail()
	_test_gauge_floor_twist()
	_test_hazard_zone()
	_test_decoy_wander()
	_test_energy_orb_pickup()
	_test_ball_hazard_bounce()
	_test_campaign_data_resources()
	_test_campaign_save()
	_test_campaign_context_sequencing()
	_test_vif_campaign_authoring()
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
	context.start_branch(campaign, branch, mook_1)
	_check("branch starts on mook_1", context.encounter == mook_1)

	_check("advance from mook_1 moves to mook_2", context.advance_within_branch() and context.encounter == mook_2)
	_check("advance from mook_2 moves to rival", context.advance_within_branch() and context.encounter == rival)
	_check("advance from the rival reports no further step", not context.advance_within_branch())
	_check("encounter stays on the rival after the final advance() call", context.encounter == rival)

	context.free()

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
		_check("branch '%s' rival has a twist assigned" % branch.id, branch.rival.twist != null)
		_check("branch '%s' rival grants an unlock" % branch.id, branch.rival.unlock_reward != null)

	_check("organizer encounter is set", campaign.organizer_encounter != null)
	_check("organizer encounter has its signature twist", campaign.organizer_encounter.twist != null and campaign.organizer_encounter.twist.twist_type == "energy_orb_pickup")
