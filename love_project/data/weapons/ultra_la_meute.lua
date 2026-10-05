local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/ultra_la_meute.tres — Traqueur's
-- Ultra ("La Meute"): a bigger, more aggressively-homing missile burst than
-- her base homing_missile.lua. homing_full_turn (true 2D pursuit, letting a
-- missile turn all the way around instead of only steering vertically) is
-- NOT a WeaponData field — match_arena.lua's spawn_projectile() sets it the
-- same hardcoded, weapon-id-based way projectile_factory.gd does.
return weapon_data.new({
	id = "ultra_la_meute",
	display_name = "La Meute",
	damage = 3.0,
	homing_strength = 2.5,
	visual_scale_multiplier = 2.0,
	projectile_count = 8,
	burst_spread_deg = 130.0,
	burst_stagger = 0.1,
})
