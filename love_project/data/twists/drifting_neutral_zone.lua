local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/drifting_neutral_zone.tres.
return twist_data.new({
	id = "drifting_neutral_zone",
	display_name = "Zone neutre mobile",
	twist_type = "drifting_neutral_zone",
	drift_speed = 40.0,
	drift_range = 120.0,
})
