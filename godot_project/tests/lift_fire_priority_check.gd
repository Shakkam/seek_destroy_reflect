extends Node2D

## One-off scene-boot verification for the 2026-08-13 lift/fire priority
## fix (Camil: "si j'appuie a la fois sur charge tir + charge lift, ca
## fait... du caca. on va donner la priorite au lift dans ce cas."):
## holding Lift + Fire together must NOT fire at all — Lift wins outright
## — and releasing Lift while still holding Fire must let firing resume
## normally right after. Real Input.parse_input_event key presses, same
## pattern as vif_recoil_check.gd/lift_movement_check.gd. Run with:
##   Godot --headless --path godot_project res://tests/lift_fire_priority_check.tscn --quit-after 60

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var vif: CharacterData = load("res://data/characters/vif.tres")
	arena.ship_1.set_character(vif)
	arena.ship_1.weapon_state = arena.ship_1.weapon_state.with_gauge_added(999.0) # guarantee the Tourbillon can fire regardless of its actual gauge_cost_per_shot
	arena._unfreeze_round()

	# Hold Lift (Shift) + Fire (Space) together — Lift must win, no shot.
	var gauge_before_both := arena.ship_1.weapon_state.gauges[0]
	_hold_key(KEY_SHIFT, true)
	_hold_key(KEY_SPACE, true)
	for i in 5:
		await get_tree().physics_frame
	var gauge_after_both := arena.ship_1.weapon_state.gauges[0]
	var no_fire_while_both_held: bool = is_equal_approx(gauge_after_both, gauge_before_both)
	print(("PASS: holding Lift + Fire together fires nothing at all (lift wins outright)" if no_fire_while_both_held else ("FAIL: a shot fired anyway while both were held (gauge %.1f -> %.1f)" % [gauge_before_both, gauge_after_both])))

	# Release Lift, keep Fire held — firing should resume normally right after.
	_hold_key(KEY_SHIFT, false)
	await get_tree().physics_frame # let the release register (established one-tick lag, see vif_recoil_check.gd)
	var gauge_before_fire_alone := arena.ship_1.weapon_state.gauges[0]
	await get_tree().physics_frame
	var gauge_after_fire_alone := arena.ship_1.weapon_state.gauges[0]
	var fires_once_lift_released: bool = gauge_after_fire_alone < gauge_before_fire_alone
	print(("PASS: releasing Lift while Fire is still held lets firing resume" if fires_once_lift_released else ("FAIL: still didn't fire after releasing Lift (gauge %.1f -> %.1f)" % [gauge_before_fire_alone, gauge_after_fire_alone])))

	_hold_key(KEY_SPACE, false)

	var all_ok := no_fire_while_both_held and fires_once_lift_released
	get_tree().quit(0 if all_ok else 1)

func _hold_key(physical_keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
