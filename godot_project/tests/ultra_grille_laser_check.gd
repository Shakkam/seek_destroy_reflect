extends Node2D

## One-off scene-boot verification for Zoneur's Ultra, "Grille Laser"
## (2026-08-13 Epic 4 party-mode memlog: "grille laser (motif de faisceaux
## lisible, des trous a trouver)"). Own dedicated file, same reasoning as
## ultra_mitrailleuses_satellites_check.gd — keeps each Ultra's test run
## focused instead of growing one shared wait-loop file. Confirms: the
## guaranteed floor lands at unfreeze, exactly (BAND_COUNT - GAP_COUNT)
## fixed-position BeamNodes spawn, each landing on one of the expected
## evenly-spaced band Y positions with freeze_position actually set (the
## whole point of the BeamNode change — a beam that doesn't chase the
## shooter). Run with:
##   Godot --headless --path godot_project res://tests/ultra_grille_laser_check.tscn --quit-after 2200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/zoneur.tres"))
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

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.GRILLE_LASER_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.GRILLE_LASER_GUARANTEED_DAMAGE]))

	var beams: Array = []
	for child in arena.get_children():
		if child is BeamNode:
			beams.append(child)
	var expected_beam_count := MatchArenaNode.GRILLE_LASER_BAND_COUNT - MatchArenaNode.GRILLE_LASER_GAP_COUNT
	var count_ok: bool = beams.size() == expected_beam_count
	print(("PASS: %d/%d bands are active (the rest are gaps)" % [beams.size(), MatchArenaNode.GRILLE_LASER_BAND_COUNT]) if count_ok else ("FAIL: %d beams spawned, expected %d" % [beams.size(), expected_beam_count]))

	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	var expected_ys: Array = []
	for i in MatchArenaNode.GRILLE_LASER_BAND_COUNT:
		var t := float(i) / float(MatchArenaNode.GRILLE_LASER_BAND_COUNT - 1)
		expected_ys.append(lerpf(bounds.position.y + MatchArenaNode.GRILLE_LASER_BAND_MARGIN, bounds.position.y + bounds.size.y - MatchArenaNode.GRILLE_LASER_BAND_MARGIN, t))

	var config_ok := true
	var seen_ys: Array = []
	for beam in beams:
		if not beam.freeze_position:
			config_ok = false
		if beam.weapon != MatchArenaNode.ULTRA_GRILLE_LASER:
			config_ok = false
		var matched := false
		for y in expected_ys:
			if is_equal_approx(beam.position.y, y):
				matched = true
		if not matched:
			config_ok = false
		if beam.position.y in seen_ys: # no two active bands land on the same gap-shuffled slot
			config_ok = false
		seen_ys.append(beam.position.y)
	print("PASS: every beam is frozen in place on a real, distinct band position" if config_ok else "FAIL: a beam's freeze_position/weapon/band-Y was wrong")

	var all_ok := floor_ok and count_ok and config_ok
	get_tree().quit(0 if all_ok else 1)
