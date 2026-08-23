extends Node2D

## One-off scene-boot verification for the 2026-08-16 same-day AI fix
## (Camil, after actually playing against it: "elle rate tout le temps la
## balle (enfin souvent)"). The priority rework's ball_weight (0.85) plus
## a 0.15 wander blend on top left only ~72% real pull toward the ball
## even at full HP — nowhere near decisive enough. Confirms the AI-
## controlled ship's Y position actually CONVERGES close to a ball parked
## well within its reach (not just "the instantaneous direction sign is
## right once", which the existing ai_behavior_check.gd already covers)
## by driving REAL continuous _physics_process ticks, not direct method
## calls. Run with:
##   Godot --headless --path godot_project res://tests/ai_ball_tracking_check.tscn --quit-after 3000

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_2.ai_controlled = true
	arena._unfreeze_round()

	# Ball parked deep in ship_2's own half (side 1, right), far off in Y
	# from ship_2's starting position, stationary (no velocity) so this
	# isolates pure Y-tracking convergence from prediction/lookahead noise.
	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	# BallNode re-syncs its own .position FROM .state.position every physics
	# tick (see ball_node.gd) — setting the node property alone would get
	# silently overwritten on the very next frame, so both have to be set.
	var ball_target_pos := Vector2(bounds.position.x + bounds.size.x - 150.0, bounds.position.y + 60.0) # near the top of ship_2's own side
	arena.ball.position = ball_target_pos
	arena.ball.state.position = ball_target_pos
	arena.ball.state.velocity = Vector2.ZERO
	# Keep the opponent (ship_1) out of the way so aggression-blend noise
	# can't accidentally pull ship_2 toward a Y that happens to be close
	# to the ball's by coincidence.
	arena.ship_1.position = Vector2(bounds.position.x + 150.0, bounds.position.y + bounds.size.y - 60.0) # bottom of ship_1's own side, far from the ball's Y

	var start_distance := absf(arena.ship_2.position.y - arena.ball.position.y)
	for i in 120: # 4s at 30 ticks/sec — comfortably enough to close a few hundred px at SPEED=420px/s
		await get_tree().physics_frame
	var end_distance := absf(arena.ship_2.position.y - arena.ball.position.y)

	var converged_ok: bool = end_distance < 20.0 # well within paddle reach, not just "closer than before"
	print(("PASS: the AI actually converges onto the ball's Y (start dist %.0fpx -> end dist %.0fpx)" % [start_distance, end_distance]) if converged_ok else ("FAIL: the AI never closed in on the ball (start dist %.0fpx -> end dist %.0fpx)" % [start_distance, end_distance]))

	get_tree().quit(0 if converged_ok else 1)
