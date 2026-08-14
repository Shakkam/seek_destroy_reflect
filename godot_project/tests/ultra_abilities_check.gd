extends Node2D

## One-off scene-boot verification for the first two bespoke Ultras
## (2026-08-13 Epic 4 party-mode memlog roster, replacing the generic
## 25-damage placeholder): Traqueur's "La Meute" and Lourd's "Pluie de
## Scuds". Confirms, via the real trigger path (Input.parse_input_event,
## same pattern as ultra_meter_check.gd): (1) the guaranteed damage floor
## always lands, immediately, regardless of the burst, and (2) the full
## projectile burst actually spawns (right count of ProjectileNode
## children) rather than just checking the floor and assuming the rest
## works. Run with:
##   Godot --headless --path godot_project res://tests/ultra_abilities_check.tscn --quit-after 5500

func _ready() -> void:
	var la_meute_ok := await _check_ultra(
		load("res://data/characters/missiles.tres"), # Traqueur
		MatchArenaNode.LA_MEUTE_GUARANTEED_DAMAGE,
		MatchArenaNode.ULTRA_LA_MEUTE.projectile_count,
		"La Meute",
	)
	var scuds_ok := await _check_ultra(
		load("res://data/characters/lourd.tres"),
		MatchArenaNode.PLUIE_DE_SCUDS_GUARANTEED_DAMAGE,
		MatchArenaNode.PLUIE_DE_SCUDS_SHELL_COUNT,
		"Pluie de Scuds",
	)
	get_tree().quit(0 if (la_meute_ok and scuds_ok) else 1)

func _check_ultra(character: CharacterData, expected_floor: float, expected_projectile_count: int, expected_name: String) -> bool:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(character)
	while not arena.ship_1.weapon_state.ultra_ready():
		arena.ship_1.add_ultra_pip()
	arena._unfreeze_round()

	var hp_before: float = arena.ship_2.state.hp
	_tap_key(KEY_E) # P1's Ultra trigger
	await get_tree().physics_frame
	await get_tree().physics_frame # matches ultra_meter_check.gd's press-then-2-frames pattern — one frame alone isn't reliably enough for the input event to be observed
	var hp_right_after: float = arena.ship_2.state.hp
	var floor_ok: bool = is_equal_approx(hp_before - hp_right_after, expected_floor)
	print(("PASS: %s's guaranteed floor lands immediately (%.0f -> %.0f)" % [expected_name, hp_before, hp_right_after]) if floor_ok else ("FAIL: %s's floor was wrong (%.0f -> %.0f, expected -%.0f)" % [expected_name, hp_before, hp_right_after, expected_floor]))

	# Staggered spawns use get_tree().create_timer() (real process-delta
	# accumulation, same as the "GO !" flash) — headless frames run far
	# faster than realtime, so waiting out even ~0.6s of stagger needs
	# hundreds of awaited frames, not a couple dozen (see project memory's
	# "--quit-after counts FRAMES" trap, same underlying cause). Sampling
	# the LIVE count every tick (not just once at the end) instead of
	# guessing a single "everything's spawned, nothing's hit yet" moment —
	# a homing burst against a stationary target starts connecting well
	# before every staggered shot has even spawned, so the count rises
	# and falls; the peak is what proves the full burst actually happened.
	var peak_projectile_count := 0
	for i in 400:
		await get_tree().physics_frame
		var live_count := 0
		for child in arena.get_children():
			if child is ProjectileNode:
				live_count += 1
		peak_projectile_count = maxi(peak_projectile_count, live_count)
	var burst_ok: bool = peak_projectile_count == expected_projectile_count
	print(("PASS: %s's full burst spawned (peak %d projectiles live at once)" % [expected_name, peak_projectile_count]) if burst_ok else ("FAIL: %s's peak live count was %d, expected %d" % [expected_name, peak_projectile_count, expected_projectile_count]))

	arena.queue_free()
	await get_tree().process_frame
	return floor_ok and burst_ok

## Presses and leaves the key held — safe here because each _check_ultra()
## call uses a brand-new ShipNode (fresh _ultra_prev = false default), so
## there's no risk of a leftover press blocking a later edge like there
## would be reusing one ship across multiple taps (see
## character_select_nav_check.gd's _tap() for that case instead).
func _tap_key(physical_keycode: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = physical_keycode
	down.pressed = true
	Input.parse_input_event(down)
