local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/laser.tres. `damage` is
-- reinterpreted as damage PER SECOND for a beam's duration (see
-- weapon_data.lua's own field comment) — 20 * TICK_INTERVAL(0.1) per tick,
-- 10 ticks/sec, nets exactly 20/sec.
return weapon_data.new({
	id = "laser",
	display_name = "Laser",
	damage = 20.0,
	fire_rate = 1.25, -- 0.8s cooldown between pulses
	gauge_max = 100.0,
	gauge_cost_per_shot = 28.0,
	is_heavy = true, -- triggers the shooter's own vulnerability window on fire (Story 1.8)
	effect_type = "beam",
	beam_range = 5000.0, -- comfortably larger than the arena — "traverse toute la map"
	beam_duration = 0.5,
	beam_thickness_multiplier = 1.0,
	-- Charged fire: a 3s pulse, 2x thick, with a self-slow while it's out.
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_beam_duration = 3.0,
	charged_beam_thickness_multiplier = 2.0,
	charged_beam_shooter_slow_multiplier = 0.6,
	-- Epic 4 passive reward (sweeping vertical laser wall).
	passive_interval = 26.0,
	passive_description = "Un mur laser vertical balaie le camp adverse au hasard toutes les 26s.",
})
