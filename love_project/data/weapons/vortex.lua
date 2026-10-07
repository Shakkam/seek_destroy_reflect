local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/vortex.tres ("Tourbillon").
return weapon_data.new({
	id = "vortex",
	display_name = "Tourbillon",
	damage = 3.0,
	-- 2026-10-07 balance pass (Vif still weakest in the headless battery) —
	-- Camil: "tu peux legerement diminuer le cooldown entre 2 tirs (25%) et
	-- le cout d'un tir (-15%)". fire_rate is shots/s (cooldown = 1/fire_rate
	-- in weapon_system_state.lua), so a 25% SHORTER cooldown means fire_rate
	-- scaled up by 1/0.75.
	fire_rate = 2.3 / 0.75,
	gauge_max = 100.0,
	gauge_cost_per_shot = 8.0 * 0.85,
	is_heavy = false,
	projectile_speed = 900.0,
	is_sine = true,
	-- 2026-10-07 balance pass (headless data: Vif fires a lot but only lands
	-- ~20% of shots, by far the lowest hit-rate in the roster — the sine
	-- drift makes it easy to sidestep once the pattern reads) — Camil:
	-- "on peut augmenter un peu la sinusoide (+20%)" (was 20.0).
	sine_amplitude = 24.0,
	sine_angular_speed = 720.0, -- deg/sec
	-- 2026-10-07, same pass — Camil: "la vitesse peut augmenter avec la
	-- distance [...] si je tire du bord gauche, arrive au bord droit le tir
	-- a pris +50% de vitesse". Solved from v0=900 and the arena's own full
	-- width (ARENA_BOUNDS.size.x = 1200): constant acceleration along the
	-- shot's own travel direction such that v(t)=1.5*v0 exactly when the
	-- shot has covered that distance (v_f^2 = v0^2 + 2*a*D) — reuses the
	-- same generic `bullet.acceleration` mechanic Bourrasque's Ultra
	-- vortices already use (see update_bullets()'s is_sine branch and
	-- spawn_projectile()'s own read of this field).
	travel_acceleration = 421.875,
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
