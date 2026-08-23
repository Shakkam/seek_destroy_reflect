extends Node2D

## One-off scene-boot verification for the 2026-08-16 same-day AI fix
## (Camil, after the ball-tracking-weight and net-camping fixes: "elle la
## rate encore beaucoup"). AI_LOOKAHEAD used to be a flat 0.15s nudge
## regardless of how far away or how fast the ball actually was — for a
## ball still the better part of a second out, that's a tiny correction
## on top of "where it is right now", not "where it will actually be
## when it arrives". Replaced with a real intercept estimate
## (_ai_ball_time_to_arrival(): distance / closing speed, capped at
## AI_MAX_LOOKAHEAD). Confirms: with the ball far away, moving fast, with
## real vertical drift, the ship's chosen direction matches the REAL
## predicted arrival Y, not the old flat-lookahead one — set up so the
## ship's current Y sits BETWEEN the two predictions, making them
## disagree on direction entirely (old lookahead says "up", real
## intercept says "down"). Also confirms the fallback: a ball moving AWAY
## from this ship doesn't get a wild long-range prediction. Run with:
##   Godot --headless --path godot_project res://tests/ai_intercept_prediction_check.tscn --quit-after 200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_2.ai_controlled = true # side 1 (right) — "toward my wall" means velocity.x > 0

	# Ball far out (dx=480 at vx=400 -> exactly 1.2s, AI_MAX_LOOKAHEAD's own
	# cap), drifting down HARD at vy=300. Real intercept prediction:
	# y=300 + 300*1.2 = 660. The OLD flat 0.15s lookahead would have
	# predicted y=300 + 300*0.15 = 345. Ship sits at y=400, BETWEEN the
	# two — old says "move up" (345 < 400), real intercept says "move
	# down" (660 > 400): the two predictions flatly disagree, with enough
	# margin either way to clear the hysteresis deadzone regardless of the
	# (small, at full HP) aggression/wander blend layered on top. Ship_1
	# (the "aggression" target) is pinned to the SAME Y as ship_2's own
	# start so that blend contributes zero net pull either way, isolating
	# this to the ball prediction specifically. Both ships' X are set
	# explicitly rather than left at scene defaults so the distances are
	# exact.
	arena.ship_2.position = Vector2(1180.0, 400.0)
	arena.ship_1.position = Vector2(200.0, 400.0)
	var ball_pos := Vector2(700.0, 300.0)
	arena.ball.position = ball_pos
	arena.ball.state.position = ball_pos # BallNode re-syncs .position FROM .state.position every physics tick — both must be set
	arena.ball.state.velocity = Vector2(400.0, 300.0)

	var time_to_arrival: float = arena.ship_2._ai_ball_time_to_arrival()
	var capped_correctly_ok: bool = is_equal_approx(time_to_arrival, ShipNode.AI_MAX_LOOKAHEAD)
	print(("PASS: time-to-arrival is correctly capped at AI_MAX_LOOKAHEAD for a fast, distant ball (%.2fs)" % time_to_arrival) if capped_correctly_ok else ("FAIL: time-to-arrival was %.2fs, expected the %.2fs cap" % [time_to_arrival, ShipNode.AI_MAX_LOOKAHEAD]))

	var dir: Vector2 = arena.ship_2._ai_read_input()
	var predicts_real_intercept_ok: bool = dir.y > 0.0 # "move down", toward y=420 — would be < 0.0 under the old flat 0.15s lookahead
	print(("PASS: the chosen direction matches the REAL intercept prediction, not the old flat-lookahead one (dir.y=%.2f)" % dir.y) if predicts_real_intercept_ok else ("FAIL: direction still matches the old short-sighted prediction (dir.y=%.2f)" % dir.y))

	# --- fallback: a ball moving AWAY from this ship shouldn't get a wild prediction ---
	arena.ball.state.velocity = Vector2(-400.0, 100.0) # now moving toward ship_1's wall, away from ship_2
	var time_away: float = arena.ship_2._ai_ball_time_to_arrival()
	var fallback_ok: bool = is_equal_approx(time_away, 0.15)
	print(("PASS: a ball moving away falls back to the short base nudge (%.2fs), no wild long-range guess" % time_away) if fallback_ok else ("FAIL: expected the 0.15s fallback for a receding ball, got %.2fs" % time_away))

	var all_ok := capped_correctly_ok and predicts_real_intercept_ok and fallback_ok
	get_tree().quit(0 if all_ok else 1)
