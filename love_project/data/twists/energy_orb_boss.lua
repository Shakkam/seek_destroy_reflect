local twist_data = require("simulation.twist_data")

-- Ported from godot_project/data/twists/energy_orb_boss.tres — the
-- organizer's own signature mechanic.
return twist_data.new({
	id = "energy_orb_boss",
	display_name = "Billes d'energie",
	twist_type = "energy_orb_pickup",
	orb_gauge_bonus_percent = 20.0,
	orb_spawn_interval = 10.0,
})
