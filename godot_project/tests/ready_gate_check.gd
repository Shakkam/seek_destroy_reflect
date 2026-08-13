extends Node2D

## One-off scene-boot verification for the 2026-08-13 "Ready...Go!" pass
## (Sally's 2026-08-11 UX review: MatchArena had zero pacing between
## "waiting" and "live"). Confirms both halves of the fix: (1) round 1
## still gates on a Fire press before a brief "GO !" flash unfreezes
## everything, and (2) round 2/3 — which previously got NO gate at all,
## not even round 1's original single press-to-start — now re-freeze and
## re-show the gate too. Simulates real keyboard input the same way
## tests/character_select_nav_check.gd does (Input.parse_input_event with
## physical_keycode set). Waits out a real GO_FLASH_DURATION-based
## SceneTreeTimer, so needs a much bigger --quit-after than a typical
## single-frame check (headless frames run far faster than realtime, so
## accumulating ~0.7s of process delta takes hundreds of frames, not a
## handful — see project memory's "--quit-after counts FRAMES" trap).
## Run with:
##   Godot --headless --path godot_project res://tests/ready_gate_check.tscn --quit-after 600

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var frozen_at_start: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active and not arena._round_playing
	print("PASS: round 1 starts frozen, waiting on the ready gate" if frozen_at_start else "FAIL: round 1 didn't start frozen")
	var round1_label_ok: bool = arena.ready_label.text.begins_with("Round 1")
	print("PASS: round 1's ready label reads 'Round 1...'" if round1_label_ok else "FAIL: round 1 label was '%s'" % arena.ready_label.text)

	# Press Tir (Space) and hold it for one frame — matches the "press,
	# await a frame while still held, then release" pattern
	# character_select_nav_check.gd already established; releasing before
	# a frame ever sees it pressed means the edge never registers.
	var down := InputEventKey.new()
	down.physical_keycode = KEY_SPACE
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

	var flashing: bool = arena._starting_round and not arena._round_playing and arena.ready_label.text == "GO !"
	print("PASS: confirming shows the 'GO !' flash before unfreezing" if flashing else "FAIL: expected a GO flash, got starting_round=%s round_playing=%s label='%s'" % [arena._starting_round, arena._round_playing, arena.ready_label.text])

	await get_tree().create_timer(MatchArenaNode.GO_FLASH_DURATION + 0.1).timeout
	await get_tree().process_frame
	var unfrozen: bool = arena._round_playing and arena.ship_1.active and arena.ship_2.active and arena.ball.active
	print("PASS: ships/ball actually unfreeze once the GO flash elapses" if unfrozen else "FAIL: still frozen after the flash duration")

	# --- Round 2: force a non-match-ending round win, verify the SAME gate fires again ---
	arena.ship_2.state = arena.ship_2.state.damaged(1000.0) # ship_2 to 0 HP -> ship_1 wins round 1 (1-0, not match over)
	arena._check_round_end()
	var round2_frozen: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active and not arena._round_playing
	print("PASS: round 2 re-freezes and re-shows the ready gate (used to have NONE at all)" if round2_frozen else "FAIL: round 2 started unfrozen, no gate")
	var round2_label_ok: bool = arena.ready_label.text.begins_with("Round 2")
	print("PASS: round 2's ready label reads 'Round 2...'" if round2_label_ok else "FAIL: round 2 label was '%s'" % arena.ready_label.text)

	var all_ok := frozen_at_start and round1_label_ok and flashing and unfrozen and round2_frozen and round2_label_ok
	get_tree().quit(0 if all_ok else 1)
