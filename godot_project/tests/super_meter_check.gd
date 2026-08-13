extends Node2D

## One-off scene-boot verification for the 2026-08-13 "systeme des 5
## balles" pass (project memory super-meter-backlog-idea: Camil, 2026-08-
## 11 — "5 ronds vides qui se remplissent avec une balle a chaque fois
## que l'adversaire perd la balle. Au bout de 5 balles (jauge pleine) on
## peut declencher un super."). Covers the full loop through REAL
## production code paths, not synthetic shortcuts: a real ball miss (via
## ball_node.gd's actual _resolve_out_of_bounds()) fills the OPPONENT's
## super pip five times, then the trigger key (real
## Input.parse_input_event, same pattern as character_select_nav_check.gd/
## ready_gate_check.gd) fires super_triggered, damages the opponent, and
## resets the meter. Run with:
##   Godot --headless --path godot_project res://tests/super_meter_check.tscn --quit-after 30

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame
	arena._unfreeze_round() # skip the ready gate — that's ready_gate_check.gd's job, this test is about the super meter itself

	# --- Fill ship_2's meter via 5 REAL misses by ship_1 (side 0) ---
	var bounds: Rect2 = arena.ball.arena_bounds
	var off_left := Vector2(bounds.position.x - BallState.RADIUS * 5.0, bounds.position.y + bounds.size.y / 2.0)
	var fill_ok := true
	for i in WeaponSystemState.SUPER_METER_MAX:
		var pips_before: int = arena.ship_2.weapon_state.super_pips
		arena.ball.state.position = off_left
		arena.ball._resolve_out_of_bounds()
		var pips_after: int = arena.ship_2.weapon_state.super_pips
		if pips_after != pips_before + 1:
			fill_ok = false
			print("FAIL: miss #%d expected ship_2 pips %d -> %d, got %d" % [i + 1, pips_before, pips_before + 1, pips_after])
	print("PASS: 5 real ball misses by ship_1 fill ship_2's super meter one pip at a time" if fill_ok else "FAIL: see above")

	var ready_ok: bool = arena.ship_2.weapon_state.super_ready()
	print("PASS: ship_2's meter reads ready after 5 misses" if ready_ok else "FAIL: ship_2's meter not ready (pips=%d)" % arena.ship_2.weapon_state.super_pips)

	# --- Trigger ship_2's super (P2's key: numpad Enter) ---
	var hp_before: float = arena.ship_1.state.hp
	var down := InputEventKey.new()
	down.physical_keycode = KEY_KP_ENTER
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_KP_ENTER
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

	var meter_reset_ok: bool = arena.ship_2.weapon_state.super_pips == 0 and not arena.ship_2.weapon_state.super_ready()
	print("PASS: triggering the super spends the whole meter" if meter_reset_ok else "FAIL: ship_2's meter still reads %d after triggering" % arena.ship_2.weapon_state.super_pips)

	var damage_ok: bool = is_equal_approx(arena.ship_1.state.hp, hp_before - MatchArenaNode.GENERIC_SUPER_DAMAGE)
	print("PASS: the opponent (ship_1) takes the generic super's damage" if damage_ok else "FAIL: ship_1 HP was %.1f -> %.1f, expected a %.1f drop" % [hp_before, arena.ship_1.state.hp, MatchArenaNode.GENERIC_SUPER_DAMAGE])

	var all_ok := fill_ok and ready_ok and meter_reset_ok and damage_ok
	get_tree().quit(0 if all_ok else 1)
