extends Node2D

## One-off scene-boot verification for Story 4.5's MatchArenaNode.apply_twist()
## wiring — same rationale as round_end_check.gd (autoloads aren't available
## under the -s harness smoke_test.gd uses, and match_arena_node.gd depends
## on the MatchSetup autoload). Run with:
##   Godot --headless --path godot_project res://tests/twist_apply_check.tscn --quit-after 10

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var gauge_floor := TwistData.new()
	gauge_floor.twist_type = "gauge_floor"
	gauge_floor.passive_trickle_rate = 3.0
	arena.apply_twist(gauge_floor)

	var ok := arena.ship_1.self_fill_locked and arena.ship_2.self_fill_locked \
		and arena.ship_1.passive_trickle_rate == 3.0
	print("PASS: gauge_floor twist locks self-fill and sets trickle on both ships" if ok else "FAIL: gauge_floor twist did not wire correctly")

	var invis := TwistData.new()
	invis.twist_type = "invisible_opponent"
	arena.ship_2.ai_controlled = true
	arena.apply_twist(invis)
	var invis_ok := arena.ship_2.hidden_from_opponent and not arena.ship_1.hidden_from_opponent
	print("PASS: invisible_opponent twist hides only the AI-controlled ship" if invis_ok else "FAIL: invisible_opponent twist did not wire correctly")

	var decoy_twist := TwistData.new()
	decoy_twist.twist_type = "visual_decoy"
	decoy_twist.decoy_wander_speed = 200.0
	arena.apply_twist(decoy_twist)
	await get_tree().process_frame
	var decoy_ok := is_instance_valid(arena._decoy)
	print("PASS: visual_decoy twist spawns a DecoyNode" if decoy_ok else "FAIL: visual_decoy twist did not spawn a decoy")

	var multi_ball := TwistData.new()
	multi_ball.twist_type = "multi_ball"
	multi_ball.ball_count = 3
	arena.apply_twist(multi_ball)
	await get_tree().process_frame
	var multiball_ok := arena._extra_balls.size() == 2
	print("PASS: multi_ball twist (count=3) spawns 2 extra balls" if multiball_ok else "FAIL: multi_ball twist spawned %d extra balls, expected 2" % arena._extra_balls.size())

	get_tree().quit(0 if (ok and invis_ok and decoy_ok and multiball_ok) else 1)
