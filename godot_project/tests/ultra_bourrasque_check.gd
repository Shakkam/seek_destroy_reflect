extends Node2D

## One-off scene-boot verification for Vif's Ultra rework, "Bourrasque"
## (2026-08-15, Camil, with a reference image): 10 vortices at FIXED
## (not random) vertical slots, spawned off-screen behind the caster's
## own wall, racing straight toward the opponent's half; plus a
## continuous WindGustNode shoving the opponent toward their own outer
## wall for the duration. Own dedicated file, same reasoning as the
## other per-Ultra check files. Confirms: the guaranteed floor lands at
## unfreeze, exactly 10 vortex ProjectileNodes spawn — each at the exact
## Y fraction from BOURRASQUE_VORTEX_Y_FRACTIONS (not random), off-screen
## on the caster's side, heading toward the opponent — a WindGustNode
## spawns targeting the opponent, and it actually pushes them (real
## ShipNode.apply_knockback() calls) toward THEIR OWN outer wall, not
## toward the frontier. Run with:
##   Godot --headless --path godot_project res://tests/ultra_bourrasque_check.tscn --quit-after 2200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/vif.tres"))
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

	var was_active := arena.ship_1.active
	var hp_at_unfreeze := -1.0
	for i in 1600:
		await get_tree().physics_frame
		if not was_active and arena.ship_1.active:
			hp_at_unfreeze = arena.ship_2.state.hp
			break
		was_active = arena.ship_1.active

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.BOURRASQUE_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.BOURRASQUE_GUARANTEED_DAMAGE]))

	var vortices: Array = []
	for child in arena.get_children():
		if child is ProjectileNode and child.textures == MatchArenaNode.BOURRASQUE_VORTEX_TEXTURES:
			vortices.append(child)
	var count_ok: bool = vortices.size() == MatchArenaNode.BOURRASQUE_VORTEX_COUNT
	print(("PASS: all %d vortices spawned at once" % vortices.size()) if count_ok else ("FAIL: %d vortices spawned, expected %d" % [vortices.size(), MatchArenaNode.BOURRASQUE_VORTEX_COUNT]))

	# Fixed placement, not random: every vortex's Y must match one of the
	# configured fractions exactly, off-screen on ship_1's own side (side
	# 0 -> spawn X below the arena's left wall), heading toward ship_2.
	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	var expected_ys: Array = []
	for f in MatchArenaNode.BOURRASQUE_VORTEX_Y_FRACTIONS:
		expected_ys.append(bounds.position.y + bounds.size.y * f)
	var placement_ok := true
	for v in vortices:
		if v.position.x >= bounds.position.x:
			placement_ok = false # must start OFF-SCREEN, behind the caster's own wall
		if v.velocity.x <= 0.0:
			placement_ok = false # heading toward the opponent (side 0 -> positive X)
		if v.acceleration <= 0.0:
			placement_ok = false # "avancent de plus en plus vite" — must actually speed up over time
		var matched := false
		for y in expected_ys:
			if is_equal_approx(v.position.y, y):
				matched = true
		if not matched:
			placement_ok = false
		# NOT checking for distinct Y across vortices — two slots in
		# BOURRASQUE_VORTEX_Y_FRACTIONS deliberately share the same value
		# (matching the reference image, where two tornadoes land at the
		# same height), so a duplicate Y is expected, not a bug.
	print("PASS: every vortex spawns off-screen at a fixed Y slot, accelerating toward the opponent" if placement_ok else "FAIL: a vortex's spawn position/velocity/acceleration was wrong")

	# 2026-08-16: "les tourbillons ne doivent pas tourner sur eux meme" - no
	# node self-rotation; the tornado read comes purely from the texture
	# cycle now (see the count_ok check above already matching on
	# BOURRASQUE_VORTEX_TEXTURES).
	var no_self_spin_ok := true
	for v in vortices:
		if v.spin_speed != 0.0:
			no_self_spin_ok = false
	print("PASS: vortices don't self-rotate (spin_speed == 0)" if no_self_spin_ok else "FAIL: a vortex still has node self-rotation set")

	var gust: WindGustNode = null
	for child in arena.get_children():
		if child is WindGustNode:
			gust = child
	var gust_spawn_ok: bool = gust != null and gust.target == arena.ship_2
	print("PASS: a WindGustNode spawned targeting the opponent" if gust_spawn_ok else "FAIL: no WindGustNode found (or wrong target)")
	if not gust_spawn_ok:
		get_tree().quit(1)
		return

	# ship_2 is on side 1 (right half) — its own outer wall is further
	# RIGHT (away from the frontier), so the gust must push it further
	# right (increasing X), not toward the frontier.
	var x_before := arena.ship_2.position.x
	for i in 5:
		await get_tree().physics_frame
	var x_after := arena.ship_2.position.x
	var push_ok: bool = x_after > x_before
	print(("PASS: the gust pushes the opponent toward their own outer wall (x %.1f -> %.1f)" % [x_before, x_after]) if push_ok else ("FAIL: the opponent wasn't pushed toward their own wall (x %.1f -> %.1f)" % [x_before, x_after]))

	# 2026-08-16 playtest correction: "ca pousse tout le temps de l'ultra
	# (pas au contact). Et plus les tourbillons avancent vite, plus la
	# poussee est forte (a la fin ... il doit meme un poil reculer)" — the
	# gust's push must RAMP UP over its whole duration (not a flat number,
	# and not something that only fires on a vortex hit), ending strong
	# enough to fully cancel ShipState.SPEED (420 px/s) so the opponent
	# can't advance at all by the end.
	var ramps_up_ok: bool = gust.push_speed_end > gust.push_speed_start
	print(("PASS: the gust's push ramps up over the ultra's duration (%.0f -> %.0f)" % [gust.push_speed_start, gust.push_speed_end]) if ramps_up_ok else ("FAIL: the gust's push doesn't ramp up (%.0f -> %.0f)" % [gust.push_speed_start, gust.push_speed_end]))
	var end_overpowers_movement_ok: bool = gust.push_speed_end > ShipState.SPEED
	print(("PASS: by the end, the push (%.0f) fully overpowers movement speed (%.0f) — the opponent can't advance" % [gust.push_speed_end, ShipState.SPEED]) if end_overpowers_movement_ok else ("FAIL: the gust's peak push (%.0f) doesn't clear movement speed (%.0f)" % [gust.push_speed_end, ShipState.SPEED]))
	var start_is_mild_ok: bool = gust.push_speed_start < ShipState.SPEED
	print(("PASS: the push starts mild, not already overpowering (%.0f < %.0f)" % [gust.push_speed_start, ShipState.SPEED]) if start_is_mild_ok else ("FAIL: the push starts too strong already (%.0f >= %.0f)" % [gust.push_speed_start, ShipState.SPEED]))

	var all_ok := floor_ok and count_ok and placement_ok and no_self_spin_ok and gust_spawn_ok and push_ok and ramps_up_ok and end_overpowers_movement_ok and start_is_mild_ok
	get_tree().quit(0 if all_ok else 1)
