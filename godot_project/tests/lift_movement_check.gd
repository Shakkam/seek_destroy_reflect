extends Node2D

## One-off scene-boot verification for the 2026-08-13 lift rework (Camil:
## "pendant la charge, il faut pouvoir se deplacer un peu. je dirais, 25%
## de la vitesse normale" — charging the lift used to freeze movement
## entirely). Drives it through REAL production code — real
## Input.parse_input_event key presses (D + Shift held together) and
## get_tree().physics_frame tick-precise displacement measurement, same
## pattern as vif_recoil_check.gd. Run with:
##   Godot --headless --path godot_project res://tests/lift_movement_check.tscn --quit-after 30

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame
	arena._unfreeze_round()

	# Baseline: D held alone, no lift.
	_hold_key(KEY_D, true)
	await get_tree().physics_frame
	var pos_before := arena.ship_1.position
	await get_tree().physics_frame
	var baseline_step := arena.ship_1.position.distance_to(pos_before)

	# Now hold Lift (Shift) too — still moving, but charging.
	_hold_key(KEY_SHIFT, true)
	await get_tree().physics_frame # let the held-key state fully register (see vif_recoil_check.gd's note on this)
	var pos_charging := arena.ship_1.position
	await get_tree().physics_frame
	var charging_step := arena.ship_1.position.distance_to(pos_charging)
	_hold_key(KEY_D, false)
	_hold_key(KEY_SHIFT, false)

	var not_frozen: bool = charging_step > 0.5 # used to be an exact 0.0 freeze
	print(("PASS: movement isn't fully frozen while charging the lift anymore (step=%.2fpx)" % charging_step) if not_frozen else ("FAIL: still frozen solid while charging (step=%.2fpx)" % charging_step))

	var ratio := charging_step / baseline_step if baseline_step > 0.0 else 0.0
	var ratio_ok: bool = is_equal_approx(ratio, ShipNode.LIFT_CHARGE_MOVE_MULTIPLIER) or absf(ratio - ShipNode.LIFT_CHARGE_MOVE_MULTIPLIER) < 0.05
	print(("PASS: the charging speed is ~25%% of baseline (baseline=%.2fpx, charging=%.2fpx, ratio=%.3f)" % [baseline_step, charging_step, ratio]) if ratio_ok else ("FAIL: expected ~%.2f ratio, got %.3f (baseline=%.2fpx, charging=%.2fpx)" % [ShipNode.LIFT_CHARGE_MOVE_MULTIPLIER, ratio, baseline_step, charging_step]))

	var all_ok := not_frozen and ratio_ok
	get_tree().quit(0 if all_ok else 1)

func _hold_key(physical_keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
