local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/visual_decoy.tres ("Double moi").
return twist_data.new({
	id = "visual_decoy",
	display_name = "Double moi",
	twist_type = "visual_decoy",
	decoy_wander_speed = 180.0,
})
