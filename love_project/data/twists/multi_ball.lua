local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/multi_ball.tres. 2026-09-14: the
-- "spawn N-1 extra independent balls" mechanic is fully wired up in
-- match_arena.lua — see extra_balls there.
return twist_data.new({
	id = "multi_ball",
	display_name = "Double balle",
	twist_type = "multi_ball",
	ball_count = 2,
})
