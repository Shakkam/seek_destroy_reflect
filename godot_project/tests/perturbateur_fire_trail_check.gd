extends Node2D

## Scene-boot check for the 2026-08-17 Perturbateur pass (Camil: "le tir
## charge n'est pas bien... on lance un gros boomerang, mais il laisse une
## trainee de feu (particules) derriere lui, qui font des degats si on les
## touche. Les trainees durent 3s" + "les tirs de perturbateur sont petits,
## grossir un peu (x1.3)"). Covers: visual_scale_multiplier, the charged
## release actually opting into leaves_fire_trail (and the NORMAL 3-burst
## NOT opting in), and a FireTrailNode really damaging a victim on overlap
## then expiring after its 3s lifetime. Run with:
##   Godot --headless --path . res://tests/perturbateur_fire_trail_check.tscn --quit-after 2000

func _ready() -> void:
	var weapon: WeaponData = load("res://data/weapons/stun_boomerang.tres")
	var scale_ok := is_equal_approx(weapon.visual_scale_multiplier, 1.3)
	print(("PASS: stun_boomerang.visual_scale_multiplier is 1.3" if scale_ok else "FAIL: visual_scale_multiplier was %s" % weapon.visual_scale_multiplier))

	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	# --- charged release opts into the fire trail, normal fire doesn't ---
	arena._on_charged_weapon_fired(weapon, arena.ship_1)
	await get_tree().process_frame
	var charged_projectile: ProjectileNode = null
	for child in arena.get_children():
		if child is ProjectileNode:
			charged_projectile = child
	var charged_ok := charged_projectile != null and charged_projectile.leaves_fire_trail
	print("PASS: the charged boomerang release opts into leaves_fire_trail" if charged_ok else "FAIL: the charged release did not set leaves_fire_trail")
	if charged_projectile:
		charged_projectile.queue_free()
	await get_tree().process_frame

	arena._on_weapon_fired(weapon, arena.ship_1) # normal 3-burst
	await get_tree().process_frame
	var normal_ok := true
	for child in arena.get_children():
		if child is ProjectileNode and child.leaves_fire_trail:
			normal_ok = false
	print("PASS: the normal 3-burst does NOT leave a fire trail" if normal_ok else "FAIL: a normal-fire boomerang unexpectedly set leaves_fire_trail")
	for child in arena.get_children().duplicate():
		if child is ProjectileNode:
			child.queue_free()
	await get_tree().process_frame

	# --- FireTrailNode itself: damages an overlapping victim, then expires ---
	var trail := FireTrailNode.new()
	trail.position = Vector2(400, 300)
	trail.victim = arena.ship_2
	trail.lifetime = 3.0
	arena.ship_2.position = Vector2(400, 300) # standing right in it
	arena.ship_2.state.position = arena.ship_2.position
	arena.add_child(trail)
	await get_tree().process_frame

	var hp_before := arena.ship_2.state.hp
	for i in 15: # 0.5s @ 30fps — comfortably past one TICK_INTERVAL (0.4s)
		await get_tree().physics_frame
	var damaged_ok := arena.ship_2.state.hp < hp_before
	print(("PASS: standing in the fire trail damages the victim (%.1f -> %.1f)" % [hp_before, arena.ship_2.state.hp]) if damaged_ok else "FAIL: the fire trail never damaged the victim")

	for i in 90: # 3s @ 30fps — past its lifetime
		await get_tree().physics_frame
	var expired_ok := not is_instance_valid(trail)
	print("PASS: the fire trail expires after its 3s lifetime" if expired_ok else "FAIL: the fire trail is still alive past its lifetime")

	# --- AI aim compensation: "son tir part vers le haut ou vers le bas,
	# il faut donc viser en consequence" — right when about to throw, the
	# AI should face the opponent's real offset (so the boomerang's fixed
	# arc curves the right way) instead of whatever ball-tracking left it
	# doing. Force ship_1 onto the boomerang, healthy gauge/cooldown, ball
	# far away (not urgent), opponent well below ship_1's Y.
	arena.ship_1.ai_controlled = true
	arena.ship_1.weapon_state = WeaponSystemState.new([weapon], 0)
	arena.ship_1.weapon_state.gauges[0] = weapon.gauge_max
	arena.ship_1.position = Vector2(200, 200)
	arena.ship_1.state.position = arena.ship_1.position
	arena.ship_2.position = Vector2(1080, 500) # well below ship_1
	arena.ship_2.state.position = arena.ship_2.position
	arena.ball.state.position = Vector2(1000, 500) # on ship_2's side — not urgent for ship_1
	arena.ball.position = arena.ball.state.position
	var aim_dir := arena.ship_1._ai_read_input()
	var aim_ok := aim_dir.y > 0.0 # opponent is below (+y) — should face down, not whatever ball-tracking alone would pick
	print(("PASS: about to throw, the AI faces the opponent's real offset (aim.y=%.2f, opponent below)" % aim_dir.y) if aim_ok else ("FAIL: aim didn't compensate for the opponent's offset (aim.y=%.2f)" % aim_dir.y))

	arena.queue_free()
	await get_tree().process_frame

	var all_ok := scale_ok and charged_ok and normal_ok and damaged_ok and expired_ok and aim_ok
	get_tree().quit(0 if all_ok else 1)
