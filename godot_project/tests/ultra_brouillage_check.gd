extends Node2D

## One-off scene-boot verification for Perturbateur's Ultra, "Brouillage
## de commandes" (2026-08-13 Epic 4 party-mode memlog: "scramble les
## controles adverses"). Own dedicated file, same reasoning as the other
## per-Ultra check files. Confirms: the guaranteed floor lands at
## unfreeze, the opponent's _controls_scrambled_timer is armed, and —
## the actual point of the effect — a REAL simulated keypress
## (Input.parse_input_event, P2's RIGHT arrow) reads back INVERTED from
## ShipNode._read_input() while scrambled, then reads normally again once
## the scramble duration elapses. Run with:
##   Godot --headless --path godot_project res://tests/ultra_brouillage_check.tscn --quit-after 2500

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/perturbateur.tres"))
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

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.BROUILLAGE_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.BROUILLAGE_GUARANTEED_DAMAGE]))

	var armed_ok: bool = arena.ship_2._controls_scrambled_timer > 0.0
	print("PASS: the opponent's controls-scrambled timer is armed" if armed_ok else "FAIL: _controls_scrambled_timer wasn't armed")

	# Hold P2's RIGHT arrow — raw input would read (1, 0); scrambled, the
	# actual _read_input() ShipNode._physics_process() uses should read
	# the opposite.
	var right := InputEventKey.new()
	right.physical_keycode = KEY_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	await get_tree().physics_frame

	var raw := arena.ship_2._read_raw_input()
	var scrambled_read := arena.ship_2._read_input()
	var invert_ok: bool = raw.x > 0.0 and scrambled_read.x < 0.0
	print(("PASS: input reads inverted while scrambled (raw=%s, actual=%s)" % [raw, scrambled_read]) if invert_ok else ("FAIL: input wasn't inverted (raw=%s, actual=%s)" % [raw, scrambled_read]))

	# Wait out the scramble duration, confirm input reads normally again.
	for i in 2000:
		await get_tree().physics_frame
		if arena.ship_2._controls_scrambled_timer <= 0.0:
			break
	var restored_read := arena.ship_2._read_input()
	var restored_ok: bool = arena.ship_2._controls_scrambled_timer <= 0.0 and restored_read.x > 0.0
	print(("PASS: input reads normally again once the scramble expires (actual=%s)" % restored_read) if restored_ok else ("FAIL: scramble never expired or input still inverted (timer=%.2f, actual=%s)" % [arena.ship_2._controls_scrambled_timer, restored_read]))

	var all_ok := floor_ok and armed_ok and invert_ok and restored_ok
	get_tree().quit(0 if all_ok else 1)
