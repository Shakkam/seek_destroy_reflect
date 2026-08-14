extends Node2D

## One-off scene-boot verification for the 2026-08-13 dev cheat keys
## (Camil: "des cheats shortcuts pour tests ingame - k => tu instantanement
## l'adversaire, u => passe les balles a 5 (pour pouvoir declencher un
## ultre), m => munitions a 100"). Real Input.parse_input_event key
## presses, same pattern as every other input-driven test this session.
## Run with:
##   Godot --headless --path godot_project res://tests/cheat_keys_check.tscn --quit-after 30

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame
	arena._unfreeze_round() # cheats are gated on _round_playing

	# --- M: fill ship_1's ammo to 100 ---
	var gauge_before := arena.ship_1.weapon_state.gauges[0]
	_tap_key(KEY_M)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gauge_after := arena.ship_1.weapon_state.gauges[0]
	var ammo_ok: bool = is_equal_approx(gauge_after, arena.ship_1.weapon_state.kit[0].gauge_max) and gauge_after > gauge_before
	print(("PASS: M fills ship_1's ammo to max (%.0f -> %.0f)" % [gauge_before, gauge_after]) if ammo_ok else ("FAIL: M didn't fill ammo to max (%.0f -> %.0f, max=%.0f)" % [gauge_before, gauge_after, arena.ship_1.weapon_state.kit[0].gauge_max]))

	# --- U: max ship_1's ultra meter ---
	var ultra_before := arena.ship_1.weapon_state.ultra_pips
	_tap_key(KEY_U)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ultra_ok: bool = arena.ship_1.weapon_state.ultra_ready() and arena.ship_1.weapon_state.ultra_pips == WeaponSystemState.ULTRA_METER_MAX
	print(("PASS: U maxes ship_1's ultra meter (%d -> %d)" % [ultra_before, arena.ship_1.weapon_state.ultra_pips]) if ultra_ok else ("FAIL: U didn't max the ultra meter (%d -> %d)" % [ultra_before, arena.ship_1.weapon_state.ultra_pips]))

	# --- K: instantly kill the opponent (ship_2) ---
	# NOTE: apply_damage() and _check_round_end() both run within the SAME
	# _process() call, so a kill's HP-0 is only ever transient — by the
	# time any later frame is observed, a non-match-ending round win has
	# already reset ship_2 back to full HP for the next round (the real,
	# correct round-end flow, same as an actual kill). What's actually
	# checkable here is that the kill was awarded as a round win.
	var rounds_won_before: int = arena.match_state.rounds_won[0]
	_tap_key(KEY_K)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var kill_ok: bool = arena.match_state.rounds_won[0] == rounds_won_before + 1
	print(("PASS: K instantly kills the opponent, awarding ship_1 a round win (%d -> %d)" % [rounds_won_before, arena.match_state.rounds_won[0]]) if kill_ok else ("FAIL: K didn't award ship_1 a round win (%d -> %d)" % [rounds_won_before, arena.match_state.rounds_won[0]]))

	var all_ok := ammo_ok and ultra_ok and kill_ok
	get_tree().quit(0 if all_ok else 1)

func _tap_key(physical_keycode: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = physical_keycode
	down.pressed = true
	Input.parse_input_event(down)
