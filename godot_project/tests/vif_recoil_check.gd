extends Node2D

## One-off scene-boot verification for the 2026-08-13 Vif weapon rework
## (Camil: "a chaque tire, vif, a une petite poussee d'acceleration de
## 100% degressif sur 1/2 seconde"). Drives it through REAL production
## code paths — real Input.parse_input_event key presses, same pattern as
## character_select_nav_check.gd/ready_gate_check.gd/ultra_meter_check.gd —
## measuring actual per-tick displacement before/right-after/well-after
## firing to confirm the boost applies and decays. Uses
## get_tree().physics_frame for precise tick counting instead of a real
## wall-clock SceneTreeTimer (see ready_gate_check.gd's header for why
## that needs a much bigger --quit-after; this avoids that specific
## problem, but still needs a generous budget for its own ~30-tick decay
## wait). Run with:
##   Godot --headless --path godot_project res://tests/vif_recoil_check.tscn --quit-after 200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var vif: CharacterData = load("res://data/characters/vif.tres")
	arena.ship_1.set_character(vif)
	arena.ship_1.weapon_state = arena.ship_1.weapon_state.with_gauge_added(999.0) # guarantee the Tourbillon can fire regardless of its actual gauge_cost_per_shot
	arena._unfreeze_round()

	# Hold movement (D) throughout — measure baseline displacement/tick
	# BEFORE firing at all.
	_hold_key(KEY_D, true)
	await get_tree().physics_frame
	var pos_before_move := arena.ship_1.position
	await get_tree().physics_frame
	var baseline_step := arena.ship_1.position.distance_to(pos_before_move)

	# Fire (Space) for exactly one tick, then release — semi-auto fires on
	# the rising edge, no need to hold.
	_hold_key(KEY_SPACE, true)
	await get_tree().physics_frame # the fire itself happens THIS tick (FIRE_HOLD_SPEED_MULTIPLIER slows THIS tick's movement, unrelated to what we're measuring), setting the recoil timer at the very end of the tick
	_hold_key(KEY_SPACE, false)
	await get_tree().physics_frame # one tick for the release to fully register — releasing and measuring on the SAME awaited tick still read fire_held as true (FIRE_HOLD_SPEED_MULTIPLIER-shaped 0.5x results), so the snapshot below is taken one tick later than the fire itself

	var pos_at_fire := arena.ship_1.position
	await get_tree().physics_frame # first tick where the boost is actually live
	var boosted_step := arena.ship_1.position.distance_to(pos_at_fire)

	var boost_ok: bool = boosted_step > baseline_step * 1.3
	print(("PASS: Vif's movement is measurably boosted the tick right after firing (baseline=%.2fpx, boosted=%.2fpx)" % [baseline_step, boosted_step]) if boost_ok else ("FAIL: expected a clear boost, got baseline=%.2fpx boosted=%.2fpx" % [baseline_step, boosted_step]))

	# Keep holding D, let the 0.5s decay window fully elapse (30 physics
	# ticks/sec per project.godot -> ~15 ticks; wait extra for safety),
	# then confirm it's back to baseline.
	for i in 25:
		await get_tree().physics_frame
	var pos_settled := arena.ship_1.position
	await get_tree().physics_frame
	var settled_step := arena.ship_1.position.distance_to(pos_settled)
	var decay_ok: bool = settled_step < baseline_step * 1.3
	print(("PASS: the boost decays back to baseline well within the wait" if decay_ok else "FAIL: still boosted long after the decay window (settled=%.2fpx, baseline=%.2fpx)" % [settled_step, baseline_step]))

	_hold_key(KEY_D, false)

	var all_ok := boost_ok and decay_ok
	get_tree().quit(0 if all_ok else 1)

func _hold_key(physical_keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
