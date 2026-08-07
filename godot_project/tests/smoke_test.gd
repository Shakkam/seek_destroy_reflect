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
