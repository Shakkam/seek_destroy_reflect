local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/gauge_floor.tres.
return twist_data.new({
	id = "gauge_floor",
	display_name = "Jauge a plancher",
	twist_type = "gauge_floor",
	passive_trickle_rate = 3.0,
})
