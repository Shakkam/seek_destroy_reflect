local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/turret.tres.
return weapon_data.new({
	id = "turret",
	display_name = "Tourelle",
	damage = 3.0,
	fire_rate = 1.5,
	gauge_max = 100.0,
	gauge_cost_per_shot = 40.0,
	is_heavy = false,
	effect_type = "turret",
	turret_hp = 11.0,
	turret_lifetime = 18.75,
	-- Charged fire: an ephemeral turret that fires 4x faster but only
	-- lasts 5s.
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_turret_fire_rate_multiplier = 4.0,
	charged_turret_lifetime = 5.0,
	-- Epic 4 passive reward (satellite turret).
	passive_interval = 20.0,
	passive_description = "Une tourelle satellite apparait et tire toute seule 8s, toutes les 20s.",
})
