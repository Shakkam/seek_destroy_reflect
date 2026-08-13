extends Node2D

## One-off scene-boot verification for the "Ready...Go!" pass (Sally's
## 2026-08-11 UX review: MatchArena had zero pacing between "waiting" and
## "live"; 2026-08-13 follow-up, Camil: "on a bien le 'go!' mais pas
## 'Ready...... go !'. Donc y'a bien 2 steps. Ready (1.5 secondes) Go !
## 1 sec" — a real two-phase beat, not a single flash). Confirms: (1)
## round 1 gates on a Fire press, then runs "Ready......" for
## READY_FLASH_DURATION, THEN "GO !" for GO_FLASH_DURATION, before
## unfreezing, and (2) round 2/3 — which previously got NO gate at all,
## not even round 1's original single press-to-start — re-freeze and
## re-run the same two-phase beat too. Simulates real keyboard input
## (Input.parse_input_event) and uses get_tree().physics_frame for
## precise tick counting instead of a real wall-clock SceneTreeTimer (see
## vif_recoil_check.gd — more reliable, and avoids needing a huge
## --quit-after for headless frames that run far faster than realtime).
## Run with:
##   Godot --headless --path godot_project res://tests/ready_gate_check.tscn --quit-after 400

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var frozen_at_start: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active and not arena._round_playing
	print("PASS: round 1 starts frozen, waiting on the ready gate" if frozen_at_start else "FAIL: round 1 didn't start frozen")
	var round1_label_ok: bool = arena.ready_label.text.begins_with("Round 1")
	print("PASS: round 1's ready label reads 'Round 1...'" if round1_label_ok else "FAIL: round 1 label was '%s'" % arena.ready_label.text)

	# Press Tir (Space) and hold it for one physics tick — matches the
	# "press, await a tick while still held, then release" pattern
	# vif_recoil_check.gd established; releasing before a tick ever sees
	# it pressed means the edge never registers.
	_hold_key(KEY_SPACE, true)
	await get_tree().physics_frame
	_hold_key(KEY_SPACE, false)
	await get_tree().physics_frame # let the release register

	var ready_phase_ok: bool = arena._round_start_phase == MatchArenaNode.RoundStartPhase.READY_FLASH and not arena._round_playing and arena.ready_label.text == "Ready......"
	print("PASS: confirming enters the 'Ready......' phase first (not straight to GO!)" if ready_phase_ok else "FAIL: expected the Ready phase, got phase=%s round_playing=%s label='%s'" % [arena._round_start_phase, arena._round_playing, arena.ready_label.text])

	# Wait out READY_FLASH_DURATION (30 ticks/sec per project.godot) + margin.
	var ready_ticks := int(ceil(MatchArenaNode.READY_FLASH_DURATION * 30.0)) + 3
	for i in ready_ticks:
		await get_tree().physics_frame
	var go_phase_ok: bool = arena._round_start_phase == MatchArenaNode.RoundStartPhase.GO_FLASH and not arena._round_playing and arena.ready_label.text == "GO !"
	print("PASS: the Ready phase elapses into a distinct 'GO !' phase" if go_phase_ok else "FAIL: expected the GO phase after %.1fs, got phase=%s label='%s'" % [MatchArenaNode.READY_FLASH_DURATION, arena._round_start_phase, arena.ready_label.text])

	# Wait out GO_FLASH_DURATION + margin.
	var go_ticks := int(ceil(MatchArenaNode.GO_FLASH_DURATION * 30.0)) + 3
	for i in go_ticks:
		await get_tree().physics_frame
	var unfrozen: bool = arena._round_playing and arena.ship_1.active and arena.ship_2.active and arena.ball.active
	print("PASS: ships/ball actually unfreeze once the GO phase elapses" if unfrozen else "FAIL: still frozen after the full Ready+GO sequence")

	# --- Round 2: force a non-match-ending round win, verify the SAME two-phase gate fires again ---
	arena.ship_2.state = arena.ship_2.state.damaged(1000.0) # ship_2 to 0 HP -> ship_1 wins round 1 (1-0, not match over)
	arena._check_round_end()
	var round2_frozen: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active and not arena._round_playing
	print("PASS: round 2 re-freezes and re-shows the ready gate (used to have NONE at all)" if round2_frozen else "FAIL: round 2 started unfrozen, no gate")
	var round2_label_ok: bool = arena.ready_label.text.begins_with("Round 2")
	print("PASS: round 2's ready label reads 'Round 2...'" if round2_label_ok else "FAIL: round 2 label was '%s'" % arena.ready_label.text)

	var all_ok := frozen_at_start and round1_label_ok and ready_phase_ok and go_phase_ok and unfrozen and round2_frozen and round2_label_ok
	get_tree().quit(0 if all_ok else 1)

func _hold_key(physical_keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
