extends Node2D

## One-off scene-boot verification for Contrôleur's Ultra, "Trou noir"
## (2026-08-13 Epic 4 party-mode memlog: "champ continu, attire+ralentit,
## synergie avec ses tourelles"). Own dedicated file, same reasoning as
## the other per-Ultra check files. Confirms: the guaranteed floor lands
## at unfreeze, a BlackHoleNode spawns targeting the opponent, and —
## placing the opponent inside its radius and ticking a few physics
## frames — it actually pulls them closer (real ShipNode.apply_knockback()
## calls, not just a flag) and applies the external slow (distinct from
## the self-slow timer other effects use, so this proves they don't
## collide). Run with:
##   Godot --headless --path godot_project res://tests/ultra_trou_noir_check.tscn --quit-after 2200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/controleur.tres"))
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

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.TROU_NOIR_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.TROU_NOIR_GUARANTEED_DAMAGE]))

	var black_hole: BlackHoleNode = null
	for child in arena.get_children():
		if child is BlackHoleNode:
			black_hole = child
	var spawn_ok: bool = black_hole != null and black_hole.target == arena.ship_2
	print("PASS: a BlackHoleNode spawned targeting the opponent" if spawn_ok else "FAIL: no BlackHoleNode found (or wrong target)")
	if not spawn_ok:
		get_tree().quit(1)
		return

	# Place ship_2 inside the field's radius (real gameplay position at
	# trigger time is arbitrary) and tick a few frames to observe the
	# pull/slow actually apply, not just check a static config. Both
	# ship.position (the Node2D transform) AND ship.state.position (the
	# pure simulation state) need setting — _physics_process() recomputes
	# state.update() from the LATTER every tick and overwrites .position
	# from it right after, so touching only .position gets silently
	# reverted to wherever state.position actually was on the next tick.
	arena.ship_2.position = black_hole.position + Vector2(black_hole.radius * 0.7, 0.0)
	arena.ship_2.state.position = arena.ship_2.position
	var dist_before := arena.ship_2.position.distance_to(black_hole.position)
	for i in 5:
		await get_tree().physics_frame
	var dist_after := arena.ship_2.position.distance_to(black_hole.position)
	var pull_ok: bool = dist_after < dist_before
	print(("PASS: the field pulls the opponent closer (dist %.1f -> %.1f)" % [dist_before, dist_after]) if pull_ok else ("FAIL: opponent didn't get pulled closer (dist %.1f -> %.1f)" % [dist_before, dist_after]))
	var slow_ok: bool = arena.ship_2._external_slow_timer > 0.0 and is_equal_approx(arena.ship_2._external_slow_multiplier, MatchArenaNode.TROU_NOIR_SLOW_MULTIPLIER)
	print("PASS: the opponent's external slow is applied while inside the field" if slow_ok else "FAIL: external slow wasn't applied correctly")

	var all_ok := floor_ok and spawn_ok and pull_ok and slow_ok
	get_tree().quit(0 if all_ok else 1)
