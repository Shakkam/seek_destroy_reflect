local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/shrinking_arena.tres.
return twist_data.new({
	id = "shrinking_arena",
	display_name = "Zone qui retrecit",
	twist_type = "shrinking_arena",
	shrink_interval = 15.0,
	shrink_fraction = 0.1,
	shrink_animation_duration = 1.5,
})
