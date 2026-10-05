local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/ultra_pluie_de_bonbons.tres —
-- Spreader's Ultra: a much bigger burst than her base mini_shot.lua,
-- spread wide enough to saturate the arena top-to-bottom.
return weapon_data.new({
	id = "ultra_pluie_de_bonbons",
	display_name = "Pluie de Bonbons",
	damage = 6.0,
	projectile_count = 14,
	burst_spread_deg = 80.0,
	burst_stagger = 0.04,
	projectile_spin_speed = 900.0,
	visual_scale_multiplier = 1.4,
})
