extends Node2D

## One-off scene-boot verification for the Versus-mode post-match menu
## (2026-08-16 UX audit, Sally: "Versus mode ends in a dead screen" — a
## non-campaign match used to just sit on "Match termine..." forever, no
## rematch, no way back to character select). Confirms: (1) a non-campaign
## match end shows the result label and keeps ships/ball frozen, (2) after
## the short beat, a Revanche/Choix des personnages menu actually appears,
## (3) it's really navigable (Up/Down moves the selection marker). Doesn't
## exercise the actual change_scene_to_file() calls on confirm — same
## reasoning campaign_setup_check.gd documents for its own scene-change
## paths, it would replace this test's own scene tree mid-run. Run with:
##   Godot --headless --path godot_project res://tests/versus_post_match_check.tscn --quit-after 3000

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	# Force the match straight to "one round left" (1-0), then finish it —
	# faster and more direct than actually playing out two rounds.
	arena.match_state = arena.match_state.round_won_by(0) # ship_1 already up 1-0
	arena._unfreeze_round() # skip the ready gate — irrelevant to what's under test here
	arena.ship_2.state = arena.ship_2.state.damaged(1000.0) # ship_2 to 0 HP -> ship_1 wins round 2 -> match over (2-0)
	arena._check_round_end()

	var match_over_ok: bool = arena.match_state.match_over and arena.match_label.text.begins_with("Match termine")
	print(("PASS: a non-campaign match end shows the result label ('%s')" % arena.match_label.text) if match_over_ok else ("FAIL: match didn't resolve as expected ('%s')" % arena.match_label.text))

	var frozen_ok: bool = not arena.ship_1.active and not arena.ship_2.active and not arena.ball.active
	print("PASS: ships/ball stay frozen at match end" if frozen_ok else "FAIL: ships/ball weren't frozen at match end")

	var not_shown_yet_ok: bool = not arena._post_match_choice_active
	print("PASS: the post-match menu doesn't appear instantly (lets the result read first)" if not_shown_yet_ok else "FAIL: the menu appeared before its beat elapsed")

	# _show_post_match_choice() awaits a 1.2s beat before showing the menu
	# — wait it out (36 ticks at 30/sec + margin).
	for i in 40:
		await get_tree().physics_frame

	var menu_shown_ok: bool = arena._post_match_choice_active and arena.post_match_label.text.contains("Revanche") and arena.post_match_label.text.contains("Choix des personnages")
	print(("PASS: the post-match menu appears after the beat ('%s')" % arena.post_match_label.text.replace("\n", " / ")) if menu_shown_ok else ("FAIL: post-match menu never appeared ('%s')" % arena.post_match_label.text))
	var default_selection_ok: bool = arena._post_match_choice_index == 0 and arena.post_match_label.text.begins_with("> Revanche")
	print("PASS: Revanche is the default selection" if default_selection_ok else "FAIL: default selection was wrong ('%s')" % arena.post_match_label.text)

	# Navigate down once (Revanche -> Choix des personnages).
	_tap_key(KEY_DOWN)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nav_ok: bool = arena._post_match_choice_index == 1 and arena.post_match_label.text.contains("> Choix des personnages")
	print(("PASS: Down navigates to 'Choix des personnages' ('%s')" % arena.post_match_label.text.replace("\n", " / ")) if nav_ok else ("FAIL: navigation didn't move the selection (index=%d, '%s')" % [arena._post_match_choice_index, arena.post_match_label.text]))

	var all_ok := match_over_ok and frozen_ok and not_shown_yet_ok and menu_shown_ok and default_selection_ok and nav_ok
	get_tree().quit(0 if all_ok else 1)

func _tap_key(physical_keycode: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = physical_keycode
	down.pressed = true
	Input.parse_input_event(down)
