local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/vortex.tres ("Tourbillon").
return weapon_data.new({
	id = "vortex",
	display_name = "Tourbillon",
	damage = 3.0,
	fire_rate = 2.3,
	gauge_max = 100.0,
	gauge_cost_per_shot = 8.0,
	is_heavy = false,
	projectile_speed = 900.0,
	is_sine = true,
	sine_amplitude = 20.0,
	sine_angular_speed = 720.0, -- deg/sec
	-- Vif's own recoil kick: +60% move speed on fire, decaying linearly to
	-- 0 over 0.5s. Re-firing resets the window rather than stacking.
	fire_recoil_speed_boost = 0.6,
	fire_recoil_boost_decay_time = 0.5,
	-- Charged fire: a 3-shot staggered burst.
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_projectile_count = 3,
	charged_stagger = 0.1,
	-- Epic 4 passive reward (permanent +20% speed — see UT.PASSIVE_VIF_
	-- SPEED_MULTIPLIER/passive_state in match_arena.lua, not a periodic
	-- timer like the others since it's an always-on multiplier).
	passive_interval = 0.0,
	passive_description = "+20% de vitesse de deplacement, en permanence.",
})
