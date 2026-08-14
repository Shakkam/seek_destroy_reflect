extends Node2D

## One-off scene-boot verification for the first two bespoke Ultras
## (2026-08-13 Epic 4 party-mode memlog roster, replacing the generic
## 25-damage placeholder): Traqueur's "La Meute" and Lourd's "Pluie de
## Scuds". Confirms, via the real trigger path (Input.parse_input_event,
## same pattern as ultra_meter_check.gd): (1) triggering freezes the
## match and plays the UltraIntroNode intro beat (2026-08-14) BEFORE
## anything lands — no damage, no projectiles, ships/ball inactive; (2)
## once the intro finishes, ships/ball unfreeze and the guaranteed damage
## floor lands; (3) the full projectile burst actually spawns (right
## count of ProjectileNode children). Run with:
##   Godot --headless --path godot_project res://tests/ultra_abilities_check.tscn --quit-after 20000

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

	# --- The 2026-08-14 intro beat gates the attack — nothing should land yet ---
	var frozen_during_intro: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active
	print(("PASS: %s's trigger freezes the match for the intro beat" % expected_name) if frozen_during_intro else ("FAIL: %s didn't freeze for the intro" % expected_name))
	var intro_showing: bool = false
	for child in arena.debug_hud.get_children():
		if child is UltraIntroNode:
			intro_showing = true
	print(("PASS: %s's UltraIntroNode is showing" % expected_name) if intro_showing else ("FAIL: %s's intro node never appeared" % expected_name))
	var hp_during_intro: float = arena.ship_2.state.hp
	var no_early_damage: bool = is_equal_approx(hp_during_intro, hp_before)
	print(("PASS: %s deals no damage until the intro finishes" % expected_name) if no_early_damage else ("FAIL: %s dealt damage before the intro finished (%.0f -> %.0f)" % [expected_name, hp_before, hp_during_intro]))

	# Single combined wait loop, not two separate windows: the intro
	# (~1.667s) plus the missile swarm's OWN flight-to-impact time can
	# together take longer than expected, so a fixed "wait out the intro,
	# THEN check the floor, THEN wait again for the burst" sequence risks
	# the burst having already fully resolved (hit or expired) by the time
	# the second window even starts. Instead: catch the exact tick ships
	# transition frozen -> active (that's the intro finishing and
	# _resolve_ultra_effect() having just run synchronously) and sample
	# HP right there — before any projectile has had a tick to travel —
	# while ALSO tracking the peak live projectile count across the whole
	# loop regardless of when that transition happens.
	var was_active := arena.ship_1.active
	var hp_at_unfreeze := -1.0
	var peak_projectile_count := 0
	for i in 1600:
		await get_tree().physics_frame
		if not was_active and arena.ship_1.active:
			hp_at_unfreeze = arena.ship_2.state.hp
		was_active = arena.ship_1.active
		var live_count := 0
		for child in arena.get_children():
			if child is ProjectileNode:
				live_count += 1
		peak_projectile_count = maxi(peak_projectile_count, live_count)

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, expected_floor)
	print(("PASS: %s's guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [expected_name, hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: %s's floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [expected_name, hp_before, hp_at_unfreeze, expected_floor]))
	var unfrozen_after: bool = arena.ship_1.active and arena.ship_2.active and arena.ball.active
	print(("PASS: %s's match is unfrozen by the end of the wait" % expected_name) if unfrozen_after else ("FAIL: %s's match stayed frozen" % expected_name))
	var burst_ok: bool = peak_projectile_count == expected_projectile_count
	print(("PASS: %s's full burst spawned (peak %d projectiles live at once)" % [expected_name, peak_projectile_count]) if burst_ok else ("FAIL: %s's peak live count was %d, expected %d" % [expected_name, peak_projectile_count, expected_projectile_count]))

	arena.queue_free()
	await get_tree().process_frame
	return frozen_during_intro and intro_showing and no_early_damage and floor_ok and unfrozen_after and burst_ok

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
