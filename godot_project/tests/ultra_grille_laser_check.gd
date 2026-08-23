extends Node2D

## One-off scene-boot verification for Zoneur's Ultra, "Grille Laser"
## (reworked 2026-08-15, Camil: "ca fait trois lasers horizontaux. On
## avait dit que ca devait faire des laser en maillage, qui apparaissent
## au fur et a mesure (10 lasers sur 1 seconde), dans tous les sens, et
## uniquement dans le champ adverse, direction random" — replaces the old
## fixed horizontal BeamNode bands entirely). Own dedicated file, same
## reasoning as ultra_mitrailleuses_satellites_check.gd. Confirms: the
## guaranteed floor lands at unfreeze, exactly GRILLE_LASER_COUNT
## LaserMeshNodes spawn cumulatively (short-lived + staggered, so most
## never coexist — see ultra_abilities_check.gd's "cumulative" mode for
## the same pattern), every segment stays fully inside the OPPONENT's
## half, and the angles actually vary (not a regression back to
## all-horizontal). Run with:
##   Godot --headless --path godot_project res://tests/ultra_grille_laser_check.tscn --quit-after 20000

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
	var seen: Dictionary = {} # instance_id -> {start, end}, recorded the first time each laser is observed
	for i in 1600:
		await get_tree().physics_frame
		if not was_active and arena.ship_1.active:
			hp_at_unfreeze = arena.ship_2.state.hp
		was_active = arena.ship_1.active
		for child in arena.get_children():
			if child is LaserMeshNode:
				var id := child.get_instance_id()
				if not seen.has(id):
					seen[id] = {"start": child.start, "end": child.end}

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.GRILLE_LASER_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.GRILLE_LASER_GUARANTEED_DAMAGE]))

	var count_ok: bool = seen.size() == MatchArenaNode.GRILLE_LASER_COUNT
	print(("PASS: all %d lasers spawned over the build-up window" % seen.size()) if count_ok else ("FAIL: %d lasers spawned, expected %d" % [seen.size(), MatchArenaNode.GRILLE_LASER_COUNT]))

	# ship_2 (the target) is on side 1 (right half) in this test's default
	# setup — confined_ok checks both endpoints of every segment land at or
	# past the frontier, never bleeding into ship_1's half.
	var confined_ok := true
	var angles: Array = []
	for id in seen:
		var seg: Dictionary = seen[id]
		var start: Vector2 = seg.start
		var end: Vector2 = seg.end
		if start.x < arena._current_frontier_x - 0.01 or end.x < arena._current_frontier_x - 0.01:
			confined_ok = false
		angles.append(wrapf((end - start).angle(), 0.0, PI)) # mod PI: a line's angle and angle+PI describe the same line
	print("PASS: every laser stays confined to the opponent's half" if confined_ok else "FAIL: at least one laser crossed into the shooter's own half")

	var angle_variety_ok := false
	for a in angles:
		for b in angles:
			if absf(a - b) > deg_to_rad(20.0): # any two segments meaningfully non-parallel is enough to prove it's not just horizontal again
				angle_variety_ok = true
	print("PASS: laser angles actually vary (not a regression to all-horizontal)" if angle_variety_ok else "FAIL: every laser landed at basically the same angle")

	var all_ok := floor_ok and count_ok and confined_ok and angle_variety_ok
	get_tree().quit(0 if all_ok else 1)
