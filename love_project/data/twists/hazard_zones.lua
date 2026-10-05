local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/hazard_zones.tres.
return twist_data.new({
	id = "hazard_zones",
	display_name = "Epines",
	twist_type = "hazard_zones",
	hazard_count = 2,
	hazard_radius = 24.0,
	hazard_spawn_interval = 8.0,
	hazard_lifetime = 6.0,
	hazard_stuns_ships = true,
	hazard_deflects_ball = true,
})
