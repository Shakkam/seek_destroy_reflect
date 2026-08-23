extends Node2D

## One-off scene-boot verification for the 2026-08-16 same-day AI fix
## (Camil, after watching her miss ~10 returns in a row: "quand elle perd
## la balle, elle doit aller en fond de court. Si elle reste devant le
## filet, elle est quasi sure de la louper !"). A prior "healthy = hustle
## harder" tweak had widened the commit-to-frontier trigger up to 1.6x at
## full HP and pushed the resting depth toward the net near death — both
## backwards for a Pong derivative, where distance from the ball IS
## reaction time. Confirms: (1) with the ball far away (not "her
## problem"), an AI-controlled ship's X position settles near the BACK of
## its own half, not the frontier, at both full AND critical HP, (2) once
## the ball genuinely closes in, she still commits forward to meet it (the
## other half of the same behavior, so this fix didn't just delete the
## whole mechanic). Run with:
##   Godot --headless --path godot_project res://tests/ai_depth_positioning_check.tscn --quit-after 3000

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_2.ai_controlled = true
	arena._unfreeze_round()

	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	var back_x: float = bounds.position.x + bounds.size.x - arena.ship_2.half_extents.x # ship_2 is side 1 (right) — ITS back wall is the far right edge
	var frontier_x: float = arena.arena_origin.x + arena.arena_size.x / 2.0

	# --- (1) ball far away on the OPPONENT's side, at full HP: she should settle BACK, not camp the net ---
	# BallNode re-syncs its own .position FROM .state.position every
	# physics tick (see ball_node.gd) — setting the node property alone
	# gets silently overwritten on the very next frame, so both must be set.
	var far_ball_pos := Vector2(bounds.position.x + 100.0, bounds.position.y + bounds.size.y * 0.5) # deep in ship_1's own half, nowhere near ship_2
	arena.ball.position = far_ball_pos
	arena.ball.state.position = far_ball_pos
	arena.ball.state.velocity = Vector2.ZERO
	for i in 150: # 5s — comfortably enough to settle
		await get_tree().physics_frame
	var dist_to_back_full_hp := absf(arena.ship_2.position.x - back_x)
	var dist_to_frontier_full_hp := absf(arena.ship_2.position.x - frontier_x)
	var retreats_at_full_hp_ok: bool = dist_to_back_full_hp < dist_to_frontier_full_hp
	print(("PASS: at full HP, with the ball far away, she settles nearer her own back wall than the net (dist to back=%.0f, to net=%.0f)" % [dist_to_back_full_hp, dist_to_frontier_full_hp]) if retreats_at_full_hp_ok else ("FAIL: she settled nearer the net than her own back wall (dist to back=%.0f, to net=%.0f)" % [dist_to_back_full_hp, dist_to_frontier_full_hp]))

	# --- same check, near death — she shouldn't camp the net even then ---
	arena.ship_2.state = arena.ship_2.state.damaged(95.0)
	for i in 150:
		await get_tree().physics_frame
	var dist_to_back_critical := absf(arena.ship_2.position.x - back_x)
	var dist_to_frontier_critical := absf(arena.ship_2.position.x - frontier_x)
	var retreats_at_critical_hp_ok: bool = dist_to_back_critical < dist_to_frontier_critical
	print(("PASS: near death, with the ball far away, she STILL doesn't camp the net (dist to back=%.0f, to net=%.0f)" % [dist_to_back_critical, dist_to_frontier_critical]) if retreats_at_critical_hp_ok else ("FAIL: near death she camped the net (dist to back=%.0f, to net=%.0f)" % [dist_to_back_critical, dist_to_frontier_critical]))

	# --- (2) ball genuinely closing in: she still commits forward to meet it ---
	var close_ball_pos := Vector2(back_x - 40.0, arena.ship_2.position.y) # right on top of her, on her own side
	arena.ball.position = close_ball_pos
	arena.ball.state.position = close_ball_pos
	for i in 60: # 2s
		await get_tree().physics_frame
	var commits_forward_ok: bool = absf(arena.ship_2.position.x - frontier_x) < absf(arena.ship_2.position.x - back_x)
	print("PASS: once the ball genuinely closes in, she still commits toward the frontier to meet it" if commits_forward_ok else "FAIL: she didn't commit forward even with the ball right on top of her")

	var all_ok := retreats_at_full_hp_ok and retreats_at_critical_hp_ok and commits_forward_ok
	get_tree().quit(0 if all_ok else 1)
