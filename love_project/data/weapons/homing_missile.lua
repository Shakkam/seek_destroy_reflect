local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/homing_missile.tres. Reuses two
-- mechanics this port already has (bazooka's vertical-only homing, and
-- Spreader's fan-burst spawn) — no new engine code needed for this
-- character, only its data.
return weapon_data.new({
	id = "homing_missile",
	display_name = "Missiles",
	damage = 3.0,
	fire_rate = 0.8,
	gauge_max = 100.0,
	gauge_cost_per_shot = 22.0,
	is_heavy = false,
	homing_strength = 1.6,
	projectile_count = 3,
	burst_spread_deg = 50.0,
	burst_stagger = 0.05,
	-- Charged fire: a 6-missile rafale.
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_projectile_count = 6,
	charged_burst_spread_deg = 50.0,
	charged_stagger = 0.12,
	charged_speed_multiplier = 1.15,
	-- Epic 4 passive reward (frequent single homing missile).
	passive_interval = 2.0,
	passive_description = "Un missile a tete chercheuse part tout seul toutes les 2s.",
})
