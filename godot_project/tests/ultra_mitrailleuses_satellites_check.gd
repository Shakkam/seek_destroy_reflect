extends Node2D

## One-off scene-boot verification for Mitrailleur's Ultra, "Mitrailleuses
## Satellites" (2026-08-13 Epic 4 party-mode memlog: "double full-auto
## temporaire"). Split into its own file rather than growing
## ultra_abilities_check.gd further — that file's shared wait-loop
## already takes a while real-time with 3 characters in it; a dedicated
## file per additional Ultra keeps each test run focused. Confirms, via
## the real trigger path: the guaranteed floor lands the instant the
## intro finishes, and exactly 2 TurretNodes spawn flanking the shooter,
## carrying the right weapon/target/side. Run with:
##   Godot --headless --path godot_project res://tests/ultra_mitrailleuses_satellites_check.tscn --quit-after 2200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/mitrailleur.tres"))
	while not arena.ship_1.weapon_state.ultra_ready():
		arena.ship_1.add_ultra_pip()
	arena._unfreeze_round()

	var hp_before: float = arena.ship_2.state.hp
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Catch the exact tick the intro finishes and ships unfreeze — see
	# ultra_abilities_check.gd for why this beats a fixed "wait N then
	# check" (headless frames run far faster than realtime, and a
	# too-long wait risks other side effects piling up before the check).
	var was_active := arena.ship_1.active
	var hp_at_unfreeze := -1.0
	for i in 1600:
		await get_tree().physics_frame
		if not was_active and arena.ship_1.active:
			hp_at_unfreeze = arena.ship_2.state.hp
			break
		was_active = arena.ship_1.active

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE]))

	var turrets: Array = []
	for child in arena.get_children():
		if child is TurretNode:
			turrets.append(child)
	var count_ok: bool = turrets.size() == 2
	print(("PASS: exactly 2 satellite turrets spawned" % []) if count_ok else ("FAIL: %d turrets spawned, expected 2" % turrets.size()))

	var config_ok := true
	for turret in turrets:
		if turret.weapon != MatchArenaNode.ULTRA_MITRAILLEUSES_SATELLITES:
			config_ok = false
		if turret.target != arena.ship_2:
			config_ok = false
		if turret.owner_side != arena.ship_1.side:
			config_ok = false
		var offset_y: float = turret.position.y - arena.ship_1.position.y
		if not is_equal_approx(absf(offset_y), MatchArenaNode.MITRAILLEUSES_SATELLITES_OFFSET_Y):
			config_ok = false
	print("PASS: both turrets carry the right weapon/target/side, flanking the shooter" if config_ok else "FAIL: a turret's config was wrong")

	# 2026-08-15 bug report (Camil): "les tirs doivent etre des tirs normaux
	# de mitraillette (la tu as mis des carres verts qui visent l'ennemi =>
	# non)" — firing P1's normal shot should make BOTH satellites spawn a
	# real, sprited, STRAIGHT-forward ProjectileNode (not TurretNode's own
	# aimed-at-target/spriteless _fire_at_target()) alongside his own shot.
	# Gauges start EMPTY (see WeaponSystemState._init()) and normal fire
	# costs gauge (machine_gun.tres: gauge_cost_per_shot = 4.0) — a fresh
	# ship built by this test never returned a ball to earn any, so it
	# has to be topped up manually or weapon_state.fired() just silently
	# refuses to fire.
	arena.ship_1.fill_selected_gauge(100.0)
	var projectiles_before: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	var fire_down := InputEventKey.new()
	fire_down.physical_keycode = KEY_SPACE
	fire_down.pressed = true
	Input.parse_input_event(fire_down)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var projectiles_after: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	var new_projectiles := projectiles_after.size() - projectiles_before.size()
	# 3 = his own normal shot + one echoed from each of the 2 satellites.
	var fire_count_ok: bool = new_projectiles == 3
	print(("PASS: firing normally spawns 3 shots (his own + 2 satellite echoes)" if fire_count_ok else "FAIL: %d new shots spawned, expected 3" % new_projectiles))

	var satellite_shots_ok := true
	for child in projectiles_after:
		if child in projectiles_before:
			continue
		if is_equal_approx(absf(child.position.y - arena.ship_1.position.y), MatchArenaNode.MITRAILLEUSES_SATELLITES_OFFSET_Y):
			# Came from a satellite's offset origin — must look/behave like
			# a normal shot: a real texture (not TurretNode's spriteless
			# fallback square) and a roughly-horizontal velocity (not aimed
			# at the opponent's arbitrary position). "Roughly" because
			# machine_gun.tres carries its own small +/-2deg spread_deg
			# jitter (WeaponData default) on every normal shot, satellite
			# echoes included — angle-from-horizontal has to tolerate that
			# same expected wobble, not demand a mathematically perfect 0.
			if child.textures.is_empty():
				satellite_shots_ok = false
			if absf(child.velocity.angle()) > deg_to_rad(10.0):
				satellite_shots_ok = false
	print("PASS: satellite shots are real sprited, straight-forward machine-gun fire" if satellite_shots_ok else "FAIL: a satellite shot was spriteless or aimed instead of straight")

	# 2026-08-15 bug report (Camil): "attention a la fin de l'ultra les
	# modules disparaissent, mais les tirs sont toujours la" — the
	# weapon_fired connection used to outlive the satellites' own
	# turret_lifetime entirely (nothing ever disconnected it). Force their
	# expiry directly (setting _lifetime_left, rather than actually waiting
	# out the real 12s turret_lifetime in simulated physics ticks) and
	# confirm firing afterward goes back to just his own single shot.
	for turret in turrets:
		turret._lifetime_left = 0.001
	await get_tree().physics_frame
	await get_tree().physics_frame
	var turrets_gone_ok := true
	for turret in turrets:
		if is_instance_valid(turret):
			turrets_gone_ok = false
	print("PASS: satellites actually expire (turret_lifetime honored)" if turrets_gone_ok else "FAIL: a satellite outlived its turret_lifetime")

	var projectiles_before_2: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	Input.parse_input_event(fire_down) # already pressed=true; re-send so a fresh rising edge isn't required for full_auto, matches the earlier press
	await get_tree().physics_frame
	await get_tree().physics_frame
	var projectiles_after_2: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	var new_projectiles_2 := projectiles_after_2.size() - projectiles_before_2.size()
	var no_ghost_fire_ok: bool = new_projectiles_2 == 1 # just his own shot, no satellite echoes from beyond the grave
	print(("PASS: firing after the satellites expire no longer echoes from empty air (1 shot, his own only)" if no_ghost_fire_ok else "FAIL: %d shots spawned after expiry, expected 1" % new_projectiles_2))

	# 2026-08-15 bug report (Camil, after playing it): "quand il a utilise
	# son ultra, s'il le reutilise, les tirs des modules ne marchent plus"
	# — the actual root cause: the old design called ship.weapon_fired.
	# connect(_on_satellite_fire.bind(...)) fresh on every single cast, and
	# Godot ERRORS connecting the same (self, method) pair to the same
	# signal twice (regardless of different bind() args) — so the SECOND
	# cast's connect() call silently failed and the new wave of satellites
	# never got wired to anything. Re-trigger the Ultra a second time (a
	# real release+press for a fresh edge — the key's been held since the
	# very first trigger) and confirm satellite fire still works exactly
	# like the first time.
	while not arena.ship_1.weapon_state.ultra_ready():
		arena.ship_1.add_ultra_pip()
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().physics_frame
	Input.parse_input_event(down) # down = the original KEY_E press event, still valid to resend
	await get_tree().physics_frame
	await get_tree().physics_frame

	var was_active_2 := arena.ship_1.active
	var reused_ok := false
	for i in 1600:
		await get_tree().physics_frame
		if not was_active_2 and arena.ship_1.active:
			reused_ok = true
			break
		was_active_2 = arena.ship_1.active
	print("PASS: the Ultra actually re-triggers a second time" if reused_ok else "FAIL: re-triggering the Ultra never unfroze the match")

	var new_turrets: Array = []
	for child in arena.get_children():
		if child is TurretNode:
			new_turrets.append(child)
	var reuse_count_ok: bool = new_turrets.size() == 2
	print(("PASS: exactly 2 fresh satellite turrets spawned on reuse" if reuse_count_ok else "FAIL: %d turrets present after reuse, expected 2" % new_turrets.size()))

	arena.ship_1.fill_selected_gauge(100.0)
	var projectiles_before_3: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	Input.parse_input_event(fire_down)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var projectiles_after_3: Array = arena.get_children().filter(func(c): return c is ProjectileNode)
	var new_projectiles_3 := projectiles_after_3.size() - projectiles_before_3.size()
	var reuse_fire_ok: bool = new_projectiles_3 == 3
	print(("PASS: satellite fire still works after reusing the Ultra (3 shots again)" if reuse_fire_ok else "FAIL: only %d shots spawned after reuse, expected 3 — the reuse bug is back" % new_projectiles_3))

	var all_ok := floor_ok and count_ok and config_ok and fire_count_ok and satellite_shots_ok and turrets_gone_ok and no_ghost_fire_ok and reused_ok and reuse_count_ok and reuse_fire_ok
	get_tree().quit(0 if all_ok else 1)
