local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/mini_shot.tres ("Éventail").
return weapon_data.new({
	id = "mini_shot",
	display_name = "Éventail",
	damage = 3.0,
	fire_rate = 1.0,
	gauge_max = 100.0,
	gauge_cost_per_shot = 14.0,
	is_heavy = false,
	spread_deg = 0.0,
	projectile_count = 5,
	burst_spread_deg = 35.0,
	burst_stagger = 0.0,
	visual_scale_multiplier = 1.4,
	projectile_spin_speed = 900.0,
	-- Charged fire: a wider ping-pong sweep (top-to-bottom then back).
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_projectile_count = 10,
	charged_burst_spread_deg = 60.0,
	charged_burst_ping_pong = true,
	charged_stagger = 0.125,
	-- Epic 4 passive reward (self-heal).
	passive_interval = 20.0,
	passive_description = "Un eventail tourne autour de vous et soigne 15% de vos PV, toutes les 20s.",
})
