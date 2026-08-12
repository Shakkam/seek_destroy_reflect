extends Node2D

## One-off scene-boot verification for the 2026-08-12 SF2-grid redesign
## (Camil: "il faudrait au moins les cadres de selection J1 et J2 qui
## bougent avec les fleches" — after the redesign, testing suggested the
## cursors weren't moving). Simulates REAL keyboard input via
## Input.parse_input_event() with physical_keycode set (feeds the same
## input pipeline is_physical_key_pressed() reads from) — unlike a live
## GUI automation pass (blocked on this machine, see project memory),
## this runs entirely headless and is repeatable. Run with:
##   Godot --headless --path godot_project res://tests/character_select_nav_check.tscn --quit-after 20

func _ready() -> void:
	var scene := load("res://scenes/CharacterSelect.tscn") as PackedScene
	var select := scene.instantiate() as CharacterSelectNode
	add_child(select)
	await get_tree().process_frame # let _ready()'s _refresh_labels() run

	var p1_start := select._p1_index
	var p1_after_d := await _tap(select, KEY_D, func(): return select._p1_index)
	print("PASS: P1's cursor moves on KEY_D (%d -> %d)" % [p1_start, p1_after_d] if p1_after_d != p1_start else "FAIL: P1's cursor did NOT move on KEY_D (stuck at %d)" % p1_start)

	var p1_after_s := await _tap(select, KEY_S, func(): return select._p1_index)
	print("PASS: P1's cursor moves on KEY_S (%d -> %d)" % [p1_after_d, p1_after_s] if p1_after_s != p1_after_d else "FAIL: P1's cursor did NOT move on KEY_S (stuck at %d)" % p1_after_d)

	var p2_start := select._p2_index
	var p2_after_right := await _tap(select, KEY_RIGHT, func(): return select._p2_index)
	print("PASS: P2's cursor moves on KEY_RIGHT (%d -> %d)" % [p2_start, p2_after_right] if p2_after_right != p2_start else "FAIL: P2's cursor did NOT move on KEY_RIGHT (stuck at %d)" % p2_start)

	var p2_after_down := await _tap(select, KEY_DOWN, func(): return select._p2_index)
	print("PASS: P2's cursor moves on KEY_DOWN (%d -> %d)" % [p2_after_right, p2_after_down] if p2_after_down != p2_after_right else "FAIL: P2's cursor did NOT move on KEY_DOWN (stuck at %d)" % p2_after_right)

	var all_ok := p1_after_d != p1_start and p1_after_s != p1_after_d and p2_after_right != p2_start and p2_after_down != p2_after_right
	get_tree().quit(0 if all_ok else 1)

## Presses physical_keycode, lets ONE process frame run (so the node's own
## edge-triggered "just pressed" check actually fires), releases it, then
## lets a second frame run so move_prev settles back to zero before the
## next simulated key — otherwise a still-held key from a previous tap
## would block the next edge from ever triggering.
func _tap(select: CharacterSelectNode, physical_keycode: int, read_index: Callable) -> int:
	var down := InputEventKey.new()
	down.physical_keycode = physical_keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame

	var up := InputEventKey.new()
	up.physical_keycode = physical_keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

	return read_index.call()
