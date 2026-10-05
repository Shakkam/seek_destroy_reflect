local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/stun_boomerang.tres ("Boomerang").
-- Despite the id/filename, effect_type stayed "damage" after an earlier
-- stun->damage rework (kept the id to avoid re-touching every reference).
return weapon_data.new({
	id = "stun_boomerang",
	display_name = "Boomerang",
	-- 2026-09-27 (Camil: "l'arme de Perturbateur ne fait pas assez de
	-- degats") — bumped x1.5 (was 1.5).
	damage = 1.5 * 1.5,
	fire_rate = 1.0,
	gauge_max = 100.0,
	gauge_cost_per_shot = 17.5,
	is_heavy = false,
	effect_type = "damage",
	is_boomerang = true,
	visual_scale_multiplier = 1.3,
	projectile_spin_speed = 720.0,
	projectile_count = 3,
	burst_spread_deg = 24.0,
	burst_stagger = 0.08,
	boomerang_out_duration = 2.0,
	-- Charged fire: a single giant 5x boomerang (5x size, 5x damage).
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_projectile_count = 1,
	charged_boomerang_out_duration = 2.0,
	charged_damage_multiplier = 5.0,
	charged_visual_scale_multiplier = 5.0,
	-- Epic 4 passive reward (Ultra control-scramble extension) — reactive,
	-- not periodic (see resolve_ultra_effect() in match_arena.lua, not
	-- update_passive_rewards()'s own timer loop).
	passive_interval = 0.0,
	passive_description = "Votre Ultra brouille aussi les commandes adverses, 5s en plus de son effet normal.",
})
